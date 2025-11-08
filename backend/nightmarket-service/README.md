# 夜市食安微笑標章資料處理服務

台北通（Town Pass）後端微服務 - 夜市食安資料處理

## 📋 功能

- 從 PDF 提取台北市夜市食安微笑標章資料
- 自動解析並結構化資料
- 輸出 JSON 和 CSV 兩種格式
- 原子寫入操作確保資料完整性
- 支援多年度資料處理（112、113 年度）

## 🚀 快速開始

### 安裝依賴

```bash
pip install -r requirements.txt
```

### 執行程式

```bash
cd src
python parse_nightmarket_data.py
```

## 📁 資料夾結構

```
nightmarket-service/
├── README.md                      # 本文件
├── requirements.txt               # Python 依賴
├── src/
│   └── parse_nightmarket_data.py # 主程式
├── data/
│   ├── raw/                       # 原始 PDF 檔案
│   │   ├── 112年度夜市食安微笑標章獲頒名單.pdf
│   │   └── 113年度夜市食安微笑標章獲頒名單.pdf
│   └── processed/                 # 處理後的資料
│       ├── nightmarket_data.json # JSON 格式輸出
│       ├── nightmarket_data.csv  # CSV 格式輸出
│       └── extracted_text.txt    # PDF 提取的原始文字
└── docs/
    └── API.md                     # API 文件（未來擴充）
```

## 📊 資料格式

### JSON 格式

```json
{
  "南機場夜市": [
    {
      "年度": "112年度",
      "編號": "1",
      "夜市名稱": "南機場夜市",
      "攤位名稱": "曉迪筒仔米糕",
      "食品業者登錄字號": "A-200049553-00000-5",
      "評核結果": "金質獎"
    }
  ]
}
```

### CSV 格式

```csv
年度,編號,夜市名稱,攤位名稱,食品業者登錄字號,評核結果
112年度,1,南機場夜市,曉迪筒仔米糕,A-200049553-00000-5,金質獎
```

## ⚙️ 設定

編輯 [src/parse_nightmarket_data.py](src/parse_nightmarket_data.py) 的設定區（第 28-37 行）：

```python
# 更新此變數以處理不同年度的 PDF
pdf_path = "../data/raw/113年度夜市食安微笑標章獲頒名單.pdf"

# 輸出檔案路徑
json_output_path = "../data/processed/nightmarket_data.json"
csv_output_path = "../data/processed/nightmarket_data.csv"
```

## 📈 處理統計

### 112年度
- **南機場夜市**：70 個攤位
- **華西街夜市**：45 個攤位
- **寧夏夜市**：97 個攤位
- **遼寧夜市**：31 個攤位
- **總計**：228 個攤位

### 113年度
- **艋舺夜市**：73 個攤位
- **公館夜市**：53 個攤位
- **臨江街夜市**：59 個攤位
- **廣州街夜市**：19 個攤位
- **梧州街夜市**：26 個攤位
- **西昌街夜市**：7 個攤位
- **總計**：237 個攤位

## 🔗 資料來源

台北市政府衛生局 - 夜市食安微笑標章
https://health.gov.taipei/News.aspx?n=76B61C8754E47803&sms=84804F52CD70DFE4

## 🛠️ 技術細節

- **語言**: Python 3
- **主要依賴**: pypdf
- **資料處理**: 正則表達式、自動年度識別
- **檔案操作**: 原子寫入（使用臨時檔案 + 重命名）

## ⚠️ 注意事項

- 部分攤位名稱可能因 PDF 格式問題而不完整
- 所有登錄字號和評核結果都經過驗證確保正確
- 程式會自動移除攤位名稱中的空格

## 🔮 未來規劃

- [ ] REST API 端點
- [ ] 資料庫整合
- [ ] 定期自動更新
- [ ] 資料視覺化
- [ ] 更多年度資料支援
