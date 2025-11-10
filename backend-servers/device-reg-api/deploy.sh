#!/bin/bash

# 部署腳本：構建並推送 Docker 映像到 GCR，然後更新 Cloud Run 服務

set -e  # 如果任何命令失敗，停止執行

# 配置
PROJECT_ID="micro-service-477116"
SERVICE_NAME="api-service"
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
VERSION_TAG="${1:-new-version}"  # 使用第一個參數作為版本標籤，默認為 new-version
REGION="asia-east1"  # 根據您的 Cloud Run 區域調整

echo "🚀 開始部署流程..."
echo "📦 專案 ID: ${PROJECT_ID}"
echo "🏷️  版本標籤: ${VERSION_TAG}"
echo "🌍 區域: ${REGION}"

# 步驟 1: 確認已登錄 gcloud
echo ""
echo "步驟 1: 檢查 gcloud 認證..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "❌ 未找到活躍的 gcloud 認證"
    echo "請執行: gcloud auth login"
    exit 1
fi
echo "✅ gcloud 認證檢查通過"

# 步驟 2: 配置 Docker 使用 gcloud 認證
echo ""
echo "步驟 2: 配置 Docker 認證..."
gcloud auth configure-docker --quiet
echo "✅ Docker 認證配置完成"

# 步驟 3: 構建 Docker 映像
echo ""
echo "步驟 3: 構建 Docker 映像..."
docker build --platform linux/amd64 -t ${IMAGE_NAME}:${VERSION_TAG} .
echo "✅ Docker 映像構建完成"

# 步驟 4: 推送映像到 GCR
echo ""
echo "步驟 4: 推送映像到 Google Container Registry..."
docker push ${IMAGE_NAME}:${VERSION_TAG}
echo "✅ 映像推送完成"

# 步驟 5: 更新 Cloud Run 服務
echo ""
echo "步驟 5: 更新 Cloud Run 服務..."
gcloud run deploy ${SERVICE_NAME} \
    --image ${IMAGE_NAME}:${VERSION_TAG} \
    --platform managed \
    --region ${REGION} \
    --project ${PROJECT_ID} \
    --allow-unauthenticated

echo ""
echo "✅ 部署完成！"
echo "📝 服務 URL:"
gcloud run services describe ${SERVICE_NAME} --region ${REGION} --project ${PROJECT_ID} --format="value(status.url)"

