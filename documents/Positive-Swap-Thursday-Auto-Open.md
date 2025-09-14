## Thursday Auto-Open in Positive Swap Mode (MT4/MT5)

This document explains the new auto-open behavior when `input_trading_positive_swap = true`.

### Summary
- When Positive Swap mode is enabled, on Thursday at a configurable local time, the EA will attempt to open an order automatically if there are no open pairs.
- The open action uses the same synchronized flow as pressing the "Open Now" button on Master to ensure Slave opens together.
- The lots used are configurable and independent via a new input.
- Positions will be closed normally by the standard diffClose condition; due to the dynamic close threshold override window, the close normally happens after 05:30.

### New Inputs
- `input_swap_thursday_open_time` (string, default `"03:30"`): Local time in HH:mm for Thursday auto-open trigger.
- `input_swap_trading_lots` (double, default `0.01`): Lots used for the Thursday auto-open (applies to both Master and Slave via the open command).

### Behavior
1. Applies only when `input_trading_positive_swap = true` and role is Master.
2. Trigger day/time: Thursday at `input_swap_thursday_open_time` (local terminal time).
3. Guard conditions:
   - Skip if there is any open order for the current `symbol/magic`.
   - Skip during Saturday quiet window (not applicable to Thursday but kept for consistency in both builds).
4. Execution:
   - Master calls the same open flow as “Open Now” but with custom lots (`input_swap_trading_lots`).
   - Writes `open_cmd.csv` including audit fields; Slave acknowledges and opens accordingly.
   - Grace windows and watchdog behaviors remain unchanged to avoid immediate close/reconcile.
5. Close behavior: Orders close by standard logic when `diffClose >= close_th`. With Positive Swap overrides, this typically occurs after 05:30.

### Notes
- Time comparisons use `TimeLocal()` and fire once per day by minute equality. If the terminal is started after the exact minute, the scheduled open for that day is skipped.
- This feature does not change thresholds or schedules—only initiates an open when conditions match.
- Available in both `Diff-Grabber.mq4` and `Diff-Grabber.mq5`.


