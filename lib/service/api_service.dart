import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';

class ApiService extends GetxService {
  static const String baseUrl = 'https://api-service-745797496080.asia-east1.run.app';
  
  Future<ApiService> init() async {
    return this;
  }

  /// 註冊裝置到後端 API
  /// 
  /// [userId] 使用者 ID
  /// [fcmToken] FCM Token
  /// [latitude] 緯度
  /// [longitude] 經度
  /// [timestamp] 時間戳 (ISO 8601 格式)
  Future<Map<String, dynamic>> registerDevice({
    required String userId,
    required String fcmToken,
    required double latitude,
    required double longitude,
    required String timestamp,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/register-device');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': userId,
          'fcmToken': fcmToken,
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': timestamp,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to register device: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error registering device: $e');
    }
  }
}




