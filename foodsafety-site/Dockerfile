# Dockerfile
FROM nginx:alpine

# 安裝 curl 用於健康檢查
RUN apk add --no-cache curl

# 複製構建好的文件
COPY dist/ /usr/share/nginx/html

# 複製 nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 測試 nginx 配置語法
RUN nginx -t

# 暴露端口
EXPOSE 8081

# 啟動 nginx
CMD ["nginx", "-g", "daemon off;"]