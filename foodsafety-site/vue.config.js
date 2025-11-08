const { defineConfig } = require('@vue/cli-service')
module.exports = defineConfig({
  transpileDependencies: true,
  devServer: {
    proxy: {
      '/api': {
        target: 'https://all-integrate-api-745797496080.asia-east1.run.app',
        changeOrigin: true,
        secure: true,
        pathRewrite: {
          '^/api': ''
        },
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        }
      }
    }
  }
})
