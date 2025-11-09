import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';

class GeocodingService extends GetxService {
  Future<GeocodingService> init() async {
    return this;
  }

  /// 將經緯度轉換為地址（逆地理編碼）
  /// 使用 OpenStreetMap Nominatim API
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1&accept-language=zh-TW,zh,en',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'TownPass-FoodSafety/1.0',
        },
      );

      if (response.statusCode != 200) {
        printError(info: 'Geocoding API request failed: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data.containsKey('address')) {
        // 構建台灣地址格式
        final addr = data['address'] as Map<String, dynamic>;
        final addressParts = <String>[];

        // 台灣地址順序: 城市 -> 區 -> 里 -> 路/街 -> 號
        if (addr['city'] != null) {
          addressParts.add(addr['city'] as String);
        } else if (addr['town'] != null) {
          addressParts.add(addr['town'] as String);
        } else if (addr['city_district'] != null) {
          addressParts.add(addr['city_district'] as String);
        }

        if (addr['suburb'] != null) {
          addressParts.add(addr['suburb'] as String);
        } else if (addr['district'] != null) {
          addressParts.add(addr['district'] as String);
        } else if (addr['township'] != null) {
          addressParts.add(addr['township'] as String);
        }

        if (addr['road'] != null) {
          addressParts.add(addr['road'] as String);
        } else if (addr['street'] != null) {
          addressParts.add(addr['street'] as String);
        }

        if (addr['house_number'] != null) {
          addressParts.add(addr['house_number'] as String);
        }

        if (addressParts.isNotEmpty) {
          return addressParts.join('');
        }
      }

      // 如果無法構建地址，使用 display_name
      if (data.containsKey('display_name')) {
        return data['display_name'] as String;
      }

      // 如果都失敗，返回經緯度
      return '$latitude, $longitude';
    } catch (error) {
      printError(info: 'Error reverse geocoding: $error');
      return null;
    }
  }
}