# EA Account Number + Expiry Date Lock Implementation Instructions

## Overview
เพิ่มฟังก์ชั่นการ lock EA ด้วยทั้ง Account Number และ Expiry Date ให้กับ Diff-Grabber.mq4 และ Diff-Grabber.mq5 โดยสามารถกำหนด account number ที่อนุญาตได้หลายเลขพร้อมกัน และมีวันหมดอายุการใช้งาน

## Implementation Requirements

### 1. Function Design Principles
- ใช้แค่ฟังก์ชั่นเท่านั้น ไม่ต้องสร้าง global variables ภายนอก
- ออกแบบให้หยิบใช้หรือถอดออกได้ง่าย (modular design)
- ไม่ส่งผลกระทบต่อ business logic หลักของ EA

### 2. Dual Lock Configuration
- **Account Number Lock**: อนุญาตให้ใช้ได้หลาย account number พร้อมกัน
- **Expiry Date Lock**: กำหนดวันหมดอายุการใช้งาน
- **ต้องผ่านทั้งสองเงื่อนไข**: Account ถูกต้อง AND ยังไม่หมดอายุ

### 3. Integration Points

#### 3.1 OnInit Function
```cpp
int OnInit()
{
   // เรียกใช้ฟังก์ชั่น lock ตรงนี้
   if(!CheckAccountExpiryLicense()) 
   {
      return(INIT_FAILED);
   }
   
   // ... existing OnInit code ...
   
   return(INIT_SUCCEEDED);
}
```

#### 3.2 OnTimer Function
```cpp
void OnTimer()
{
   static datetime last_license_check = 0;
   datetime current_time = TimeCurrent();
   
   // ตรวจสอบทุกๆ 6 ชั่วโมง (21600 วินาที)
   if(current_time - last_license_check >= 21600)
   {
      if(!CheckAccountExpiryLicense()) 
      {
         ExpertRemove(); // หยุด EA
         return;
      }
      last_license_check = current_time;
   }
   
   // ... existing OnTimer code ...
}
```

## Function Implementation

### Required Function: CheckAccountExpiryLicense()

```cpp
bool CheckAccountExpiryLicense()
{
   // === ACCOUNT NUMBER VALIDATION ===
   // รายการ Account Number ที่อนุญาตให้ใช้งาน
   int allowed_accounts[] = {
      12345678,    // Account 1
      87654321,    // Account 2
      11111111,    // Account 3
      22222222,    // Account 4
      33333333     // Account 5
      // เพิ่ม account number ได้ตามต้องการ
   };
   
   int current_account = AccountNumber();
   int total_allowed = ArraySize(allowed_accounts);
   bool account_authorized = false;
   
   // ตรวจสอบ Account Number
   for(int i = 0; i < total_allowed; i++)
   {
      if(current_account == allowed_accounts[i])
      {
         account_authorized = true;
         break;
      }
   }
   
   if(!account_authorized)
   {
      Alert("EA License Error: Account ", current_account, " ไม่ได้รับอนุญาตให้ใช้งาน EA นี้");
      Print("Unauthorized Account Number: ", current_account);
      return false;
   }
   
   // === EXPIRY DATE VALIDATION ===
   // วันหมดอายุ: 30 พฤศจิกายน 2025
   datetime expiry_date = D'2025.11.30 23:59:59';
   datetime current_time = TimeCurrent();
   
   if(current_time > expiry_date)
   {
      Alert("EA License Expired! วันหมดอายุ: 30 พฤศจิกายน 2025");
      Print("EA License Expired on: 2025.11.30 for Account: ", current_account);
      return false;
   }
   
   // คำนวณวันที่เหลือ
   int days_remaining = (int)((expiry_date - current_time) / 86400);
   
   // แจ้งเตือนเมื่อเหลือ 7 วัน
   if(days_remaining <= 7 && days_remaining > 0)
   {
      Alert("EA License Warning: Account ", current_account, " เหลือเวลาใช้งาน ", days_remaining, " วัน");
   }
   
   // ผ่านทั้งสองเงื่อนไข
   return true;
}
```

### Alternative Implementation with Per-Account Expiry

```cpp
struct AccountLicense
{
   int account_number;
   datetime expiry_date;
};

bool CheckAccountExpiryLicense()
{
   // รายการ Account และวันหมดอายุแต่ละ Account
   AccountLicense allowed_licenses[] = {
      {12345678, D'2025.11.30 23:59:59'},    // Account 1 หมดอายุ 30 Nov 2025
      {87654321, D'2025.12.31 23:59:59'},    // Account 2 หมดอายุ 31 Dec 2025
      {11111111, D'2026.01.31 23:59:59'},    // Account 3 หมดอายุ 31 Jan 2026
      {22222222, D'2025.10.15 23:59:59'},    // Account 4 หมดอายุ 15 Oct 2025
      {33333333, D'2025.11.30 23:59:59'}     // Account 5 หมดอายุ 30 Nov 2025
   };
   
   int current_account = AccountNumber();
   datetime current_time = TimeCurrent();
   int total_licenses = ArraySize(allowed_licenses);
   
   // ค้นหา Account และตรวจสอบวันหมดอายุ
   for(int i = 0; i < total_licenses; i++)
   {
      if(current_account == allowed_licenses[i].account_number)
      {
         datetime account_expiry = allowed_licenses[i].expiry_date;
         
         if(current_time > account_expiry)
         {
            Alert("EA License Expired! Account ", current_account, " หมดอายุแล้ว");
            Print("Account ", current_account, " expired on: ", TimeToString(account_expiry));
            return false;
         }
         
         // คำนวณวันที่เหลือ
         int days_remaining = (int)((account_expiry - current_time) / 86400);
         
         // แจ้งเตือนเมื่อเหลือ 7 วัน
         if(days_remaining <= 7 && days_remaining > 0)
         {
            Alert("EA License Warning: Account ", current_account, " เหลือเวลาใช้งาน ", days_remaining, " วัน");
         }
         
         return true; // Account ถูกต้องและยังไม่หมดอายุ
      }
   }
   
   // Account ไม่อยู่ในรายการที่อนุญาต
   Alert("EA License Error: Account ", current_account, " ไม่ได้รับอนุญาตให้ใช้งาน EA นี้");
   Print("Unauthorized Account Number: ", current_account);
   return false;
}
```

## Implementation Steps

### Step 1: Add Function to Both Files
1. เพิ่มฟังก์ชั่น `CheckAccountExpiryLicense()` ลงในไฟล์ Diff-Grabber.mq4
2. เพิ่มฟังก์ชั่น `CheckAccountExpiryLicense()` ลงในไฟล์ Diff-Grabber.mq5
3. **กำหนด account number และวันหมดอายุในฟังก์ชั่น**

### Step 2: Add Struct (for Per-Account Expiry version)
```cpp
// เพิ่ม struct นี้ก่อนฟังก์ชั่น (ถ้าใช้ per-account expiry)
struct AccountLicense
{
   int account_number;
   datetime expiry_date;
};
```

### Step 3: Modify OnInit
1. เพิ่มการเรียกใช้ `CheckAccountExpiryLicense()` ใน OnInit
2. ถ้า license ไม่ผ่านให้ return INIT_FAILED

### Step 4: Modify OnTimer
1. เพิ่ม static variable สำหรับเก็บเวลาตรวจสอบครั้งล่าสุด
2. ตรวจสอบ license ทุกๆ 6 ชั่วโมง
3. ถ้า license ไม่ผ่านให้เรียก ExpertRemove()

## Configuration Guide

### Adding New Account with Expiry (Global Expiry Version)
```cpp
// เพิ่ม account ใหม่ในอาร์เรย์
int allowed_accounts[] = {
   12345678,    // Account เดิม
   87654321,    // Account เดิม
   99999999,    // Account ใหม่ที่เพิ่ม
   88888888     // Account ใหม่ที่เพิ่ม
};

// เปลี่ยนวันหมดอายุ (ใช้ร่วมกันทุก Account)
datetime expiry_date = D'2026.06.30 23:59:59'; // เปลี่ยนเป็น 30 June 2026
```

### Adding New Account with Individual Expiry (Per-Account Version)
```cpp
AccountLicense allowed_licenses[] = {
   {12345678, D'2025.11.30 23:59:59'},    // Account เดิม
   {87654321, D'2025.12.31 23:59:59'},    // Account เดิม
   {99999999, D'2026.03.15 23:59:59'},    // Account ใหม่ - หมดอายุ 15 Mar 2026
   {88888888, D'2026.06.30 23:59:59'}     // Account ใหม่ - หมดอายุ 30 Jun 2026
};
```

### Removing Account
```cpp
// ลบ account ที่ไม่ต้องการออกจากอาร์เรย์
AccountLicense allowed_licenses[] = {
   {12345678, D'2025.11.30 23:59:59'},    // เก็บไว้
   // {87654321, D'2025.12.31 23:59:59'}, // ลบออก (comment หรือลบบรรทัด)
   {99999999, D'2026.03.15 23:59:59'}     // เก็บไว้
};
```

## Performance Considerations

### Timer Optimization
- ใช้ static variable เพื่อเก็บเวลาตรวจสอบครั้งล่าสุด
- ตรวจสอบทุกๆ 6 ชั่วโมง (21600 วินาที) เท่านั้น
- ไม่ส่งผลกระทบต่อ performance ของ business logic

### Memory Usage
- ไม่ใช้ global variables
- ใช้ static variables ภายในฟังก์ชั่นเท่านั้น
- Struct array สำหรับ per-account expiry

### Search Performance
- Linear search O(n) - เหมาะสำหรับ account น้อยกว่า 50 เลข
- สำหรับ account จำนวนมาก ควรใช้ hash table

## Testing Guidelines

### Test Cases
1. **Authorized + Valid**: Account ถูกต้องและยังไม่หมดอายุ
2. **Authorized + Expired**: Account ถูกต้องแต่หมดอายุแล้ว
3. **Unauthorized + Valid**: Account ไม่ถูกต้องแต่ยังไม่หมดอายุ
4. **Unauthorized + Expired**: Account ไม่ถูกต้องและหมดอายุแล้ว
5. **Warning Period**: ทดสอบการแจ้งเตือนเมื่อเหลือ 7 วัน
6. **Timer Frequency**: ยืนยันว่าตรวจสอบทุกๆ 6 ชั่วโมงเท่านั้น

### Manual Testing
```cpp
// สำหรับทดสอบ - เปลี่ยนวันหมดอายุเป็นวันพรุ่งนี้
datetime expiry_date = TimeCurrent() + 86400; // +1 วัน

// หรือทดสอบ account ปัจจุบัน
int current_test_account = AccountNumber();
Print("Testing Account: ", current_test_account);
```

## Security Considerations

### Basic Protection
- ใช้ AccountNumber() และ TimeCurrent() functions ของ MT4/MT5
- เปรียบเทียบทั้ง integer และ datetime
- แสดงข้อความเตือนที่ชัดเจน

### Enhanced Security (Optional)
```cpp
bool CheckAccountExpiryLicense()
{
   // เพิ่มการเข้ารหัสแบบง่าย
   int key = 0xABCD1234;
   
   AccountLicense allowed_licenses[] = {
      {12345678 ^ key, (D'2025.11.30 23:59:59' ^ key)},
      {87654321 ^ key, (D'2025.12.31 23:59:59' ^ key)}
   };
   
   int current_account = AccountNumber() ^ key;
   datetime current_time = TimeCurrent() ^ key;
   
   // ... rest of the function with encrypted values
}
```

## Error Handling

### Common Issues
1. **Struct Definition**: ตรวจสอบ struct ถูกประกาศก่อนใช้งาน
2. **Array Size**: ตรวจสอบ ArraySize() ให้ถูกต้อง
3. **DateTime Format**: ใช้ D'YYYY.MM.DD HH:MM:SS' format
4. **Time Zone**: ตรวจสอบ server time vs local time

### Debug Information
```cpp
bool CheckAccountExpiryLicense()
{
   int current_account = AccountNumber();
   datetime current_time = TimeCurrent();
   
   Print("Debug: Current Account = ", current_account);
   Print("Debug: Current Time = ", TimeToString(current_time));
   Print("Debug: Total Licensed Accounts = ", ArraySize(allowed_licenses));
   
   // ... rest of the function
}
```

## Maintenance Notes

### Easy Removal
- ลบ struct `AccountLicense` (ถ้าใช้)
- ลบฟังก์ชั่น `CheckAccountExpiryLicense()`
- ลบการเรียกใช้ใน OnInit และ OnTimer

### Easy Modification
- เปลี่ยน account number และ expiry date ในอาร์เรย์
- เปลี่ยนความถี่การตรวจสอบใน OnTimer
- เปลี่ยนจำนวนวันแจ้งเตือน (ปัจจุบัน 7 วัน)

### License Management
- เก็บ license ในไฟล์แยก (advanced)
- ใช้ web service สำหรับ validation (advanced)
- Log การใช้งานพร้อม timestamp

## Advanced Features (Optional)

### Grace Period After Expiry
```cpp
// อนุญาตให้ใช้งานต่อได้ 3 วันหลังหมดอายุ
datetime grace_period = 3 * 86400; // 3 days
if(current_time > (account_expiry + grace_period))
{
   // หมดอายุจริงๆ
   return false;
}
```

### Soft Warning vs Hard Stop
```cpp
// Soft warning: แจ้งเตือนแต่ยังใช้งานได้
if(days_remaining <= 3 && days_remaining > 0)
{
   Alert("URGENT: License expires in ", days_remaining, " days!");
   // ยังคืน true ให้ใช้งานต่อได้
}
```

## File Locations
- **MQ4 File**: Diff-Grabber.mq4
- **MQ5 File**: Diff-Grabber.mq5
- **Both files** ต้องได้รับการแก้ไขเหมือนกัน

## Final Notes
- ทดสอบใน Strategy Tester ก่อนใช้งานจริง
- Backup ไฟล์เดิมก่อนแก้ไข
- ตรวจสอบ compilation ทั้ง MQ4 และ MQ5
- ยืนยันว่าไม่ส่งผลกระทบต่อ existing functionality
- **อย่าลืมกำหนด account number และวันหมดอายุที่ถูกต้อง**
- **ตรวจสอบ timezone ของ server ให้ตรงกับการตั้งค่า**
