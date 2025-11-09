import 'dart:io';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:town_pass/firebase_options.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/service/account_service.dart';
import 'package:town_pass/service/api_service.dart';
import 'package:town_pass/service/device_registration_service.dart';
import 'package:town_pass/service/device_service.dart';
import 'package:town_pass/service/fcm_service.dart';
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:town_pass/service/notification_service.dart';
import 'package:town_pass/service/package_service.dart';
import 'package:town_pass/service/shared_preferences_service.dart';
import 'package:town_pass/service/subscription_service.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';

// 預設參考座標：北緯 25.018 度，東經 121.535 度（如果無法獲取用戶位置時使用）
const double _defaultReferenceLatitude = 25.018;
const double _defaultReferenceLongitude = 121.535;
// 通知範圍：10 公里
const double _notificationRadiusKm = 10.0;

const _transparentStatusBar = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
);

/// 背景訊息處理器（必須是頂層函數，在 main() 之前定義）
/// 當應用程式完全關閉時，這個處理器會被調用以處理 FCM 訊息
/// 
/// 注意：這個函數會在單獨的 isolate 中運行，不能訪問 GetX 服務或其他應用程式狀態
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 在背景 isolate 中也載入 .env 文件
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    print('⚠️  背景處理器無法載入 .env 文件: $e');
    // 繼續執行，將使用預設值
  }
  
  // 必須先初始化 Firebase（在背景 isolate 中）
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 輸出訊息詳情（用於除錯）
  print('=== 背景訊息處理器被觸發 ===');
  print('訊息 ID: ${message.messageId}');
  print('訊息時間: ${message.sentTime}');
  print('訊息數據: ${message.data}');
  print('通知標題: ${message.notification?.title}');
  print('通知內容: ${message.notification?.body}');
  
  // 從 data 字段讀取餐廳資訊（匹配 Python 後端發送的格式）
  final data = message.data;
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
  
  if (message.notification?.title != null) {
    title = message.notification!.title;
    body = message.notification!.body;
  } else if (data.containsKey('title')) {
    title = data['title']?.toString();
    body = data['body']?.toString();
  }
  
  print('📋 接收到的 FCM 訊息（背景）：');
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
        // 嘗試獲取用戶當前位置（用於距離計算）
        // 注意：在背景處理器中，我們直接使用 geolocator，不依賴 GetX 服務
        Position? userPosition;
        try {
          userPosition = await _getUserPositionInBackground();
        } catch (e) {
          print('⚠️  背景處理器無法獲取用戶位置: $e');
        }
        
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
          if (title != null && title.isNotEmpty) {
            print('✅ 餐廳在 ${_notificationRadiusKm} 公里範圍內，顯示通知');
            print('標題: $title');
            print('內容: ${body ?? "無內容"}');
            print('餐廳: $restaurantName');
            print('經緯度: ($lat, $lng)');
            
            // 在背景處理器中顯示通知
            await _showBackgroundNotification(title, body ?? '您有新的通知');
            
            print('通知已顯示');
          } else {
            print('ℹ️  餐廳在範圍內但沒有 title，只輸出日志');
            print('完整數據: ${message.data}');
          }
        } else {
          print('⚠️  餐廳距離 ${distanceKm.toStringAsFixed(2)} 公里，超出 ${_notificationRadiusKm} 公里範圍，不顯示通知');
        }
      } else {
        print('⚠️  無法解析經緯度數值: lat=$lat, lng=$lng');
      }
    } catch (e) {
      print('❌ 計算距離時發生錯誤: $e');
      print('完整數據: ${message.data}');
    }
  } else {
    print('⚠️  沒有經緯度或經緯度為空，只輸出日志');
    print('完整數據: ${message.data}');
    if (message.notification != null) {
      print('通知對象: ${message.notification}');
    }
  }
  
  print('=== 背景訊息處理完成 ===');
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

/// 在背景處理器中獲取用戶位置
/// 注意：這個函數在獨立的 isolate 中運行，不能使用 GetX 服務
Future<Position?> _getUserPositionInBackground() async {
  try {
    if (kIsWeb) {
      // Web 平台：檢查權限並獲取位置
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️  Web 平台：定位權限被拒絕');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('⚠️  Web 平台：定位權限被永久拒絕');
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5), // 背景處理器中使用較短的超時時間
        ),
      );
    } else {
      // 移動平台：檢查定位服務和權限
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️  定位服務未開啟');
        return null;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️  定位權限被拒絕');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('⚠️  定位權限被永久拒絕');
        return null;
      }
      
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    }
  } catch (e) {
    print('❌ 背景處理器獲取位置失敗: $e');
    return null;
  }
}

/// 在背景處理器中顯示通知
/// 注意：這個函數運行在單獨的 isolate 中，需要單獨初始化通知服務
/// 在背景 isolate 中不能請求權限，所以需要確保應用程式啟動時已經授予權限
Future<void> _showBackgroundNotification(String title, String body) async {
  try {
    // 初始化通知插件（在背景 isolate 中需要單獨初始化）
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    // Android 初始化設置
    const androidInitializationSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS 初始化設置
    const iosInitializationSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    
    // 初始化設置
    const initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );
    
    // 初始化通知插件
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    
    // 注意：在背景 isolate 中不能請求權限
    // 所以不調用 requestNotificationsPermission()
    // 需要確保應用程式啟動時已經授予通知權限
    
    // 創建通知通道（Android 8.0+）
    if (Platform.isAndroid) {
      final androidImplementation = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      // 創建通知通道（如果不存在）
      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          'TownPass android notification id',
          'TownPass android notification channel name',
          description: 'TownPass 通知通道',
          importance: Importance.max,
        ),
      );
    }
    
    // 顯示通知
    const androidDetails = AndroidNotificationDetails(
      'TownPass android notification id',
      'TownPass android notification channel name',
      channelDescription: 'TownPass 通知通道',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
    );
    
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    
    // 使用時間戳作為通知 ID，確保每條通知都是唯一的
    final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
    );
    
    print('✅ 背景通知已成功顯示');
  } catch (e, stackTrace) {
    print('❌ 顯示背景通知失敗: $e');
    print('堆疊追蹤: $stackTrace');
    // 即使通知顯示失敗，也不影響其他邏輯
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 載入 .env 文件
  try {
    await dotenv.load(fileName: '.env');
    print('✅ .env 文件載入成功');
  } catch (e) {
    print('⚠️  無法載入 .env 文件: $e');
    print('將使用預設的 Firebase 配置值');
  }
  
  // 初始化 Firebase（在主線程中）
  // 嘗試初始化 Firebase，如果已經初始化則忽略錯誤
  try {
    if (Firebase.apps.isEmpty) {
      print('🔄 初始化 Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase 初始化成功');
    } else {
      print('✅ Firebase 已經初始化（${Firebase.apps.length} 個應用）');
    }
  } catch (e) {
    // 檢查是否為重複初始化錯誤
    if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
      print('✅ Firebase 已經存在（可能在其他地方已初始化），繼續執行');
    } else {
      // 其他錯誤，重新拋出
      print('❌ Firebase 初始化失敗: $e');
      rethrow;
    }
  }
  
  // 重要：必須在任何 Firebase 操作之前註冊背景訊息處理器
  // 這樣當應用程式關閉時，FCM 訊息仍能被處理
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  // FlutterNativeSplash.preserve(
  //   widgetsBinding: WidgetsFlutterBinding.ensureInitialized(),
  // );

  await initServices();

  // 註冊裝置
  await registerDevice();

  SystemChrome.setSystemUIOverlayStyle(_transparentStatusBar);

  runApp(const MyApp());
}

Future<void> initServices() async {
  await Get.putAsync<AccountService>(() async => await AccountService().init());
  await Get.putAsync<DeviceService>(() async => await DeviceService().init());
  await Get.putAsync<PackageService>(() async => await PackageService().init());
  await Get.putAsync<SharedPreferencesService>(() async => await SharedPreferencesService().init());
  await Get.putAsync<GeoLocatorService>(() async => await GeoLocatorService().init());
  await Get.putAsync<NotificationService>(() async => await NotificationService().init());
  
  // 初始化 API 服務
  await Get.putAsync<ApiService>(() async => await ApiService().init());
  
  // 初始化 FCM 服務（必須在 Firebase 初始化之後）
  await Get.putAsync<FcmService>(() async => await FcmService().init());
  
  // 初始化裝置註冊服務
  await Get.putAsync<DeviceRegistrationService>(() async => await DeviceRegistrationService().init());

  Get.put<SubscriptionService>(SubscriptionService());
}

/// 註冊裝置到後端 API
Future<void> registerDevice() async {
  try {
    final deviceRegistrationService = Get.find<DeviceRegistrationService>();
    await deviceRegistrationService.registerDevice();
  } catch (e) {
    print('註冊裝置時發生錯誤: $e');
    // 不拋出異常，避免影響應用程式啟動
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Town Pass',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: TPColors.grayscale50,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: TPColors.white,
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: TPColors.primary500),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0.0,
          iconTheme: IconThemeData(size: 56),
          actionsIconTheme: IconThemeData(size: 56),
        ),
        actionIconTheme: ActionIconThemeData(
          backButtonIconBuilder: (_) => Semantics(
            excludeSemantics: true,
            child: Assets.svg.iconArrowLeft.svg(width: 24, height: 24),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: TPRoute.main,
      onInit: () {
        NotificationService.requestPermission();
      },
      getPages: TPRoute.page,
    );
  }
}