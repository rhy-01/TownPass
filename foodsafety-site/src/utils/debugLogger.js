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
  
  // 更新頁面上的調試面板
  updateDebugPanel();
}

/**
 * 初始化調試面板
 */
function initDebugPanel() {
  if (document.getElementById('debug-panel')) {
    return; // 已經初始化
  }
  
  // 創建調試面板
  const panel = document.createElement('div');
  panel.id = 'debug-panel';
  panel.style.cssText = `
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    max-height: 200px;
    overflow-y: auto;
    background-color: rgba(0, 0, 0, 0.95);
    color: #fff;
    font-family: 'Courier New', monospace;
    font-size: 11px;
    padding: 8px;
    z-index: 10000;
    display: none;
    border-top: 2px solid #5AB4C5;
    box-shadow: 0 -2px 8px rgba(0,0,0,0.3);
  `;
  
  // 添加清除按鈕
  const clearBtn = document.createElement('button');
  clearBtn.textContent = '清除';
  clearBtn.style.cssText = `
    position: absolute;
    top: 8px;
    right: 8px;
    padding: 4px 8px;
    background-color: #D45251;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 11px;
    z-index: 1;
  `;
  clearBtn.onclick = () => {
    debugLogs.length = 0;
    updateDebugPanel();
  };
  panel.appendChild(clearBtn);
  
  // 添加內容容器
  const content = document.createElement('div');
  content.id = 'debug-panel-content';
  panel.appendChild(content);
  
  document.body.appendChild(panel);
  
  // 添加切換按鈕
  const toggleBtn = document.createElement('button');
  toggleBtn.id = 'debug-toggle';
  toggleBtn.textContent = '🐛';
  toggleBtn.style.cssText = `
    position: fixed;
    bottom: 10px;
    right: 10px;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background-color: #5AB4C5;
    color: white;
    border: none;
    cursor: pointer;
    z-index: 10001;
    font-size: 20px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    display: flex;
    align-items: center;
    justify-content: center;
  `;
  toggleBtn.onclick = () => {
    const panel = document.getElementById('debug-panel');
    if (panel) {
      const isVisible = panel.style.display !== 'none';
      panel.style.display = isVisible ? 'none' : 'block';
    }
  };
  document.body.appendChild(toggleBtn);
}

/**
 * 更新調試面板
 */
function updateDebugPanel() {
  // 確保面板已初始化
  if (typeof document === 'undefined') {
    return;
  }
  
  // 如果 DOM 還沒準備好，等待一下
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      initDebugPanel();
      updateDebugPanel();
    });
    return;
  }
  
  initDebugPanel();
  
  const panel = document.getElementById('debug-panel');
  const content = document.getElementById('debug-panel-content');
  
  if (!panel || !content) {
    return;
  }
  
  // 更新內容
  content.style.cssText = 'padding-right: 60px;';
  
  if (debugLogs.length === 0) {
    content.innerHTML = '<div style="color: #888; padding: 8px;">暫無日誌</div>';
  } else {
    const logsHtml = debugLogs.slice(-20).reverse().map(log => {
      const levelColor = {
        error: '#D45251',
        warn: '#F5BA4B',
        log: '#5AB4C5'
      }[log.level] || '#fff';
      
      const borderColor = {
        error: '#D45251',
        warn: '#F5BA4B',
        log: '#5AB4C5'
      }[log.level] || '#5AB4C5';
      
      return `
        <div style="
          padding: 4px 8px;
          margin-bottom: 2px;
          border-left: 3px solid ${borderColor};
          background-color: rgba(255,255,255,0.05);
        ">
          <span style="color: #888; font-size: 10px;">[${log.timestamp}]</span>
          <span style="color: ${levelColor}; font-weight: bold; margin-left: 8px;">${log.level.toUpperCase()}</span>
          <span style="color: #fff; margin-left: 8px;">${escapeHtml(log.message)}</span>
          ${log.data ? `<pre style="margin: 4px 0 0 0; color: #aaa; font-size: 10px; white-space: pre-wrap; word-break: break-all;">${escapeHtml(log.data)}</pre>` : ''}
        </div>
      `;
    }).join('');
    
    content.innerHTML = logsHtml;
  }
  
  // 自動滾動到底部
  panel.scrollTop = panel.scrollHeight;
}

/**
 * 轉義 HTML 字符
 */
function escapeHtml(text) {
  if (!text) return '';
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// 在模塊加載時初始化面板
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initDebugPanel);
  } else {
    // DOM 已經準備好
    setTimeout(initDebugPanel, 100);
  }
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
  updateDebugPanel();
}

