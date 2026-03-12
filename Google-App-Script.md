# คู่มือติดตั้ง Google Apps Script สำหรับ EA API

คู่มือฉบับสมบูรณ์สำหรับการติดตั้งและใช้งานระบบ API ผ่าน Google Apps Script รองรับทั้ง Authorization, Signal API และ External Signal Proxy

*เวอร์ชัน: 1.6 | อัพเดทล่าสุด: มีนาคม 2026*

---

## สารบัญ

- [ขั้นตอนที่ 1: สร้าง Google Sheet](#ขั้นตอนที่-1-สร้าง-google-sheet)
- [ขั้นตอนที่ 2: สร้าง Google Apps Script](#ขั้นตอนที่-2-สร้าง-google-apps-script)
- [ขั้นตอนที่ 3: กำหนดค่า Configuration](#ขั้นตอนที่-3-กำหนดค่า-configuration)
- [ขั้นตอนที่ 4: Deploy เป็น Web App](#ขั้นตอนที่-4-deploy-เป็น-web-app)
- [ขั้นตอนที่ 5: ทดสอบ API](#ขั้นตอนที่-5-ทดสอบ-api)
- [ขั้นตอนที่ 6: ตั้งค่า Auto Scraping / Fast Polling](#ขั้นตอนที่-6-ตั้งค่า-auto-scraping--fast-polling)
- [ขั้นตอนที่ 7: ตั้งค่า External Signal Proxy](#ขั้นตอนที่-7-ตั้งค่า-external-signal-proxy)
- [ขั้นตอนที่ 8: ตั้งค่า MT4/MT5](#ขั้นตอนที่-8-ตั้งค่า-mt4mt5)
- [โค้ด Google Apps Script (ฉบับเต็ม)](#โค้ด-google-apps-script-ฉบับเต็ม)
- [การแก้ปัญหา](#การแก้ปัญหา)

---

## ขั้นตอนที่ 1: สร้าง Google Sheet

### 1.1 สร้าง Google Sheet ใหม่

1. ไปที่ [Google Sheets](https://sheets.google.com)
2. คลิก "สร้าง" > "สเปรดชีตเปล่า"
3. ตั้งชื่อ (เช่น "EA API Data")

### 1.2 สร้าง Sheet 2 แผ่น

**Sheet 1: Authorization** (ตรวจสอบสิทธิ์บัญชี)

1. คลิกขวาที่แท็บ "Sheet1" ด้านล่าง > เปลี่ยนชื่อเป็น **`Authorization`**
2. กรอก header แถวที่ 1 และข้อมูลตั้งแต่แถวที่ 2:

| A | B | C | D | E | F |
|---|---|---|---|---|---|
| account | expires_at | max_lots | open_cooldown | close_cooldown | min_version |
| 12345678 | 2025.12.31 | 2.0 | 7200 | 300 | 1.16 |

**Sheet 2: Signals** (สัญญาณเทรด)

1. คลิกปุ่ม "+" ด้านล่างเพื่อเพิ่ม sheet ใหม่
2. คลิกขวา > เปลี่ยนชื่อเป็น **`Signals`**
3. กรอก header แถวที่ 1 และข้อมูลแถวที่ 2:

| A | B | C | D | E | F |
|---|---|---|---|---|---|
| signal | timestamp | confidence | source | ext_override | ext_sheet_id |
| BUY | 2025-12-01T10:30:00Z | 0.85 | AUTO | FALSE | |

**คำอธิบายคอลัมน์ Signals:**

| คอลัมน์ | ชื่อ | คำอธิบาย | ค่าที่รองรับ |
|---------|------|----------|-------------|
| A | signal | สัญญาณเทรด | `BUY` หรือ `SELL` |
| B | timestamp | เวลาอัพเดท | ISO 8601 format |
| C | confidence | ค่าความมั่นใจ | 0.0 - 1.0 |
| D | source | แหล่งที่มา (ระบบเติมอัตโนมัติ) | `AUTO` หรือ `EXTERNAL` |
| E | ext_override | เปิด/ปิดรับ signal จากชีทภายนอก | `TRUE` หรือ `FALSE` |
| F | ext_sheet_id | Sheet ID หรือ URL ของชีทภายนอก | Google Sheet ID/URL |

> **สำคัญ**: ชื่อ Sheet ต้องตรงตัวอักษรใหญ่-เล็กตามนี้เท่านั้น: `Authorization` และ `Signals`

### 1.3 จด Sheet ID

เปิด Google Sheet แล้วคัดลอก Sheet ID จาก URL:
```
https://docs.google.com/spreadsheets/d/[SHEET_ID_ตรงนี้]/edit
```

---

## ขั้นตอนที่ 2: สร้าง Google Apps Script

1. ไปที่ [Google Apps Script](https://script.google.com)
2. คลิก "โครงการใหม่"
3. ตั้งชื่อโครงการ (เช่น "EA API")
4. ลบโค้ดเริ่มต้นทั้งหมด
5. คัดลอกโค้ดจากส่วน [โค้ด Google Apps Script (ฉบับเต็ม)](#โค้ด-google-apps-script-ฉบับเต็ม) ไปวาง
6. กด **Ctrl+S** (หรือ Cmd+S) เพื่อบันทึก

---

## ขั้นตอนที่ 3: กำหนดค่า Configuration

แก้ไขบรรทัดต้นๆ ของโค้ด:

```javascript
const SHEET_ID = 'ใส่_SHEET_ID_ของคุณ';     // Sheet ID จากขั้นตอนที่ 1.3
const USE_SCRAPER_API = true;                 // เปิดใช้ ScraperAPI
const SCRAPER_API_KEY = 'ใส่_API_KEY_ของคุณ'; // API key จาก scraperapi.com
```

**วิธีหา ScraperAPI Key:**
1. สมัครที่ https://www.scraperapi.com/signup (Free tier: 1,000 requests/เดือน)
2. Login แล้วไปที่ Dashboard
3. คัดลอก API Key

**Fast Polling (สำหรับไม่ใช้ Web Scraping):**

```javascript
const POLL_INTERVAL_SECONDS = 30;       // ตัวเลือก: 5, 15, 30, 60 วินาที
const WEB_SCRAPE_INTERVAL_MINUTES = 30; // Fallback web scraping ทุกกี่นาที
```

| ค่า | ความถี่ | คำอธิบาย |
|-----|---------|----------|
| `5` | ทุก 5 วินาที | รับ signal เร็วมาก (ใช้ quota สูง) |
| `15` | ทุก 15 วินาที | รับ signal เร็ว |
| `30` | ทุก 30 วินาที | **แนะนำ** — สมดุลระหว่างความเร็วและ quota |
| `60` | ทุก 60 วินาที | ประหยัด quota สูงสุด |

> **หมายเหตุ**: `POLL_INTERVAL_SECONDS` คือความถี่ที่ระบบตรวจสอบ signal ใน Fast Polling mode — ถ้า external sheet เปิดอยู่จะดึงตาม interval นี้ ถ้าไม่มี external signal จะ fallback ไป web scraping ตาม `WEB_SCRAPE_INTERVAL_MINUTES` (default 30 นาที)

---

## ขั้นตอนที่ 4: Deploy เป็น Web App

1. ใน Apps Script Editor คลิก **Deploy** > **New deployment**
2. เลือก type: **Web app**
3. ตั้งค่า:
   - **Execute as**: Me (อีเมลของคุณ)
   - **Who has access**: Anyone
4. คลิก **Deploy**
5. อนุญาตสิทธิ์ที่จำเป็น (กด Review permissions > เลือกบัญชี > Allow)
6. คัดลอก **Web app URL** เก็บไว้

ตัวอย่าง URL:
```
https://script.google.com/macros/s/AKfycbzXXXXXXXXXXXXXXXXXXXXXX/exec
```

> **สำคัญ**: หลังแก้ไขโค้ดทุกครั้ง ต้อง Deploy > Manage deployments > แก้ไข > เลือก Version ใหม่ > Deploy

---

## ขั้นตอนที่ 5: ทดสอบ API

เปิด URL ต่อไปนี้ในเว็บเบราว์เซอร์:

**ทดสอบ Authorization:**
```
YOUR_URL?action=auth
```
ผลลัพธ์ควรเป็น CSV:
```
account,expires_at,max_lots,open_cooldown,close_cooldown,min_version
12345678,2025.12.31,2.0,7200,300,1.16
```

**ทดสอบ Signal:**
```
YOUR_URL?action=signal
```
ผลลัพธ์ควรเป็น CSV:
```
signal,timestamp,confidence,source
BUY,2025-12-01T10:30:00Z,0.85,AUTO
```

**ทดสอบ scrapeAndUpdateSignal():**
1. ใน Apps Script Editor เลือกฟังก์ชัน `scrapeAndUpdateSignal` จาก dropdown
2. กด Run
3. ตรวจสอบ Logs (View > Logs)
4. ตรวจสอบ Signals sheet ว่าอัพเดทข้อมูลแล้ว

---

## ขั้นตอนที่ 6: ตั้งค่า Auto Scraping / Fast Polling

เลือกโหมดการทำงานตามแหล่งที่มาของ signal:

### 6.1 โหมด A: Web Scraping (ดึงจาก TradersUnion)

Scrape signal จาก tradersunion.com ทุก 30 นาที:

1. ใน Apps Script Editor เลือกฟังก์ชัน `createScheduledSignalTriggers`
2. กด Run
3. ตรวจสอบใน Apps Script > Triggers ว่า trigger ถูกสร้างแล้ว

**การทำงาน:**
- **01:00-20:00 UTC**: Scrape จาก TradersUnion (หรือใช้ signal จากชีทนอกถ้าเปิดไว้)
- **20:00-01:00 UTC**: บังคับ signal เป็น SELL (ช่วงตลาดปิด)

### 6.2 โหมด B: Fast Polling (รองรับทั้ง External Sheet และ Web Scraping Fallback)

ระบบ poll ถี่ขึ้นได้ตั้งแต่ **5 วินาที ถึง 60 วินาที** โดยทำงานแบบ dynamic:

- ถ้า **external sheet เปิด** (`ext_override = TRUE`) → ดึง signal จากชีทภายนอกตาม interval ที่ตั้ง (เร็ว)
- ถ้า **external sheet ปิด** หรือไม่มี signal → fallback ไป **web scraping ทุก 30 นาที** (ตาม `WEB_SCRAPE_INTERVAL_MINUTES`)
- สามารถ **สลับ `ext_override` ได้ตลอดเวลา** โดยไม่ต้องเปลี่ยน trigger

**ขั้นตอน:**

1. ตั้งค่า `POLL_INTERVAL_SECONDS` ในโค้ด (ค่าเริ่มต้น: `30`)
2. ใน Apps Script Editor เลือกฟังก์ชัน `createFastSignalTriggers`
3. กด Run
4. ตรวจสอบใน Apps Script > Triggers ว่า trigger ถูกสร้างแล้ว

**การทำงานของแต่ละ poll iteration:**

```
fastPollSignal()
  ├── Blocked period (20:00-01:00 UTC)?
  │     └── YES → บังคับ SELL
  └── NO → ลอง external sheet ก่อน
        ├── ext signal สำเร็จ → ใช้ EXTERNAL
        └── ไม่มี ext signal → เช็คว่าถึงรอบ web scrape (30 นาที) หรือยัง
              ├── ถึงรอบ → scrapeFromWeb() + บันทึกเวลา
              └── ยังไม่ถึง → ข้ามไป (signal ค้างค่าเดิม)
```

> ⚠️ Fast Polling ใช้ `Utilities.sleep()` ภายใน trigger ซึ่งนับรวมใน daily execution quota ของ Google Apps Script

### 6.3 Google Apps Script Quota & Limits

| รายการ | Consumer (ฟรี) | Google Workspace |
|--------|---------------|-----------------|
| Execution time / ครั้ง | 6 นาที | 6 นาที |
| Total trigger runtime / วัน | 90 นาที | 6 ชั่วโมง |
| Triggers / user / script | 20 | 20 |
| UrlFetch calls / วัน | 20,000 | 100,000 |

**ประมาณการใช้ quota ต่อวัน (ช่วงตลาดเปิด ~19 ชั่วโมง):**

| Interval | Polls/นาที | Exec time/trigger | ทำงานได้ (Consumer) | ทำงานได้ (Workspace) |
|----------|-----------|-------------------|--------------------|--------------------|
| 60 วินาที | 1 | ~2 วินาที | ✅ ตลอดวัน | ✅ ตลอดวัน |
| 30 วินาที | 2 | ~32 วินาที | ⚠️ ~2.8 ชั่วโมง | ⚠️ ~11.2 ชั่วโมง |
| 15 วินาที | ~4 | ~49 วินาที | ❌ ~1.8 ชั่วโมง | ⚠️ ~7.3 ชั่วโมง |
| 5 วินาที | ~10 | ~55 วินาที | ❌ ~1.6 ชั่วโมง | ❌ ~6.5 ชั่วโมง |

> - ✅ = ใช้งานได้ตลอดทั้งวันโดยไม่ติด limit
> - ⚠️ = ใช้ได้แต่จำกัดเวลา (ระบบจะหยุดทำงานเมื่อ quota หมด)
> - ❌ = ใช้ได้น้อยมาก ไม่แนะนำ

**คำแนะนำ:**
- **Consumer account**: ใช้ `60` วินาทีเพื่อความปลอดภัย หรือ `30` วินาทีถ้ายอมรับได้ว่าจะทำงานได้ ~2.8 ชั่วโมง/วัน
- **Google Workspace**: ใช้ `30` วินาที (ครอบคลุม ~11.2 ชั่วโมง) หรือ `60` วินาที (ไม่ติด limit)

### 6.4 สลับโหมด / ปิด Trigger

- **สลับจาก A → B**: รัน `createFastSignalTriggers()` (จะลบ trigger เดิมอัตโนมัติ)
- **สลับจาก B → A**: รัน `createScheduledSignalTriggers()` (จะลบ trigger เดิมอัตโนมัติ)
- **ปิดทั้งหมด**: รัน `deleteAllSignalTriggers()` หรือลบ trigger ใน Apps Script > Triggers

---

## ขั้นตอนที่ 7: ตั้งค่า External Signal Proxy

ฟีเจอร์นี้ช่วยให้ผู้เชี่ยวชาญภายนอกสามารถส่ง signal เข้ามา override สัญญาณอัตโนมัติได้

### 7.1 สร้างชีทภายนอก (ฝั่งผู้เชี่ยวชาญ)

1. สร้าง Google Sheet ใหม่
2. ตั้งชื่อ Sheet แรกเป็น **`Signals`**
3. กรอกข้อมูลดังนี้:

| A | B | C | D |
|---|---|---|---|
| signal | timestamp | confidence | active |
| SELL | 2025-12-01T11:00:00Z | 0.92 | TRUE |

**คำอธิบายคอลัมน์:**

| คอลัมน์ | ชื่อ | คำอธิบาย | ค่าที่รองรับ |
|---------|------|----------|-------------|
| A | signal | สัญญาณเทรด | `BUY` หรือ `SELL` |
| B | timestamp | เวลาอัพเดท (ไม่บังคับ) | ISO 8601 format |
| C | confidence | ค่าความมั่นใจ (ไม่บังคับ) | 0.0 - 1.0 |
| D | active | สวิตช์เปิด/ปิดส่ง signal | `TRUE` หรือ `FALSE` |

4. **แชร์ชีทนี้** ให้กับบัญชี Google ของเจ้าของ Apps Script หลัก (อย่างน้อยสิทธิ์ "ผู้ดู")

### 7.2 เปิดใช้งานในชีทหลัก

1. เปิด Google Sheet หลัก > ไปที่ Sheet `Signals`
2. คอลัมน์ E แถวที่ 2 (`ext_override`): เปลี่ยนเป็น **`TRUE`**
3. คอลัมน์ F แถวที่ 2 (`ext_sheet_id`): วาง Sheet ID หรือ URL ของชีทภายนอก

ตัวอย่าง:
```
ext_override = TRUE
ext_sheet_id = 1AbC2dEfG3hIjKlMnOpQrStUvWxYz
```

หรือวาง URL เต็มก็ได้:
```
ext_sheet_id = https://docs.google.com/spreadsheets/d/1AbC2dEfG3hIjK.../edit
```

### 7.3 วิธีใช้งานสำหรับผู้เชี่ยวชาญ

- **เริ่มส่ง signal**: ตั้ง `active` = `TRUE` แล้วกรอก `signal` เป็น `BUY` หรือ `SELL`
- **เปลี่ยน signal**: แก้ไขคอลัมน์ A ได้ตลอดเวลา
- **หยุดส่ง signal**: ตั้ง `active` = `FALSE` (ระบบจะ fallback ไปใช้ auto-scrape ทันที)

### 7.4 การทำงานของ Fallback

| สถานะ | ผลลัพธ์ |
|--------|---------|
| `ext_override` = FALSE | ใช้ AUTO เสมอ (scrape จากเว็บ) |
| `ext_override` = TRUE + ชีทนอก `active` = TRUE + signal ถูกต้อง | ใช้ EXTERNAL |
| `ext_override` = TRUE + ชีทนอก `active` = FALSE | Fallback ไป AUTO |
| `ext_override` = TRUE + ชีทนอกมีปัญหา (สิทธิ์/เครือข่าย/ข้อมูลผิด) | Fallback ไป AUTO |
| `ext_override` = TRUE + `ext_sheet_id` ว่าง | Fallback ไป AUTO |

### 7.5 ดูแหล่งที่มาของ Signal

ดูคอลัมน์ D (`source`) ในชีทหลัก:
- **`AUTO`** = signal มาจากการ scrape อัตโนมัติ
- **`EXTERNAL`** = signal มาจากชีทภายนอก (ผู้เชี่ยวชาญ)

### 7.6 ปิด External Signal Proxy

เปลี่ยนคอลัมน์ E แถวที่ 2 (`ext_override`) เป็น **`FALSE`** ในชีทหลัก

---

## ขั้นตอนที่ 8: ตั้งค่า MT4/MT5

### 8.1 เพิ่ม URL ในรายการที่อนุญาต

ไปที่ **Tools > Options > Expert Advisors > Allow WebRequest** แล้วเพิ่ม:
```
https://script.google.com
https://script.googleusercontent.com
```

### 8.2 ตั้งค่า EA Input

```
input_api_enabled = true
input_api_auth_enabled = true
input_api_auth_url = "YOUR_URL?action=auth"
input_api_signal_enabled = true
input_api_signal_url = "YOUR_URL?action=signal"
```

แทนที่ `YOUR_URL` ด้วย Web app URL จากขั้นตอนที่ 4

---

## โค้ด Google Apps Script (ฉบับเต็ม)

คัดลอกโค้ดด้านล่างทั้งหมดไปวางใน Google Apps Script Editor:

```javascript
// ========================================
// Configuration
// ========================================
const SHEET_ID = 'YOUR_GOOGLE_SHEET_ID_HERE';
const AUTH_SHEET_NAME = 'Authorization';
const SIGNAL_SHEET_NAME = 'Signals';
const EXTERNAL_SIGNAL_SHEET_NAME = 'Signals';

// ScraperAPI Configuration (required for bypassing Cloudflare)
// Sign up at: https://www.scraperapi.com (Free: 1000 requests/month)
const USE_SCRAPER_API = true;   // Set to true to enable ScraperAPI
const SCRAPER_API_KEY = '';     // Your ScraperAPI key

// Fast Polling Configuration
// Options: 5, 15, 30, 60 (seconds)
const POLL_INTERVAL_SECONDS = 60;
const WEB_SCRAPE_INTERVAL_MINUTES = 30;

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
    
    // Return only columns A-D (signal, timestamp, confidence, source)
    // Exclude config columns E-F (ext_override, ext_sheet_id)
    const maxCols = Math.min(data[0].length, 4);
    let csvContent = data[0].slice(0, maxCols).join(',') + '\n';
    csvContent += data[1].slice(0, maxCols).join(',') + '\n';
    
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
// Extract Sheet ID from URL or raw ID
// ========================================
function extractSheetIdFromUrl(input) {
  if (!input || input.toString().trim() === '') {
    return null;
  }
  
  const str = input.toString().trim();
  
  const match = str.match(/\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
  if (match && match[1]) {
    return match[1];
  }
  
  if (!str.includes('/')) {
    return str;
  }
  
  return null;
}

// ========================================
// Read External Override Config from Main Sheet
// ========================================
function getExternalOverrideConfig() {
  try {
    const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(SIGNAL_SHEET_NAME);
    if (!sheet) return { enabled: false };
    
    const extOverride = sheet.getRange(2, 5).getValue();
    const extSheetRaw = sheet.getRange(2, 6).getValue();
    
    return {
      enabled: (extOverride === true || extOverride.toString().toUpperCase() === 'TRUE'),
      sheetId: extractSheetIdFromUrl(extSheetRaw)
    };
  } catch (error) {
    Logger.log('[EXT] Failed to read config: ' + error.toString());
    return { enabled: false };
  }
}

// ========================================
// Fetch Signal from External Google Sheet
// ========================================
function fetchExternalSignal() {
  try {
    const config = getExternalOverrideConfig();
    
    if (!config.enabled) {
      Logger.log('[EXT] External override is disabled');
      return null;
    }
    
    if (!config.sheetId) {
      Logger.log('[EXT] External sheet ID is empty or invalid');
      return null;
    }
    
    Logger.log('[EXT] Fetching from external sheet: ' + config.sheetId);
    
    const extSpreadsheet = SpreadsheetApp.openById(config.sheetId);
    const extSheet = extSpreadsheet.getSheetByName(EXTERNAL_SIGNAL_SHEET_NAME);
    
    if (!extSheet) {
      Logger.log('[EXT] Sheet "' + EXTERNAL_SIGNAL_SHEET_NAME + '" not found');
      return null;
    }
    
    const data = extSheet.getDataRange().getValues();
    
    if (data.length < 2) {
      Logger.log('[EXT] No data rows in external sheet');
      return null;
    }
    
    const row = data[1];
    const signal = row[0] ? row[0].toString().trim().toUpperCase() : '';
    const timestamp = row[1] ? row[1].toString().trim() : new Date().toISOString();
    const confidence = row[2] ? parseFloat(row[2]) : 1.0;
    const active = row[3];
    
    const isActive = (active === true || (active && active.toString().toUpperCase() === 'TRUE'));
    
    if (!isActive) {
      Logger.log('[EXT] Expert is offline (active = FALSE)');
      return null;
    }
    
    if (signal !== 'BUY' && signal !== 'SELL') {
      Logger.log('[EXT] Invalid signal: "' + signal + '"');
      return null;
    }
    
    Logger.log('[EXT] Signal: ' + signal + ' (confidence: ' + confidence + ')');
    
    return {
      signal: signal,
      timestamp: timestamp,
      confidence: isNaN(confidence) ? 1.0 : confidence
    };
    
  } catch (error) {
    Logger.log('[EXT] Error: ' + error.toString());
    return null;
  }
}

// ========================================
// Update Signal (Manual/Programmatic)
// ========================================
function updateSignal(signal, confidence, source) {
  try {
    if (signal !== 'BUY' && signal !== 'SELL') {
      throw new Error('Invalid signal: ' + signal);
    }
    
    const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(SIGNAL_SHEET_NAME);
    const timestamp = new Date().toISOString();
    
    sheet.getRange(2, 1).setValue(signal);
    sheet.getRange(2, 2).setValue(timestamp);
    sheet.getRange(2, 3).setValue(confidence || 1.0);
    sheet.getRange(2, 4).setValue(source || 'AUTO');
    
    Logger.log('Signal updated: ' + signal + ' (source: ' + (source || 'AUTO') + ')');
    return true;
    
  } catch (error) {
    Logger.log('Update signal error: ' + error.toString());
    return false;
  }
}

// ========================================
// Web Scraping (extracted for reuse)
// ========================================
function scrapeFromWeb() {
  try {
    const targetUrl = 'https://tradersunion.com/currencies/forecast/gold/signals/';
    let url = targetUrl;
    let fetchOptions = {
      method: 'GET',
      muteHttpExceptions: true,
      followRedirects: true
    };
    
    if (USE_SCRAPER_API) {
      if (!SCRAPER_API_KEY || SCRAPER_API_KEY === '') {
        Logger.log('ERROR: ScraperAPI enabled but API key is missing!');
        return false;
      }
      
      url = 'https://api.scraperapi.com/?api_key=' + SCRAPER_API_KEY + 
            '&url=' + encodeURIComponent(targetUrl) +
            '&render=false';
      
      Logger.log('Using ScraperAPI to bypass Cloudflare...');
    } else {
      fetchOptions.headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9'
      };
      
      Logger.log('Fetching directly (no ScraperAPI)...');
    }
    
    const response = UrlFetchApp.fetch(url, fetchOptions);
    const statusCode = response.getResponseCode();
    
    if (statusCode !== 200) {
      Logger.log('HTTP Error: ' + statusCode);
      
      if (statusCode === 403 && !USE_SCRAPER_API) {
        Logger.log('Blocked by Cloudflare! Consider enabling ScraperAPI.');
      }
      
      return false;
    }
    
    const html = response.getContentText();
    
    if (html.includes('Attention Required') && html.includes('Cloudflare')) {
      Logger.log('Cloudflare challenge detected!');
      return false;
    }
    
    const signal = parseSignalFromHTML(html);
    
    if (!signal) {
      Logger.log('Failed to parse signal from webpage');
      return false;
    }
    
    const confidence = 0.85;
    updateSignal(signal, confidence, 'AUTO');
    
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
// Auto-update with External Signal Proxy
// ========================================
function scrapeAndUpdateSignal() {
  try {
    const extSignal = fetchExternalSignal();
    
    if (extSignal) {
      const success = updateSignal(extSignal.signal, extSignal.confidence, 'EXTERNAL');
      if (success) {
        Logger.log('[EXT] Signal overridden: ' + extSignal.signal);
      }
      return success;
    }
    
    Logger.log('[AUTO] Fallback to auto-scrape');
    
    if (isInBlockedPeriod()) {
      Logger.log('Currently in blocked period (20:00-01:00 UTC)');
      const success = updateSignal('SELL', 1.0, 'AUTO');
      if (success) {
        Logger.log('Signal forced to SELL successfully');
      }
      return success;
    }
    
    const success = scrapeFromWeb();
    if (success) {
      PropertiesService.getScriptProperties().setProperty('last_web_scrape_ms', Date.now().toString());
    }
    return success;
    
  } catch (error) {
    Logger.log('Scrape error: ' + error.toString());
    return false;
  }
}

// ========================================
// Fast Poll Signal (with Web Scraping Fallback)
// ========================================
function fastPollSignal() {
  const intervalMs = POLL_INTERVAL_SECONDS * 1000;
  const startTime = Date.now();
  const maxDurationMs = 55000;
  let iteration = 0;

  while (true) {
    iteration++;

    try {
      if (isInBlockedPeriod()) {
        updateSignal('SELL', 1.0, 'AUTO');
        Logger.log('[FAST #' + iteration + '] Blocked period - forced SELL');
      } else {
        const extSignal = fetchExternalSignal();
        if (extSignal) {
          updateSignal(extSignal.signal, extSignal.confidence, 'EXTERNAL');
          Logger.log('[FAST #' + iteration + '] Signal: ' + extSignal.signal);
        } else {
          const props = PropertiesService.getScriptProperties();
          const lastScrape = parseInt(props.getProperty('last_web_scrape_ms') || '0');
          const scrapeIntervalMs = WEB_SCRAPE_INTERVAL_MINUTES * 60 * 1000;
          const elapsed = Date.now() - lastScrape;

          if (elapsed >= scrapeIntervalMs) {
            Logger.log('[FAST #' + iteration + '] Fallback: web scraping (last scrape ' + Math.round(elapsed / 60000) + ' min ago)');
            if (scrapeFromWeb()) {
              props.setProperty('last_web_scrape_ms', Date.now().toString());
            }
          } else {
            Logger.log('[FAST #' + iteration + '] No ext signal, web scrape in ' + Math.round((scrapeIntervalMs - elapsed) / 60000) + ' min');
          }
        }
      }
    } catch (error) {
      Logger.log('[FAST #' + iteration + '] Error: ' + error.toString());
    }

    if (POLL_INTERVAL_SECONDS >= 60) {
      break;
    }

    const elapsedLoop = Date.now() - startTime;
    if (elapsedLoop + intervalMs >= maxDurationMs) {
      break;
    }

    Utilities.sleep(intervalMs);
  }

  Logger.log('[FAST] Completed ' + iteration + ' iteration(s)');
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
// Scheduled Signal Control (Market Close)
// ========================================

function isInBlockedPeriod() {
  const now = new Date();
  const utcHour = now.getUTCHours();
  
  if (utcHour >= 20 || utcHour < 1) {
    return true;
  }
  
  return false;
}

function createScheduledSignalTriggers() {
  deleteAllSignalTriggers();
  
  ScriptApp.newTrigger('scrapeAndUpdateSignal')
    .timeBased()
    .everyMinutes(30)
    .create();
  
  Logger.log('=== Scheduled Triggers (Web Scraping Mode) ===');
  Logger.log('Trigger: every 30 minutes');
  Logger.log('01:00-20:00 UTC: Scrape/External every 30 min');
  Logger.log('20:00-01:00 UTC: Force SELL every 30 min');
}

// ========================================
// Fast Signal Trigger Management
// ========================================
function createFastSignalTriggers() {
  deleteAllSignalTriggers();
  
  ScriptApp.newTrigger('fastPollSignal')
    .timeBased()
    .everyMinutes(1)
    .create();
  
  const pollsPerMin = POLL_INTERVAL_SECONDS >= 60 ? 1 : Math.floor(55 / POLL_INTERVAL_SECONDS);
  Logger.log('=== Fast Signal Triggers Created ===');
  Logger.log('Base trigger: every 1 minute');
  Logger.log('Poll interval: ' + POLL_INTERVAL_SECONDS + ' seconds');
  Logger.log('Polls per trigger: ~' + pollsPerMin);
  Logger.log('Source: External Sheet (fast) + Web Scraping fallback (every ' + WEB_SCRAPE_INTERVAL_MINUTES + ' min)');
}

function deleteAllSignalTriggers() {
  const triggers = ScriptApp.getProjectTriggers();
  let deletedCount = 0;
  
  for (let i = 0; i < triggers.length; i++) {
    const handler = triggers[i].getHandlerFunction();
    if (handler === 'scrapeAndUpdateSignal' ||
        handler === 'fastPollSignal') {
      ScriptApp.deleteTrigger(triggers[i]);
      deletedCount++;
    }
  }
  
  Logger.log('Deleted ' + deletedCount + ' signal trigger(s)');
}
```

---

## การแก้ปัญหา

### ปัญหาทั่วไป

| ปัญหา | สาเหตุ | วิธีแก้ |
|--------|--------|---------|
| `WebRequest failed` | URL ไม่อยู่ในรายการที่อนุญาต | เพิ่ม `https://script.google.com` และ `https://script.googleusercontent.com` ใน MT4/MT5 |
| `Account not found` | หมายเลขบัญชีไม่ตรง | ตรวจสอบบัญชีใน Sheet Authorization |
| `HTTP error: 403` | Deploy ผิดหรือสิทธิ์ไม่ถูก | Deploy ใหม่โดยตั้ง "Who has access" เป็น "Anyone" |
| `Signal sheet not found` | ชื่อ Sheet ไม่ตรง | ตรวจสอบว่าชื่อ Sheet เป็น `Signals` (ตัว S ใหญ่) |
| `Cloudflare challenge` | เว็บ block request | เปิดใช้ ScraperAPI: `USE_SCRAPER_API = true` |
| `ScraperAPI key missing` | ลืมใส่ API key | ใส่ key ใน `SCRAPER_API_KEY` |

### ปัญหา External Signal Proxy

| ปัญหา | สาเหตุ | วิธีแก้ |
|--------|--------|---------|
| ไม่ดึง signal จากชีทนอก | `ext_override` เป็น FALSE | เปลี่ยนเป็น TRUE ในคอลัมน์ E |
| `External sheet ID is empty` | ไม่ได้ใส่ Sheet ID | ใส่ Sheet ID หรือ URL ในคอลัมน์ F |
| `Expert is offline` | ผู้เชี่ยวชาญตั้ง active = FALSE | ผู้เชี่ยวชาญต้องเปลี่ยน active เป็น TRUE |
| `Sheet not found` ในชีทนอก | ชื่อ Sheet ไม่ตรง | ชีทภายนอกต้องมี Sheet ชื่อ `Signals` |
| ไม่มีสิทธิ์เข้าถึงชีทนอก | ไม่ได้แชร์ชีท | ผู้เชี่ยวชาญต้องแชร์ชีทให้กับบัญชี Google ของเจ้าของ script |
| source ยังเป็น AUTO ทั้งที่เปิดชีทนอกแล้ว | ชีทนอกมีปัญหา | ตรวจ Logs ใน Apps Script (View > Logs) หา `[EXT]` messages |

### ปัญหา Fast Polling

| ปัญหา | สาเหตุ | วิธีแก้ |
|--------|--------|---------|
| Trigger หยุดทำงานกลางวัน | Daily execution quota หมด | เพิ่ม `POLL_INTERVAL_SECONDS` เป็น 60 หรือใช้ Google Workspace |
| Signal อัพเดทช้ากว่าที่ตั้ง | `Utilities.sleep()` + execution time overhead | ปกติ — จะมี overhead เล็กน้อยต่อรอบ |
| `fastPollSignal` ไม่ทำงาน | ยังไม่ได้สร้าง trigger | รัน `createFastSignalTriggers()` |
| ยังคง scrape จากเว็บ | ใช้ trigger ผิดโหมด | รัน `createFastSignalTriggers()` แทน `createScheduledSignalTriggers()` |
| ต้องการกลับไปใช้ Web Scraping | เปลี่ยนโหมด | รัน `createScheduledSignalTriggers()` |

### วิธีตรวจสอบ Logs

1. เปิด Apps Script Editor
2. เลือกฟังก์ชัน `scrapeAndUpdateSignal` แล้วกด Run
3. ไปที่ **View > Logs** (หรือ Ctrl+Enter)
4. ดู log messages:
   - `[FAST]` = เกี่ยวกับ Fast Polling mode
   - `[EXT]` = เกี่ยวกับ External Signal Proxy
   - `[AUTO]` = เกี่ยวกับ auto-scrape
   - error messages จะบอกสาเหตุของปัญหา

---

## เอกสารที่เกี่ยวข้อง

- [Google-Sheets-Authorization-Setup.md](Google-Sheets-Authorization-Setup.md) - คู่มือตั้งค่า Google Sheets สำหรับระบบอนุญาตบัญชี
- [documents/API-Signal-Integration-Guide.md](documents/API-Signal-Integration-Guide.md) - คู่มือ API Signal Integration ฉบับละเอียด

---

*Document Version: 1.6*
*Last Updated: March 2026*
