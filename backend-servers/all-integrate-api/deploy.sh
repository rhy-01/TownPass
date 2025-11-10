#!/bin/bash

# 部署腳本 for all-integrate-api

echo "🚀 開始部署 All Integrate API..."

# 配置
PROJECT_ID="${GCP_PROJECT_ID:-micro-service-477116}"
SERVICE_NAME="all-integrate-api"
REGION="asia-east1"
SERVICE_ACCOUNT="food-sync-sa@micro-service-477116.iam.gserviceaccount.com"

echo "📦 使用專案: $PROJECT_ID"
echo "🔧 服務名稱: $SERVICE_NAME"
echo "📍 區域: $REGION"
echo ""

# 檢查當前目錄
CURRENT_DIR=$(pwd)
echo "📍 當前目錄: $CURRENT_DIR"

# 確保在正確的目錄
if [ ! -f "main.py" ]; then
    echo "❌ 錯誤: 找不到 main.py 文件"
    echo "   請在 all-integrate-api/all-integrate-api 目錄下執行此腳本"
    exit 1
fi

# 檢查 .gcloudignore 文件
if [ ! -f ".gcloudignore" ]; then
    echo "⚠️  警告: 找不到 .gcloudignore 文件"
fi

# 部署到 Cloud Run
echo "🚀 部署到 Cloud Run..."
gcloud run deploy $SERVICE_NAME \
  --source . \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --service-account $SERVICE_ACCOUNT \
  --project $PROJECT_ID \
  --memory 512Mi \
  --cpu 1 \
  --timeout 300 \
  --concurrency 80

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 部署成功!"
    echo ""
    echo "🌐 取得服務 URL:"
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --project=$PROJECT_ID --format='value(status.url)')
    echo "$SERVICE_URL"
    echo ""
    echo "🧪 測試健康檢查..."
    curl -s "$SERVICE_URL/health" | jq . 2>/dev/null || curl -s "$SERVICE_URL/health"
    echo ""
    echo "✨ 部署完成!"
else
    echo ""
    echo "❌ 部署失敗"
    exit 1
fi



