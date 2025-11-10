#!/bin/bash

# Cloud Run FCM Notifier 部署腳本

PROJECT_ID="micro-service-477116"
SERVICE_NAME="fcm-push-service"
REGION="asia-east1"  # 根據您的需求修改區域

echo "開始構建和部署 Cloud Run 服務..."

# 使用 Cloud Build 構建和推送映像檔
gcloud builds submit --tag gcr.io/${PROJECT_ID}/${SERVICE_NAME}:latest

# 部署到 Cloud Run
# 注意：PORT 環境變數由 Cloud Run 自動設置，無需手動指定
gcloud run deploy ${SERVICE_NAME} \
  --image gcr.io/${PROJECT_ID}/${SERVICE_NAME}:latest \
  --platform managed \
  --region ${REGION} \
  --allow-unauthenticated

echo "部署完成！"

