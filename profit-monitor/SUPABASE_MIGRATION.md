# 🚀 Supabase Migration Guide

## ✅ **สถานะปัจจุบัน:**
โปรเจคได้เปลี่ยนจาก **in-memory storage** เป็น **Supabase** แล้ว!

## 🔧 **ขั้นตอนการตั้งค่า:**

### 1. **สร้าง Supabase Project**
1. ไปที่ [supabase.com](https://supabase.com)
2. สร้าง project ใหม่
3. รอให้ project setup เสร็จ

### 2. **สร้าง Database Tables**
ไปที่ **SQL Editor** ใน Supabase Dashboard และรัน:

```sql
-- Create accounts table (Final Schema - One Row Per Account)
CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    account_number VARCHAR(50) NOT NULL UNIQUE,
    account_name VARCHAR(255) NOT NULL,
    broker_name VARCHAR(255) NOT NULL,
    balance DECIMAL(15,2) NOT NULL,
    equity DECIMAL(15,2) NOT NULL,
    unit INTEGER NOT NULL DEFAULT 1,
    timestamp TIMESTAMPTZ NOT NULL,
    position_side VARCHAR(10) DEFAULT 'UNKNOWN',
    position_price DECIMAL(15,5) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX idx_accounts_number ON accounts(account_number);
CREATE INDEX idx_accounts_timestamp ON accounts(timestamp);
CREATE INDEX idx_accounts_unit ON accounts(unit);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON accounts
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create settings table
CREATE TABLE IF NOT EXISTS settings (
    setting_key VARCHAR(50) PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default settings
INSERT INTO settings (setting_key, setting_value) VALUES 
('initial_capital', '60000'),
('capital_per_unit', '7500'),
('total_active_accounts', '16'),
('access_pin', '250514'),
('unit_mappings', '{"1":"neex-sell","2":"neex-buy","3":"neex-avg-sell","4":"neex-avg-buy","5":"xs-sell","6":"xs-buy","7":"xs-avg-sell","8":"xs-avg-buy"}')
ON CONFLICT (setting_key) DO NOTHING;
```

### 3. **หา API Keys**
1. ไปที่ **Settings** → **API**
2. คัดลอก:
   - **Project URL** (เช่น `https://abcdefg.supabase.co`)
   - **anon/public key** (จาก Legacy API Keys section)

### 4. **ตั้งค่า Environment Variables**

#### **Local Development:**
สร้างไฟล์ `.env.local`:
```bash
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

#### **Vercel Deployment:**
1. ไปที่ Vercel Dashboard
2. เลือก project → **Settings** → **Environment Variables**
3. เพิ่ม:
   - `SUPABASE_URL` = `https://your-project-id.supabase.co`
   - `SUPABASE_ANON_KEY` = `your-anon-key`

### 5. **Deploy**
```bash
yarn build
# หรือ deploy ผ่าน Vercel
```

## 🎯 **ประโยชน์ที่ได้:**

### ✅ **ข้อมูลไม่หายแล้ว!**
- ✅ **Persistent Storage**: ข้อมูลเก็บใน PostgreSQL
- ✅ **No More Data Loss**: ไม่หายเมื่อ restart server
- ✅ **Backup & Recovery**: Supabase มี backup อัตโนมัติ
- ✅ **Scalable**: รองรับข้อมูลจำนวนมาก

### 🔄 **โครงสร้างใหม่ - One Row Per Account**
- ✅ **ประหยัดพื้นที่**: แต่ละ account_number มีแค่ row เดียว
- ✅ **UPSERT Logic**: ข้อมูลใหม่อัพเดทแทนการสร้าง row ใหม่
- ✅ **Auto Timestamp**: `updated_at` อัพเดทอัตโนมัติเมื่อมีการแก้ไข
- ✅ **Position Tracking**: เพิ่ม `lastPositionSide` และ `lastPositionEntryPrice`

### 📊 **Performance Improvements**
- ✅ **Real-time Updates**: Supabase รองรับ real-time
- ✅ **Indexed Queries**: ค้นหาเร็วขึ้นด้วย database indexes
- ✅ **Connection Pooling**: จัดการ connection อัตโนมัติ

### 🔒 **Security & Reliability**
- ✅ **Row Level Security**: ความปลอดภัยระดับแถว
- ✅ **SSL Encryption**: เข้ารหัสการเชื่อมต่อ
- ✅ **99.9% Uptime**: เสถียรภาพสูง

## 🐛 **แก้ปัญหาที่เกิดขึ้น:**

### **ปัญหา: Account หาย 16 → 13**
**สาเหตุเดิม (In-memory):**
```
EA ส่งข้อมูล → RAM → Server restart → ข้อมูลหาย
```

**แก้แล้ว (Supabase):**
```
EA ส่งข้อมูล → PostgreSQL → Server restart → ข้อมูลยังอยู่
```

### **ปัญหา: ข้อมูลหายเมื่อ Deploy**
**สาเหตุเดิม:**
- In-memory storage เก็บข้อมูลใน RAM
- Deploy ใหม่ = เริ่มต้นใหม่

**แก้แล้ว:**
- Supabase เก็บข้อมูลใน database
- Deploy กี่ครั้งก็ไม่หาย


## 🔄 **Data Migration:**

### **ข้อมูลเก่าจะหายไหม?**
- ✅ **ข้อมูลเก่าใน in-memory หายแล้ว** (เป็นเรื่องปกติ)
- ✅ **ข้อมูลใหม่จะไม่หายอีก** (เก็บใน Supabase)
- ✅ **EA จะส่งข้อมูลมาใหม่** (ภายใน 30 วินาที)

### **Timeline การเปลี่ยนแปลง:**
```
เดิม: EA → API → RAM → หายเมื่อ restart
      (หลาย rows ต่อ account)

ใหม่: EA → API → Supabase → เก็บถาวร
      (1 row ต่อ account, UPSERT อัพเดท)
```

### **🔄 การเปลี่ยนแปลงสำคัญ:**

#### **เดิม (Multiple Rows):**
```sql
-- เก็บหลาย rows ต่อ account_number
account_number | timestamp           | balance
123456        | 2024-01-01 10:00:00 | 5000
123456        | 2024-01-01 10:05:00 | 5100  
123456        | 2024-01-01 10:10:00 | 5200
```

#### **ใหม่ (Single Row + UPSERT):**
```sql
-- เก็บแค่ row เดียว อัพเดทเมื่อมีข้อมูลใหม่
account_number | timestamp           | balance | updated_at
123456        | 2024-01-01 10:10:00 | 5200    | 2024-01-01 10:10:00
```

## 📈 **Monitoring & Analytics:**

### **ตรวจสอบข้อมูล:**
1. **Supabase Dashboard** → **Table Editor**
2. **SQL Editor** สำหรับ query ข้อมูล
3. **API Logs** ดู request/response

### **Query ตัวอย่าง:**
```sql
-- ดูข้อมูลทั้งหมด (แต่ละ account มีแค่ row เดียว)
SELECT account_number, account_name, balance, equity, unit, timestamp, 
       position_side, position_price, updated_at
FROM accounts 
ORDER BY broker_name, account_number;

-- นับจำนวน accounts ที่ active
SELECT COUNT(*) as active_accounts 
FROM accounts 
WHERE timestamp > NOW() - INTERVAL '5 minutes';

-- ดู accounts ที่มีการเทรด (balance != equity)
SELECT account_number, account_name, balance, equity, 
       (balance - equity) as floating_pnl,
       position_side, position_price
FROM accounts 
WHERE ABS(balance - equity) > 0.01;

-- ดู unit mappings และ settings อื่นๆ
SELECT * FROM settings WHERE setting_key IN ('unit_mappings', 'initial_capital', 'access_pin');

-- ตรวจสอบข้อมูลที่อัพเดทล่าสุด
SELECT account_number, timestamp, updated_at,
       EXTRACT(EPOCH FROM (NOW() - updated_at)) as seconds_since_update
FROM accounts 
ORDER BY updated_at DESC;
```

## 🎉 **สรุป:**
ตอนนี้ระบบใช้ **Supabase PostgreSQL** แล้ว ข้อมูลจะไม่หายอีกต่อไป! 🚀

### **🔧 การปรับปรุงล่าสุด:**
- ✅ **One Row Per Account**: ประหยัดพื้นที่ฐานข้อมูล
- ✅ **UPSERT Logic**: อัพเดทข้อมูลแทนการสร้างใหม่
- ✅ **Position Tracking**: ติดตาม position_side และ position_price
- ✅ **Auto Timestamps**: updated_at อัพเดทอัตโนมัติ
- ✅ **Simplified Schema**: ใช้ชื่อคอลัมน์ที่ง่ายและชัดเจน

**Next Steps:**
1. ตั้งค่า Supabase project
2. รัน SQL commands ตามโครงสร้างล่าสุด
3. เพิ่ม environment variables  
4. Deploy และทดสอบ

### **⚠️ Migration Notes:**
- ใช้โครงสร้างตารางล่าสุดที่ระบุไว้ข้างต้น
- EA จะส่งข้อมูลมาใหม่อัตโนมัติ
- ระบบจะทำงานแบบ real-time update

