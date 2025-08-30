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
-- Create accounts table
CREATE TABLE IF NOT EXISTS accounts (
    id SERIAL PRIMARY KEY,
    account_number VARCHAR(50) NOT NULL,
    account_name VARCHAR(255) NOT NULL,
    broker_name VARCHAR(255) NOT NULL,
    balance DECIMAL(15,2) NOT NULL,
    equity DECIMAL(15,2) NOT NULL,
    unit INTEGER NOT NULL DEFAULT 1,
    timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(account_number, timestamp)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_accounts_number ON accounts(account_number);
CREATE INDEX IF NOT EXISTS idx_accounts_timestamp ON accounts(timestamp);
CREATE INDEX IF NOT EXISTS idx_accounts_unit ON accounts(unit);

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

### **ปัญหา: PGRST202 – ไม่พบฟังก์ชัน RPC `public.get_account_summaries()`**
**อาการ:** API ตอบกลับ error `PGRST202` ว่าไม่พบฟังก์ชันใน schema cache

**สาเหตุ:** ยังไม่ได้สร้างฟังก์ชัน RPC ในฐานข้อมูล Supabase

**วิธีแก้ (รันใน Supabase SQL Editor):**
```sql
-- Remove if exists to ensure clean state
drop function if exists public.get_account_summaries();

-- Create RPC to fetch the latest record per account
create or replace function public.get_account_summaries()
returns table (
  account_number text,
  account_name   text,
  broker_name    text,
  latest_balance numeric,
  latest_equity  numeric,
  unit           integer,
  last_update    timestamptz
)
language sql
stable
as $$
  with ranked as (
    select
      a.account_number,
      a.account_name,
      a.broker_name,
      a.balance  as latest_balance,
      a.equity   as latest_equity,
      a.unit,
      a.timestamp as last_update,
      row_number() over (
        partition by a.account_number
        order by a.timestamp desc
      ) as rn
    from public.accounts a
  )
  select
    account_number,
    account_name,
    broker_name,
    latest_balance,
    latest_equity,
    unit,
    last_update
  from ranked
  where rn = 1
  order by broker_name, account_number;
$$;

-- Grant to API roles
grant execute on function public.get_account_summaries() to anon, authenticated;

-- Optional: refresh PostgREST schema cache immediately
notify pgrst, 'reload schema';
```

**ตรวจสอบเพิ่มเติม:**
- ตั้งค่า Environment Variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
- ตาราง `public.accounts` ต้องมีคอลัมน์: `account_number, account_name, broker_name, balance, equity, unit, timestamp`

## 🔄 **Data Migration:**

### **ข้อมูลเก่าจะหายไหม?**
- ✅ **ข้อมูลเก่าใน in-memory หายแล้ว** (เป็นเรื่องปกติ)
- ✅ **ข้อมูลใหม่จะไม่หายอีก** (เก็บใน Supabase)
- ✅ **EA จะส่งข้อมูลมาใหม่** (ภายใน 30 วินาที)

### **Timeline การเปลี่ยนแปลง:**
```
เดิม: EA → API → RAM → หายเมื่อ restart
ใหม่: EA → API → Supabase → เก็บถาวร
```

## 📈 **Monitoring & Analytics:**

### **ตรวจสอบข้อมูล:**
1. **Supabase Dashboard** → **Table Editor**
2. **SQL Editor** สำหรับ query ข้อมูล
3. **API Logs** ดู request/response

### **Query ตัวอย่าง:**
```sql
-- ดูข้อมูลล่าสุดของแต่ละ account
SELECT DISTINCT ON (account_number) 
    account_number, account_name, balance, equity, unit, timestamp
FROM accounts 
ORDER BY account_number, timestamp DESC;

-- นับจำนวน accounts ที่ active
SELECT COUNT(DISTINCT account_number) as active_accounts 
FROM accounts 
WHERE timestamp > NOW() - INTERVAL '5 minutes';

-- ดู unit mappings
SELECT * FROM settings WHERE setting_key = 'unit_mappings';
```

## 🎉 **สรุป:**
ตอนนี้ระบบใช้ **Supabase PostgreSQL** แล้ว ข้อมูลจะไม่หายอีกต่อไป! 🚀

**Next Steps:**
1. ตั้งค่า Supabase project
2. รัน SQL commands
3. เพิ่ม environment variables  
4. Deploy และทดสอบ

