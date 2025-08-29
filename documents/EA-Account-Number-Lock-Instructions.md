# EA Account Number Lock Implementation Instructions

## Overview
เพิ่มฟังก์ชั่นการ lock EA ด้วย Account Number ให้กับ Diff-Grabber.mq4 และ Diff-Grabber.mq5 โดยสามารถกำหนด account number ที่อนุญาตได้หลายเลขพร้อมกัน

## Implementation Requirements

### 1. Function Design Principles
- ใช้แค่ฟังก์ชั่นเท่านั้น ไม่ต้องสร้าง global variables ภายนอก
- ออกแบบให้หยิบใช้หรือถอดออกได้ง่าย (modular design)
- ไม่ส่งผลกระทบต่อ business logic หลักของ EA

### 2. Account Number Configuration
- **อนุญาตให้ใช้ได้หลาย account number พร้อมกัน**
- กำหนด account number ที่อนุญาตภายในฟังก์ชั่น
- ถ้า account number ไม่ตรงกับรายการที่อนุญาต EA จะหยุดทำงาน

### 3. Integration Points

#### 3.1 OnInit Function
```cpp
int OnInit()
{
   // เรียกใช้ฟังก์ชั่น lock ตรงนี้
   if(!CheckAccountLicense()) 
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
   static datetime last_account_check = 0;
   datetime current_time = TimeCurrent();
   
   // ตรวจสอบทุกๆ 1 ชั่วโมง (3600 วินาที)
   if(current_time - last_account_check >= 3600)
   {
      if(!CheckAccountLicense()) 
      {
         ExpertRemove(); // หยุด EA
         return;
      }
      last_account_check = current_time;
   }
   
   // ... existing OnTimer code ...
}
```

## Function Implementation

### Required Function: CheckAccountLicense()

```cpp
bool CheckAccountLicense()
{
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
   
   // ตรวจสอบว่า account ปัจจุบันอยู่ในรายการที่อนุญาตหรือไม่
   for(int i = 0; i < total_allowed; i++)
   {
      if(current_account == allowed_accounts[i])
      {
         // Account ถูกต้อง - อนุญาตให้ใช้งาน
         return true;
      }
   }
   
   // Account ไม่ได้รับอนุญาต
   Alert("EA License Error: Account ", current_account, " ไม่ได้รับอนุญาตให้ใช้งาน EA นี้");
   Print("Unauthorized Account Number: ", current_account);
   
   return false;
}
```

### Alternative Implementation with String Array (for very long account numbers)

```cpp
bool CheckAccountLicense()
{
   // รายการ Account Number ที่อนุญาตให้ใช้งาน (รูปแบบ string)
   string allowed_accounts[] = {
      "12345678",    // Account 1
      "87654321",    // Account 2
      "11111111",    // Account 3
      "22222222",    // Account 4
      "33333333"     // Account 5
      // เพิ่ม account number ได้ตามต้องการ
   };
   
   string current_account = IntegerToString(AccountNumber());
   int total_allowed = ArraySize(allowed_accounts);
   
   // ตรวจสอบว่า account ปัจจุบันอยู่ในรายการที่อนุญาตหรือไม่
   for(int i = 0; i < total_allowed; i++)
   {
      if(current_account == allowed_accounts[i])
      {
         // Account ถูกต้อง - อนุญาตให้ใช้งาน
         return true;
      }
   }
   
   // Account ไม่ได้รับอนุญาต
   Alert("EA License Error: Account ", current_account, " ไม่ได้รับอนุญาตให้ใช้งาน EA นี้");
   Print("Unauthorized Account Number: ", current_account);
   
   return false;
}
```

## Implementation Steps

### Step 1: Add Function to Both Files
1. เพิ่มฟังก์ชั่น `CheckAccountLicense()` ลงในไฟล์ Diff-Grabber.mq4
2. เพิ่มฟังก์ชั่น `CheckAccountLicense()` ลงในไฟล์ Diff-Grabber.mq5
3. **กำหนด account number ที่อนุญาตในฟังก์ชั่น**

### Step 2: Modify OnInit
1. เพิ่มการเรียกใช้ `CheckAccountLicense()` ใน OnInit
2. ถ้า account ไม่ได้รับอนุญาตให้ return INIT_FAILED

### Step 3: Modify OnTimer
1. เพิ่ม static variable สำหรับเก็บเวลาตรวจสอบครั้งล่าสุด
2. ตรวจสอบ account ทุกๆ 1 ชั่วโมง
3. ถ้า account ไม่ได้รับอนุญาตให้เรียก ExpertRemove()

## Configuration Guide

### Adding New Account Numbers
```cpp
// เพิ่ม account number ใหม่ในอาร์เรย์
int allowed_accounts[] = {
   12345678,    // Account เดิม
   87654321,    // Account เดิม
   99999999,    // Account ใหม่ที่เพิ่ม
   88888888     // Account ใหม่ที่เพิ่ม
};
```

### Removing Account Numbers
```cpp
// ลบ account number ที่ไม่ต้องการออกจากอาร์เรย์
int allowed_accounts[] = {
   12345678,    // เก็บไว้
   // 87654321, // ลบออก (comment หรือลบบรรทัด)
   99999999     // เก็บไว้
};
```

## Performance Considerations

### Timer Optimization
- ใช้ static variable เพื่อเก็บเวลาตรวจสอบครั้งล่าสุด
- ตรวจสอบทุกๆ 1 ชั่วโมง (3600 วินาที) เท่านั้น
- ไม่ส่งผลกระทบต่อ performance ของ business logic

### Memory Usage
- ไม่ใช้ global variables
- ใช้ static variables ภายในฟังก์ชั่นเท่านั้น
- Array size จำกัดตามจำนวน account ที่อนุญาต

### Array Performance
- Linear search O(n) - เหมาะสำหรับ account น้อยกว่า 100 เลข
- สำหรับ account จำนวนมาก ควรใช้ hash table หรือ binary search

## Testing Guidelines

### Test Cases
1. **Authorized Account**: ทดสอบด้วย account ที่อยู่ในรายการอนุญาต
2. **Unauthorized Account**: ทดสอบด้วย account ที่ไม่อยู่ในรายการ
3. **Multiple Accounts**: ทดสอบหลาย account ที่อนุญาต
4. **Timer Frequency**: ยืนยันว่าตรวจสอบทุกๆ 1 ชั่วโมงเท่านั้น

### Manual Testing
```cpp
// สำหรับทดสอบ - เพิ่ม account ปัจจุบันในรายการ
int current_test_account = AccountNumber();
Print("Current Account for Testing: ", current_test_account);
```

## Security Considerations

### Basic Protection
- ใช้ AccountNumber() function ของ MT4/MT5
- เปรียบเทียบ integer หรือ string แบบตรงไปตรงมา
- แสดงข้อความเตือนที่ชัดเจน

### Enhanced Security (Optional)
```cpp
bool CheckAccountLicense()
{
   // เพิ่มการเข้ารหัสแบบง่าย
   int allowed_accounts[] = {
      12345678 ^ 0xABCD,    // XOR encryption
      87654321 ^ 0xABCD,
      11111111 ^ 0xABCD
   };
   
   int current_account = AccountNumber() ^ 0xABCD;
   
   // ... rest of the function
}
```

## Maintenance Notes

### Easy Removal
- ลบฟังก์ชั่น `CheckAccountLicense()`
- ลบการเรียกใช้ใน OnInit และ OnTimer
- ไม่มี global variables ที่ต้องลบ

### Easy Modification
- เปลี่ยน account number ในอาร์เรย์ `allowed_accounts[]`
- เปลี่ยนความถี่การตรวจสอบใน OnTimer
- เปลี่ยนข้อความแจ้งเตือน

### Account Management
- เก็บรายการ account ในไฟล์แยก (advanced)
- ใช้ external file หรือ web service (advanced)
- Log การใช้งานของแต่ละ account

## Error Handling

### Common Issues
1. **Array Size**: ตรวจสอบ ArraySize() ให้ถูกต้อง
2. **Data Type**: ใช้ int หรือ string ให้สอดคล้องกัน
3. **Case Sensitivity**: string comparison ต้องตรงกัน

### Debug Information
```cpp
bool CheckAccountLicense()
{
   // เพิ่ม debug information
   int current_account = AccountNumber();
   Print("Debug: Current Account = ", current_account);
   
   int allowed_accounts[] = { /* ... */ };
   Print("Debug: Total Allowed Accounts = ", ArraySize(allowed_accounts));
   
   // ... rest of the function
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
- **อย่าลืมกำหนด account number ที่ถูกต้องในฟังก์ชั่น**
