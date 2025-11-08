#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
夜市餐廳資料爬蟲
爬取 https://imap.health.gov.tw/App_Prog/SubjectNightMarket.aspx
1. 取得所有夜市列表（不包含觀光夜市）
2. 取得每個夜市內所有餐廳的登錄字號
"""

import requests
import json
import threading
import os
from concurrent.futures import ThreadPoolExecutor
from bs4 import BeautifulSoup

# 夜市列表（執行時自動從頁面抓取）
NIGHT_MARKETS = []

# 設定
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_URL = "https://imap.health.gov.tw/App_Prog/SubjectNightMarket.aspx"
WORKER_COUNT = 5
PAGE_SIZE = 20
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
}

# 全域變數
restaurants_by_market = {}  # 每個夜市的餐廳資料
data_lock = threading.Lock()


def fetch_night_market_options():
    """從頁面抓取夜市清單（排除最上層「觀光夜市」）"""
    try:
        response = requests.get(BASE_URL, headers=HEADERS, timeout=30)
        response.encoding = 'utf-8'
        soup = BeautifulSoup(response.text, 'html.parser')
        select = soup.find('select', id='ContentPlaceHolder1_ContentPlaceHolder2_ddlSubjectAppendix')
        if not select:
            print("✗ 無法找到夜市下拉選單")
            return []

        options = []
        for option in select.find_all('option'):
            name = option.get_text(strip=True)
            value = (option.get('value') or '').strip()
            if not value or name == "觀光夜市":
                # 跳過空值與總覽選項
                continue
            options.append({'name': name, 'value': value})

        return options
    except Exception as exc:
        print(f"✗ 取得夜市列表失敗: {exc}")
        return []


def get_viewstate(html_text):
    """從頁面中提取 ViewState 和相關參數"""
    soup = BeautifulSoup(html_text, 'html.parser')
    viewstate = soup.find('input', {'name': '__VIEWSTATE'})
    viewstate_gen = soup.find('input', {'name': '__VIEWSTATEGENERATOR'})
    event_validation = soup.find('input', {'name': '__EVENTVALIDATION'})

    return {
        '__VIEWSTATE': viewstate['value'] if viewstate else '',
        '__VIEWSTATEGENERATOR': viewstate_gen['value'] if viewstate_gen else '',
        '__EVENTVALIDATION': event_validation['value'] if event_validation else ''
    }


def get_initial_session():
    """取得初始 session 和 viewstate"""
    session = requests.Session()
    response = session.get(BASE_URL, headers=HEADERS, timeout=30)
    response.encoding = 'utf-8'
    return session, get_viewstate(response.text), response.text


def select_night_market(session, viewstate_params, market_code):
    """選擇特定夜市並設定每頁20筆，返回第一頁資料"""
    # 構建 POST 資料
    post_data = {
        '__EVENTTARGET': 'ctl00$ctl00$ContentPlaceHolder1$ContentPlaceHolder2$ddlSubjectAppendix',
        '__EVENTARGUMENT': '',
        '__VIEWSTATE': viewstate_params['__VIEWSTATE'],
        '__VIEWSTATEGENERATOR': viewstate_params['__VIEWSTATEGENERATOR'],
        '__EVENTVALIDATION': viewstate_params['__EVENTVALIDATION'],
        'ctl00$ctl00$ContentPlaceHolder1$ContentPlaceHolder2$ddlSubjectAppendix': market_code,
        'ctl00$ctl00$ContentPlaceHolder1$ContentPlaceHolder2$ucPagingControl1$uDdlPageSize': str(PAGE_SIZE),
    }

    try:
        response = session.post(BASE_URL, data=post_data, headers=HEADERS, timeout=30)
        response.encoding = 'utf-8'
        return response.text
    except Exception as e:
        print(f"  ✗ 選擇夜市代碼 {market_code} 時發生錯誤: {e}")
        return None


def parse_restaurants(html_text):
    """解析頁面中的餐廳登錄字號"""
    soup = BeautifulSoup(html_text, 'html.parser')
    restaurants = []

    # 先嘗試從隱藏的 JSON 取資料（一次就有完整清單）
    json_span = soup.find('span', id='ContentPlaceHolder1_ContentPlaceHolder2_cblChartValue')
    if json_span:
        json_text = json_span.get_text(strip=True)
        if json_text:
            try:
                data = json.loads(json_text)
                for item in data:
                    reg_num = item.get('store_regNum', '').strip()
                    if reg_num:
                        restaurants.append(reg_num)
            except json.JSONDecodeError:
                pass

    if restaurants:
        return restaurants

    # 若 JSON 失敗，再從 HTML 頁面逐筆抓取
    items = soup.find_all('div', class_='list-item')

    for item in items:
        try:
            # 尋找登錄字號
            paragraphs = item.find_all('p')
            for p in paragraphs:
                text = p.get_text(strip=True)
                if text.startswith('登錄字號：'):
                    reg_num = text.replace('登錄字號：', '').strip()
                    if reg_num:
                        restaurants.append(reg_num)
                    break
        except Exception as e:
            print(f"  ⚠ 解析單筆餐廳資料時發生錯誤: {e}")
            continue

    return restaurants


def scrape_market(worker_id, market_info):
    """爬取單個夜市的所有資料"""
    market_name = market_info['name']
    market_code = market_info['value']
    print(f"[Worker {worker_id:02d}] 開始爬取: {market_name}")

    try:
        # 建立 session
        session, viewstate_params, html = get_initial_session()

        # 選擇夜市
        html = select_night_market(session, viewstate_params, market_code)
        if not html:
            print(f"[Worker {worker_id:02d}] ✗ 無法選擇夜市: {market_name}")
            return

        # 解析第一頁
        restaurants = parse_restaurants(html)

        # 儲存結果
        with data_lock:
            restaurants_by_market[market_name] = restaurants
            save_restaurants_data()

        print(f"[Worker {worker_id:02d}] ✓ {market_name} 完成，共 {len(restaurants)} 筆餐廳")

    except Exception as e:
        print(f"[Worker {worker_id:02d}] ✗ 爬取 {market_name} 時發生錯誤: {e}")


def run_parallel_scrape(markets):
    """使用多執行緒平行爬取所有夜市"""
    print(f"\n=== 開始平行爬取 {len(markets)} 個夜市（{WORKER_COUNT} 個 Worker） ===\n")

    # 將夜市分配給各個 worker
    assignments = {i: [] for i in range(WORKER_COUNT)}
    for idx, market in enumerate(markets):
        worker_id = idx % WORKER_COUNT
        assignments[worker_id].append(market)

    with ThreadPoolExecutor(max_workers=WORKER_COUNT) as executor:
        futures = []
        for worker_id in range(WORKER_COUNT):
            my_markets = assignments[worker_id]
            for market in my_markets:
                futures.append(
                    executor.submit(scrape_market, worker_id, market)
                )

        # 等待所有任務完成
        for future in futures:
            future.result()

    print("\n=== 爬取完成 ===\n")


def save_night_market_list(market_options):
    """儲存夜市列表到 JSON 檔案"""
    filename = os.path.join(SCRIPT_DIR, 'night_market_list.json')

    names = [market['name'] for market in market_options]

    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(names, f, ensure_ascii=False, indent=2)

    print(f"✓ 夜市列表已儲存到 {filename}")


def save_restaurants_data():
    """儲存每個夜市的餐廳資料到 JSON 檔案"""
    filename = os.path.join(SCRIPT_DIR, 'night_market_restaurants.json')

    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(restaurants_by_market, f, ensure_ascii=False, indent=2)

    print(f"✓ 餐廳資料已儲存到 {filename}")


def main():
    """主程式"""
    print("=" * 70)
    print("  夜市餐廳資料爬蟲")
    print("=" * 70)
    print()

    global NIGHT_MARKETS
    NIGHT_MARKETS = fetch_night_market_options()
    if not NIGHT_MARKETS:
        print("✗ 無可用夜市資料，請稍後再試")
        return

    # 顯示要爬取的夜市列表
    print("將爬取以下夜市（排除觀光夜市）:")
    for idx, market in enumerate(NIGHT_MARKETS, 1):
        print(f"  {idx}. {market['name']}")
    print()

    # 儲存夜市列表
    save_night_market_list(NIGHT_MARKETS)
    print()

    # 爬取所有夜市的餐廳資料
    run_parallel_scrape(NIGHT_MARKETS)

    # 統計結果
    print("=" * 70)
    print("爬取結果統計:")
    print(f"  總夜市數: {len(NIGHT_MARKETS)}")
    total_restaurants = sum(len(restaurants) for restaurants in restaurants_by_market.values())
    print(f"  總餐廳數: {total_restaurants}")
    print()

    print("各夜市餐廳數量:")
    for market in NIGHT_MARKETS:
        name = market['name']
        count = len(restaurants_by_market.get(name, []))
        print(f"  {name}: {count} 筆")
    print("=" * 70)
    print()

    # 儲存餐廳資料
    save_restaurants_data()


if __name__ == "__main__":
    main()
