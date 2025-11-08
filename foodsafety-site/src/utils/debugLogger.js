/**
 * 調試日誌工具
 * 在 App 環境中顯示調試信息，方便查看 bug
 */

const debugLogs = [];
const MAX_LOGS = 100;

/**
 * 添加調試日誌
 * @param {string} level - 日誌級別: 'log', 'warn', 'error'
 * @param {string} message - 日誌消息
 * @param {any} data - 可選的數據對象
 */
export function addDebugLog(level, message, data = null) {
  const timestamp = new Date().toLocaleTimeString('zh-TW');
  const logEntry = {
    timestamp,
    level,
    message,
    data: data ? JSON.stringify(data, null, 2) : null
  };
  
  debugLogs.push(logEntry);
  
  // 限制日誌數量
  if (debugLogs.length > MAX_LOGS) {
    debugLogs.shift();
  }
  
  // 同時輸出到 console（開發環境）
  if (process.env.NODE_ENV === 'development') {
    const consoleMethod = console[level] || console.log;
    consoleMethod(`[${timestamp}] ${message}`, data || '');
  }
  
  // 不再更新頁面上的調試面板（已移除 debug UI）
}

/**
 * 導出日誌
 */
export function getDebugLogs() {
  return [...debugLogs];
}

/**
 * 清除日誌
 */
export function clearDebugLogs() {
  debugLogs.length = 0;
}

