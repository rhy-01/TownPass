#!/bin/bash

# 台北市夜市食安微笑標章資料處理工具 - 安裝腳本

echo "=========================================="
echo "  夜市食安微笑標章資料處理工具"
echo "=========================================="
echo ""

# 檢查 Python 版本
echo "檢查 Python 版本..."
python3 --version

if [ $? -ne 0 ]; then
    echo "❌ 錯誤：找不到 Python 3"
    echo "請先安裝 Python 3: https://www.python.org/downloads/"
    exit 1
fi

echo "✅ Python 已安裝"
echo ""

# 安裝依賴
echo "安裝 Python 依賴套件..."
pip3 install -r requirements.txt

if [ $? -eq 0 ]; then
    echo "✅ 依賴套件安裝完成"
else
    echo "❌ 依賴套件安裝失敗"
    exit 1
fi

echo ""
echo "=========================================="
echo "  安裝完成！"
echo "=========================================="
echo ""
echo "使用方法："
echo "  1. 將 PDF 檔案放入 '夜市食安微笑標章獲頒名單/' 資料夾"
echo "  2. 編輯 parse_nightmarket_data.py 中的 pdf_path"
echo "  3. 執行："
echo "     cd 夜市食安微笑標章獲頒名單"
echo "     python3 parse_nightmarket_data.py"
echo ""
echo "詳細說明請參考 README.md"
echo ""
