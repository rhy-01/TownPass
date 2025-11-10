const admin = require('firebase-admin');

// 初始化 Firebase Admin SDK
// 在 Cloud Run 環境中，會自動使用應用程式預設憑證 (Application Default Credentials)
// 在本地開發環境中，可以設置 GOOGLE_APPLICATION_CREDENTIALS 環境變數指向服務帳戶密鑰文件
// 或者使用 Firebase 項目 ID 環境變數
let db = null;

try {
    // 檢查是否已經初始化
    if (admin.apps.length === 0) {
        // 方法 1: 如果在 GCP 環境（Cloud Run）或已設置應用程式預設憑證
        // 只需提供項目 ID 即可，會自動使用環境的服務帳戶
        if (process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT) {
            // 使用應用程式預設憑證（推薦用於生產環境）
            admin.initializeApp({
                credential: admin.credential.applicationDefault(),
                // 如果設置了項目 ID 環境變數，使用它；否則讓 SDK 自動偵測
                projectId: process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT
            });
            console.log('Firebase Admin initialized with Application Default Credentials');
        } 
        // 方法 2: 使用服務帳戶密鑰文件（本地開發用）
        else if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
            const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
            admin.initializeApp({
                credential: admin.credential.cert(serviceAccount)
            });
            console.log('Firebase Admin initialized with service account key from environment variable');
        }
        // 方法 3: 使用環境變數中的項目 ID 和私有密鑰（本地開發用）
        else if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY && process.env.FIREBASE_CLIENT_EMAIL) {
            admin.initializeApp({
                credential: admin.credential.cert({
                    projectId: process.env.FIREBASE_PROJECT_ID,
                    privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
                    clientEmail: process.env.FIREBASE_CLIENT_EMAIL
                })
            });
            console.log('Firebase Admin initialized with environment variables');
        }
        // 方法 4: 嘗試使用默認初始化（會自動偵測環境）
        else {
            admin.initializeApp();
            console.log('Firebase Admin initialized with default configuration');
        }
    }

    // 獲取 Firestore 實例
    db = admin.firestore();
    console.log('Firestore database connected successfully');

} catch (error) {
    console.error('Error initializing Firebase Admin:', error);
    console.error('Please ensure you have configured Firebase credentials correctly.');
    // 不拋出錯誤，允許應用程式繼續運行（但資料庫操作會失敗）
}

// 導出 Firestore 實例和管理功能
module.exports = {
    db,
    admin
};

