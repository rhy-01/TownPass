"""
Configuration settings for the food-sync-service
"""
import os

# GCP 專案設定
PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "micro-service-477116")

# Pub/Sub 設定
NOTIFICATION_TOPIC_NAME = "data-update-notifications"
NOTIFICATION_TOPIC = f"projects/{PROJECT_ID}/topics/{NOTIFICATION_TOPIC_NAME}"

# 稽查不合格判定關鍵字
INSPECTION_FAILURE_KEYWORDS = [
    "不合格",
    "不符合", 
    "違規",
    "裁罰",
    "停業",
    "限期改善",
    "改善"
]

# 通知設定
NOTIFICATION_SETTINGS = {
    "high_severity_keywords": ["停業", "裁罰"],
    "medium_severity_keywords": ["限期改善", "違規"],
    "low_severity_keywords": ["不合格", "不符合"]
}