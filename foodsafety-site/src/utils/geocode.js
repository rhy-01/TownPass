/**
 * 地址轉換為坐標的工具函數
 * 使用 OpenStreetMap Nominatim API
 */

import { addDebugLog } from "./debugLogger";

/**
 * 將地址轉換為經緯度
 * 使用 OpenStreetMap Nominatim API
 * @param {string} address - 地址字符串
 * @returns {Promise<Object|null>} 包含 lat 和 lng 的對象，失敗返回 null
 */
export async function geocodeAddress(address) {
  if (!address || !address.trim()) {
    return null;
  }

  try {
    const encodedAddress = encodeURIComponent(address);
    // 使用 Nominatim API（OpenStreetMap 的地理編碼服務）
    const url = `https://nominatim.openstreetmap.org/search?format=json&q=${encodedAddress}&limit=1&accept-language=zh-TW,zh,en&countrycodes=tw`;

    const response = await fetch(url, {
      headers: {
        "User-Agent": "TownPass-FoodSafety/1.0", // Nominatim 要求設置 User-Agent
      },
    });

    if (!response.ok) {
      throw new Error(`Geocoding API request failed: ${response.status}`);
    }

    const data = await response.json();

    if (data && data.length > 0) {
      const result = {
        lat: parseFloat(data[0].lat),
        lng: parseFloat(data[0].lon),
      };
      addDebugLog("log", "Address geocoded successfully", { address, ...result });
      return result;
    } else {
      addDebugLog("warn", "No results found for address", { address });
      return getFallbackCoordinates(address);
    }
  } catch (error) {
    addDebugLog("error", "Error geocoding address", { address, error: error.message });
    return getFallbackCoordinates(address);
  }
}

/**
 * 根據地址關鍵字返回預設坐標（fallback）
 * @param {string} address - 地址字符串
 * @returns {Object|null} 包含 lat 和 lng 的對象
 */
function getFallbackCoordinates(address) {
  // 簡單的地址關鍵字匹配
  const addressLower = address.toLowerCase();

  // 台北市區域
  if (addressLower.includes("信義") || addressLower.includes("松高")) {
    return { lat: 25.0409, lng: 121.5678 };
  }
  if (addressLower.includes("松山") || addressLower.includes("饒河")) {
    return { lat: 25.0510, lng: 121.5750 };
  }
  if (addressLower.includes("中正") || addressLower.includes("忠孝西路")) {
    return { lat: 25.0479, lng: 121.5170 };
  }
  if (addressLower.includes("大安") || addressLower.includes("復興南路")) {
    return { lat: 25.0330, lng: 121.5430 };
  }
  if (addressLower.includes("士林")) {
    return { lat: 25.0878, lng: 121.5269 };
  }

  // 台中市區域
  if (addressLower.includes("台中") || addressLower.includes("西屯") || addressLower.includes("逢甲")) {
    return { lat: 24.1790, lng: 120.6440 };
  }

  // 高雄市區域
  if (addressLower.includes("高雄") || addressLower.includes("前鎮")) {
    return { lat: 22.6273, lng: 120.3014 };
  }

  // 預設返回台北101
  return { lat: 25.0330, lng: 121.5654 };
}
