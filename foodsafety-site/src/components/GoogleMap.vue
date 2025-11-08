<template>
  <div
    ref="mapContainer"
    class="map-container"
  />
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, nextTick, computed } from "vue";
import { addDebugLog } from "@/utils/debugLogger";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

const props = defineProps({
  center: {
    type: Object,
    required: true,
    default: () => ({ lat: 25.0330, lng: 121.5654 }),
  },
  zoom: {
    type: Number,
    default: 13,
  },
  markers: {
    type: Array,
    default: () => [],
  },
  mapId: {
    type: String,
    default: "default",
  },
  saveState: {
    type: Boolean,
    default: true,
  },
  forceUpdate: {
    type: Boolean,
    default: false,
  },
});

const mapContainer = ref(null);
let map = null;
let markers = [];
let markersLayer = null;

// 計算狀態存儲鍵
const STATE_STORAGE_KEY = computed(() => `mapState_${props.mapId}`);

// 根據狀態獲取顏色 - 每種狀態都有獨特的顏色
function getStatusColor(status) {
  if (!status) {
    return "#5E6D76"; // grayscale-600 (預設)
  }

  const statusMap = {
    // 不合格相關 - 紅色系
    "不合格": "#DC2626", // red-600 - 鮮紅色
    "複查不合格": "#B91C1C", // red-700 - 深紅色
    
    // 改善相關 - 橙色/黃色系
    "限期改善": "#F59E0B", // amber-500 - 琥珀色
    "輔導改善": "#F97316", // orange-500 - 橙色
    
    // 合格相關 - 綠色系
    "合格": "#10B981", // emerald-500 - 翠綠色
    "複查合格": "#059669", // emerald-600 - 深翠綠色
    
    // 優良相關 - 藍色/青色系
    "優良": "#3B82F6", // blue-500 - 藍色
    "金質": "#FBBF24", // amber-400 - 金色（更亮的金色）
    "銀質": "#94A3B8", // slate-400 - 銀色
  };

  return statusMap[status] || "#5E6D76"; // 預設灰色
}

// 保存地圖狀態到 sessionStorage
function saveMapState() {
  if (!props.saveState || !map) {
    return;
  }

  try {
    const center = map.getCenter();
    const zoom = map.getZoom();
    const state = {
      center: {
        lat: center.lat,
        lng: center.lng,
      },
      zoom: zoom,
      timestamp: Date.now(),
    };
    sessionStorage.setItem(STATE_STORAGE_KEY.value, JSON.stringify(state));
    addDebugLog("log", "Map state saved", state);
  } catch (error) {
    addDebugLog("error", "Failed to save map state", { error: error.message });
  }
}

// 從 sessionStorage 恢復地圖狀態
function loadMapState() {
  if (!props.saveState) {
    return null;
  }

  try {
    const savedState = sessionStorage.getItem(STATE_STORAGE_KEY.value);
    if (savedState) {
      const state = JSON.parse(savedState);
      // 檢查狀態是否過期（24小時）
      const maxAge = 24 * 60 * 60 * 1000; // 24小時
      if (Date.now() - state.timestamp < maxAge) {
        addDebugLog("log", "Map state loaded", state);
        return state;
      } else {
        // 清除過期狀態
        sessionStorage.removeItem(STATE_STORAGE_KEY.value);
      }
    }
  } catch (error) {
    addDebugLog("error", "Failed to load map state", { error: error.message });
  }
  return null;
}

// 轉義 HTML
function escapeHtml(text) {
  if (!text) return "";
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// 創建標記的彈窗內容
function createPopupContent(markerData) {
  return `
    <div style="padding: 12px; min-width: 200px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
      ${markerData.storeName ? `<h3 style="margin: 0 0 8px 0; font-size: 16px; font-weight: 600; color: #2C3E50; line-height: 1.4;">${escapeHtml(markerData.storeName)}</h3>` : ""}
      ${markerData.address ? `<p style="margin: 0 0 8px 0; font-size: 14px; color: #5E6D76; line-height: 1.5;">${escapeHtml(markerData.address)}</p>` : ""}
      ${markerData.status ? `<p style="margin: 0 0 4px 0; font-size: 14px; font-weight: 600; color: ${getStatusColor(markerData.status)};">${escapeHtml(markerData.status)}</p>` : ""}
      ${markerData.inspectionDate ? `<p style="margin: 0; font-size: 12px; color: #8A9BA8;">稽查日期: ${escapeHtml(markerData.inspectionDate)}</p>` : ""}
    </div>
  `;
}

// 創建自定義標記圖標
function createCustomIcon(color) {
  return L.divIcon({
    className: "custom-marker",
    html: `
      <div style="
        width: 18px;
        height: 18px;
    background-color: ${color};
    border: 2px solid #ffffff;
    border-radius: 50%;
    box-shadow: 0 2px 4px rgba(0,0,0,0.3);
      "></div>
    `,
    iconSize: [18, 18],
    iconAnchor: [9, 9],
  });
}

// 初始化地圖
async function initMap() {
  if (!mapContainer.value) {
    addDebugLog("error", "Map container not found");
    return;
  }

  // 如果地圖已經初始化，直接返回
  if (map) {
    addDebugLog("log", "Map already initialized, skipping");
      return;
    }

  try {
    // 如果 forceUpdate 為 true，優先使用 props 中的中心點（地址選擇）
    // 否則嘗試恢復保存的狀態
    let initialCenter, initialZoom;
    let savedState = null;
    
    if (props.forceUpdate) {
      initialCenter = props.center;
      initialZoom = props.zoom;
      // 清除保存的狀態，因為用戶主動選擇了地址
      if (props.saveState) {
        sessionStorage.removeItem(STATE_STORAGE_KEY.value);
      }
    } else {
      savedState = loadMapState();
      initialCenter = savedState?.center || props.center;
      initialZoom = savedState?.zoom || props.zoom;
    }

    // 創建地圖實例
    map = L.map(mapContainer.value, {
      center: [initialCenter.lat, initialCenter.lng],
      zoom: initialZoom,
      zoomControl: true,
    });

    // 添加 OpenStreetMap 圖層
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(map);

    // 創建標記圖層組
    markersLayer = L.layerGroup().addTo(map);

    // 監聽地圖移動和縮放事件，保存狀態
    if (props.saveState) {
      map.on("moveend", saveMapState);
      map.on("zoomend", saveMapState);
    }

    addDebugLog("log", "Map initialized", {
      center: initialCenter,
      zoom: initialZoom,
      markersCount: props.markers.length,
      stateRestored: !!savedState,
    });

    // 載入標記
    updateMarkers();

    // 監聽地圖載入完成
    map.whenReady(() => {
      addDebugLog("log", "Map tiles loaded");
    });
  } catch (error) {
    addDebugLog("error", "Failed to initialize map", {
      error: error.message,
    });
    if (mapContainer.value) {
      mapContainer.value.innerHTML = `
        <div style="display: flex; align-items: center; justify-content: center; height: 100%; background-color: #f5f5f5; color: #666; padding: 20px; text-align: center;">
          <div>
            <p style="margin: 0 0 8px 0; font-size: 16px; font-weight: 600;">地圖載入失敗</p>
            <p style="margin: 0; font-size: 14px;">${escapeHtml(error.message)}</p>
          </div>
        </div>
      `;
    }
  }
}

// 清除所有標記
function clearMarkers() {
  if (markersLayer) {
    markersLayer.clearLayers();
  }
  markers = [];
}

// 更新標記
function updateMarkers() {
  if (!map || !markersLayer) {
    return;
  }

  // 清除舊標記
  clearMarkers();

  // 創建新標記
  props.markers.forEach((markerData) => {
    if (!markerData.lat || !markerData.lng) {
      addDebugLog("warn", "Marker missing coordinates", markerData);
      return;
    }

    const position = [markerData.lat, markerData.lng];
    const statusColor = getStatusColor(markerData.status);
    
    // 創建自定義圖標
    const customIcon = createCustomIcon(statusColor);

    // 創建標記
    const marker = L.marker(position, {
      icon: customIcon,
            title: markerData.storeName || "標記",
          });

    // 添加彈窗
    const popupContent = createPopupContent(markerData);
    marker.bindPopup(popupContent);

    // 添加到圖層
    marker.addTo(markersLayer);
    markers.push(marker);
  });

  addDebugLog("log", "Markers updated", {
    count: markers.length,
  });
}

// 更新地圖中心
function updateCenter() {
  if (!map) {
    return;
  }

  // 如果 forceUpdate 為 true，強制更新中心點（例如用戶選擇了新地址）
  // 這種情況下，優先使用地址的位置，忽略保存的狀態
  if (props.forceUpdate) {
    map.setView([props.center.lat, props.center.lng], map.getZoom(), {
      animate: true,
      duration: 0.5,
    });
    // 清除保存的狀態，因為用戶主動改變了位置
    if (props.saveState) {
      sessionStorage.removeItem(STATE_STORAGE_KEY.value);
    }
    addDebugLog("log", "Map center force updated by address", props.center);
    return;
  }

  // 正常情況下，當 center prop 改變時更新地圖中心
  // 但不要覆蓋用戶正在查看的位置（除非是明確的地址選擇）
  const currentCenter = map.getCenter();
  const distance = Math.sqrt(
    Math.pow(currentCenter.lat - props.center.lat, 2) +
    Math.pow(currentCenter.lng - props.center.lng, 2)
  );
  
  // 只有當中心點變化較大時才更新（避免不必要的跳動）
  if (distance > 0.001) {
    map.setView([props.center.lat, props.center.lng], map.getZoom(), {
      animate: true,
      duration: 0.5,
    });
  addDebugLog("log", "Map center updated", props.center);
  }
}

// 更新縮放等級
function updateZoom() {
  if (!map) {
    return;
  }

  map.setZoom(props.zoom);
  addDebugLog("log", "Map zoom updated", { zoom: props.zoom });
}

// 監聽 props 變化
watch(
  () => props.center,
  (newCenter) => {
    if (map && newCenter) {
      updateCenter();
    }
  },
  { deep: true }
);

watch(
  () => props.zoom,
  (newZoom) => {
    if (map && newZoom) {
      updateZoom();
    }
  }
);

// 監聽 forceUpdate 變化
watch(
  () => props.forceUpdate,
  (newValue) => {
    if (map && newValue && props.center) {
      // 當 forceUpdate 變為 true 時，立即更新地圖中心
      updateCenter();
    }
  }
);

watch(
  () => props.markers,
  () => {
    if (map) {
      updateMarkers();
    }
  },
  { deep: true }
);

// 組件掛載時初始化地圖
onMounted(async () => {
  await nextTick();
  initMap();
});

// 組件卸載時清理
onUnmounted(() => {
  // 保存最終狀態
  if (props.saveState && map) {
    saveMapState();
  }

  // 移除事件監聽器
  if (map) {
    map.off("moveend", saveMapState);
    map.off("zoomend", saveMapState);
  }

  clearMarkers();
  if (map) {
    map.remove();
    map = null;
  }
  markersLayer = null;
});
</script>

<style scoped>
.map-container {
  width: 100%;
  height: 100%;
  min-height: 300px;
  border-radius: 8px;
  overflow: hidden;
  position: relative;
  z-index: 1;
}

/* 覆蓋 Leaflet 預設樣式以適應我們的設計 */
:deep(.leaflet-container) {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
}

/* 確保 Leaflet 地圖圖層不會擋住覆蓋層 */
:deep(.leaflet-map-pane),
:deep(.leaflet-tile-pane),
:deep(.leaflet-overlay-pane),
:deep(.leaflet-shadow-pane),
:deep(.leaflet-marker-pane),
:deep(.leaflet-tooltip-pane),
:deep(.leaflet-popup-pane) {
  z-index: 1;
}

/* 確保 Leaflet 控制項可以正常使用 */
:deep(.leaflet-control-container) {
  z-index: 10;
}

:deep(.leaflet-popup-content-wrapper) {
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

:deep(.leaflet-popup-tip) {
  background: white;
}

:deep(.leaflet-control-zoom) {
  border: none;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
}

:deep(.leaflet-control-zoom a) {
  background-color: white;
  color: #475259;
  border: none;
  width: 30px;
  height: 30px;
  line-height: 30px;
  text-align: center;
  text-decoration: none;
}

:deep(.leaflet-control-zoom a:hover) {
  background-color: #f5f5f5;
}

:deep(.leaflet-control-zoom-in),
:deep(.leaflet-control-zoom-out) {
  font-size: 18px;
  font-weight: bold;
}

/* 自定義標記樣式 */
:deep(.custom-marker) {
  background: transparent;
  border: none;
}
</style>
