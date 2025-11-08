// File generated from google-services.json for Firebase initialization
// 現在從 .env 文件讀取配置

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
/// 從 .env 文件讀取配置值
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  /// 從 .env 文件讀取 Firebase 配置
  /// 如果 .env 中沒有值，則使用預設值（從 google-services.json）
  static FirebaseOptions get android {
    // 從 .env 讀取，如果沒有則使用預設值
    final apiKey = dotenv.env['FIREBASE_API_KEY'] ?? 
        'AIzaSyDWW0pJe3w6VT4trEJsTlGgPzd6HymtlFE';
    final appId = dotenv.env['FIREBASE_APP_ID'] ?? 
        '1:745797496080:android:e86db6c434affd63a50995';
    final messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? 
        '745797496080';
    final projectId = dotenv.env['FIREBASE_PROJECT_ID'] ?? 
        'micro-service-477116';
    final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? 
        'micro-service-477116.firebasestorage.app';

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket,
    );
  }
}


