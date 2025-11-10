const express = require('express');
const { PubSub } = require('@google-cloud/pubsub');
const { registerDevice } = require('./db');

// 初始化 Firebase（這會自動連接 Firestore）
const { admin, db } = require('./firebase');

// 配置
const TOPIC_ID = 'data-update-notifications'; 
const pubSubClient = new PubSub();
const app = express();
app.use(express.json());

// ----------------------------------------------------
// 設備註冊 API 端點
// ----------------------------------------------------
app.post('/api/register-device', async (req, res) => {
    const { userId, fcmToken, latitude, longitude, timestamp } = req.body;

    // 驗證必要參數
    if (!userId || !fcmToken) {
        return res.status(400).send({ 
            error: 'Missing required parameters: userId and fcmToken are required.' 
        });
    }

    try {
        // 記錄設備註冊資訊
        console.log(`Device registration for user ${userId}:`);
        console.log(`  - FCM Token: ${fcmToken.substring(0, 20)}...`);
        console.log(`  - Location: ${latitude}, ${longitude}`);
        console.log(`  - Timestamp: ${timestamp || new Date().toISOString()}`);

        // 儲存設備資訊到 Firestore
        const deviceData = await registerDevice({
            userId,
            fcmToken,
            latitude,
            longitude,
            timestamp
        });

        res.status(200).send({ 
            message: 'Device registered successfully.',
            deviceId: deviceData.deviceId,
            userId,
            registeredAt: deviceData.registeredAt
        });

    } catch (error) {
        console.error('Error in device registration:', error);
        res.status(500).send({ 
            error: 'Internal server error during device registration.',
            details: error.message 
        });
    }
});

// ----------------------------------------------------
// 主業務 API 端點 (範例: 處理用戶的資料更新請求)
// ----------------------------------------------------
app.post('/api/data/update', async (req, res) => {
    const { userId, dataKey, newValue, notificationTitle, notificationBody } = req.body;

    if (!userId || !dataKey) {
        return res.status(400).send({ error: 'Missing required parameters.' });
    }
    
    // 步驟 1: 執行核心業務邏輯 (例如，更新資料庫)
    try {
        // [TODO: 在這裡加入您的資料庫寫入或業務邏輯]
        console.log(`Processing update for user ${userId} on key ${dataKey} to ${newValue}`);
        // await db.update(dataKey, newValue); 
        
        // 步驟 2: 判斷是否需要通知 (假設每次更新都需要)
        const targetUrl = `/webview/data-view?user=${userId}&key=${dataKey}`;

        // 步驟 3: 發布 Pub/Sub 事件 (觸發 FCM 推送)
        await publishNotificationEvent({
            targetUserIds: [userId], // 通知單一用戶
            notificationTitle: notificationTitle || '您的資料已更新',
            notificationBody: notificationBody || '點擊查看變更內容。',
            targetUrl: targetUrl 
        });
        
        res.status(200).send({ 
            message: 'Data processed and notification event published.',
            publishedToTopic: TOPIC_ID
        });

    } catch (error) {
        console.error('Error in API or Pub/Sub publish:', error);
        res.status(500).send({ error: 'Internal server error during processing.' });
    }
});

// 健康檢查端點（Cloud Run 標準）
app.get('/health', (req, res) => {
    res.status(200).send('OK');
});

// // ----------------------------------------------------
// // 測試 FCM 推播 API 端點
// // ----------------------------------------------------
// app.post('/api/test-fcm', async (req, res) => {
//     try {
//         const { 
//             restaurant_name, 
//             latitude, 
//             longitude, 
//             reg_no,
//             title,
//             message
//         } = req.body;

//         // 驗證必要參數
//         if (!restaurant_name || latitude === undefined || longitude === undefined) {
//             return res.status(400).send({ 
//                 error: 'Missing required parameters: restaurant_name, latitude, longitude are required.' 
//             });
//         }

//         console.log('=========================================');
//         console.log('🧪 測試 FCM 推播');
//         console.log('=========================================');
//         console.log(`餐廳名稱: ${restaurant_name}`);
//         console.log(`經緯度: (${latitude}, ${longitude})`);
//         if (reg_no) {
//             console.log(`登記號碼: ${reg_no}`);
//         }
//         console.log('');

//         // 1. 獲取所有用戶的 FCM Tokens
//         console.log('📥 開始獲取所有用戶的 FCM Tokens...');
//         const userTokens = await getAllFCMTokens();

//         if (userTokens.length === 0) {
//             return res.status(200).send({
//                 success: false,
//                 message: 'No FCM tokens found',
//                 total_users: 0,
//                 total_tokens: 0
//             });
//         }

//         const allTokens = userTokens.flatMap(ut => ut.tokens);
//         console.log(`✅ 找到 ${userTokens.length} 個用戶，共 ${allTokens.length} 個 FCM Tokens`);
//         console.log('');

//         // 2. 構建 FCM 消息
//         const notificationTitle = title || '1'; // 預設為 "1" 讓 App 顯示通知
//         const notificationBody = message || `餐廳 '${restaurant_name}' 稽查結果不合格`;
        
//         const fcmData = {
//             title: notificationTitle,
//             body: notificationBody,
//             targetUrl: reg_no ? `/restaurant/${reg_no}` : '/default',
//             type: 'inspection_failure',
//             timestamp: new Date().toISOString(),
//             restaurant_name: restaurant_name,
//             restaurant_latitude: String(latitude),
//             restaurant_longitude: String(longitude),
//         };

//         if (reg_no) {
//             fcmData.restaurant_reg_no = reg_no;
//         }

//         // 3. 發送 FCM 消息
//         console.log('📤 開始發送 FCM 推播...');
//         const messaging = admin.messaging();
//         const MAX_TOKENS_PER_BATCH = 500;
//         let totalSuccessCount = 0;
//         let totalFailureCount = 0;

//         // 分批發送
//         for (let i = 0; i < allTokens.length; i += MAX_TOKENS_PER_BATCH) {
//             const batchTokens = allTokens.slice(i, i + MAX_TOKENS_PER_BATCH);
//             const batchNumber = Math.floor(i / MAX_TOKENS_PER_BATCH) + 1;
//             const totalBatches = Math.ceil(allTokens.length / MAX_TOKENS_PER_BATCH);

//             console.log(`發送批次 ${batchNumber}/${totalBatches} (${batchTokens.length} 個設備)...`);

//             const message = {
//                 tokens: batchTokens,
//                 data: fcmData,
//             };

//             try {
//                 const response = await messaging.sendEachForMulticast(message);
//                 totalSuccessCount += response.successCount;
//                 totalFailureCount += response.failureCount;

//                 console.log(`批次 ${batchNumber} 結果: 成功 ${response.successCount}, 失敗 ${response.failureCount}`);

//                 // 處理失敗的 Token
//                 if (response.failureCount > 0) {
//                     response.responses.forEach((resp, idx) => {
//                         if (!resp.success) {
//                             console.error(`❌ 發送失敗 - Token ${idx + 1}: ${batchTokens[idx].substring(0, 50)}...`);
//                             console.error(`   錯誤: ${resp.error?.message || resp.error}`);
//                         }
//                     });
//                 }
//             } catch (error) {
//                 console.error(`❌ 批次 ${batchNumber} 發送失敗:`, error.message);
//                 totalFailureCount += batchTokens.length;
//             }
//         }

//         console.log('=========================================');
//         console.log(`📊 FCM 推播總計結果`);
//         console.log(`=========================================`);
//         console.log(`✅ 成功: ${totalSuccessCount} 則`);
//         console.log(`❌ 失敗: ${totalFailureCount} 則`);
//         console.log(`📱 總 Token 數: ${allTokens.length}`);
//         console.log(`👥 用戶數量: ${userTokens.length}`);
//         console.log('=========================================');

//         res.status(200).send({
//             success: true,
//             message: 'FCM test notification sent',
//             result: {
//                 total_users: userTokens.length,
//                 total_tokens: allTokens.length,
//                 success_count: totalSuccessCount,
//                 failure_count: totalFailureCount
//             }
//         });

//     } catch (error) {
//         console.error('❌ 測試 FCM 推播失敗:', error);
//         res.status(500).send({ 
//             error: 'Failed to send test FCM notification',
//             details: error.message 
//         });
//     }
// });

// ----------------------------------------------------
// 輔助函數：獲取所有用戶的 FCM Tokens
// ----------------------------------------------------
async function getAllFCMTokens() {
    if (!db) {
        throw new Error('Firestore database is not initialized');
    }

    const userTokens = [];
    
    try {
        // 獲取 users collection 中的所有文檔
        const snapshot = await db.collection('users').get();
        
        console.log(`找到 ${snapshot.size} 個用戶文檔`);
        
        snapshot.docs.forEach((doc, index) => {
            const userId = doc.id;
            const userData = doc.data();
            const tokens = extractTokensFromUserData(userData);
            
            // 如果有找到 Token，添加到結果中
            if (tokens.length > 0) {
                userTokens.push({
                    userId: userId,
                    tokens: tokens
                });
                
                // 每處理 100 個用戶輸出一次進度
                if ((index + 1) % 100 === 0) {
                    console.log(`  已處理 ${index + 1}/${snapshot.size} 個用戶...`);
                }
            }
        });
        
        const totalTokens = userTokens.reduce((sum, ut) => sum + ut.tokens.length, 0);
        console.log(`✅ 成功獲取 ${userTokens.length} 個用戶的 FCM Tokens，共 ${totalTokens} 個 Token`);
        
        return userTokens;
    } catch (error) {
        console.error('❌ 獲取所有用戶 FCM Tokens 時發生錯誤:', error);
        throw error;
    }
}

// ----------------------------------------------------
// 輔助函數：從用戶資料中提取 FCM Tokens
// ----------------------------------------------------
function extractTokensFromUserData(userData) {
    const tokens = [];
    
    // 從 devices 陣列中讀取 fcmToken
    if (userData.devices && Array.isArray(userData.devices)) {
        userData.devices.forEach((device) => {
            if (device && device.fcmToken) {
                tokens.push(device.fcmToken);
            }
        });
    }
    
    // 向後兼容：如果文件根部也有 fcmToken（舊格式），也加入
    if (userData.fcmToken) {
        if (!tokens.includes(userData.fcmToken)) {
            tokens.push(userData.fcmToken);
        }
    }
    
    return tokens;
}

// ----------------------------------------------------
// 輔助函數：發布到 Pub/Sub
// ----------------------------------------------------
async function publishNotificationEvent(payload) {
    // 檢查 Pub/Sub SDK 是否能使用 GCP 服務帳戶的權限
    if (!pubSubClient) {
        throw new Error("PubSub client not initialized. Check IAM permissions.");
    }
    
    // 數據必須是 Base64 編碼的字串 (JSON 字串的 Buffer)
    const dataBuffer = Buffer.from(JSON.stringify(payload));

    const messageId = await pubSubClient
        .topic(TOPIC_ID)
        .publishMessage({data: dataBuffer});
        
    console.log(`Notification event published with ID: ${messageId}`);
    return messageId;
}

// 啟動 Server
const PORT = process.env.PORT || 8081;
app.listen(PORT, () => {
  console.log(`API Service (Event Publisher) started on port ${PORT}`);
});

