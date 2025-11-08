# 修復背景通知問題

## 🔍 問題分析

從錯誤日志可以看到：
```
PlatformException(error, Attempt to invoke virtual method 'int android.content.Context.checkPermission(java.lang.String, int, int)' on a null object reference
```

**問題原因：**
- 在背景 isolate 中無法訪問 Android Context
- 無法在背景處理器中請求通知權限
- 通知通道可能沒有正確創建

## ✅ 解決方案

### 1. 在應用程式啟動時創建通知通道

在 `NotificationService.init()` 中創建通知通道：

```dart
// 創建通知通道（Android 8.0+）
if (Platform.isAndroid) {
  final androidImplementation = _notificationInstance
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  
  await androidImplementation?.createNotificationChannel(
    const AndroidNotificationChannel(
      'TownPass android notification id',
      'TownPass android notification channel name',
      description: 'TownPass 通知通道',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ),
  );
}
```

### 2. 在應用程式啟動時請求通知權限

確保在應用程式啟動時調用 `NotificationService.requestPermission()`。

### 3. 在背景處理器中不請求權限

背景處理器中已經移除了權限請求，只創建通知通道並顯示通知。

## 🧪 測試步驟

### 1. 確保應用程式已授予通知權限

1. 運行應用程式
2. 檢查是否彈出通知權限請求
3. 如果沒有，手動授予權限：
   - Android: 設置 > 應用程式 > Town Pass > 通知 > 允許通知

### 2. 測試前景通知

1. 應用程式在前景運行
2. 發送 FCM 訊息（title = '1'）
3. 應該能看到通知

### 3. 測試背景通知

1. 應用程式在背景運行
2. 發送 FCM 訊息（title = '1'）
3. 應該能看到通知

### 4. 測試關閉時的通知

1. 完全關閉應用程式
2. 發送 FCM 訊息（title = '1'）
3. 使用 `adb logcat` 查看日志：
   ```bash
   adb logcat | grep -E "flutter|通知|Notification"
   ```
4. 應該能看到通知

## ⚠️ 注意事項

1. **權限必須在應用程式啟動時授予**
   - 背景處理器無法請求權限
   - 必須在應用程式啟動時請求並授予權限

2. **通知通道必須在應用程式啟動時創建**
   - 背景處理器可以創建通知通道，但最好在啟動時創建
   - 確保通道 ID 和名稱一致

3. **檢查通知權限**
   ```bash
   # 檢查應用程式是否有通知權限
   adb shell dumpsys package com.example.townpass | grep notification
   ```

4. **檢查通知通道**
   ```bash
   # 檢查通知通道是否創建
   adb shell dumpsys notification | grep -A 10 "TownPass"
   ```

## 🔧 調試方法

### 1. 檢查權限

```bash
adb shell dumpsys package com.example.townpass | grep -i notification
```

### 2. 檢查通知通道

```bash
adb shell dumpsys notification | grep -A 10 "TownPass android notification id"
```

### 3. 查看詳細日志

```bash
adb logcat | grep -E "flutter|Notification|TownPass|通知"
```

### 4. 測試本地通知

在應用程式中直接調用：

```dart
NotificationService.showNotification(
  title: '測試',
  content: '這是一個測試通知',
);
```

如果這個可以顯示，說明權限和通道都正確。

## 📚 相關資源

- [Flutter Local Notifications 文檔](https://pub.dev/packages/flutter_local_notifications)
- [Android 通知通道](https://developer.android.com/training/notify-user/channels)
- [FCM 背景訊息處理](./FCM_BACKGROUND_MESSAGE_GUIDE.md)

