<template>
  <div class="food-safety-page">
    <!-- Content -->
    <main class="content">
      <!-- Map Section with Address Overlay -->
      <div class="map-section">
        <GoogleMap
          :center="mapCenter"
          :zoom="mapZoom"
          :markers="inspectionMarkers"
          map-id="foodSafety"
          :save-state="true"
          :force-update="forceMapUpdate"
        />
        <!-- Address Selector with Action Icons - Overlay on Map -->
        <div class="address-section address-section--overlay">
          <div class="address-row">
            <div class="address-icons">
              <button
                class="action-icon-button"
                @click="goNotification"
              >
                <span class="material-icons">notifications_none</span>
        </button>
              <button
                class="action-icon-button"
                @click="goReceipt"
              >
                <span class="material-icons">receipt</span>
        </button>
      </div>
            <div 
              class="address-card" 
              @click="toggleDropdown"
            >
              <span class="address-text">
                {{ isLoadingLocation ? "正在載入地址..." : selectedAddress }}
              </span>
              <div class="address-dropdown-icon">
                <span
                  class="material-icons"
                  :class="{ 'rotate-180': showDropdown }"
                >expand_more</span>
              </div>
            </div>
          </div>
          <!-- Dropdown positioned relative to address section -->
          <div 
            v-if="showDropdown"
            class="address-dropdown" 
            @click.stop
          >
            <div
              v-for="(address, index) in addressList"
              :key="index"
              class="address-dropdown-item"
              :class="{ 'address-dropdown-item--selected': address === selectedAddress }"
              @click.stop="selectAddress(address)"
            >
              <span class="address-item-text">{{ address }}</span>
              <button
                class="address-delete-button"
                :aria-label="`刪除地址 ${address}`"
                @click.stop="deleteAddress(address)"
              >
                <span class="material-icons">delete</span>
              </button>
            </div>
            <div
              class="address-dropdown-item address-dropdown-item--add"
              @click="goAddAddress"
            >
              <span class="material-icons">add</span>
              <span>新增地址</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="action-buttons">
        <button
          class="action-button"
          :class="{ 'action-button--active': activeTab === 'store' }"
          @click="goStore"
        >
          店家
        </button>
        <button
          class="action-button"
          :class="{ 'action-button--active': activeTab === 'night-market' }"
          @click="goNightMarket"
        >
          夜市
        </button>
      </div>
    </main>

    <!-- Dropdown Overlay -->
    <div
      v-if="showDropdown"
      class="dropdown-overlay"
      @click="showDropdown = false"
    />
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, onActivated } from "vue";
import { useRouter } from "vue-router";
import { addDebugLog } from "@/utils/debugLogger";
import GoogleMap from "@/components/GoogleMap.vue";
import { geocodeAddress } from "@/utils/geocode";
import { getUnsafeLocations } from "@/utils/api";
import {
  initializeFavoriteLocations,
  getAllAddresses,
  addAddress,
  removeAddress,
  setSelectedAddress,
} from "@/utils/favoriteLocation";

const router = useRouter();

// Address dropdown
const selectedAddress = ref("請選擇地址");
const addressList = ref([]);
const showDropdown = ref(false);
const isLoadingLocation = ref(false);

// Map settings
const mapCenter = ref({ lat: 25.0330, lng: 121.5654 }); // 台北101 預設位置
const mapZoom = ref(13);
const inspectionMarkers = ref([]);
const forceMapUpdate = ref(false); // 用於強制更新地圖中心點

// 載入稽查資料點
async function loadInspectionMarkers() {
  try {
    const data = await getUnsafeLocations();
    inspectionMarkers.value = data.map((point) => ({
      lat: point.latitude,
      lng: point.longitude,
      storeName: point.businessName,
      address: "",
      status: point.inspectionStatus,
      inspectionDate: "",
    }));
    addDebugLog("log", "Loaded inspection markers", {
      count: inspectionMarkers.value.length,
    });
  } catch (error) {
    addDebugLog("error", "Failed to load inspection markers", {
      error: error.message,
    });
    inspectionMarkers.value = [];
  }
}

function toggleDropdown() {
  showDropdown.value = !showDropdown.value;
}

async function selectAddress(address) {
  selectedAddress.value = address;
  showDropdown.value = false;
  // Save selected address using favoriteLocation utility
  setSelectedAddress(address);
  
  // 更新地圖中心到選中的地址
  try {
    const coordinates = await geocodeAddress(address);
    if (coordinates) {
      // 設置強制更新標記，然後更新中心點
      forceMapUpdate.value = true;
      mapCenter.value = coordinates;
      addDebugLog("log", "Map center updated by address selection", { address, ...coordinates });
      
      // 在下一個 tick 後重置強制更新標記
      setTimeout(() => {
        forceMapUpdate.value = false;
      }, 100);
    }
  } catch (error) {
    addDebugLog("error", "Failed to update map center", { address, error: error.message });
  }
}

function deleteAddress(address) {
  if (confirm(`確定要刪除地址「${address}」嗎？`)) {
    // Remove address using favoriteLocation utility
    removeAddress(address);
    
    // Update local state
    addressList.value = getAllAddresses();
    
    // If deleted address was selected, select first available address
    if (selectedAddress.value === address) {
      const updatedAddresses = getAllAddresses();
      if (updatedAddresses.length > 0) {
        selectedAddress.value = updatedAddresses[0];
        setSelectedAddress(updatedAddresses[0]);
      } else {
        // If no addresses left, set a default or empty message
        selectedAddress.value = "請新增地址";
      }
    }
  }
}

// Tab navigation
const activeTab = ref("store");

function goStore() {
  activeTab.value = "store";
  router.push("/store");
}

function goNightMarket() {
  activeTab.value = "night-market";
  router.push("/night-market");
}

// Navigation
function goNotification() {
  router.push("/notification");
}

function goReceipt() {
  router.push("/receipt");
}

function goAddAddress() {
  showDropdown.value = false;
  router.push("/add-address");
}


// Listen for address updates from AddAddressPage
function handleAddressAdded() {
  // Reload addresses from localStorage to ensure sync
  loadAddresses();
}

// Load addresses from favorite_location.json and localStorage
async function loadAddresses() {
  // Initialize favorite locations (loads from JSON and merges with localStorage)
  const { addresses, selectedAddress: savedSelected } = initializeFavoriteLocations();
  
  if (addresses && addresses.length > 0) {
    addressList.value = addresses;
    
    if (savedSelected && addresses.includes(savedSelected)) {
      selectedAddress.value = savedSelected;
      // 更新地圖中心
      try {
        const coordinates = await geocodeAddress(savedSelected);
        if (coordinates) {
          forceMapUpdate.value = true;
          mapCenter.value = coordinates;
          setTimeout(() => {
            forceMapUpdate.value = false;
          }, 100);
        }
      } catch (error) {
        addDebugLog("error", "Failed to geocode saved address", {
          address: savedSelected,
          error: error.message,
        });
      }
    } else if (addresses.length > 0) {
      selectedAddress.value = addresses[0];
      setSelectedAddress(addresses[0]);
      // 更新地圖中心
      try {
        const coordinates = await geocodeAddress(addresses[0]);
        if (coordinates) {
          forceMapUpdate.value = true;
          mapCenter.value = coordinates;
          setTimeout(() => {
            forceMapUpdate.value = false;
          }, 100);
        }
      } catch (error) {
        addDebugLog("error", "Failed to geocode first address", {
          address: addresses[0],
          error: error.message,
        });
      }
    }
  }
}

// 接收 Flutter 傳遞的定位地址
function receiveLocationAddress(address) {
  if (!address || !address.trim()) {
    addDebugLog('warn', "Received empty address from Flutter");
    return;
  }

  addDebugLog('log', "Received location address from Flutter", { address });
  isLoadingLocation.value = false;

  // 處理接收到的地址
  const newAddress = address.trim();
  const existingAddresses = new Set(getAllAddresses().map(addr => addr.trim()));

  // 如果地址不存在，添加到地址列表
  if (!existingAddresses.has(newAddress)) {
    addAddress(newAddress, true); // 設置為選中
    addressList.value = getAllAddresses();
  }

  // 設置為選中地址
  selectedAddress.value = newAddress;
  setSelectedAddress(newAddress);

  // 更新地圖中心
  geocodeAddress(newAddress).then(coordinates => {
    if (coordinates) {
      forceMapUpdate.value = true;
      mapCenter.value = coordinates;
      setTimeout(() => {
        forceMapUpdate.value = false;
      }, 200);
    }
  }).catch(error => {
    addDebugLog("error", "Failed to geocode received address", {
      address: newAddress,
      error: error.message
    });
  });
}

// 將 receiveLocationAddress 函數暴露到全局，供 Flutter 調用
if (typeof window !== 'undefined') {
  window.receiveLocationAddress = receiveLocationAddress;
}

// 初始化地址：從 localStorage 加載已保存的地址
async function initializeAddresses() {
  isLoadingLocation.value = true;
  
  // 先加載已保存的地址
  loadAddresses();
  
  // 等待 Flutter 傳遞定位地址（如果有的話）
  // Flutter 會在頁面加載完成後自動調用 receiveLocationAddress
  // 這裡設置一個超時，如果 Flutter 沒有傳遞地址，就使用已保存的地址
  setTimeout(() => {
    if (isLoadingLocation.value) {
      isLoadingLocation.value = false;
      addDebugLog('log', "Location address not received from Flutter, using saved addresses");
    }
  }, 3000);
}

// Close dropdown when clicking outside
function handleClickOutside(event) {
  if (showDropdown.value && 
      !event.target.closest(".address-section") && 
      !event.target.closest(".address-dropdown")) {
    showDropdown.value = false;
  }
}

// 標記是否已初始化
const isInitialized = ref(false);

onMounted(async () => {
  if (!isInitialized.value) {
    // 初始化Flutter Bridge並獲取地址
    await initializeAddresses();
    // 載入稽查資料點（只在首次掛載時載入）
    await loadInspectionMarkers();
    isInitialized.value = true;
  }
  document.addEventListener("click", handleClickOutside);
  window.addEventListener("address-added", handleAddressAdded);
});

// 當組件被 keep-alive 激活時
onActivated(() => {
  // 組件從其他頁面返回時，不需要重新載入數據
  // 地圖狀態會自動從 sessionStorage 恢復
  addDebugLog("log", "FoodSafetyWebView activated");
});

onUnmounted(() => {
  document.removeEventListener("click", handleClickOutside);
  window.removeEventListener("address-added", handleAddressAdded);
});
</script>

<style scoped>
@import "@/styles/colors.css";

.food-safety-page {
  height: 100vh;
  max-height: 100vh;
  background-color: var(--grayscale-50);
  display: flex;
  flex-direction: column;
  position: relative;
  overflow: hidden;
}

/* Action Icon Button */
.action-icon-button {
  background-color: var(--white);
  border: 1px solid var(--grayscale-200);
  border-radius: 8px;
  padding: 8px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary-500);
  transition: all 0.2s;
  box-shadow: 0 1px 3px rgba(11, 13, 14, 0.1);
  flex-shrink: 0;
}

.action-icon-button:hover {
  background-color: var(--primary-50);
}

.action-icon-button:active {
  background-color: var(--primary-100);
}

.action-icon-button .material-icons {
  font-size: 20px;
}

/* Content */
.content {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* Address Section */
.address-section {
  margin-bottom: 4px;
  position: relative;
}

/* Address Section Overlay on Map */
.address-section--overlay {
  position: absolute;
  top: 12px;
  left: 12px;
  right: 12px;
  margin-bottom: 0;
  z-index: 1000;
  pointer-events: none;
}

/* 地址選擇器內的按鈕和卡片需要可點擊 */
.address-section--overlay .address-card,
.address-section--overlay .action-icon-button,
.address-section--overlay .address-dropdown {
  pointer-events: auto;
}

.address-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.address-icons {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

.address-card {
  flex: 1;
  background-color: var(--white);
  border: 1px solid var(--grayscale-200);
  border-radius: 8px;
  padding: 12px 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: 0 2px 8px rgba(11, 13, 14, 0.15);
  cursor: pointer;
  transition: background-color 0.2s;
  user-select: none;
  position: relative;
  z-index: 1;
}

.address-card:hover {
  background-color: var(--grayscale-50);
}

.address-card:active {
  background-color: var(--grayscale-100);
}

.address-text {
  font-size: 16px;
  font-weight: 500;
  color: var(--grayscale-800);
  flex: 1;
}

.address-dropdown-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--grayscale-700);
  transition: transform 0.3s ease;
}

.address-dropdown-icon .material-icons {
  font-size: 24px;
}

.address-dropdown-icon .material-icons.rotate-180 {
  transform: rotate(180deg);
}

.address-dropdown {
  position: absolute;
  top: calc(100% + 8px);
  left: 0;
  right: 0;
  width: 100%;
  background-color: var(--white);
  border: 1px solid var(--grayscale-200);
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(11, 13, 14, 0.15);
  z-index: 1001;
  overflow: hidden;
  max-height: calc(100vh - 200px);
  overflow-y: auto;
  pointer-events: auto;
}

.address-dropdown-item {
  padding: 12px 16px;
  font-size: 16px;
  color: var(--grayscale-800);
  cursor: pointer;
  transition: background-color 0.2s;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.address-dropdown-item:hover {
  background-color: var(--primary-50);
}

.address-dropdown-item--selected {
  background-color: var(--primary-50);
  color: var(--primary-600);
  font-weight: 600;
}

.address-item-text {
  flex: 1;
}

.address-delete-button {
  background: none;
  border: none;
  cursor: pointer;
  padding: 4px 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--grayscale-500);
  border-radius: 4px;
  transition: all 0.2s;
  flex-shrink: 0;
}

.address-delete-button:hover {
  background-color: var(--red-50);
  color: var(--red-600);
}

.address-delete-button .material-icons {
  font-size: 20px;
}

.address-dropdown-item--add {
  border-top: 1px solid var(--grayscale-100);
  color: var(--primary-500);
  justify-content: center;
  gap: 8px;
}

.address-dropdown-item--add .material-icons {
  font-size: 20px;
}

/* Map Section */
.map-section {
  width: 100%;
  flex: 1;
  min-height: 0;
  margin-bottom: 4px;
  border-radius: 12px;
  overflow: visible;
  box-shadow: 0 1px 3px rgba(11, 13, 14, 0.1);
  position: relative;
}

/* 地圖容器本身需要 overflow hidden，但外層容器需要 visible 以顯示覆蓋層 */
.map-section :deep(.map-container) {
  width: 100%;
  height: 100%;
  border-radius: 12px;
  overflow: hidden;
  position: relative;
  z-index: 1;
}

/* Action Buttons */
.action-buttons {
  display: flex;
  gap: 12px;
  margin-bottom: 4px;
  flex-shrink: 0;
}

.action-button {
  flex: 1;
  padding: 14px 24px;
  background-color: var(--white);
  border: 1px solid var(--primary-500);
  border-radius: 8px;
  font-size: 16px;
  font-weight: 600;
  color: var(--primary-500);
  cursor: pointer;
  transition: all 0.2s;
}

.action-button:hover {
  background-color: var(--primary-50);
}

.action-button--active {
  background-color: var(--white);
  border-color: var(--primary-500);
  color: var(--primary-500);
}

.action-button--active:hover {
  background-color: var(--primary-50);
}

/* Empty State */
.empty-state {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 32px 16px;
  text-align: center;
}

.empty-state-text {
  font-size: 16px;
  color: var(--grayscale-500);
  margin: 0;
}

/* Dropdown Overlay */
.dropdown-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 99;
  background-color: transparent;
}
</style>
