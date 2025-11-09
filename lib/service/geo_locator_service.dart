import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

class GeoLocatorService extends GetxService {
  Future<GeoLocatorService> init() async {
    return this;
  }

  /// 獲取當前位置
  /// 支持 Android、iOS 和 Web 平台
  Future<Position> position() async {
    // Web 平台的處理
    if (kIsWeb) {
      return _getWebPosition();
    }
    
    // Android/iOS 平台的處理
    return _getMobilePosition();
  }

  /// Web 平台的定位處理
  Future<Position> _getWebPosition() async {
    try {
      // 在 Web 上，檢查定位服務是否可用
      // 注意：Web 上 isLocationServiceEnabled() 可能不準確，直接嘗試獲取位置
      
      // 檢查權限狀態
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        // 請求權限（會觸發瀏覽器的原生權限對話框）
        permission = await Geolocator.requestPermission();
        
        if (permission == LocationPermission.denied) {
          return Future.error('使用者未允許定位權限，請在瀏覽器設定中允許定位權限');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return Future.error('定位權限已被永久拒絕，請在瀏覽器設定中手動允許定位權限');
      }

      // 在 Web 上獲取位置
      // 設置適當的位置設置以獲得更好的精度
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Web 上可以設置超時時間
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      print('❌ Web 平台獲取位置失敗: $e');
      return Future.error('無法獲取位置: $e');
    }
  }

  /// Android/iOS 平台的定位處理
  Future<Position> _getMobilePosition() async {
    try {
      // 檢查定位服務是否啟用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return Future.error('未開啟定位服務，請在設定中開啟定位服務');
      }

      // 檢查權限狀態
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // 請求權限
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return Future.error('使用者未允許定位權限');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return Future.error('使用者未允許定位權限（永久），請在設定中手動允許定位權限');
      }

      // 獲取當前位置
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      print('❌ 移動平台獲取位置失敗: $e');
      return Future.error('無法獲取位置: $e');
    }
  }

  /// 檢查定位服務是否可用
  Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) {
      // Web 平台上，直接返回 true（瀏覽器會處理）
      return true;
    }
    return await Geolocator.isLocationServiceEnabled();
  }

  /// 檢查定位權限狀態
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// 請求定位權限
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// 打開定位設定頁面（僅移動平台）
  Future<bool> openLocationSettings() async {
    if (kIsWeb) {
      print('⚠️  Web 平台不支持打開設定頁面');
      return false;
    }
    return await Geolocator.openLocationSettings();
  }

  /// 打開應用設定頁面（僅移動平台）
  Future<bool> openAppSettings() async {
    if (kIsWeb) {
      print('⚠️  Web 平台不支持打開應用設定頁面');
      return false;
    }
    return await Geolocator.openAppSettings();
  }
}
