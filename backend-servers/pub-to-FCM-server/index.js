const express = require('express');
const admin = require('firebase-admin');

/**
 * FCM Push Service - Cloud Run 服務
 * 
 * 功能：
 * - 接收 Pub/Sub 推送訊息
 * - 從 Firestore 查詢用戶的 FCM Token
 * - 發送 FCM 推播通知給多個用戶
 * 
 * 📡 Pub/Sub Topic 配置：
 * - Topic 名稱: data-update-notifications
 * - 完整路徑: projects/micro-service-477116/topics/data-update-notifications
 * - 編碼: UTF-8 JSON
 * - 訂閱者: cloudrun-fcm-trigger-sub (Push 訂閱，推送到此服務)
 * 
 * 📋 支援的訊息格式：
 * 
 * 1. 餐廳稽查不合格通知 (type: "inspection_failure") - 專用格式
 *    來自 food-sync-service，當 GCS inspection/latest.json 檔案更新時觸發
 *    {
 *      "type": "inspection_failure",  // 字串類型，不是 JSON 物件
 *      "title": "通知標題",
 *      "message": "通知內容",
 *      "targetUserIds": ["user1", "user2"],  // 可選，如果沒有則不會發送推播
 *      "restaurant_info": {
 *        "name": "餐廳名稱",
 *        "address": "地址",
 *        "phone": "電話",
 *        "reg_no": "登記號碼",
 *        "status": "狀態",
 *        "inspection_date": "稽查日期"
 *      },
 *      "timestamp": "ISO 8601 時間戳",
 *      "severity": "嚴重程度"
 *    }
 * 
 * 2. 通用通知格式（舊格式，向後兼容）:
 *    {
 *      "targetUserIds": ["user1", "user2"],
 *      "notificationTitle": "通知標題",
 *      "notificationBody": "通知內容",
 *      "targetUrl": "/path"
 *    }
 * 
 * ⚠️  注意事項：
 * - type 欄位是字串類型（例如："inspection_failure"），不是 JSON 物件
 * - 整個 Pub/Sub 訊息是 JSON 格式，但 type 只是其中的一個字串屬性
 * - FCM data 欄位中的所有值都必須轉換為字串類型
 * - 如果沒有提供 targetUserIds，將發送推播通知給所有 Firestore 中的用戶（廣播模式）
 * - 如果提供了 targetUserIds，只發送給指定的用戶（精準推送模式）
 */

// 初始化 Firebase Admin SDK
let firebaseInitialized = false;
let firebaseProjectId = 'micro-service-477116';

try {
    // 在 Cloud Run 中，SDK 會自動使用服務帳戶憑證
    // 注意：專案必須在 Firebase Console 中設置才能使用 FCM
    admin.initializeApp({
        projectId: firebaseProjectId,
    });
    firebaseInitialized = true;
    console.log(`✅ Firebase Admin SDK 初始化成功`);
    console.log(`📦 專案 ID: ${firebaseProjectId}`);
    
    // 驗證專案配置
    const app = admin.app();
    console.log(`🔍 驗證 Firebase 專案配置...`);
    console.log(`   專案 ID: ${app.options.projectId}`);
} catch (error) {
    console.error('❌ Firebase Admin SDK 初始化失敗:', error);
    console.error('   錯誤訊息:', error.message);
    console.error('   錯誤代碼:', error.code || 'UNKNOWN');
    console.error('');
    console.error('💡 可能的解決方案:');
    console.error('   1. 確認專案已在 Firebase Console 中設置');
    console.error('   2. 訪問: https://console.firebase.google.com/project/' + firebaseProjectId);
    console.error('   3. 確認 Firebase Cloud Messaging API 已啟用');
    console.error('   4. 確認服務帳戶有正確的權限');
    firebaseInitialized = false;
}

const app = express();

// Pub/Sub 推送訊息是 JSON 格式
app.use(express.json());

// Cloud Run 服務應監聽的入口端點
app.post('/', async (req, res) => {
    // 檢查 Firebase 初始化
    if (!firebaseInitialized) {
        console.error('Firebase Admin SDK 未初始化，無法處理請求');
        return res.status(500).send('Service Unavailable: Firebase not initialized');
    }

    // 檢查 Pub/Sub 訊息格式
    if (!req.body || !req.body.message || !req.body.message.data) {
        console.error('❌ 無效的 Pub/Sub 訊息格式: 缺少 message.data 欄位');
        console.error('收到的請求 body:', JSON.stringify(req.body, null, 2));
        console.error('請求 headers:', JSON.stringify(req.headers, null, 2));
        
        // 檢查是否是直接訪問（非 Pub/Sub 請求）
        const userAgent = req.headers['user-agent'] || '';
        if (userAgent.includes('Mozilla') || userAgent.includes('Chrome') || userAgent.includes('Safari')) {
            return res.status(400).json({
                error: 'Invalid request format',
                message: 'This endpoint expects Pub/Sub push messages, not direct browser/HTTP requests.',
                hint: 'Please send messages through Pub/Sub topic: data-update-notifications',
                endpoint: 'This is a Cloud Run service for Pub/Sub push subscriptions',
                usage: 'Use gcloud pubsub topics publish or the Pub/Sub API to send messages'
            });
        }
        
        return res.status(400).json({
            error: 'Invalid Pub/Sub message format',
            message: 'Missing message.data field. This endpoint expects Pub/Sub push messages.',
            receivedBody: req.body
        });
    }

    try {
        // 1. 解碼 Pub/Sub 訊息
        // Pub/Sub data 是 Base64 編碼的 JSON
        
        let rawMessageData;
        try {
            // 嘗試 Base64 解碼
            rawMessageData = Buffer.from(req.body.message.data, 'base64').toString('utf8');
        } catch (decodeError) {
            console.error('❌ Base64 解碼失敗:', decodeError.message);
            console.error('原始 data (前100字符):', req.body.message.data.substring(0, 100));
            console.error('原始 data 長度:', req.body.message.data.length);
            
            // 檢查是否是非 Base64 格式的字符串
            if (typeof req.body.message.data === 'string' && !/^[A-Za-z0-9+/=]+$/.test(req.body.message.data)) {
                return res.status(400).json({
                    error: 'Invalid request format',
                    message: 'The message.data field should be Base64-encoded JSON, but received plain text.',
                    hint: 'This endpoint expects Pub/Sub push messages. Please send messages through Pub/Sub topic.',
                    receivedDataPreview: req.body.message.data.substring(0, 100)
                });
            }
            
            return res.status(400).json({
                error: 'Invalid Base64 encoding',
                message: 'Failed to decode message.data from Base64',
                errorDetail: decodeError.message
            });
        }
        
        let updateEvent;
        try {
            updateEvent = JSON.parse(rawMessageData);
        } catch (parseError) {
            console.error('❌ JSON 解析失敗:', parseError.message);
            console.error('解碼後的原始數據 (前200字符):', rawMessageData.substring(0, 200));
            console.error('數據長度:', rawMessageData.length);
            console.error('數據類型:', typeof rawMessageData);
            console.error('是否包含中文字符:', /[\u4e00-\u9fa5]/.test(rawMessageData));
            
            // 檢查是否包含中文字符（可能是直接發送的文本）
            if (/[\u4e00-\u9fa5]/.test(rawMessageData) && rawMessageData.length < 500) {
                return res.status(400).json({
                    error: 'Invalid request format',
                    message: 'Received plain text instead of JSON. This endpoint expects Pub/Sub push messages with Base64-encoded JSON.',
                    hint: 'Please send messages through Pub/Sub topic: data-update-notifications',
                    receivedData: rawMessageData,
                    note: 'If you want to test, use: gcloud pubsub topics publish data-update-notifications --message=\'{"type":"inspection_failure",...}\''
                });
            }
            
            return res.status(400).json({
                error: 'Invalid JSON format',
                message: 'Failed to parse message data as JSON',
                errorDetail: parseError.message,
                receivedDataPreview: rawMessageData.substring(0, 200)
            });
        }

        console.log('=========================================');
        console.log('✅ 成功解析 Pub/Sub 訊息');
        console.log('=========================================');
        console.log('收到 Pub/Sub 訊息:', JSON.stringify(updateEvent, null, 2));
        console.log('📡 來源: projects/micro-service-477116/topics/data-update-notifications');
        console.log('訊息 ID:', req.body.message?.messageId || 'N/A');
        console.log('發布時間:', req.body.message?.publishTime || 'N/A');
        console.log('=========================================');

        // 支援兩種訊息格式：
        // 1. 餐廳稽查不合格通知 (type: "inspection_failure") - 專用格式
        // 2. 通用通知格式（舊格式，向後兼容）
        
        let targetUserIds, notificationTitle, notificationBody, targetUrl, messageType, restaurantInfo;

        // 檢查是否為餐廳稽查不合格通知格式
        // 條件：type === 'inspection_failure' 或存在 restaurant_info 欄位
        if (updateEvent.type === 'inspection_failure' || updateEvent.restaurant_info) {
            // 餐廳稽查不合格通知格式（專用格式）
            messageType = updateEvent.type || 'inspection_failure';
            restaurantInfo = updateEvent.restaurant_info || {};
            const restaurantName = restaurantInfo.name || '餐廳';
            
            // 確保 title 包含"不合格"，這樣應用才會顯示通知
            notificationTitle = updateEvent.title || `餐廳 '${restaurantName}' 稽查結果不合格`;
            notificationBody = updateEvent.message || `餐廳 '${restaurantName}' 稽查結果不合格`;
            targetUrl = `/restaurant/${restaurantInfo.reg_no || ''}`;
            targetUserIds = updateEvent.targetUserIds || [];
            
            console.log('📋 處理餐廳稽查不合格通知格式 (type: "inspection_failure")');
            console.log(`   類型: ${messageType}`);
            console.log(`   標題: ${notificationTitle}`);
            console.log(`   餐廳: ${restaurantInfo.name || '未知'}`);
            console.log(`   狀態: ${restaurantInfo.status || '未知'}`);
            console.log(`   嚴重程度: ${updateEvent.severity || '未知'}`);
            console.log(`   登記號碼: ${restaurantInfo.reg_no || '未知'}`);
            console.log(`   稽查日期: ${restaurantInfo.inspection_date || '未知'}`);
            console.log(`   目標用戶數量: ${targetUserIds.length}`);
            
            // 如果沒有 targetUserIds，將發送給所有用戶
        if (!targetUserIds || targetUserIds.length === 0) {
                console.log('⚠️  餐廳稽查通知格式中沒有提供 targetUserIds');
                console.log('   將發送推播通知給所有 Firestore 中的用戶');
            }
        } else {
            // 舊格式：通用通知（向後兼容）
            targetUserIds = updateEvent.targetUserIds;
            notificationTitle = updateEvent.notificationTitle;
            notificationBody = updateEvent.notificationBody;
            targetUrl = updateEvent.targetUrl;
            messageType = updateEvent.type || 'notification';
            restaurantInfo = null;
            
            console.log('📋 處理通用通知格式（向後兼容）');
        }

        // 2. 查詢 Firestore 以獲取 FCM Tokens
        // 如果沒有指定 targetUserIds，則獲取所有用戶的 Tokens
        console.log('=========================================');
        console.log('🔍 開始查詢 FCM Tokens');
        console.log('=========================================');
        
        let userTokens;
        try {
            if (!targetUserIds || targetUserIds.length === 0) {
                console.log('📢 沒有指定目標用戶，將發送推播通知給所有用戶（廣播模式）');
                userTokens = await getAllFCMTokens();
            } else {
                console.log(`📢 將發送推播通知給指定的 ${targetUserIds.length} 個用戶（精準推送模式）`);
                console.log(`目標用戶 ID: ${targetUserIds.join(', ')}`);
                userTokens = await getFCMTokensForUsers(targetUserIds);
            }
        } catch (tokenError) {
            console.error('❌ 查詢 FCM Tokens 時發生錯誤:', tokenError.message);
            console.error('錯誤堆疊:', tokenError.stack);
            throw tokenError;
        }

        // 輸出匹配結果
        console.log('=========================================');
        console.log('用戶 ID 和 FCM Token 匹配結果');
        console.log('=========================================');
        if (targetUserIds && targetUserIds.length > 0) {
        console.log(`目標用戶 ID 數量: ${targetUserIds.length}`);
        } else {
            console.log(`目標用戶: 所有用戶（廣播模式）`);
        }
        console.log(`找到 Token 的用戶數量: ${userTokens.length}`);
        console.log('');

        if (userTokens.length === 0) {
            console.error('=========================================');
            console.error('❌ 沒有找到任何有效的 FCM Token');
            console.error('=========================================');
            if (targetUserIds && targetUserIds.length > 0) {
                console.error('目標用戶 ID:');
            targetUserIds.forEach(userId => {
                    console.error(`  - ${userId}`);
                });
                console.error('');
                console.error('可能原因：');
                console.error('  1. 指定的用戶 ID 不存在於 Firestore');
                console.error('  2. 用戶存在但沒有 devices 陣列');
                console.error('  3. 用戶的 devices 陣列中沒有有效的 fcmToken');
            } else {
                console.error('廣播模式：Firestore 中沒有任何用戶或所有用戶都沒有有效的 FCM Token');
                console.error('');
                console.error('可能原因：');
                console.error('  1. Firestore users collection 為空');
                console.error('  2. 所有用戶都沒有 devices 陣列');
                console.error('  3. 所有用戶的 devices 陣列中都沒有有效的 fcmToken');
                console.error('');
                console.error('解決方法：');
                console.error('  1. 確認 Flutter App 已註冊設備並上傳 FCM token 到 Firestore');
                console.error('  2. 檢查 Firestore users collection 是否有資料');
                console.error('  3. 確認用戶資料結構包含 devices 陣列和 fcmToken');
            }
            console.error('=========================================');
            
            // 返回 200 但記錄警告（不讓 Pub/Sub 重試，因為這不是暫時性錯誤）
            return res.status(200).json({
                message: 'No valid tokens found',
                warning: 'No FCM tokens available to send notification',
                targetUserIds: targetUserIds || 'all',
                foundUsers: [],
                suggestion: 'Please ensure Flutter App has registered devices and uploaded FCM tokens to Firestore'
            });
        }

        // 輸出每個用戶的資訊
        userTokens.forEach((userToken, index) => {
            console.log(`用戶 ${index + 1}:`);
            console.log(`  User ID: ${userToken.userId}`);
            console.log(`  Token 數量: ${userToken.tokens.length}`);
            userToken.tokens.forEach((token, tokenIndex) => {
                console.log(`  Token ${tokenIndex + 1}: ${token.substring(0, 50)}... (總長度: ${token.length})`);
            });
            console.log('');
        });

        console.log('=========================================');
        console.log('詳細資訊 (JSON 格式):');
        console.log(JSON.stringify(userTokens, null, 2));
        console.log('=========================================');

        // 3. 構建 FCM 訊息並發送推播通知
        const allTokens = userTokens.flatMap(ut => ut.tokens);
        console.log(`準備發送 FCM 推播給 ${allTokens.length} 個設備...`);
        
        // sendEachForMulticast 最多支援 500 個 Token，如果超過需要分批發送
        const MAX_TOKENS_PER_BATCH = 500;
        const messaging = admin.messaging();
        let totalSuccessCount = 0;
        let totalFailureCount = 0;
        const allFailedTokens = [];

        // 如果 Token 數量超過限制，分批發送
        if (allTokens.length > MAX_TOKENS_PER_BATCH) {
            console.log(`⚠️  Token 數量 (${allTokens.length}) 超過限制 (${MAX_TOKENS_PER_BATCH})，將分批發送...`);
        }

        try {
            // 分批發送（如果需要）
            for (let i = 0; i < allTokens.length; i += MAX_TOKENS_PER_BATCH) {
                const batchTokens = allTokens.slice(i, i + MAX_TOKENS_PER_BATCH);
                const batchNumber = Math.floor(i / MAX_TOKENS_PER_BATCH) + 1;
                const totalBatches = Math.ceil(allTokens.length / MAX_TOKENS_PER_BATCH);
                
                console.log(`發送批次 ${batchNumber}/${totalBatches} (${batchTokens.length} 個設備)...`);
                
                // 構建 FCM 消息（包含 notification 和 data）
                // notification: 讓系統在應用關閉時也能顯示通知
                // data: 應用可以處理的自定義數據（如餐廳資訊、經緯度等）
                
                // FCM data 欄位（應用可以處理的自定義數據）
                // 注意：FCM data 欄位中的所有值都必須是字串類型
                const fcmData = {
                    // 跳轉 URL
                    targetUrl: String(targetUrl || '/default'),
                    // 訊息類型（字串格式，例如："inspection_failure"）
                    type: String(messageType || 'notification'),
                    // 時間戳
                    timestamp: String(updateEvent.timestamp || new Date().toISOString()),
                };
                
                // 如果是餐廳稽查通知，添加餐廳資訊
                if (restaurantInfo && Object.keys(restaurantInfo).length > 0) {
                    fcmData.restaurant_name = String(restaurantInfo.name || '');
                    fcmData.restaurant_reg_no = String(restaurantInfo.reg_no || '');
                    
                    // 添加經緯度（如果有）
                    if (restaurantInfo.latitude) {
                        fcmData.restaurant_latitude = String(restaurantInfo.latitude);
                    }
                    if (restaurantInfo.longitude) {
                        fcmData.restaurant_longitude = String(restaurantInfo.longitude);
                    }
                    
                    // 向後兼容：保留其他欄位（如果有）
                    if (restaurantInfo.address) {
                        fcmData.restaurant_address = String(restaurantInfo.address);
                    }
                    if (restaurantInfo.phone) {
                        fcmData.restaurant_phone = String(restaurantInfo.phone);
                    }
                    if (restaurantInfo.status) {
                        fcmData.restaurant_status = String(restaurantInfo.status);
                    }
                    if (restaurantInfo.inspection_date) {
                        fcmData.inspection_date = String(restaurantInfo.inspection_date);
                    }
                }
                
                // 構建 FCM 消息
                // 只有 title 包含"不合格"時才包含 notification 字段（讓系統自動顯示通知）
                // 否則只發送 data 字段（應用會讀取並只輸出日志）
                const message = {
                    tokens: batchTokens,
                    data: fcmData,
                };
                
                // 檢查 title 是否包含"不合格"，如果包含則添加 notification 字段
                if (notificationTitle && notificationTitle.includes('不合格')) {
                    message.notification = {
                        title: String(notificationTitle),
                        body: String(notificationBody || '請點擊查看最新內容。'),
                    };
                    // Android 特定設定
                    message.android = {
                        priority: 'high',
                        notification: {
                            channelId: 'default',
                            sound: 'default',
                            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                        }
                    };
                    // iOS 特定設定
                    message.apns = {
                        payload: {
                            aps: {
                                sound: 'default',
                                badge: 1,
                            }
                        }
                    };
                } else {
                    // title 不包含"不合格"或沒有 title，只發送 data 字段
                    // 應用會讀取 data 並只輸出日志，不顯示通知
                    console.log(`ℹ️  title 不包含"不合格" (${notificationTitle})，只發送 data 字段`);
                }
                
                // 確保 data 字段中包含 title 和 body，以便應用可以讀取
                fcmData.title = String(notificationTitle || '');
                fcmData.body = String(notificationBody || '');

                // 使用 sendEachForMulticast API (取代已棄用的 sendMulticast)
                const response = await messaging.sendEachForMulticast(message);
                
                totalSuccessCount += response.successCount;
                totalFailureCount += response.failureCount;
                
                console.log(`批次 ${batchNumber} 結果: 成功 ${response.successCount}, 失敗 ${response.failureCount}`);
                
                // 處理失敗的 Token
                if (response.failureCount > 0) {
                    response.responses.forEach((resp, idx) => {
                        if (!resp.success) {
                            const tokenIndex = i + idx;
                            console.error(`❌ 發送失敗 - Token ${tokenIndex + 1}: ${batchTokens[idx].substring(0, 50)}...`);
                            console.error(`   錯誤: ${resp.error?.message || resp.error}`);
                            console.error(`   錯誤代碼: ${resp.error?.code || 'UNKNOWN'}`);
                            allFailedTokens.push({
                                token: batchTokens[idx],
                                error: resp.error
                            });
                        }
                    });
                }
            }

            console.log(`=========================================`);
            console.log(`📊 FCM 推播總計結果`);
            console.log(`=========================================`);
            console.log(`✅ 成功: ${totalSuccessCount} 則`);
            console.log(`❌ 失敗: ${totalFailureCount} 則`);
            console.log(`📱 總 Token 數: ${allTokens.length}`);
            console.log(`👥 用戶數量: ${userTokens.length}`);
            if (totalFailureCount > 0) {
                console.log(`⚠️  失敗的 Token 數量: ${allFailedTokens.length}`);
            }
            console.log(`=========================================`);

            if (totalSuccessCount > 0) {
                console.log(`✅ 成功發送 ${totalSuccessCount} 則推播通知`);
            }

            // 成功處理，返回 200 讓 Pub/Sub 訂閱確認訊息
            return res.status(200).json({
                message: 'FCM Push Completed',
                successCount: totalSuccessCount,
                failureCount: totalFailureCount,
                targetUserIds: targetUserIds,
                foundUsers: userTokens,
                totalTokens: allTokens.length,
                batches: Math.ceil(allTokens.length / MAX_TOKENS_PER_BATCH)
            });
        } catch (fcmError) {
            console.error('=========================================');
            console.error('FCM 推播發送錯誤:');
            console.error('錯誤訊息:', fcmError.message);
            console.error('錯誤代碼:', fcmError.code || 'UNKNOWN');
            console.error('錯誤堆疊:', fcmError.stack);
            
            // 如果是 404 錯誤，提供解決方案
            if (fcmError.code && fcmError.code.includes('unknown-error') || 
                fcmError.message && fcmError.message.includes('404')) {
                console.error('');
                console.error('💡 這是一個 404 錯誤，通常表示：');
                console.error('   專案尚未在 Firebase Console 中註冊');
                console.error('   請訪問: https://console.firebase.google.com/');
                console.error('   添加專案: micro-service-477116');
                console.error('');
            }
            
            console.error('=========================================');
            
            // 返回錯誤但包含找到的 Token 資訊
            return res.status(500).json({
                error: 'FCM Push Failed',
                message: fcmError.message,
                code: fcmError.code || 'UNKNOWN',
                targetUserIds: targetUserIds,
                foundUsers: userTokens,
                totalTokens: allTokens.length
            });
        }
    } catch (error) {
        console.error('=========================================');
        console.error('處理錯誤:');
        console.error('錯誤訊息:', error.message);
        console.error('錯誤代碼:', error.code || 'UNKNOWN');
        console.error('錯誤堆疊:', error.stack);
        
        // 記錄請求資訊以便診斷
        console.error('請求資訊:');
        console.error('  URL:', req.url);
        console.error('  Method:', req.method);
        console.error('  Headers:', JSON.stringify(req.headers, null, 2));
        console.error('  Body 存在:', !!req.body);
        if (req.body) {
            console.error('  Body keys:', Object.keys(req.body));
            if (req.body.message) {
                console.error('  Message 存在:', !!req.body.message);
                if (req.body.message.data) {
                    console.error('  Message.data 類型:', typeof req.body.message.data);
                    console.error('  Message.data 長度:', req.body.message.data.length);
                    console.error('  Message.data 預覽 (前100字符):', req.body.message.data.substring(0, 100));
                }
            }
        }
        
        // 檢查是否為 Firebase 相關錯誤
        if (error.code && error.code.startsWith('messaging/')) {
            console.error('⚠️  這是一個 FCM 服務錯誤');
            console.error('請檢查：');
            console.error('  1. Firebase 專案是否正確配置');
            console.error('  2. Cloud Run 服務帳戶是否有 FCM 權限');
            console.error('  3. FCM Token 是否有效');
            console.error('  4. Firebase 專案是否已在 Firebase Console 中註冊');
            console.error('  5. FCM API 是否已啟用');
        }
        
        if (error.code && error.code.startsWith('firestore/')) {
            console.error('⚠️  這是一個 Firestore 錯誤');
            console.error('請檢查：');
            console.error('  1. Firestore 資料庫是否已創建');
            console.error('  2. Cloud Run 服務帳戶是否有 Firestore 讀取權限');
            console.error('  3. 用戶 ID 是否存在於 Firestore');
            console.error('  4. Firestore 資料庫模式（Native 或 Datastore）是否正確');
        }
        
        // 檢查是否為 JSON 解析錯誤
        if (error instanceof SyntaxError && error.message.includes('JSON')) {
            console.error('⚠️  這是一個 JSON 解析錯誤');
            console.error('可能原因：');
            console.error('  1. food-sync-service 發送的訊息格式不正確');
            console.error('  2. 訊息不是有效的 JSON');
            console.error('  3. Base64 解碼後的內容不是 JSON');
            console.error('  4. 訊息包含無效的字符');
            console.error('建議：');
            console.error('  1. 檢查 food-sync-service 的訊息格式');
            console.error('  2. 確認使用 json.dumps(notification_data, ensure_ascii=False).encode(\'utf-8\')');
            console.error('  3. 確認沒有手動 Base64 編碼');
            console.error('  4. 檢查訊息中是否包含特殊字符');
        }
        
        console.error('=========================================');
        
        // 根據錯誤類型返回適當的狀態碼
        // JSON 解析錯誤返回 400（客戶端錯誤，不重試）
        // 其他錯誤返回 500（服務器錯誤，Pub/Sub 會重試）
        const statusCode = (error instanceof SyntaxError && error.message.includes('JSON')) ? 400 : 500;
        const errorType = error instanceof SyntaxError ? 'Bad Request' : 'Internal Server Error';
        
        res.status(statusCode).json({
            error: errorType,
            message: error.message,
            code: error.code || 'UNKNOWN',
            type: error.constructor.name,
            timestamp: new Date().toISOString(),
            ...(statusCode === 400 && {
                hint: 'This is likely a message format issue. Please check the message format sent by food-sync-service.'
            })
        });
    }
});

// 健康檢查端點（Cloud Run 需要）
app.get('/health', (req, res) => {
    res.status(200).send('OK');
});

// 診斷端點：檢查服務狀態和 Firebase 連接
app.get('/status', async (req, res) => {
    const status = {
        service: 'FCM Push Service',
        timestamp: new Date().toISOString(),
        firebase: {
            initialized: firebaseInitialized,
            projectId: firebaseProjectId,
        },
        checks: {},
    };

    // 檢查 Firebase 初始化
    if (!firebaseInitialized) {
        status.checks.firebaseInit = {
            status: 'failed',
            message: 'Firebase Admin SDK 未初始化',
        };
        return res.status(500).json(status);
    }

    // 測試 Firestore 連接
    try {
        const db = admin.firestore();
        // 嘗試讀取一個測試文檔（不實際讀取，只測試連接）
        await db.collection('_health_check').limit(1).get();
        status.checks.firestore = {
            status: 'success',
            message: 'Firestore 連接正常',
        };
    } catch (error) {
        status.checks.firestore = {
            status: 'failed',
            message: `Firestore 連接失敗: ${error.message}`,
            error: error.code || 'UNKNOWN',
        };
    }

    // 檢查 FCM 服務（通過檢查 app 實例）
    try {
        const messaging = admin.messaging();
        status.checks.fcm = {
            status: 'success',
            message: 'FCM 服務可用',
        };
    } catch (error) {
        status.checks.fcm = {
            status: 'failed',
            message: `FCM 服務檢查失敗: ${error.message}`,
            error: error.code || 'UNKNOWN',
        };
    }

    // 檢查專案配置
    try {
        const app = admin.app();
        const projectId = app.options.projectId;
        status.checks.projectConfig = {
            status: projectId === firebaseProjectId ? 'success' : 'warning',
            message: `專案 ID: ${projectId}`,
            expected: firebaseProjectId,
            actual: projectId,
        };
    } catch (error) {
        status.checks.projectConfig = {
            status: 'failed',
            message: `無法獲取專案配置: ${error.message}`,
        };
    }

    // 判斷整體狀態
    const allChecksPassed = Object.values(status.checks).every(
        (check) => check.status === 'success'
    );

    res.status(allChecksPassed ? 200 : 500).json(status);
});

// 檢查用戶是否存在於 Firestore 的端點
app.get('/check-users', async (req, res) => {
    // 從查詢參數獲取用戶 ID（支援多個，用逗號分隔）
    const userIdsParam = req.query.userIds || req.query.userId;
    
    if (!userIdsParam) {
        return res.status(400).json({
            error: 'Missing userIds parameter',
            message: '請提供 userIds 查詢參數，例如: /check-users?userIds=user1,user2 或 /check-users?userId=user1'
        });
    }

    // 解析用戶 ID 列表
    const targetUserIds = userIdsParam.split(',').map(id => id.trim()).filter(id => id.length > 0);

    if (targetUserIds.length === 0) {
        return res.status(400).json({
            error: 'Invalid userIds',
            message: '用戶 ID 列表為空'
        });
    }

    console.log('=========================================');
    console.log('檢查用戶是否存在於 Firestore');
    console.log('=========================================');
    console.log(`目標用戶 ID 數量: ${targetUserIds.length}`);
    console.log(`用戶 ID: ${targetUserIds.join(', ')}`);
    console.log('');

    try {
        const result = await checkUsersInFirestore(targetUserIds);
        
        return res.status(200).json({
            message: 'User check completed',
            targetUserIds: targetUserIds,
            found: result.found,
            notFound: result.notFound,
            totalFound: result.found.length,
            totalNotFound: result.notFound.length,
            details: result.details
        });
    } catch (error) {
        console.error('檢查用戶時發生錯誤:', error);
        return res.status(500).json({
            error: 'Check failed',
            message: error.message,
            targetUserIds: targetUserIds
        });
    }
});

// ----------------------------------------------------
// 輔助函數：檢查用戶是否存在於 Firestore
// 返回格式: { found: string[], notFound: string[], details: {...} }
// ----------------------------------------------------
async function checkUsersInFirestore(userIds) {
    const db = admin.firestore();
    const found = [];
    const notFound = [];
    const details = {};

    const BATCH_SIZE = 10;

    for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
        const batchIds = userIds.slice(i, i + BATCH_SIZE);

        try {
            const snapshot = await db.collection('users')
                .where(admin.firestore.FieldPath.documentId(), 'in', batchIds)
                .get();

            // 記錄找到的用戶
            const foundInBatch = new Set();
            snapshot.docs.forEach(doc => {
                const userId = doc.id;
                foundInBatch.add(userId);
                found.push(userId);

                const userData = doc.data();
                const tokenCount = countTokens(userData);
                
                details[userId] = {
                    exists: true,
                    hasDevices: !!(userData.devices && Array.isArray(userData.devices)),
                    deviceCount: userData.devices ? userData.devices.length : 0,
                    tokenCount: tokenCount,
                    hasRootToken: !!userData.fcmToken,
                    dataKeys: Object.keys(userData)
                };
            });

            // 記錄未找到的用戶
            batchIds.forEach(userId => {
                if (!foundInBatch.has(userId)) {
                    notFound.push(userId);
                    details[userId] = {
                        exists: false,
                        message: '用戶不存在於 Firestore users collection'
                    };
                }
            });
        } catch (error) {
            console.error(`檢查用戶批次時發生錯誤: ${error.message}`);
            // 如果查詢失敗，將整個批次標記為未找到
            batchIds.forEach(userId => {
                notFound.push(userId);
                details[userId] = {
                    exists: false,
                    error: error.message
                };
            });
        }
    }

    return { found, notFound, details };
}

// 輔助函數：計算 Token 數量
function countTokens(userData) {
    let count = 0;
    
    if (userData.devices && Array.isArray(userData.devices)) {
        userData.devices.forEach(device => {
            if (device && device.fcmToken) {
                count++;
            }
        });
    }
    
    if (userData.fcmToken) {
        count++;
    }
    
    return count;
}

// ----------------------------------------------------
// 輔助函數：從 Firestore 查詢 FCM Token
// 返回格式: [{ userId: string, tokens: string[] }, ...]
// ----------------------------------------------------
async function getFCMTokensForUsers(userIds) {
    // 假設您的 FCM Token 儲存在名為 'users' 的 Collection 中
    const db = admin.firestore();

    // Firestore 的 'in' 查詢限制為最多 10 個元素，如果 userIds 很大，需要分批查詢
    const userTokens = []; // 改為返回用戶 ID 和 Token 的映射
    const BATCH_SIZE = 10;

    for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
        const batchIds = userIds.slice(i, i + BATCH_SIZE);

        try {
            const snapshot = await db.collection('users')
                .where(admin.firestore.FieldPath.documentId(), 'in', batchIds)
                .get();

            snapshot.docs.forEach(doc => {
                const userId = doc.id;
                const userData = doc.data();
                const tokens = extractTokensFromUserData(userData);
                
                console.log(`檢查用戶: ${userId}`);
                
                // 如果有找到 Token，添加到結果中
                if (tokens.length > 0) {
                    userTokens.push({
                        userId: userId,
                        tokens: tokens
                    });
                    console.log(`  ✅ 用戶 ${userId} 共有 ${tokens.length} 個 Token`);
                } else {
                    console.log(`  ❌ 用戶 ${userId} 沒有找到任何 Token`);
                }
            });
        } catch (error) {
            console.error(`Error fetching tokens for batch: ${error.message}`);
            console.error(`錯誤堆疊:`, error.stack);
        }
    }

    return userTokens;
}

// ----------------------------------------------------
// 輔助函數：從 Firestore 獲取所有用戶的 FCM Token
// 返回格式: [{ userId: string, tokens: string[] }, ...]
// ----------------------------------------------------
async function getAllFCMTokens() {
    const db = admin.firestore();
    const userTokens = [];
    
    console.log('📥 開始獲取所有用戶的 FCM Tokens...');
    
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
// 返回格式: string[]
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

// 啟動 Server
const PORT = process.env.PORT || 8081;
app.listen(PORT, async () => {
    console.log(`=========================================`);
    console.log(`FCM Notifier Service 啟動`);
    console.log(`=========================================`);
    console.log(`📡 服務監聽端口: ${PORT}`);
    console.log(`📦 專案 ID: ${firebaseProjectId}`);
    console.log(`🔥 Firebase 初始化: ${firebaseInitialized ? '✅ 成功' : '❌ 失敗'}`);
    console.log(`=========================================`);
    console.log(`端點:`);
    console.log(`  GET  /health  - 健康檢查`);
    console.log(`  GET  /status  - 服務狀態診斷`);
    console.log(`  POST /        - Pub/Sub 訊息處理`);
    console.log(`=========================================`);

    // 啟動時執行診斷檢查
    if (firebaseInitialized) {
        try {
            const db = admin.firestore();
            console.log(`🔍 測試 Firestore 連接...`);
            await db.collection('users').limit(1).get();
            console.log(`✅ Firestore 連接測試成功`);
        } catch (error) {
            console.error(`❌ Firestore 連接測試失敗:`, error.message);
            console.error(`   錯誤代碼: ${error.code || 'UNKNOWN'}`);
        }

        try {
            const messaging = admin.messaging();
            console.log(`✅ FCM 服務可用`);
        } catch (error) {
            console.error(`❌ FCM 服務檢查失敗:`, error.message);
        }
    }
});

