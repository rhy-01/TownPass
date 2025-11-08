import { addDebugLog } from "./debugLogger";

// API Base URL
// 統一使用 /api 代理，避免 CORS 問題
// 開發環境: vue.config.js 中的 proxy 會處理 /api，轉發到後端 API
// 生產環境: nginx.conf 中的 location ~ ^/api/(.*)$ 會將 /api/* 請求代理到後端 API
// 這樣所有的 API 請求都通過同一個域名，瀏覽器不會觸發 CORS 檢查
const API_BASE_URL = '/api';

/**
 * 獲取不安全店家資訊
 * @returns {Promise<Array>} 不安全店家列表
 */
export async function getUnsafeLocations() {
  try {
    const url = `${API_BASE_URL}/locations/unsafe`;
    addDebugLog("log", "Fetching unsafe locations", { url });

    const response = await fetch(url, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      throw new Error(`API request failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    addDebugLog("log", "Unsafe locations fetched successfully", { count: data.length });

    return data;
  } catch (error) {
    addDebugLog("error", "Failed to fetch unsafe locations", { error: error.message });
    throw error;
  }
}

/**
 * 獲取夜市店家資訊
 * @param {string} nightMarketName - 夜市名稱
 * @returns {Promise<Array>} 夜市店家列表
 */
export async function getNightMarketShops(nightMarketName) {
  if (!nightMarketName) {
    addDebugLog("error", "Night market name is required");
    throw new Error("Night market name is required");
  }

  try {
    const encodedName = encodeURIComponent(nightMarketName);
    const url = `${API_BASE_URL}/night-market?name=${encodedName}`;
    addDebugLog("log", "Fetching night market shops", { url, nightMarketName });

    const response = await fetch(url, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      throw new Error(`API request failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    addDebugLog("log", "Night market shops fetched successfully", { 
      nightMarketName,
      count: data.length 
    });

    return data;
  } catch (error) {
    addDebugLog("error", "Failed to fetch night market shops", { 
      nightMarketName,
      error: error.message 
    });
    throw error;
  }
}

