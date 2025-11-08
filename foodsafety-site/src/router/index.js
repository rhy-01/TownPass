import { createRouter, createWebHistory } from "vue-router";
import FoodSafetyWebView from "@/views/FoodSafetyWebView.vue";
import FoodSafetyActivityView from "@/views/FoodSafetyActivityView.vue";
import AddAddressPage from "@/views/AddAddressPage.vue";
import StorePage from "@/views/StorePage.vue";
import NotificationPage from "@/views/NotificationPage.vue";
import NightMarketPage from "@/views/NightMarketPage.vue";
import ReceiptPage from "@/views/ReceiptPage.vue";

const routes = [
  { path: "/", name: "FoodSafetyWebView", component: FoodSafetyWebView },
  { path: "/activities", name: "FoodSafetyActivityView", component: FoodSafetyActivityView },
  { path: "/add-address", name: "AddAddressPage", component: AddAddressPage },
  { path: "/store", name: "StorePage", component: StorePage },
  { path: "/notification", name: "NotificationPage", component: NotificationPage },
  { path: "/night-market", name: "NightMarketPage", component: NightMarketPage },
  { path: "/receipt", name: "ReceiptPage", component: ReceiptPage },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
});

export default router;
