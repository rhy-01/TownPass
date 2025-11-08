<template>
  <div class="receipt-page">
    <!-- AppBar -->
    <header class="app-bar">
      <button
        class="back-button"
        @click="goBack"
      >
        <span class="material-icons">arrow_back</span>
      </button>
      <h1 class="app-bar-title">
        發票資訊
      </h1>
      <div class="app-bar-spacer" />
    </header>

    <!-- Content -->
    <main class="content">
      <!-- Month Selector -->
      <div class="month-selector">
        <button
          class="month-nav-button"
          @click="prevMonth"
        >
          <span class="material-icons">chevron_left</span>
        </button>
        <h2 class="month-title">
          {{ currentMonthText }}
        </h2>
        <button
          class="month-nav-button"
          @click="nextMonth"
        >
          <span class="material-icons">chevron_right</span>
        </button>
      </div>

      <!-- Receipt List -->
      <div
        v-if="currentMonthReceipts.length > 0"
        class="receipt-list"
      >
        <article
          v-for="(receipt, index) in currentMonthReceipts"
          :key="index"
          class="receipt-card"
          :class="getAuditResultClass(receipt.auditResult)"
        >
          <div class="receipt-card-content">
            <div class="receipt-header">
              <h3 class="receipt-title">
                {{ receipt.storeName }}
              </h3>
              <span
                v-if="receipt.auditResult !== '合格'"
                class="receipt-audit-badge"
                :class="getAuditBadgeClass(receipt.auditResult)"
              >
                {{ receipt.auditResult }}
              </span>
            </div>
            <div class="receipt-info">
              <p class="receipt-date">
                {{ receipt.date }}
              </p>
              <p class="receipt-seller-id">
                統編: {{ receipt.sellerId }}
              </p>
            </div>
          </div>
        </article>
      </div>
      <div
        v-else
        class="empty-state"
      >
        <p class="empty-state-text">
          此月份尚無發票資料
        </p>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import { useRouter } from "vue-router";
import receiptData from "@/data/receipt.json";

const router = useRouter();

// Current month
const currentDate = ref(new Date());

// Receipt data from JSON
const receipts = ref([]);

// Transform receipt data from JSON format to component format
function transformReceiptData(data) {
  return data.map((item, index) => {
    // Parse date from "2025-11-05-14:00" to "2025-11-05"
    const dateStr = item["發票日期"];
    const dateOnly = dateStr.split("-").slice(0, 3).join("-");
    
    return {
      id: index + 1,
      storeName: item["賣方名稱"],
      sellerId: item["賣方統編"],
      date: dateOnly,
      auditResult: item["稽核結果"],
    };
  });
}

// Get current month text
const currentMonthText = computed(() => {
  const year = currentDate.value.getFullYear();
  const month = currentDate.value.getMonth() + 1;
  return `${year}年${month}月`;
});

// Get receipts for current month
const currentMonthReceipts = computed(() => {
  const year = currentDate.value.getFullYear();
  const month = currentDate.value.getMonth();
  return receipts.value.filter((receipt) => {
    const receiptDate = new Date(receipt.date);
    return (
      receiptDate.getFullYear() === year && receiptDate.getMonth() === month
    );
  });
});

// Get CSS class based on audit result
function getAuditResultClass(auditResult) {
  const classMap = {
    "合格": "receipt-card--qualified",
    "複查合格": "receipt-card--recheck-qualified",
    "限期改善": "receipt-card--improvement",
    "複查不合格": "receipt-card--unqualified",
    "輔導改善": "receipt-card--guidance",
  };
  return classMap[auditResult] || "receipt-card--default";
}

// Get badge CSS class based on audit result
function getAuditBadgeClass(auditResult) {
  const classMap = {
    "複查合格": "receipt-audit-badge--success",
    "限期改善": "receipt-audit-badge--warning",
    "複查不合格": "receipt-audit-badge--error",
    "輔導改善": "receipt-audit-badge--guidance",
  };
  return classMap[auditResult] || "receipt-audit-badge--default";
}

function prevMonth() {
  const newDate = new Date(currentDate.value);
  newDate.setMonth(newDate.getMonth() - 1);
  currentDate.value = newDate;
}

function nextMonth() {
  const newDate = new Date(currentDate.value);
  newDate.setMonth(newDate.getMonth() + 1);
  currentDate.value = newDate;
}

function goBack() {
  router.back();
}

// Load receipt data on mount
onMounted(() => {
  receipts.value = transformReceiptData(receiptData);
});
</script>

<style scoped>
@import "@/styles/colors.css";

.receipt-page {
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
  display: flex;
  flex-direction: column;
  gap: 16px;
}

/* Month Selector */
.month-selector {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background-color: var(--white);
  border-radius: 8px;
  padding: 12px 16px;
  box-shadow: 0 1px 3px rgba(11, 13, 14, 0.1);
}

.month-nav-button {
  background: none;
  border: none;
  cursor: pointer;
  padding: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--grayscale-700);
  border-radius: 4px;
  transition: background-color 0.2s;
}

.month-nav-button:hover {
  background-color: var(--grayscale-50);
}

.month-nav-button .material-icons {
  font-size: 24px;
}

.month-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--grayscale-800);
  margin: 0;
}

/* Receipt List */
.receipt-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

/* Receipt Card */
.receipt-card {
  background-color: var(--white);
  border-radius: 8px;
  padding: 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: 0 1px 3px rgba(11, 13, 14, 0.1);
  cursor: pointer;
  transition: background-color 0.2s;
  border-left: 4px solid transparent;
}

.receipt-card:active {
  background-color: var(--grayscale-50);
}

/* 合格 - 白色背景，綠色邊框 */
.receipt-card--qualified {
  background-color: var(--white);
  border-left-color: #4CAF50;
}

.receipt-card--qualified:active {
  background-color: var(--grayscale-50);
}

/* 複查合格 - 淺綠色背景 */
.receipt-card--recheck-qualified {
  background-color: #E8F5E9;
  border-left-color: #4CAF50;
}

.receipt-card--recheck-qualified:active {
  background-color: #C8E6C9;
}

/* 限期改善 - 黃色背景 */
.receipt-card--improvement {
  background-color: #FFF9E6;
  border-left-color: var(--secondary-500);
}

.receipt-card--improvement:active {
  background-color: #FFF3C4;
}

/* 複查不合格 - 紅色背景 */
.receipt-card--unqualified {
  background-color: var(--red-50);
  border-left-color: var(--red-500);
}

.receipt-card--unqualified:active {
  background-color: var(--red-100);
}

/* 輔導改善 - 橙色背景 */
.receipt-card--guidance {
  background-color: #FFF3E0;
  border-left-color: #FF9800;
}

.receipt-card--guidance:active {
  background-color: #FFE0B2;
}

/* 預設樣式 */
.receipt-card--default {
  background-color: var(--white);
  border-left-color: var(--grayscale-300);
}

.receipt-card-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.receipt-header {
  display: flex;
  align-items: center;
  gap: 8px;
}

.receipt-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--grayscale-800);
  margin: 0;
}

.receipt-audit-badge {
  font-size: 12px;
  font-weight: 600;
  color: var(--white);
  padding: 2px 8px;
  border-radius: 12px;
}

.receipt-audit-badge--success {
  background-color: #4CAF50;
}

.receipt-audit-badge--warning {
  background-color: var(--secondary-500);
}

.receipt-audit-badge--error {
  background-color: var(--red-500);
}

.receipt-audit-badge--guidance {
  background-color: #FF9800;
}

.receipt-audit-badge--default {
  background-color: var(--grayscale-500);
}

.receipt-info {
  display: flex;
  align-items: center;
  gap: 16px;
}

.receipt-date {
  font-size: 14px;
  color: var(--grayscale-500);
  margin: 0;
}

.receipt-seller-id {
  font-size: 14px;
  color: var(--grayscale-600);
  margin: 0;
}

.receipt-card-arrow {
  font-size: 24px;
  color: var(--grayscale-400);
  flex-shrink: 0;
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
</style>

