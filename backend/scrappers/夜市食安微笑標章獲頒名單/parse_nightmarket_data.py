#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
台北市夜市食安微笑標章資料處理工具

功能：
    1. 從 PDF 提取夜市食安微笑標章資料
    2. 解析並結構化資料
    3. 輸出 JSON 和 CSV 格式

使用方法：
    1. 安裝依賴：pip install pypdf
    2. 下載 PDF：https://health.gov.taipei/News.aspx?n=76B61C8754E47803&sms=84804F52CD70DFE4
    3. 更新下方 pdf_path 變數
    4. 執行：python parse_nightmarket_data.py

作者：Claude
日期：2024-11-08
"""

import re
import json
import csv
import os
from pypdf import PdfReader

# ==================== 設定區 ====================
# 更新此變數以處理不同年度的 PDF
pdf_path = "113年度夜市食安微笑標章獲頒名單.pdf"
# ==============================================

def extract_text_from_pdf(file_path: str) -> str:
    """
    Extract text content from a PDF file.
    """
    reader = PdfReader(file_path)
    text = []
    for page in reader.pages:
        page_text = page.extract_text()
        if page_text:
            text.append(page_text)
    return "\n".join(text)

def extract_year_from_content(content: str) -> str:
    """
    Extract the year from the content (e.g., "112年度" or "113年度").
    Returns the year string or "未知年度" if not found.
    """
    year_match = re.search(r'(\d{3})', content)
    if year_match:
        return year_match.group(1)
    return "未知年度"

def parse_nightmarket_data(content: str, year: str = None):
    """
    Parse the night market food safety badge data from text content.
    Returns a dictionary organized by night market name.
    """
    # Extract year from content BEFORE cleaning (so we can still find it)
    if year is None:
        year = extract_year_from_content(content)

    # Step 1: Clean up the content - remove unwanted patterns
    # Remove page number patterns: " \n \n<number> \n" (from PDF extraction - 113年度)
    content = re.sub(r' \n \n\d+ \n', '\n', content)
    # Remove standalone page numbers (112年度 format - single digit lines)
    content = re.sub(r'^\d+\s*$', '', content, flags=re.MULTILINE)
    # Remove title lines (xxx 年度夜市食安微笑標章獲頒名單)
    content = re.sub(r'.*夜市食安微笑標章獲頒名單.*\n?', '', content)
    # Remove header lines - handle multi-line headers
    content = re.sub(r'編號 夜市名稱 攤位名稱.*?\n', '', content)
    # Remove standalone "結果" lines (continuation of header)
    content = re.sub(r'^結果\s*$', '', content, flags=re.MULTILINE)

    # Split into lines and clean up
    lines = content.split('\n')

    # Step 2: Parse the data
    night_markets = {}
    current_market = None
    buffer = ""  # Buffer to accumulate lines for a single record

    for line in lines:
        line = line.strip()

        # Skip empty lines
        if not line:
            continue

        # Check if this is a night market name line (ends with "夜市" and doesn't start with a number)
        if line.endswith('夜市') and not re.match(r'^\d+\s', line):
            # Before switching markets, process any remaining buffer
            if buffer and current_market:
                record = parse_record(buffer, current_market, year)
                if record:
                    night_markets[current_market].append(record)

            current_market = line
            if current_market not in night_markets:
                night_markets[current_market] = []
            buffer = ""  # Reset buffer
            continue

        # Skip if we haven't found a market yet
        if current_market is None:
            continue

        # Check if this line starts a new record (begins with a number followed by space and market name)
        if re.match(r'^\d+\s+', line) and current_market and current_market in line:
            # If we have a buffer, process it first
            if buffer and re.search(r'(金質獎?|銀質獎?)', buffer):
                record = parse_record(buffer, current_market, year)
                if record:
                    night_markets[current_market].append(record)
            # Start new buffer with this line
            buffer = line
        else:
            # Add line to buffer
            if buffer:
                buffer += " " + line
            else:
                buffer = line

    # Process any remaining buffer at the end
    if buffer and current_market:
        record = parse_record(buffer, current_market, year)
        if record:
            night_markets[current_market].append(record)

    return night_markets

def parse_record(text: str, market_name: str, year: str):
    """
    Parse a single vendor record.
    Expected format: 編號 夜市名稱 攤位名稱 登錄字號 評核結果
    """
    # Pattern to match: number, registration number (letter-numbers-numbers-numbers), quality rating
    # Everything in between is market name and vendor name
    # Registration numbers can start with A, F, O, D, etc.
    # Quality rating can be "金質", "銀質", "金質獎", or "銀質獎"
    # Allow additional text after quality rating (due to PDF parsing issues)
    pattern = r'^(\d+)\s+(.+?)\s+([A-Z]-\d+-\d+-\d+)\s+(金質獎?|銀質獎?)(?:\s+.*)?$'

    match = re.match(pattern, text)
    if match:
        number = match.group(1)
        middle_part = match.group(2).strip()  # This contains market name and vendor name
        registration = match.group(3)
        quality = match.group(4)

        # Try to split middle_part into market name and vendor name
        # The market name usually appears first
        parts = middle_part.split(None, 1)  # Split on first whitespace
        if len(parts) == 2:
            extracted_market = parts[0]
            vendor_name = parts[1]
        else:
            # If only one part, treat it as vendor name
            extracted_market = market_name
            vendor_name = middle_part

        # Remove spaces from vendor name (caused by line breaks in PDF)
        vendor_name_clean = vendor_name.replace(' ', '')

        record = {
            '年度': year,
            '編號': number,
            '夜市名稱': extracted_market,
            '攤位名稱': vendor_name_clean,
            '食品業者登錄字號': registration,
            '評核結果': quality
        }
        return record
    else:
        # If pattern doesn't match, try to parse manually
        print(f"Warning: Could not parse record: {text}")
        return None

def save_to_json(data: dict, output_file: str):
    """Save the parsed data to JSON format using atomic write operation."""
    # Write to temporary file first
    temp_file = output_file + '.temp'
    with open(temp_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # Atomically rename temp file to final file
    os.replace(temp_file, output_file)
    print(f"JSON file saved to: {output_file}")

def save_to_csv(data: dict, output_file: str):
    """Save the parsed data to CSV format using atomic write operation."""
    # Write to temporary file first
    temp_file = output_file + '.temp'
    with open(temp_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['年度', '編號', '夜市名稱', '攤位名稱', '食品業者登錄字號', '評核結果'])
        writer.writeheader()

        for market_name, vendors in data.items():
            for vendor in vendors:
                writer.writerow(vendor)

    # Atomically rename temp file to final file
    os.replace(temp_file, output_file)
    print(f"CSV file saved to: {output_file}")

if __name__ == "__main__":
    # Extract year from filename
    year_from_filename = extract_year_from_content(pdf_path)

    # Step 1: Extract text from PDF
    print(f"Extracting text from PDF: {pdf_path}")
    content = extract_text_from_pdf(pdf_path)

    """
    # Save extracted content to .txt file
    txt_output = pdf_path.replace(".pdf", ".txt")
    with open(txt_output, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Extracted text saved to: {txt_output}")
    """

    # Step 2: Parse the data
    print("Parsing data...")
    # Try to extract year from content, fallback to filename
    year = extract_year_from_content(content)
    if year == "未知年度":
        year = year_from_filename
    data = parse_nightmarket_data(content, year)

    # Print summary
    print(f"\nFound {len(data)} night markets:")
    for market, vendors in data.items():
        print(f"  {market}: {len(vendors)} vendors")

    # Step 3: Save to JSON
    json_output = "夜市食安微笑標章獲頒名單.json"
    save_to_json(data, json_output)

    # Step 4: Save to CSV
    csv_output = "夜市食安微笑標章獲頒名單.csv"
    save_to_csv(data, csv_output)

    print("\nProcessing complete!")
