/**
 * Two-Way Connection工具函數
 * 用於與Flutter App進行通信
 */

// 存儲pending的請求，key為請求ID，value為Promise的resolve和reject函數
const pendingRequests = new Map();
let requestIdCounter = 0;

/**
 * 初始化Flutter Bridge
 * 設置消息監聽器來接收App的回復
 */
export function initFlutterBridge() {
  console.log('[Two-Way Connection] 🔧 初始化 Flutter Bridge...');
  
  // 檢查是否在App環境中
  if (typeof window === 'undefined' || typeof window.flutterObject === 'undefined') {
    console.warn('[Two-Way Connection] ⚠️ Flutter bridge not available - running outside of app');
    console.log('[Two-Way Connection] Debug info:', {
      hasWindow: typeof window !== 'undefined',
      hasFlutterObject: typeof window !== 'undefined' && typeof window.flutterObject !== 'undefined'
    });
    return false;
  }

  console.log('[Two-Way Connection] ✅ Window 和 flutterObject 可用');
  console.log('[Two-Way Connection] flutterObject:', window.flutterObject);

  if (window.addEventListener && !window._flutterBridgeInitialized) {
    console.log('[Two-Way Connection] 📡 設置 message 事件監聽器');
    window.addEventListener('message', handleFlutterMessage, false);
    window._flutterBridgeInitialized = true;
    console.log('[Two-Way Connection] ✅ Message 監聽器已設置');
  } else {
    console.log('[Two-Way Connection] ℹ️ Message 監聽器已存在或無法設置');
  }

  // 方法2: 如果flutterObject支持onmessage，也設置它
  // 注意：這取決於flutter_inappwebview的實際實現
  try {
    if (window.flutterObject && typeof window.flutterObject.onmessage === 'undefined') {
      console.log('[Two-Way Connection] ℹ️ flutterObject.onmessage 未定義');
      // 某些版本的flutter_inappwebview可能會通過這種方式返回回復
      // 我們暫時不設置，因為可能會干擾其他功能
    } else if (window.flutterObject && typeof window.flutterObject.onmessage !== 'undefined') {
      console.log('[Two-Way Connection] ℹ️ flutterObject.onmessage 已存在');
    }
  } catch (e) {
    console.error('[Two-Way Connection] ❌ 檢查 flutterObject.onmessage 時出錯:', e);
  }

  console.log('[Two-Way Connection] ✅ Flutter Bridge 初始化完成');
  return true;
}

/**
 * 處理來自Flutter App的消息回復
 * 根據flutter_inappwebview的實現，回復會通過WebMessageListener的replyProxy返回
 * 我們需要使用一個全局的回調機制來接收回復
 */
function handleFlutterMessage(event) {
  console.log('[Two-Way Connection] 📨 收到 message 事件');
  console.log('[Two-Way Connection] Event 詳情:', {
    type: event.type,
    origin: event.origin,
    source: event.source,
    data: event.data,
    dataType: typeof event.data
  });

  try {
    // 檢查消息是否來自Flutter
    if (!event.data) {
      console.log('[Two-Way Connection] ⚠️ Event 沒有 data，忽略');
      return;
    }

    let response;
    if (typeof event.data === 'string') {
      console.log('[Two-Way Connection] 🔍 嘗試解析 JSON 字符串:', event.data);
      try {
        response = JSON.parse(event.data);
        console.log('[Two-Way Connection] ✅ JSON 解析成功:', response);
      } catch (e) {
        console.log('[Two-Way Connection] ⚠️ JSON 解析失敗，忽略:', e.message);
        // 如果不是JSON，可能是直接的消息
        return;
      }
    } else if (typeof event.data === 'object') {
      console.log('[Two-Way Connection] ✅ Event data 是對象:', event.data);
      response = event.data;
    } else {
      console.log('[Two-Way Connection] ⚠️ Event data 類型不支持:', typeof event.data);
      return;
    }

    // 檢查是否是Flutter的回復（包含name和data字段）
    if (response && response.name && typeof response.name === 'string') {
      console.log('[Two-Way Connection] 🔍 查找匹配的請求 - 方法名:', response.name);
      console.log('[Two-Way Connection] 當前 pending 請求數量:', pendingRequests.size);
      console.log('[Two-Way Connection] 當前 pending 請求:', Array.from(pendingRequests.entries()).map(([id, data]) => ({
        requestId: id,
        methodName: data.methodName,
        timestamp: data.timestamp
      })));

      // 查找對應的pending request（找到最舊的匹配請求）
      let matchedRequest = null;
      let oldestTimestamp = Infinity;
      
      for (const [requestId, requestData] of pendingRequests.entries()) {
        if (requestData.methodName === response.name && requestData.timestamp < oldestTimestamp) {
          oldestTimestamp = requestData.timestamp;
          matchedRequest = { requestId, requestData };
          console.log('[Two-Way Connection] ✅ 找到匹配請求:', {
            requestId,
            methodName: requestData.methodName,
            timestamp: requestData.timestamp
          });
        }
      }

      if (matchedRequest) {
        const { requestId, requestData } = matchedRequest;
        console.log('[Two-Way Connection] 🎯 處理匹配請求:', {
          requestId,
          methodName: requestData.methodName,
          responseData: response.data
        });
        // 清除超時
        if (requestData.timeout) {
          clearTimeout(requestData.timeout);
          console.log('[Two-Way Connection] ⏱️ 清除超時計時器');
        }
        // 移除pending request
        pendingRequests.delete(requestId);
        console.log('[Two-Way Connection] ✅ 移除 pending 請求，當前數量:', pendingRequests.size);
        // 解析Promise
        console.log('[Two-Way Connection] ✅ 解析 Promise，返回數據:', response.data);
        requestData.resolve(response.data);
      } else {
        console.log('[Two-Way Connection] ⚠️ 沒有找到匹配的請求');
        console.log('[Two-Way Connection] 響應方法名:', response.name);
        console.log('[Two-Way Connection] 響應數據:', response.data);
      }
    } else {
      console.log('[Two-Way Connection] ⚠️ 響應格式不正確，缺少 name 字段');
      console.log('[Two-Way Connection] 響應對象:', response);
    }
  } catch (error) {
    console.error('[Two-Way Connection] ❌ 處理 Flutter message 時出錯:', error);
    console.error('[Two-Way Connection] 錯誤堆疊:', error.stack);
  }
}

// 注意：根據flutter_inappwebview的實現，回復可能通過不同的方式返回
// 我們在initFlutterBridge中設置監聽器，這裡只是確保在模塊加載時就有監聽器

/**
 * 調用Flutter App方法
 * 根據flutter_inappwebview的WebMessageListener機制，回復會通過replyProxy返回
 * 我們需要設置一個機制來接收回復
 * @param {string} methodName - 方法名稱 (如 'location', 'userinfo')
 * @param {any} data - 要傳遞的數據
 * @returns {Promise} 返回App的回復數據
 */
export function callFlutterMethod(methodName, data = null) {
  console.log('[Two-Way Connection] 🚀 調用 Flutter 方法:', methodName);
  console.log('[Two-Way Connection] 請求數據:', data);
  
  return new Promise((resolve, reject) => {
    // 檢查是否在App環境中
    if (typeof window === 'undefined' || typeof window.flutterObject === 'undefined') {
      const error = new Error('Flutter bridge not available - not running in app environment');
      console.error('[Two-Way Connection] ❌', error.message);
      console.log('[Two-Way Connection] Debug info:', {
        hasWindow: typeof window !== 'undefined',
        hasFlutterObject: typeof window !== 'undefined' && typeof window.flutterObject !== 'undefined'
      });
      reject(error);
      return;
    }

    try {
      // 創建請求對象
      const request = {
        name: methodName,
        data: data
      };

      // 為每個請求創建一個唯一標識
      const requestId = `${methodName}_${Date.now()}_${requestIdCounter++}`;
      const timestamp = Date.now();
      
      console.log('[Two-Way Connection] 📝 創建請求:', {
        requestId,
        methodName,
        data,
        timestamp
      });
      
      // 存儲resolve和reject函數
      const timeout = setTimeout(() => {
        if (pendingRequests.has(requestId)) {
          console.error('[Two-Way Connection] ⏱️ 請求超時:', {
            requestId,
            methodName,
            timeout: '10 seconds'
          });
          pendingRequests.delete(requestId);
          reject(new Error(`Flutter method ${methodName} timed out after 10 seconds`));
        }
      }, 10000); // 10秒超時

      pendingRequests.set(requestId, {
        resolve: (responseData) => {
          console.log('[Two-Way Connection] ✅ 請求成功:', {
            requestId,
            methodName,
            responseData
          });
          clearTimeout(timeout);
          resolve(responseData);
        },
        reject: (error) => {
          console.error('[Two-Way Connection] ❌ 請求失敗:', {
            requestId,
            methodName,
            error: error.message
          });
          clearTimeout(timeout);
          reject(error);
        },
        methodName,
        timestamp,
        timeout
      });

      console.log('[Two-Way Connection] 📤 準備發送消息到 Flutter');
      console.log('[Two-Way Connection] 請求對象:', request);
      console.log('[Two-Way Connection] 序列化後的請求:', JSON.stringify(request));
      console.log('[Two-Way Connection] flutterObject:', window.flutterObject);
      console.log('[Two-Way Connection] flutterObject.postMessage:', typeof window.flutterObject.postMessage);

      // 發送消息給Flutter App
      // 根據flutter_inappwebview的文檔，postMessage需要傳遞字符串
      // Flutter的WebMessageListener會通過replyProxy.postMessage()回復
      // 回復應該能夠通過某種機制返回到這裡
      window.flutterObject.postMessage(JSON.stringify(request));

      console.log('[Two-Way Connection] ✅ 消息已發送');
      console.log('[Two-Way Connection] 當前 pending 請求數量:', pendingRequests.size);

      // 注意：根據flutter_inappwebview的實現，回復可能會通過以下方式之一返回：
      // 1. 通過window.message事件
      // 2. 通過postMessage的返回值（如果支持）
      // 3. 通過一個回調機制
      // 我們已經在initFlutterBridge中設置了message事件監聽器

    } catch (error) {
      // 如果發送消息失敗，立即reject
      console.error('[Two-Way Connection] ❌ 發送消息時出錯:', error);
      console.error('[Two-Way Connection] 錯誤堆疊:', error.stack);
      reject(error);
    }
  });
}

/**
 * 獲取用戶信息
 * @returns {Promise<Object>} 用戶信息對象
 */
export async function getUserInfo() {
  console.log('[Two-Way Connection] 👤 獲取用戶信息');
  try {
    const userInfo = await callFlutterMethod('userinfo', null);
    console.log('[Two-Way Connection] ✅ 用戶信息獲取成功:', userInfo);
    return userInfo;
  } catch (error) {
    console.error('[Two-Way Connection] ❌ 獲取用戶信息失敗:', error);
    console.error('[Two-Way Connection] 錯誤詳情:', error.message);
    return null;
  }
}

/**
 * 獲取當前位置
 * @returns {Promise<Object>} 位置信息對象 (包含latitude, longitude等)
 */
export async function getCurrentLocation() {
  console.log('[Two-Way Connection] 📍 獲取當前位置');
  try {
    const location = await callFlutterMethod('location', null);
    console.log('[Two-Way Connection] ✅ 位置信息獲取成功:', location);
    return location;
  } catch (error) {
    console.error('[Two-Way Connection] ❌ 獲取位置信息失敗:', error);
    console.error('[Two-Way Connection] 錯誤詳情:', error.message);
    return null;
  }
}

/**
 * 將經緯度轉換為地址
 * 使用Google Maps Geocoding API (需要API key)
 * 或者可以使用其他reverse geocoding服務
 * @param {number} lat - 緯度
 * @param {number} lng - 經度
 * @returns {Promise<string>} 地址字符串
 */
export async function reverseGeocode(lat, lng) {
  console.log('[Two-Way Connection] 🗺️ 反向地理編碼:', { lat, lng });
  try {
    // 這裡可以使用Google Maps Geocoding API或其他服務
    // 由於需要API key，我們先使用一個簡單的實現
    // 實際應用中應該使用真實的geocoding服務
    
    // 方法1: 使用Google Maps Geocoding API (需要API key)
    // const apiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
    // const response = await fetch(
    //   `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${apiKey}&language=zh-TW`
    // );
    // const data = await response.json();
    // if (data.results && data.results.length > 0) {
    //   return data.results[0].formatted_address;
    // }

    // 方法2: 使用Nominatim (OpenStreetMap) - 免費但有限制
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1&accept-language=zh-TW,zh,en`;
    console.log('[Two-Way Connection] 📡 發送 geocoding 請求:', url);
    
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'TownPass-FoodSafety/1.0'
      }
    });
    
    if (!response.ok) {
      console.error('[Two-Way Connection] ❌ Geocoding API 請求失敗:', response.status, response.statusText);
      throw new Error('Geocoding API request failed');
    }

    const data = await response.json();
    console.log('[Two-Way Connection] ✅ Geocoding 響應:', data);
    
    if (data && data.address) {
      // 構建台灣地址格式
      const addr = data.address;
      let addressParts = [];
      
      // 台灣地址順序: 城市 -> 區 -> 里 -> 路/街 -> 號
      if (addr.city || addr.town || addr.city_district) {
        addressParts.push(addr.city || addr.town || addr.city_district || '');
      }
      if (addr.suburb || addr.district || addr.township) {
        addressParts.push(addr.suburb || addr.district || addr.township || '');
      }
      if (addr.road || addr.street) {
        addressParts.push(addr.road || addr.street || '');
      }
      if (addr.house_number) {
        addressParts.push(addr.house_number);
      }

      const address = addressParts.filter(Boolean).join('');
      const result = address || data.display_name || `${lat}, ${lng}`;
      console.log('[Two-Way Connection] ✅ 地址解析成功:', result);
      return result;
    }

    const result = data.display_name || `${lat}, ${lng}`;
    console.log('[Two-Way Connection] ✅ 使用顯示名稱:', result);
    return result;
  } catch (error) {
    console.error('[Two-Way Connection] ❌ 反向地理編碼失敗:', error);
    console.error('[Two-Way Connection] 錯誤詳情:', error.message);
    // 如果geocoding失敗，返回經緯度作為fallback
    const fallback = `${lat}, ${lng}`;
    console.log('[Two-Way Connection] 🔄 使用 fallback:', fallback);
    return fallback;
  }
}

/**
 * 獲取當前位置並轉換為地址
 * @returns {Promise<string>} 地址字符串
 */
export async function getCurrentLocationAddress() {
  console.log('[Two-Way Connection] 📍🗺️ 獲取當前位置並轉換為地址');
  try {
    const location = await getCurrentLocation();
    console.log('[Two-Way Connection] 位置數據:', location);
    
    if (!location || !location.latitude || !location.longitude) {
      console.warn('[Two-Way Connection] ⚠️ 位置數據無效:', location);
      return null;
    }

    const address = await reverseGeocode(location.latitude, location.longitude);
    console.log('[Two-Way Connection] ✅ 最終地址:', address);
    return address;
  } catch (error) {
    console.error('[Two-Way Connection] ❌ 獲取當前位置地址失敗:', error);
    console.error('[Two-Way Connection] 錯誤詳情:', error.message);
    return null;
  }
}

