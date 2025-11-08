# 環境變數設定說明

## Google Maps API Key 設定

1. 在專案根目錄創建 `.env` 文件
2. 在 `.env` 文件中添加以下內容：

```
VUE_APP_GOOGLE_MAPS_API_KEY=你的Google_Maps_API_Key
```

3. 獲取 Google Maps API Key：
   - 前往 [Google Cloud Console](https://console.cloud.google.com/)
   - 創建新專案或選擇現有專案
   - 啟用 "Maps JavaScript API" 和 "Geocoding API"
   - 創建 API Key
   - 將 API Key 複製到 `.env` 文件中

4. 重新啟動開發伺服器：
   ```bash
   npm run serve
   ```

## 注意事項

- `.env` 文件已加入 `.gitignore`，不會被提交到版本控制
- 請勿將 API Key 提交到公開倉庫
- 在生產環境中，請確保 API Key 有適當的使用限制

