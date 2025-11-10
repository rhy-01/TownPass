from fastapi import FastAPI, HTTPException, Query, Request
from pydantic import BaseModel
from typing import Optional, List, Dict, Any, Tuple
from google.cloud import firestore
from datetime import datetime, timezone
import requests
import google.auth
from google.auth.transport.requests import Request as AuthRequest
from concurrent.futures import ThreadPoolExecutor, as_completed

app = FastAPI()
db = firestore.Client()

# 視為「安全」的檢查結果
SAFE_STATUSES = {"合格", "複查合格"}


# ---------- 共用小工具 ----------

def get_inspection_status(doc_dict: dict) -> Optional[str]:
    """
    Firestore 結構可能有兩種：
    1) InspectionResults: "合格"
    2) InspectionResults: { "status": "合格", ... }
    統一回傳狀態字串或 None。
    """
    raw = doc_dict.get("InspectionResults")
    if raw is None:
        return None
    if isinstance(raw, dict):
        return raw.get("status")
    return raw


def should_alert(status: Optional[str]) -> bool:
    """
    true 代表「有風險，需要 alert / 通知」。
      - status 是 合格 / 複查合格 / None -> 不 alert
      - 其他文字 (例如: 限期改善、複查不合格...) -> alert
    """
    if status is None:
        return False
    return status not in SAFE_STATUSES


# ---------- FCM 通知相關函數 ----------

def get_access_token() -> Optional[str]:
    """
    獲取 Google OAuth 2.0 access token 用於 FCM API
    """
    try:
        credentials, project = google.auth.default()
        credentials.refresh(AuthRequest())
        return credentials.token
    except Exception as e:
        print(f"❌ 獲取 access token 失敗: {e}")
        return None


def get_all_fcm_tokens() -> List[dict]:
    """
    從 Firestore users collection 獲取所有 FCM tokens
    返回格式: [{"userId": "xxx", "tokens": ["token1", "token2"]}, ...]
    """
    user_tokens = []
    try:
        users_ref = db.collection("users")
        docs = users_ref.stream()
        
        for doc in docs:
            user_id = doc.id
            user_data = doc.to_dict()
            tokens = []
            
            # 從 devices 陣列中讀取 fcmToken
            if user_data.get("devices") and isinstance(user_data["devices"], list):
                for device in user_data["devices"]:
                    if device and device.get("fcmToken"):
                        tokens.append(device["fcmToken"])
            
            # 向後兼容：如果文件根部也有 fcmToken（舊格式），也加入
            if user_data.get("fcmToken"):
                if user_data["fcmToken"] not in tokens:
                    tokens.append(user_data["fcmToken"])
            
            if tokens:
                user_tokens.append({
                    "userId": user_id,
                    "tokens": tokens
                })
        
        total_tokens = sum(len(ut["tokens"]) for ut in user_tokens)
        print(f"✅ 找到 {len(user_tokens)} 個用戶，共 {total_tokens} 個 FCM Tokens")
        return user_tokens
    except Exception as e:
        print(f"❌ 獲取 FCM Tokens 失敗: {e}")
        return []


def send_invoice_fcm_to_token(token: str, access_token: str, seller_name: str, 
                              invoice_date: str, seller_tin: str, alert: int, 
                              title: str, latitude: Optional[float] = None, 
                              longitude: Optional[float] = None, 
                              status: Optional[str] = None) -> Tuple[bool, Optional[str]]:
    """
    發送發票相關的 FCM 消息到單個 token
    同時使用 notification 和 data 字段（notification 用於系統顯示，data 用於應用處理）
    返回: (成功與否, 錯誤訊息)
    """
    FCM_API_URL = "https://fcm.googleapis.com/v1/projects/micro-service-477116/messages:send"
    
    # 構建通知內容
    notification_body = f"發票日期：{invoice_date}，賣方：{seller_name}"
    
    # FCM data 欄位（應用可以處理的自定義數據）
    fcm_data = {
        "msgtyp": "invoice",
        "seller_name": seller_name,
        "invoice_date": invoice_date,
        "seller_tin": seller_tin,
        "alert": str(alert),
        "title": title,
        "body": notification_body,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    
    # 如果有座標和狀態，也加入
    if latitude is not None:
        fcm_data["latitude"] = str(latitude)
    if longitude is not None:
        fcm_data["longitude"] = str(longitude)
    if status is not None:
        fcm_data["status"] = status
    
    # 構建 FCM 消息 - 同時包含 notification 和 data 字段
    message = {
        "message": {
            "token": token,
            "notification": {
                "title": title,
                "body": notification_body,
            },
            "data": {k: str(v) for k, v in fcm_data.items()},
            "android": {
                "priority": "high",
                "notification": {
                    "channelId": "default",
                    "sound": "default",
                    "clickAction": "FLUTTER_NOTIFICATION_CLICK",
                }
            },
            "apns": {
                "payload": {
                    "aps": {
                        "sound": "default",
                        "badge": 1,
                    }
                }
            }
        }
    }
    
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    
    try:
        response = requests.post(FCM_API_URL, json=message, headers=headers, timeout=10)
        response.raise_for_status()
        return True, None
    except requests.exceptions.HTTPError as e:
        error_msg = f"HTTP {response.status_code}: {response.text}"
        return False, error_msg
    except Exception as e:
        error_msg = str(e)
        return False, error_msg


def send_invoice_fcm_notification(seller_name: str, invoice_date: str, seller_tin: str, 
                                  alert: int, title: str, latitude: Optional[float] = None,
                                  longitude: Optional[float] = None, 
                                  status: Optional[str] = None) -> Dict[str, Any]:
    """
    發送發票相關的 FCM 消息到所有設備
    返回統計信息字典
    """
    print("=" * 50)
    print(f"📤 開始發送發票 FCM 推播: {seller_name} ({seller_tin})")
    print("=" * 50)
    
    # 1. 獲取 access token
    access_token = get_access_token()
    if not access_token:
        error_msg = "無法獲取 access token"
        print(f"❌ {error_msg}，跳過 FCM 發送")
        return {
            "success": False,
            "error": error_msg,
            "total_users": 0,
            "total_tokens": 0,
            "success_count": 0,
            "failure_count": 0
        }
    
    # 2. 獲取所有 FCM tokens
    user_tokens = get_all_fcm_tokens()
    if not user_tokens:
        error_msg = "沒有找到任何 FCM tokens"
        print(f"⚠️  {error_msg}，跳過發送")
        return {
            "success": False,
            "error": error_msg,
            "total_users": 0,
            "total_tokens": 0,
            "success_count": 0,
            "failure_count": 0
        }
    
    all_tokens = []
    for ut in user_tokens:
        all_tokens.extend(ut["tokens"])
    
    print(f"📱 準備發送給 {len(all_tokens)} 個設備")
    print(f"👥 用戶數量: {len(user_tokens)}")
    print("")
    
    # 3. 分批發送 FCM 消息（每批最多 500 個）
    MAX_TOKENS_PER_BATCH = 500
    total_success_count = 0
    total_failure_count = 0
    failed_tokens = []
    
    # 如果 token 數量超過限制，分批發送
    if len(all_tokens) > MAX_TOKENS_PER_BATCH:
        print(f"⚠️  Token 數量 ({len(all_tokens)}) 超過限制 ({MAX_TOKENS_PER_BATCH})，將分批發送...")
        print("")
    
    # 分批處理
    for i in range(0, len(all_tokens), MAX_TOKENS_PER_BATCH):
        batch_tokens = all_tokens[i:i + MAX_TOKENS_PER_BATCH]
        batch_number = (i // MAX_TOKENS_PER_BATCH) + 1
        total_batches = (len(all_tokens) + MAX_TOKENS_PER_BATCH - 1) // MAX_TOKENS_PER_BATCH
        
        print(f"📦 發送批次 {batch_number}/{total_batches} ({len(batch_tokens)} 個設備)...")
        
        # 並發發送當前批次
        batch_success = 0
        batch_failure = 0
        max_workers = 10  # 並發數量
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(send_invoice_fcm_to_token, token, access_token, seller_name,
                              invoice_date, seller_tin, alert, title, latitude, longitude, status): token
                for token in batch_tokens
            }
            
            for future in as_completed(futures):
                token = futures[future]
                try:
                    success, error_msg = future.result()
                    if success:
                        batch_success += 1
                    else:
                        batch_failure += 1
                        failed_tokens.append({
                            "token": token[:50] + "..." if len(token) > 50 else token,
                            "error": error_msg
                        })
                        # 記錄失敗的 token（僅前 10 個）
                        if len(failed_tokens) <= 10:
                            print(f"   ❌ Token {token[:50]}... 發送失敗: {error_msg}")
                except Exception as e:
                    batch_failure += 1
                    failed_tokens.append({
                        "token": token[:50] + "..." if len(token) > 50 else token,
                        "error": str(e)
                    })
                    print(f"   ❌ Token {token[:50]}... 發生異常: {e}")
        
        total_success_count += batch_success
        total_failure_count += batch_failure
        print(f"   ✅ 成功: {batch_success}, ❌ 失敗: {batch_failure}")
        print("")
    
    # 4. 輸出最終統計
    print("=" * 50)
    print(f"📊 FCM 發送完成")
    print(f"   ✅ 成功: {total_success_count}")
    print(f"   ❌ 失敗: {total_failure_count}")
    print(f"   📱 總設備數: {len(all_tokens)}")
    print("=" * 50)
    print("")
    
    return {
        "success": total_failure_count == 0,
        "total_users": len(user_tokens),
        "total_tokens": len(all_tokens),
        "success_count": total_success_count,
        "failure_count": total_failure_count,
        "failed_tokens": failed_tokens[:10]  # 只返回前 10 個失敗的 token
    }


# ---------- 回傳資料的 Pydantic model ----------

class UnsafeLocation(BaseModel):
    registrationNumber: str
    businessName: Optional[str]
    latitude: float
    longitude: float
    inspectionStatus: Optional[str]
    inspectionDate: Optional[str]
    address: Optional[str]


class NightMarketLocation(BaseModel):
    registrationNumber: str
    latitude: float
    longitude: float
    evaluationResult: Optional[str]
    nightMarketName: Optional[str]
    stallName: Optional[str]
    inspectionStatus: Optional[str]
    inspectionDate: Optional[str]
    address: Optional[str]


class InvoiceIn(BaseModel):
    invoiceDate: str      # 發票日期
    sellerTin: str        # 賣方統編
    sellerName: str       # 賣方名稱


class InvoiceOut(BaseModel):
    invoiceDate: str
    sellerTin: str
    sellerName: str
    alert: int                # 0=安全, 1=有風險/不明
    latitude: Optional[float]
    longitude: Optional[float]
    inspectionStatus: Optional[str]
    addr: Optional[str]


# =====================================================
# 1) 取得「不合格」店家的座標
# =====================================================
@app.get("/locations/unsafe", response_model=List[UnsafeLocation])
async def get_unsafe_locations():
    query = db.collection("foodByReg").where("InspectionResults", "!=", None)
    docs = query.stream()

    results: List[UnsafeLocation] = []

    for doc in docs:
        d = doc.to_dict()
        status = get_inspection_status(d)

        # 用統一的規則判斷：不需要 alert 的全部跳過
        if not should_alert(status):
            continue

        lat = d.get("latitude")
        lon = d.get("longitude")
        if lat is None or lon is None:
            continue

        # 先看 InspectionResults map，有的話用裡面的 date/address
        insp = d.get("InspectionResults") or {}
        insp_date = None
        insp_addr = None

        if isinstance(insp, dict):
            insp_date = insp.get("date")
            insp_addr = insp.get("address")

        # 沒有就退回頂層欄位
        if insp_date is None:
            insp_date = d.get("InspectionDate")
        if insp_addr is None:
            insp_addr = d.get("address")

        results.append(
            UnsafeLocation(
                registrationNumber=d.get("registrationNumber") or doc.id,
                businessName=d.get("businessName"),
                latitude=lat,
                longitude=lon,
                inspectionStatus=status,
                inspectionDate=insp_date,
                address=insp_addr,
            )
        )

    return results


# =====================================================
# 2) 查某個夜市的「不合格」攤位
#    只回 InspectionResults 需要 alert 的那些
# =====================================================
@app.get("/night-market", response_model=List[NightMarketLocation])
async def get_night_market_locations(
    name: str = Query(..., description="夜市名稱，例如：公館夜市")
):
    query = (
        db.collection("foodByReg")
        .where("nightMarketName", "==", name)
    )
    docs = query.stream()

    results: List[NightMarketLocation] = []

    for doc in docs:
        d = doc.to_dict()
        if d.get("nightMarketName") is None:
            continue

        # 檢查結果只要「不需要 alert」就跳過
        status = get_inspection_status(d)
        if not should_alert(status):
            continue

        lat = d.get("latitude")
        lon = d.get("longitude")
        if lat is None or lon is None:
            continue

        # 先試著從 InspectionResults map 拿日期 / 地址
        insp = d.get("InspectionResults") or {}
        insp_date = None
        insp_addr = None

        if isinstance(insp, dict):
            insp_date = insp.get("date")
            insp_addr = insp.get("address")

        # 再退回頂層欄位
        if insp_date is None:
            insp_date = d.get("InspectionDate")
        if insp_addr is None:
            insp_addr = d.get("address")

        info = d.get("nightMarketInfo") or {}

        results.append(
            NightMarketLocation(
                registrationNumber=d.get("registrationNumber") or doc.id,
                latitude=lat,
                longitude=lon,
                evaluationResult=info.get("evaluationResult"),
                nightMarketName=d.get("nightMarketName"),
                stallName=info.get("stallName"),
                inspectionStatus=status,
                inspectionDate=insp_date,
                address=insp_addr,
            )
        )

    return results


# =====================================================
# 3) 發票檢查 API（同統編多筆都檢查，並回傳地址）
#    alert 也用 should_alert() 的統一邏輯
# =====================================================
@app.post("/invoice/check", response_model=InvoiceOut)
async def check_invoice(invoice: InvoiceIn):
    tin = invoice.sellerTin

    docs_iter = (
        db.collection("foodByReg")
        .where("tin", "==", tin)
        .stream()
    )

    found_any = False
    # (status, lat, lon, addr)
    non_null_statuses: List[tuple[str, Optional[float], Optional[float], Optional[str]]] = []
    any_lat: Optional[float] = None
    any_lon: Optional[float] = None
    any_addr: Optional[str] = None

    for doc in docs_iter:
        found_any = True
        d = doc.to_dict()

        status_i = get_inspection_status(d)
        lat_i = d.get("latitude")
        lon_i = d.get("longitude")
        addr_i = d.get("address")

        # 記一個備用座標 / 地址
        if any_lat is None and lat_i is not None and lon_i is not None:
            any_lat = lat_i
            any_lon = lon_i
        if any_addr is None and addr_i:
            any_addr = addr_i

        if status_i is not None:
            non_null_statuses.append((status_i, lat_i, lon_i, addr_i))

    # 預設：有風險
    alert = 1
    final_status: Optional[str] = None
    lat_out: Optional[float] = None
    lon_out: Optional[float] = None
    addr_out: Optional[str] = None

    if not found_any:
        # Firestore 完全沒有這個統編
        alert = 1
        final_status = None
        addr_out = None
        # 沒有找到統編也視為有風險，發送通知
        try:
            title = f'您曾經於未知餐廳：{invoice.sellerName} 消費過，請注意食品安全。'
            send_invoice_fcm_notification(
                seller_name=invoice.sellerName,
                invoice_date=invoice.invoiceDate,
                seller_tin=invoice.sellerTin,
                alert=alert,
                title=title,
                latitude=None,
                longitude=None,
                status=None
            )
        except Exception as e:
            print(f"⚠️  發送 FCM 通知失敗: {e}")
    else:
        if non_null_statuses:
            # 有至少一筆非 None，就拿第一筆當代表（之後如果要選「最嚴重」再另外加規則）
            final_status, lat_candidate, lon_candidate, addr_candidate = non_null_statuses[0]
            lat_out = lat_candidate
            lon_out = lon_candidate
            addr_out = addr_candidate or any_addr
        else:
            # 全部都是 None
            final_status = None
            addr_out = any_addr
            # 使用備用座標
            if any_lat is not None and any_lon is not None:
                lat_out = any_lat
                lon_out = any_lon

        # 用統一規則決定 alert，如果 should_alert 為 True 就直接發送通知
        if should_alert(final_status):
            # 有風險：直接發送 FCM 通知
            alert = 1
            title = f'您曾經於稽查不合格的餐廳：{invoice.sellerName} 消費過，請注意食品安全。'
            
            # 發送 FCM 通知
            try:
                send_invoice_fcm_notification(
                    seller_name=invoice.sellerName,
                    invoice_date=invoice.invoiceDate,
                    seller_tin=invoice.sellerTin,
                    alert=alert,
                    title=title,
                    latitude=lat_out,
                    longitude=lon_out,
                    status=final_status
                )
            except Exception as e:
                print(f"⚠️  發送 FCM 通知失敗: {e}")
        else:
            # 安全（合格 / 複查合格 / 或 status=None）
            alert = 0
            # 地址可以留給前端顯示，所以不清掉 addr_out

    return InvoiceOut(
        invoiceDate=invoice.invoiceDate,
        sellerTin=invoice.sellerTin,
        sellerName=invoice.sellerName,
        alert=alert,
        latitude=lat_out,
        longitude=lon_out,
        inspectionStatus=final_status,
        addr=addr_out,
    )


# =====================================================
# 4) 測試路由：測試發票 FCM 推播通知
# =====================================================
@app.post("/test-invoice-fcm")
async def test_invoice_fcm_notification(request: Request):
    """
    測試發票相關的 FCM 推播通知端點
    
    請求格式 (JSON):
    {
        "seller_name": "測試餐廳",
        "invoice_date": "2024-01-15",
        "seller_tin": "12345678",
        "alert": 1,
        "title": "您曾經於稽查不合格的餐廳：測試餐廳 消費過，請注意食品安全。",
        "latitude": 25.051898,
        "longitude": 121.5281835,
        "status": "不合格"
    }
    
    所有字段都是可選的，如果不提供會使用默認值。
    """
    try:
        body = await request.json()
        
        # 獲取參數，提供默認值
        seller_name = body.get("seller_name", "測試餐廳")
        invoice_date = body.get("invoice_date", datetime.now().strftime("%Y-%m-%d"))
        seller_tin = body.get("seller_tin", "TEST-12345")
        alert = body.get("alert", 1)
        title = body.get("title", f"您曾經於稽查不合格的餐廳：{seller_name} 消費過，請注意食品安全。")
        latitude = body.get("latitude", 25.051898)
        longitude = body.get("longitude", 121.5281835)
        status = body.get("status", "不合格")
        
        # 驗證必要參數
        if not seller_name:
            raise HTTPException(status_code=400, detail="seller_name is required")
        if not invoice_date:
            raise HTTPException(status_code=400, detail="invoice_date is required")
        if not seller_tin:
            raise HTTPException(status_code=400, detail="seller_tin is required")
        
        print("=" * 50)
        print("🧪 測試發票 FCM 推播通知")
        print("=" * 50)
        print(f"賣方名稱: {seller_name}")
        print(f"發票日期: {invoice_date}")
        print(f"賣方統編: {seller_tin}")
        print(f"警報狀態: {alert}")
        print(f"標題: {title}")
        print(f"經緯度: ({latitude}, {longitude})")
        print(f"狀態: {status}")
        print("")
        
        # 發送 FCM 推播並獲取統計信息
        result = send_invoice_fcm_notification(
            seller_name=seller_name,
            invoice_date=invoice_date,
            seller_tin=seller_tin,
            alert=int(alert),
            title=title,
            latitude=float(latitude) if latitude is not None else None,
            longitude=float(longitude) if longitude is not None else None,
            status=status if status else None
        )
        
        return {
            "success": result.get("success", True),
            "message": "Invoice FCM notification sent",
            "data": {
                "seller_name": seller_name,
                "invoice_date": invoice_date,
                "seller_tin": seller_tin,
                "alert": alert,
                "title": title,
                "latitude": latitude,
                "longitude": longitude,
                "status": status,
                "msgtyp": "invoice"
            },
            "result": {
                "total_users": result.get("total_users", 0),
                "total_tokens": result.get("total_tokens", 0),
                "success_count": result.get("success_count", 0),
                "failure_count": result.get("failure_count", 0)
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ 測試發票 FCM 推播失敗: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to send test invoice FCM notification: {str(e)}")


@app.get("/health")
async def health_check():
    """
    健康檢查端點
    """
    return {
        "status": "healthy",
        "service": "all-integrate-api",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


@app.get("/list-tokens")
async def list_all_tokens():
    """
    列出所有註冊的 FCM tokens
    """
    try:
        user_tokens = get_all_fcm_tokens()
        
        # 格式化輸出
        tokens_list = []
        for ut in user_tokens:
            tokens_list.append({
                "userId": ut["userId"],
                "tokenCount": len(ut["tokens"]),
                "tokens": ut["tokens"][:5] if len(ut["tokens"]) <= 5 else ut["tokens"][:5] + [f"... and {len(ut['tokens']) - 5} more"]
            })
        
        total_tokens = sum(len(ut["tokens"]) for ut in user_tokens)
        
        return {
            "success": True,
            "total_users": len(user_tokens),
            "total_tokens": total_tokens,
            "users": tokens_list
        }
    except Exception as e:
        print(f"❌ 列出 tokens 失敗: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to list tokens: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
