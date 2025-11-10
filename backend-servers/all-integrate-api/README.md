# All Integrate API

發票檢查和 FCM 推播服務

## 功能

1. **發票檢查 API** (`POST /invoice/check`) - 檢查發票對應的餐廳是否有食品安全風險
2. **測試 FCM 推播** (`POST /test-invoice-fcm`) - 測試發票相關的 FCM 推播通知
3. **健康檢查** (`GET /health`) - 服務健康狀態檢查
4. **列出 Tokens** (`GET /list-tokens`) - 列出所有註冊的 FCM tokens

## 部署

### 方法 1: 使用部署腳本

```bash
cd all-integrate-api/all-integrate-api
./deploy.sh
```

### 方法 2: 手動部署

```bash
cd all-integrate-api/all-integrate-api
gcloud run deploy all-integrate-api \
  --source . \
  --region asia-east1 \
  --platform managed \
  --allow-unauthenticated \
  --service-account food-sync-sa@micro-service-477116.iam.gserviceaccount.com \
  --project micro-service-477116
```

## 重要注意事項

⚠️ **必須在 `all-integrate-api/all-integrate-api` 目錄下執行部署命令**

如果遇到 `TownPass/.git/AUTO_MERGE` 錯誤，請確保：
1. 在正確的目錄執行部署命令
2. `.gcloudignore` 文件已正確配置
3. 沒有 Git 合併衝突未解決

## 測試

### 測試健康檢查
```bash
curl https://your-service-url/health
```

### 測試發票檢查
```bash
curl -X POST https://your-service-url/invoice/check \
  -H "Content-Type: application/json" \
  -d '{
    "invoiceDate": "2024-01-15",
    "sellerTin": "12345678",
    "sellerName": "測試餐廳"
  }'
```

### 測試 FCM 推播
```bash
./test-invoice-fcm.sh
```

## 環境變數

無需額外環境變數，服務使用默認的 Google Cloud 服務賬戶認證。

## 依賴

- FastAPI
- Google Cloud Firestore
- Google Auth (for FCM)
- Requests (for FCM API)



