#!/bin/bash

# FCM 背景訊息測試腳本
# 用於查看應用程式關閉時的 FCM 日志

echo "========================================="
echo "FCM 背景訊息日志監控"
echo "========================================="
echo ""
echo "請按照以下步驟操作："
echo "1. 確保應用程式已經完全關閉"
echo "2. 在另一個 terminal 發送 FCM 訊息"
echo "3. 觀察此 terminal 的輸出"
echo ""
echo "按 Ctrl+C 停止監控"
echo "========================================="
echo ""

# 清除舊日志
echo "清除舊日志..."
adb logcat -c

echo "開始監控日志..."
echo ""

# 監控 Flutter、FCM 相關日志
adb logcat | grep -E "flutter|FCM|FirebaseMessaging|firebase_messaging|背景訊息|firebaseMessagingBackgroundHandler|1"




