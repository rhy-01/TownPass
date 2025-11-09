/**
 * 管理收藏地址的工具函數
 * 使用 localStorage 作為運行時存儲，並與 favorite_location.json 同步
 */

import favoriteLocationData from "@/data/favorite_location.json";
import { addDebugLog } from "./debugLogger";

const STORAGE_KEY_ADDRESSES = "foodSafetyAddresses";
const STORAGE_KEY_SELECTED = "foodSafetySelectedAddress";

/**
 * 初始化地址數據
 * 從 JSON 文件加載，並與 localStorage 合併
 */
export function initializeFavoriteLocations() {
  try {
    // 從 JSON 文件獲取初始數據
    const jsonAddresses = favoriteLocationData.addresses || [];
    const jsonSelected = favoriteLocationData.selectedAddress || "";

    // 從 localStorage 獲取用戶已保存的數據
    const savedAddresses = getStoredAddresses();
    const savedSelected = localStorage.getItem(STORAGE_KEY_SELECTED) || "";

    // 合併地址列表（JSON 文件的地址 + localStorage 中的地址，去重）
    const allAddresses = [...new Set([...jsonAddresses, ...savedAddresses])];

    // 優先使用 localStorage 中選中的地址，否則使用 JSON 文件中的
    const selectedAddress = savedSelected || jsonSelected || (allAddresses.length > 0 ? allAddresses[0] : "");

    // 保存合併後的數據到 localStorage
    if (allAddresses.length > 0) {
      saveAddressesToStorage(allAddresses);
      if (selectedAddress) {
        localStorage.setItem(STORAGE_KEY_SELECTED, selectedAddress);
      }
    }

    addDebugLog("log", "Favorite locations initialized", {
      jsonCount: jsonAddresses.length,
      savedCount: savedAddresses.length,
      totalCount: allAddresses.length,
      selected: selectedAddress,
    });

    return {
      addresses: allAddresses,
      selectedAddress: selectedAddress,
    };
  } catch (error) {
    addDebugLog("error", "Failed to initialize favorite locations", { error: error.message });
    // 如果出錯，返回 localStorage 中的數據
    return {
      addresses: getStoredAddresses(),
      selectedAddress: localStorage.getItem(STORAGE_KEY_SELECTED) || "",
    };
  }
}

/**
 * 從 localStorage 獲取地址列表
 */
export function getStoredAddresses() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY_ADDRESSES);
    if (stored) {
      const parsed = JSON.parse(stored);
      return Array.isArray(parsed) ? parsed : [];
    }
  } catch (error) {
    addDebugLog("error", "Failed to parse stored addresses", { error: error.message });
  }
  return [];
}

/**
 * 保存地址列表到 localStorage
 */
export function saveAddressesToStorage(addresses) {
  try {
    if (Array.isArray(addresses) && addresses.length > 0) {
      localStorage.setItem(STORAGE_KEY_ADDRESSES, JSON.stringify(addresses));
      addDebugLog("log", "Addresses saved to storage", { count: addresses.length });
    } else {
      localStorage.removeItem(STORAGE_KEY_ADDRESSES);
    }
  } catch (error) {
    addDebugLog("error", "Failed to save addresses to storage", { error: error.message });
  }
}

/**
 * 添加新地址
 * @param {string} address - 要添加的地址
 * @param {boolean} setAsSelected - 是否設置為選中地址（默認為 false）
 */
export function addAddress(address, setAsSelected = false) {
  if (!address || !address.trim()) {
    return false;
  }

  const trimmedAddress = address.trim();
  const currentAddresses = getStoredAddresses();

  // 檢查地址是否已存在
  if (currentAddresses.includes(trimmedAddress)) {
    addDebugLog("log", "Address already exists", { address: trimmedAddress });
    // 如果地址已存在但要求設置為選中，則設置
    if (setAsSelected) {
      setSelectedAddress(trimmedAddress);
    }
    return false;
  }

  // 添加新地址
  const newAddresses = [...currentAddresses, trimmedAddress];
  saveAddressesToStorage(newAddresses);

  // 如果要求設置為選中地址，則設置
  if (setAsSelected) {
    setSelectedAddress(trimmedAddress);
  }

  addDebugLog("log", "Address added", { address: trimmedAddress, totalCount: newAddresses.length, setAsSelected });
  return true;
}

/**
 * 刪除地址
 */
export function removeAddress(address) {
  if (!address) {
    return false;
  }

  const currentAddresses = getStoredAddresses();
  const index = currentAddresses.indexOf(address);

  if (index === -1) {
    return false;
  }

  // 刪除地址
  const newAddresses = currentAddresses.filter((addr) => addr !== address);
  saveAddressesToStorage(newAddresses);

  // 如果刪除的是選中地址，選擇第一個可用地址
  const selectedAddress = localStorage.getItem(STORAGE_KEY_SELECTED);
  if (selectedAddress === address) {
    if (newAddresses.length > 0) {
      localStorage.setItem(STORAGE_KEY_SELECTED, newAddresses[0]);
    } else {
      localStorage.removeItem(STORAGE_KEY_SELECTED);
    }
  }

  addDebugLog("log", "Address removed", { address, remainingCount: newAddresses.length });
  return true;
}

/**
 * 設置選中的地址
 */
export function setSelectedAddress(address) {
  if (address) {
    localStorage.setItem(STORAGE_KEY_SELECTED, address);
    addDebugLog("log", "Selected address updated", { address });
  } else {
    localStorage.removeItem(STORAGE_KEY_SELECTED);
  }
}

/**
 * 獲取選中的地址
 */
export function getSelectedAddress() {
  return localStorage.getItem(STORAGE_KEY_SELECTED) || "";
}

/**
 * 獲取所有地址
 * 確保包含 JSON 文件和 localStorage 中的地址
 */
export function getAllAddresses() {
  // 先初始化，確保 JSON 文件中的地址已經合併到 localStorage
  const { addresses } = initializeFavoriteLocations();
  return addresses || getStoredAddresses();
}

/**
 * 導出地址數據為 JSON 格式（用於下載或同步）
 */
export function exportAddressesAsJSON() {
  const addresses = getStoredAddresses();
  const selectedAddress = getSelectedAddress();

  return JSON.stringify(
    {
      addresses: addresses,
      selectedAddress: selectedAddress,
    },
    null,
    2
  );
}

