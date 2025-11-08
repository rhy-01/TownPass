#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
餐飲業者資料爬蟲
預設從 HTML 解析（含日期），可透過 CLI 設定稽查日期範圍
"""

import argparse
import requests
import json
import csv
import time
import os
import threading
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlencode
from bs4 import BeautifulSoup

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TEMP_DATA_FILE = os.path.join(SCRIPT_DIR, 'food_data_updated.temp.json')
FINAL_DATA_FILE = os.path.join(SCRIPT_DIR, 'food_data_updated.json')
WORKER_COUNT = 5
MAX_RETRIES = 5
PAGE_SIZE = 20
BASE_URL = "https://imap.health.gov.tw/App_Prog/ListFood.aspx"
START_DATE = None
END_DATE = None
BASE_QUERY_PARAMS = {}
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
}

def parse_date(date_str):
    """將日期字串轉換為 datetime 物件"""
    try:
        # 格式: 2025.11.06
        return datetime.strptime(date_str, '%Y.%m.%d')
    except:
        return None

def parse_cli_date(value):
    """解析 CLI 傳入的日期（YYYY-MM-DD）"""
    if not value:
        return None
    for fmt in ('%Y-%m-%d', '%Y/%m/%d', '%Y.%m.%d'):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"無法解析日期：{value}，請使用 YYYY-MM-DD 格式")

def build_page_url(page_num):
    """產生附帶日期篩選的頁面 URL"""
    params = {
        'page': page_num,
        'size': PAGE_SIZE,
    }
    params.update(BASE_QUERY_PARAMS)
    return f"{BASE_URL}?{urlencode(params)}"

def scrape_page_from_html(page_num):
    """從HTML解析每頁資料（包含日期）"""
    url = build_page_url(page_num)
    try:
        response = requests.get(url, headers=HEADERS, timeout=30)
        response.encoding = 'utf-8'
        soup = BeautifulSoup(response.text, 'html.parser')

        results = []
        items = soup.find_all('div', class_='list-item')

        for item in items:
            try:
                # 名稱
                title_div = item.find('div', class_='list-title')
                name_link = title_div.find('a') if title_div else None
                name = name_link.get_text(strip=True) if name_link else ''

                # 找所有的 <p> 標籤
                paragraphs = item.find_all('p')
                address = ''
                phone = ''
                reg_num = ''

                for p in paragraphs:
                    text = p.get_text(strip=True)
                    if text.startswith('地址：'):
                        address = text.replace('地址：', '')
                    elif text.startswith('電話：'):
                        phone = text.replace('電話：', '')
                    elif text.startswith('登錄字號：'):
                        reg_num = text.replace('登錄字號：', '')

                # 狀態和日期
                mark_div = item.find('div', class_='mark')
                status = ''
                date_str = ''

                if mark_div:
                    # 狀態文字
                    status_span = mark_div.find('span', class_='text')
                    if status_span:
                        status = status_span.get_text(strip=True)

                    # 日期
                    date_span = mark_div.find('span', class_='date')
                    if date_span:
                        date_str = date_span.get_text(strip=True)

                data = {
                    '名稱': name,
                    '地址': address,
                    '電話': phone,
                    '登錄字號': reg_num,
                    '狀態': status,
                    '日期': date_str
                }
                results.append(data)

            except Exception as e:
                print(f"  ⚠ 解析單筆資料時發生錯誤: {e}")
                continue

        return results

    except Exception as e:
        print(f"✗ 抓取第 {page_num} 頁時發生錯誤: {str(e)}")
        return []

def filter_by_recent_month(data_list, days=30):
    """篩選最近N天的資料"""
    if not data_list:
        return []

    cutoff_date = datetime.now() - timedelta(days=days)
    filtered = []

    for item in data_list:
        if item['日期']:
            date_obj = parse_date(item['日期'])
            if date_obj and date_obj >= cutoff_date:
                filtered.append(item)

    return filtered

def save_to_csv(data_list, filename='food_data_final.csv'):
    """儲存資料到 CSV 檔案"""
    if not data_list:
        print("沒有資料可儲存")
        return

    with open(filename, 'w', newline='', encoding='utf-8-sig') as f:
        fieldnames = ['名稱', '地址', '電話', '登錄字號', '狀態', '日期']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data_list)

    print(f"✓ 資料已儲存到 {filename}")

def save_to_json(data_list, filename='food_data_final.json'):
    """儲存資料到 JSON 檔案"""
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(data_list, f, ensure_ascii=False, indent=2)

    print(f"✓ 資料已儲存到 {filename}")

def flatten_results(results_by_page):
    """依頁碼排序後展平成單一清單"""
    aggregated = []
    for page in sorted(results_by_page):
        aggregated.extend(results_by_page[page])
    return aggregated

def snapshot_results(results_by_page, filename=TEMP_DATA_FILE):
    """將目前成功頁面寫入暫存 JSON，確保隨時可取得部分成果"""
    aggregated = flatten_results(results_by_page)
    tmp_file = filename + '.tmp'
    with open(tmp_file, 'w', encoding='utf-8') as f:
        json.dump(aggregated, f, ensure_ascii=False, indent=2)
    os.replace(tmp_file, filename)

def finalize_json(data_list):
    """先寫入 .temp.json 再覆蓋正式 JSON"""
    tmp_file = TEMP_DATA_FILE
    with open(tmp_file, 'w', encoding='utf-8') as f:
        json.dump(data_list, f, ensure_ascii=False, indent=2)
    os.replace(tmp_file, FINAL_DATA_FILE)
    print(f"✓ JSON 已輸出：{FINAL_DATA_FILE}（來源 {TEMP_DATA_FILE}）")

def parse_total_pages(html_text):
    """解析頁面總數"""
    soup = BeautifulSoup(html_text, 'html.parser')
    span = soup.find('span', id='ContentPlaceHolder1_ContentPlaceHolder2_ContentPlaceHolder2_PageControl1_ucPagingControl1_uLblTotalPageNum')
    if not span:
        return 0
    try:
        value = span.get_text(strip=True).replace(',', '')
        return int(value)
    except:
        return 0

def detect_total_pages():
    """自動偵測符合日期範圍的總頁數"""
    url = build_page_url(1)
    try:
        response = requests.get(url, headers=HEADERS, timeout=30)
        response.encoding = 'utf-8'
        total = parse_total_pages(response.text)
        if total == 0:
            print("⚠ 找不到頁數資訊或沒有資料")
            return 0
        return total
    except Exception as exc:
        print(f"⚠ 偵測總頁數失敗，採預設 1 頁: {exc}")
        return 1

def init_progress(total_pages):
    """初始化（覆寫）頁面進度表"""
    progress = {
        'generated_at': datetime.now().isoformat(timespec='seconds'),
        'total_pages': total_pages,
        'workers': WORKER_COUNT,
        'page_size': PAGE_SIZE,
        'filters': {
            'start_date': START_DATE.isoformat(),
            'end_date': END_DATE.isoformat(),
            'ds_param': BASE_QUERY_PARAMS.get('ds'),
            'de_param': BASE_QUERY_PARAMS.get('de')
        },
        'pages': {
            str(page): {
                'status': 'pending',
                'attempts': 0
            } for page in range(1, total_pages + 1)
        }
    }
    return progress

def count_completed(progress):
    """統計已完成頁數"""
    return sum(1 for meta in progress['pages'].values() if meta.get('status') == 'success')

def assign_pages_to_workers(pages):
    """依照 (page-1) % WORKER_COUNT 分配頁面，避免重複"""
    assignments = {i: [] for i in range(WORKER_COUNT)}
    for page in pages:
        worker_id = (page - 1) % WORKER_COUNT
        assignments[worker_id].append(page)
    return assignments

def worker_job(worker_id, pages, total_pages, results_by_page, progress, progress_lock, data_lock, global_state):
    """單一 worker 的抓取流程"""
    for page in pages:
        start = time.time()
        data = scrape_page_from_html(page)
        elapsed = time.time() - start

        success = False
        error_msg = ''

        if data and (len(data) == PAGE_SIZE or page == total_pages):
            success = True
        else:
            if not data:
                error_msg = '無資料或解析失敗'
            elif len(data) != 20 and page != total_pages:
                error_msg = f'僅取得 {len(data)} 筆'
            elif page == total_pages and not data:
                error_msg = '最後一頁無任何資料'

        with progress_lock:
            entry = progress['pages'][str(page)]
            entry['attempts'] = entry.get('attempts', 0) + 1
            entry['worker'] = worker_id
            entry['last_elapsed_sec'] = round(elapsed, 2)
            entry['last_update'] = datetime.now().isoformat(timespec='seconds')
            entry['raw_records'] = len(data) if data else 0

            if success:
                entry['status'] = 'success'
                entry.pop('last_error', None)
            else:
                entry['status'] = 'failed'
                entry['last_error'] = error_msg or '未知原因'


        page_dates = []

        if success and data:
            with data_lock:
                filtered = []
                for item in data:
                    date_obj = parse_date(item['日期'])
                    if date_obj:
                        date_only = date_obj.date()
                        page_dates.append(date_only)
                        if START_DATE <= date_only <= END_DATE:
                            filtered.append(item)

                with progress_lock:
                    entry = progress['pages'][str(page)]
                    entry['filtered_records'] = len(filtered)
                    entry['has_recent'] = bool(filtered)
                    if page_dates:
                        entry['page_latest_date'] = max(page_dates).isoformat()
                        entry['page_oldest_date'] = min(page_dates).isoformat()
                    if filtered:
                        filtered_dates = [
                            parse_date(item['日期']).date()
                            for item in filtered
                            if parse_date(item['日期'])
                        ]
                        if filtered_dates:
                            entry['max_date'] = max(filtered_dates).isoformat()
                            entry['min_date'] = min(filtered_dates).isoformat()

                results_by_page[page] = filtered
                snapshot_results(results_by_page)
            print(
                f"[Worker {worker_id:02d}] ✓ 第 {page} 頁 (原始 {len(data)} 筆，符合區間 {len(filtered)} 筆，{elapsed:.1f} 秒)",
                flush=True
            )
        elif success:
            # 成功但沒有資料（理論上僅最後一頁）
            with progress_lock:
                entry = progress['pages'][str(page)]
                entry['filtered_records'] = 0
                entry['has_recent'] = False
            print(f"[Worker {worker_id:02d}] ✓ 第 {page} 頁 (無可用資料，{elapsed:.1f} 秒)", flush=True)
        else:
            print(f"[Worker {worker_id:02d}] ✗ 第 {page} 頁 ({error_msg or '重試中'})", flush=True)

        # 若本頁最新日期已早於範圍，更新全域停止頁數
        if page_dates:
            newest = max(page_dates)
            if newest < START_DATE:
                with progress_lock:
                    current_limit = global_state['max_page_allowed']
                    new_limit = min(current_limit, page - 1)
                    if new_limit < current_limit:
                        global_state['max_page_allowed'] = new_limit

def run_parallel_scrape_with_tracking(total_pages):
    """以固定 worker 數平行抓取並記錄進度"""
    progress = init_progress(total_pages)
    results_by_page = {}
    snapshot_results(results_by_page)
    progress_lock = threading.Lock()
    data_lock = threading.Lock()
    global_state = {'max_page_allowed': total_pages}
    round_number = 1

    while True:
        pending_pages = []
        any_update = False
        max_allowed = global_state['max_page_allowed']
        for page, meta in progress['pages'].items():
            page_num = int(page)
            if page_num > total_pages:
                continue
            if page_num > max_allowed:
                if meta.get('status') not in ('skipped', 'skipped_date'):
                    meta['status'] = 'skipped_date'
                    meta['last_update'] = datetime.now().isoformat(timespec='seconds')
                    meta['last_error'] = '日期早於指定範圍'
                    any_update = True
                continue
            status = meta.get('status')
            attempts = meta.get('attempts', 0)
            if status == 'success':
                continue
            if attempts >= MAX_RETRIES:
                if status != 'skipped':
                    meta['status'] = 'skipped'
                    meta['last_update'] = datetime.now().isoformat(timespec='seconds')
                    meta['last_error'] = meta.get('last_error', '已達最大重試次數')
                    any_update = True
                continue
            pending_pages.append(page_num)


        pending_pages.sort()

        if not pending_pages:
            break

        print(f"\n=== 第 {round_number} 輪：剩餘 {len(pending_pages)} 頁待處理 ===")
        assignments = assign_pages_to_workers(pending_pages)
        completed_before = count_completed(progress)

        with ThreadPoolExecutor(max_workers=WORKER_COUNT) as executor:
            futures = []
            for worker_id in range(WORKER_COUNT):
                worker_pages = assignments.get(worker_id, [])
                futures.append(
                    executor.submit(
                        worker_job,
                        worker_id,
                        worker_pages,
                        total_pages,
                        results_by_page,
                        progress,
                        progress_lock,
                        data_lock,
                        global_state
                    )
                )

            for future in futures:
                future.result()

        completed_after = count_completed(progress)
        print(f"→ 累計完成 {completed_after}/{total_pages} 頁")

        if completed_after == completed_before:
            print("⚠ 本輪未取得新的成功頁面，停止重試")
            break

        round_number += 1

    aggregated = flatten_results(results_by_page)

    unfinished = [
        int(page) for page, meta in progress['pages'].items()
        if meta.get('status') != 'success'
    ]

    return aggregated, unfinished

def main():
    """主程式"""
    parser = argparse.ArgumentParser(description="餐飲稽查資料爬蟲（支援日期篩選）")
    parser.add_argument('--start-date', help='起始日期 (YYYY-MM-DD)，預設為昨天')
    parser.add_argument('--end-date', help='結束日期 (YYYY-MM-DD)，預設為今天')
    parser.add_argument('--page-size', type=int, default=20, help='每頁筆數 (5/10/20)')
    parser.add_argument('--workers', type=int, default=5, help='平行請求數 (1-10)')
    parser.add_argument('--max-retries', type=int, default=5, help='每頁最多重試次數')
    args = parser.parse_args()

    today = datetime.now().date()
    start_date = parse_cli_date(args.start_date) or (today - timedelta(days=1))
    end_date = parse_cli_date(args.end_date) or today
    if end_date < start_date:
        start_date, end_date = end_date, start_date

    global START_DATE, END_DATE, PAGE_SIZE, WORKER_COUNT, MAX_RETRIES, BASE_QUERY_PARAMS
    START_DATE = start_date
    END_DATE = end_date
    allowed_page_sizes = {5, 10, 20}
    PAGE_SIZE = args.page_size if args.page_size in allowed_page_sizes else 20
    WORKER_COUNT = max(1, min(10, args.workers or WORKER_COUNT))
    MAX_RETRIES = max(1, args.max_retries or MAX_RETRIES)
    BASE_QUERY_PARAMS = {
        'ftype': 'B',
        'ds': START_DATE.strftime('%Y%m%d'),
        'de': END_DATE.strftime('%Y%m%d')
    }

    print("=" * 70)
    print("  餐飲業者資料爬蟲 - 自動版")
    print("=" * 70)
    print()
    print(f"每頁 {PAGE_SIZE} 筆，從 HTML 解析（包含稽查日期）")
    print(f"僅保留 {START_DATE.strftime('%Y.%m.%d')} 至 {END_DATE.strftime('%Y.%m.%d')} 的資料")
    print()

    total_pages = detect_total_pages()
    if total_pages == 0:
        print("→ 沒有符合日期範圍的資料")
        finalize_json([])
        return

    print(f"→ 偵測到 {total_pages} 頁（每頁 {PAGE_SIZE} 筆）")
    all_data, unfinished_pages = run_parallel_scrape_with_tracking(total_pages)

    print()
    print("=" * 70)
    print(f"總共抓取 {len(all_data)} 筆資料")
    if unfinished_pages:
        print(f"⚠ 仍有 {len(unfinished_pages)} 頁未完成：{', '.join(str(p) for p in unfinished_pages)}")

    print("=" * 70)
    print()

    if all_data:
        # 儲存資料
        save_to_csv(all_data)

        print()
        print("前 5 筆資料範例：")
        print("-" * 70)

        for i, item in enumerate(all_data[:5], 1):
            print(f"\n{i}. {item['名稱']}")
            print(f"   地址：{item['地址']}")
            print(f"   電話：{item['電話']}")
            print(f"   登錄字號：{item['登錄字號']}")
            print(f"   {item['狀態']} {item['日期']}")

        # 統計資料
        print()
        print("=" * 70)
        print("資料統計：")
        print(f"  總筆數：{len(all_data)}")

        # 統計狀態
        status_count = {}
        for item in all_data:
            status = item['狀態']
            status_count[status] = status_count.get(status, 0) + 1

        for status, count in sorted(status_count.items(), key=lambda x: -x[1]):
            print(f"  {status}：{count} 筆")

        print("=" * 70)
    else:
        print("⚠ 日期區間內沒有符合資料")

    finalize_json(all_data)

if __name__ == "__main__":
    main()
