# GCP 部署指南

本指南說明如何將 foodsafety-site 部署到 Google Cloud Platform (GCP) 的 Cloud Run。

## 前置需求

1. **GCP 帳戶**: 確保您有 GCP 帳戶並已建立專案
2. **Google Cloud SDK**: 安裝並設定 gcloud CLI
3. **Docker**: 本地測試時需要（可選）

## 設定步驟

### 1. 安裝 Google Cloud SDK

如果尚未安裝，請訪問 [Google Cloud SDK 安裝指南](https://cloud.google.com/sdk/docs/install)

### 2. 登入並設定專案

```bash
# 登入 GCP
gcloud auth login

# 設定預設專案（替換 YOUR_PROJECT_ID 為您的專案 ID）
gcloud config set project YOUR_PROJECT_ID

# 啟用必要的 API
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable containerregistry.googleapis.com
```

### 3. 設定 Cloud Build

```bash
# 給 Cloud Build 服務帳戶 Cloud Run Admin 權限
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)")
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/run.admin"

# 給 Cloud Build 服務帳戶 Service Account User 權限
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"
```

### 4. 部署方式

#### 方式 A: 使用 Cloud Build（推薦）

這是最簡單的方式，會自動構建、推送鏡像並部署到 Cloud Run：

```bash
# 進入專案目錄
cd foodsafety-site

# 提交構建任務
gcloud builds submit --config cloudbuild.yaml
```

#### 方式 B: 使用 gcloud 直接部署

如果您已經構建了 Docker 鏡像：

```bash
# 構建並推送鏡像
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/foodsafety-web

# 部署到 Cloud Run
gcloud run deploy foodsafety-web \
  --image gcr.io/YOUR_PROJECT_ID/foodsafety-web \
  --region asia-east1 \
  --platform managed \
  --allow-unauthenticated \
  --port 8080
```

#### 方式 C: 使用 GitHub Actions（CI/CD）

1. 在 GitHub 儲存庫設定 GCP 服務帳戶金鑰為 Secret
2. 創建 `.github/workflows/deploy.yml`（見下方範例）

## 配置說明

### Cloud Run 設定

- **區域**: asia-east1 (台灣)
- **端口**: 8080
- **記憶體**: 512Mi
- **CPU**: 1
- **最小實例**: 0（降低成本）
- **最大實例**: 10
- **允許未驗證訪問**: 是

### 環境變數（如需）

如果您的應用需要環境變數，可以在 `cloudbuild.yaml` 的部署步驟中添加：

```yaml
- '--set-env-vars'
- 'KEY1=VALUE1,KEY2=VALUE2'
```

或在部署後使用：

```bash
gcloud run services update foodsafety-web \
  --region asia-east1 \
  --set-env-vars KEY1=VALUE1,KEY2=VALUE2
```

## 驗證部署

部署完成後，Cloud Build 會輸出服務 URL。您也可以使用以下命令查看：

```bash
gcloud run services describe foodsafety-web --region asia-east1 --format="value(status.url)"
```

訪問該 URL 確認應用正常運行。

## 更新部署

每次更新代碼後，只需重新執行部署命令：

```bash
gcloud builds submit --config cloudbuild.yaml
```

Cloud Build 會自動：
1. 安裝依賴
2. 構建 Vue 應用
3. 構建 Docker 鏡像
4. 推送到 Container Registry
5. 部署到 Cloud Run

## 監控和日誌

```bash
# 查看日誌
gcloud run services logs read foodsafety-web --region asia-east1

# 查看服務資訊
gcloud run services describe foodsafety-web --region asia-east1
```

## 成本優化

- 最小實例設為 0，可在無流量時減少成本
- 使用 Cloud Run 的按需計費模式
- 考慮設定 Cloud CDN 以加速靜態資源載入

## 故障排除

### 構建失敗

1. 檢查 `cloudbuild.yaml` 語法
2. 確認所有必要的 API 已啟用
3. 查看 Cloud Build 日誌

### 部署失敗

1. 確認服務帳戶權限已正確設定
2. 檢查 Dockerfile 是否正確
3. 確認端口設定為 8080

### 應用無法訪問

1. 確認 `--allow-unauthenticated` 已設定
2. 檢查 nginx 配置是否正確
3. 查看 Cloud Run 日誌

## 自訂域名（可選）

如果需要使用自訂域名：

```bash
gcloud run domain-mappings create \
  --service foodsafety-web \
  --domain your-domain.com \
  --region asia-east1
```

然後按照提示設定 DNS 記錄。

## 參考資源

- [Cloud Run 文件](https://cloud.google.com/run/docs)
- [Cloud Build 文件](https://cloud.google.com/build/docs)
- [Vue.js 部署指南](https://vuejs.org/guide/scaling-up/deployment.html)

