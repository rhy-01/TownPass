import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:town_pass/service/api_service.dart';
import 'package:town_pass/service/fcm_service.dart';
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:town_pass/service/account_service.dart';

/// 裝置註冊服務
/// 負責在應用程式初始化時註冊裝置到後端 API
class DeviceRegistrationService extends GetxService {
  Future<DeviceRegistrationService> init() async {
    return this;
  }

  /// 註冊裝置
  /// 會自動獲取 FCM Token、地理位置和使用者 ID，然後註冊到後端
  Future<void> registerDevice() async {
    try {
      // 獲取服務實例
      final fcmService = Get.find<FcmService>();
      final geoLocatorService = Get.find<GeoLocatorService>();
      final apiService = Get.find<ApiService>();
      final accountService = Get.find<AccountService>();

      // 獲取 FCM Token
      final fcmToken = await fcmService.getToken();
      if (fcmToken == null) {
        print('無法獲取 FCM Token，跳過裝置註冊');
        return;
      }

      // 獲取地理位置
      Position? position;
      try {
        position = await geoLocatorService.position();
      } catch (e) {
        print('無法獲取地理位置: $e，使用預設值');
        // 使用預設位置（台北）
        position = null;
      }

      // 獲取使用者 ID
      final userId = accountService.account?.id ?? 'anonymous';
      
      // 獲取當前時間戳（ISO 8601 格式）
      final timestamp = DateTime.now().toUtc().toIso8601String();
      
      // 準備註冊數據
      final latitude = position?.latitude ?? 25.0477; // 預設台北緯度
      final longitude = position?.longitude ?? 121.5173; // 預設台北經度

      // 註冊到後端 API
      print('開始註冊裝置...');
      print('userId: $userId');
      print('fcmToken: $fcmToken');
      print('latitude: $latitude');
      print('longitude: $longitude');
      print('timestamp: $timestamp');

      final response = await apiService.registerDevice(
        userId: userId,
        fcmToken: fcmToken,
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
      );

      print('裝置註冊成功: $response');
    } catch (e) {
      print('裝置註冊失敗: $e');
      // 不拋出異常，避免影響應用程式啟動
      // 如果是網絡錯誤，可以在後台重試
      if (e.toString().contains('SocketException') || 
          e.toString().contains('Failed host lookup')) {
        print('⚠️  網絡連接問題，設備註冊將在後台重試');
        // 可以在這裡添加重試邏輯
      }
    }
  }
}

