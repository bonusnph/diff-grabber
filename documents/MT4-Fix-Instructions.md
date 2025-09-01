## Diff-Grabber (MT4) – Root Cause Fix: Slave not opening after MT4 Master

### Problem
MT4 Slave parsed `created_ms` (millisecond timestamp) using an integer conversion that truncated 64-bit values. This produced extremely large, incorrect `age_ms` and caused the Slave to reject the open command as “expired” immediately.

### Fix
Parse `created_ms` using `StrToDouble(...)` and cast to `ulong` in the MT4 Slave command handlers.

- In `Diff-Grabber.mq4`:
  - `SlaveProcessOpenCmd()`
  - `SlaveProcessCloseCmd()`

Before (bug):
```cpp
ulong created_ms = (ulong)StrToInteger(fields[9]);
```

After (fixed):
```cpp
ulong created_ms = (ulong)StrToDouble(fields[9]);
```

### Verification
1) With MT4 as Master and MT4 as Slave on the same `channel_id`, Slave no longer logs immediate “open_cmd expired” with huge `age_ms`.
2) Slave opens the mirrored position after Master open under normal conditions.


