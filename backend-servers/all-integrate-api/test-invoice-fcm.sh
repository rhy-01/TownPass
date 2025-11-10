#!/bin/bash

# 測試發票 FCM 推播通知腳本

echo "🧪 測試發票 FCM 推播通知"
echo ""

# 配置
PROJECT_ID="${GCP_PROJECT_ID:-micro-service-477116}"
SERVICE_NAME="all-integrate-api"
REGION="asia-east1"

# 如果提供了第一個參數作為 URL，使用它；否則嘗試從 Cloud Run 獲取
if [ -n "$1" ]; then
    SERVICE_URL="$1"
    echo "📡 使用提供的服務 URL: $SERVICE_URL"
else
    echo "🔍 嘗試從 Cloud Run 獲取服務 URL..."
    SERVICE_URL='https://all-integrate-api-745797496080.asia-east1.run.app'
    
    if [ -z "$SERVICE_URL" ]; then
        echo "⚠️  無法從 Cloud Run 獲取服務 URL，使用本地 URL"
        SERVICE_URL="http://localhost:8080"
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
else
    echo "⚠️  獲取 Tokens 列表失敗 (HTTP $HTTP_CODE)"
    echo "$BODY"
fi

echo ""
echo ""

# 測試 1: 發送測試發票 FCM 通知（使用默認值）
echo "========================================="
echo "測試 1: 發送測試發票 FCM 通知（使用默認值）"
echo "========================================="
TEST_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$SERVICE_URL/test-invoice-fcm" \
    -H "Content-Type: application/json" \
    -d '{}' || echo "000")
HTTP_CODE=$(echo "$TEST_RESPONSE" | tail -n1)
BODY=$(echo "$TEST_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 測試發票 FCM 通知發送成功"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
else
    echo "❌ 測試發票 FCM 通知發送失敗 (HTTP $HTTP_CODE)"
    echo "$BODY"
fi

echo ""
echo ""

#