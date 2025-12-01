# 📋 API Signal Integration - Implementation Plan

## 🎯 Overview

เอกสารนี้สรุปขั้นตอนการพัฒนาระบบดึงสัญญาณเทรดอัตโนมัติผ่าน API สำหรับ EA FXH-Diff-Grabber

**⚠️ Breaking Changes**: 
- EA เวอร์ชันเก่าจะใช้งานไม่ได้หลังจาก deploy API ใหม่
- ต้องอัพเดท EA ทุกตัวเป็นเวอร์ชันใหม่

---

## 📝 Part 1: MQL4 Code Changes

### 1.1 Input Parameters (เพิ่มใหม่)

**ตำแหน่ง**: หลังบรรทัด 150 (หลัง Force Close config)

```mql4
// ========================================
// API System Configuration
// ========================================

// Master API Switch
input bool   input_api_enabled = false;                  // Scope: Both — Enable/Disable ALL API features

// Authorization API
input bool   input_api_auth_enabled = true;              // Scope: Both — Enable account authorization via API
input string input_api_auth_url = "";                    // Scope: Both — Authorization API endpoint URL
input int    input_api_auth_interval_hours = 24;         // Scope: Both — Authorization check interval (hours)

// Signal API (Master only)
input bool   input_api_signal_enabled = false;           // Scope: Master — Enable signal fetching via API
input string input_api_signal_url = "";                  // Scope: Master — Signal API endpoint URL
input int    input_api_signal_interval_hours = 1;        // Scope: Master — Signal fetch interval (hours)
input bool   input_api_signal_auto_apply = true;         // Scope: Master — Auto-apply signal to master_side
input double input_api_signal_min_confidence = 0.0;      // Scope: Master — Minimum confidence to apply signal (0.0-1.0)
```

**ลบออก**:
```mql4
// ลบบรรทัดเหล่านี้ (บรรทัด 152-153 เดิม)
string input_auth_sheet_url = "...";
bool   input_auth_enabled = true;
```

---

### 1.2 Global Variables (เพิ่มใหม่)

**ตำแหน่ง**: หลังบรรทัด ~300 (หลัง Account Authorization globals)

```mql4
// ========================================
// API System Globals
// ========================================

// Authorization state
datetime g_api_auth_last_check_time = 0;
bool g_api_auth_valid = false;
datetime g_api_auth_expires = 0;
double g_api_auth_max_lots = 0.0;
string g_api_auth_error = "";

// Signal state
datetime g_api_signal_last_fetch_time = 0;
string g_api_signal_current = "";                        // "BUY" or "SELL"
datetime g_api_signal_timestamp = 0;
double g_api_signal_confidence = 0.0;
bool g_api_signal_valid = false;
string g_api_signal_error = "";

// Signal change tracking
MasterSide g_api_signal_pending_side = SIDE_BUY;
bool g_api_signal_pending_change = false;
```

**ลบออก**:
```mql4
// ลบตัวแปรเก่าที่เกี่ยวกับ auth (ถ้ามี)
// ค้นหาและลบ: g_auth_error_message, g_auth_last_check_time (ถ้าแยกกับของใหม่)
```

---

### 1.3 New Functions (สร้างใหม่)

**ตำแหน่ง**: สร้าง section ใหม่หลังฟังก์ชัน authorization เดิม

#### **1.3.1 API Control Functions**

```mql4
//+------------------------------------------------------------------+
//| API System Control Functions                                      |
//+------------------------------------------------------------------+

// Check if API system is enabled
bool IsAPIEnabled()
{
   return input_api_enabled;
}

// Check if authorization API is enabled
bool IsAuthAPIEnabled()
{
   return IsAPIEnabled() && input_api_auth_enabled;
}

// Check if signal API is enabled
bool IsSignalAPIEnabled()
{
   return IsAPIEnabled() && input_api_signal_enabled && (input_role == ROLE_MASTER);
}
```

#### **1.3.2 Authorization Functions (อัพเดท)**

```mql4
//+------------------------------------------------------------------+
//| Authorization API Functions                                       |
//+------------------------------------------------------------------+

// Check if authorization check is needed
bool NeedAuthorizationCheck()
{
   if (!IsAuthAPIEnabled())
      return false;
   
   datetime now = TimeCurrent();
   int hours_since_last = (int)((now - g_api_auth_last_check_time) / 3600);
   
   return (hours_since_last >= input_api_auth_interval_hours) || !g_api_auth_valid;
}

// Perform authorization check via API
bool CheckAccountAuthorization()
{
   if (!IsAuthAPIEnabled())
      return true; // Skip if disabled
   
   if (!NeedAuthorizationCheck())
      return g_api_auth_valid; // Use cached result
   
   string url = input_api_auth_url;
   
   if (StringLen(url) == 0)
   {
      Print("[API-AUTH] Error: No authorization URL configured");
      return false;
   }
   
   string response;
   if (!HttpGetRequest(url, response))
   {
      g_api_auth_error = "HTTP request failed";
      Print("[API-AUTH] ", g_api_auth_error);
      return false;
   }
   
   datetime expires;
   double max_lots;
   
   if (!ParseAuthorizationData(response, AccountNumber(), expires, max_lots))
   {
      g_api_auth_error = "Account not authorized or expired";
      g_api_auth_valid = false;
      Print("[API-AUTH] ", g_api_auth_error);
      return false;
   }
   
   g_api_auth_last_check_time = TimeCurrent();
   g_api_auth_expires = expires;
   g_api_auth_max_lots = max_lots;
   g_api_auth_valid = true;
   g_api_auth_error = "";
   
   if (input_verbose_journal_logs)
      Print("[API-AUTH] Account authorized (expires: ", TimeToString(expires, TIME_DATE), 
            ", max_lots: ", DoubleToString(max_lots, 2), ")");
   
   return true;
}
```

**หมายเหตุ**: ฟังก์ชัน `HttpGetRequest()` และ `ParseAuthorizationData()` ที่มีอยู่แล้วสามารถใช้ต่อได้

#### **1.3.3 Signal Functions (สร้างใหม่)**

```mql4
//+------------------------------------------------------------------+
//| Signal API Functions                                              |
//+------------------------------------------------------------------+

// Check if signal fetch is needed
bool NeedSignalFetch()
{
   if (!IsSignalAPIEnabled())
      return false;
   
   datetime now = TimeCurrent();
   int hours_since_last = (int)((now - g_api_signal_last_fetch_time) / 3600);
   
   return (hours_since_last >= input_api_signal_interval_hours) || !g_api_signal_valid;
}

// Fetch trading signal from API
bool FetchTradingSignal()
{
   if (!IsSignalAPIEnabled())
      return true;
   
   if (!NeedSignalFetch())
      return g_api_signal_valid;
   
   string url = input_api_signal_url;
   
   if (StringLen(url) == 0)
   {
      Print("[API-SIGNAL] Error: No signal URL configured");
      return false;
   }
   
   string response;
   if (!HttpGetRequest(url, response))
   {
      g_api_signal_error = "HTTP request failed";
      Print("[API-SIGNAL] ", g_api_signal_error);
      return false;
   }
   
   if (!ParseSignalData(response))
   {
      g_api_signal_error = "Failed to parse signal data";
      Print("[API-SIGNAL] ", g_api_signal_error);
      return false;
   }
   
   if (g_api_signal_confidence < input_api_signal_min_confidence)
   {
      if (input_verbose_journal_logs)
         Print("[API-SIGNAL] Signal confidence too low: ", 
               DoubleToString(g_api_signal_confidence, 2), 
               " < ", DoubleToString(input_api_signal_min_confidence, 2));
      return false;
   }
   
   g_api_signal_last_fetch_time = TimeCurrent();
   g_api_signal_valid = true;
   g_api_signal_error = "";
   
   if (input_verbose_journal_logs)
      Print("[API-SIGNAL] Fetched signal: ", g_api_signal_current, 
            " (confidence: ", DoubleToString(g_api_signal_confidence, 2), ")");
   
   return true;
}

// Parse signal CSV response
bool ParseSignalData(const string csv_data)
{
   if (StringLen(csv_data) == 0)
      return false;
   
   string lines[];
   int line_count = StringSplit(csv_data, '\n', lines);
   
   if (line_count < 2)
      return false;
   
   string fields[];
   int field_count = StringSplit(lines[1], ',', fields);
   
   if (field_count < 1)
      return false;
   
   string signal = StringTrimLeft(StringTrimRight(fields[0]));
   StringToUpper(signal);
   
   if (signal != "BUY" && signal != "SELL")
   {
      Print("[API-SIGNAL] Invalid signal value: ", signal);
      return false;
   }
   
   g_api_signal_current = signal;
   
   if (field_count > 1)
   {
      string timestamp_str = StringTrimLeft(StringTrimRight(fields[1]));
      // Parse timestamp if needed
   }
   
   if (field_count > 2)
   {
      g_api_signal_confidence = StringToDouble(fields[2]);
   }
   else
   {
      g_api_signal_confidence = 1.0;
   }
   
   return true;
}

// Apply signal to master_side with safety checks
bool ApplySignalToMasterSide()
{
   if (!IsSignalAPIEnabled() || !input_api_signal_auto_apply)
      return true;
   
   if (!g_api_signal_valid || StringLen(g_api_signal_current) == 0)
      return true;
   
   MasterSide new_side;
   if (g_api_signal_current == "BUY")
      new_side = SIDE_BUY;
   else if (g_api_signal_current == "SELL")
      new_side = SIDE_SELL;
   else
      return false;
   
   if (new_side == input_master_side)
      return true;
   
   int self_pairs = CountSelfPairs();
   if (self_pairs > 0)
   {
      g_api_signal_pending_side = new_side;
      g_api_signal_pending_change = true;
      
      if (input_verbose_journal_logs)
         Print("[API-SIGNAL] Side change pending (", g_api_signal_current, 
               ") - waiting for positions to close");
      
      return false;
   }
   
   input_master_side = new_side;
   g_api_signal_pending_change = false;
   
   if (input_verbose_journal_logs)
      Print("[API-SIGNAL] Master side changed to: ", g_api_signal_current);
   
   string event_data = "new_side=" + g_api_signal_current + 
                       ",confidence=" + DoubleToString(g_api_signal_confidence, 2);
   FileLogEvent("SIGNAL_SIDE_CHANGE", event_data);
   
   return true;
}

// Check and apply pending signal change
void CheckPendingSignalChange()
{
   if (!g_api_signal_pending_change)
      return;
   
   int self_pairs = CountSelfPairs();
   if (self_pairs > 0)
      return;
   
   input_master_side = g_api_signal_pending_side;
   g_api_signal_pending_change = false;
   
   if (input_verbose_journal_logs)
      Print("[API-SIGNAL] Applied pending side change to: ", 
            (g_api_signal_pending_side == SIDE_BUY ? "BUY" : "SELL"));
   
   string signal_str = (g_api_signal_pending_side == SIDE_BUY ? "BUY" : "SELL");
   FileLogEvent("SIGNAL_SIDE_CHANGE", "new_side=" + signal_str + ",pending=true");
}
```

---

### 1.4 OnInit() Integration

**ค้นหา**: ฟังก์ชัน `OnInit()` ที่มีอยู่

**แก้ไข**: เพิ่มโค้ดก่อน `return(INIT_SUCCEEDED);`

```mql4
int OnInit()
{
   // ... existing initialization code ...
   
   // Initialize API system
   if (IsAPIEnabled())
   {
      // Check authorization (both Master and Slave)
      if (IsAuthAPIEnabled())
      {
         if (!CheckAccountAuthorization())
         {
            Alert("Account authorization failed: ", g_api_auth_error);
            return(INIT_FAILED);
         }
      }
      
      // Fetch initial signal (Master only)
      if (IsSignalAPIEnabled())
      {
         if (!FetchTradingSignal())
         {
            Alert("Warning: Failed to fetch initial signal: ", g_api_signal_error);
            // Continue with default side
         }
         else
         {
            ApplySignalToMasterSide();
         }
      }
   }
   
   return(INIT_SUCCEEDED);
}
```

---

### 1.5 OnTick() Integration

**ค้นหา**: ฟังก์ชัน `OnTick()` ที่มีอยู่

**แก้ไข**: เพิ่มโค้ดหลังจาก role conflict check และก่อน main logic

```mql4
void OnTick()
{
   // ... existing role conflict check ...
   
   // API system updates
   if (IsAPIEnabled())
   {
      // Check authorization periodically
      if (IsAuthAPIEnabled())
      {
         CheckAccountAuthorization();
      }
      
      // Fetch signal periodically (Master only)
      if (IsSignalAPIEnabled())
      {
         if (FetchTradingSignal())
         {
            ApplySignalToMasterSide();
         }
         
         CheckPendingSignalChange();
      }
   }
   
   // ... rest of EA logic ...
}
```

---

## 📝 Part 2: Google Apps Script

### 2.1 Create New Script

1. ไปที่ https://script.google.com
2. คลิก "โครงการใหม่"
3. ตั้งชื่อ: "EA API - Auth & Signal"
4. วางโค้ดด้านล่าง

### 2.2 Apps Script Code

```javascript
// ========================================
// Configuration
// ========================================
const SHEET_ID = 'YOUR_GOOGLE_SHEET_ID_HERE';
const AUTH_SHEET_NAME = 'Authorization';
const SIGNAL_SHEET_NAME = 'Signals';

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
// Optional: Auto-update from External API
// ========================================
function scrapeAndUpdateSignal() {
  try {
    // Example: Call external signal provider
    const apiUrl = 'https://your-signal-provider.com/api/signal';
    const response = UrlFetchApp.fetch(apiUrl, {
      method: 'GET',
      headers: {
        'Authorization': 'Bearer YOUR_API_KEY'
      },
      muteHttpExceptions: true
    });
    
    if (response.getResponseCode() === 200) {
      const data = JSON.parse(response.getContentText());
      const signal = data.signal;
      const confidence = data.confidence || 0.85;
      
      updateSignal(signal, confidence);
      
      return true;
    }
    
    return false;
    
  } catch (error) {
    Logger.log('Scrape error: ' + error.toString());
    return false;
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
  
  ScriptApp.newTrigger('scrapeAndUpdateSignal')
    .timeBased()
    .everyHours(1)
    .create();
    
  Logger.log('Hourly trigger created');
}
```

### 2.3 Deploy Script

1. คลิก "Deploy" → "New deployment"
2. เลือก type: "Web app"
3. ตั้งค่า:
   - **Execute as**: Me
   - **Who has access**: Anyone
4. คลิก "Deploy"
5. คัดลอก **Web app URL**

---

## 📝 Part 3: Google Sheets Setup

### 3.1 Create New Sheet

1. ไปที่ https://sheets.google.com
2. สร้าง Google Sheet ใหม่
3. ตั้งชื่อ: "EA API Data"

### 3.2 Sheet 1: Authorization

**ชื่อ Sheet**: `Authorization`

| A | B | C |
|---|---|---|
| account | expires_at | max_lots |
| 502523729 | 2025.12.31 | 2.0 |
| 12345678 | 2026.06.30 | 1.5 |

### 3.3 Sheet 2: Signals

**ชื่อ Sheet**: `Signals`

| A | B | C |
|---|---|---|
| signal | timestamp | confidence |
| BUY | 2025-12-01T10:30:00Z | 0.85 |

**หมายเหตุ**: 
- มีแค่ 2 แถว (header + data)
- แก้ไขแถวที่ 2 เพื่ออัพเดทสัญญาณ

### 3.4 Get Sheet ID

1. เปิด Google Sheet
2. คัดลอก ID จาก URL:
   ```
   https://docs.google.com/spreadsheets/d/[SHEET_ID]/edit
   ```
3. แทนที่ `YOUR_GOOGLE_SHEET_ID_HERE` ใน Apps Script

---

## 📝 Part 4: MT4/MT5 Configuration

### 4.1 Add Allowed URLs

**MT4**: Tools → Options → Expert Advisors → Allow WebRequest

**MT5**: Tools → Options → Expert Advisors → Allow WebRequest

**เพิ่ม URLs**:
```
https://script.google.com
https://script.googleusercontent.com
```

### 4.2 EA Input Settings (ตัวอย่าง)

```
// Master API Switch
input_api_enabled = true

// Authorization
input_api_auth_enabled = true
input_api_auth_url = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec?action=auth"
input_api_auth_interval_hours = 24

// Signal (Master only)
input_api_signal_enabled = true
input_api_signal_url = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec?action=signal"
input_api_signal_interval_hours = 1
input_api_signal_auto_apply = true
input_api_signal_min_confidence = 0.5
```

---

## ✅ Part 5: Testing Checklist

### 5.1 Google Apps Script Testing

- [ ] Test auth endpoint ใน browser: `/exec?action=auth`
- [ ] Test signal endpoint ใน browser: `/exec?action=signal`
- [ ] ตรวจสอบ CSV format ถูกต้อง
- [ ] Test error cases (sheet not found, empty data)

### 5.2 EA Compilation

- [ ] Compile EA โดยไม่มี errors
- [ ] Compile EA โดยไม่มี warnings สำคัญ

### 5.3 EA Initialization Testing

- [ ] Test with `input_api_enabled = false` (ควรทำงานแบบเดิม)
- [ ] Test with `input_api_enabled = true, input_api_auth_enabled = false`
- [ ] Test with both auth and signal enabled
- [ ] Test with invalid URLs (ควรแสดง error และไม่ crash)
- [ ] Test with expired account (ควร fail initialization)
- [ ] Test with valid account (ควรผ่าน initialization)

### 5.4 Signal Functionality Testing

- [ ] Test signal fetch ครั้งแรกใน OnInit
- [ ] Test signal BUY → ควร set `input_master_side = SIDE_BUY`
- [ ] Test signal SELL → ควร set `input_master_side = SIDE_SELL`
- [ ] Test signal change with open positions (ควร pending)
- [ ] Test pending signal apply after positions close
- [ ] Test signal with low confidence (ควรไม่ apply)
- [ ] Test interval (fetch ทุก 1 ชั่วโมง)

### 5.5 Edge Cases

- [ ] Test network timeout
- [ ] Test API returns error
- [ ] Test API returns invalid CSV
- [ ] Test API returns invalid signal (not BUY/SELL)
- [ ] Test rapid signal changes

### 5.6 Logging & Monitoring

- [ ] ตรวจสอบ Experts log มี [API-AUTH] messages
- [ ] ตรวจสอบ Experts log มี [API-SIGNAL] messages
- [ ] ตรวจสอบ file log มี SIGNAL_SIDE_CHANGE events
- [ ] ตรวจสอบไม่มี excessive logging

---

## 📊 Part 6: Deployment Steps

### 6.1 Pre-Deployment

1. [ ] Backup EA เวอร์ชันเก่า
2. [ ] Backup Google Apps Script เก่า (ถ้ามี)
3. [ ] แจ้งเตือนผู้ใช้เกี่ยวกับ breaking changes
4. [ ] เตรียม rollback plan

### 6.2 Deployment

1. [ ] Deploy Google Apps Script ใหม่
2. [ ] อัพเดท Google Sheets structure
3. [ ] Test endpoints ด้วย browser
4. [ ] Compile และ test EA ใน demo account
5. [ ] Deploy EA ไปยัง production terminals

### 6.3 Post-Deployment

1. [ ] Monitor logs ใน 24 ชั่วโมงแรก
2. [ ] ตรวจสอบ authorization checks ทำงานถูกต้อง
3. [ ] ตรวจสอบ signal fetching ทำงานถูกต้อง
4. [ ] ตรวจสอบ side changes ตามสัญญาณ

---

## 🔧 Part 7: Manual Signal Update

### วิธีที่ 1: แก้ไขใน Google Sheet

1. เปิด Google Sheet
2. ไปที่ Sheet "Signals"
3. แก้ไขแถวที่ 2:
   - Column A: `BUY` หรือ `SELL`
   - Column B: timestamp (optional)
   - Column C: confidence 0.0-1.0 (optional)

### วิธีที่ 2: ใช้ Apps Script Function

1. เปิด Apps Script Editor
2. เลือกฟังก์ชัน `updateSignal`
3. แก้ไขพารามิเตอร์:
   ```javascript
   updateSignal('BUY', 0.85);
   ```
4. กด Run

### วิธีที่ 3: Schedule Auto-Update

1. เปิด Apps Script Editor
2. แก้ไขฟังก์ชัน `scrapeAndUpdateSignal()`
3. ใส่ external API URL และ API key
4. รันฟังก์ชัน `createHourlyTrigger()`
5. สัญญาณจะอัพเดทอัตโนมัติทุกชั่วโมง

---

## 📌 Part 8: Important Notes

### Breaking Changes
- ⚠️ ไม่มี backward compatibility
- ⚠️ EA เวอร์ชันเก่าต้องอัพเดทเป็นเวอร์ชันใหม่ทั้งหมด
- ⚠️ ต้องตั้งค่า input parameters ใหม่ทั้งหมด

### URLs Required
- Authorization URL: `?action=auth`
- Signal URL: `?action=signal`
- ใช้ script เดียวกัน แต่แยก action

### Interval Settings
- **Authorization**: แนะนำ 24 ชั่วโมง (check วันละครั้ง)
- **Signal**: แนะนำ 1 ชั่วโมง (ตามที่ requirement ระบุ)
- สามารถปรับได้ตามความต้องการ

### Safety Features
- ไม่เปลี่ยน side ถ้ามี positions เปิดอยู่
- รอให้ positions ปิดก่อนแล้วค่อยเปลี่ยน
- ตรวจสอบ confidence threshold
- Log ทุก action สำคัญ

---

## 📞 Support & Troubleshooting

### Common Issues

**"WebRequest failed"**
- ตรวจสอบ URLs ใน allowed list
- ตรวจสอบ internet connection

**"Account not authorized"**
- ตรวจสอบหมายเลขบัญชีใน Google Sheet
- ตรวจสอบวันหมดอายุ

**"Failed to parse signal"**
- ตรวจสอบ Signals sheet format
- ต้องมี header + data row
- Signal ต้องเป็น BUY หรือ SELL เท่านั้น

**"Signal not applied"**
- ตรวจสอบว่ามี positions เปิดอยู่หรือไม่
- ตรวจสอบ confidence threshold
- ตรวจสอบ auto_apply = true

---

**สรุป**: เอกสารนี้ครอบคลุมทุกขั้นตอนที่ต้องทำตั้งแต่แก้ไข EA, สร้าง API, setup Google Sheets, จนถึง testing และ deployment

