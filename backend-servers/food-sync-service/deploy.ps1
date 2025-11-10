# PowerShell 部署腳本 for food-sync-service

Write-Host "🚀 開始部署 Food Sync Service..." -ForegroundColor Green

# 檢查必要環境變數
$PROJECT_ID = $env:GCP_PROJECT_ID
if (-not $PROJECT_ID) {
    Write-Host "❌ 請設定 GCP_PROJECT_ID 環境變數" -ForegroundColor Red
    Write-Host "   `$env:GCP_PROJECT_ID = 'your-project-id'" -ForegroundColor Yellow
    exit 1
}

Write-Host "📦 使用專案: $PROJECT_ID" -ForegroundColor Cyan

# 確保 Pub/Sub Topic 存在
Write-Host "🔧 檢查 Pub/Sub Topic..." -ForegroundColor Yellow
$topicExists = gcloud pubsub topics describe data-update-notifications --project=$PROJECT_ID 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "📝 創建 Pub/Sub Topic: data-update-notifications" -ForegroundColor Yellow
    gcloud pubsub topics create data-update-notifications --project=$PROJECT_ID
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Pub/Sub Topic 創建成功" -ForegroundColor Green
    } else {
        Write-Host "❌ 創建 Pub/Sub Topic 失敗" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✅ Pub/Sub Topic 已存在" -ForegroundColor Green
}

# 部署到 Cloud Run
Write-Host "🚀 部署到 Cloud Run..." -ForegroundColor Yellow
gcloud run deploy food-sync-service `
  --source . `
  --platform managed `
  --region asia-east1 `
  --set-env-vars GCP_PROJECT_ID=$PROJECT_ID `
  --allow-unauthenticated `
  --project=$PROJECT_ID

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 部署成功!" -ForegroundColor Green
    
    Write-Host "🌐 取得服務 URL:" -ForegroundColor Cyan
    $serviceUrl = gcloud run services describe food-sync-service --region=asia-east1 --project=$PROJECT_ID --format='value(status.url)'
    Write-Host $serviceUrl -ForegroundColor White
    
    Write-Host "🧪 測試健康檢查..." -ForegroundColor Yellow
    try {
        $response = Invoke-RestMethod -Uri "$serviceUrl/health" -Method Get
        Write-Host "健康檢查結果:" -ForegroundColor Green
        $response | ConvertTo-Json -Depth 3
    } catch {
        Write-Host "⚠️ 健康檢查失敗，但服務可能仍在啟動中" -ForegroundColor Yellow
    }
    
    Write-Host "✨ 部署完成!" -ForegroundColor Green
    Write-Host "📋 測試通知功能:" -ForegroundColor Cyan
    Write-Host "   Invoke-RestMethod -Uri '$serviceUrl/test-notification' -Method Post -ContentType 'application/json' -Body '{`"name`":`"測試餐廳`",`"status`":`"不合格`"}'" -ForegroundColor Gray
    
} else {
    Write-Host "❌ 部署失敗" -ForegroundColor Red
    exit 1
}