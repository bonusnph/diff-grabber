# คู่มือการตั้งค่า Google Sheets สำหรับระบบอนุญาตบัญชี EA

## ภาพรวม

คู่มือนี้อธิบายวิธีการตั้งค่า Google Sheets สำหรับระบบอนุญาตบัญชี EA ระบบนี้ช่วยให้คุณสามารถควบคุมว่าบัญชีเทรดไหนบ้างที่สามารถใช้ EA ได้ และกำหนดวันหมดอายุสำหรับแต่ละบัญชี

## ขั้นตอนที่ 1: สร้าง Google Sheets

### 1.1 สร้าง Google Sheet ใหม่

1. ไปที่ [Google Sheets](https://sheets.google.com)
2. คลิก "สร้าง" → "สเปรดชีตเปล่า"
3. ตั้งชื่อชีตของคุณ (เช่น "EA API Data")

### 1.2 สร้าง Sheet ทั้ง 2 แผ่น

**สำคัญ:** ต้องสร้าง Sheet 2 แผ่นโดยตั้งชื่อให้ตรงกับโค้ด Apps Script:

#### ขั้นตอนการสร้าง Sheet

**Sheet 1: Authorization** (สำหรับตรวจสอบสิทธิ์บัญชี)
1. คลิกขวาที่แท็บ "Sheet1" ด้านล่าง
2. เลือก "เปลี่ยนชื่อ"
3. ตั้งชื่อเป็น **`Authorization`** (ต้องตรงตัวอักษรใหญ่-เล็ก)

**Sheet 2: Signals** (สำหรับสัญญาณเทรด)
1. คลิกปุ่ม "+" ด้านล่างเพื่อเพิ่ม sheet ใหม่
2. คลิกขวาที่แท็บ sheet ใหม่
3. เลือก "เปลี่ยนชื่อ"
4. ตั้งชื่อเป็น **`Signals`** (ต้องตรงตัวอักษรใหญ่-เล็ก)

> **หมายเหตุสำคัญ**: ชื่อ Sheet ต้องตรงกับค่าใน Apps Script:
> ```javascript
> const AUTH_SHEET_NAME = 'Authorization';
> const SIGNAL_SHEET_NAME = 'Signals';
> ```

### 1.3 ตั้งค่าโครงสร้างข้อมูล

#### Sheet 1: Authorization

| A | B | C |
|---|---|---|
| account | expires_at | max_lots |
| 12345678 | 2025.12.31 | 2.0 |
| 87654321 | 2025.06.30 | 1.5 |
| 11223344 | 2025.03.15 | |

**วิธีกรอกข้อมูล:**
1. แถว 1: กรอก header → `account`, `expires_at`, `max_lots`
2. แถว 2 เป็นต้นไป: กรอกข้อมูลบัญชีที่อนุญาต

**คำอธิบายคอลัมน์:**
| คอลัมน์ | ชื่อ | คำอธิบาย | ตัวอย่าง |
|---------|------|----------|----------|
| A | account | หมายเลขบัญชี MT4/MT5 | 12345678 |
| B | expires_at | วันหมดอายุ (YYYY.MM.DD) | 2025.12.31 |
| C | max_lots | ขนาด lot สูงสุด (ไม่บังคับ) | 2.0 |

#### Sheet 2: Signals

| A | B | C |
|---|---|---|
| signal | timestamp | confidence |
| BUY | 2025-12-01T10:30:00Z | 0.85 |

**วิธีกรอกข้อมูล:**
1. แถว 1: กรอก header → `signal`, `timestamp`, `confidence`
2. แถว 2: กรอกสัญญาณปัจจุบัน (มีแค่ 1 แถวข้อมูล)

**คำอธิบายคอลัมน์:**
| คอลัมน์ | ชื่อ | คำอธิบาย | ค่าที่รองรับ |
|---------|------|----------|-------------|
| A | signal | สัญญาณเทรด | `BUY` หรือ `SELL` |
| B | timestamp | เวลาอัพเดท | ISO 8601 format |
| C | confidence | ค่าความมั่นใจ | 0.0 - 1.0 |

> **หมายเหตุ**: Sheet Signals มีแค่ **2 แถว** (header + data)
> - ถ้าใช้ Auto Scraping: ฟังก์ชัน `scrapeAndUpdateSignal()` จะอัพเดทแถวที่ 2 อัตโนมัติ
> - ถ้าใช้ Manual: แก้ไขแถวที่ 2 โดยตรง

### 1.4 ตัวอย่างข้อมูลแบบ CSV

**Authorization Sheet:**
```
account,expires_at,max_lots
12345678,2025.12.31,2.0
87654321,2025.06.30,1.5
11223344,2025.03.15,
55667788,2026.01.01,5.0
```

**Signals Sheet:**
```
signal,timestamp,confidence
BUY,2025-12-01T10:30:00Z,0.85
```

### 1.5 หมายเหตุสำคัญ

**Authorization Sheet:**
- ถ้าไม่กำหนดค่า `max_lots` (เว้นว่าง) จะไม่มีข้อจำกัดด้านขนาด lot
- `max_lots` ตรวจสอบเฉพาะกับ EA ที่ตั้งเป็น `ROLE_MASTER` เท่านั้น
- ถ้า `input_lot` เกินกว่า `max_lots` EA จะแสดง error และไม่สามารถเริ่มทำงานได้

**Signals Sheet:**
- ค่า `signal` ต้องเป็น `BUY` หรือ `SELL` เท่านั้น (case-insensitive)
- ค่า `confidence` ใช้กรองสัญญาณ ถ้าต่ำกว่า `input_api_signal_min_confidence` จะไม่ apply
- ถ้าเปิด Auto Scraping จะอัพเดททุก 1 ชั่วโมง (หรือตามที่ตั้งค่า trigger)

## ขั้นตอนที่ 2: สร้าง Google Apps Script API (แนะนำ)

### 2.1 สร้าง Google Apps Script

1. ไปที่ [Google Apps Script](https://script.google.com)
2. คลิก "โครงการใหม่"
3. ตั้งชื่อโครงการ (เช่น "EA Authorization API")

### 2.2 เขียนโค้ด Apps Script

> **หมายเหตุ**: โค้ดนี้เป็นเวอร์ชัน 1.3 ซึ่งรองรับทั้ง Authorization และ Signal API
> สำหรับรายละเอียดเพิ่มเติมดูที่ [API-Signal-Integration-Guide.md](documents/API-Signal-Integration-Guide.md)

แทนที่โค้ดเริ่มต้นด้วย:

```javascript
// ========================================
// Configuration
// ========================================
const SHEET_ID = 'YOUR_GOOGLE_SHEET_ID_HERE';
const AUTH_SHEET_NAME = 'Authorization';
const SIGNAL_SHEET_NAME = 'Signals';

// ScraperAPI Configuration (required for bypassing Cloudflare)
// Sign up at: https://www.scraperapi.com (Free: 1000 requests/month)
const USE_SCRAPER_API = true;   // Set to true to enable ScraperAPI
const SCRAPER_API_KEY = '';     // Your ScraperAPI key

// ========================================
// Main GET Handler
// ========================================
function doGet(e) {
  try {
    const action = e.parameter.action || 'auth';
    
    if (action === 'auth') {
      return handleAuthRequest(e);
    } else if (action === 'signal') {
      return handleSignalRequest(e);
    } else {
      return createErrorResponse('Invalid action: ' + action);
    }
  } catch (error) {
    return createErrorResponse(error.toString());
  }
}

// ========================================
// Authorization Endpoint
// ========================================
function handleAuthRequest(e) {
  try {
    const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(AUTH_SHEET_NAME);
    
    if (!sheet) {
      return createErrorResponse('Authorization sheet not found');
    }
    
    const data = sheet.getDataRange().getValues();
    
    let csvContent = '';
    for (let i = 0; i < data.length; i++) {
      csvContent += data[i].join(',') + '\n';
    }
    
    return ContentService
      .createTextOutput(csvContent)
      .setMimeType(ContentService.MimeType.TEXT);
      
  } catch (error) {
    return createErrorResponse('Auth error: ' + error.toString());
  }
}

// ========================================
// Signal Endpoint
// ========================================
function handleSignalRequest(e) {
  try {
    const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(SIGNAL_SHEET_NAME);
    
    if (!sheet) {
      return createErrorResponse('Signal sheet not found');
    }
    
    const data = sheet.getDataRange().getValues();
    
    if (data.length < 2) {
      return createErrorResponse('No signal data available');
    }
    
    let csvContent = data[0].join(',') + '\n';
    csvContent += data[1].join(',') + '\n';
    
    return ContentService
      .createTextOutput(csvContent)
      .setMimeType(ContentService.MimeType.TEXT);
      
  } catch (error) {
    return createErrorResponse('Signal error: ' + error.toString());
  }
}

// ========================================
// Helper Functions
// ========================================
function createErrorResponse(message) {
  return ContentService
    .createTextOutput('error,message\n1,' + message)
    .setMimeType(ContentService.MimeType.TEXT);
}

// ========================================
// Update Signal (Manual/Programmatic)
// ========================================
function updateSignal(signal, confidence) {
  try {
    if (signal !== 'BUY' && signal !== 'SELL') {
      throw new Error('Invalid signal: ' + signal);
    }
    
    const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(SIGNAL_SHEET_NAME);
    const timestamp = new Date().toISOString();
    
    sheet.getRange(2, 1).setValue(signal);
    sheet.getRange(2, 2).setValue(timestamp);
    sheet.getRange(2, 3).setValue(confidence || 1.0);
    
    Logger.log('Signal updated: ' + signal);
    return true;
    
  } catch (error) {
    Logger.log('Update signal error: ' + error.toString());
    return false;
  }
}

// ========================================
// Auto-update from TradersUnion Gold Signals
// ========================================
function scrapeAndUpdateSignal() {
  try {
    const targetUrl = 'https://tradersunion.com/currencies/forecast/gold/signals/';
    let url = targetUrl;
    let fetchOptions = {
      method: 'GET',
      muteHttpExceptions: true,
      followRedirects: true
    };
    
    // Use ScraperAPI if enabled (bypasses Cloudflare)
    if (USE_SCRAPER_API) {
      if (!SCRAPER_API_KEY || SCRAPER_API_KEY === '') {
        Logger.log('ERROR: ScraperAPI enabled but API key is missing!');
        Logger.log('Get your API key at: https://www.scraperapi.com/signup');
        return false;
      }
      
      // Build ScraperAPI URL
      url = 'https://api.scraperapi.com/?api_key=' + SCRAPER_API_KEY + 
            '&url=' + encodeURIComponent(targetUrl) +
            '&render=false';  // Set to true if need JavaScript rendering
      
      Logger.log('Using ScraperAPI to bypass Cloudflare...');
    } else {
      // Direct fetch (may be blocked by Cloudflare)
      fetchOptions.headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9'
      };
      
      Logger.log('Fetching directly (no ScraperAPI)...');
    }
    
    // Fetch webpage content
    const response = UrlFetchApp.fetch(url, fetchOptions);
    const statusCode = response.getResponseCode();
    
    if (statusCode !== 200) {
      Logger.log('HTTP Error: ' + statusCode);
      
      if (statusCode === 403 && !USE_SCRAPER_API) {
        Logger.log('Blocked by Cloudflare! Consider enabling ScraperAPI.');
        Logger.log('Set USE_SCRAPER_API = true and add your API key.');
      }
      
      return false;
    }
    
    const html = response.getContentText();
    
    // Check if we got Cloudflare challenge page
    if (html.includes('Attention Required') && html.includes('Cloudflare')) {
      Logger.log('Cloudflare challenge detected!');
      Logger.log('Enable ScraperAPI to bypass: Set USE_SCRAPER_API = true');
      return false;
    }
    
    // Parse signal from HTML
    const signal = parseSignalFromHTML(html);
    
    if (!signal) {
      Logger.log('Failed to parse signal from webpage');
      return false;
    }
    
    // Update signal with default confidence 0.85
    const confidence = 0.85;
    updateSignal(signal, confidence);
    
    Logger.log('Signal updated successfully: ' + signal);
    return true;
    
  } catch (error) {
    Logger.log('Scrape error: ' + error.toString());
    
    if (error.toString().includes('429')) {
      Logger.log('Rate limit exceeded. Wait before trying again.');
    }
    
    return false;
  }
}

// ========================================
// Parse Signal from HTML Content
// ========================================
function parseSignalFromHTML(html) {
  try {
    Logger.log('=== DEBUG: Starting HTML Parse ===');
    Logger.log('HTML length: ' + html.length + ' chars');
    
    // Method 1: Look for "Forecast:" section and extract signal
    Logger.log('\n[Method 1] Searching: Forecast: + ta-wg__summary-body');
    const forecastPattern = /Forecast:[\s\S]{0,500}ta-wg__summary-body[^>]*>([^<]+)</i;
    let match = html.match(forecastPattern);
    
    if (match && match[1]) {
      let signalText = match[1].trim();
      Logger.log('[Method 1] Found text: "' + signalText + '"');
      Logger.log('[Method 1] Context (150 chars): "' + match[0].substring(0, 150) + '..."');
      
      let signalUpper = signalText.toUpperCase();
      
      if (signalUpper.includes('BUY')) {
        Logger.log('[Method 1] Parsed: BUY -> Returning: SELL (swapped)');
        return 'SELL';
      } else if (signalUpper.includes('SELL')) {
        Logger.log('[Method 1] Parsed: SELL -> Returning: BUY (swapped)');
        return 'BUY';
      } else {
        Logger.log('[Method 1] No BUY/SELL in text: "' + signalText + '"');
      }
    } else {
      Logger.log('[Method 1] No match');
    }
    
    // Method 2: Broader search for ALL ta-wg__summary-body
    Logger.log('\n[Method 2] Searching ALL ta-wg__summary-body elements');
    const summaryPattern = /ta-wg__summary-body[^>]*>([^<]+)/gi;
    const matches = html.matchAll(summaryPattern);
    
    let count = 0;
    for (const m of matches) {
      count++;
      if (m && m[1]) {
        let text = m[1].trim();
        Logger.log('[Method 2.' + count + '] Found: "' + text + '"');
        
        let textUpper = text.toUpperCase();
        
        if (textUpper.includes('BUY')) {
          Logger.log('[Method 2.' + count + '] Parsed: BUY -> Returning: SELL (swapped)');
          return 'SELL';
        } else if (textUpper.includes('SELL')) {
          Logger.log('[Method 2.' + count + '] Parsed: SELL -> Returning: BUY (swapped)');
          return 'BUY';
        }
      }
    }
    Logger.log('[Method 2] Found ' + count + ' elements, none with BUY/SELL');
    
    // Method 3: Search around "Forecast" keyword
    Logger.log('\n[Method 3] Searching around "Forecast:" keyword');
    const forecastIndex = html.toLowerCase().indexOf('forecast:');
    
    if (forecastIndex !== -1) {
      const chunk = html.substring(forecastIndex, forecastIndex + 1000);
      Logger.log('[Method 3] Found at position: ' + forecastIndex);
      Logger.log('[Method 3] Context (300 chars):\n' + chunk.substring(0, 300));
      
      const chunkUpper = chunk.toUpperCase();
      
      const hasBuy = chunkUpper.match(/\bBUY\b/);
      const hasSell = chunkUpper.match(/\bSELL\b/);
      
      if (hasBuy && hasSell) {
        const buyPos = chunkUpper.indexOf('BUY');
        const sellPos = chunkUpper.indexOf('SELL');
        Logger.log('[Method 3] BOTH found - BUY@' + buyPos + ', SELL@' + sellPos);
        
        if (buyPos < sellPos) {
          Logger.log('[Method 3] Using BUY (first) -> Returning: SELL (swapped)');
          return 'SELL';
        } else {
          Logger.log('[Method 3] Using SELL (first) -> Returning: BUY (swapped)');
          return 'BUY';
        }
      } else if (hasBuy) {
        Logger.log('[Method 3] Parsed: BUY -> Returning: SELL (swapped)');
        return 'SELL';
      } else if (hasSell) {
        Logger.log('[Method 3] Parsed: SELL -> Returning: BUY (swapped)');
        return 'BUY';
      } else {
        Logger.log('[Method 3] No BUY/SELL in context');
      }
    } else {
      Logger.log('[Method 3] "Forecast:" not found');
    }
    
    // Debug: Show HTML preview
    Logger.log('\nAll methods failed!');
    Logger.log('HTML preview (first 800 chars):\n' + html.substring(0, 800));
    Logger.log('\nNo signal found');
    
    return null;
    
  } catch (error) {
    Logger.log('Parse error: ' + error.toString());
    return null;
  }
}

// ========================================
// Setup Time-Based Trigger (Optional)
// ========================================
function createHourlyTrigger() {
  const triggers = ScriptApp.getProjectTriggers();
  for (let i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'scrapeAndUpdateSignal') {
      ScriptApp.deleteTrigger(triggers[i]);
    }
  }
  
  // Run every hour at minute 0 (e.g., 10:00, 11:00, 12:00, ...)
  ScriptApp.newTrigger('scrapeAndUpdateSignal')
    .timeBased()
    .everyHours(1)
    .nearMinute(0)
    .create();
    
  Logger.log('Hourly trigger created (runs at minute 0 of each hour)');
}
```

### 2.3 กำหนดค่า Sheet ID

1. เปิด Google Sheet ของคุณ
2. คัดลอก Sheet ID จาก URL (ส่วนระหว่าง `/d/` และ `/edit`)
   - ตัวอย่าง: `https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit`
   - Sheet ID: `1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms`
3. แทนที่ `YOUR_SHEET_ID_HERE` ในโค้ดด้วย Sheet ID จริง

### 2.4 Deploy Apps Script

1. คลิก "Deploy" → "New deployment"
2. เลือก type: "Web app"
3. ตั้งค่า:
   - **Execute as**: Me (your email)
   - **Who has access**: Anyone
4. คลิก "Deploy"
5. อนุญาตสิทธิ์ที่จำเป็น
6. คัดลอก **Web app URL** (จะใช้เป็น API endpoint)

**ตัวอย่าง Web app URL:**
```
https://script.google.com/macros/s/AKfycbzXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX/exec
```

**🔗 ตัวอย่างจริงที่ใช้งานได้:**
- **Google Sheet URL**: https://docs.google.com/spreadsheets/d/1e9VNVA5oPjIggPQ2ScisBiLV1mvaJA2CQ3Tqln0BUhM/edit?gid=0#gid=0
- **Apps Script API URL**: https://script.google.com/macros/s/AKfycbwu4NytwY2ycRFsonoyEJFJICqT-ooS6Wszb5LTY3PEysF1hxXMEZ0ThgAlzUlCZr1gdg/exec

**ข้อมูลในชีตตัวอย่าง:**

*Sheet: Authorization*
```
account,expires_at,max_lots
502523729,2025.12.31,2.0
```

*Sheet: Signals*
```
signal,timestamp,confidence
BUY,2025-12-01T10:30:00Z,0.85
```

**ทดสอบ API Endpoints:**
- Authorization: `YOUR_URL?action=auth`
- Signal: `YOUR_URL?action=signal`

## ขั้นตอนที่ 3: วิธีการแบบเดิม (CSV Export) - ไม่แนะนำ

### 3.1 การตั้งค่าการแชร์

1. คลิกปุ่ม "แชร์" (มุมบนขวา)
2. คลิก "เปลี่ยนเป็นทุกคนที่มีลิงก์"
3. ตั้งสิทธิ์เป็น "ผู้ดู"
4. คลิก "เสร็จสิ้น"

### 3.2 รับ URL สำหรับ Export CSV

1. คัดลอก URL ของ Google Sheets (เช่น `https://docs.google.com/spreadsheets/d/ABC123.../edit#gid=0`)
2. แทนที่ `/edit#gid=0` ด้วย `/export?format=csv&gid=0`
3. URL สุดท้ายควรมีลักษณะ: `https://docs.google.com/spreadsheets/d/ABC123.../export?format=csv&gid=0`

**ตัวอย่าง:**
- URL เดิม: `https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=0`
- CSV Export URL: `https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/export?format=csv&gid=0`

## ขั้นตอนที่ 4: กำหนดค่า MetaTrader

### 4.1 เพิ่ม URL ในรายการ URL ที่อนุญาต

**สำหรับ Google Apps Script API (แนะนำ):**

**MT4:**
1. ไปที่ Tools → Options → Expert Advisors
2. เลือก "Allow WebRequest for listed URL"
3. เพิ่ม URL ต่อไปนี้:
   ```
   https://script.google.com
   https://script.googleusercontent.com
   ```
4. คลิก OK

**MT5:**
1. ไปที่ Tools → Options → Expert Advisors
2. เลือก "Allow WebRequest for listed URL"
3. เพิ่ม URL ต่อไปนี้:
   ```
   https://script.google.com
   https://script.googleusercontent.com
   ```
4. คลิก OK

**สำหรับ CSV Export (วิธีเดิม):**

**MT4/MT5:**
1. ไปที่ Tools → Options → Expert Advisors
2. เลือก "Allow WebRequest for listed URL"
3. เพิ่ม URL:
   ```
   https://docs.google.com
   ```
4. คลิก OK

### 4.2 พารามิเตอร์ Input ของ EA

**สำหรับ Google Apps Script API:**
```
input_auth_enabled = true
input_auth_sheet_url = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec"
```

**🔧 ตัวอย่างการตั้งค่าจริง:**
```
input_auth_enabled = true
input_auth_sheet_url = "https://script.google.com/macros/s/AKfycbwu4NytwY2ycRFsonoyEJFJICqT-ooS6Wszb5LTY3PEysF1hxXMEZ0ThgAlzUlCZr1gdg/exec"
```

**สำหรับ CSV Export:**
```
input_auth_enabled = true
input_auth_sheet_url = "https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID/export?format=csv&gid=0"
```

**🔧 ตัวอย่างการตั้งค่าจริง (CSV Export):**
```
input_auth_enabled = true
input_auth_sheet_url = "https://docs.google.com/spreadsheets/d/1e9VNVA5oPjIggPQ2ScisBiLV1mvaJA2CQ3Tqln0BUhM/export?format=csv&gid=0"
```

## ขั้นตอนที่ 5: การทดสอบ

### 5.1 ทดสอบ Google Apps Script API

**ทดสอบ Authorization Endpoint:**
1. เปิด Web app URL ในเว็บเบราว์เซอร์พร้อม `?action=auth`
2. คุณควรเห็นข้อมูล CSV จาก Sheet Authorization:
   ```
   account,expires_at,max_lots
   12345678,2025.12.31,2.0
   87654321,2025.06.30,1.5
   ```

**ทดสอบ Signal Endpoint:**
1. เปิด Web app URL ในเว็บเบราว์เซอร์พร้อม `?action=signal`
2. คุณควรเห็นข้อมูล CSV จาก Sheet Signals:
   ```
   signal,timestamp,confidence
   BUY,2025-12-01T10:30:00Z,0.85
   ```

**🧪 ทดสอบกับตัวอย่างจริง:**

*Authorization:*
- เปิด URL: `https://script.google.com/macros/s/AKfycbwu4NytwY2ycRFsonoyEJFJICqT-ooS6Wszb5LTY3PEysF1hxXMEZ0ThgAlzUlCZr1gdg/exec?action=auth`
- ผลลัพธ์ที่ได้:
  ```
  account,expires_at,max_lots
  502523729,2025.12.31,2.0
  ```

*Signal:*
- เปิด URL: `https://script.google.com/macros/s/AKfycbwu4NytwY2ycRFsonoyEJFJICqT-ooS6Wszb5LTY3PEysF1hxXMEZ0ThgAlzUlCZr1gdg/exec?action=signal`
- ผลลัพธ์ที่ได้:
  ```
  signal,timestamp,confidence
  BUY,2025-12-01T10:30:00Z,0.85
  ```

> **หมายเหตุ**: ถ้าไม่ใส่ `?action=` จะใช้ค่าเริ่มต้นเป็น `auth`

### 5.2 ทดสอบ Auto Scraping (ไม่บังคับ)

ถ้าเปิดใช้งาน ScraperAPI:
1. เปิด Apps Script Editor
2. เลือกฟังก์ชัน `scrapeAndUpdateSignal`
3. กด Run
4. ตรวจสอบ Logs (View → Logs) ว่าดึงสัญญาณสำเร็จ
5. ตรวจสอบ Sheet Signals ว่าอัพเดทข้อมูลแล้ว

### 5.3 ทดสอบการเข้าถึง CSV (วิธีเดิม) - ไม่แนะนำ

1. เปิด CSV export URL ในเว็บเบราว์เซอร์
2. คุณควรเห็นข้อมูล CSV เช่น:
   ```
   account,expires_at
   12345678,2025.12.31
   87654321,2025.06.30
   ```

### 5.4 ทดสอบการอนุญาต EA

1. แนบ EA กับชาร์ตโดยเปิดใช้งานการอนุญาต
2. ตรวจสอบแท็บ Expert สำหรับข้อความการอนุญาต:
   - `[AUTH] Checking account authorization...`
   - `[AUTH] Account XXXXX authorized (expires: YYYY.MM.DD)`

## ขั้นตอนที่ 6: การจัดการข้อมูล

### 6.1 การจัดการบัญชี (Sheet: Authorization)

**การเพิ่มบัญชีใหม่:**
1. เปิด Google Sheet ของคุณ
2. ไปที่ Sheet `Authorization`
3. เพิ่มแถวใหม่พร้อมหมายเลขบัญชีและวันหมดอายุ
4. การเปลี่ยนแปลงจะมีผลภายใน 24 ชั่วโมง (หรือรีสตาร์ท EA เพื่อให้มีผลทันที)

**การลบบัญชี:**
1. ลบแถวที่มีหมายเลขบัญชีนั้น
2. หรือตั้งวันหมดอายุเป็นวันที่ผ่านมาแล้ว

**การขยายวันหมดอายุ:**
1. อัปเดตคอลัมน์ `expires_at` ด้วยวันที่ใหม่
2. ใช้รูปแบบ **YYYY.MM.DD** (เช่น 2025.12.31)

### 6.2 การจัดการสัญญาณ (Sheet: Signals)

**การอัพเดทสัญญาณด้วยมือ:**
1. เปิด Google Sheet ของคุณ
2. ไปที่ Sheet `Signals`
3. แก้ไขแถวที่ 2:
   - Column A: `BUY` หรือ `SELL`
   - Column B: timestamp (ไม่บังคับ)
   - Column C: confidence 0.0-1.0 (ไม่บังคับ)

**การเปิดใช้งาน Auto Scraping:**
1. เปิด Apps Script Editor
2. รันฟังก์ชัน `createHourlyTrigger()` เพื่อตั้งอัพเดทอัตโนมัติ
3. ตรวจสอบ Triggers ใน Apps Script → Triggers

> **หมายเหตุ**: Trigger จะทำงานทุกชั่วโมงที่นาทีที่ 0 (เช่น 10:00, 11:00, 12:00, ...)
> ไม่ว่าจะเริ่มรัน `createHourlyTrigger()` ตอนไหนก็ตาม

**การปิด Auto Scraping:**
1. ไปที่ Apps Script → Triggers
2. ลบ trigger ของ `scrapeAndUpdateSignal`

## ตัวอย่างรูปแบบวันที่

| รูปแบบ | ตัวอย่าง | คำอธิบาย |
|--------|---------|-------------|
| **YYYY.MM.DD** | 2025.12.31 | **รูปแบบที่แนะนำ** |
| YYYY-MM-DD | 2025-12-31 | รองรับด้วย |
| YYYY/MM/DD | 2025/12/31 | รองรับด้วย |

## ข้อพิจารณาด้านความปลอดภัย

### 7.1 ข้อดีของ Google Apps Script API

**ความปลอดภัย:**
- ไม่ต้องแชร์ Google Sheet เป็น public
- ควบคุมการเข้าถึงได้ดีกว่า
- สามารถเพิ่ม authentication ขั้นสูงได้
- Log การเข้าถึงได้

**ประสิทธิภาพ:**
- ตอบสนองเร็วกว่า CSV export
- สามารถ cache ข้อมูลได้
- ประมวลผลข้อมูลก่อนส่งได้

### 7.2 ความปลอดภัยของชีต

**สำหรับ Google Apps Script:**
- เก็บ Web app URL เป็นความลับ
- ตรวจสอบ Apps Script logs เป็นประจำ
- สามารถเพิ่ม IP whitelist ได้

**สำหรับ CSV Export:**
- เก็บ URL ของชีตเป็นความลับ
- แชร์เฉพาะกับบุคคลที่เชื่อถือได้
- ตรวจสอบบัญชีที่ได้รับอนุญาตเป็นประจำ
- ใช้วันหมดอายุสำหรับการเข้าถึงชั่วคราว

### 7.3 หมายเลขบัญชี

- ไม่เปิดเผยหมายเลขบัญชีต่อสาธารณะ
- ใช้รหัสผ่านที่แข็งแกร่งสำหรับบัญชี Google
- เปิดใช้งานการยืนยันตัวตน 2 ขั้นตอนในบัญชี Google

## การแก้ไขปัญหา

### 8.1 ปัญหาที่พบบ่อย

**ข้อผิดพลาด "WebRequest failed":**
- ตรวจสอบว่า URL ถูกเพิ่มในรายการ URL ที่อนุญาตใน MT4/MT5 แล้ว
- สำหรับ Apps Script: เพิ่ม `https://script.google.com` และ `https://script.googleusercontent.com`
- สำหรับ CSV Export: เพิ่ม `https://docs.google.com`
- ทดสอบ URL ในเว็บเบราว์เซอร์

**ข้อผิดพลาด "Account not found":**
- ตรวจสอบว่าหมายเลขบัญชีถูกต้องในชีต
- ตรวจสอบว่าไม่มีช่องว่างเพิ่มเติมในข้อมูล
- ตรวจสอบว่ารูปแบบ CSV ถูกต้อง

**ข้อผิดพลาด "HTTP error: 403":**
- สำหรับ Apps Script: ตรวจสอบว่า Deploy ถูกต้องและ "Who has access" เป็น "Anyone"
- สำหรับ CSV Export: ตรวจสอบว่าชีตสามารถเข้าถึงได้สาธารณะ

**ข้อผิดพลาด Apps Script "Exception: Cannot read properties":**
- ตรวจสอบว่า Sheet ID ถูกต้อง
- ตรวจสอบว่าชีตมีข้อมูลและไม่ว่าง
- ตรวจสอบว่า Apps Script มีสิทธิ์เข้าถึงชีต

**ข้อผิดพลาด "Lot size violation":**
- ข้อความ error: `Account XXXXX lot size violation: input_lot=X.XX exceeds max_lots=Y.YY`
- ตรวจสอบค่า `input_lot` ใน EA settings
- ตรวจสอบค่า `max_lots` ในคอลัมน์ C ของ Google Sheet
- แก้ไข: ลดค่า `input_lot` หรือเพิ่มค่า `max_lots` ใน Google Sheet
- หมายเหตุ: การตรวจสอบนี้ใช้กับ ROLE_MASTER เท่านั้น

### 8.2 ขั้นตอนการดีบัก

**สำหรับ Google Apps Script:**
1. ทดสอบ Web app URL ในเว็บเบราว์เซอร์
2. ตรวจสอบ Apps Script logs ใน Google Apps Script Editor
3. ตรวจสอบแท็บ Expert ของ MT4/MT5 สำหรับข้อความข้อผิดพลาด
4. ตรวจสอบว่าหมายเลขบัญชีตรงกันทุกประการ

**สำหรับ CSV Export:**
1. ทดสอบ CSV URL ในเว็บเบราว์เซอร์
2. ตรวจสอบแท็บ Expert ของ MT4/MT5 สำหรับข้อความข้อผิดพลาด
3. ตรวจสอบว่าหมายเลขบัญชีตรงกันทุกประการ
4. ตรวจสอบว่ารูปแบบวันที่ถูกต้อง

## คุณสมบัติขั้นสูง

### 9.1 Google Apps Script ขั้นสูง

**การเพิ่ม Authentication ใน doGet:**
```javascript
function doGet(e) {
  try {
    // ตรวจสอบ API key (ไม่บังคับ)
    const apiKey = e.parameter.key;
    if (apiKey !== 'YOUR_SECRET_API_KEY') {
      return createErrorResponse('Unauthorized');
    }
    
    const action = e.parameter.action || 'auth';
    
    if (action === 'auth') {
      return handleAuthRequest(e);
    } else if (action === 'signal') {
      return handleSignalRequest(e);
    } else {
      return createErrorResponse('Invalid action: ' + action);
    }
  } catch (error) {
    return createErrorResponse(error.toString());
  }
}
```

**การ Log การเข้าถึง:**
```javascript
function handleAuthRequest(e) {
  try {
    // Log การเข้าถึง
    const timestamp = new Date();
    Logger.log('Auth request at ' + timestamp.toISOString());
    
    const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(AUTH_SHEET_NAME);
    // ... โค้ดเดิม ...
  } catch (error) {
    return createErrorResponse('Auth error: ' + error.toString());
  }
}
```

### 9.2 ScraperAPI Configuration

**การตั้งค่า ScraperAPI สำหรับ bypass Cloudflare:**
```javascript
// Configuration section
const USE_SCRAPER_API = true;   // เปิดใช้ ScraperAPI
const SCRAPER_API_KEY = 'YOUR_SCRAPER_API_KEY';  // API key จาก scraperapi.com

// Credit Usage:
// render=false → 1 credit per request (แนะนำ)
// render=true  → 5 credits per request
// Free tier: 1,000 credits/month
```

**ขั้นตอนการสมัคร ScraperAPI:**
1. ไปที่ https://www.scraperapi.com/signup
2. สมัครบัญชี (Free tier)
3. Login แล้วไปที่ Dashboard
4. คัดลอก **API Key**
5. แทนที่ `SCRAPER_API_KEY` ในโค้ด

### 9.4 หลายชีต

คุณสามารถใช้ชีตที่แตกต่างกันสำหรับ EA instances ที่แตกต่างกันโดยใช้ค่า `gid` ที่แตกต่างกัน:

- ชีต 1: `gid=0`
- ชีต 2: `gid=123456789`

### 9.5 การจำกัดขนาด Lot (Max Lots)

**คำอธิบาย:**
- คอลัมน์ `max_lots` (คอลัมน์ C) ใช้สำหรับจำกัดขนาด lot สูงสุดที่บัญชีสามารถใช้ได้
- การตรวจสอบจะทำงานเฉพาะกับ EA ที่ตั้งเป็น `ROLE_MASTER` เท่านั้น
- หาก `input_lot` เกินกว่า `max_lots` ที่กำหนด:
  - EA จะแสดง Alert error message
  - EA จะไม่สามารถเริ่มทำงานได้ (INIT_FAILED)
  - Log event จะบันทึกเป็น `AUTH_LOT_LIMIT_VIOLATION`

**ตัวอย่างการใช้งาน:**
```
account,expires_at,max_lots
12345678,2025.12.31,2.0
87654321,2025.06.30,1.0
11223344,2025.03.15,
```

- บัญชี 12345678: สามารถใช้ `input_lot` ได้สูงสุด 2.0
- บัญชี 87654321: สามารถใช้ `input_lot` ได้สูงสุด 1.0
- บัญชี 11223344: ไม่มีข้อจำกัด (เว้นว่าง)

### 9.6 คอลัมน์เพิ่มเติม

คุณสามารถเพิ่มคอลัมน์เพิ่มเติมสำหรับการจัดทำเอกสาร (จะถูกละเว้นโดย EA):

| account | expires_at | max_lots | trader_name | notes |
|---------|------------|----------|-------------|-------|
| 12345678 | 2025.12.31 | 2.0 | นาย ก | ลูกค้า VIP |

### 9.7 กลยุทธ์การสำรองข้อมูล

1. สำรองข้อมูลชีตการอนุญาตเป็นประจำ
2. เก็บสำเนาออฟไลน์ของบัญชีที่ได้รับอนุญาต
3. พิจารณาใช้หลายชีตเพื่อความซ่ำซ้อน

## ข้อจำกัดอัตรา API

- Google Sheets อนุญาตการเข้าถึง API ในระดับที่เหมาะสม
- EA ตรวจสอบการอนุญาตทุก 24 ชั่วโมงหลังจากการตรวจสอบครั้งแรก
- ไม่จำเป็นต้องจำกัดอัตราพิเศษสำหรับการใช้งานปกติ

## การสนับสนุน

หากคุณพบปัญหา:

1. ตรวจสอบส่วนการแก้ไขปัญหา
2. ตรวจสอบว่าขั้นตอนการตั้งค่าทั้งหมดเสร็จสมบูรณ์
3. ทดสอบด้วยชีต 2 บัญชีง่ายๆ ก่อน
4. ตรวจสอบแท็บ Expert ของ MT4/MT5 สำหรับข้อความข้อผิดพลาดโดยละเอียด

---

**หมายเหตุ:** ระบบนี้ให้การอนุญาตบัญชีพื้นฐาน สำหรับการใช้งานในการผลิตกับบัญชีที่มีความละเอียดอ่อน ให้พิจารณามาตรการความปลอดภัยเพิ่มเติม เช่น การจำกัด IP หรือระบบการยืนยันตัวตนที่ซับซ้อนกว่า

---

## เอกสารที่เกี่ยวข้อง

สำหรับฟีเจอร์ขั้นสูงและรายละเอียดเพิ่มเติม:

- **[API-Signal-Integration-Guide.md](documents/API-Signal-Integration-Guide.md)** - คู่มือฉบับเต็มสำหรับ API Signal Integration
  - TP/SL Active Diff Close Feature
  - Auto Web Scraping จาก TradersUnion
  - Real-World Scenarios & Best Practices
  - Testing Checklist ครบถ้วน

---

*Document Version: 1.3*  
*Last Updated: January 2026*  
*Synced with: API-Signal-Integration-Guide.md v1.3*
