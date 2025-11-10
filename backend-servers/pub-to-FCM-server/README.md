# Cloud Run FCM Notifier Service

這個服務用於接收 Pub/Sub 訊息並發送 FCM 推播通知。

## 功能

- 接收 Pub/Sub 推送的 HTTP 請求
- 從 Firestore 查詢用戶的 FCM Token
- 發送 FCM 推播通知給多個用戶

## 本地開發

### 安裝依賴

```bash
npm install
```

### 設置環境變數

創建 `.env` 文件（用於本地測試，Cloud Run 會使用服務帳戶）：

```env
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
```

### 運行本地服務

```bash
npm start
```

## 構建 Docker 映像檔

```bash
docker build -t gcr.io/your-project-id/fcm-push-service:latest .
```

## 推送映像檔到 Artifact Registry

```bash
gcloud auth configure-docker
docker push gcr.io/your-project-id/fcm-push-service:latest
```

## 部署到 Cloud Run

在 Cloud Run 介面中：
1. 選擇「建立新服務」
2. 容器映像檔網址：`gcr.io/your-project-id/fcm-push-service:latest`
3. 設定服務帳戶權限（需要 Firestore 和 FCM 權限）
4. 設定 Pub/Sub 訂閱推送端點

## Pub/Sub 訊息格式

```json
{
  "message": {
    "data": "base64-encoded-json"
  }
}
```

解碼後的 JSON 格式：

```json
{
  "targetUserIds": ["user1", "user2"],
  "notificationTitle": "新資料通知",
  "notificationBody": "您有新的更新內容",
  "targetUrl": "/updates"
}
```

## Firestore 資料結構

用戶 FCM Token 應儲存在 `users` collection 中：

```
users/
  └── {userId}/
      └── fcmToken: "FCM_TOKEN_STRING"
```

