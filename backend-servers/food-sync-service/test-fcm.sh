#!/bin/bash

# 測試 FCM 推播通知腳本

# 不設置 set -e，讓所有測試都能執行

echo "🧪 測試 FCM 推播通知"
echo ""

# 配置
PROJECT_ID="${GCP_PROJECT_ID:-micro-service-477116}"
SERVICE_NAME="food-sync-service"
REGION="asia-east1"

# 如果提供了第一個參數作為 URL，使用它；否則嘗試從 Cloud Run 獲取
if [ -n "$1" ]; then
    SERVICE_URL="$1"
    echo "📡 使用提供的服務 URL: $SERVICE_URL"
else
    echo "🔍 嘗試從 Cloud Run 獲取服務 URL..."
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)' 2>/dev/null || echo "")
    
    if [ -z "$SERVICE_URL" ]; then
        echo "⚠️  無法從 Cloud Run 獲取服務 URL，使用本地 URL"
        SERVICE_URL="http://localhost:8000"
    else
        echo "✅ 從 Cloud Run 獲取到服務 URL: $SERVICE_URL"
    fi
fi

echo ""

# 測試 0: 健康檢查
echo "========================================="
echo "測試 0: 健康檢查"
echo "========================================="
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$SERVICE_URL/health" || echo "000")
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
BODY=$(echo "$HEALTH_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 服務健康檢查通過"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
else
    echo "❌ 服務健康檢查失敗 (HTTP $HTTP_CODE)"
    echo "$BODY"
    echo ""
    echo "⚠️  服務可能未啟動或 URL 不正確"
    exit 1
fi

echo ""
echo ""

# 測試 0.5: 列出所有設備 Token
echo "========================================="
echo "測試 0.5: 列出所有設備 FCM Tokens"
echo "========================================="
TOKENS_RESPONSE=$(curl -s -w "\n%{http_code}" "$SERVICE_URL/list-tokens" || echo "000")
HTTP_CODE=$(echo "$TOKENS_RESPONSE" | tail -n1)
BODY=$(echo "$TOKENS_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 成功獲取 Tokens 列表"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    
    # 提取統計資訊
    TOTAL_USERS=$(echo "$BODY" | jq -r '.total_users // 0' 2>/dev/null || echo "0")
    TOTAL_TOKENS=$(echo "$BODY" | jq -r '.total_tokens // 0' 2>/dev/null || echo "0")
    echo ""
    echo "📊 統計："
    echo "  總用戶數: $TOTAL_USERS"
    echo "  總 Token 數: $TOTAL_TOKENS"
else
    echo "❌ 獲取 Tokens 列表失敗 (HTTP $HTTP_CODE)"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
fi

echo ""
echo ""

# 測試 1: 發送測試 FCM 推播（台北餐廳）
echo "========================================="
echo "測試 1: 發送測試 FCM 推播（台北餐廳）"
echo "========================================="
echo "這會："
echo "  1. 從 Firestore 讀取所有用戶的 FCM Tokens"
echo "  2. 直接通過 FCM API 發送推播給所有設備"
echo "  3. 包含經緯度，應用應該會顯示通知"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$SERVICE_URL/test-fcm" \
  -H "Content-Type: application/json" \
  -d '{
    "restaurant_name": "貳樓美食股份有限公司-貳樓餐廳師大店",
    "reg_no": "H-182780362-00001-2",
    "latitude": 25.026478113259,
    "longitude": 121.528416288196,
    "status": "不合格"
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 測試 1 成功 (HTTP $HTTP_CODE)"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
else
    echo "❌ 測試 1 失敗 (HTTP $HTTP_CODE)"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
fi

echo ""
echo ""

