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
      // 檢查 Firebase 是否已經初始化
      // 如果已經初始化（例如在 Android 端自動初始化或在 main() 中初始化），就不需要再次初始化
      if (Firebase.apps.isEmpty) {
        print('🔄 FcmService: 初始化 Firebase...');
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          print('✅ FcmService: Firebase 初始化成功');
        } catch (e) {
          // 檢查是否為重複初始化錯誤
          if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
            print('✅ FcmService: Firebase 已經存在（可能在其他地方已初始化），繼續執行');
          } else {
            // 其他錯誤，重新拋出
            print('❌ FcmService: Firebase 初始化失敗: $e');
            rethrow;
          }
        }
      } else {
        print('✅ FcmService: Firebase 已經初始化（${Firebase.apps.length} 個應用），跳過初始化步驟');
      }

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
    final notification = message.notification;

    // 輸出訊息詳情
    print('=== 前景訊息處理器被觸發 ===');
    print('訊息數據: $data');
    print('通知標題: ${notification?.title}');
    print('通知內容: ${notification?.body}');

    // 從 data 字段讀取餐廳資訊（匹配 Python 後端發送的格式）
    final restaurantName = data['restaurant_name']?.toString();
    final regNo = data['restaurant_reg_no']?.toString();
    final lat = data['restaurant_latitude']?.toString();
    final lng = data['restaurant_longitude']?.toString();
    final status = data['restaurant_status']?.toString();
    final type = data['type']?.toString();
    // targetUrl 和 timestamp 保留供將來使用（例如導航到餐廳詳情頁）
    final targetUrl = data['targetUrl']?.toString();
    final timestamp = data['timestamp']?.toString();
    
    // 獲取 title 和 body（優先從 notification，否則從 data）
    String? title;
    String? body;
    
    if (notification?.title != null) {
      title = notification!.title;
      body = notification.body;
    } else if (data.containsKey('title')) {
      title = data['title']?.toString();
      body = data['body']?.toString();
    }
    
    print('📋 接收到的 FCM 訊息：');
    print('  餐廳名稱: $restaurantName');
    print('  登記號碼: $regNo');
    print('  經緯度: ($lat, $lng)');
    print('  狀態: $status');
    print('  類型: $type');
    print('  目標 URL: $targetUrl');
    print('  時間戳: $timestamp');
    print('  標題: $title');
    print('  內容: $body');

    // 檢查是否有經緯度（必要條件）
    if (lat != null && lng != null && lat.isNotEmpty && lng.isNotEmpty) {
      // 如果有經緯度，就顯示通知（無論 title 是否包含"不合格"）
      // 因為 Python 後端已經過濾了，只有不合格的才會發送
      if (title != null && title.isNotEmpty) {
        print('✅ 有經緯度且 title，將顯示通知');
        print('標題: $title');
        print('內容: ${body ?? "無內容"}');
        print('餐廳: $restaurantName');
        print('經緯度: ($lat, $lng)');
        
        // 顯示通知
        NotificationService.showNotification(
          title: title,
          content: body ?? '您有新的通知',
        );
        
        print('通知已顯示');
      } else {
        print('ℹ️  有經緯度但沒有 title，只輸出日志');
        print('完整訊息數據: $data');
      }
    } else {
      print('⚠️  沒有經緯度或經緯度為空，只輸出日志');
      print('完整訊息數據: $data');
      if (notification != null) {
        print('通知對象: $notification');
      }
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