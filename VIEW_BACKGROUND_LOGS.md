# 查看應用程式關閉時的 FCM 背景日志

## 🔍 問題說明

當應用程式完全關閉時，`flutter run` 的 terminal 會失去連線，無法直接看到 `print()` 的輸出。

## ✅ 解決方案

### Android - 使用 adb logcat

#### 方法 1：查看所有 Flutter 日志

```bash
# 查看所有 Flutter 相關日志
adb logcat | grep -i flutter

# 或查看特定標籤
adb logcat -s flutter
```

#### 方法 2：查看應用程式特定日志

```bash
# 查看特定應用程式的日志（使用 package name）
adb logcat | grep "com.example.townpass"

# 或使用應用程式 PID
adb logcat --pid=$(adb shell pidof -s com.example.townpass)
```

#### 方法 3：查看 FCM 相關日志

```bash
# 查看 FCM 和 Firebase 相關日志
adb logcat | grep -E "flutter|FCM|FirebaseMessaging|firebase_messaging"
```

#### 方法 4：實時監控並過濾

```bash
# 清除舊日志
adb logcat -c

# 實時查看日志，只顯示包含 "1" 或 "背景訊息" 的行
adb logcat | grep -E "1|背景訊息|firebaseMessagingBackgroundHandler|FCM"
```

#### 方法 5：保存日志到文件

```bash
# 保存日志到文件
adb logcat > background_logs.txt

# 然後在另一個 terminal 發送 FCM 訊息
# 發送完成後，按 Ctrl+C 停止記錄
# 查看文件中的相關日志
cat background_logs.txt | grep -E "1|背景訊息|FCM"
```

### iOS - 使用 Xcode Console 或 syslog

#### 方法 1：使用 Xcode Console

1. 在 Xcode 中打開項目
2. 運行應用程式（或只是連接設備）
3. 打開 Xcode 的 Console（View > Debug Area > Activate Console）
4. 關閉應用程式
5. 發送 FCM 訊息
6. 在 Console 中查看日志

#### 方法 2：使用 syslog（macOS）

```bash
# 查看系統日志（需要 macOS）
log stream --predicate 'processImagePath contains "Runner"' --level debug

# 或查看特定時間的日志
log show --predicate 'processImagePath contains "Runner"' --last 5m
```

#### 方法 3：使用 iOS 設備日志

```bash
# 通過 Xcode 的設備窗口查看
# Xcode > Window > Devices and Simulators
# 選擇設備 > View Device Logs
```

---

## 🔧 改進：將日志寫入文件

為了更方便地查看背景日志，我們可以將日志寫入文件。

### Android 實現

創建一個日志工具，將日志寫入文件：

```dart
// lib/util/log_util.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class LogUtil {
  static File? _logFile;
  
  static Future<void> init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File(path.join(directory.path, 'fcm_background_logs.txt'));
    } catch (e) {
      print('初始化日志文件失敗: $e');
    }
  }
  
  static Future<void> writeLog(String message) async {
    // 同時輸出到 console 和文件
    print(message);
    
    if (_logFile != null) {
      try {
        final timestamp = DateTime.now().toIso8601String();
        await _logFile!.writeAsString(
          '[$timestamp] $message\n',
          mode: FileMode.append,
        );
      } catch (e) {
        print('寫入日志文件失敗: $e');
      }
    }
  }
  
  static Future<String> readLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      return await _logFile!.readAsString();
    }
    return '沒有日志文件';
  }
  
  static Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
    }
  }
}
```

### 在背景處理器中使用

```dart
// lib/main.dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 初始化日志工具
  await LogUtil.init();
  
  // 寫入日志
  await LogUtil.writeLog('1');
  await LogUtil.writeLog('=== 背景訊息處理器被觸發 ===');
  await LogUtil.writeLog('訊息 ID: ${message.messageId}');
  await LogUtil.writeLog('訊息數據: ${message.data}');
  
  // ... 其他處理邏輯
}
```

### 查看日志文件

#### Android

```bash
# 使用 adb 查看日志文件
adb shell "run-as com.example.townpass cat /data/data/com.example.townpass/app_flutter/fcm_background_logs.txt"

# 或使用 adb pull 下載文件
adb shell "run-as com.example.townpass cat /data/data/com.example.townpass/app_flutter/fcm_background_logs.txt" > background_logs.txt
```

#### iOS

```bash
# 使用 Xcode 設備窗口
# Xcode > Window > Devices and Simulators
# 選擇設備 > 選擇應用程式 > Download Container
# 解壓後在 AppData/Documents/ 中找到日志文件
```

---

## 📱 測試步驟

### 完整測試流程

1. **啟動日志監控**
   
   **Android:**
   ```bash
   # Terminal 1: 監控日志
   adb logcat -c  # 清除舊日志
   adb logcat | grep -E "flutter|FCM|1|背景訊息"
   ```
   
   **iOS:**
   - 打開 Xcode Console

2. **運行應用程式**
   ```bash
   flutter run
   ```

3. **完全關閉應用程式**
   - Android: 從最近應用列表中滑除
   - iOS: 雙擊 Home 鍵，向上滑動應用程式

4. **發送 FCM 訊息**
   ```bash
   # 使用後端的測試腳本
   cd backend
   ./test-pubsub.sh
   ```

5. **查看日志**
   - 在監控的 terminal 中應該能看到 "1" 和相關日志
   - 或查看日志文件

---

## 🎯 快速測試命令

### Android 一鍵測試

```bash
#!/bin/bash
# test-background-fcm.sh

echo "清除舊日志..."
adb logcat -c

echo "開始監控日志（等待 FCM 訊息）..."
echo "請在另一個 terminal 發送 FCM 訊息"
echo ""

adb logcat | grep -E "flutter|FCM|1|背景訊息|firebaseMessagingBackgroundHandler"
```

### 使用方式

```bash
chmod +x test-background-fcm.sh
./test-background-fcm.sh
```

然後在另一個 terminal 發送 FCM 訊息。

---

## 🔍 驗證清單

- [ ] 應用程式在前景時能看到通知 ✅
- [ ] 應用程式在背景時能看到通知 ✅
- [ ] 應用程式關閉時能在 logcat/Console 中看到 "1" ✅
- [ ] 日志文件中有記錄（如果實現了文件日志）✅

---

## 📚 相關資源

- [Android adb logcat 文檔](https://developer.android.com/studio/command-line/logcat)
- [iOS 設備日志](https://developer.apple.com/documentation/xcode/viewing-device-logs-in-xcode)
- [Flutter 調試指南](https://docs.flutter.dev/testing/debugging)

