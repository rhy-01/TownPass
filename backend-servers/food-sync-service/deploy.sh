#!/bin/bash

# 部署腳本 for food-sync-service

echo "🚀 開始部署 Food Sync Service..."

# 檢查必要環境變數
if [ -z "$GCP_PROJECT_ID" ]; then
    echo "❌ 請設定 GCP_PROJECT_ID 環境變數"
    echo "   export GCP_PROJECT_ID=your-project-id"
    exit 1
fi

echo "📦 使用專案: $GCP_PROJECT_ID"

# 確保 Pub/Sub Topic 存在
echo "🔧 檢查 Pub/Sub Topic..."
gcloud pubsub topics describe data-update-notifications --project=$GCP_PROJECT_ID 2>/dev/null
if [ $? -ne 0 ]; then
    echo "📝 創建 Pub/Sub Topic: data-update-notifications"
    gcloud pubsub topics create data-update-notifications --project=$GCP_PROJECT_ID
else
    echo "✅ Pub/Sub Topic 已存在"
fi

# 部署到 Cloud Run
echo "🚀 部署到 Cloud Run..."
gcloud run deploy food-sync-service \
  --source . \
  --platform managed \
  --region asia-east1 \
  --set-env-vars GCP_PROJECT_ID=$GCP_PROJECT_ID \
  --allow-unauthenticated \
  --project=$GCP_PROJECT_ID

if [ $? -eq 0 ]; then
    echo "✅ 部署成功!"
    echo "🌐 取得服務 URL:"
    gcloud run services describe food-sync-service --region=asia-east1 --project=$GCP_PROJECT_ID --format='value(status.url)'
else
    echo "❌ 部署失敗"
    exit 1
fi

echo "🧪 測試健康檢查..."
SERVICE_URL=$(gcloud run services describe food-sync-service --region=asia-east1 --project=$GCP_PROJECT_ID --format='value(status.url)')
curl -s "$SERVICE_URL/health" | jq .

echo "✨ 部署完成!"