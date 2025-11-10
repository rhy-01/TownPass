const { db } = require('./firebase');

// Firestore 集合名稱
const COLLECTIONS = {
    DEVICES: 'devices',
    USERS: 'users'
};

/**
 * 註冊或更新設備資訊
 * @param {Object} deviceData - 設備資料
 * @param {string} deviceData.userId - 用戶 ID
 * @param {string} deviceData.fcmToken - FCM 推送令牌
 * @param {number} deviceData.latitude - 緯度
 * @param {number} deviceData.longitude - 經度
 * @param {string} deviceData.timestamp - 時間戳
 * @returns {Promise<Object>} 設備文檔資料
 */
async function registerDevice(deviceData) {
    if (!db) {
        throw new Error('Firestore database is not initialized');
    }

    const { userId, fcmToken, latitude, longitude, timestamp } = deviceData;
    const deviceId = `${userId}_${fcmToken.substring(0, 20)}`; // 使用 userId 和 fcmToken 前綴創建唯一 ID

    const deviceDoc = {
        userId,
        fcmToken,
        latitude: latitude || null,
        longitude: longitude || null,
        registeredAt: timestamp || new Date().toISOString(),
        lastUpdated: new Date().toISOString(),
        isActive: true
    };

    try {
        // 使用 deviceId 作為文檔 ID，如果已存在則更新，否則創建新文檔
        const deviceRef = db.collection(COLLECTIONS.DEVICES).doc(deviceId);
        
        // 檢查設備是否已存在
        const deviceSnapshot = await deviceRef.get();
        
        if (deviceSnapshot.exists) {
            // 更新現有設備（只更新 lastUpdated 和其他可變欄位）
            await deviceRef.update({
                fcmToken,
                latitude: latitude || deviceSnapshot.data().latitude,
                longitude: longitude || deviceSnapshot.data().longitude,
                lastUpdated: new Date().toISOString(),
                isActive: true
            });
            console.log(`Device updated: ${deviceId}`);
        } else {
            // 創建新設備
            await deviceRef.set(deviceDoc);
            console.log(`Device created: ${deviceId}`);
        }

        // 同時更新用戶文檔中的設備列表（可選）
        await updateUserDevices(userId, deviceId, fcmToken);

        return {
            deviceId,
            ...deviceDoc
        };
    } catch (error) {
        console.error('Error registering device in Firestore:', error);
        throw error;
    }
}

/**
 * 更新用戶的設備列表
 * @param {string} userId - 用戶 ID
 * @param {string} deviceId - 設備 ID
 * @param {string} fcmToken - FCM 令牌
 */
async function updateUserDevices(userId, deviceId, fcmToken) {
    if (!db) {
        return; // 如果資料庫未初始化，靜默失敗
    }

    try {
        const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
        const userSnapshot = await userRef.get();

        const deviceInfo = {
            deviceId,
            fcmToken,
            lastUpdated: new Date().toISOString()
        };

        if (userSnapshot.exists) {
            // 更新用戶文檔，將設備添加到 devices 陣列
            const userData = userSnapshot.data();
            const devices = userData.devices || [];
            
            // 檢查設備是否已存在
            const deviceIndex = devices.findIndex(d => d.deviceId === deviceId);
            if (deviceIndex >= 0) {
                devices[deviceIndex] = deviceInfo;
            } else {
                devices.push(deviceInfo);
            }

            await userRef.update({
                devices,
                lastUpdated: new Date().toISOString()
            });
        } else {
            // 創建新用戶文檔
            await userRef.set({
                userId,
                devices: [deviceInfo],
                createdAt: new Date().toISOString(),
                lastUpdated: new Date().toISOString()
            });
        }
    } catch (error) {
        console.error('Error updating user devices:', error);
        // 不拋出錯誤，因為這不是關鍵操作
    }
}

/**
 * 根據用戶 ID 獲取設備列表
 * @param {string} userId - 用戶 ID
 * @returns {Promise<Array>} 設備列表
 */
async function getDevicesByUserId(userId) {
    if (!db) {
        throw new Error('Firestore database is not initialized');
    }

    try {
        const devicesSnapshot = await db.collection(COLLECTIONS.DEVICES)
            .where('userId', '==', userId)
            .where('isActive', '==', true)
            .get();

        return devicesSnapshot.docs.map(doc => ({
            deviceId: doc.id,
            ...doc.data()
        }));
    } catch (error) {
        console.error('Error getting devices by user ID:', error);
        throw error;
    }
}

/**
 * 根據用戶 ID 獲取所有 FCM 令牌
 * @param {string} userId - 用戶 ID
 * @returns {Promise<Array<string>>} FCM 令牌列表
 */
async function getFCMTokensByUserId(userId) {
    if (!db) {
        throw new Error('Firestore database is not initialized');
    }

    try {
        const devices = await getDevicesByUserId(userId);
        return devices.map(device => device.fcmToken).filter(token => token);
    } catch (error) {
        console.error('Error getting FCM tokens by user ID:', error);
        throw error;
    }
}

module.exports = {
    registerDevice,
    getDevicesByUserId,
    getFCMTokensByUserId,
    updateUserDevices,
    COLLECTIONS
};

