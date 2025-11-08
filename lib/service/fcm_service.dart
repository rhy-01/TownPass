import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';
import 'package:town_pass/firebase_options.dart';
import 'package:town_pass/service/device_registration_service.dart';
import 'package:town_pass/service/notification_service.dart';

/// Firebase Cloud Messaging 服務
/// 負責處理 FCM 的初始化、token 獲取、訊息接收等功能
class FcmService extends GetxService {
  FirebaseMessaging? _firebaseMessaging;
  String? _fcmToken;
  
  /// 獲取當前的 FCM Token
  String? get fcmToken => _fcmToken;

  Future<FcmService> init() async {
    try {
      // 初始化 Firebase
      // 注意：背景訊息處理器應該在 main() 函數中註冊，而不是在這裡
      // 因為背景處理器必須在應用程式啟動時就註冊
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      
      _firebaseMessaging = FirebaseMessaging.instance;
      
      // 請求通知權限
      await _requestPermission();
      
      // 設置訊息處理器
      _setupMessageHandlers();
      
      // 獲取並保存 FCM Token
      await _getFcmToken();
      
      // 監聽 token 刷新
      _firebaseMessaging!.onTokenRefresh.listen(_onTokenRefresh);
      
      return this;
    } catch (e) {
      print('FCM Service initialization error: $e');
      rethrow;
    }
  }

  /// 請求通知權限
  Future<void> _requestPermission() async {
    if (Platform.isIOS) {
      final settings = await _firebaseMessaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        print('User declined or has not accepted notification permissions');
      }
    }
  }

  /// 設置訊息處理器
  void _setupMessageHandlers() {
    // 處理前景訊息（應用程式在前景運行時）
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('收到前景訊息: ${message.messageId}');
      _handleMessage(message);
    });

    // 處理背景訊息（應用程式在背景時點擊通知打開）
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('通過通知打開應用: ${message.messageId}');
      _handleMessage(message);
    });

    // 檢查應用程式是否通過通知啟動
    _firebaseMessaging!.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('應用程式通過通知啟動: ${message.messageId}');
        _handleMessage(message);
      }
    });
  }

  /// 處理接收到的訊息
  void _handleMessage(RemoteMessage message) {
    final data = message.data;

    // 輸出訊息詳情
    print('=== 前景訊息處理器被觸發 ===');
    print('訊息數據: $data');

    // 決策邏輯：檢查 title 欄位是否為 '1'
    final title = data['title'];
    
    // 輸出接收到的 title
    print('接收到的 title: $title');
    
    // 如果 title 是 '1'，就發出通知
    if (title == '1') {
      print('✅ title 是 "1"，將顯示通知');
      
      // 獲取通知內容（使用 body 作為通知內容）
      final notificationBody = data['body'] ?? '通知';
      
      // 顯示通知
      NotificationService.showNotification(
        title: '通知',
        content: notificationBody,
      );
      
      print('通知已顯示');
    } else {
      // 如果 title 不是 '1'，就只在 log 輸出
      print('❌ title 不是 "1" ($title)，只輸出日志，不顯示通知');
      print('完整數據: $data');
    }
    
    print('=== 前景訊息處理完成 ===');
  }

  /// 獲取 FCM Token
  Future<String?> _getFcmToken() async {
    try {
      _fcmToken = await _firebaseMessaging!.getToken();
      print('FCM Token: $_fcmToken');
      return _fcmToken;
    } catch (e) {
      print('獲取 FCM Token 失敗: $e');
      return null;
    }
  }

  /// Token 刷新處理
  void _onTokenRefresh(String newToken) {
    _fcmToken = newToken;
    print('FCM Token 已刷新: $newToken');
    // 自動重新註冊裝置
    _reregisterDevice();
  }

  /// 重新註冊裝置（當 token 刷新時）
  void _reregisterDevice() {
    try {
      if (Get.isRegistered<DeviceRegistrationService>()) {
        final deviceRegistrationService = Get.find<DeviceRegistrationService>();
        deviceRegistrationService.registerDevice();
      } else {
        print('DeviceRegistrationService 尚未初始化，跳過重新註冊');
      }
    } catch (e) {
      print('重新註冊裝置失敗: $e');
    }
  }

  /// 手動獲取 FCM Token（公開方法）
  Future<String?> getToken() async {
    return await _getFcmToken();
  }

  /// 訂閱主題
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging!.subscribeToTopic(topic);
      print('已訂閱主題: $topic');
    } catch (e) {
      print('訂閱主題失敗: $e');
    }
  }

  /// 取消訂閱主題
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging!.unsubscribeFromTopic(topic);
      print('已取消訂閱主題: $topic');
    } catch (e) {
      print('取消訂閱主題失敗: $e');
    }
  }
}

