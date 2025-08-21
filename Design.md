## EA Heading Master–Slave (MT4 & MT5) — Design Plan

### เป้าหมาย
- รองรับ MT4 และ MT5 ทุกรูปแบบการจับคู่ (MT4–MT4, MT5–MT5, MT4–MT5)
- รันบนคอมพิวเตอร์เครื่องเดียวกัน จับคู่ได้ทีละ 2 โบรกต่อ 1 ช่องสัญญาณ (room/channel)
- สื่อสารระหว่าง EA ด้วยการ read/write ไฟล์แบบ near real-time
- กำหนดบทบาท Master/Slave, สัญลักษณ์, ฝั่งคำสั่ง, lots, threshold, cooldown, และ limit คู่เปิด
- เปิด/ปิดเฮดจ์พร้อมกันและซิงก์สถานะให้สมบูรณ์เสมอ
- แสดง Display Monitor บนกราฟ (ซ้ายบน) ด้วยอ็อบเจ็กต์ ไม่ใช้ Comment()

### สถาปัตยกรรม

#### บทบาทและอินสแตนซ์
- **Master EA**: ตัดสินใจเปิด–ปิด, กำหนดทิศทางฝั่งตัวเอง (Buy/Sell), กำหนด threshold, cooldown, max open pairs
- **Slave EA**: ทำฝั่งตรงข้ามอัตโนมัติ, ทำตามสัญญาณ Master, เชื่อมสถานะและปิดตาม Master ทุกกรณี
- หนึ่งคู่ = 2 อินสแตนซ์ (Master 1 + Slave 1) บน 2 บัญชี/โบรก
- หลายคู่พร้อมกัน → ใช้ `channel` ไม่ซ้ำต่อคู่

#### โครงสร้าง IO (ไฟล์)
- ใช้ Common Files อัตโนมัติ: `TERMINAL_COMMONDATA_PATH/Files/EAChannels/channel_<ID>/`
  - `shared_dir` เป็น legacy ไม่จำเป็นต้องตั้งค่า
  - แยก channel ด้วยโฟลเดอร์ `channel_<ID>` เพื่อกันสัญญาณปะปน
- แต่ละฝั่ง “เขียนไฟล์ของตัวเอง” และ “อ่านไฟล์ของคู่ตรงข้าม” เพื่อลด write conflict
- เขียนไฟล์แบบ atomic: เขียน `.tmp` แล้ว `rename` ด้วย `FileMove(..., FILE_COMMON)` ป้องกัน partial read

หมายเหตุการแยก channel:
- แนะนำให้สร้างโฟลเดอร์ย่อยต่อ `channel_id` เสมอ เพื่อป้องกันการปนสัญญาณและไฟล์เขียนทับกัน
- โครงสร้างตัวอย่าง:
  ```
  <Common>/Files/EAChannels/
    channel_A01/
      ... (ไฟล์ทั้งหมดของ channel A01)
    channel_B02/
      ... (ไฟล์ทั้งหมดของ channel B02)
  ```

ไฟล์ต่อ 1 channel:
- `quotes_master.csv` / `quotes_slave.csv`: last tick snapshot
  - ฟอร์แมต: `epoch_ms,bid,ask`
- `open_cmd.csv`: คำสั่งเปิดจาก Master
  - `version,cmd_id,seq,pair_id,symbol,master_side,lot_master,lot_slave,slippage,created_ms,expire_ms`
- `open_ack_master.csv` / `open_ack_slave.csv`: ผลลัพธ์เปิดออเดอร์
  - `version,cmd_id,seq,pair_id,ticket,price,ok,error_code,latency_ms`
- `close_cmd.csv`: คำสั่งปิดจาก Master หรือการ trigger close จากเหตุผิดปกติ
  - `version,cmd_id,seq,pair_id,reason,created_ms,expire_ms`
- `close_ack_master.csv` / `close_ack_slave.csv`: ผลลัพธ์ปิดออเดอร์
  - `version,cmd_id,seq,pair_id,ok,error_code,latency_ms`

รหัส `error_code` ที่ใช้:
- `0` สำเร็จ, `400` malformed/อ่านไฟล์ไม่ครบ, `408` คำสั่งหมดอายุ, `205` ยอมรับคำสั่งปิดที่หมดอายุเพื่อช่วย reconcile

ไฟล์สถานะเสริมเพื่อ Smart Sync:
- `state_master.json` / `state_slave.json`: บันทึก state machine ต่อ `pair_id` และ `last_cmd_id`,`last_seq`
- `journal.csv` (rotation ตามขนาดไฟล์): บันทึกเหตุการณ์สำคัญต่อบรรทัดเพื่อใช้ debug/replay

ไฟล์สำหรับ Dry Run (ทดสอบ sync โดยไม่เทรดจริง):
- `dryrun_metrics.csv`: `epoch_ms,diff_open_points,diff_close_points,decision,reason,peer_fresh_ms,latency_ms`
- `dryrun_decisions.csv`: `version,cmd_id,seq,pair_id,decision,expected_master_side,expected_slave_side,lot_master,lot_slave,price_master,price_slave`

แนวปฏิบัติด้านไฟล์:
- เขียนแบบ atomic (`.tmp` → rename), ใช้ `FILE_COMMON` เสมอ
- ใช้ `seq` เพิ่มขึ้นป้องกันอ่านซ้ำ, ใส่ `expire_ms` กันคำสั่งค้าง
- ตรวจ freshness ของ quotes: เกิน threshold จะไม่เปิด/ปิด

### โปรโตคอลและลอจิก

#### คำจำกัดความส่วนต่าง (points)
- เปิด: `sell_bid - buy_ask >= open_threshold_points`
- ปิด: `buy_bid - sell_ask >= close_threshold_points`

#### การตัดสินใจเปิด (Master-Driven)
1) สตรีม `quotes_*.csv` บนทุก tick/Timer
2) Master คำนวณส่วนต่างจากราคาตัวเอง + peer (ต้อง fresh)
3) ผ่าน guard + ไม่ชน cooldown/limit → เขียน `open_cmd.csv`, Master ส่งคำสั่งตัวเองทันทีและเขียน `open_ack_master.csv`
4) Slave อ่าน `open_cmd.csv` → ส่งคำสั่งตรงข้าม → เขียน `open_ack_slave.csv`
5) Master รอ ACK ทั้งสองฝั่ง; ถ้าฝั่งใดล้มเหลว/ไม่ตอบใน `ack_timeout_ms` → rollback โดยส่ง `close_cmd.csv`

#### การตัดสินใจปิด (Master-Driven + Safety)
- Master ถึง `close_threshold_points` → เขียน `close_cmd.csv` → ปิดฝั่งตัวเอง และ Slave ปิดตามเมื่อเห็นคำสั่ง
- Safety: หากมีการปิดด้วยมือฝั่งใดฝั่งหนึ่ง อีกฝั่งต้องปิดตาม โดยเทียบ `positions_*.csv`

### Smart Sync & Recovery
- Idempotency: ทุกคำสั่งต้องมี `cmd_id/seq` ไม่ซ้ำ; ฝั่งรับ drop คำสั่งซ้ำตาม `last_cmd_id`
- Acknowledgement binding: ACK ผูกกับ `cmd_id` เดิม
- Expiry/Timeout: คำสั่งหมดอายุตาม `expire_ms`; Master มี `ack_timeout_ms` เพื่อ rollback อัตโนมัติ
- Freshness guard: ใช้ `quotes_fresh_ms` เปรียบเทียบกับเวลาปัจจุบัน
- State machine + Crash/Restart: อ่าน `state_*.json`/`positions_*.csv` เพื่อกู้ context และ reconcile ตาม `reconcile_mode`
- Desync detection: ตรวจ signature ของคู่เปิด; ต่างกันให้ reconcile (`CLOSE`/`REOPEN`)
- Atomic IO + Journal/metrics สำหรับ latency
- Receipt ACK (สำคัญ): Slave เขียน ACK ทันทีแม้อ่านคำสั่งผิดรูปหรือหมดอายุ เพื่อให้ Master ตัดสินใจได้เร็ว
- Durable idempotency: Slave ใช้ `open_ack_slave.csv`/`close_ack_slave.csv` เป็นความจำถาวรของ `last processed cmd_id` กันประมวลผลซ้ำหลังรีสตาร์ต

#### Cooldown และ Limit
- Master: `cooldown_seconds`, `max_open_pairs`
- Slave: ทำตามคำสั่งเท่านั้น

### พารามิเตอร์ (Inputs)

#### พื้นฐาน
- `role`, `channel_id`, `symbol`, `master_side`, `lot_master`, `lot_slave`, `open_threshold_points`, `close_threshold_points`, `slippage_points`, `cooldown_seconds`, `max_open_pairs`

#### ความปลอดภัย/คุณภาพสัญญาณ
- `max_spread_points_self`, `max_spread_points_peer`, `quotes_fresh_ms`, `file_poll_ms`, `magic_number_base`, `retry_on_requote`, `max_retries`, `cmd_expire_ms`, `ack_timeout_ms`, `heartbeat_timeout_ms`, `reconcile_mode`, `reconcile_interval_ms`, `journal_rotate_max_kb`

#### โหมดทดสอบ (Dry Run)
- `dry_run_enabled`, `dry_run_handshake_mode`, `dry_run_inject_delay_ms`, `dry_run_drop_rate_percent`, `dry_run_override_cmd_expire_ms`, `dry_run_suppress_heartbeat`

#### โหมด Debug บนกราฟ (Manual Trigger)
- `debug_buttons_enabled` (Master เท่านั้น): แสดงปุ่ม `Open Now` และ `Close Now`
  - Open Now: ใช้ลอจิกเปิดจริงครบ (peer alive, freshness, spread, cooldown, max pairs) แต่ข้าม `diffOpen`
  - Close Now: ใช้ลอจิกปิดจริงครบ แต่ข้าม `diffClose`
  - เขียน `open_cmd.csv` / `close_cmd.csv` และ ACK ตามปกติ เพื่อจำลอง flow end‑to‑end

#### ความเข้ากันได้ MT4/MT5
- MT4: คำสั่งแบบ Hedge, ticket-based (`OrderSend`/`OrderClose`)
- MT5: รองรับ Hedge/Netting (`OrderSend` via `MqlTradeRequest`)
  - Netting: แนะนำ `max_open_pairs=1` ต่อ symbol หรือใช้ mapping ตาม `pair_id`
  - Hedge: ปิดตำแหน่งต้องระบุ `req.position = <ticket>` เพื่อปิดโพสิชันที่ถูกต้อง

### Display Monitor (ซ้ายบนกราฟ, ไม่ใช้ Comment)
- แสดง `role/channel/symbol`, account/broker/build, master_side, lots(th M/S), thresholds, slippage, cooldown, max_open_pairs
- quotes: bid/ask self+peer, spread, freshness(ms)
- sync: heartbeat อายุ, ไฟล์ IO ล่าสุด และ `sync_path` ของ channel
- pairs opened: รายการคู่เปิด (pair_id, tickets, ราคาเปิด, PnL), status: cooldown, guards, smart sync metrics

### ความเร็วและความทนทาน
- อัปเดต quotes บนทุก tick และ/หรือ OnTimer ระยะสั้น; เขียนไฟล์แบบ atomic; ใช้ freshness guard; Master เป็นตัวตัดสินใจเพื่อหลีกเลี่ยง race

### จัดการข้อผิดพลาด
- เปิดสำเร็จเพียงฝั่งเดียว → rollback โดย `close_cmd`
- requote/partial fill: MT4 ใช้ slippage/retry, MT5 ตรวจ deal/position

### โหมดทดสอบ (Dry Run Mode)
- ทดสอบการซิงก์ สถานการณ์ latency/drop/expire, บันทึก metrics

### ความแตกต่าง MT4 vs MT5
- MT4: Hedge, ticket-based
- MT5: Hedge/Netting; Netting จำกัด open pair; Hedge ต้องระบุ `req.position` ตอนปิด

### กรณีใช้งานจริง (ตัวอย่าง)
- ตามสเปคเดิม (Neex buy ask, Fxprimus sell bid; open/close 30 points)

### กรอบการทดสอบและยืนยันผล
- ทดสอบเปิด–ปิด–rollback–manual close sync; วัด latency 10–100 ms ตาม IO

### ข้อกำหนดการดีพลอยและใช้งาน
- รัน EA สองตัว (Master/Slave) บนสัญลักษณ์เดียวกัน; ตั้ง channel ตรงกัน; ตรวจ monitor ให้พร้อมก่อนใช้งานจริง

### ข้อจำกัดและคำแนะนำ
- ประสิทธิภาพขึ้นกับ IO/เครื่อง; หากใช้ข้ามเครื่องควรหลีกเลี่ยงหรือใช้เครือข่ายหน่วงต่ำ; MT5 Netting มีข้อจำกัดเรื่องจำนวนคู่


