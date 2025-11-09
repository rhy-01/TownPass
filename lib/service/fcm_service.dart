import 'dart:async';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:town_pass/firebase_options.dart';
import 'package:town_pass/service/device_registration_service.dart';
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:town_pass/service/notification_service.dart';

/// Firebase Cloud Messaging 服務
/// 負責處理 FCM 的初始化、token 獲取、訊息接收等功能
class FcmService extends GetxService {
  // 預設參考座標：北緯 25.018 度，東經 121.535 度（如果無法獲取用戶位置時使用）
  static const double _defaultReferenceLatitude = 25.018;
  static const double _defaultReferenceLongitude = 121.535;
  // 通知範圍：10 公里
  static const double _notificationRadiusKm = 10.0;
  FirebaseMessaging? _firebaseMessaging;
  String? _fcmToken;
  
  // 用戶當前位置（緩存）
  Position? _userPosition;
  DateTime? _positionCacheTime;
  static const Duration _positionCacheDuration = Duration(minutes: 5); // 位置緩存 5 分鐘
  
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
    // iOS 和 Web 平台需要請求通知權限
    if (!kIsWeb) {
      // 移動平台（Android/iOS）
      // Android 通知權限在運行時自動請求
      // iOS 需要明確請求
      try {
        // 檢查是否為 iOS（通過檢查平台特徵）
        final settings = await _firebaseMessaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          print('⚠️  使用者未授權通知權限');
        }
      } catch (e) {
        // 如果不是 iOS 或發生錯誤，忽略
        print('通知權限請求: $e');
      }
    } else {
      // Web 平台：通知權限通過瀏覽器 API 處理
      // FCM 會在需要時自動請求權限
      print('ℹ️  Web 平台：通知權限由瀏覽器處理');
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
  Future<void> _handleMessage(RemoteMessage message) async {
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
      try {
        // 將字串轉換為數字
        final restaurantLat = double.tryParse(lat);
        final restaurantLng = double.tryParse(lng);
        
        if (restaurantLat != null && restaurantLng != null) {
          // 獲取用戶當前位置（用於距離計算）
          final userPosition = await _getUserPosition();
          final referenceLat = userPosition?.latitude ?? _defaultReferenceLatitude;
          final referenceLng = userPosition?.longitude ?? _defaultReferenceLongitude;
          final isUsingDefaultLocation = userPosition == null;
          
          // 計算餐廳與用戶位置的距離
          final distanceKm = _calculateDistance(
            referenceLat,
            referenceLng,
            restaurantLat,
            restaurantLng,
          );
          
          print('📍 餐廳座標: ($restaurantLat, $restaurantLng)');
          if (isUsingDefaultLocation) {
            print('📍 使用預設參考座標: ($referenceLat, $referenceLng)');
            print('ℹ️  無法獲取用戶位置，使用預設座標進行距離計算');
          } else {
            print('📍 用戶當前位置: ($referenceLat, $referenceLng)');
          }
          print('📏 距離: ${distanceKm.toStringAsFixed(2)} 公里');
          
          // 只在 10 公里範圍內才顯示通知
          if (distanceKm <= _notificationRadiusKm) {
            print('✅ 餐廳在 ${_notificationRadiusKm} 公里範圍內，顯示通知');
            NotificationService.showNotification(
              title: title,
              content: body ?? '您有新的通知',
            );
          } else {
            print('⚠️  餐廳距離 ${distanceKm.toStringAsFixed(2)} 公里，超出 ${_notificationRadiusKm} 公里範圍，不顯示通知');
          }
        } else {
          print('⚠️  無法解析經緯度數值: lat=$lat, lng=$lng');
        }
      } catch (e) {
        print('❌ 計算距離時發生錯誤: $e');
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

  /// 計算兩點之間的距離（使用 Haversine 公式）
  /// 返回距離（單位：公里）
  /// [lat1] 第一個點的緯度
  /// [lon1] 第一個點的經度
  /// [lat2] 第二個點的緯度
  /// [lon2] 第二個點的經度
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0; // 地球半徑（公里）
    
    // 將度數轉換為弧度
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final double distance = earthRadiusKm * c;
    
    return distance;
  }

  /// 將度數轉換為弧度
  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }

  /// 獲取用戶當前位置
  /// 優先使用緩存的位置（如果緩存未過期），否則嘗試獲取新位置
  /// 返回 null 如果無法獲取位置（會使用預設座標）
  Future<Position?> _getUserPosition() async {
    try {
      // 檢查緩存是否有效
      if (_userPosition != null && 
          _positionCacheTime != null &&
          DateTime.now().difference(_positionCacheTime!) < _positionCacheDuration) {
        print('✅ 使用緩存的用戶位置');
        return _userPosition;
      }

      // 嘗試獲取 GeoLocatorService
      if (!Get.isRegistered<GeoLocatorService>()) {
        print('⚠️  GeoLocatorService 未註冊，無法獲取用戶位置');
        return null;
      }

      final geoLocatorService = Get.find<GeoLocatorService>();
      
      // 請求定位權限並獲取位置
      try {
        final position = await geoLocatorService.position();
        _userPosition = position;
        _positionCacheTime = DateTime.now();
        print('✅ 成功獲取用戶位置: (${position.latitude}, ${position.longitude})');
        return position;
      } catch (e) {
        print('⚠️  獲取用戶位置失敗: $e');
        print('ℹ️  將使用預設參考座標進行距離計算');
        return null;
      }
    } catch (e) {
      print('❌ 獲取用戶位置時發生錯誤: $e');
      return null;
    }
  }

  /// 清除位置緩存（強制重新獲取位置）
  void clearPositionCache() {
    _userPosition = null;
    _positionCacheTime = null;
    print('🗑️  位置緩存已清除');
  }

  /// 手動更新用戶位置
  Future<Position?> updateUserPosition() async {
    clearPositionCache();
    return await _getUserPosition();
  }
}