## การเก็บสถิติ Diff และการตั้งค่าที่ปรับได้ (MT4/MT5)

เอกสารนี้สรุปวิธีเก็บสถิติส่วนต่างราคา (diff) และตัวแปรที่ปรับได้สำหรับการคำนวณ “ค่าที่แนะนำ” เพื่อใช้ตั้ง threshold ที่เหมาะสม โดยเน้นไม่กระทบประสิทธิภาพของระบบหลัก และแสดงเฉพาะฝั่ง MASTER

---

### 1) สิ่งที่เก็บสถิติ (Runtime-Only)
- Peak (ค่ามากสุดแบบ Real ตลอดรอบการทำงาน)
  - `g_peak_open_real`: ค่าสูงสุดของ diffOpen (จุด)
  - `g_peak_close_real`: ค่าสูงสุดของ diffClose (จุด)
- Histogram ความถี่ (bin กว้าง 1 จุด, ช่วง 0..300)
  - `g_hist_open_counts[0..300]`: นับความถี่ของ diffOpen แบบ O(1)/tick
  - `g_hist_close_counts[0..300]`: นับความถี่ของ diffClose แบบ O(1)/tick
  - หมายเหตุ: ค่า diff ≤ 0 จะถูก map ไปที่ bin 0 (สามารถเปลี่ยนเป็นนับเฉพาะ > 0 ได้ หากต้องการ)
- Mode (จุดที่ถี่สุดแบบจุดเดียว ในช่วง [0..peak])
  - `g_mode_open_index`, `g_mode_open_count`
  - `g_mode_close_index`, `g_mode_close_count`

ทั้งหมดนี้เป็นข้อมูลในหน่วยความจำ (reset เมื่อ EA ถูกถอด/รีสตาร์ท)

---

### 2) การอัปเดตสถิติ (Performance-Friendly)
- ต่อ tick (MASTER เท่านั้น และเมื่อ `QuotesFresh()` เป็นจริง):
  - คำนวณ diff จริง (Real)
  - อัปเดต peak หากค่าสูงกว่าเดิม
  - แปลง diff เป็นดัชนี bin: `idx = floor(max(0, diff))` และ clamp ที่ 300
  - `g_hist_*_counts[idx]++` และอัปเดต mode แบบ incremental
- ไม่มีการวนลูปทั้งอาร์เรย์ต่อ tick (ต้นทุน O(1) ต่อ tick)

---

### 3) Weighted Suggest (โหมดถ่วงน้ำหนัก)
แนวคิด: ให้ค่าที่ “สูงกว่า” มีน้ำหนักมากขึ้น แม้ความถี่น้อยกว่า โดยสแกนช่วง [1..peak] (ตัด bin 0) แบบไม่ถี่ เพื่อหลีกเลี่ยงผลกระทบกับงานหลัก

- สูตรคะแนนต่อจุด i (ตัวอย่าง):
  - `score(i) = i^alpha × Σ count[j] (j ∈ window[i])`
  - `window[i]` คือช่วงรอบๆ i ความกว้าง W (เลขคี่)
  - พิจารณาเฉพาะเมื่อ Σcount ≥ min_count
- ผลลัพธ์:
  - `g_weighted_open_suggest`, `g_weighted_close_suggest`
- ช่วงเวลาคำนวณ (ใน OnTimer): ทุก `g_weighted_refresh_ms` มิลลิวินาที (เริ่มต้น 30 นาที)

---

### 4) ตัวแปรที่ปรับได้
ปรับค่าได้โดยแก้ไขค่าตัวแปร global (ทั้ง MQ4/MQ5 ใช้ชื่อเดียวกัน)

- ขอบเขตฮิสโตแกรม
  - `#define DIFF_HIST_MAX_POINTS 300` (bin = 0..300)

- พารามิเตอร์ Weighted Suggest
  - `g_weighted_alpha` (double, เริ่มต้น 1.5): กำลังถ่วงน้ำหนัก i^alpha (เพิ่ม alpha เพื่อให้ค่าที่สูงกว่ามีอิทธิพลมากขึ้น)
  - `g_weighted_window` (int, เริ่มต้น 5): ความกว้างหน้าต่างของการรวมความถี่รอบๆ i (ระบบบังคับเป็นเลขคี่)
  - `g_weighted_min_count` (int, เริ่มต้น 5): จำนวนความถี่รวมขั้นต่ำของหน้าต่างก่อนพิจารณาคะแนน
  - `g_weighted_refresh_ms` (int, เริ่มต้น 1,800,000 ms ≈ 30 นาที): รอบเวลาในการคำนวณ weighted suggest ใน OnTimer

- เอาต์พุต (อ่านอย่างเดียว)
  - `g_weighted_open_suggest`, `g_weighted_close_suggest`: ค่าที่แนะนำแบบถ่วงน้ำหนัก
  - `g_mode_open_index`, `g_mode_close_index`: โหมดแบบจุดเดียว (นับถี่สุด)
  - `g_peak_open_real`, `g_peak_close_real`: ค่าสูงสุดของ diff จริง

---

### 5) คำแนะนำการจูน
- อยากเน้น “ค่าที่สูง” มากขึ้น: เพิ่ม `g_weighted_alpha` (เช่น 1.5 → 2.0)
- อยากกดสัญญาณรบกวน: เพิ่ม `g_weighted_min_count` หรือขยาย `g_weighted_window`
- อยากดูสรุปไม่ถี่: เพิ่ม `g_weighted_refresh_ms` เป็น 30–60 นาที (1,800,000–3,600,000 ms)

---

### 6) การแสดงผลบน Display Monitor (MASTER)
ตัวอย่างบรรทัดที่จะแสดง:

```
Peak Real: open=47.3 close=39.8
Mode Open[0..47]=32 cnt=15842 (suggest=32)
Mode Close[0..39]=28 cnt=14307 (suggest=28)
Weighted Suggest: open=34 close=30 (alpha=1.5 W=5 min=5)
```

- Mode = โหมดจุดเดียวของฮิสโตแกรม (bin ที่ถี่สุดในช่วง [0..peak])
- Weighted Suggest = ค่าที่แนะนำแบบถ่วงน้ำหนัก ซึ่งให้ความสำคัญกับ “ความสูงของ diff” และ “ความถี่ในหน้าต่าง” ไปพร้อมกัน

---

### 7) หมายเหตุสำคัญ
- สถิติทั้งหมดเก็บเฉพาะในหน่วยความจำและรีเซ็ตเมื่อ EA ถูกถอด/รีสตาร์ท
- นับเฉพาะเมื่อ `QuotesFresh()` เป็นจริง และทำงานเฉพาะฝั่ง MASTER
- ค่า diff ≤ 0 จะถูกนับใน bin 0 (หากต้องการ “ไม่นับเลย” สามารถแก้โค้ดให้ข้ามได้)


---

### 8) การบันทึกไฟล์รายวัน (Daily Histogram Persistence)
- บันทึกอัตโนมัติ “เมื่อข้ามวัน” ตามเวลา `TimeLocal()` (เฉพาะ MASTER)
- โฟลเดอร์ปลายทางต่อช่องสัญญาณ: `EAChannels/channel_<ID>/histogram/`
- ชื่อไฟล์: `hist_YYYYMMDD.csv` (เช่น `hist_20250901.csv`)
- สคีมาไฟล์ (CSV):
  - เฮดเดอร์ข้อมูลดิบความถี่: `type,index,count`
    - แถว `open,i,cnt` สำหรับ diffOpen bin i
    - แถว `close,i,cnt` สำหรับ diffClose bin i
    - เขียนเฉพาะ bin ที่ `count > 0` (ต้องการครบทุก bin ระบุเพิ่มได้)
  - ส่วนสรุปท้ายไฟล์ (หนึ่งค่าต่อบรรทัด):
    - `summary,peak_open,<double>`
    - `summary,peak_close,<double>`
    - `summary,mode_open,<int>`
    - `summary,mode_close,<int>`
    - `summary,weighted_open,<int>`
    - `summary,weighted_close,<int>`
- หลังเขียนไฟล์ของ “วันก่อนหน้า” สำเร็จ ระบบจะรีเซ็ตตัวนับทั้งหมดสำหรับวันใหม่:
  - `g_hist_*_counts[0..300] = 0`
  - `g_peak_*_real = 0.0`, `g_mode_* = 0`, และ `g_weighted_*_suggest = 0`
- ข้อมูลที่บันทึกในส่วน `type,index,count` เป็น “ข้อมูลดิบ” (raw frequency) เพื่อรองรับการ post‑process ภายหลังได้เต็มที่


