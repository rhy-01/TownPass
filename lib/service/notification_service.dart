import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

/// 頂層函數：處理 App 在背景或關閉時收到的訊息
/// 必須在頂層定義，不能是類別方法
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("處理背景 FCM 訊息: ${message.messageId}");
  print("背景訊息標題: ${message.notification?.title}");
  print("背景訊息內容: ${message.notification?.body}");
  print("背景訊息資料: ${message.data}");
  // FCM 會自動顯示通知，無需在這裡觸發本地通知
}

class NotificationService extends GetxService {
  static int _id = 0;
  static final FlutterLocalNotificationsPlugin _notificationInstance =
      FlutterLocalNotificationsPlugin();

  // FCM 通知渠道 ID（必須與 AndroidManifest.xml 中的一致）
  static const String _channelId = 'high_importance_channel';
  static const String _channelName = '高重要性通知';
  static const String _channelDescription = '用於重要的業務更新通知';

  Future<NotificationService> init() async {
    await _notificationInstance.getNotificationAppLaunchDetails();

    // Android 設置
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS 設置
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationInstance.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null) {
          print('Notification Tapped! Payload: ${response.payload}');
          // TODO: 在這裡處理通知點擊事件，例如導航到特定頁面
          // 可以使用 Get.toNamed() 或 Get.find<WebViewController>().loadUrl()
        }
      },
    );

    // 為 Android 創建通知渠道
    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }

    // 設定 FCM 訊息監聽
    _setupFCMListeners();

    return this;
  }

  /// 創建 Android 通知渠道
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    await _notificationInstance
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      await _notificationInstance
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _notificationInstance
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  static Future<void> showNotification({
    String? title,
    String? content,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationInstance.show(
      _id++,
      title,
      content,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  /// 設定 FCM 訊息監聽
  void _setupFCMListeners() {
    // 監聽 App 在前景時收到的訊息
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('App 在前景時收到訊息: ${message.notification?.title}');
      print('訊息資料: ${message.data}');

      // App 在前景時，手動觸發本地通知
      RemoteNotification? notification = message.notification;

      if (notification != null) {
        // 使用 FCM data payload 作為本地通知的 payload (targetUrl)
        showNotification(
          title: notification.title ?? "新通知",
          content: notification.body ?? "您有新的更新內容",
          payload: message.data['targetUrl'], // 從後端 data 字段獲取跳轉 URL
        );
      }
    });

    // 監聽用戶點擊通知開啟 App 的事件 (App 從背景/關閉狀態進入前景)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('用戶點擊通知開啟 App: ${message.data}');
      _handleNotificationClick(message.data);
    });

    // 處理 App 關閉或背景時用戶點擊通知的事件
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('App 啟動時由通知觸發: ${message.data}');
        _handleNotificationClick(message.data);
      }
    });
  }

  /// 處理通知點擊事件
  void _handleNotificationClick(Map<String, dynamic> data) {
    // TODO: 在這裡處理通知點擊後的導航邏輯
    // 例如：如果 data 包含 'targetUrl'，可以導航到該 URL
    if (data.containsKey('targetUrl')) {
      final String targetUrl = data['targetUrl'];
      print('導航到: $targetUrl');
      // 可以使用 Get.toNamed() 或 Get.find<WebViewController>().loadUrl()
    }
  }
}
