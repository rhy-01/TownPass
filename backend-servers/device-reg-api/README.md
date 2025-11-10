# API Service

主業務 API Server，負責處理業務邏輯並發布 Pub/Sub 訊息以觸發 FCM 推送通知。

## 功能

- 處理主業務 API 請求
- 執行核心業務邏輯（資料更新等）
- 發布 Pub/Sub 訊息到 `data-update-notifications` 主題
- 觸發 FCM 推送流程

## 依賴

- `express`: Web Server 框架
- `@google-cloud/pubsub`: Google Cloud Pub/Sub SDK

## 本地開發

```bash
npm install
npm start
```

## 建構 Docker 映像檔

```bash
docker build -t gcr.io/your-project-id/api-service:latest .
```

## 推送到 Artifact Registry

```bash
docker push gcr.io/your-project-id/api-service:latest
```

## 部署到 Cloud Run

1. 在 Cloud Run Console 中建立新服務
2. 使用映像檔：`gcr.io/your-project-id/api-service:latest`
3. 設定服務名稱：`api-service`
4. 允許公開存取
5. 確保服務帳戶有 Pub/Sub Publisher 權限

## API 端點

### POST /api/data/update

處理資料更新請求並發布通知事件。

**請求 Body:**
```json
{
  "userId": "user123",
  "dataKey": "profile",
  "newValue": "updated value",
  "notificationTitle": "您的資料已更新",
  "notificationBody": "點擊查看變更內容。"
}
```

**回應:**
```json
{
  "message": "Data processed and notification event published.",
  "publishedToTopic": "data-update-notifications"
}
```

### GET /health

健康檢查端點。

## 注意事項

- 確保 Cloud Run 服務帳戶具有 `pubsub.publisher` 角色
- Pub/Sub 主題 `data-update-notifications` 必須已存在
- 在 `index.js` 中的 `[TODO]` 區塊需要實作實際的資料庫操作邏輯

