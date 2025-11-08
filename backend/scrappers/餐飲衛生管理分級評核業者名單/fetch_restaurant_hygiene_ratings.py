#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
餐飲衛生管理分級評核業者名單

功能：
    1. 從指定 URL 下載餐飲衛生管理分級評核業者名單 CSV（不儲存）
    2. 解析並處理資料
    3. 輸出 JSON 格式：{食品業者登錄字號: 評核結果}

使用方法：
    python fetch_restaurant_ratings.py

輸出：
    餐飲衛生管理分級評核業者名單.json

作者：Claude
日期：2024-11-08
"""

import csv
import json
import os
import urllib.request
from io import StringIO

# ==================== 設定區 ====================
# 台北市政府衛生局 - 餐飲衛生管理分級評核業者名單
# 來源：https://health.gov.taipei/News.aspx?n=DE4B43F114D94B4F&sms=F8548A1E404339A3
CSV_URL = "https://data.taipei/api/dataset/59579c19-a561-4564-8c0f-545bfb32c0f6/resource/c5646d80-9118-4439-b924-075f96371d75/download"

# 輸出檔案名稱
OUTPUT_FILE = "restaurant_hygiene_ratings.json"
# ==============================================


def download_csv_from_url(url: str) -> str:
    """
    從 URL 下載 CSV 內容（不儲存到硬碟）

    Args:
        url: CSV 檔案的 URL

    Returns:
        str: CSV 內容文字
    """
    print(f"正在從 URL 下載資料...")
    print(f"URL: {url}")

    with urllib.request.urlopen(url) as response:
        # 讀取內容並解碼為 UTF-8
        csv_content = response.read().decode('utf-8-sig')  # utf-8-sig 自動移除 BOM

    print(f"下載完成！資料大小: {len(csv_content)} 字元")
    return csv_content


def parse_restaurant_ratings(csv_content: str) -> dict:
    """
    解析餐飲衛生管理分級評核資料

    Args:
        csv_content: CSV 內容文字

    Returns:
        dict: {食品業者登錄字號: 評核結果}
    """
    print("正在解析資料...")

    # 使用 StringIO 將字串轉換為類似檔案的物件
    csv_file = StringIO(csv_content)
    csv_reader = csv.DictReader(csv_file)

    # 建立結果字典
    result = {}
    count = 0
    duplicates = 0

    for row in csv_reader:
        # 提取食品業者登錄字號和評核結果
        registration_number = row.get('食品業者登錄字號', '').strip()
        rating = row.get('評核結果', '').strip()

        # 跳過空值
        if not registration_number or not rating:
            continue

        # 檢查是否有重複的登錄字號
        if registration_number in result:
            # 如果評核結果不同，顯示警告
            if result[registration_number] != rating:
                print(f"警告: 登錄字號 {registration_number} 有不同的評核結果: "
                      f"{result[registration_number]} vs {rating}")
            duplicates += 1

        # 儲存到結果字典
        result[registration_number] = rating
        count += 1

    print(f"解析完成！共處理 {count} 筆資料")
    if duplicates > 0:
        print(f"發現 {duplicates} 筆重複的登錄字號")
    print(f"獨立業者數量: {len(result)}")

    return result


def save_to_json(data: dict, output_file: str):
    """
    儲存資料為 JSON 格式（使用原子寫入操作）

    Args:
        data: 要儲存的資料字典
        output_file: 輸出檔案名稱
    """
    print(f"正在儲存 JSON 檔案...")

    # 使用臨時檔案進行原子寫入
    temp_file = output_file + '.temp'

    with open(temp_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)

    # 原子性重新命名
    os.replace(temp_file, output_file)

    print(f"✓ JSON 檔案已儲存: {output_file}")


def print_statistics(data: dict):
    """
    顯示統計資訊

    Args:
        data: 資料字典 {登錄字號: 評核結果}
    """
    print("\n" + "="*50)
    print("統計資訊")
    print("="*50)

    # 計算各評核結果的數量
    rating_counts = {}
    for rating in data.values():
        rating_counts[rating] = rating_counts.get(rating, 0) + 1

    print(f"總業者數: {len(data)}")
    print("\n評核結果分布:")
    for rating, count in sorted(rating_counts.items()):
        percentage = (count / len(data)) * 100
        print(f"  {rating}: {count} 家 ({percentage:.1f}%)")

    print("\n範例資料 (前 5 筆):")
    for i, (reg_num, rating) in enumerate(list(data.items())[:5], 1):
        print(f"  {i}. {reg_num}: {rating}")

    print("="*50 + "\n")


def main():
    """主程式"""
    print("="*50)
    print("餐飲衛生管理分級評核業者名單資料處理工具")
    print("="*50 + "\n")

    try:
        # 步驟 1: 從 URL 下載 CSV（不儲存）
        csv_content = download_csv_from_url(CSV_URL)

        # 步驟 2: 解析資料
        restaurant_ratings = parse_restaurant_ratings(csv_content)

        # 步驟 3: 顯示統計資訊
        print_statistics(restaurant_ratings)

        # 步驟 4: 儲存為 JSON
        save_to_json(restaurant_ratings, OUTPUT_FILE)

        print("處理完成！")

    except Exception as e:
        print(f"\n❌ 錯誤: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
