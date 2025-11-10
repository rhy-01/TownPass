# Food Sync Service - 餐廳稽查通知功能

這個服務會監控餐廳稽查結果，當發現餐廳稽查不合格時，會自動發送通知到 Pub/Sub。

## 功能特色

- 🔍 **自動監控稽查結果**: 當處理稽查數據時，自動檢測不合格餐廳
- 📢 **智能通知分級**: 根據不合格程度自動分級通知（高/中/低嚴重性）
- 🎯 **Pub/Sub 整合**: 發送結構化通知到 `data-update-notifications` topic
- 🧪 **測試功能**: 提供測試端點方便調試

## 設定方式

### 1. 環境變數設定

```bash
export GCP_PROJECT_ID="your-actual-project-id"
```

或直接修改 `config.py` 中的 `PROJECT_ID`。

### 2. 確保 Pub/Sub Topic 存在

```bash
gcloud pubsub topics create data-update-notifications
```

### 3. 安裝依賴

```bash
pip install -r requirements.txt
```

## 通知觸發條件

系統會檢查稽查狀態中是否包含以下關鍵字：
- 不合格
- 不符合
- 違規
- 裁罰
- 停業
- 限期改善

## 嚴重程度分級

### 🚨 高嚴重性 (High)
- 停業
- 裁罰

### ⚠️ 中嚴重性 (Medium) 
- 限期改善
- 違規

### 📋 低嚴重性 (Low)
- 不合格
- 不符合

## 通知訊息格式

```json
{
  "type": "inspection_failure",
  "title": "🚨 緊急通知：'餐廳名稱' 2024-11-09 稽查嚴重不合格",
  "message": "餐廳 '餐廳名稱' 於 2024-11-09 的稽查結果為：停業。請注意食品安全。",
  "restaurant_info": {
    "name": "餐廳名稱",
    "address": "餐廳地址",
    "phone": "聯絡電話",
    "reg_no": "登錄字號",
    "status": "停業",
    "inspection_date": "2024-11-09"
  },
  "timestamp": "2024-11-09T12:00:00Z",
  "severity": "high"
}
```

## API 端點

### POST /test-notification
測試通知功能

**請求範例:**
```json
{
  "name": "測試餐廳",
  "status": "不合格",
  "address": "台北市信義區測試路123號",
  "phone": "02-1234-5678"
}
```

**回應範例:**
```json
{
  "status": "success",
  "message": "測試通知已發送",
  "message_id": "1234567890",
  "restaurant_info": { ... }
}
```

### GET /health
健康檢查端點

## 使用方式

1. **自動觸發**: 當稽查數據更新時，系統會自動檢查並發送通知
2. **手動測試**: 使用 `/test-notification` 端點測試通知功能
3. **監控**: 檢查 Cloud Logging 查看通知發送狀況

## 故障排除

### 權限問題
確保服務帳戶有以下權限：
- Pub/Sub Publisher
- Cloud Storage Object Viewer
- Firestore User

### Topic 不存在
```bash
gcloud pubsub topics create data-update-notifications
```

### 測試連接
```bash
curl -X POST http://localhost:8000/test-notification \
  -H "Content-Type: application/json" \
  -d '{"name": "測試餐廳", "status": "不合格"}'
```

## 部署

### Cloud Run 部署
```bash
gcloud run deploy food-sync-service \
  --source . \
  --set-env-vars GCP_PROJECT_ID=your-project-id \
  --allow-unauthenticated
```