## คู่มือการตั้งค่า Input — EA Heading Master–Slave (MT4/MT5)

เอกสารนี้สรุปวิธีตั้งค่าอินพุตของ EA ตามไฟล์ `EAHeadingMasterSlave.mq4` และ `EAHeadingMasterSlave.mq5` ตามสเปคใน `EA-Heading-Design.md` เพื่อใช้งานจริงและโหมดทดสอบ (Dry Run)

### ข้อกำหนดเบื้องต้น
- รันเทอร์มินัล 2 ตัว (2 โบรก) บนเครื่องเดียวกัน
- ใช้ช่องทางไฟล์ร่วมใน Common Files โดยอัตโนมัติ: EA จะสร้างโฟลเดอร์ `EAChannels/channel_<ID>/`
- ถ้าต้องการหลายคู่พร้อมกัน ให้ใช้ `channel_id` แตกต่างกันในแต่ละคู่
- ติดตั้ง EA ลงบนกราฟสัญลักษณ์เดียวกันทั้งฝั่ง Master/Slave

---

### ชุดอินพุตหลัก (ทั้ง MT4/MT5)

Input scope (which side the input applies to):

| Input | Scope | Notes |
|---|---|---|
| role (`ROLE_MASTER`/`ROLE_SLAVE`) | Both | เลือกบทบาทของอินสแตนซ์ EA |
| channel_id | Both | ต้องตรงกันระหว่าง Master/Slave ของคู่เดียวกัน |
| symbol | Both | ใช้สัญลักษณ์เดียวกันทั้งสองฝั่ง |
| master_side (`SIDE_BUY`/`SIDE_SELL`) | Master | Slave จะตรงข้ามโดยอัตโนมัติ |
| lot_master | Master | ใช้ตอน Master ส่งคำสั่งของตัวเอง; ฝั่ง Slave ไม่ใช้ค่านี้ของตัวเอง |
| lot_slave | Master | Master เป็นคนกำหนดและส่งไปให้ Slave ผ่านไฟล์คำสั่ง |
| open_threshold_points | Master | เงื่อนไขส่วนต่างเพื่อ “เปิด” |
| close_threshold_points | Master | เงื่อนไขส่วนต่างเพื่อ “ปิด” |
| slippage_points | Both | ใช้ตอนส่งคำสั่งเทรดของฝั่งตนเอง |
| cooldown_seconds | Master | เวลาหน่วงหลังเปิดคู่หนึ่ง ก่อนพิจารณาคู่ถัดไป |
| max_open_pairs | Master | ลิมิตจำนวนคู่เปิดพร้อมกัน |
| max_spread_points_self | Master | การ์ดป้องกันสเปรดของบัญชีตนเอง (Slave รับค่าจาก Master) |
| max_spread_points_peer | Master | ตรวจสเปรดฝั่งคู่จากไฟล์ quotes ก่อนเปิด |
| quotes_fresh_ms | Master | กำหนดความสดของราคา (Slave รับค่าจาก Master) |
| file_poll_ms | Master | จังหวะอ่านไฟล์เสริม (Slave รับค่าจาก Master) |
| magic_number_base | Master | แยก magic ต่อ channel/symbol (Slave รับค่าจาก Master) |
| retry_on_requote, max_retries | Master | พฤติกรรม retry (Slave รับค่าจาก Master) |
| cmd_expire_ms | Master | อายุคำสั่ง open/close (ms) |
| ack_timeout_ms | Master | เวลารอ ack (ms) สำหรับ watchdog/rollback |
| heartbeat_timeout_ms | Master | Timeout heartbeat ของ peer (ms) |
| reconcile_mode (`CLOSE`/`REOPEN`) | Master | กลยุทธ์แก้ desync |
| reconcile_interval_ms | Master | ช่วงเวลาตรวจ/ซ่อม desync |
| journal_rotate_max_kb | Master | ขนาด journal ก่อน rotate |
| dry_run_enabled | Master | เปิดโหมดทดสอบ (Slave ตาม Master) |
| dry_run_handshake_mode | Master | NONE/WRITE_CMD_ONLY/WRITE_CMD_AND_FAKE_ACK |
| dry_run_inject_delay_ms | Master | จำลองดีเลย์ IO |
| dry_run_drop_rate_percent | Master | จำลองดรอปไฟล์คำสั่ง/ack |
| dry_run_override_cmd_expire_ms | Master | อายุคำสั่งเฉพาะโหมดทดสอบ |
| dry_run_suppress_heartbeat | Master | ปิด heartbeat ชั่วคราวเพื่อทดสอบ |
หมายเหตุเสริมที่สำคัญ:
- Slave จะ “ดึงค่าการ์ด/timeout/Dry Run ทั้งหมดจาก Master อัตโนมัติ” ผ่านไฟล์ `config_master.csv` และอัปเดตทุก OnTimer (ไม่ต้องตั้งค่าซ้ำใน Slave)
- lot_master/lot_slave: ค่าที่มีผลต่อการส่งคำสั่งจริงใช้งานจาก Master เท่านั้น; ฝั่ง Slave จะรับค่าล็อตจากไฟล์คำสั่งของ Master เสมอ
- open/close_threshold_points, cooldown_seconds, max_open_pairs: เป็นนโยบายของ Master เท่านั้น

การป้องกันคุณภาพสัญญาณ (กำหนดที่ Master):
- max_spread_points_self: ไม่ส่งคำสั่งถ้า spread ตัวเองเกินค่านี้
- max_spread_points_peer: ไม่เปิดถ้า spread ฝั่งคู่เกิน (อ่านจากไฟล์ quotes)
- quotes_fresh_ms: อายุข้อมูลราคา (ms) ที่ยอมรับได้
- file_poll_ms: จังหวะอ่านไฟล์เสริม (ms)
- magic_number_base: base ของ magic number ต่อ channel
- retry_on_requote, max_retries: ตั้งค่าสำหรับการ retry

Smart Sync/Recovery (กำหนดที่ Master):
- cmd_expire_ms: อายุคำสั่ง open/close (ms)
- ack_timeout_ms: เวลารอ ack (ms)
- heartbeat_timeout_ms: ขีดจำกัดการหายของ heartbeat ฝั่งคู่ (ms)
- reconcile_mode: โหมดแก้ desync
  - `RECONCILE_CLOSE`: ปิดฝั่งที่ยังค้างเพื่อความปลอดภัย
  - `RECONCILE_REOPEN`: พยายามเปิดฝั่งที่ขาด (ใช้เมื่อมั่นใจ)
- reconcile_interval_ms: รอบตรวจและซ่อม desync (ms)

Dry Run (ทดสอบโดยไม่เทรดจริง):
- dry_run_enabled: เปิดโหมดทดสอบ (ไม่ส่งคำสั่งเทรดจริง)
- dry_run_handshake_mode:
  - `DRY_NONE`: ไม่เขียนไฟล์คำสั่ง (ทดสอบเฉพาะการคำนวณ)
  - `DRY_WRITE_CMD_ONLY`: เขียนไฟล์คำสั่ง แต่ไม่สร้าง ack จำลอง
  - `DRY_WRITE_CMD_AND_FAKE_ACK`: เขียนคำสั่งและสร้าง ack จำลองครบเส้นทาง (แนะนำสำหรับทดสอบซิงก์)
- dry_run_inject_delay_ms: จำลองดีเลย์ IO (ms)
- dry_run_drop_rate_percent: โอกาสดรอปไฟล์คำสั่ง/ack (%)
- dry_run_override_cmd_expire_ms: อายุคำสั่งเฉพาะโหมดทดสอบ (ms), 0 = ใช้ค่าปกติ
- dry_run_suppress_heartbeat: ปิด heartbeat เพื่อทดสอบการตรวจจับขาดการติดต่อ

---

### ตั้งค่า Master
1) ตั้ง `role = ROLE_MASTER`
2) ตั้ง `channel_id` ให้ตรงกับฝั่ง Slave (เช่น `A01`)
3) ตั้ง `symbol` ตามกราฟ หรือปล่อยว่างเพื่อใช้สัญลักษณ์กราฟปัจจุบัน
4) ตั้ง `master_side` เป็นฝั่งที่ต้องการ (เช่น `SIDE_BUY`)
5) ตั้งขนาดล็อต: `lot_master` (ล็อตฝั่ง Master), `lot_slave` (ล็อตที่แนะนำไปยัง Slave)
6) ตั้งเกณฑ์: `open_threshold_points`, `close_threshold_points`, `slippage_points`
7) ตั้งข้อจำกัด: `cooldown_seconds`, `max_open_pairs`
8) ตั้งการ์ดป้องกัน: `max_spread_points_self`, `max_spread_points_peer`, `quotes_fresh_ms`
9) ตั้ง Smart Sync/Recovery: `cmd_expire_ms`, `ack_timeout_ms`, `heartbeat_timeout_ms`, `reconcile_mode`, `reconcile_interval_ms`

คำแนะนำ:
- ถ้าเป็นบัญชี MT5 netting: จำกัด `max_open_pairs` ต่อ symbol ให้เหมาะสม
- หากต้องทดสอบซิงก์ก่อนเทรดจริง ให้ดูหัวข้อ Dry Run ด้านล่าง

---

### ตั้งค่า Slave
1) ตั้ง `role = ROLE_SLAVE`
2) ตั้ง `channel_id` ให้ตรงกับฝั่ง Master (เช่น `A01`)
3) ตั้ง `symbol` ให้ตรงกับ Master
4) ไม่ต้องตั้ง `master_side` (Slave จะทำฝั่งตรงข้ามอัตโนมัติ)
5) ขนาดล็อตฝั่ง Slave จะถูกระบุโดย Master ผ่านไฟล์คำสั่ง (อ่านจาก `lot_slave` ของ Master)
6) ไม่ต้องตั้งค่าการ์ด/Smart Sync/Dry Run ซ้ำ — Slave จะอ่านจาก `config_master.csv` อัตโนมัติและอัปเดตทุก OnTimer

หมายเหตุเพิ่มเติม:
- หากเปิด Slave ก่อน Master: Slave จะใช้ค่าที่พบล่าสุดใน `config_master.csv`; เมื่อ Master รันขึ้นและเขียนค่าใหม่ Slave จะอัปเดตตามทันที
- รองรับ Master/Slave ข้ามแพลตฟอร์ม (MT4↔MT5) เต็มรูปแบบ

---

### โหมดทดสอบ (Dry Run) — แนะนำค่าตั้งต้น
เป้าหมาย: ทดสอบการคำนวณส่วนต่าง, การส่งคำสั่งผ่านไฟล์, การตอบรับ ack และการแสดงผล โดยไม่ส่งคำสั่งเทรดจริง

ตั้งค่าเฉพาะ Master เท่านั้น (Slave จะตามอัตโนมัติ):
- `dry_run_enabled = true`
- `dry_run_handshake_mode = DRY_WRITE_CMD_AND_FAKE_ACK` (แนะนำเพื่อเห็น handshake ครบ)
- ตัวเลือกเพิ่มเติมสำหรับทดสอบความทนทาน:
  - `dry_run_inject_delay_ms = 50~200` เพื่อจำลองดีเลย์ IO
  - `dry_run_drop_rate_percent = 0~10` เพื่อจำลองการสูญหายของไฟล์บางส่วน
  - `dry_run_override_cmd_expire_ms` เพื่อย่น/ยืดอายุคำสั่ง (ช่วยทดสอบ timeout/rollback)
  - `dry_run_suppress_heartbeat = false` (หรือ true หากต้องการทดสอบการแจ้งเตือน heartbeat ขาด)

ข้อสังเกต:
- โหมด Dry Run จะไม่ส่งคำสั่งเทรดจริง แต่จะบันทึกคำสั่งและ ack จำลอง ช่วยตรวจสอบ latency และความสดของ quotes
- หากเลือก `DRY_NONE` จะไม่เขียนคำสั่ง ทำให้ทดสอบได้เฉพาะฝั่งคำนวณ ไม่เห็นไฟล์ handshake

---

### ตัวอย่างการตั้งค่าใช้งานจริง (ตามโจทย์)
กรณีต้องการเข้า: Buy ที่ Neex (Master) และ Sell ที่ Fxprimus (Slave)
- Master (Neex):
  - `role = ROLE_MASTER`
  - `channel_id = A01`
  - `symbol = [คู่เงิน/สัญลักษณ์เดียวกัน]`
  - `master_side = SIDE_BUY`
  - `open_threshold_points = 30`, `close_threshold_points = 30`
  - `lot_master = ...`, `lot_slave = ...`
- Slave (Fxprimus):
  - `role = ROLE_SLAVE`
  - `channel_id = A01`
  - `symbol = [เหมือน Master]`

หมายเหตุสูตรส่วนต่าง:
- เปิด: `sell_bid - buy_ask >= open_threshold_points`
- ปิด: `buy_bid - sell_ask >= close_threshold_points`

---

### การรันหลายคู่พร้อมกัน
- ใช้ `channel_id` ต่างกันในแต่ละคู่ (เช่น `A01`, `B02`, ...)
- ติดตั้ง EA ลงบนกราฟของแต่ละบัญชี/โบรก แยกตาม channel ที่กำหนด
- Single-instance per channel/role: 1 Master + 1 Slave ต่อ 1 channel เท่านั้น หากตรวจพบหลายตัวในบทบาทเดียวกัน ระบบจะเข้าสู่โหมดปลอดภัย (ไม่ส่งคำสั่ง) และแสดง `role_conflict=YES` ใน Display Monitor
- Display Monitor จะสรุปข้อมูลบทบาท, channel, สถานะ sync, จำนวนคู่เปิด และส่วนต่างราคาแบบเรียลไทม์

ค่าดีฟอลต์สำคัญ (โค้ดปัจจุบัน): `lot_master=0.01`, `lot_slave=0.01`, `file_poll_ms=20`, `reconcile_interval_ms=1000`

Debug (Master เท่านั้น): ปุ่ม `Open Now`/`Close Now` สำหรับจำลองการเข้า/ออก โดยยังคง flow cmd/ack/rollback จริง และกันปิดอัตโนมัติด้วย diffClose จนกว่าจะกด Close Now


