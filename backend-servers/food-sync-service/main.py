from fastapi import FastAPI, Request, HTTPException
from google.cloud import storage, firestore
from datetime import datetime, timezone
import time
import json
import base64
import os
import requests
from typing import Optional, Tuple, List, Dict, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import google.auth
from google.auth.transport.requests import Request as AuthRequest

app = FastAPI()

storage_client = storage.Client()
GEOCODING_API_KEY = os.environ.get("GEOCODING_API_KEY")
SAFE_INSPECTION_STATUSES = {"合格", "複查合格"}

db = firestore.Client()

# ---------------- 工具：讀取 GCS JSON（空檔回傳 default） ----------------
def read_gcs_json(bucket_name: str, object_name: str, default):
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    
    # 嘗試多種編碼方式讀取文件
    encodings = ["utf-8", "utf-8-sig", "big5", "gb2312", "gbk", "latin1"]
    text = None
    
    for encoding in encodings:
        try:
            text = blob.download_as_text(encoding=encoding).strip()
            break
        except UnicodeDecodeError:
            continue
        except Exception as e:
            print(f"⚠️ 讀取文件時發生錯誤 ({encoding}): {e}")
            continue
    
    # 如果所有編碼都失敗，使用 errors='replace' 強制讀取
    if text is None:
        try:
            text = blob.download_as_bytes().decode("utf-8", errors="replace").strip()
        except Exception as e:
            print(f"❌ 無法讀取文件 {object_name}: {e}")
            return default
    
    if text == "":
        return default
    
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"❌ JSON 解析失敗 ({object_name}): {e}")
        return default

def now_ts():
    now_iso = datetime.now(timezone.utc).isoformat()
    now_ms = int(time.time() * 1000)
    return now_iso, now_ms

def geocode_address(address: str) -> Optional[Tuple[float, float]]:
    """
    用 Google Geocoding API 把地址轉成 (lat, lng)
    回傳 None 代表查不到或出錯
    """
    if not address:
        return None

    if not GEOCODING_API_KEY:
        print("⚠️ GEOCODING_API_KEY 未設定，略過 geocoding")
        return None

    url = "https://maps.googleapis.com/maps/api/geocode/json"
    params = {
        "address": address,
        "key": GEOCODING_API_KEY,
        "language": "zh-TW",
    }

    try:
        resp = requests.get(url, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()

        if data.get("status") == "OK" and data.get("results"):
            loc = data["results"][0]["geometry"]["location"]
            return float(loc["lat"]), float(loc["lng"])
        else:
            print(f"⚠️ Geocoding 失敗: {address} status={data.get('status')}")
            return None
    except Exception as e:
        print(f"❌ Geocoding error ({address}): {e}")
        return None


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


def send_fcm_to_token(token: str, access_token: str, restaurant_name: str, reg_no: str, 
                      lat: float, lng: float, status: str) -> Tuple[bool, Optional[str]]:
    """
    發送 FCM 消息到單個 token
    返回: (成功與否, 錯誤訊息)
    """
    FCM_API_URL = "https://fcm.googleapis.com/v1/projects/micro-service-477116/messages:send"
    
    # 構建 FCM 消息
    # 確保 title 包含"不合格"，這樣應用才會顯示通知
    notification_title = f"餐廳 '{restaurant_name}' 稽查結果不合格"
    notification_body = f"餐廳 '{restaurant_name}' 稽查結果：{status}"
    
    # FCM data 欄位（應用可以處理的自定義數據）
    fcm_data = {
        "targetUrl": f"/restaurant/{reg_no}",
        "type": "inspection_failure",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "restaurant_name": restaurant_name,
        "restaurant_reg_no": reg_no,
        "restaurant_latitude": str(lat),
        "restaurant_longitude": str(lng),
        "restaurant_status": status,
        "title": notification_title,
        "body": notification_body,
    }
    
    # 構建 FCM 消息
    # 只有 title 包含"不合格"時才包含 notification 字段（讓系統自動顯示通知）
    message = {
        "message": {
            "token": token,
            "data": {k: str(v) for k, v in fcm_data.items()},
        }
    }
    
    # 檢查 title 是否包含"不合格"，如果包含則添加 notification 字段
    if "不合格" in notification_title:
        message["message"]["notification"] = {
            "title": notification_title,
            "body": notification_body,
        }
        message["message"]["android"] = {
            "priority": "high",
            "notification": {
                "channelId": "default",
                "sound": "default",
                "clickAction": "FLUTTER_NOTIFICATION_CLICK",
            }
        }
        message["message"]["apns"] = {
            "payload": {
                "aps": {
                    "sound": "default",
                    "badge": 1,
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


def send_fcm_to_all_devices(restaurant_name: str, reg_no: str, lat: float, lng: float, status: str) -> Dict[str, Any]:
    """
    發送 FCM 消息到所有設備（參考 Node.js 實現）
    包含詳細的錯誤處理和統計信息
    返回統計信息字典
    """
    print("=" * 50)
    print(f"📤 開始發送 FCM 推播: {restaurant_name} ({reg_no})")
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
    
    # 3. 分批發送 FCM 消息（參考 Node.js 實現，每批最多 500 個）
    MAX_TOKENS_PER_BATCH = 500
    total_success_count = 0
    total_failure_count = 0
    failed_tokens = []  # 記錄失敗的 token 和錯誤信息
    
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
                executor.submit(send_fcm_to_token, token, access_token, restaurant_name, 
                              reg_no, lat, lng, status): token 
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
        
        print(f"   批次 {batch_number} 結果: 成功 {batch_success}, 失敗 {batch_failure}")
        print("")
    
    # 5. 輸出統計信息
    print("=" * 50)
    print("📊 FCM 推播總計結果")
    print("=" * 50)
    print(f"✅ 成功: {total_success_count} 則")
    print(f"❌ 失敗: {total_failure_count} 則")
    print(f"📱 總 Token 數: {len(all_tokens)}")
    print(f"👥 用戶數量: {len(user_tokens)}")
    
    if failed_tokens:
        print(f"⚠️  失敗的 Token 數量: {len(failed_tokens)}")
        if len(failed_tokens) > 10:
            print(f"   （僅顯示前 10 個失敗的 Token）")
    print("=" * 50)
    
    # 返回統計信息
    return {
        "success": True,
        "total_users": len(user_tokens),
        "total_tokens": len(all_tokens),
        "success_count": total_success_count,
        "failure_count": total_failure_count,
        "failed_tokens_count": len(failed_tokens),
        "failed_tokens_sample": failed_tokens[:10] if failed_tokens else []
    }


def notify_app_about_inspection(reg_no: str, inspection_obj: dict, lat: float, lng: float):
    """
    發送 FCM 推播通知到所有設備
    """
    restaurant_name = inspection_obj.get("name", "未知餐廳")
    status = inspection_obj.get("status", "未知狀態")
    
    # 只有狀態不是"合格"或"複查合格"時才發送通知
    if status not in SAFE_INSPECTION_STATUSES:
        send_fcm_to_all_devices(restaurant_name, reg_no, lat, lng, status)
    else:
        print(f"ℹ️  餐廳 {restaurant_name} 狀態為 {status}，跳過推播")


# ---------------- 1) HygieneRating：全量重建 ----------------
def process_hygiene_rating(bucket: str, name: str):
    # 空檔就當作 {}
    data = read_gcs_json(bucket, name, default={})
    if not isinstance(data, dict):
        raise ValueError("HygieneRating JSON 應該是 { reg_no: rating }")

    now_iso, now_ms = now_ts()

    new_map = dict(data)  # reg_no -> rating
    batch = db.batch()
    count = 0
    processed = set()

    # 1) 先處理「目前已經有 HygieneRating」的 doc
    docs = db.collection("foodByReg").where("HygieneRating", "!=", None).stream()
    for doc in docs:
        reg_no = doc.id
        doc_ref = doc.reference

        if reg_no in new_map:
            batch.set(
                doc_ref,
                {
                    "HygieneRating": new_map[reg_no],
                    "updatedAtISO": now_iso,
                    "updatedAtMs": now_ms,
                },
                merge=True,
            )
        else:
            # 新 JSON 裡沒有 → 刪掉欄位
            batch.set(
                doc_ref,
                {
                    "HygieneRating": None,
                    "updatedAtISO": now_iso,
                    "updatedAtMs": now_ms,
                },
                merge=True,
            )

        processed.add(reg_no)
        count += 1
        if count >= 400:
            batch.commit()
            batch = db.batch()
            count = 0

    # 2) 這次 JSON 有，但之前沒有 HygieneRating 的
    for reg_no, rating in new_map.items():
        if reg_no in processed:
            continue
        doc_ref = db.collection("foodByReg").document(reg_no)
        batch.set(
            doc_ref,
            {
                "HygieneRating": rating,
                "updatedAtISO": now_iso,
                "updatedAtMs": now_ms,
            },
            merge=True,
        )
        count += 1
        if count >= 400:
            batch.commit()
            batch = db.batch()
            count = 0

    if count > 0:
        batch.commit()
# ---------------- 2) InspectionResults：增量更新 + 針對「非合格」自動補座標 ----------------
def process_inspection_results(bucket: str, name: str):
    # 空檔就當作沒有任何更新 []
    records = read_gcs_json(bucket, name, default=[])
    if not isinstance(records, list):
        raise ValueError("InspectionResults JSON 應該是一個陣列")

    now_iso, now_ms = now_ts()
    batch = db.batch()
    count = 0

    for r in records:
        reg_no = r.get("登錄字號")
        if not reg_no:
            continue

        status = r.get("狀態")
        inspection_obj = {
            "status": status,
            "date": r.get("日期"),
            "name": r.get("名稱"),
            "address": r.get("地址"),
            "phone": r.get("電話"),
        }

        doc_ref = db.collection("foodByReg").document(reg_no)

        # 先準備要更新的欄位（檢查結果一定會更新）
        update_data = {
            "InspectionResults": inspection_obj,
            "updatedAtISO": now_iso,
            "updatedAtMs": now_ms,
        }

        # 只有「不是 合格 / 複查合格」才需要補座標 & 推播
        if status not in SAFE_INSPECTION_STATUSES:
            try:
                snapshot = doc_ref.get()
            except Exception as e:
                print(f"⚠️ 無法讀取 doc {reg_no}: {e}")
                snapshot = None

            existing_lat = None
            existing_lng = None
            existing_addr = None

            if snapshot and snapshot.exists:
                d = snapshot.to_dict()
                existing_lat = d.get("latitude")
                existing_lng = d.get("longitude")
                existing_addr = d.get("address")

            # 用「這次檔案的地址」，如果沒有就退而求其次用 Firestore 裡的 address
            addr = inspection_obj.get("address") or existing_addr

            # 如果目前沒有座標，且有地址，就去 geocoding
            if (existing_lat is None or existing_lng is None) and addr:
                coords = geocode_address(addr)
                if coords:
                    lat, lng = coords
                    update_data["latitude"] = lat
                    update_data["longitude"] = lng

                    # 這裡可以觸發推播（之後你把 TODO 實作掉即可）
                    notify_app_about_inspection(reg_no, inspection_obj, lat, lng)

                    # 避免太兇猛打 API，如果你一次更新很多筆可以稍微 sleep 一下：
                    # time.sleep(0.1)

        # 把這次結果寫回 Firestore
        batch.set(doc_ref, update_data, merge=True)
        count += 1

        if count >= 400:
            batch.commit()
            batch = db.batch()
            count = 0

    if count > 0:
        batch.commit()


# ---------------- 3) nightMarketName：全量重建 ----------------
def process_night_markets(bucket: str, name: str):
    # 空檔就當作 {}
    raw = read_gcs_json(bucket, name, default={})
    if not isinstance(raw, dict):
        raise ValueError("nightMarket JSON 應該是 { marketName: [stalls...] }")

    now_iso, now_ms = now_ts()

    # 這次 JSON 攤平成 reg_no -> (market_name, info)
    new_map = {}
    for market_name, stalls in raw.items():
        if not isinstance(stalls, list):
            continue

        for s in stalls:
            reg_no = s.get("食品業者登錄字號")
            if not reg_no:
                continue

            info = {
                "year": s.get("年度"),
                "stallName": s.get("攤位名稱"),
                "evaluationResult": s.get("評核結果"),
            }
            new_map[reg_no] = (market_name, info)

    batch = db.batch()
    count = 0
    processed = set()

    # 1) 先處理「目前已經有 nightMarketName」的 doc
    docs = db.collection("foodByReg").where("nightMarketName", "!=", None).stream()
    for doc in docs:
        reg_no = doc.id
        doc_ref = doc.reference

        if reg_no in new_map:
            market_name, info = new_map[reg_no]
            batch.set(
                doc_ref,
                {
                    "nightMarketName": market_name,
                    "nightMarketInfo": info,
                    "updatedAtISO": now_iso,
                    "updatedAtMs": now_ms,
                },
                merge=True,
            )
        else:
            # 新 JSON 裡沒有 → 刪掉欄位
            batch.update(
                doc_ref,
                {
                    "nightMarketName": None,
                    "nightMarketInfo": firestore.DELETE_FIELD,
                    "updatedAtISO": now_iso,
                    "updatedAtMs": now_ms,
                },
            )


        processed.add(reg_no)
        count += 1
        if count >= 400:
            batch.commit()
            batch = db.batch()
            count = 0

    # 2) 這次 JSON 有，但之前沒有 nightMarketName 的
    for reg_no, (market_name, info) in new_map.items():
        if reg_no in processed:
            continue

        doc_ref = db.collection("foodByReg").document(reg_no)
        batch.set(
            doc_ref,
            {
                "nightMarketName": market_name,
                "nightMarketInfo": info,
                "updatedAtISO": now_iso,
                "updatedAtMs": now_ms,
            },
            merge=True,
        )
        count += 1
        if count >= 400:
            batch.commit()
            batch = db.batch()
            count = 0

    if count > 0:
        batch.commit()

# ---------------- 健康檢查路由 ----------------
@app.get("/health")
async def health_check():
    """健康檢查端點"""
    return {"status": "ok", "service": "food-sync-service"}


# ---------------- 列出所有設備 Token 路由 ----------------
@app.get("/list-tokens")
async def list_all_tokens():
    """
    列出所有設備的 FCM Tokens
    返回格式:
    {
        "success": true,
        "total_users": 10,
        "total_tokens": 15,
        "users": [
            {
                "userId": "xxx",
                "token_count": 2,
                "tokens": ["token1", "token2"]
            },
            ...
        ]
    }
    """
    try:
        print("=" * 50)
        print("📋 列出所有設備 FCM Tokens")
        print("=" * 50)
        
        user_tokens = get_all_fcm_tokens()
        
        # 格式化返回數據
        result = {
            "success": True,
            "total_users": len(user_tokens),
            "total_tokens": sum(len(ut["tokens"]) for ut in user_tokens),
            "users": []
        }
        
        for ut in user_tokens:
            result["users"].append({
                "userId": ut["userId"],
                "token_count": len(ut["tokens"]),
                "tokens": ut["tokens"]
            })
        
        print(f"✅ 找到 {result['total_users']} 個用戶，共 {result['total_tokens']} 個 Tokens")
        return result
        
    except Exception as e:
        print(f"❌ 列出 Tokens 失敗: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to list tokens: {str(e)}")


# ---------------- 測試路由：測試 FCM 推播通知 ----------------
@app.post("/test-fcm")
async def test_fcm_notification(request: Request):
    """
    測試 FCM 推播通知的端點
    
    請求格式:
    {
        "restaurant_name": "測試餐廳",
        "reg_no": "TEST-12345",
        "latitude": 25.051898,
        "longitude": 121.5281835,
        "status": "不合格"
    }
    """
    try:
        body = await request.json()
        
        # 獲取參數，提供默認值
        restaurant_name = body.get("restaurant_name", "測試餐廳")
        reg_no = body.get("reg_no", "TEST-00000")
        latitude = body.get("latitude", 25.051898)
        longitude = body.get("longitude", 121.5281835)
        status = body.get("status", "不合格")
        
        # 驗證必要參數
        if not restaurant_name:
            raise HTTPException(status_code=400, detail="restaurant_name is required")
        if latitude is None or longitude is None:
            raise HTTPException(status_code=400, detail="latitude and longitude are required")
        
        print("=" * 50)
        print("🧪 測試 FCM 推播通知")
        print("=" * 50)
        print(f"餐廳名稱: {restaurant_name}")
        print(f"登記號碼: {reg_no}")
        print(f"經緯度: ({latitude}, {longitude})")
        print(f"狀態: {status}")
        print("")
        
        # 發送 FCM 推播並獲取統計信息
        result = send_fcm_to_all_devices(restaurant_name, reg_no, float(latitude), float(longitude), status)
        
        return {
            "success": result.get("success", True),
            "message": "FCM notification sent",
            "data": {
                "restaurant_name": restaurant_name,
                "restaurant_reg_no": reg_no,
                "restaurant_latitude": latitude,
                "restaurant_longitude": longitude,
                "restaurant_status": status
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
        print(f"❌ 測試 FCM 推播失敗: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to send test FCM notification: {str(e)}")


# ---------------- Cloud Run 入口：接 Eventarc ----------------
@app.post("/")
async def handle_event(request: Request):
    body = await request.json()
    print("RAW_EVENT:", body)

    bucket = None
    name = None

    # 情況 0：最外層就有 bucket / name
    if isinstance(body, dict) and "bucket" in body and "name" in body:
        bucket = body["bucket"]
        name = body["name"]

    # 情況 1：CloudEvent 格式，data.bucket / data.name
    elif "data" in body and isinstance(body["data"], dict) and "bucket" in body["data"]:
        bucket = body["data"]["bucket"]
        name = body["data"]["name"]

    # 情況 2：Pub/Sub push，body.message.data(Base64)
    elif "message" in body:
        msg = body["message"]
        data_b64 = msg.get("data")
        if data_b64:
            decoded = base64.b64decode(data_b64).decode("utf-8")
            inner = json.loads(decoded)
            if "bucket" in inner and "name" in inner:
                bucket = inner["bucket"]
                name = inner["name"]
            elif "data" in inner and isinstance(inner["data"], dict):
                bucket = inner["data"]["bucket"]
                name = inner["data"]["name"]

    if not bucket or not name:
        raise HTTPException(
            status_code=400,
            detail="Unknown event format or missing bucket/name"
        )

    if name.startswith("hygiene/"):
        process_hygiene_rating(bucket, name)
    elif name.startswith("inspection/"):
        process_inspection_results(bucket, name)
    elif name.startswith("night_market/"):
        process_night_markets(bucket, name)
    else:
        return {"status": "ignored", "bucket": bucket, "name": name}

    return {"status": "ok", "bucket": bucket, "name": name}
