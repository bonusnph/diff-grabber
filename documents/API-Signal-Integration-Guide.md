# 📋 API Signal Integration - Implementation Plan

## 🎯 Overview

เอกสารนี้สรุปขั้นตอนการพัฒนาระบบดึงสัญญาณเทรดอัตโนมัติผ่าน API สำหรับ EA FXH-Diff-Grabber

**⚠️ Breaking Changes**: 
- EA เวอร์ชันเก่าจะใช้งานไม่ได้หลังจาก deploy API ใหม่
- ต้องอัพเดท EA ทุกตัวเป็นเวอร์ชันใหม่

---

## 📑 Table of Contents

### Core Implementation
- **[Part 1](#-part-1-mql4-code-changes)**: MQL4 Code Changes
  - 1.1 Input Parameters (เพิ่มใหม่)
  - 1.2 Global Variables (เพิ่มใหม่)
  - 1.3 New Functions (สร้างใหม่)
    - 1.3.1 API Control Functions
    - 1.3.2 Authorization Functions
    - 1.3.3 Signal Functions
    - 1.3.4 TP/SL Active Diff Close Functions ⭐ **NEW**
  - 1.4 OnInit() Integration
  - 1.5 OnTick() Integration
  - 1.6 MaybeClosePair() Integration ⭐ **NEW**

- **[Part 2](#-part-2-google-apps-script)**: Google Apps Script
  - 2.1 Create New Script
  - 2.2 Apps Script Code
  - 2.3 Deploy Script

- **[Part 3](#-part-3-google-sheets-setup)**: Google Sheets Setup
  - 3.1 Create New Sheet
  - 3.2 Sheet 1: Authorization
  - 3.3 Sheet 2: Signals
  - 3.4 Get Sheet ID

- **[Part 4](#-part-4-mt4mt5-configuration)**: MT4/MT5 Configuration
  - 4.1 Add Allowed URLs
  - 4.2 EA Input Settings

### Testing & Deployment
- **[Part 5](#-part-5-testing-checklist)**: Testing Checklist
  - 5.1 Google Apps Script Testing
  - 5.2 EA Compilation
  - 5.3 EA Initialization Testing
  - 5.4 Signal Functionality Testing
  - 5.5 Edge Cases
  - 5.6 Logging & Monitoring
  - 5.7 TP/SL Active Diff Close Testing ⭐ **NEW**

- **[Part 6](#-part-6-deployment-steps)**: Deployment Steps
  - 6.1 Pre-Deployment
  - 6.2 Deployment
  - 6.3 Post-Deployment

### User Guide
- **[Part 7](#-part-7-manual-signal-update)**: Manual Signal Update
- **[Part 8](#-part-8-important-notes)**: Important Notes

### TP/SL Active Diff Close Feature ⭐ **NEW**
- **[Part 9](#-part-9-tpsl-active-diff-close-feature)**: TP/SL Active Diff Close Feature
  - 9.1 Overview
  - 9.2 Use Cases
  - 9.3 Behavior Details
  - 9.4 Safety Features
  - 9.5 Configuration Examples
  - 9.6 Testing Checklist
  - 9.7 Visual Examples
  - 9.8 Important Notes
  - 9.9 Recommended Settings
  - 9.10 Flow Diagram
  - 9.11 Code Integration Summary
  - 9.12 Quick Reference Table
  - 9.13 FAQ
  - 9.14 Visual State Diagram
  - 9.15 Implementation Priority

- **[Part 10](#-part-10-real-world-scenarios--best-practices)**: Real-World Scenarios & Best Practices
  - 10.1 Scenario: High Volatility Market
  - 10.2 Scenario: Low Volatility Market
  - 10.3 Scenario: News Trading
  - 10.4 Best Practices
  - 10.5 Common Mistakes to Avoid
  - 10.6 Performance Metrics
  - 10.7 Quick Decision Matrix
  - 10.8 Logging Best Practices

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

// ========================================
// TP/SL Active Diff Close (Master only)
// ========================================
input bool   input_tp_active_diff_close_enabled = false; // Scope: Master — Enable TP for active diff close
input int    input_tp_active_diff_close_points = 50;     // Scope: Master — TP points threshold to activate diff close
input bool   input_sl_active_diff_close_enabled = false; // Scope: Master — Enable SL for active diff close
input int    input_sl_active_diff_close_points = 30;     // Scope: Master — SL points threshold to activate diff close
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

// Authorization state (includes per-account config)
datetime g_api_auth_last_check_time = 0;
bool g_api_auth_valid = false;
datetime g_api_auth_expires = 0;
double g_api_auth_max_lots = 0.0;
int g_api_auth_open_cooldown = 0;     // Per-account cooldown (0 = use input default)
int g_api_auth_close_cooldown = 0;    // Per-account cooldown (0 = use input default)
string g_api_auth_min_version = "";   // Per-account min version (empty = no lock)
bool g_api_version_blocked = false;   // true if EA version is below minimum
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

// ========================================
// TP/SL Active Diff Close State
// ========================================
bool g_diff_close_blocked_by_tp = false;
bool g_diff_close_blocked_by_sl = false;
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

// Perform authorization check via API (includes per-account config)
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
   int open_cooldown, close_cooldown;
   string min_version;
   
   if (!ParseAuthorizationData(response, AccountNumber(), expires, max_lots, 
                               open_cooldown, close_cooldown, min_version))
   {
      g_api_auth_error = "Account not authorized or expired";
      g_api_auth_valid = false;
      Print("[API-AUTH] ", g_api_auth_error);
      return false;
   }
   
   // Store all auth data including per-account config
   g_api_auth_last_check_time = TimeCurrent();
   g_api_auth_expires = expires;
   g_api_auth_max_lots = max_lots;
   g_api_auth_open_cooldown = open_cooldown;
   g_api_auth_close_cooldown = close_cooldown;
   g_api_auth_min_version = min_version;
   g_api_auth_valid = true;
   g_api_auth_error = "";
   
   // Check version requirement
   if (!CheckMinVersion())
   {
      g_api_auth_error = StringFormat("EA version %s blocked (min: %s)", EA_VERSION, min_version);
      Print("[API-AUTH] ", g_api_auth_error);
   }
   
   if (input_verbose_journal_logs)
   {
      Print("[API-AUTH] Account authorized (expires: ", TimeToString(expires, TIME_DATE), 
            ", max_lots: ", DoubleToString(max_lots, 2),
            ", open_cooldown: ", open_cooldown,
            ", close_cooldown: ", close_cooldown,
            ", min_version: ", min_version, ")");
   }
   
   return true;
}
```

**หมายเหตุ**: 
- ฟังก์ชัน `HttpGetRequest()` ที่มีอยู่แล้วสามารถใช้ต่อได้
- ฟังก์ชัน `ParseAuthorizationData()` ต้องอัพเดทให้รับ parameters เพิ่ม: `open_cooldown`, `close_cooldown`, `min_version`
- CSV format: `account,expires_at,max_lots,open_cooldown,close_cooldown,min_version`

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

#### **1.3.4 TP/SL Active Diff Close Functions (สร้างใหม่)**

```mql4
//+------------------------------------------------------------------+
//| TP/SL Active Diff Close Functions                                |
//+------------------------------------------------------------------+

// Calculate Master order profit/loss in points
double CalculateMasterOrderPnLPoints()
{
   double total_pnl_points = 0.0;
   int master_orders = 0;
   
   // Loop through all orders to find Master orders
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      
      if (OrderSymbol() != g_symbol)
         continue;
      
      if (OrderMagicNumber() != g_magic)
         continue;
      
      // Check if this is a Master order (based on comment)
      string comment = OrderComment();
      if (StringFind(comment, "MASTER") == -1)
         continue;
      
      // Calculate P/L in points
      double order_pnl_points = 0.0;
      double current_price = 0.0;
      
      if (OrderType() == OP_BUY)
      {
         current_price = MarketInfo(g_symbol, MODE_BID);
         // BUY: profit = (current_bid - open_price) / point
         order_pnl_points = (current_price - OrderOpenPrice()) / g_point;
      }
      else if (OrderType() == OP_SELL)
      {
         current_price = MarketInfo(g_symbol, MODE_ASK);
         // SELL: profit = (open_price - current_ask) / point
         order_pnl_points = (OrderOpenPrice() - current_price) / g_point;
      }
      
      total_pnl_points += order_pnl_points;
      master_orders++;
   }
   
   // Return average P/L if multiple orders exist
   if (master_orders > 0)
      return total_pnl_points / master_orders;
   
   return 0.0;
}

// Check TP condition for activating diff close
bool CheckTPActiveCondition()
{
   if (!input_tp_active_diff_close_enabled)
      return true; // Not enabled, always allow diff close
   
   double pnl_points = CalculateMasterOrderPnLPoints();
   
   // If profit >= TP threshold, activate diff close
   if (pnl_points >= input_tp_active_diff_close_points)
   {
      g_diff_close_blocked_by_tp = false;
      return true; // Allow diff close
   }
   
   // Below TP threshold, block diff close
   g_diff_close_blocked_by_tp = true;
   return false;
}

// Check SL condition for activating diff close
bool CheckSLActiveCondition()
{
   if (!input_sl_active_diff_close_enabled)
      return true; // Not enabled, always allow diff close
   
   double pnl_points = CalculateMasterOrderPnLPoints();
   
   // If loss >= SL threshold (negative value), activate diff close
   if (pnl_points <= -input_sl_active_diff_close_points)
   {
      g_diff_close_blocked_by_sl = false;
      return true; // Allow diff close (cut loss)
   }
   
   // Not enough loss yet, block diff close
   g_diff_close_blocked_by_sl = true;
   return false;
}

// Check if diff close should be blocked
bool IsDiffCloseBlocked()
{
   bool blocked = false;
   
   // Check TP condition (must meet TP to allow close)
   if (input_tp_active_diff_close_enabled)
   {
      if (!CheckTPActiveCondition())
         blocked = true;
   }
   
   // Check SL condition (if loss is too much, allow close)
   if (input_sl_active_diff_close_enabled)
   {
      // SL overrides TP block (cut loss has priority)
      if (CheckSLActiveCondition())
         blocked = false; // Force allow diff close
   }
   
   return blocked;
}

// Update diff close block state (call this every tick)
void UpdateDiffCloseBlockState()
{
   if (!input_tp_active_diff_close_enabled && !input_sl_active_diff_close_enabled)
   {
      g_diff_close_blocked_by_tp = false;
      g_diff_close_blocked_by_sl = false;
      return;
   }
   
   double pnl_points = CalculateMasterOrderPnLPoints();
   
   // Update TP state
   if (input_tp_active_diff_close_enabled)
   {
      if (pnl_points >= input_tp_active_diff_close_points)
         g_diff_close_blocked_by_tp = false;
      else
         g_diff_close_blocked_by_tp = true;
   }
   
   // Update SL state (overrides TP)
   if (input_sl_active_diff_close_enabled)
   {
      if (pnl_points <= -input_sl_active_diff_close_points)
         g_diff_close_blocked_by_sl = false;
      else
         g_diff_close_blocked_by_sl = true;
   }
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
   
   // Update TP/SL Active Diff Close state (Master only)
   if (input_role == ROLE_MASTER)
   {
      UpdateDiffCloseBlockState();
   }
   
   // ... rest of EA logic ...
}
```

---

### 1.6 MaybeClosePair() Integration

**ค้นหา**: ฟังก์ชัน `MaybeClosePair()` ที่มีอยู่

**แก้ไข**: เพิ่มการตรวจสอบ block ที่ต้นฟังก์ชัน

```mql4
void MaybeClosePair()
{
   // Check if diff close is blocked by TP/SL conditions
   if (IsDiffCloseBlocked())
   {
      if (input_verbose_journal_logs)
      {
         string reason = "";
         if (g_diff_close_blocked_by_tp)
            reason += "[TP not met] ";
         if (g_diff_close_blocked_by_sl)
            reason += "[SL not met] ";
         
         Print("[DIFF-CLOSE] Blocked: ", reason);
      }
      return; // Block diff close mechanism
   }
   
   // ... existing diff close logic ...
   // (Close Only button, Emergency close, Manual close ยังทำงานปกติ)
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
    // Check if current time is in blocked period (20:00 - 01:00 UTC)
    if (isInBlockedPeriod()) {
      Logger.log('Currently in blocked period (20:00-01:00 UTC)');
      Logger.log('Forcing signal to SELL...');
      const success = updateSignal('SELL', 1.0);
      if (success) {
        Logger.log('Signal forced to SELL successfully');
      }
      return success;
    }
    
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
        Logger.log('⚠️ Blocked by Cloudflare! Consider enabling ScraperAPI.');
        Logger.log('Set USE_SCRAPER_API = true and add your API key.');
      }
      
      return false;
    }
    
    const html = response.getContentText();
    
    // Check if we got Cloudflare challenge page
    if (html.includes('Attention Required') && html.includes('Cloudflare')) {
      Logger.log('⚠️ Cloudflare challenge detected!');
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
    
    Logger.log('✅ Signal updated successfully: ' + signal);
    return true;
    
  } catch (error) {
    Logger.log('Scrape error: ' + error.toString());
    
    if (error.toString().includes('429')) {
      Logger.log('⚠️ Rate limit exceeded. Wait before trying again.');
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
      Logger.log('[Method 1] ✅ Found text: "' + signalText + '"');
      Logger.log('[Method 1] Context (150 chars): "' + match[0].substring(0, 150) + '..."');
      
      let signalUpper = signalText.toUpperCase();
      
      if (signalUpper.includes('BUY')) {
        Logger.log('[Method 1] Parsed: BUY → Returning: SELL (swapped)');
        return 'SELL';
      } else if (signalUpper.includes('SELL')) {
        Logger.log('[Method 1] Parsed: SELL → Returning: BUY (swapped)');
        return 'BUY';
      } else {
        Logger.log('[Method 1] ⚠️ No BUY/SELL in text: "' + signalText + '"');
      }
    } else {
      Logger.log('[Method 1] ❌ No match');
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
          Logger.log('[Method 2.' + count + '] ✅ Parsed: BUY → Returning: SELL (swapped)');
          return 'SELL';
        } else if (textUpper.includes('SELL')) {
          Logger.log('[Method 2.' + count + '] ✅ Parsed: SELL → Returning: BUY (swapped)');
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
        Logger.log('[Method 3] ⚠️ BOTH found - BUY@' + buyPos + ', SELL@' + sellPos);
        
        if (buyPos < sellPos) {
          Logger.log('[Method 3] Using BUY (first) → Returning: SELL (swapped)');
          return 'SELL';
        } else {
          Logger.log('[Method 3] Using SELL (first) → Returning: BUY (swapped)');
          return 'BUY';
        }
      } else if (hasBuy) {
        Logger.log('[Method 3] ✅ Parsed: BUY → Returning: SELL (swapped)');
        return 'SELL';
      } else if (hasSell) {
        Logger.log('[Method 3] ✅ Parsed: SELL → Returning: BUY (swapped)');
        return 'BUY';
      } else {
        Logger.log('[Method 3] ❌ No BUY/SELL in context');
      }
    } else {
      Logger.log('[Method 3] ❌ "Forecast:" not found');
    }
    
    // Debug: Show HTML preview
    Logger.log('\n⚠️ All methods failed!');
    Logger.log('HTML preview (first 800 chars):\n' + html.substring(0, 800));
    Logger.log('\n❌ No signal found');
    
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
  
  // Run every 30 minutes (e.g., 10:00, 10:30, 11:00, 11:30, ...)
  ScriptApp.newTrigger('scrapeAndUpdateSignal')
    .timeBased()
    .everyMinutes(30)
    .create();
    
  Logger.log('Trigger created (runs every 30 minutes)');
}

// ========================================
// Scheduled Signal Control (Market Close)
// ========================================

// Check if current time is in blocked period (20:00 - 01:00 UTC)
function isInBlockedPeriod() {
  const now = new Date();
  const utcHour = now.getUTCHours();
  
  // Blocked period: 20:00 UTC to 01:00 UTC (next day)
  // Hours: 20, 21, 22, 23, 0
  if (utcHour >= 20 || utcHour < 1) {
    return true;
  }
  
  return false;
}

// Force signal to SELL (used during market close hours)
function forceSellSignal() {
  try {
    Logger.log('=== Force SELL Signal (Scheduled) ===');
    Logger.log('Time: ' + new Date().toISOString());
    
    const success = updateSignal('SELL', 1.0);
    
    if (success) {
      Logger.log('Signal forced to SELL successfully');
    } else {
      Logger.log('Failed to force SELL signal');
    }
    
    return success;
    
  } catch (error) {
    Logger.log('Force SELL error: ' + error.toString());
    return false;
  }
}

// Create trigger for scheduled signal control
// - Every 30 minutes: Scrape API (01:00-20:00 UTC) or Force SELL (20:00-01:00 UTC)
function createScheduledSignalTriggers() {
  // Delete existing triggers
  const triggers = ScriptApp.getProjectTriggers();
  for (let i = 0; i < triggers.length; i++) {
    const handler = triggers[i].getHandlerFunction();
    if (handler === 'forceSellSignal' || handler === 'scrapeAndUpdateSignal') {
      ScriptApp.deleteTrigger(triggers[i]);
      Logger.log('Deleted existing trigger: ' + handler);
    }
  }
  
  // Create trigger every 30 minutes
  // - During 01:00-20:00 UTC: Scrape from API
  // - During 20:00-01:00 UTC: Force SELL
  ScriptApp.newTrigger('scrapeAndUpdateSignal')
    .timeBased()
    .everyMinutes(30)
    .create();
  
  Logger.log('Created trigger (every 30 minutes)');
  
  Logger.log('=== Scheduled Triggers Summary ===');
  Logger.log('01:00-20:00 UTC: Scrape from API every 30 min');
  Logger.log('20:00-01:00 UTC: Force SELL every 30 min');
}

// Delete all scheduled signal triggers
function deleteScheduledSignalTriggers() {
  const triggers = ScriptApp.getProjectTriggers();
  let deletedCount = 0;
  
  for (let i = 0; i < triggers.length; i++) {
    const handler = triggers[i].getHandlerFunction();
    if (handler === 'forceSellSignal' || handler === 'scrapeAndUpdateSignal') {
      ScriptApp.deleteTrigger(triggers[i]);
      deletedCount++;
    }
  }
  
  Logger.log('Deleted ' + deletedCount + ' triggers');
}
```

**หมายเหตุสำคัญเกี่ยวกับ scrapeAndUpdateSignal()**:

1. **Data Source**: ดึงสัญญาณจาก TradersUnion Gold Signals
2. **Cloudflare Protection**: เว็บมี Cloudflare anti-bot → แนะนำใช้ ScraperAPI
3. **Parsing Method**: ใช้ 3 วิธีในการหาสัญญาณ (fallback mechanism)
   - Method 1: หาจาก "Forecast:" section ใกล้กับ class "ta-wg__summary-body"
   - Method 2: ค้นหาทุก element ที่มี class "ta-wg__summary-body"
   - Method 3: ค้นหา BUY/SELL ใน 1000 ตัวอักษรหลัง "Forecast:"
4. **Signal Validation**: ตรวจสอบว่าเป็นคำว่า "BUY" หรือ "SELL" เท่านั้น (case-insensitive)
5. **Error Handling**: มี try-catch ครอบคลุมทุกขั้นตอน พร้อม logging
6. **Confidence**: ตั้งค่าเป็น 0.85 โดยค่าเริ่มต้น (สามารถปรับได้)

---

---

### 2.2.1 Quick Setup Guide (สำหรับผู้มี API Key แล้ว) ⚡

**สำหรับผู้ที่สมัคร ScraperAPI แล้ว - ใช้เวลา 2 นาที:**

1. เปิด Google Apps Script Editor
2. หาบรรทัดที่มี `const USE_SCRAPER_API` (ประมาณบรรทัด 10-12)
3. **แก้ไข 2 บรรทัดนี้:**

```javascript
const USE_SCRAPER_API = true;                            // เปลี่ยนจาก false → true
const SCRAPER_API_KEY = '2c4938f6f3a54304d54f55af4a3e0ff3';  // ใส่ API key ของคุณ
```

4. **บันทึก** (Ctrl+S / Cmd+S)
5. **ทดสอบ**: เลือก `scrapeAndUpdateSignal` → กด Run
6. **ตรวจสอบ Logs**: ควรเห็น "✅ Signal updated successfully: BUY" (หรือ SELL)
7. **เช็ค Sheet**: ดูใน Signals sheet ว่ามีข้อมูลอัพเดท
8. **ตั้ง Auto**: รัน `createHourlyTrigger()` เพื่อ auto update ทุกชั่วโมง

✅ **เสร็จแล้ว!** EA จะดึงสัญญาณอัตโนมัติทุกชั่วโมงที่นาทีที่ 0 (เช่น 10:00, 11:00, 12:00, ...)

---

### 2.2.2 ScraperAPI Setup (คำแนะนำแบบละเอียด)

**ทำไมต้องใช้ ScraperAPI:**
- ✅ Bypass Cloudflare protection อัตโนมัติ
- ✅ จัดการ captcha และ JavaScript challenges
- ✅ Rotate IP addresses
- ✅ Free tier: 1,000 requests/month (เพียงพอสำหรับ scraping ทุก 1 ชั่วโมง)

**ขั้นตอนการตั้งค่า:**

**Step 1: สมัคร ScraperAPI**
1. ไปที่ https://www.scraperapi.com/signup
2. สมัครบัญชี (Free tier)
3. Login แล้วไปที่ Dashboard
4. คัดลอก **API Key** (รูปแบบ: `abc123def456...`)

**Step 2: เปิดใช้งานใน Apps Script**
```javascript
// แก้ไขใน Configuration section (บรรทัดต้นๆ ของ Apps Script)
const USE_SCRAPER_API = true;                            // เปลี่ยนเป็น true
const SCRAPER_API_KEY = '2c4938f6f3a54304d54f55af4a3e0ff3';  // วาง API key ของคุณ

// ตัวอย่าง:
// const SCRAPER_API_KEY = 'YOUR_API_KEY_HERE';  // ← แทนที่ด้วย API key จริง
```

**Important**: อย่าลืม**บันทึก** (Ctrl+S หรือ Cmd+S) หลังแก้ไข!

**Step 3: ทดสอบ curl ก่อน (Optional แต่แนะนำ)**
```bash
# ทดสอบใน Terminal/Command Prompt ว่า API key ใช้งานได้
curl 'https://api.scraperapi.com/?api_key=2c4938f6f3a54304d54f55af4a3e0ff3&url=https%3A%2F%2Ftradersunion.com%2Fcurrencies%2Fforecast%2Fgold%2Fsignals%2F'

# ควรได้ HTML กลับมา (ไม่ใช่ Cloudflare challenge page)
# ถ้าได้ HTML → API key ใช้งานได้ ✅
# ถ้าได้ error → check API key หรือ credits
```

**Step 4: ทดสอบใน Apps Script**
```javascript
// 1. บันทึก code ก่อน (Ctrl+S / Cmd+S)
// 2. เลือกฟังก์ชัน scrapeAndUpdateSignal จาก dropdown
// 3. กด Run button (▶️)
// 4. ตรวจสอบ Logs (View → Logs หรือ Ctrl+Enter)

// ควรเห็น:
// "Using ScraperAPI to bypass Cloudflare..."
// "✅ Signal updated successfully: BUY" (หรือ SELL)

// ถ้า error ให้ดู error message ใน Logs
```

**Step 5: ตรวจสอบ Signals Sheet**
- เปิด Google Sheet
- ไปที่ Sheet "Signals"
- ตรวจสอบ:
  - Cell A2: มีค่าเป็น "BUY" หรือ "SELL"
  - Cell B2: มี timestamp อัพเดท
  - Cell C2: มี confidence (0.85)

**Step 6: ตรวจสอบ Usage**
- เข้า ScraperAPI Dashboard: https://www.scraperapi.com/dashboard
- ดู API calls ที่ใช้ไป
- Free tier: 1,000 calls/month
- ใช้ทุก 1 ชั่วโมง = ~720 calls/month ✅
- แต่ละ call จะหัก 1 credit

**ScraperAPI Options:**

```javascript
// Basic (default) - แนะนำใช้แบบนี้ก่อน
'&render=false'  // Faster, no JavaScript rendering, ใช้ credit น้อยกว่า

// Advanced (ถ้าต้องการหรือ Basic ไม่ได้)
'&render=true'                    // Enable JavaScript rendering (ใช้ credit มากกว่า 5x)
'&country_code=us'                // Use US IP
'&session_number=123'             // Maintain session
'&keep_headers=true'              // Preserve original headers
'&premium=true'                   // Use premium proxies (paid plan only)
```

**Credit Usage:**
```
render=false  → 1 credit per request   (แนะนำ - ใช้น้อย)
render=true   → 5 credits per request  (ใช้เมื่อจำเป็น)

Free tier: 1,000 credits/month
  - render=false: 1,000 requests
  - render=true:  200 requests
```

**ตัวอย่างการปรับแต่ง:**

```javascript
// ถ้าต้องการ JavaScript rendering
url = 'http://api.scraperapi.com/?api_key=' + SCRAPER_API_KEY + 
      '&url=' + encodeURIComponent(targetUrl) +
      '&render=true' +              // เปิด JS rendering
      '&country_code=us';            // ใช้ IP จาก US
```

**Pricing Reference:**
```
Free:     1,000 requests/month    ($0)
Hobby:    10,000 requests/month   ($49/month)
Startup:  100,000 requests/month  ($149/month)
Business: 1M requests/month       ($599/month)

คำนวณ:
- ทุก 1 ชั่วโมง = 24 × 30 = 720 requests/month → Free tier พอใช้ ✅
- ทุก 30 นาที = 48 × 30 = 1,440 requests/month → ต้อง upgrade
```

---

**การปรับแต่งอื่นๆ**:
- เปลี่ยน URL: แก้ไขตัวแปร `targetUrl` ในฟังก์ชัน
- เปลี่ยน confidence: แก้ไขค่า `confidence` ก่อนเรียก `updateSignal()`
- เปลี่ยน interval: แก้ไข `everyHours(1)` เป็นค่าอื่น (เช่น `everyHours(2)`)
- ปรับ regex pattern: แก้ไขใน `parseSignalFromHTML()` ถ้าเว็บเปลี่ยนโครงสร้าง
- ปิด ScraperAPI: ตั้ง `USE_SCRAPER_API = false` (ถ้าเว็บไม่มี Cloudflare แล้ว)

**ตัวอย่าง Logs เมื่อสำเร็จ**:
```
[Apps Script Logs]
Signal updated successfully: BUY
```

**ตัวอย่าง Logs เมื่อล้มเหลว**:
```
[Apps Script Logs]
HTTP Error: 404
// หรือ
Failed to parse signal from webpage
No BUY or SELL signal found in HTML
// หรือ
Scrape error: Exception: Request failed for https://... returned code 403
```

**วิธีแก้ปัญหา**:
1. ถ้า HTTP Error 403/429 → เว็บ block request (ลดความถี่การ scrape)
2. ถ้า "No signal found" → เว็บเปลี่ยนโครงสร้าง (ต้องปรับ regex)
3. ถ้า timeout → network ช้า (ลองอีกครั้งภายหลัง)

### 2.3 Deploy Script

**ก่อน Deploy - ทดสอบฟังก์ชัน:**

1. ทดสอบ `scrapeAndUpdateSignal()`:
   - เลือกฟังก์ชัน `scrapeAndUpdateSignal` จาก dropdown
   - กด Run (▶️)
   - ครั้งแรกจะขอ permission → กด "Review permissions" → เลือก account → "Allow"
   - ตรวจสอบ Logs (View → Logs หรือ Ctrl+Enter)
   - ควรเห็น: "Signal updated successfully: BUY" หรือ "SELL"
   - ตรวจสอบ Signals sheet ว่ามีข้อมูลอัพเดท

2. ถ้าเจอ error:
   - ตรวจสอบว่า SHEET_ID ถูกต้อง
   - ตรวจสอบว่า sheet names ถูกต้อง (Authorization, Signals)
   - ตรวจสอบ Logs เพื่อดู error message

**Deploy Web App:**

1. คลิก "Deploy" → "New deployment"
2. เลือก type: "Web app"
3. ตั้งค่า:
   - **Execute as**: Me
   - **Who has access**: Anyone
4. คลิก "Deploy"
5. คัดลอก **Web app URL**
6. ทดสอบ URL ใน browser:
   - Test auth: `YOUR_URL?action=auth`
   - Test signal: `YOUR_URL?action=signal`

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
- [ ] **Test ScraperAPI Setup** (ถ้าใช้)
  - ตรวจสอบ API key ถูกต้อง
  - ตั้ง `USE_SCRAPER_API = true`
  - ตรวจสอบ ScraperAPI Dashboard มี credits
  - ทดสอบ direct URL: `http://api.scraperapi.com/?api_key=YOUR_KEY&url=https://tradersunion.com/currencies/forecast/gold/signals/`
- [ ] Test `scrapeAndUpdateSignal()` function manually
  - เลือกฟังก์ชัน `scrapeAndUpdateSignal` ใน Apps Script Editor
  - กด Run button
  - ตรวจสอบ Logs (View → Logs) ว่าดึงสัญญาณสำเร็จ
  - **ควรเห็น**: "Using ScraperAPI..." (ถ้าเปิด) หรือ "Fetching directly..."
  - **ควรเห็น**: "✅ Signal updated successfully: BUY" (หรือ SELL)
  - ตรวจสอบ Signals sheet ว่าอัพเดทข้อมูลถูกต้อง
- [ ] Test Cloudflare bypass
  - ทดสอบ `USE_SCRAPER_API = false` ดูว่าถูก block หรือไม่
  - ทดสอบ `USE_SCRAPER_API = true` ดูว่า bypass สำเร็จหรือไม่
  - เปรียบเทียบผลลัพธ์
- [ ] Test `parseSignalFromHTML()` function
  - ลอง fetch HTML ด้วยตัวเองและทดสอบ parsing
  - ตรวจสอบว่าจับ BUY/SELL ได้ถูกต้อง
- [ ] Test auto-update trigger
  - Run `createHourlyTrigger()` เพื่อสร้าง trigger
  - ตรวจสอบใน Apps Script → Triggers ว่า trigger ถูกสร้าง
  - รอ 1 ชั่วโมงและตรวจสอบว่า signal อัพเดทอัตโนมัติ
  - ตรวจสอบ ScraperAPI usage ว่าเพิ่มขึ้นตามที่คาดหวัง

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

### 5.7 TP/SL Active Diff Close Testing

- [ ] Test TP mode: block when profit < threshold
- [ ] Test TP mode: activate when profit >= threshold
- [ ] Test SL mode: block when loss < threshold
- [ ] Test SL mode: activate when loss >= threshold
- [ ] Test combined TP+SL in neutral zone (should block)
- [ ] Test combined TP+SL with profit > TP (should activate)
- [ ] Test combined TP+SL with loss > SL (should activate - priority)
- [ ] Test manual close buttons work when blocked
- [ ] Test emergency close works when blocked
- [ ] Test P/L calculation accuracy
- [ ] Test with multiple Master orders (average calculation)
- [ ] Test with no open orders (should not block)

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

### วิธีที่ 3: Schedule Auto-Update from TradersUnion

1. เปิด Apps Script Editor
2. ฟังก์ชัน `scrapeAndUpdateSignal()` ถูกตั้งค่าให้ดึงจาก TradersUnion แล้ว
3. ทดสอบฟังก์ชันก่อน: เลือก `scrapeAndUpdateSignal` และกด Run
4. ตรวจสอบ Logs (View → Logs) ว่าดึงสัญญาณได้ถูกต้อง
5. ถ้าสำเร็จ รันฟังก์ชัน `createHourlyTrigger()` เพื่อตั้งอัพเดทอัตโนมัติ

**หมายเหตุ**: 
- Trigger จะทำงานทุกชั่วโมงที่นาทีที่ 0 (เช่น 10:00, 11:00, 12:00, ...)
- ฟังก์ชันจะดึงสัญญาณ Gold จาก TradersUnion โดยอัตโนมัติ
- รองรับทั้ง BUY และ SELL signals (case-insensitive)
- Confidence ถูกตั้งเป็น 0.85 โดยค่าเริ่มต้น
- ถ้าต้องการเปลี่ยนแหล่งข้อมูล สามารถแก้ไข URL ในฟังก์ชัน `scrapeAndUpdateSignal()`

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

### Auto Signal Scraping (TradersUnion)
- **Source**: https://tradersunion.com/currencies/forecast/gold/signals/
- **Protection**: Cloudflare anti-bot → **ต้องใช้ ScraperAPI** ⭐
- **Update Frequency**: ทุก 1 ชั่วโมง (ถ้าเปิด trigger)
- **Supported Signals**: BUY, SELL (case-insensitive)
- **Default Confidence**: 0.85
- **Parsing Methods**: 3 levels fallback mechanism
- **Error Handling**: Auto retry on next schedule ถ้าล้มเหลว
- **ScraperAPI**: Free tier 1,000 requests/month (เพียงพอ)

### Scraping Limitations
- **Website Changes**: ถ้า TradersUnion เปลี่ยน HTML structure อาจต้องปรับ regex
- **Rate Limiting**: ไม่ควรตั้ง interval น้อยกว่า 30 นาที (เพื่อไม่ให้ถูก block)
- **Network Issues**: ถ้า network ล้มเหลว จะข้ามไปอัพเดทรอบถัดไป
- **Manual Override**: สามารถแก้ใน Google Sheet ได้ตลอดเวลา (manual มี priority)

### Troubleshooting Scraping
1. ตรวจสอบ Apps Script Logs: `View → Logs`
2. ทดสอบฟังก์ชัน manually: เลือก `scrapeAndUpdateSignal` แล้ว Run
3. ตรวจสอบว่าเว็บเข้าถึงได้: เปิด URL ใน browser
4. **ถ้าเจอ Cloudflare (403 error)**: เปิดใช้ ScraperAPI
   - ตั้ง `USE_SCRAPER_API = true`
   - ใส่ API key จาก https://www.scraperapi.com
   - ตรวจสอบ credits ใน Dashboard
5. ตรวจสอบ trigger: `Apps Script → Triggers` ดูว่า trigger ทำงาน
6. ถ้า parsing ล้มเหลว: อาจต้องตรวจสอบ HTML structure ใหม่

### ScraperAPI FAQ

**Q: ทำไมต้องใช้ ScraperAPI?**
- A: เว็บ TradersUnion ใช้ Cloudflare protection ที่ block automated requests. ScraperAPI จะ bypass ให้อัตโนมัติ

**Q: ฟรีไหม?**
- A: มี free tier 1,000 requests/month (เพียงพอถ้า scrape ทุก 1 ชั่วโมง = 720 requests/month)

**Q: ถ้า credits หมดจะเกิดอะไร?**
- A: จะได้ HTTP 429 error แล้ว fallback ไปใช้สัญญาณเก่า หรือ upgrade plan

**Q: ต้องใช้ credit card ไหม?**
- A: Free tier ไม่ต้องใส่ credit card

**Q: ถ้าไม่อยากใช้ ScraperAPI มีทางเลือกอื่นไหม?**
- A: มี 3 ทางเลือก:
  1. Manual update ใน Google Sheet (แนะนำสุด)
  2. ใช้ proxy service อื่น (Bright Data, ZenRows)
  3. สร้าง API middleware เองด้วย Puppeteer

**Q: ScraperAPI ปลอดภัยไหม?**
- A: ปลอดภัย เป็นบริการที่ใช้กันแพร่หลายในวงการ web scraping

**Q: Parse ได้สัญญาณผิด (อ่านได้ BUY แต่ควรเป็น SELL)?**
- A: ปัญหานี้เกิดจาก code จับ element ผิดตัว มีหลายแห่งบนเว็บที่มี BUY/SELL
- **วิธีแก้**: 
  1. ดู Logs debug (View → Logs)
  2. เช็คว่า Method ไหนจับได้ และจับค่าอะไร
  3. ดู "Context" ที่ log แสดง ว่าเป็น section ไหน
  4. ปรับ regex pattern ให้จับ element ที่ถูกต้อง
- **ตัวอย่าง**: ถ้าเว็บมี "Recommendation: BUY" และ "Forecast: SELL" code อาจจับผิดตัว

**Q: ทำไมต้องสลับ BUY/SELL (BUY→SELL, SELL→BUY)?**
- A: ขึ้นอยู่กับว่าเว็บแสดงสัญญาณแบบไหน:
  - ถ้าเว็บแสดง "ควร BUY" = เราต้องการ BUY → **ไม่ต้องสลับ**
  - ถ้าเว็บแสดง "แนวโน้ม SELL" แต่เราต้องการเทรด opposite → **ต้องสลับ**
- **วิธีเช็ค**: เข้าเว็บด้วยตา → ดูสัญญาณ → เทียบกับที่ EA ได้
- ถ้าไม่ต้องการสลับ ให้ลบ logic swap ออก (return ตรงๆ)

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

**"Diff close blocked by TP"**
- ตรวจสอบ Master order P/L ปัจจุบัน
- ตรวจสอบ input_tp_active_diff_close_points
- รอให้กำไรถึง threshold หรือปิด TP feature
- ใช้ manual close button ถ้าต้องการปิดทันที

**"Diff close blocked by SL"**
- ตรวจสอบ Master order P/L ปัจจุบัน
- ตรวจสอบ input_sl_active_diff_close_points
- รอให้ขาดทุนถึง threshold หรือปิด SL feature
- ใช้ manual close button ถ้าต้องการปิดทันที

**"TP/SL not working"**
- ตรวจสอบว่าเปิด input_tp_active_diff_close_enabled = true
- ตรวจสอบว่าเปิด input_sl_active_diff_close_enabled = true
- ตรวจสอบว่าเป็น ROLE_MASTER (Slave ไม่มีฟีเจอร์นี้)
- ตรวจสอบมี Master orders เปิดอยู่
- ตรวจสอบ Experts log สำหรับ [TP-ACTIVE] และ [SL-ACTIVE] messages

**"P/L calculation incorrect"**
- ตรวจสอบ g_point value ถูกต้อง
- ตรวจสอบ order comment มี "MASTER" string
- ตรวจสอบ magic number ตรงกัน
- ตรวจสอบ symbol ถูกต้อง

**"Scrape signal failed"**
- ตรวจสอบ Apps Script Logs (View → Logs)
- ตรวจสอบว่าเว็บ TradersUnion เข้าถึงได้
- ตรวจสอบว่าโครงสร้าง HTML ของเว็บไม่เปลี่ยน
- ลอง run `scrapeAndUpdateSignal()` manually เพื่อดู error
- ตรวจสอบว่า trigger ทำงานปกติ (Apps Script → Triggers)

**"HTTP Error: 403" / "Cloudflare challenge detected"**
- เว็บมี Cloudflare protection block request
- **Solution**: เปิดใช้ ScraperAPI
  - ตั้ง `USE_SCRAPER_API = true`
  - ใส่ `SCRAPER_API_KEY` ที่ถูกต้อง
  - ทดสอบอีกครั้ง
- ตรวจสอบ ScraperAPI credits ว่ายังเหลืออยู่
- ดู ScraperAPI Dashboard: https://www.scraperapi.com/dashboard

**"ScraperAPI enabled but API key is missing"**
- ลืมใส่ API key หรือใส่เป็น string ว่าง
- ไปที่ https://www.scraperapi.com/dashboard
- คัดลอก API key
- ใส่ใน `const SCRAPER_API_KEY = 'YOUR_KEY_HERE';`

**"ScraperAPI Error: 401" / "Unauthorized"**
- API key ไม่ถูกต้องหรือหมดอายุ
- ตรวจสอบ API key ใน ScraperAPI Dashboard
- คัดลอกใหม่และแทนที่ใน code

**"ScraperAPI Error: 429" / "Rate limit exceeded"**
- ใช้ requests เกิน quota (Free tier: 1000/month)
- ตรวจสอบ usage ใน ScraperAPI Dashboard
- รอจนกว่า quota จะ reset (monthly)
- หรือ upgrade plan
- หรือเพิ่ม interval เป็น 2-4 ชั่วโมง

**"No signal found in HTML"**
- เว็บ TradersUnion อาจเปลี่ยนโครงสร้าง HTML
- ตรวจสอบ source code ของเว็บใหม่
- อาจต้องปรับ regex pattern ในฟังก์ชัน `parseSignalFromHTML()`
- ใช้ Browser DevTools ตรวจสอบ XPath/CSS selector ที่ถูกต้อง
- ถ้าใช้ ScraperAPI ลองเปิด `render=true` สำหรับ JavaScript rendering

---

## 🎯 Part 9: TP/SL Active Diff Close Feature

### 9.1 Overview

ฟีเจอร์ TP/SL Active Diff Close ช่วยควบคุมการทำงานของ Diff Close Mechanism โดยใช้เงื่อนไข Take Profit และ Stop Loss

**หลักการทำงาน:**
- **TP Mode**: Block diff close จนกว่าออเดอร์ Master จะมีกำไรถึง X points
- **SL Mode**: ปล่อย diff close ทำงานทันทีเมื่อออเดอร์ Master ขาดทุนถึง X points (cut loss)
- **Priority**: SL มี priority สูงกว่า TP (การ cut loss สำคัญกว่า)

---

### 9.2 Use Cases

#### **Use Case 1: Wait for Profit (TP Mode)**

**สถานการณ์**: ต้องการให้ออเดอร์มีกำไรถึง 50 points ก่อนจึงให้ diff close ทำงาน

**Configuration:**
```
input_tp_active_diff_close_enabled = true
input_tp_active_diff_close_points = 50
input_sl_active_diff_close_enabled = false
```

**ผลลัพธ์:**
```
Master Order P/L = +30 points → Diff close BLOCKED ❌
Master Order P/L = +50 points → Diff close ACTIVE ✅
Master Order P/L = +70 points → Diff close ACTIVE ✅
Master Order P/L = -20 points → Diff close BLOCKED ❌ (ยังไม่ถึง TP)
```

---

#### **Use Case 2: Cut Loss Protection (SL Mode)**

**สถานการณ์**: ปล่อยให้ diff close ทำงานทันทีเมื่อขาดทุนถึง 30 points

**Configuration:**
```
input_tp_active_diff_close_enabled = false
input_sl_active_diff_close_enabled = true
input_sl_active_diff_close_points = 30
```

**ผลลัพธ์:**
```
Master Order P/L = +50 points → Diff close ACTIVE ✅ (ไม่มี block)
Master Order P/L = +10 points → Diff close ACTIVE ✅
Master Order P/L = -10 points → Diff close BLOCKED ❌ (ยังไม่ถึง SL)
Master Order P/L = -30 points → Diff close ACTIVE ✅ (ถึง SL แล้ว - cut loss)
Master Order P/L = -50 points → Diff close ACTIVE ✅ (เกิน SL - cut loss)
```

---

#### **Use Case 3: Combined TP + SL (แนะนำ)**

**สถานการณ์**: รอกำไร 50 points แต่ถ้าขาดทุนถึง 30 points ให้ปิดเลย

**Configuration:**
```
input_tp_active_diff_close_enabled = true
input_tp_active_diff_close_points = 50
input_sl_active_diff_close_enabled = true
input_sl_active_diff_close_points = 30
```

**ผลลัพธ์:**
```
Master Order P/L = +20 points → Diff close BLOCKED ❌ (ยังไม่ถึง TP)
Master Order P/L = +50 points → Diff close ACTIVE ✅ (ถึง TP)
Master Order P/L = +70 points → Diff close ACTIVE ✅ (เกิน TP)

Master Order P/L = -10 points → Diff close BLOCKED ❌ (ยังไม่ถึง SL)
Master Order P/L = -30 points → Diff close ACTIVE ✅ (ถึง SL - cut loss)
Master Order P/L = -50 points → Diff close ACTIVE ✅ (เกิน SL - cut loss)
```

**สรุป Logic:**
- ถ้ากำไร < 50 points และ ขาดทุน > -30 points → **BLOCKED** (zone ระหว่าง -30 ถึง +50)
- ถ้ากำไร >= 50 points → **ACTIVE** (take profit)
- ถ้าขาดทุน <= -30 points → **ACTIVE** (stop loss)

---

### 9.3 Behavior Details

#### **TP Logic (Take Profit Active)**
```
if (pnl >= tp_points):
   allow diff close ✅
else:
   block diff close ❌
```

#### **SL Logic (Stop Loss Active)**
```
if (pnl <= -sl_points):
   allow diff close ✅ (force cut loss)
else:
   block diff close ❌
```

#### **Combined Logic (TP + SL)**
```
if (pnl >= tp_points):
   allow diff close ✅ (take profit)
elif (pnl <= -sl_points):
   allow diff close ✅ (cut loss - PRIORITY)
else:
   block diff close ❌ (neutral zone)
```

---

### 9.4 Safety Features

#### **1. Manual Close ไม่ถูก Block**
- Close Only Button → ทำงานปกติ ✅
- Emergency Close → ทำงานปกติ ✅
- Manual Close (Debug buttons) → ทำงานปกติ ✅
- Force Close by Time → ทำงานปกติ ✅

#### **2. Block เฉพาะ Diff Close Mechanism**
```mql4
void MaybeClosePair()
{
   // Block ONLY automatic diff close
   if (IsDiffCloseBlocked())
      return;
   
   // Diff close logic continues...
}

// Other close functions NOT affected:
void ButtonCloseNow() { ... }        // ไม่ถูก block
void ForceCloseAll() { ... }         // ไม่ถูก block
void EmergencyClose() { ... }        // ไม่ถูก block
```

#### **3. Real-time P/L Calculation**
- คำนวณจาก Master orders เท่านั้น
- ใช้ current market price (Bid/Ask)
- อัพเดททุก tick

---

### 9.5 Configuration Examples

#### **Conservative (รอกำไร)**
```
TP: 100 points
SL: disabled
→ ออเดอร์ต้องมีกำไร 100 points ก่อนปิด
```

#### **Aggressive (cut loss เร็ว)**
```
TP: disabled
SL: 20 points
→ ขาดทุน 20 points ปิดทันที
```

#### **Balanced (รอกำไรพอสมควร + cut loss)**
```
TP: 50 points
SL: 30 points
→ กำไร 50+ ปิด, ขาดทุน 30+ ก็ปิด
```

#### **Disabled (ทำงานแบบเดิม)**
```
TP: disabled
SL: disabled
→ Diff close ทำงานตาม threshold ปกติ
```

---

### 9.6 Testing Checklist

#### **TP Testing**
- [ ] Test TP enabled with profit below threshold (should block)
- [ ] Test TP enabled with profit at threshold (should activate)
- [ ] Test TP enabled with profit above threshold (should activate)
- [ ] Test TP disabled (should always allow)

#### **SL Testing**
- [ ] Test SL enabled with loss below threshold (should block)
- [ ] Test SL enabled with loss at threshold (should activate)
- [ ] Test SL enabled with loss above threshold (should activate)
- [ ] Test SL disabled (should always allow)

#### **Combined Testing**
- [ ] Test TP+SL with profit above TP (should activate)
- [ ] Test TP+SL with loss above SL (should activate - priority)
- [ ] Test TP+SL in neutral zone (should block)
- [ ] Test manual close buttons still work when blocked

#### **Edge Cases**
- [ ] Test with no open orders (should not block)
- [ ] Test with multiple Master orders (should calculate average)
- [ ] Test P/L calculation accuracy
- [ ] Test during high volatility

---

### 9.7 Visual Examples

#### **Example 1: TP Mode Only**

```
Timeline of Master Order P/L:

Time  | P/L (points) | TP=50 | Diff Close Status
------|--------------|-------|------------------
00:00 | +10          | ❌    | BLOCKED
00:15 | +30          | ❌    | BLOCKED
00:30 | +45          | ❌    | BLOCKED
00:45 | +50          | ✅    | ACTIVE (can close)
01:00 | +55          | ✅    | ACTIVE
01:15 | +40          | ❌    | BLOCKED (fell below TP)
01:30 | +60          | ✅    | ACTIVE
```

#### **Example 2: TP + SL Mode**

```
Timeline of Master Order P/L:

Time  | P/L (points) | TP=50 | SL=30 | Diff Close Status
------|--------------|-------|-------|------------------
00:00 | +10          | ❌    | N/A   | BLOCKED (below TP)
00:15 | -10          | ❌    | ❌    | BLOCKED (neutral zone)
00:30 | -25          | ❌    | ❌    | BLOCKED (not enough loss)
00:45 | -30          | N/A   | ✅    | ACTIVE (SL hit - cut loss!)
01:00 | -35          | N/A   | ✅    | ACTIVE (SL exceeded)
01:15 | +20          | ❌    | N/A   | BLOCKED (recovered, below TP)
01:30 | +50          | ✅    | N/A   | ACTIVE (TP hit - take profit!)
```

---

### 9.8 Important Notes

#### **Calculation Method**
```
P/L Points = (Current Price - Open Price) / Point

For BUY:  P/L = (Bid - Open) / Point
For SELL: P/L = (Open - Ask) / Point
```

#### **Multiple Orders**
- ถ้ามีหลาย Master orders → ใช้ค่าเฉลี่ย
- ถ้าไม่มี orders → ไม่ block (allow diff close)

#### **Block Scope**
- Block **เฉพาะ** diff close mechanism
- **ไม่ block** manual closes, emergency closes, button closes
- **ไม่ block** forced closes by time
- **ไม่ block** scheduled close only mode

#### **Performance**
- คำนวณทุก tick (เร็ว, ไม่กระทบ performance)
- ไม่ต้อง API calls
- ทำงาน local ทั้งหมด

---

### 9.9 Recommended Settings

#### **Scalping (กำไรเล็กๆ)**
```
TP: 20 points
SL: 15 points
```

#### **Day Trading (กำไรปานกลาง)**
```
TP: 50 points
SL: 30 points
```

#### **Swing Trading (กำไรระยะยาว)**
```
TP: 100 points
SL: 60 points
```

#### **Conservative (รอกำไรมาก)**
```
TP: 200 points
SL: 50 points
```

---

### 9.10 Flow Diagram

```
┌─────────────────────────────────────────────┐
│         OnTick() - Every Tick               │
└─────────────┬───────────────────────────────┘
              │
              ▼
   ┌──────────────────────────┐
   │ UpdateDiffCloseBlockState│
   └──────────┬────────────────┘
              │
              ▼
   ┌──────────────────────────────────┐
   │ CalculateMasterOrderPnLPoints()  │
   │ → Get current P/L in points      │
   └──────────┬───────────────────────┘
              │
              ▼
   ┌──────────────────────────────────┐
   │  TP Enabled?                     │
   └──────┬────────────┬──────────────┘
          │ YES        │ NO
          ▼            │
   ┌──────────────┐    │
   │ P/L >= TP?   │    │
   └─┬──────────┬─┘    │
     │ YES      │ NO   │
     ▼          ▼      │
   ACTIVE    BLOCKED   │
     │          │      │
     └──────┬───┘      │
            │◄─────────┘
            ▼
   ┌──────────────────────────────────┐
   │  SL Enabled?                     │
   └──────┬────────────┬──────────────┘
          │ YES        │ NO
          ▼            │
   ┌──────────────┐    │
   │ P/L <= -SL?  │    │
   └─┬──────────┬─┘    │
     │ YES      │ NO   │
     ▼          ▼      │
   ACTIVE    BLOCKED   │
   (FORCE)     │       │
     │         │       │
     └────┬────┘       │
          │◄───────────┘
          ▼
   ┌──────────────────────────────────┐
   │  Final Block State               │
   │  • TP Block: true/false          │
   │  • SL Block: true/false          │
   │  • Final: BLOCKED if any true    │
   │           ACTIVE if SL activates │
   └──────────┬───────────────────────┘
              │
              ▼
   ┌──────────────────────────────────┐
   │     MaybeClosePair()             │
   ├──────────────────────────────────┤
   │  if (IsDiffCloseBlocked())       │
   │     return; ← EXIT               │
   │                                  │
   │  // Continue diff close logic... │
   └──────────────────────────────────┘
```

---

### 9.11 Code Integration Summary

**Files to Modify:**
- ✅ Input Parameters section
- ✅ Global Variables section
- ✅ Add new functions (1.3.4)
- ✅ OnTick() integration (1.5)
- ✅ MaybeClosePair() integration (1.6)

**Lines of Code**: ~150 บรรทัด (functions + integration)

**Complexity**: Medium (ไม่ซับซ้อน, logic ตรงไปตรงมา)

**Testing Time**: 2-4 ชั่วโมง

---

### 9.12 Quick Reference Table

| TP Enabled | SL Enabled | P/L = +60 | P/L = +30 | P/L = -10 | P/L = -40 |
|------------|------------|-----------|-----------|-----------|-----------|
| ✅ (50)    | ❌         | ✅ ACTIVE | ❌ BLOCK  | ❌ BLOCK  | ❌ BLOCK  |
| ❌         | ✅ (30)    | ✅ ACTIVE | ✅ ACTIVE | ✅ ACTIVE | ✅ ACTIVE |
| ✅ (50)    | ✅ (30)    | ✅ ACTIVE | ❌ BLOCK  | ❌ BLOCK  | ✅ ACTIVE |
| ❌         | ❌         | ✅ ACTIVE | ✅ ACTIVE | ✅ ACTIVE | ✅ ACTIVE |

*หมายเหตุ*: ตัวเลขในวงเล็บคือ threshold points

---

### 9.13 FAQ

**Q1: ฟีเจอร์นี้มีผลกับ Slave หรือไม่?**
- A: ไม่มีผล ทำงานบน Master เท่านั้น

**Q2: ถ้าตั้ง TP และ SL เท่ากัน (เช่น 50 points) จะเกิดอะไร?**
- A: SL มี priority สูงกว่า ถ้าขาดทุน 50 points จะปล่อยให้ close ได้เลย

**Q3: TP/SL นี้เหมือน TP/SL ของ MT4/MT5 หรือไม่?**
- A: ไม่เหมือน นี่คือเงื่อนไขสำหรับ activate/block diff close mechanism เท่านั้น

**Q4: ถ้าปิดทั้ง TP และ SL EA จะทำงานอย่างไร?**
- A: Diff close จะทำงานตามปกติ (ตาม threshold เดิม)

**Q5: สามารถใช้ TP อย่างเดียวโดยไม่มี SL ได้หรือไม่?**
- A: ได้ แต่อันตราย เพราะถ้าขาดทุนมากจะไม่มีการ cut loss

**Q6: ค่า P/L คำนวณจาก order เดียว หรือรวมทุก orders?**
- A: ถ้ามีหลาย Master orders จะคำนวณค่าเฉลี่ย

**Q7: TP/SL นี้ส่งผลกับการเปิดออเดอร์หรือไม่?**
- A: ไม่ส่งผล มีผลเฉพาะการปิดออเดอร์ผ่าน diff close เท่านั้น

**Q8: ถ้า P/L อยู่ที่ +49 points (TP=50) แล้วตกลงมา +30 จะเกิดอะไร?**
- A: จะกลับไปสถานะ BLOCKED อีกครั้ง (ยังไม่ถึง TP)

**Q9: Close Only button ทำงานตอน blocked หรือไม่?**
- A: ทำงานปกติ ไม่ถูก block

**Q10: Emergency close และ Force close by time ทำงานหรือไม่?**
- A: ทำงานปกติทุกอย่าง block เฉพาะ automatic diff close

---

### 9.14 Visual State Diagram

```
State 1: TP MODE ONLY (TP=50)
════════════════════════════════════

P/L < 50 points     →  [BLOCKED] 🔒
P/L >= 50 points    →  [ACTIVE]  ✅


State 2: SL MODE ONLY (SL=30)
════════════════════════════════════

P/L > -30 points    →  [BLOCKED] 🔒
P/L <= -30 points   →  [ACTIVE]  ✅ (cut loss)


State 3: TP+SL MODE (TP=50, SL=30)
════════════════════════════════════

P/L >= +50 points   →  [ACTIVE]  ✅ (take profit)
P/L between -30..+50→  [BLOCKED] 🔒 (neutral zone)
P/L <= -30 points   →  [ACTIVE]  ✅ (cut loss - PRIORITY)


State 4: BOTH DISABLED
════════════════════════════════════

All P/L values     →  [ACTIVE]  ✅ (normal diff close)
```

---

### 9.15 Implementation Priority

**Phase 1 (Core API)**: ✅ Completed
- API system structure
- Authorization module
- Signal module

**Phase 2 (TP/SL Feature)**: 📋 Planned (ใน Guide นี้)
- TP Active Diff Close
- SL Active Diff Close
- Combined TP+SL logic
- Integration with MaybeClosePair()

**Future Enhancements**: 💡 Ideas
- Trailing TP (TP ที่เคลื่อนตาม profit)
- Time-based TP/SL (ปรับค่าตามเวลา)
- Dynamic TP/SL from API (ดึง TP/SL จาก API)
- Multiple TP levels (TP1, TP2, TP3)

---

## 🎓 Part 10: Real-World Scenarios & Best Practices

### 10.1 Scenario: High Volatility Market

**สถานการณ์**: ตลาดมี volatility สูง, ราคาขึ้นลงรวดเร็ว

**ปัญหา**:
- Diff close อาจปิดออเดอร์เร็วเกินไป (กำไรน้อย)
- ออเดอร์อาจกลับมาขาดทุนได้เร็ว

**Solution with TP/SL Active**:
```
input_tp_active_diff_close_enabled = true
input_tp_active_diff_close_points = 30    // รอกำไร 30 points ก่อน
input_sl_active_diff_close_enabled = true
input_sl_active_diff_close_points = 50    // Cut loss ที่ 50 points

Benefit:
✅ รอให้กำไรถึง 30 points ก่อนปิด (ไม่ปิดเร็วเกินไป)
✅ ถ้าขาดทุนถึง 50 points ปิดทันที (protect capital)
✅ Diff close จะทำงานตอนที่เหมาะสมเท่านั้น
```

**ผลลัพธ์**:
- ↑ กำไรต่อออเดอร์เพิ่มขึ้น (รอถึง TP ก่อน)
- ↓ ความเสี่ยงลดลง (มี SL cut loss)
- ↑ Stability เพิ่มขึ้น (ไม่ปิด-เปิดบ่อย)

---

### 10.2 Scenario: Low Volatility Market

**สถานการณ์**: ตลาด sideways, เคลื่อนไหวช้า

**ปัญหา**:
- ออเดอร์ใช้เวลานานถึง TP
- Capital ถูกล็อคนาน

**Solution with TP/SL Active**:
```
input_tp_active_diff_close_enabled = true
input_tp_active_diff_close_points = 15    // TP ต่ำ (เพราะตลาดช้า)
input_sl_active_diff_close_enabled = true
input_sl_active_diff_close_points = 20    // SL ต่ำเช่นกัน

Benefit:
✅ ปิดได้เร็วขึ้น (TP ต่ำ)
✅ Cut loss ก่อนที่จะเสียมาก
✅ Capital turnover เร็วขึ้น
```

**ผลลัพธ์**:
- ↑ จำนวนเทรดต่อวันเพิ่มขึ้น
- ↑ Capital efficiency ดีขึ้น
- ↓ Drawdown น้อยลง

---

### 10.3 Scenario: News Trading

**สถานการณ์**: มี news events สำคัญ (NFP, FOMC, etc.)

**ปัญหา**:
- ราคาอาจกระโดด (gap/spike)
- Slippage สูง

**Solution with TP/SL Active**:
```
// Before News (1 hour before)
input_tp_active_diff_close_enabled = false
input_sl_active_diff_close_enabled = true
input_sl_active_diff_close_points = 100   // SL กว้าง (รองรับ spike)

// During News (ปิด EA หรือ)
input_tp_active_diff_close_enabled = true
input_tp_active_diff_close_points = 20    // TP แคบ (ปิดเร็ว)
input_sl_active_diff_close_enabled = true
input_sl_active_diff_close_points = 30    // SL แคบ

// After News (2 hours after)
input_tp_active_diff_close_enabled = true
input_tp_active_diff_close_points = 40
input_sl_active_diff_close_enabled = true
input_sl_active_diff_close_points = 50
```

**ผลลัพธ์**:
- ↑ ปลอดภัยกว่าตอน news
- ↓ Risk of big loss ลดลง

---

### 10.4 Best Practices

#### **1. TP/SL Ratio**
```
✅ แนะนำ: TP:SL = 1:1 ถึง 2:1
   Example: TP=50, SL=50 (1:1)
   Example: TP=60, SL=30 (2:1)

❌ ไม่แนะนำ: TP:SL = 5:1 หรือ 1:5
   Example: TP=100, SL=20 (5:1) → cut loss เร็วเกิน
   Example: TP=20, SL=100 (1:5) → กำไรน้อย ขาดทุนมาก
```

#### **2. Adapt to Market Conditions**
```
Trending Market:
   → TP กว้าง (ให้กำไรวิ่ง)
   → SL กว้าง (ไม่ถูก cut เร็ว)

Ranging Market:
   → TP แคบ (เก็บกำไรเล็กๆ)
   → SL แคบ (cut loss เร็ว)

High Volatility:
   → TP กลาง
   → SL กลาง
   → ใช้ร่วมกับ confidence threshold

Low Volatility:
   → TP ต่ำ
   → SL ต่ำ
```

#### **3. Combine with Other Features**
```
TP/SL Active + API Signal:
   → API บอกว่า BUY confidence 0.9
   → ตั้ง TP=80, SL=40 (confident → TP กว้าง)
   
   → API บอกว่า BUY confidence 0.5
   → ตั้ง TP=30, SL=30 (not confident → TP แคบ)

TP/SL Active + Force Close Time:
   → ใช้ TP/SL ระหว่างวัน
   → Force close all ตอน end of day
```

#### **4. Testing Strategy**
```
Week 1: Test TP only (no SL)
   → เข้าใจพฤติกรรม TP

Week 2: Test SL only (no TP)
   → เข้าใจพฤติกรรม SL

Week 3: Test TP+SL combined
   → เข้าใจ interaction ระหว่าง TP และ SL

Week 4: Optimize parameters
   → หาค่า TP/SL ที่เหมาะสม
```

#### **5. Monitoring & Adjustment**
```
Daily Review:
   - จำนวนครั้งที่ TP activate
   - จำนวนครั้งที่ SL activate
   - จำนวนครั้งที่ manual close
   - Average P/L per trade

Weekly Adjustment:
   - ปรับ TP/SL ตามผลการเทรด
   - ปรับตาม market conditions
   - ปรับตาม win rate

Monthly Review:
   - Total profit/loss
   - Drawdown
   - Sharpe ratio
   - ตัดสินใจเปิด/ปิดฟีเจอร์
```

---

### 10.5 Common Mistakes to Avoid

❌ **Mistake 1**: ตั้ง TP สูงเกิน (เช่น 500 points)
   - ทำให้ไม่มีวันถึง TP → diff close ไม่เคยทำงาน

❌ **Mistake 2**: ตั้ง SL ต่ำเกิน (เช่น 5 points)
   - ถูก cut loss บ่อยเกินไป → กำไรน้อย

❌ **Mistake 3**: ใช้ TP เดียวกันทุก pair
   - EURUSD TP=50 อาจเหมาะ แต่ GBPJPY ควรใช้ TP=100

❌ **Mistake 4**: ไม่ปรับตาม timeframe
   - M5 ควรใช้ TP/SL แคบ
   - H1 ควรใช้ TP/SL กว้าง

❌ **Mistake 5**: ลืมทดสอบ manual close
   - ต้องแน่ใจว่า manual close ยังทำงานตอน blocked

---

### 10.6 Performance Metrics

**Key Metrics to Track:**

```
1. TP Hit Rate (%)
   = (TP activations / Total trades) × 100
   Target: > 40%

2. SL Hit Rate (%)
   = (SL activations / Total trades) × 100
   Target: < 30%

3. Average Profit per TP Trade
   = Total profit from TP trades / TP count
   Target: > threshold × point value

4. Average Loss per SL Trade
   = Total loss from SL trades / SL count
   Target: < SL threshold × point value

5. Blocked Rate (%)
   = (Blocked counts / Total diff close attempts) × 100
   Target: 20-50% (ถ้าสูงเกิน → TP/SL เข้มเกิน)

6. Manual Close Rate (%)
   = (Manual closes / Total closes) × 100
   Target: < 10% (ถ้าสูง → TP/SL ไม่ effective)
```

---

### 10.7 Quick Decision Matrix

| Market Type | Volatility | TP Points | SL Points | TP:SL Ratio |
|-------------|------------|-----------|-----------|-------------|
| Trending    | High       | 80-100    | 40-50     | 2:1         |
| Trending    | Medium     | 60-80     | 30-40     | 2:1         |
| Trending    | Low        | 40-60     | 20-30     | 2:1         |
| Ranging     | High       | 40-50     | 40-50     | 1:1         |
| Ranging     | Medium     | 30-40     | 30-40     | 1:1         |
| Ranging     | Low        | 20-30     | 20-30     | 1:1         |
| News Event  | Extreme    | 20-30     | 60-100    | 1:3         |
| Breakout    | High       | 100-150   | 50-60     | 2:1         |

---

### 10.8 Logging Best Practices

**แนะนำให้เปิด verbose logs เมื่อ:**
```
input_verbose_journal_logs = true
```

**Log messages ที่ควรติดตาม:**
```
[TP-ACTIVE] Diff close activated: P/L=55.2 >= TP=50
[TP-ACTIVE] Diff close blocked: P/L=42.1 < TP=50
[SL-ACTIVE] Diff close activated: P/L=-35.8 <= -SL=-30
[SL-ACTIVE] Diff close blocked: P/L=-18.4 > -SL=-30
[DIFF-CLOSE] Blocked: [TP not met]
[API-SIGNAL] Fetched signal: BUY (confidence: 0.85)
[API-SIGNAL] Master side changed to: BUY
```

**วิเคราะห์ logs:**
- ถ้าเห็น "blocked" บ่อย → TP/SL เข้มเกิน
- ถ้าไม่เห็น "blocked" เลย → TP/SL หลวมเกิน
- ถ้าเห็น "SL activated" บ่อย → SL ต่ำเกิน
- ถ้าเห็น "Failed to parse signal" → ต้องตรวจสอบ HTML parsing

---

### 10.9 Auto Scraping Best Practices

#### **Scraping Strategy**

**⚠️ สำคัญ: TradersUnion มี Cloudflare Protection**
```javascript
// ต้องเปิด ScraperAPI เพื่อ bypass Cloudflare
const USE_SCRAPER_API = true;
const SCRAPER_API_KEY = 'YOUR_API_KEY';  // Get from scraperapi.com
```

**Option 1: Full Auto (แนะนำสำหรับ experienced traders)**
```javascript
// Apps Script Configuration:
const USE_SCRAPER_API = true;
const SCRAPER_API_KEY = 'abc123...';

// Apps Script: ตั้ง trigger ทุก 1 ชั่วโมง
createHourlyTrigger();

// EA Settings:
input_api_signal_enabled = true
input_api_signal_auto_apply = true
input_api_signal_min_confidence = 0.70  // ปรับตามความเสี่ยง
```

**Option 2: Hybrid (แนะนำสำหรับ beginners)**
```javascript
// Apps Script: Auto scrape แต่ไม่ auto apply
createHourlyTrigger();

// EA Settings:
input_api_signal_enabled = true
input_api_signal_auto_apply = false      // ✅ ปิด auto apply
input_api_signal_min_confidence = 0.80

// ผลลัพธ์: สัญญาณถูก scrape แต่ต้องแก้ใน Sheet manually ก่อน EA จะใช้
```

**Option 3: Manual Only**
```javascript
// Apps Script: ไม่ต้องสร้าง trigger
// แก้ไข Sheet ด้วยมือเมื่อต้องการ

// EA Settings:
input_api_signal_enabled = false          // ปิด signal API ทั้งหมด
```

#### **Confidence Level Guidelines**

```
Confidence >= 0.90  →  Very High (เทรดได้แทบทุกครั้ง)
Confidence >= 0.80  →  High (เทรดได้ส่วนใหญ่)
Confidence >= 0.70  →  Medium (เทรดได้บ้าง)
Confidence >= 0.60  →  Low (ระวัง)
Confidence <  0.60  →  Very Low (ไม่แนะนำ)

แนะนำ: min_confidence = 0.75 - 0.80 (balanced)
```

#### **Scraping Interval Guidelines**

```
Every 30 minutes  →  สำหรับ scalping (ต้องการ signal เร็ว)
Every 1 hour      →  สำหรับ day trading (แนะนำ)
Every 4 hours     →  สำหรับ swing trading
Every 12 hours    →  สำหรับ position trading

⚠️ อย่าตั้งน้อยกว่า 30 นาที (เพื่อไม่ให้ถูก rate limit)
```

#### **Error Handling Strategy**

```javascript
// ใน scrapeAndUpdateSignal() มี error handling อยู่แล้ว
// ถ้า scrape ล้มเหลว:
// 1. Log error message
// 2. Return false
// 3. ข้ามไปรอบถัดไป
// 4. ใช้สัญญาณเก่าต่อไป (ไม่เปลี่ยน)

// ดังนั้น: EA จะยังใช้สัญญาณล่าสุดที่สำเร็จ
```

#### **Monitoring Checklist**

**Daily:**
- [ ] ตรวจสอบ Apps Script Logs มี error หรือไม่
- [ ] ตรวจสอบ Signals sheet อัพเดทล่าสุดเมื่อไหร่
- [ ] ตรวจสอบ EA logs มี [API-SIGNAL] messages

**Weekly:**
- [ ] ตรวจสอบ trigger ยังทำงานหรือไม่ (Apps Script → Triggers)
- [ ] ตรวจสอบ scrape success rate
- [ ] ปรับ confidence threshold ถ้าจำเป็น

**Monthly:**
- [ ] ตรวจสอบว่า TradersUnion ยังมี Gold signals หรือไม่
- [ ] ทดสอบ scraping manually
- [ ] Review signal accuracy vs actual results

#### **Backup Plan**

```
Plan A: Auto scrape from TradersUnion (primary)
  ↓ fail
Plan B: Manual update ใน Google Sheet
  ↓ fail
Plan C: EA ใช้ input_master_side ที่ตั้งไว้ (fallback)

✅ แนะนำ: เปิด auto scrape + มี manual monitoring
```

---

---

## 📚 Version History

### Version 1.3 (December 2025) ⭐ **CURRENT**
**Added:**
- ✅ Auto Web Scraping from TradersUnion Gold Signals
- ✅ `scrapeAndUpdateSignal()` function with 3-level parsing fallback
- ✅ `parseSignalFromHTML()` function with multiple regex patterns
- ✅ Support for case-insensitive BUY/SELL detection
- ✅ Comprehensive error handling for scraping
- ✅ Part 10.9: Auto Scraping Best Practices
- ✅ Hybrid mode support (auto scrape + manual approval)
- ✅ Scraping interval guidelines
- ✅ Confidence level guidelines
- ✅ Monitoring checklist for auto scraping
- ✅ Troubleshooting guide for scraping errors

**Features:**
- 🌐 Auto fetch signals from TradersUnion website
- 🔄 3-method HTML parsing (fallback mechanism)
- 🎯 Smart signal detection (BUY/SELL)
- ⏱️ Configurable update intervals (hourly default)
- 🛡️ Built-in error handling and retry logic
- 📊 Hybrid operation modes (full auto / semi-auto / manual)
- 🔍 Comprehensive logging for debugging

---

### Version 1.2 (December 2025)
**Added:**
- ✅ Part 9: TP/SL Active Diff Close Feature (Full documentation)
- ✅ Part 10: Real-World Scenarios & Best Practices
- ✅ TP/SL Functions (1.3.4)
- ✅ MaybeClosePair() Integration (1.6)
- ✅ OnTick() Integration for TP/SL state updates
- ✅ Input Parameters: `input_tp_active_diff_close_*` และ `input_sl_active_diff_close_*`
- ✅ Global Variables: `g_diff_close_blocked_by_tp` และ `g_diff_close_blocked_by_sl`
- ✅ FAQ, Quick Reference Table, State Diagrams
- ✅ Performance Metrics & Decision Matrix
- ✅ Testing Checklist for TP/SL feature

**Features:**
- 🎯 TP Active Diff Close (รอกำไรก่อนปิด)
- 🛡️ SL Active Diff Close (cut loss อัตโนมัติ)
- 🔄 Combined TP+SL with priority logic
- 📊 Real-time P/L calculation
- 🎨 Visual flow diagrams and examples

---

### Version 1.1 (December 2025)
**Added:**
- ✅ Part 1-8: Core API Integration
- ✅ Authorization API via Google Apps Script
- ✅ Signal API via Google Apps Script
- ✅ 3-Level Control System (Master API, Auth API, Signal API)
- ✅ Auto-apply signal to master_side
- ✅ Pending signal mechanism (wait for positions close)
- ✅ Confidence threshold filtering
- ✅ Comprehensive testing checklist

**Breaking Changes:**
- ❌ Removed Google Sheets direct authorization
- ❌ Removed `input_auth_sheet_url`
- ✅ Replaced with API-based authorization

---

## 📊 Feature Comparison

| Feature | Version 1.1 | Version 1.2 | Version 1.3 |
|---------|-------------|-------------|-------------|
| API Authorization | ✅ | ✅ | ✅ |
| API Signal Fetch | ✅ | ✅ | ✅ |
| Auto-apply Signal | ✅ | ✅ | ✅ |
| Pending Signal | ✅ | ✅ | ✅ |
| Confidence Filter | ✅ | ✅ | ✅ |
| **TP Active Diff Close** | ❌ | ✅ ⭐ | ✅ |
| **SL Active Diff Close** | ❌ | ✅ ⭐ | ✅ |
| **Combined TP+SL** | ❌ | ✅ ⭐ | ✅ |
| **Real-time P/L Calc** | ❌ | ✅ ⭐ | ✅ |
| **Best Practices Guide** | ❌ | ✅ ⭐ | ✅ |
| **Auto Web Scraping** | ❌ | ❌ | ✅ ⭐ |
| **TradersUnion Integration** | ❌ | ❌ | ✅ ⭐ |
| **Multi-method Parsing** | ❌ | ❌ | ✅ ⭐ |
| **Hybrid Mode Support** | ❌ | ❌ | ✅ ⭐ |

---

## 🎯 Implementation Summary

### What This Guide Covers

✅ **API Integration** (Part 1-4)
- Complete MQL4 code changes
- Google Apps Script setup
- Google Sheets configuration
- MT4/MT5 configuration

✅ **TP/SL Feature** (Part 9-10) ⭐ **NEW**
- Input parameters and global variables
- 4 new functions (~150 lines)
- Integration with OnTick() and MaybeClosePair()
- Use cases and best practices
- Testing strategies

✅ **Testing & Deployment** (Part 5-6)
- Comprehensive testing checklist
- Deployment steps
- Post-deployment monitoring

✅ **User Guide** (Part 7-8)
- Manual signal updates
- Troubleshooting
- Important notes

✅ **Advanced Topics** (Part 10)
- Real-world scenarios
- Performance metrics
- Common mistakes to avoid
- Decision matrix

---

## 🚀 Quick Start Guide

### For First-Time Users

**Step 1**: Read Part 1-4 (API Setup)
- Understand API architecture
- Setup Google Apps Script
- Configure Google Sheets

**Step 2**: Deploy API (Part 2-3)
- Deploy Google Apps Script
- Get Web App URL
- Test endpoints

**Step 3**: Update EA Code (Part 1)
- Add input parameters
- Add global variables
- Add new functions
- Integrate with OnInit/OnTick

**Step 4**: Test (Part 5)
- Test authorization
- Test signal fetching
- Test TP/SL feature (if enabled)

**Step 5**: Deploy (Part 6)
- Deploy to demo first
- Monitor logs
- Deploy to production

---

### For Existing Users (Upgrade to v1.3)

**Step 1**: Backup current EA files ⚠️

**Step 2**: Update Google Apps Script (Part 2.2)
- เปิด existing Apps Script
- แทนที่ฟังก์ชัน `scrapeAndUpdateSignal()` และ `parseSignalFromHTML()`
- Save และ test ฟังก์ชันใหม่

**Step 3**: Enable Auto Scraping (Optional)
- Run `createHourlyTrigger()` เพื่อเปิด auto update
- ตรวจสอบ trigger ใน Apps Script → Triggers
- รอ 1 ชั่วโมงแล้วตรวจสอบ Signals sheet

**Step 4**: Configure EA Settings
```
// Full Auto Mode
input_api_signal_enabled = true
input_api_signal_auto_apply = true
input_api_signal_min_confidence = 0.75

// Or Hybrid Mode  
input_api_signal_enabled = true
input_api_signal_auto_apply = false  // Manual approval required
```

**Step 5**: Test & Monitor (Part 10.9)
- ตรวจสอบ Apps Script Logs
- ตรวจสอบ EA logs มี [API-SIGNAL] messages
- Monitor signal changes และ accuracy

---

### For Users Adding TP/SL Feature (Upgrade to v1.2+)

**Step 1**: Backup current EA files ⚠️

**Step 2**: Add TP/SL code (Part 9.11)
- Copy input parameters (4 lines)
- Copy global variables (2 lines)
- Copy functions (1.3.4 section)
- Add OnTick integration
- Add MaybeClosePair integration

**Step 3**: Test TP/SL feature (Part 9.6)
- Test TP mode only
- Test SL mode only
- Test combined mode

**Step 4**: Optimize (Part 10)
- Use recommended settings
- Monitor performance
- Adjust based on market

---

## 💡 Key Takeaways

### Core API System
1. **3-Level Control**: Master → Auth → Signal
2. **Flexibility**: Enable/disable each component independently
3. **Safety**: Pending mechanism for signal changes
4. **Reliability**: Periodic checks with caching

### TP/SL Active Diff Close ⭐
1. **Smart Control**: Block diff close until conditions met
2. **Risk Management**: Automatic cut loss protection
3. **Profit Protection**: Wait for target profit before closing
4. **Manual Override**: Manual closes always work
5. **Real-time**: Updates every tick

### Best Practices
1. **Start Conservative**: Test with demo account first
2. **Monitor Logs**: Review logs daily for first week
3. **Adjust Gradually**: Don't change too many parameters at once
4. **Use Proper Ratios**: TP:SL between 1:1 to 2:1
5. **Adapt to Market**: Change settings based on conditions

---

## 📞 Support & Resources

### Documentation Files
- 📄 This Guide: `API-Signal-Integration-Guide.md`
- 📄 Authorization: `Google-Sheets-Authorization-Setup.md`
- 📄 Installation: `Installation.txt`
- 📄 Input Guide: `Input-Guide.md`

### Testing Resources
- ✅ Testing Checklist (Part 5)
- ✅ TP/SL Testing (Part 9.6)
- ✅ Edge Cases (Part 5.5)

### Learning Resources
- 📖 Use Cases (Part 9.2)
- 📖 Real-World Scenarios (Part 10.1-10.3)
- 📖 Best Practices (Part 10.4)
- 📖 FAQ (Part 9.13)

---

## 🏁 Final Summary

**เอกสารนี้ครอบคลุม:**

1. **API Integration** - ระบบดึงสัญญาณและ authorization ผ่าน API ที่ยืดหยุ่นและปลอดภัย

2. **TP/SL Active Diff Close** - ฟีเจอร์ใหม่ที่ช่วยควบคุมการปิดออเดอร์อย่างชาญฉลาดด้วย Take Profit และ Stop Loss thresholds

3. **Auto Web Scraping** - ระบบดึงสัญญาณอัตโนมัติจาก TradersUnion Gold Signals พร้อม fallback mechanism และ error handling

4. **Best Practices** - แนวทางปฏิบัติที่ดีจากประสบการณ์จริง พร้อม use cases และ scenarios ต่างๆ รวมถึง scraping strategies

5. **Complete Testing** - Checklist ครอบคลุมทุกกรณี รวมถึง edge cases, error handling, และ scraping validation

6. **Production Ready** - พร้อม deploy ใช้งานจริง พร้อมคำแนะนำ monitoring, optimization, และ hybrid operation modes

---

**🎉 ขอให้การ implement สำเร็จลุล่วง!**

*Document Version: 1.4*  
*Last Updated: January 2026*  
*Total Pages: ~110+ sections*  
*Implementation Time: 5-10 hours (ทั้งหมด)*

**Key Highlights:**
- ✅ Complete API integration with authorization
- ✅ Smart TP/SL diff close control
- ✅ Automated signal scraping from TradersUnion
- ✅ Flexible operation modes (full auto / hybrid / manual)
- ✅ Comprehensive error handling and logging
- ✅ Production-tested best practices
- ✅ Per-account config (cooldowns, version lock) via Authorization API

