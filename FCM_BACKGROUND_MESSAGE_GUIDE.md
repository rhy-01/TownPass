# FCM 背景訊息處理指南

## 📋 概述

本指南說明如何在應用程式**完全關閉**時接收並處理 FCM 訊息，實現完全控制的推播通知。

## 🎯 核心概念

### Data-Only 訊息（資料訊息）

**重要：** 後端發送訊息時，**必須只包含 `data` 欄位，不應包含 `notification` 欄位**。

- ✅ **正確：** 只使用 `data` 欄位
  ```json
  {
    "to": "user_fcm_token",
    "data": {
      "type": "sync",
      "message": "需要同步數據",
      "silent": "true"
    }
  }
  ```

- ❌ **錯誤：** 包含 `notification` 欄位
  ```json
  {
    "to": "user_fcm_token",
    "notification": {
      "title": "標題",
      "body": "內容"
    },
    "data": {
      "type": "sync"
    }
  }
  ```

**原因：** 
- 如果包含 `notification` 欄位，Android/iOS 系統會**自動顯示**系統通知，App 將失去控制權
- 只使用 `data` 欄位，確保 App（即使在背景或關閉）也會被喚醒並執行 Dart 程式碼

## 🔧 實現細節

### 1. 背景訊息處理器

背景訊息處理器定義在 `lib/main.dart` 中：

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 必須先初始化 Firebase（在背景 isolate 中）
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 在 terminal 輸出 1（用於測試）
  print('1');
  
  // 決策邏輯：根據訊息數據決定處理方式
  final data = message.data;
  
  // 檢查是否為靜默訊息
  if (data['silent'] == 'true' || data['type'] == 'sync') {
    print('這是一個靜默同步訊息，不顯示通知');
    // 執行數據同步邏輯
    return;
  }
  
  // 檢查是否需要顯示通知
  if (data['showNotification'] == 'true') {
    print('需要顯示通知');
    // 手動觸發本地通知
  }
}
```

### 2. 註冊背景處理器

背景處理器必須在 `main()` 函數的最開始註冊：

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 重要：必須在任何 Firebase 操作之前註冊背景訊息處理器
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  // ... 其他初始化代碼
}
```

## 🧪 測試方法

### 步驟 1：獲取 FCM Token

1. 運行應用程式
2. 在 terminal 中查看輸出的 FCM Token
3. 複製該 Token

### 步驟 2：發送測試訊息

使用 curl 或 Firebase Console 發送 data-only 訊息：

```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "YOUR_FCM_TOKEN",
    "data": {
      "type": "test",
      "message": "測試訊息",
      "silent": "false"
    }
  }'
```

### 步驟 3：關閉應用程式

1. **完全關閉應用程式**（不要只是切換到背景）
2. 在 Android 上：從最近的應用列表中滑除應用程式
3. 在 iOS 上：雙擊 Home 鍵（或從底部向上滑動），然後向上滑動應用程式

### 步驟 4：發送訊息

發送上述測試訊息後，應該在 terminal 中看到：

```
1
=== 背景訊息處理器被觸發 ===
訊息 ID: 0:1234567890
訊息時間: 1234567890
訊息數據: {type: test, message: 測試訊息, silent: false}
訊息通知: null - null
=== 背景訊息處理完成 ===
```

## 📱 不同狀態下的訊息處理

### 1. 應用程式在前景（Foreground）

訊息由 `FirebaseMessaging.onMessage` 處理：
- 不會自動顯示通知
- 可以完全控制是否顯示通知
- 可以執行任何業務邏輯

### 2. 應用程式在背景（Background）

訊息由 `firebaseMessagingBackgroundHandler` 處理：
- 應用程式在背景但未完全關閉時
- 可以執行數據同步、更新緩存等操作
- 可以決定是否顯示通知

### 3. 應用程式完全關閉（Terminated）

訊息由 `firebaseMessagingBackgroundHandler` 處理：
- 應用程式完全關閉時
- 系統會喚醒應用程式並執行背景處理器
- 可以在 terminal 中看到輸出（通過 `print` 或 `debugPrint`）

## 🔍 決策邏輯範例

### 靜默同步

```dart
if (data['silent'] == 'true' || data['type'] == 'sync') {
  // 執行數據同步
  // 不顯示通知
  return;
}
```

### 顯示通知

```dart
if (data['showNotification'] == 'true') {
  // 使用 flutter_local_notifications 顯示通知
  // 注意：在背景處理器中，需要初始化 NotificationService
}
```

### 條件判斷

```dart
final messageType = data['type'];
switch (messageType) {
  case 'sync':
    // 同步數據
    break;
  case 'update':
    // 更新 UI
    break;
  case 'notification':
    // 顯示通知
    break;
  default:
    // 預設處理
}
```

## ⚠️ 注意事項

1. **背景處理器限制：**
   - 運行在單獨的 isolate 中
   - 不能訪問 GetX 服務
   - 不能訪問應用程式狀態
   - 必須重新初始化 Firebase

2. **訊息格式：**
   - 必須使用 data-only 訊息
   - 不能包含 `notification` 欄位
   - 數據欄位必須是字符串類型

3. **測試：**
   - 必須完全關閉應用程式
   - 不能只是切換到背景
   - **重要：** 當應用程式關閉時，`flutter run` 的 terminal 會失去連線
   - 必須使用 `adb logcat` 查看 Android 日志（詳見下方說明）
   - 使用 Xcode Console 查看 iOS 日志

## 📱 查看應用程式關閉時的日志

### ⚠️ 重要提示

當應用程式完全關閉時，`flutter run` 的 terminal 會失去連線，無法直接看到 `print()` 的輸出。必須使用系統級日志查看工具。

### Android - 使用 adb logcat

#### 快速測試（推薦）

使用提供的測試腳本：

```bash
cd TownPass
./test-background-fcm.sh
```

#### 手動監控

在一個新的 terminal 中運行：

```bash
# 1. 清除舊日志
adb logcat -c

# 2. 監控 Flutter 和 FCM 相關日志
adb logcat | grep -E "flutter|FCM|FirebaseMessaging|背景訊息|firebaseMessagingBackgroundHandler|1"
```

#### 完整測試流程

1. **啟動日志監控**（Terminal 1）
   ```bash
   adb logcat -c
   adb logcat | grep -E "flutter|FCM|1|背景訊息"
   ```

2. **完全關閉應用程式**
   - 從最近應用列表中滑除應用程式

3. **發送 FCM 訊息**（Terminal 2）
   ```bash
   cd backend
   ./test-pubsub.sh
   ```

4. **查看日志**
   - 在 Terminal 1 中應該能看到 "1" 和相關日志

### iOS - 使用 Xcode Console

1. 在 Xcode 中打開項目
2. 運行應用程式（或只是連接設備）
3. 打開 Xcode 的 Console（View > Debug Area > Activate Console）
4. 關閉應用程式
5. 發送 FCM 訊息
6. 在 Console 中查看日志

### 其他方法

- 查看詳細指南：`VIEW_BACKGROUND_LOGS.md`
- 使用日志文件：可以將日志寫入文件，然後通過 adb 或 Xcode 查看

## 📚 相關資源

- [Firebase Cloud Messaging 文檔](https://firebase.google.com/docs/cloud-messaging)
- [Flutter Firebase Messaging 插件](https://pub.dev/packages/firebase_messaging)
- [Flutter Local Notifications 插件](https://pub.dev/packages/flutter_local_notifications)


