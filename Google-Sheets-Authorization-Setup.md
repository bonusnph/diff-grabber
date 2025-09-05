# คู่มือการตั้งค่า Google Sheets สำหรับระบบอนุญาตบัญชี EA

## ภาพรวม

คู่มือนี้อธิบายวิธีการตั้งค่า Google Sheets สำหรับระบบอนุญาตบัญชี EA ระบบนี้ช่วยให้คุณสามารถควบคุมว่าบัญชีเทรดไหนบ้างที่สามารถใช้ EA ได้ และกำหนดวันหมดอายุสำหรับแต่ละบัญชี

## ขั้นตอนที่ 1: สร้าง Google Sheets

### 1.1 สร้าง Google Sheet ใหม่

1. ไปที่ [Google Sheets](https://sheets.google.com)
2. คลิก "สร้าง" → "สเปรดชีตเปล่า"
3. ตั้งชื่อชีตของคุณ (เช่น "EA Account Authorization")

### 1.2 ตั้งค่าโครงสร้างข้อมูล

สร้างชีตที่มีคอลัมน์ดังต่อไปนี้:

| คอลัมน์ A | คอลัมน์ B |
|----------|----------|
| account  | expires_at |
| 12345678 | 2025.12.31 |
| 87654321 | 2025.06.30 |
| 11223344 | 2025.03.15 |

**คำอธิบายคอลัมน์:**
- **คอลัมน์ A (account)**: หมายเลขบัญชี MT4/MT5
- **คอลัมน์ B (expires_at)**: วันหมดอายุในรูปแบบ **YYYY.MM.DD** (เช่น 2025.12.31)

### 1.3 ตัวอย่างข้อมูล

```
account,expires_at
12345678,2025.12.31
87654321,2025.06.30
11223344,2025.03.15
55667788,2026.01.01
```

## ขั้นตอนที่ 2: สร้าง Google Apps Script API (แนะนำ)

### 2.1 สร้าง Google Apps Script

1. ไปที่ [Google Apps Script](https://script.google.com)
2. คลิก "โครงการใหม่"
3. ตั้งชื่อโครงการ (เช่น "EA Authorization API")

### 2.2 เขียนโค้ด Apps Script

แทนที่โค้ดเริ่มต้นด้วย:

```javascript
function doGet(e) {
  try {
    // เปิด Google Sheet โดยใช้ ID
    const SHEET_ID = 'YOUR_SHEET_ID_HERE'; // แทนที่ด้วย Sheet ID จริง
    const sheet = SpreadsheetApp.openById(SHEET_ID).getActiveSheet();
    
    // อ่านข้อมูลทั้งหมด
    const data = sheet.getDataRange().getValues();
    
    // แปลงเป็น CSV format
    let csvContent = '';
    for (let i = 0; i < data.length; i++) {
      csvContent += data[i].join(',') + '\n';
    }
    
    // ส่งกลับเป็น CSV
    return ContentService
      .createTextOutput(csvContent)
      .setMimeType(ContentService.MimeType.TEXT);
      
  } catch (error) {
    // ส่งกลับ error ในรูปแบบ CSV
    return ContentService
      .createTextOutput('error,message\n1,' + error.toString())
      .setMimeType(ContentService.MimeType.TEXT);
  }
}

// ฟังก์ชันสำหรับตรวจสอบสิทธิ์ขั้นสูง (ไม่บังคับ)
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const account = data.account;
    
    // ตรวจสอบ account ใน sheet
    const SHEET_ID = 'YOUR_SHEET_ID_HERE';
    const sheet = SpreadsheetApp.openById(SHEET_ID).getActiveSheet();
    const values = sheet.getDataRange().getValues();
    
    for (let i = 1; i < values.length; i++) { // เริ่มจากแถว 2 (ข้าม header)
      if (values[i][0] == account) {
        const expires = values[i][1];
        return ContentService
          .createTextOutput(JSON.stringify({
            authorized: true,
            account: account,
            expires_at: expires
          }))
          .setMimeType(ContentService.MimeType.JSON);
      }
    }
    
    return ContentService
      .createTextOutput(JSON.stringify({
        authorized: false,
        account: account,
        error: 'Account not found'
      }))
      .setMimeType(ContentService.MimeType.JSON);
      
  } catch (error) {
    return ContentService
      .createTextOutput(JSON.stringify({
        authorized: false,
        error: error.toString()
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }
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
```
account,expires_at
502523729,2025.12.31
```

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

1. เปิด Web app URL ในเว็บเบราว์เซอร์
2. คุณควรเห็นข้อมูล CSV เช่น:
   ```
   account,expires_at
   12345678,2025.12.31
   87654321,2025.06.30
   ```

**🧪 ทดสอบกับตัวอย่างจริง:**
- เปิด URL: https://script.google.com/macros/s/AKfycbwu4NytwY2ycRFsonoyEJFJICqT-ooS6Wszb5LTY3PEysF1hxXMEZ0ThgAlzUlCZr1gdg/exec
- ผลลัพธ์ที่ได้:
  ```
  account,expires_at
  502523729,2025.12.31
  ```

### 5.2 ทดสอบการเข้าถึง CSV (วิธีเดิม)

1. เปิด CSV export URL ในเว็บเบราว์เซอร์
2. คุณควรเห็นข้อมูล CSV เช่น:
   ```
   account,expires_at
   12345678,2025.12.31
   87654321,2025.06.30
   ```

### 5.3 ทดสอบการอนุญาต EA

1. แนบ EA กับชาร์ตโดยเปิดใช้งานการอนุญาต
2. ตรวจสอบแท็บ Expert สำหรับข้อความการอนุญาต:
   - `[AUTH] Checking account authorization...`
   - `[AUTH] Account XXXXX authorized (expires: YYYY.MM.DD)`

## ขั้นตอนที่ 6: การจัดการบัญชี

### 6.1 การเพิ่มบัญชีใหม่

1. เปิด Google Sheet ของคุณ
2. เพิ่มแถวใหม่พร้อมหมายเลขบัญชีและวันหมดอายุ
3. การเปลี่ยนแปลงจะมีผลภายใน 24 ชั่วโมง (หรือรีสตาร์ท EA เพื่อให้มีผลทันที)

### 6.2 การลบบัญชี

1. ลบแถวที่มีหมายเลขบัญชีนั้น
2. หรือตั้งวันหมดอายุเป็นวันที่ผ่านมาแล้ว

### 6.3 การขยายวันหมดอายุ

1. อัปเดตคอลัมน์ expires_at ด้วยวันที่ใหม่
2. ใช้รูปแบบ **YYYY.MM.DD** (เช่น 2025.12.31)

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

**การเพิ่ม Authentication:**
```javascript
function doGet(e) {
  // ตรวจสอบ API key (ไม่บังคับ)
  const apiKey = e.parameter.key;
  if (apiKey !== 'YOUR_SECRET_API_KEY') {
    return ContentService
      .createTextOutput('error,message\n1,Unauthorized')
      .setMimeType(ContentService.MimeType.TEXT);
  }
  
  // โค้ดเดิม...
}
```

**การ Log การเข้าถึง:**
```javascript
function doGet(e) {
  // Log การเข้าถึง
  const timestamp = new Date();
  const userAgent = e.parameter.userAgent || 'Unknown';
  
  Logger.log(`Access at ${timestamp} from ${userAgent}`);
  
  // โค้ดเดิม...
}
```

### 9.2 หลายชีต

คุณสามารถใช้ชีตที่แตกต่างกันสำหรับ EA instances ที่แตกต่างกันโดยใช้ค่า `gid` ที่แตกต่างกัน:

- ชีต 1: `gid=0`
- ชีต 2: `gid=123456789`

### 9.3 คอลัมน์เพิ่มเติม

คุณสามารถเพิ่มคอลัมน์เพิ่มเติมสำหรับการจัดทำเอกสาร (จะถูกละเว้นโดย EA):

| account | expires_at | trader_name | notes |
|---------|------------|-------------|-------|
| 12345678 | 2025.12.31 | นาย ก | ลูกค้า VIP |

### 9.4 กลยุทธ์การสำรองข้อมูล

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
