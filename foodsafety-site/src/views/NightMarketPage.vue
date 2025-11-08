<template>
  <div class="night-market-page">
    <!-- AppBar -->
    <header class="app-bar">
      <button
        class="back-button"
        @click="goBack"
      >
        <span class="material-icons">arrow_back</span>
      </button>
      <h1 class="app-bar-title">
        夜市資訊
      </h1>
      <div class="app-bar-spacer" />
    </header>

    <!-- Content -->
    <main class="content">
      <!-- Market Selector -->
      <div class="market-selector-container">
        <select
          v-model="selectedMarket"
          class="market-selector"
        >
          <option
            v-for="m in nightMarkets"
            :key="m"
            :value="m"
          >
            {{ m }}
          </option>
        </select>
      </div>

      <!-- Loading State -->
      <div
        v-if="isLoading"
        class="empty-state"
      >
        <p class="empty-state-text">
          載入中...
        </p>
      </div>

      <!-- Lists -->
      <div
        v-else-if="selectedUnqualified.length || selectedGood.length"
        class="lists-container"
      >
        <!-- Unqualified Shops -->
        <section
          v-if="selectedUnqualified.length"
          class="shop-section"
        >
          <h2 class="section-title">
            不合格名單
          </h2>
          <div class="shop-list">
            <div
              v-for="shop in selectedUnqualified"
              :key="shop.name"
              class="shop-card"
              :class="getCardClass(shop.status)"
            >
              <div class="shop-card-content">
                <div class="shop-info">
                  <h3 class="shop-name">
                    {{ shop.name }}
                  </h3>
                  <p class="shop-address">
                    {{ shop.address }}
                  </p>
                </div>
                <span 
                  class="shop-status" 
                  :class="getStatusClass(shop.status)"
                >
                  {{ shop.status }}
                </span>
              </div>
            </div>
          </div>
        </section>

        <!-- Good Shops -->
        <section
          v-if="selectedGood.length"
          class="shop-section"
        >
          <h2 class="section-title">
            優良名單
          </h2>
          <div class="shop-list">
            <div
              v-for="shop in selectedGood"
              :key="shop.name"
              class="shop-card"
              :class="getCardClass(shop.status)"
            >
              <div class="shop-card-content">
                <div class="shop-info">
                  <h3 class="shop-name">
                    {{ shop.name }}
                  </h3>
                  <p class="shop-address">
                    {{ shop.address }}
                  </p>
                </div>
                <span 
                  class="shop-status" 
                  :class="getStatusClass(shop.status)"
                >
                  {{ shop.status }}
                </span>
              </div>
            </div>
          </div>
        </section>
      </div>

      <!-- Empty State -->
      <div
        v-else
        class="empty-state"
      >
        <p
          v-if="hasLoadedData"
          class="empty-state-text empty-state-text--success"
        >
          全數稽查合格
        </p>
        <p
          v-else
          class="empty-state-text"
        >
          目前尚無資料
        </p>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from "vue";
import { useRouter } from "vue-router";
import nightMarketList from "@/data/night_market_list.json";
import { getNightMarketShops } from "@/utils/api";
import { addDebugLog } from "@/utils/debugLogger";

const router = useRouter();

const nightMarkets = ref([]);
const selectedMarket = ref("");
const shopData = ref({
  unqualified: [],
  good: [],
});
const isLoading = ref(false);
const hasLoadedData = ref(false); // 追蹤是否已成功載入資料

// 判斷是否為優良店家
function isGoodShop(evaluationResult) {
  if (!evaluationResult) return false;
  const goodResults = ["金質", "銀質", "優良", "合格", "複查合格"];
  const result = String(evaluationResult).toLowerCase();
  return goodResults.some((good) => result.includes(good.toLowerCase()));
}

// 判斷是否為不合格店家
function isUnqualifiedShop(evaluationResult) {
  if (!evaluationResult) return false;
  const unqualifiedResults = ["不合格", "複查不合格", "限期改善", "輔導改善"];
  const result = String(evaluationResult).toLowerCase();
  return unqualifiedResults.some((bad) => result.includes(bad.toLowerCase()));
}

// 根據狀態獲取卡片邊框顏色類別
function getCardClass(status) {
  if (!status) return "shop-card--default";
  
  const statusStr = String(status).trim();
  
  // 必須按照從具體到一般的順序判斷
  // 複查不合格：深紅色（必須在"不合格"之前）
  if (statusStr.indexOf("複查不合格") !== -1) {
    return "shop-card--recheck-unqualified";
  }
  // 複查合格：淺藍色（必須在"合格"之前）
  if (statusStr.indexOf("複查合格") !== -1) {
    return "shop-card--recheck-qualified";
  }
  // 金質：金色
  if (statusStr.indexOf("金質") !== -1) {
    return "shop-card--gold";
  }
  // 銀質：銀色
  if (statusStr.indexOf("銀質") !== -1) {
    return "shop-card--silver";
  }
  // 優良：綠色
  if (statusStr.indexOf("優良") !== -1) {
    return "shop-card--excellent";
  }
  // 不合格：紅色（必須在"複查不合格"之後）
  if (statusStr.indexOf("不合格") !== -1) {
    return "shop-card--unqualified";
  }
  // 合格：藍色（必須在"複查合格"之後）
  if (statusStr.indexOf("合格") !== -1) {
    return "shop-card--qualified";
  }
  // 限期改善：橙色
  if (statusStr.indexOf("限期改善") !== -1) {
    return "shop-card--improvement";
  }
  // 輔導改善：淺橙色
  if (statusStr.indexOf("輔導改善") !== -1) {
    return "shop-card--guidance";
  }
  
  return "shop-card--default";
}

// 根據狀態獲取標籤顏色類別
function getStatusClass(status) {
  if (!status) return "shop-status--default";
  
  const statusStr = String(status).trim();
  
  // 必須按照從具體到一般的順序判斷
  // 複查不合格：深紅色（必須在"不合格"之前）
  if (statusStr.indexOf("複查不合格") !== -1) {
    return "shop-status--recheck-unqualified";
  }
  // 複查合格：淺藍色（必須在"合格"之前）
  if (statusStr.indexOf("複查合格") !== -1) {
    return "shop-status--recheck-qualified";
  }
  // 金質：金色
  if (statusStr.indexOf("金質") !== -1) {
    return "shop-status--gold";
  }
  // 銀質：銀色
  if (statusStr.indexOf("銀質") !== -1) {
    return "shop-status--silver";
  }
  // 優良：綠色
  if (statusStr.indexOf("優良") !== -1) {
    return "shop-status--excellent";
  }
  // 不合格：紅色（必須在"複查不合格"之後）
  if (statusStr.indexOf("不合格") !== -1) {
    return "shop-status--unqualified";
  }
  // 合格：藍色（必須在"複查合格"之後）
  if (statusStr.indexOf("合格") !== -1) {
    return "shop-status--qualified";
  }
  // 限期改善：橙色
  if (statusStr.indexOf("限期改善") !== -1) {
    return "shop-status--improvement";
  }
  // 輔導改善：淺橙色
  if (statusStr.indexOf("輔導改善") !== -1) {
    return "shop-status--guidance";
  }
  
  return "shop-status--default";
}

// 載入夜市店家資料
async function loadNightMarketShops(marketName) {
  if (!marketName) {
    shopData.value = { unqualified: [], good: [] };
    hasLoadedData.value = false;
    return;
  }

  isLoading.value = true;
  hasLoadedData.value = false;
  try {
    const data = await getNightMarketShops(marketName);
    
    const unqualified = [];
    const good = [];

    data.forEach((shop) => {
      const evaluationResult = shop.evaluationResult || "";
      const inspectionStatus = shop.inspectionStatus || "";
      
      // 優先使用 inspectionStatus 作為顯示狀態（代表最新的稽查狀態）
      // 如果沒有 inspectionStatus，則使用 evaluationResult
      const status = inspectionStatus || evaluationResult;
      
      const shopItem = {
        name: shop.stallName || shop.businessName || "",
        address: shop.address || "",
        status: status,
      };

      // 調試：記錄每個店家的狀態
      addDebugLog("log", "Shop evaluation result", {
        name: shopItem.name,
        evaluationResult: evaluationResult,
        inspectionStatus: inspectionStatus,
        status: shopItem.status,
        cardClass: getCardClass(status),
        statusClass: getStatusClass(status),
      });

      // 優先判斷 inspectionStatus（最新稽查狀態）
      // 如果 inspectionStatus 顯示不合格，則歸入不合格名單（優先級最高）
      // 否則根據 evaluationResult 判斷是否為優良店家
      if (inspectionStatus && isUnqualifiedShop(inspectionStatus)) {
        // 有 inspectionStatus 且為不合格，歸入不合格名單
        unqualified.push(shopItem);
      } else if (evaluationResult && isGoodShop(evaluationResult)) {
        // evaluationResult 為優良，歸入優良名單
        good.push(shopItem);
      } else if (evaluationResult && isUnqualifiedShop(evaluationResult)) {
        // 只有 evaluationResult 且為不合格，歸入不合格名單
        unqualified.push(shopItem);
      }
    });

    shopData.value = { unqualified, good };
    hasLoadedData.value = true; // 標記為已成功載入
    addDebugLog("log", "Night market shops loaded", {
      marketName,
      unqualified: unqualified.length,
      good: good.length,
    });
  } catch (error) {
    addDebugLog("error", "Failed to load night market shops", {
      marketName,
      error: error.message,
    });
    shopData.value = { unqualified: [], good: [] };
    hasLoadedData.value = false;
  } finally {
    isLoading.value = false;
  }
}

const selectedUnqualified = computed(() => shopData.value.unqualified || []);

const selectedGood = computed(() => shopData.value.good || []);

// 監聽選中的夜市變化
watch(selectedMarket, (newMarket) => {
  if (newMarket) {
    loadNightMarketShops(newMarket);
  }
});

onMounted(() => {
  // 從 JSON 文件載入夜市列表
  nightMarkets.value = nightMarketList;
  if (nightMarkets.value.length > 0) {
    selectedMarket.value = nightMarkets.value[0];
    loadNightMarketShops(selectedMarket.value);
  }
});

function goBack() {
  router.back();
}
</script>

<style scoped>
@import "@/styles/colors.css";
@import "https://fonts.googleapis.com/icon?family=Material+Icons";

.night-market-page {
  min-height: 100vh;
  background-color: var(--grayscale-50);
  display: flex;
  flex-direction: column;
}

/* AppBar */
.app-bar {
  background-color: var(--white);
  box-shadow: 0 2px 8px rgba(11, 13, 14, 0.08);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  height: 56px;
}

.back-button {
  background: none;
  border: none;
  cursor: pointer;
  padding: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--grayscale-700);
}

.back-button .material-icons {
  font-size: 24px;
}

.app-bar-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--primary-500);
  margin: 0;
  flex: 1;
  text-align: center;
}

.app-bar-spacer {
  width: 40px;
}

/* Content */
.content {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
}

/* Market Selector */
.market-selector-container {
  margin-bottom: 20px;
}

.market-selector {
  width: 100%;
  padding: 12px 16px;
  border: 1px solid var(--grayscale-200);
  border-radius: 8px;
  background-color: var(--white);
  font-size: 16px;
  color: var(--grayscale-800);
  cursor: pointer;
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%23475259' d='M6 9L1 4h10z'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 16px center;
  padding-right: 40px;
}

.market-selector:focus {
  outline: none;
  border-color: var(--primary-500);
}

/* Lists Container */
.lists-container {
  display: flex;
  flex-direction: column;
  gap: 24px;
}

/* Section */
.shop-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.section-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--grayscale-800);
  margin: 0;
}

/* Shop List */
.shop-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

/* Shop Card */
.shop-card {
  background-color: var(--white);
  border-radius: 8px;
  padding: 16px;
  box-shadow: 0 1px 3px rgba(11, 13, 14, 0.1);
}

.shop-card--default {
  border-left: 4px solid var(--grayscale-300);
}

/* 優良獎項顏色 */
.shop-card--gold {
  border-left: 4px solid #FFD700; /* 金色 */
}

.shop-card--silver {
  border-left: 4px solid #C0C0C0; /* 銀色 */
}

.shop-card--excellent {
  border-left: 4px solid #4CAF50; /* 綠色 */
}

.shop-card--qualified {
  border-left: 4px solid var(--primary-500); /* 藍色 */
}

.shop-card--recheck-qualified {
  border-left: 4px solid #81C784; /* 淺藍綠色 */
}

/* 不合格顏色 */
.shop-card--unqualified {
  border-left: 4px solid var(--red-500); /* 紅色 */
}

.shop-card--recheck-unqualified {
  border-left: 4px solid var(--red-600); /* 深紅色 */
}

.shop-card--improvement {
  border-left: 4px solid #FF9800; /* 橙色 */
}

.shop-card--guidance {
  border-left: 4px solid #FFB74D; /* 淺橙色 */
}

.shop-card-content {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
}

.shop-info {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.shop-name {
  font-size: 16px;
  font-weight: 600;
  color: var(--grayscale-800);
  margin: 0;
}

.shop-address {
  font-size: 14px;
  color: var(--grayscale-500);
  margin: 0;
}

.shop-status {
  font-size: 14px;
  font-weight: 600;
  padding: 4px 12px;
  border-radius: 12px;
  white-space: nowrap;
}

.shop-status--default {
  background-color: var(--grayscale-100);
  color: var(--grayscale-700);
}

/* 優良獎項顏色 */
.shop-status--gold {
  background-color: #FFF9C4; /* 淺金色背景 */
  color: #F57F17; /* 深金色文字 */
}

.shop-status--silver {
  background-color: #F5F5F5; /* 淺銀色背景 */
  color: #616161; /* 深灰色文字 */
}

.shop-status--excellent {
  background-color: #E8F5E9; /* 淺綠色背景 */
  color: #2E7D32; /* 深綠色文字 */
}

.shop-status--qualified {
  background-color: var(--primary-50); /* 淺藍色背景 */
  color: var(--primary-600); /* 深藍色文字 */
}

.shop-status--recheck-qualified {
  background-color: #E1F5FE; /* 淺藍綠色背景 */
  color: #0277BD; /* 深藍綠色文字 */
}

/* 不合格顏色 */
.shop-status--unqualified {
  background-color: var(--red-50); /* 淺紅色背景 */
  color: var(--red-600); /* 深紅色文字 */
}

.shop-status--recheck-unqualified {
  background-color: #FFEBEE; /* 淺深紅色背景 */
  color: #C62828; /* 深紅色文字 */
}

.shop-status--improvement {
  background-color: #FFF3E0; /* 淺橙色背景 */
  color: #E65100; /* 深橙色文字 */
}

.shop-status--guidance {
  background-color: #FFF8E1; /* 淺淺橙色背景 */
  color: #F57C00; /* 橙色文字 */
}

/* Empty State */
.empty-state {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 64px 16px;
  text-align: center;
}

.empty-state-text {
  font-size: 16px;
  color: var(--grayscale-500);
  margin: 0;
}

.empty-state-text--success {
  color: var(--primary-600);
  font-weight: 600;
  font-size: 24px;
}
</style>
