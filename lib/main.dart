import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

const _transparentStatusBar = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
);

/// 背景訊息處理器（必須是頂層函數，在 main() 之前定義）
/// 當應用程式完全關閉時，這個處理器會被調用以處理 FCM 訊息
/// 
/// 注意：這個函數會在單獨的 isolate 中運行，不能訪問 GetX 服務或其他應用程式狀態
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 必須先初始化 Firebase（在背景 isolate 中）
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 輸出訊息詳情（用於除錯）
  print('=== 背景訊息處理器被觸發 ===');
  print('訊息 ID: ${message.messageId}');
  print('訊息時間: ${message.sentTime}');
  print('訊息數據: ${message.data}');
  
  // 決策邏輯：檢查 title 欄位是否為 '1'
  final data = message.data;
  final title = data['title'];
  
  // 輸出接收到的 title
  print('接收到的 title: $title');
  
  // 如果 title 是 '1'，就發出通知
  if (title == '1') {
    print('✅ title 是 "1"，將顯示通知');
    
    // 獲取通知內容（使用 body 作為通知內容）
    final notificationBody = data['body'] ?? '通知';
    
    // 在背景處理器中顯示通知
    // 需要單獨初始化 FlutterLocalNotificationsPlugin
    await _showBackgroundNotification('通知', notificationBody);
    
    print('通知已顯示');
  } else {
    // 如果 title 不是 '1'，就只在 log 輸出
    print('❌ title 不是 "1" ($title)，只輸出日志，不顯示通知');
    print('完整數據: $data');
  }
  
  print('=== 背景訊息處理完成 ===');
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