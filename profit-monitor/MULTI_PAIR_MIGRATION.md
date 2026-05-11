# Multi-Pair Orders Feature — Migration & Setup Guide

คู่มือเตรียมการก่อนใช้ฟีเจอร์ **Multi-Pair Orders** ที่ EA จะส่ง order list ทั้งหมดที่กำลังเปิดอยู่ และ Dashboard จะจับคู่อัตโนมัติแบบ multi-pair ภายใน 1 unit

---

## ภาพรวมการเปลี่ยนแปลง

| ส่วน | เดิม | ใหม่ |
|------|------|------|
| EA | ส่งเฉพาะ position ล่าสุด (`lastPositionSide`, `lastPositionEntryPrice`, `lastSize`) | ส่ง `orders[]` ทุก position ที่เปิดอยู่ พร้อม `symbol`, `side`, `price`, `lots`, `openTime` |
| DB | คอลัมน์ `position_side`, `position_price`, `position_size` | เพิ่มคอลัมน์ `position_orders` (JSONB) |
| Webhook | รับเฉพาะฟิลด์เดี่ยว | รับ + sanitize `orders[]` พร้อม backfill ฟิลด์เดิม |
| Dashboard | แสดง 1 pair / unit | จับคู่หลายคู่ใน 1 unit จาก `openTime` ห่างกัน ≤ 10 วินาที |

> Backward compatible: ถ้า EA เก่ายังไม่อัปเดต ระบบยังใช้งานได้ตามเดิม (fallback แสดง pair เดียว)

---

## ขั้นตอนการเตรียมการ

### Step 1 — Migrate Supabase Database

ไปที่ **Supabase Dashboard → SQL Editor** แล้วรันคำสั่งนี้:

```sql
ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS position_orders JSONB DEFAULT '[]'::jsonb;
```

**ตรวจสอบว่า migrate สำเร็จ:**

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'accounts' AND column_name = 'position_orders';
```

ผลลัพธ์ที่ควรได้:

| column_name      | data_type | column_default |
|------------------|-----------|----------------|
| position_orders  | jsonb     | '[]'::jsonb    |

> ⚠️ ถ้ายังไม่ได้ migrate ระบบจะยังทำงานได้ (มี fallback อัตโนมัติ) แต่จะไม่เห็น multi-pair จนกว่าจะรัน SQL ข้างต้น

---

### Step 2 — Deploy Backend / Frontend

```bash
# build แล้ว deploy ตามปกติ (เช่น Vercel)
yarn build
```

ไม่ต้องแก้ env variable ใหม่ — ใช้ `SUPABASE_URL` / `SUPABASE_ANON_KEY` เดิม

---

### Step 3 — อัปเดต EA ทุกบัญชี

1. คัดลอกไฟล์ใหม่:
   - `ProfitMonitor-MT4.mq4` → MetaTrader 4 `MQL4/Experts/`
   - `ProfitMonitor-MT5.mq5` → MetaTrader 5 `MQL5/Experts/`
2. เปิด **MetaEditor** → กด **Compile** (`F7`)
3. ใน Terminal MT4/MT5: คลิกขวาที่กราฟ → **Expert Advisors → Refresh**
4. เปิด properties ของ EA → ตรวจสอบว่า version แสดง **`1.02`**
5. กด OK เพื่อรีโหลด EA

> ไม่ต้องแก้ input parameters เดิม (`API_URL`, `SendInterval`, `Unit`) — ใช้ค่าเดิมได้เลย

---

### Step 4 — ตรวจสอบว่าข้อมูลส่งมาครบ

#### 4.1 ที่ Supabase

```sql
SELECT
  account_number,
  unit,
  position_side,
  position_size,
  jsonb_array_length(position_orders) AS open_orders_count,
  position_orders
FROM accounts
WHERE position_orders IS NOT NULL
  AND jsonb_array_length(position_orders) > 0
ORDER BY unit, account_number;
```

ตัวอย่าง `position_orders`:

```json
[
  {
    "symbol": "XAUUSD",
    "side": "BUY",
    "price": 2050.45,
    "lots": 0.10,
    "openTime": "2026-05-01T22:15:33+07:00"
  },
  {
    "symbol": "XAUUSD",
    "side": "BUY",
    "price": 2051.20,
    "lots": 0.10,
    "openTime": "2026-05-01T22:18:07+07:00"
  }
]
```

#### 4.2 ที่ Dashboard

- หัวของแต่ละ unit จะแสดง badge: `N pairs · X.XXL` (สีน้ำเงิน/ม่วง)
- ใต้หัว unit จะมีแถว chip รายคู่ เช่น `#1 +12 · 0.10L`, `#2 -5 · 0.20L`
- เมื่อกด expand จะเห็นตารางรายคู่: `Symbol / BUY Price / SELL Price / Diff (pts) / Lots / Open Time`

---

## หลักการจับคู่ (Pairing Logic)

ภายใน **1 unit** เท่านั้น (ข้าม unit ไม่จับคู่กัน):

1. รวบรวม order ทั้งหมดจากทุกบัญชีในกลุ่ม unit แยกเป็น BUY list และ SELL list
2. เรียงตาม `openTime` (ascending)
3. ไล่จากแต่ละ BUY → หา SELL ที่ยังไม่ถูกจับคู่ และ `|openTime_BUY - openTime_SELL| ≤ 10,000 ms`
4. เลือก SELL ที่เวลาห่างน้อยที่สุด (greedy nearest)
5. คำนวณ:
   - `diff = sellPrice - buyPrice`
   - `diffPoints = diff × 100` (สำหรับ instrument ราคาแบบ gold/forex)
   - `lots = (buyLots + sellLots) / 2`
6. Order ที่จับคู่ไม่สำเร็จจะถูกแสดงเป็น **solo** (badge สีเหลือง)

### กรณีพิเศษ
- ถ้าเปิด BUY/SELL ห่างกันเกิน 10 วินาที → ถือเป็น 2 ออเดอร์เดี่ยว (solo)
- ถ้ามี BUY 2 ตัว เปิดใกล้เคียง SELL 1 ตัว → BUY ที่ openTime ใกล้กว่าจะถูกจับคู่ก่อน อีก BUY กลายเป็น solo

> ปรับค่า window ได้ที่ตัวแปร `PAIR_WINDOW_MS` ใน `src/routes/+page.svelte`

---

## Time Sync (สำคัญ!)

EA จะปรับเวลา `OrderOpenTime` / `POSITION_TIME` (ซึ่งเป็น broker server time) → **GMT+7** ก่อนส่งเสมอ:

```mql
int brokerOffsetSeconds = (int)(TimeCurrent() - TimeGMT());
datetime openTimeUtc    = openTime - brokerOffsetSeconds;
string openTimeStr      = CreateGMT7Timestamp(openTimeUtc);
```

ทำให้บัญชีที่ใช้ broker คนละ time zone (เช่น GMT+0, GMT+2, GMT+3) ส่ง `openTime` ที่เป็น absolute time เดียวกัน → จับคู่ได้ถูกต้อง

> ถ้า broker ใดเวลาเพี้ยนมาก (เช่น เครื่อง VPS เวลาเพี้ยน) ให้ตรวจ system clock ของเครื่อง MT ที่รัน EA

---

## Troubleshooting

### Dashboard ยังไม่เห็น pair

1. ตรวจ EA version ต้องเป็น `1.02` ขึ้นไป (เปิด properties → tab Common)
2. เช็ค `position_orders` ใน Supabase ว่ามีข้อมูล (ดู query Step 4.1)
3. ถ้า column ยัง not exist → กลับไปทำ Step 1
4. รอ EA tick ครบ `SendInterval` (default 10 วินาที) แล้วกด refresh ที่ dashboard

### มี order solo เยอะผิดปกติ

- ตรวจว่าเวลา PC ของแต่ละเครื่อง MT ตรงกันหรือไม่ (เปิด BUY/SELL กดพร้อมกัน แต่เวลาเครื่องห่างกัน 30 วิ ก็จับคู่ไม่ติด)
- ถ้าจงใจเปิดห่างเกิน 10 วินาที → เพิ่มค่า `PAIR_WINDOW_MS` (หน่วย ms) ในไฟล์ `src/routes/+page.svelte`

### Webhook log error เกี่ยวกับ `position_orders`

- หมายความว่ายังไม่ได้รัน `ALTER TABLE` → กลับไปทำ Step 1 — โค้ดมี fallback แต่จะไม่บันทึก orders ลง DB จนกว่าจะมีคอลัมน์

### EA แจ้ง `WebRequest failed`

- ตรวจที่ MetaTrader: **Tools → Options → Expert Advisors** → ติ๊ก *Allow WebRequest for listed URL* และเพิ่ม URL ของ webhook

---

## Rollback (ถ้าต้องการเลิกใช้ฟีเจอร์)

ฟีเจอร์นี้ไม่ break ของเดิม สามารถ rollback ได้ปลอดภัย โดยมี **3 ระดับ** เลือกตามความเหมาะสม

### Level 1 — Soft Disable (ไม่แก้ DB, ไม่แก้โค้ด)

วิธีที่ปลอดภัยและเร็วที่สุด — เก็บ schema และ code ไว้เหมือนเดิม แค่หยุดส่ง orders จาก EA

1. Downgrade EA กลับเป็นเวอร์ชัน `1.01`:
   ```bash
   git checkout <commit-ก่อน-multi-pair> -- ProfitMonitor-MT4.mq4 ProfitMonitor-MT5.mq5
   ```
2. Recompile แล้ว reload EA ทุกเครื่อง
3. EA จะส่งเฉพาะฟิลด์เดิม → field `orders` จะเป็น `[]` ใน webhook
4. Dashboard จะ fallback แสดงผลแบบ pair เดียว (single position) เหมือนเดิมอัตโนมัติ
5. (ออปชัน) เคลียร์ข้อมูล orders เก่าใน DB:
   ```sql
   UPDATE accounts SET position_orders = '[]'::jsonb;
   ```

> เหมาะกับการ pause ชั่วคราวเพื่อทดสอบ — สามารถกลับมาใช้งานได้ทันทีโดยอัปเดต EA กลับเป็น 1.02

---

### Level 2 — Code Rollback (ย้อน frontend/backend แต่เก็บ DB)

ถ้าต้องการให้ Dashboard กลับเป็น UI เดิม 100% (ไม่มี badge `N pairs` / pair table)

1. ทำ Level 1 ก่อนทั้งหมด
2. Revert commit ของฟีเจอร์ multi-pair:
   ```bash
   git log --oneline | grep -i "multi-pair\|order list"
   git revert <commit-hash>
   ```
   หรือถ้ายังไม่ merge เป็น main: `git checkout <previous-commit> -- profit-monitor/`
3. Build & deploy ใหม่:
   ```bash
   yarn build
   ```
4. Verify ใน Dashboard: หัว unit แสดงแบบ single delta + side badge (BUY/SELL) เหมือนเดิม

> คอลัมน์ `position_orders` ใน DB ยังอยู่แต่จะไม่ถูกใช้งาน — ปลอดภัย ไม่กระทบประสิทธิภาพ

---

### Level 3 — Full Rollback (ลบทุกอย่างออกจาก DB)

ถ้าแน่ใจว่าจะไม่ใช้ฟีเจอร์นี้ถาวรแล้ว และต้องการคืน schema ให้ตรงกับ baseline

1. ทำ Level 1 + 2 ครบทั้งหมดก่อน
2. (แนะนำ) Backup ข้อมูล orders ไว้ก่อน เผื่ออยากเอากลับ:
   ```sql
   CREATE TABLE accounts_orders_backup AS
   SELECT account_number, position_orders, updated_at
   FROM accounts
   WHERE position_orders IS NOT NULL
     AND jsonb_array_length(position_orders) > 0;
   ```
3. ลบคอลัมน์ออกจาก `accounts`:
   ```sql
   ALTER TABLE accounts DROP COLUMN IF EXISTS position_orders;
   ```
4. ตรวจสอบว่าลบสำเร็จ:
   ```sql
   SELECT column_name FROM information_schema.columns
   WHERE table_name = 'accounts' AND column_name = 'position_orders';
   -- ควรไม่มี row คืนกลับมา
   ```
5. Restart backend / redeploy เพื่อให้ Supabase client cache schema ใหม่

> ⚠️ Step นี้ทำลายข้อมูล — ตรวจให้แน่ใจว่า backup เรียบร้อย

---

### Verify หลัง Rollback

```sql
-- ตรวจ schema (Level 3)
\d accounts
-- หรือ
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'accounts' ORDER BY ordinal_position;

-- ตรวจ EA version ที่ส่งเข้ามาล่าสุด (ดูจาก webhook log ฝั่ง backend)
-- คาดหวัง: ไม่มี field "orders" ใน payload
```

ที่ Dashboard ควรเห็น:
- ไม่มี badge `N pairs` / `solo`
- ไม่มี Open Pairs detail table
- หัว unit กลับมาแสดงแบบ delta เดียว + lots + BUY/SELL badge

---

### Restore (ถ้าทำ Level 3 ไปแล้วแล้วอยากกลับมาใช้)

```sql
-- เพิ่ม column กลับ
ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS position_orders JSONB DEFAULT '[]'::jsonb;

-- กู้ข้อมูลจาก backup (ถ้ามี)
UPDATE accounts a
SET position_orders = b.position_orders
FROM accounts_orders_backup b
WHERE a.account_number = b.account_number;

-- ลบ backup table หลัง restore สำเร็จ
DROP TABLE IF EXISTS accounts_orders_backup;
```

แล้วทำตาม Step 2-3 ของหัวข้อ **ขั้นตอนการเตรียมการ** ด้านบน

---

## Checklist สรุป

- [ ] รัน `ALTER TABLE` เพิ่ม `position_orders` JSONB
- [ ] Verify column ด้วย query `information_schema.columns`
- [ ] Deploy backend/frontend (`yarn build`)
- [ ] อัปเดต EA `ProfitMonitor-MT4.mq4` / `ProfitMonitor-MT5.mq5` (version 1.02) ทุกเครื่อง
- [ ] Recompile EA และ refresh ใน MT
- [ ] รอ 10–30 วินาที แล้วเปิด Supabase ตรวจ `position_orders`
- [ ] เปิด Dashboard ตรวจ badge `N pairs` และตาราง pair detail
