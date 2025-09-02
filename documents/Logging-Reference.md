# EA Logging Reference Guide

## Overview
เอกสารนี้สรุประบบ logging ที่เพิ่มเข้าไปใน Diff-Grabber EA เพื่อติดตามและ debug การทำงานของระบบ โดยแยกประเภท logs ตามแหล่งที่มาและการกระทำ

---

## Log Categories

### 1. Order Opening Triggers (OPEN_TRIGGER)
ติดตามสาเหตุการเปิดออเดอร์ทั้งแบบ manual และ automatic

#### Log Format
```
OPEN_TRIGGER,source=<SOURCE>;cmd_id=<CMD_ID>;diffOpen=<DIFF_VALUE>
```

#### Source Types
- **`MANUAL_BUTTON`** - เมื่อผู้ใช้กดปุ่ม "Open Now"
- **`AUTO_AVERAGING`** - เมื่อระบบ averaging trigger การเปิด
- **`AUTO_RAW_STABILITY`** - เมื่อระบบ raw stability trigger การเปิด  
- **`AUTO_SIMPLE`** - เมื่อระบบ simple threshold trigger การเปิด

#### Example Logs
```
OPEN_TRIGGER,source=MANUAL_BUTTON;cmd_id=A01_1756809495_1
OPEN_TRIGGER,source=AUTO_SIMPLE;cmd_id=A01_1756809500_2;diffOpen=32.5
```

---

### 2. Order Closing Triggers (CLOSE_TRIGGER)
ติดตามสาเหตุการปิดออเดอร์ทั้งแบบ manual และ automatic

#### Log Format
```
CLOSE_TRIGGER,source=<SOURCE>;diffClose=<DIFF_VALUE>
CLOSE_TRIGGER,source=<SOURCE>;pair_id=<PAIR_ID>
CLOSE_TRIGGER,source=<SOURCE>;self=<COUNT>;peer=<COUNT>
```

#### Source Types
- **`MANUAL_BUTTON`** - เมื่อผู้ใช้กดปุ่ม "Close Now"
- **`AUTO_AVERAGING`** - เมื่อระบบ averaging trigger การปิด
- **`AUTO_RAW_STABILITY`** - เมื่อระบบ raw stability trigger การปิด
- **`AUTO_SIMPLE`** - เมื่อระบบ simple threshold trigger การปิด
- **`RECONCILE_PEER_EXTRA`** - เมื่อ reconcile พบ peer มีออเดอร์เกิน
- **`RECONCILE_FORCE_BOTH`** - เมื่อ reconcile บังคับปิดทั้งคู่
- **`RECONCILE_PEER_MANUAL`** - เมื่อ master ตรวจพบ peer ปิดด้วยมือ
- **`ROLLBACK_TIMEOUT`** - เมื่อ rollback เพราะ slave ไม่ตอบ ACK

#### Example Logs
```
CLOSE_TRIGGER,source=MANUAL_BUTTON
CLOSE_TRIGGER,source=AUTO_SIMPLE;diffClose=31.2
CLOSE_TRIGGER,source=RECONCILE_PEER_MANUAL;self=1;peer=0
CLOSE_TRIGGER,source=ROLLBACK_TIMEOUT;pending_cmd=A01_1756809495_1
```

---

### 3. Manual Close Detection (MANUAL_CLOSE_DETECTED)
ตรวจจับการปิดออเดอร์ด้วยมือโดยไม่ผ่านระบบ

#### Log Format
```
MANUAL_CLOSE_DETECTED,role=<ROLE>;closed_orders=<COUNT>;prev_count=<PREV>;current_count=<CURRENT>
```

#### Fields
- **`role`** - MASTER หรือ SLAVE
- **`closed_orders`** - จำนวนออเดอร์ที่ปิด
- **`prev_count`** - จำนวนออเดอร์ก่อนหน้า
- **`current_count`** - จำนวนออเดอร์ปัจจุบัน

#### Example Logs
```
MANUAL_CLOSE_DETECTED,role=SLAVE;closed_orders=1;prev_count=1;current_count=0
MANUAL_CLOSE_DETECTED,role=MASTER;closed_orders=2;prev_count=3;current_count=1
```

---

### 4. Command Processing Logs

#### 4.1 Open Commands (OPEN_CMD)
```
OPEN_CMD,cmd_id=<CMD_ID>;side=<SIDE>;lotM=<LOT_M>;lotS=<LOT_S>;expire_ms=<EXPIRE>
```

#### 4.2 Close Commands (CLOSE_CMD)
```
CLOSE_CMD,cmd_id=<CMD_ID>;reason=<REASON>;action=CLOSE
CLOSE_CMD,cmd_id=<CMD_ID>;reason=<REASON>;diffClose=<DIFF>;threshold=<THRESHOLD>;action=CLOSE
```

#### 4.3 Acknowledgments
```
OPEN_ACK_MASTER,cmd_id=<CMD_ID>;ok=<STATUS>;price=<PRICE>;err=<ERROR>
OPEN_ACK_SLAVE,cmd_id=<CMD_ID>;ok=<STATUS>;price=<PRICE>;err=<ERROR>
CLOSE_ACK_MASTER,cmd_id=<CMD_ID>;ok=<STATUS>;err=<ERROR>
CLOSE_ACK_SLAVE,cmd_id=<CMD_ID>;ok=<STATUS>;err=<ERROR>
```

---

### 5. Reconciliation Logs

#### 5.1 Manual Drop Detection
```
RECONCILE_MANUAL_DROP,selfNow=<COUNT>;peerNow=<COUNT>;prevSelf=<PREV_SELF>;prevPeer=<PREV_PEER>
```

#### 5.2 Peer Manual Close Detection
```
RECONCILE_PEER_MANUAL_CLOSE,peer_closed_manually;self=<COUNT>;peer=<COUNT>
RECONCILE_MASTER_FOLLOW_CLOSE,cmd_id=<CMD_ID>;reason=PEER_MANUAL_CLOSE
```

#### 5.3 Position Reconciliation
```
RECONCILE_CLOSE_PEER_EXTRA,pair_id=<PAIR_ID>;cmd_id=<CMD_ID>
RECONCILE_CLOSE_SELF_EXTRA,pair_id=<PAIR_ID>;ok=<STATUS>;err=<ERROR>
RECONCILE_FORCE_BOTH_CLOSE,cmd_id=<CMD_ID>;self=<COUNT>;peer=<COUNT>
```

---

### 6. Slave Processing Logs

#### 6.1 Close Processing
```
SLAVE_CLOSE_ONE,cmd_id=<CMD_ID>;pair_id=<PAIR_ID>;reason=<REASON>
SLAVE_CLOSE_ALL,cmd_id=<CMD_ID>;reason=<REASON>
```

---

## Log Analysis Guide

### Troubleshooting Order Issues

#### Problem: Orders opening but closing immediately
**Look for:**
1. `OPEN_TRIGGER` logs to see what triggered the open
2. `CLOSE_TRIGGER` logs immediately after to see what caused the close
3. `MANUAL_CLOSE_DETECTED` to see if manual intervention occurred
4. `RECONCILE_*` logs to check for synchronization issues

#### Problem: Master not following slave manual close
**Look for:**
1. `MANUAL_CLOSE_DETECTED` on slave side
2. `RECONCILE_PEER_MANUAL_CLOSE` on master side
3. `CLOSE_TRIGGER,source=RECONCILE_PEER_MANUAL` on master side

#### Problem: Slave not opening after master
**Look for:**
1. `OPEN_TRIGGER` and `OPEN_CMD` on master side
2. `OPEN_ACK_SLAVE` to see if slave processed the command
3. Check for expired commands or timeout issues

---

## Log File Locations

### Daily Log Files
- **Path**: `<CommonFiles>/Files/EAChannels/channel_<ID>/logs/`
- **Format**: `log_YYYYMMDD.csv`
- **Retention**: Configurable via `input_log_retain_hours`

### Log Format
```
<timestamp_ms>,<role>,<channel_id>,<symbol>,<event>,<details>
```

### Example Log Entry
```
1756809495123,MASTER,A01,XAUUSD,OPEN_TRIGGER,source=AUTO_SIMPLE;cmd_id=A01_1756809495_1;diffOpen=32.5
```

---

## Configuration

### Enable/Disable File Logging
```cpp
input bool input_enable_file_logs = true;  // Enable file logging
input int input_log_retain_hours = 24;     // Retain logs for 24 hours
```

### Verbose Journal Logs
```cpp
input bool input_verbose_journal_logs = true;  // Enable terminal journal logs
```

---

## Performance Impact

### Minimal Overhead
- Logging is conditional (`if(!input_enable_file_logs) return;`)
- File operations use atomic writes
- Log cleanup runs every 30 minutes
- No impact on trading logic performance

### Memory Usage
- Static variables for tracking previous states
- Minimal memory footprint per log entry
- Automatic cleanup of old log files

---

## Best Practices

### 1. Log Analysis Workflow
1. Enable file logging during testing
2. Monitor logs in real-time during EA operation
3. Analyze patterns for optimization
4. Disable verbose logging in production if needed

### 2. Debugging Steps
1. Check `OPEN_TRIGGER` and `CLOSE_TRIGGER` logs for timing
2. Verify command processing with `*_CMD` and `*_ACK` logs
3. Monitor reconciliation with `RECONCILE_*` logs
4. Track manual interventions with `MANUAL_CLOSE_DETECTED`

### 3. Performance Tuning
- Use logs to identify bottlenecks
- Adjust timeouts based on actual ACK times
- Monitor reconciliation frequency
- Optimize threshold values based on diff statistics

---

## File Structure Summary

```
<CommonFiles>/Files/EAChannels/channel_<ID>/
├── logs/
│   ├── log_20250901.csv
│   ├── log_20250902.csv
│   └── ...
├── histogram/
│   ├── hist_20250901.csv
│   └── ...
└── [other EA files...]
```

---

## Notes
- All timestamps are in milliseconds since epoch
- Role can be either "MASTER" or "SLAVE"
- Channel ID matches the `input_channel_id` parameter
- Symbol matches the trading symbol
- All logs are written atomically to prevent corruption
