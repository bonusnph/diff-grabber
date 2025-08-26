# EA Lock Function Implementation Instructions

## Overview
เพิ่มฟังก์ชั่นการ lock EA ด้วย expiredAt ให้กับ Diff-Grabber.mq4 และ Diff-Grabber.mq5 โดยตั้งให้หมดอายุในวันที่ 30-11-2025

## Implementation Requirements

### 1. Function Design Principles
- ใช้แค่ฟังก์ชั่นเท่านั้น ไม่ต้องสร้าง global variables ภายนอก
- ออกแบบให้หยิบใช้หรือถอดออกได้ง่าย (modular design)
- ไม่ส่งผลกระทบต่อ business logic หลักของ EA

### 2. Expiration Date
- **วันหมดอายุ: 30 พฤศจิกายน 2025**
- เมื่อหมดอายุให้ EA หยุดทำงานและแสดงข้อความแจ้งเตือน

### 3. Integration Points

#### 3.1 OnInit Function
```cpp
int OnInit()
{
   // เรียกใช้ฟังก์ชั่น lock ตรงนี้
   if(!CheckEALicense()) 
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
   
   // ตรวจสอบทุกๆ 12 ชั่วโมง (43200 วินาที)
   if(current_time - last_license_check >= 43200)
   {
      if(!CheckEALicense()) 
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

### Required Function: CheckEALicense()

```cpp
bool CheckEALicense()
{
   // วันหมดอายุ: 30 พฤศจิกายน 2025
   datetime expiry_date = D'2025.11.30 23:59:59';
   datetime current_time = TimeCurrent();
   
   if(current_time > expiry_date)
   {
      Alert("EA License Expired! วันหมดอายุ: 30 พฤศจิกายน 2025");
      Print("EA License Expired on: 2025.11.30");
      return false;
   }
   
   // คำนวณวันที่เหลือ
   int days_remaining = (int)((expiry_date - current_time) / 86400);
   
   // แจ้งเตือนเมื่อเหลือ 7 วัน
   if(days_remaining <= 7 && days_remaining > 0)
   {
      Alert("EA License Warning: เหลือเวลาใช้งาน ", days_remaining, " วัน");
   }
   
   return true;
}
```

## Implementation Steps

### Step 1: Add Function to Both Files
1. เพิ่มฟังก์ชั่น `CheckEALicense()` ลงในไฟล์ Diff-Grabber.mq4
2. เพิ่มฟังก์ชั่น `CheckEALicense()` ลงในไฟล์ Diff-Grabber.mq5

### Step 2: Modify OnInit
1. เพิ่มการเรียกใช้ `CheckEALicense()` ใน OnInit
2. ถ้า license หมดอายุให้ return INIT_FAILED

### Step 3: Modify OnTimer
1. เพิ่ม static variable สำหรับเก็บเวลาตรวจสอบครั้งล่าสุด
2. ตรวจสอบ license ทุกๆ 12 ชั่วโมง
3. ถ้า license หมดอายุให้เรียก ExpertRemove()

## Performance Considerations

### Timer Optimization
- ใช้ static variable เพื่อเก็บเวลาตรวจสอบครั้งล่าสุด
- ตรวจสอบทุกๆ 12 ชั่วโมง (43200 วินาที) เท่านั้น
- ไม่ส่งผลกระทบต่อ performance ของ business logic

### Memory Usage
- ไม่ใช้ global variables
- ใช้ static variables ภายในฟังก์ชั่นเท่านั้น
- Minimal memory footprint

## Testing Guidelines

### Test Cases
1. **Normal Operation**: ทดสอบการทำงานปกติก่อนวันหมดอายุ
2. **Warning Period**: ทดสอบการแจ้งเตือนเมื่อเหลือ 7 วัน
3. **Expiry Date**: ทดสอบการหยุดทำงานหลังวันหมดอายุ
4. **Timer Frequency**: ยืนยันว่าตรวจสอบทุกๆ 12 ชั่วโมงเท่านั้น

### Manual Testing
```cpp
// สำหรับทดสอบ - เปลี่ยนวันหมดอายุเป็นวันพรุ่งนี้
datetime expiry_date = TimeCurrent() + 86400; // +1 วัน
```

## Maintenance Notes

### Easy Removal
- ลบฟังก์ชั่น `CheckEALicense()`
- ลบการเรียกใช้ใน OnInit และ OnTimer
- ไม่มี global variables ที่ต้องลบ

### Easy Modification
- เปลี่ยนวันหมดอายุในฟังก์ชั่น `CheckEALicense()`
- เปลี่ยนความถี่การตรวจสอบใน OnTimer
- เปลี่ยนข้อความแจ้งเตือน

## Security Considerations

### Basic Protection
- ใช้ datetime comparison แทน string comparison
- เก็บวันหมดอายุในรูปแบบ timestamp
- แสดงข้อความเตือนที่ชัดเจน

### Advanced Protection (Optional)
- เพิ่ม checksum validation
- เพิ่ม server-side validation
- เพิ่ม hardware fingerprinting

## File Locations
- **MQ4 File**: Diff-Grabber.mq4
- **MQ5 File**: Diff-Grabber.mq5
- **Both files** ต้องได้รับการแก้ไขเหมือนกัน

## Final Notes
- ทดสอบใน Strategy Tester ก่อนใช้งานจริง
- Backup ไฟล์เดิมก่อนแก้ไข
- ตรวจสอบ compilation ทั้ง MQ4 และ MQ5
- ยืนยันว่าไม่ส่งผลกระทบต่อ existing functionality
