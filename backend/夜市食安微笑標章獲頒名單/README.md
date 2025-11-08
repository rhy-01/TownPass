# 夜市食安微笑標章資料處理

此資料夾包含處理台北市夜市食安微笑標章 PDF 資料的工具。

## 快速開始

### 1. 安裝依賴（如果尚未安裝）

```bash
cd ..
pip install -r requirements.txt
```

或直接安裝：

```bash
pip install pypdf
```

### 2. 使用方式

編輯 [parse_nightmarket_data.py](parse_nightmarket_data.py:30) 第 30 行，設定要處理的 PDF 檔案：

```python
pdf_path = "113年度夜市食安微笑標章獲頒名單.pdf"  # 修改這裡
```

執行程式：

```bash
python parse_nightmarket_data.py
```

### 3. 輸出檔案

程式會生成：
- `夜市食安微笑標章獲頒名單.json` - JSON 格式
- `夜市食安微笑標章獲頒名單.csv` - CSV 格式（Excel 可開啟）

## 資料來源

- 112年度：[112年度夜市食安微笑標章獲頒名單.pdf](112年度夜市食安微笑標章獲頒名單.pdf)
- 113年度：[113年度夜市食安微笑標章獲頒名單.pdf](113年度夜市食安微笑標章獲頒名單.pdf)

官方網站：https://health.gov.taipei/News.aspx?n=76B61C8754E47803&sms=84804F52CD70DFE4

## 處理結果

### 112年度
- 南機場夜市：70 個攤位
- 華西街夜市：45 個攤位
- 寧夏夜市：97 個攤位
- 遼寧夜市：31 個攤位

### 113年度
- 艋舺夜市：73 個攤位
- 公館夜市：53 個攤位
- 臨江街夜市：59 個攤位
- 廣州街夜市：19 個攤位
- 梧州街夜市：26 個攤位
- 西昌街夜市：7 個攤位
