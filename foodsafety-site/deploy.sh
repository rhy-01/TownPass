#!/bin/bash

# GCP 部署腳本
# 使用方法: ./deploy.sh [PROJECT_ID]

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 檢查是否提供專案 ID
if [ -z "$1" ]; then
    # 嘗試從 gcloud config 獲取專案 ID
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}錯誤: 請提供 GCP 專案 ID${NC}"
        echo "使用方法: ./deploy.sh PROJECT_ID"
        echo "或者先設定預設專案: gcloud config set project PROJECT_ID"
        exit 1
    fi
    echo -e "${YELLOW}使用預設專案: ${PROJECT_ID}${NC}"
else
    PROJECT_ID=$1
    gcloud config set project $PROJECT_ID
fi

echo -e "${GREEN}開始部署到 GCP...${NC}"
echo -e "專案 ID: ${PROJECT_ID}"
echo ""

# 檢查必要的工具
echo -e "${YELLOW}檢查必要工具...${NC}"
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}錯誤: 未安裝 gcloud CLI${NC}"
    echo "請訪問 https://cloud.google.com/sdk/docs/install 安裝"
    exit 1
fi

# 檢查是否已登入
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${YELLOW}未檢測到活躍的 gcloud 認證，正在登入...${NC}"
    gcloud auth login
fi

# 啟用必要的 API
echo -e "${YELLOW}啟用必要的 API...${NC}"
gcloud services enable cloudbuild.googleapis.com --quiet
gcloud services enable run.googleapis.com --quiet
gcloud services enable containerregistry.googleapis.com --quiet

# 設定 Cloud Build 權限
echo -e "${YELLOW}設定 Cloud Build 權限...${NC}"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# 給 Cloud Build 服務帳戶 Cloud Run Admin 權限
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/run.admin" \
    --condition=None \
    --quiet 2>/dev/null || echo "權限可能已存在"

# 給 Cloud Build 服務帳戶 Service Account User 權限
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None \
    --quiet 2>/dev/null || echo "權限可能已存在"

# 檢查是否存在 cloudbuild.yaml
if [ ! -f "cloudbuild.yaml" ]; then
    echo -e "${RED}錯誤: 找不到 cloudbuild.yaml${NC}"
    exit 1
fi

# 提交構建
echo -e "${GREEN}提交構建到 Cloud Build...${NC}"
echo "這可能需要幾分鐘時間..."
echo ""

gcloud builds submit --config cloudbuild.yaml

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ 部署成功！${NC}"
    echo ""
    echo -e "${YELLOW}服務 URL:${NC}"
    gcloud run services describe foodsafety-web \
        --region asia-east1 \
        --format="value(status.url)" 2>/dev/null || echo "請稍候，服務正在啟動..."
    echo ""
    echo -e "${YELLOW}查看日誌:${NC}"
    echo "gcloud run services logs read foodsafety-web --region asia-east1"
else
    echo -e "${RED}✗ 部署失敗${NC}"
    exit 1
fi

