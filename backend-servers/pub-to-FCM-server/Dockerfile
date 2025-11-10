# 基礎映像檔：使用高效的 Node.js 運行時
# 注意：Cloud Build 會自動為 Cloud Run 構建 linux/amd64 平台
FROM node:20-slim

# 設置工作目錄
WORKDIR /usr/src/app

# 複製 package.json 和 package-lock.json (利用 Docker Layer 快取)
COPY package*.json ./

# 安裝依賴
RUN npm install --omit=dev

# 複製應用程式原始碼
COPY . .

# 暴露端口
# 注意：Cloud Run 會自動設置 PORT 環境變數，應用程式應使用 process.env.PORT
# index.js 中已正確處理：const PORT = process.env.PORT || 8081
EXPOSE 8081

# 啟動 Node.js Server
CMD [ "node", "index.js" ]

