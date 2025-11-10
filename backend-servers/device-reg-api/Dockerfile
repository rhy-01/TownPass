# 基礎映像檔：使用高效的 Node.js 運行時
# 明確指定 amd64 架構以兼容 Cloud Run
FROM --platform=linux/amd64 node:20-slim

# 設置工作目錄
WORKDIR /usr/src/app

# 複製 package.json 和 package-lock.json (利用 Docker Layer 快取)
COPY package*.json ./

# 安裝依賴
RUN npm install --omit=dev

# 複製應用程式原始碼
COPY . .

# Cloud Run 要求應用程式監聽 $PORT 環境變數，預設為 8081
ENV PORT=8081

# 暴露端口
EXPOSE 8081

# 啟動 Node.js Server
CMD [ "node", "index.js" ]

