# Sum Equity Display Feature - Instructions

## Overview
The Sum Equity Display feature provides real-time monitoring of combined equity from both Master and Slave accounts directly on the Master's chart. This feature displays the total equity prominently beside the debug buttons for quick visual reference.

## Feature Details

### Visual Display
- **Location**: Positioned beside the "Open Now" and "Close Now" debug buttons
- **Size**: 200x42 pixels with light gray background
- **Content**: 
  - Header: "Sum Equity" (9pt Arial Bold, Black)
  - Value: "$X,XXX.XX" (12pt Arial Bold, Color-coded)

### Color Coding
- **Green**: Sum equity is above initial capital (profit)
- **Red**: Sum equity is below initial capital (loss)
- **Black**: Sum equity equals initial capital (break-even)

### Activation Condition
The Sum Equity Display is **only visible when**:
```cpp
input_debug_buttons_enabled = true
```

This ensures the feature appears only when debug buttons are active, maintaining clean chart appearance during normal operation.

## Technical Implementation

### Files Modified
1. `FXH-Diff-Grabber.mq4` (MT4 version)
2. `FXH-Diff-Grabber.mq5` (MT5 version)

### Key Components Added

#### 1. Display Geometry Constants
```cpp
// Sum Equity display geometry (beside debug buttons)
int    EQUITY_X = 650;
int    EQUITY_Y = 24;
int    EQUITY_W = 200;
int    EQUITY_H = 42;
```

#### 2. Equity Reading Functions
```cpp
// Get fresh equity from peer account status file
bool ReadPeerEquityFresh(double &equity_out, ulong &ts_out)

// Get sum of master and slave equity (realtime)
double GetSumEquity()
```

#### 3. Display Objects
- `EA_MS_LABEL_EQUITY_BG`: Background rectangle
- `EA_MS_LABEL_EQUITY_LABEL`: "Sum Equity" text
- `EA_MS_LABEL_EQUITY_VALUE`: Dynamic equity value

### Data Sources
- **Master Equity**: `AccountEquity()` (MT4) / `AccountInfoDouble(ACCOUNT_EQUITY)` (MT5)
- **Slave Equity**: Read from `account_slave.csv` file via `ReadPeerEquityFresh()`
- **Freshness Check**: Data must be within `EffectiveHeartbeatTimeoutMs()` to be considered valid

### Update Frequency
- **Real-time**: Updated on every `DisplayUpdate()` call
- **Performance**: Minimal impact - only file read and simple calculations
- **Fallback**: Shows Master equity only if Slave data unavailable

## Usage Instructions

### Enabling the Feature
1. Set `input_debug_buttons_enabled = true` in EA inputs
2. The Sum Equity Display will automatically appear beside debug buttons
3. Display updates in real-time as equity changes

### Disabling the Feature
1. Set `input_debug_buttons_enabled = false`
2. Both debug buttons and Sum Equity Display will be hidden
3. No performance impact when disabled

## Performance Considerations

### Optimizations Implemented
- **Conditional Display**: Only active when debug buttons enabled
- **Efficient File Reading**: Reuses existing file reading infrastructure
- **Minimal Object Creation**: Only 3 chart objects created
- **Smart Color Updates**: Color changes only when profit/loss status changes

### Performance Impact
- **CPU**: Negligible - simple arithmetic operations
- **Memory**: ~3 chart objects when active
- **Network**: No additional network calls
- **File I/O**: Reuses existing peer status file reading

## Troubleshooting

### Common Issues

#### 1. Display Not Appearing
**Cause**: `input_debug_buttons_enabled = false`
**Solution**: Enable debug buttons in EA inputs

#### 2. Shows Only Master Equity
**Cause**: Slave data not available or stale
**Check**: 
- Slave EA running and connected
- File sync working properly
- Heartbeat timeout settings

#### 3. Incorrect Color Coding
**Cause**: Initial capital not set or auto-detected
**Solution**: 
- Set `input_initial_capital_usd` manually, or
- Let system auto-detect from first balance readings

### Debug Information
Monitor these log events for troubleshooting:
- `AUTH_CHECK_*`: Account authorization status
- `HEARTBEAT_*`: Peer connectivity
- File sync errors in EA logs

## Removal Instructions

### Complete Feature Removal
If you need to remove this feature entirely:

#### 1. Remove Display Geometry Constants
Delete these lines:
```cpp
// Sum Equity display geometry (beside debug buttons)
int    EQUITY_X = 650;
int    EQUITY_Y = 24;
int    EQUITY_W = 200;
int    EQUITY_H = 42;
```

#### 2. Remove Equity Functions
Delete these functions:
```cpp
bool ReadPeerEquityFresh(double &equity_out, ulong &ts_out)
double GetSumEquity()
```

#### 3. Remove Display Creation Code
In `DisplayInit()`, remove the Sum Equity Display section:
```cpp
// Sum Equity Display (beside debug buttons)
string eq_bg = OBJ_PREFIX + "EQUITY_BG";
// ... (entire equity display creation block)
```

#### 4. Remove Display Update Code
In `DisplayUpdate()`, remove the Sum Equity update section:
```cpp
// Update Sum Equity Display (Master only, when debug buttons enabled)
if(input_debug_buttons_enabled && input_role==ROLE_MASTER)
{
   // ... (entire equity update block)
}
```

### Partial Disable (Keep Code, Hide Display)
To temporarily disable without removing code:
```cpp
// Change this condition to always false
if(false && input_debug_buttons_enabled && input_role==ROLE_MASTER)
```

## Version Compatibility

### MT4 Version (FXH-Diff-Grabber.mq4)
- Uses `ObjectSet()` and `ObjectSetText()` functions
- `AccountEquity()` for master equity reading

### MT5 Version (FXH-Diff-Grabber.mq5)
- Uses `ObjectSetInteger()`, `ObjectSetString()` functions
- `AccountInfoDouble(ACCOUNT_EQUITY)` for master equity reading

## Future Enhancements

### Potential Improvements
1. **Historical Equity Chart**: Mini-chart showing equity progression
2. **Profit/Loss Percentage**: Show percentage gain/loss from initial capital
3. **Daily/Weekly P&L**: Reset counters for different time periods
4. **Alert Integration**: Notifications when equity reaches certain thresholds
5. **Export Functionality**: Save equity data to CSV files

### Configuration Options
Consider adding these inputs for enhanced control:
```cpp
bool   input_equity_display_enabled = true;    // Independent control
int    input_equity_update_interval_ms = 100;  // Update frequency control
bool   input_equity_show_percentage = false;   // Show % instead of absolute
color  input_equity_profit_color = clrGreen;   // Custom profit color
color  input_equity_loss_color = clrRed;       // Custom loss color
```

---

**Note**: This feature is designed to be lightweight and non-intrusive. It only activates when debug buttons are enabled, ensuring minimal impact on production trading environments.
