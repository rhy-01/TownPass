import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:town_pass/service/account_service.dart';
import 'package:town_pass/service/geo_locator_service.dart';

/// 設備註冊服務：負責將 FCM Token 和定位資訊發送到後端 API
class DeviceRegistrationService extends GetxService {
  // TODO: 替換為您的 Cloud Run 'api-service' URL
  static const String apiBaseUrl = 'https://api-service-xxxxx-an.run.app';
  static const String registerDeviceEndpoint = '/api/register-device';

  /// 註冊設備：獲取 FCM Token 和定位，然後發送到後端
  Future<void> registerDevice() async {
    try {
      // 1. 請求 FCM 權限
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        print('FCM 權限被拒絕');
        return;
      }

      // 2. 取得 FCM Token
      String? fcmToken = await messaging.getToken();
      if (fcmToken == null) {
        print('Error: Could not get FCM Token.');
        return;
      }

      print('FCM Token: $fcmToken');

      // 3. 獲取地理定位
      Position? position;
      try {
        position = await Get.find<GeoLocatorService>().position();
      } catch (e) {
        print('Failed to get location: $e');
        // 定位失敗不影響註冊，繼續發送 Token
      }

      // 4. 獲取用戶 ID
      String? userId;
      try {
        final accountService = Get.find<AccountService>();
        userId = accountService.account?.id;
      } catch (e) {
        print('Failed to get user ID: $e');
      }

      // 5. 準備發送到後端的資料
      final payload = <String, dynamic>{
        if (userId != null) 'userId': userId,
        'fcmToken': fcmToken,
        if (position != null) 'latitude': position.latitude,
        if (position != null) 'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // 6. 發送 POST 請求給後端進行註冊
      final response = await http.post(
        Uri.parse('$apiBaseUrl$registerDeviceEndpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('設備註冊請求超時');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Device registration success. Token and Location updated.');
      } else {
        print(
            'Device registration failed. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      print('Network error during device registration: $e');
    }
  }

  /// 當 Token 更新時重新註冊
  void setupTokenRefreshListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('FCM Token refreshed: $newToken');
      registerDevice();
    });
  }
}

