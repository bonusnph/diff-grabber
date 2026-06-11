//+------------------------------------------------------------------+
//|                                                     SFX-SYNC.mq4 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#define SFX_SYNC_EA_VERSION "1.13"

#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   SFX_SYNC_EA_VERSION
#property strict

#include <SumoFx/winsocket.mqh>

#define SFX_SYNC_LOG_FILE_STEM "SFX-SYNC"

enum ENUM_ROLE
{
   ROLE_SOURCE_MASTER = 0,
   ROLE_EXECUTOR_SLAVE = 1
};

enum ENUM_SIDE
{
   SIDE_BUY = 0,
   SIDE_SELL = 1,
   SIDE_AUTO = 2
};

enum ENUM_DIFF_SIGNAL_MODE
{
   DIFF_SIGNAL_SIMPLE = 0,
   DIFF_SIGNAL_RAW_STABILITY = 1,
   DIFF_SIGNAL_AVG = 2
};

enum ENUM_OPEN_MODE
{
   OPEN_BALANCED = 0,
   OPEN_MASTER_FIRST = 1
};

enum ENUM_CLOSE_MODE
{
   CLOSE_BALANCED = 0,
   CLOSE_MASTER_FIRST = 1,
   CLOSE_MASTER_FIRST_WITH_RESCUE = 2
};

enum ENUM_LOCK_SCOPE
{
   LOCK_SCOPE_PAIR_ACTION = 0,
   LOCK_SCOPE_PAIR_ANY_ACTION = 1,
   LOCK_SCOPE_GROUP_GLOBAL = 2
};

input ENUM_ROLE I_ROLE = ROLE_SOURCE_MASTER; // Master streams orders; slave copies
input ushort    I_PORT = 65110;              // TCP port (same on master and slave)
string    I_MASTER_IP = "127.0.0.1";   // Slave only: master host or VPN IP
string    I_SECRET = "Password on this channel"; // Channel password (must match peer)
input ENUM_SIDE I_MASTER_SIDE = SIDE_AUTO;     // Side master trades; slave mirrors opposite
input double    I_LOT = 0.01;                 // Lot per synced order side
input bool      I_DYN_LOT_ENABLED = false;         // Dynamic lot: enable adaptive lot sizing
input double    I_DYN_LOT_MIN = 0.01;              // Dynamic lot: lower bound (inclusive)
input double    I_DYN_LOT_MAX = 1.00;              // Dynamic lot: upper bound (inclusive)
input double    I_DYN_LOT_STEP_UP = 0.01;          // Dynamic lot: increment on profit streak
input double    I_DYN_LOT_STEP_DOWN = 0.01;        // Dynamic lot: decrement on loss streak
input int       I_DYN_LOT_PROFIT_STREAK_N = 3;     // Dynamic lot: consecutive profit rounds to increase
input int       I_DYN_LOT_LOSS_STREAK_M = 3;       // Dynamic lot: consecutive loss rounds to decrease
input int       I_DYN_LOT_STABLE_LOOP_Y = 3;       // Dynamic lot: inc->dec oscillations before Stable-Lock
input bool      I_DYN_LOT_COUNT_SCHEDULED = false; // Dynamic lot: count weekend/schedule closes in streak
int       I_SLIPPAGE = 30;              // Max slippage (points) for sync orders
input ENUM_OPEN_MODE I_OPEN_MODE = OPEN_BALANCED;   // How to sequence master/slave opens
input ENUM_CLOSE_MODE I_CLOSE_MODE = CLOSE_BALANCED; // How to sequence closes (and rescue)
input bool      I_LOCK_ENABLED = true;                   // Enable cross-instance global lock for open/close intents
input string    I_LOCK_GROUP = "DEFAULT";                // User-defined lock namespace
input ENUM_LOCK_SCOPE I_LOCK_SCOPE = LOCK_SCOPE_PAIR_ACTION; // Lock granularity inside a group
input int       I_LOCK_STALE_MS = 8000;                  // Reclaim lock if holder appears stale for this many ms
input bool      I_LOCK_DEBUG_LOG = false;                // Emit lock acquire/release diagnostics
int       I_OPEN_ROLLBACK_TIMEOUT_MS = 10000;
int       I_SLAVE_OPEN_TIMEOUT_MS = 2200;
int       I_SLAVE_OPEN_RETRY_COUNT = 3;
int       I_SLAVE_OPEN_RETRY_INTERVAL_MS = 400;
int       I_MASTER_OPEN_RETRY_COUNT_BALANCED = 3;      // Master open retries in OPEN_BALANCED only
int       I_MASTER_OPEN_RETRY_INTERVAL_MS = 300;       // Delay between balanced master retries
int       I_SLAVE_CLOSE_TIMEOUT_MS = 2200;
int       I_SLAVE_CLOSE_RETRY_COUNT = 3;
int       I_SLAVE_CLOSE_RETRY_INTERVAL_MS = 400;
int       I_SLAVE_PENDING_COMMIT_TIMEOUT_MS = 10000; // Slave waits this long for COMMIT before self-closing pending leg
int       I_PAIR_STATUS_STALE_MS = 5000;          // Max age of slave PAIR_STATUS before protective close
input int I_PAIR_SETTLE_GRACE_MS = 10000;         // Grace ms after OPEN_INTENT before mismatch close paths fire
int I_OPEN_TX_DISCONNECT_GRACE_MS = 10000;  // Grace ms before closing master leg on disconnect during OPEN_TX
int       I_PAIR_CLEAR_CROSSKEY_MIN_AGE_SEC = 10; // Allow clear-state key mismatch only after pair is old enough
int       I_ORDER_CLOSE_RETRY_COUNT = 8;             // OrderClose attempts per call (requote/off quotes/etc.)
int       I_ORDER_CLOSE_RETRY_INTERVAL_MS = 100;    // Delay between attempts (ms); 0 = no Sleep
int       I_ORDER_CLOSE_MAX_BLOCK_MS = 350;      // Cap total blocking time inside one close call (ms)
int       I_ORPHAN_RECOVERY_COOLDOWN_MS = 3000;  // Min delay between orphan scans (ms)
int       I_ORPHAN_CONFIRM_CYCLES = 3;           // Require orphan detection for N cycles before force-close
int       I_REOPEN_GUARD_AFTER_CLOSE_MS = 3000;  // Guard window after close before next open is allowed
int       I_FORCE_FLAT_TIMEOUT_MS = 1200;        // Wait for FORCE_FLAT_RESULT before retry/fail
int       I_FORCE_FLAT_RETRY_COUNT = 1;          // Extra retries when FORCE_FLAT result is missing/fail
int       I_FORCE_FLAT_RETRY_INTERVAL_MS = 400;  // Delay before FORCE_FLAT retry
int       I_RESCUE_MAX_ATTEMPTS = 3;
bool      I_BLOCK_NEW_OPEN_WHEN_DEGRADED = true;
input int       I_LOOP_MS = 50;
bool      I_SYNC_LOG_CLEAR_ON_INIT = false; // Delete EA log files when EA attaches

bool                I_DIFF_SYNC_ENABLED = true;           // Master: diff-driven auto open/close
input ENUM_DIFF_SIGNAL_MODE I_DIFF_SIGNAL_MODE_VAL = DIFF_SIGNAL_AVG; // Signal style: SIMPLE, RAW stability, or AVG
input int               I_DIFF_OPEN_THRESHOLD_PTS = 20;          // Diff (pts) needed for auto-open signal
input int               I_DIFF_CLOSE_THRESHOLD_PTS = 20;          // Diff (pts) needed for auto-close signal
input int               I_DIFF_QUOTES_FRESH_MS = 850;             // Master: max lag (ms) for last quote observation on each side (manual; also AUTO fallback until warmup)
input bool              I_DIFF_QUOTES_FRESH_AUTO = true;    // Master: derive fresh limit from EMA of observed master/slave quote gaps (else use I_DIFF_QUOTES_FRESH_MS)
double            I_DIFF_QF_AUTO_MUL = 1.78;           // AUTO: scale factor on max(master EMA gap, slave EMA gap) before margin and clamp
int               I_DIFF_QF_AUTO_MARGIN_MS = 220;       // AUTO: extra ms added after scaling (headroom vs jitter)
int               I_DIFF_QF_AUTO_MIN_MS = 520;         // AUTO: floor for computed fresh ms (prevents an overly tight limit)
int               I_DIFF_QF_AUTO_MAX_MS = 7200;        // AUTO: ceiling for computed fresh ms (prevents runaway when one side stalls)
int               I_DIFF_QF_AUTO_WARMUP_N = 22;        // AUTO: need at least this many gap samples on master and on slave before AUTO replaces manual fresh ms
input int               I_DIFF_MAX_SPREAD_SELF = 30;              // Block if this chart spread exceeds (pts)
input int               I_DIFF_MAX_SPREAD_PEER = 30;             // Block if slave spread exceeds (pts)
input int               I_DIFF_OPEN_COOLDOWN_SEC = 660;            // Wait after an auto-open before next auto-open
input int               I_DIFF_CLOSE_COOLDOWN_SEC = 600;            // Base delay before diff auto-close; also post-open guard

int               I_DIFF_AVG_PERIOD = 9;                  // EMA period for AVG mode
bool              I_DIFF_USE_PREFILTER_MEDIAN = true;     // Median filter before EMA (AVG mode)
int               I_DIFF_PREFILTER_WINDOW = 3;            // Median window (odd, >=3)
int               I_DIFF_HYSTERESIS_PTS = 0;                // Extra points on open threshold (AVG mode)
int               I_DIFF_EPSILON_PTS = 1;                   // Extra margin for real-diff confirmation
bool              I_DIFF_REAL_CONFIRM = true;             // After AVG trigger, require raw diff confirmation
int               I_DIFF_CONFIRM_TICKS = 2;                 // Ticks in a row for confirmation
int               I_DIFF_CONFIRM_TIMEOUT_MS = 300;        // Abandon pending confirm after (ms)
int               I_DIFF_AVG_SIGNAL_COOLDOWN_MS = 400;      // Min gap between AVG open signals (ms)

int               I_DIFF_RAW_STABILITY_TICKS = 3;          // Consecutive above-threshold ticks (RAW mode)
int               I_DIFF_RAW_HYSTERESIS_OFFSET = 10;     // Points below threshold to reset streak (RAW)
int               I_DIFF_RAW_STABILITY_TIMEOUT_MS = 500; // Abandon RAW wait after (ms)

input bool              I_DIFF_ZONE_STABILITY_ENABLED = true;   // Zone filter on diff before firing
input int               I_DIFF_ZONE_STABILITY_TICKS = 7;         // Ticks in positive zone required
input int               I_DIFF_ZONE_NEGATIVE_THRESHOLD = -1;    // Pts at/below = negative zone

input bool              I_CLOSE_ONLY_SCHEDULE_MASTER = true;   // Master: time-based close-only (local clock)
input bool              I_CLOSE_ONLY_MON_EN = false;             // Use Monday window
input string            I_CLOSE_ONLY_MON_START = "02:00";      // Monday begin HH:mm (local)
input string            I_CLOSE_ONLY_MON_END = "06:00";        // Monday end HH:mm (local)
input bool              I_CLOSE_ONLY_TUE_EN = false;             // Use Tuesday window
input string            I_CLOSE_ONLY_TUE_START = "02:00";        // Tuesday begin HH:mm (local)
input string            I_CLOSE_ONLY_TUE_END = "06:00";        // Tuesday end HH:mm (local)
input bool              I_CLOSE_ONLY_WED_EN = false;             // Use Wednesday window
input string            I_CLOSE_ONLY_WED_START = "02:00";        // Wednesday begin HH:mm (local)
input string            I_CLOSE_ONLY_WED_END = "06:00";        // Wednesday end HH:mm (local)
input bool              I_CLOSE_ONLY_THU_EN = true;              // Use Thursday window
input string            I_CLOSE_ONLY_THU_START = "01:00";        // Thursday begin HH:mm (local)
input string            I_CLOSE_ONLY_THU_END = "06:00";        // Thursday end HH:mm (local)
input bool              I_CLOSE_ONLY_FRI_EN = false;             // Use Friday window
input string            I_CLOSE_ONLY_FRI_START = "02:00";        // Friday begin HH:mm (local)
input string            I_CLOSE_ONLY_FRI_END = "06:00";        // Friday end HH:mm (local)

input bool              I_CLOSE_ONLY_WEEKEND_ENABLED = true;           // Weekend strip; combined with daily rows (OR)
input bool              I_CLOSE_ONLY_WEEKEND_START_CLOSE_ALL = true; // Saturday START: close all EA orders (master + slave)
input string            I_CLOSE_ONLY_WEEKEND_PRE_FRIDAY = "02:00"; // Friday time (local): PRE — enter close-only
input string            I_CLOSE_ONLY_WEEKEND_START_SAT = "03:00"; // Saturday (local): START time for close-all-orders (master+slave)
input string            I_CLOSE_ONLY_WEEKEND_END_MON = "08:00";    // Monday time (local): END — leave close-only

input bool              I_DND_SCHEDULE_MASTER = true;             // Master: time-based do-not-disturb (local clock)
input bool              I_DND_MON_EN = true;                      // Use Monday window
input string            I_DND_MON_START = "03:40";                 // Monday begin HH:mm (local)
input string            I_DND_MON_END = "05:20";                   // Monday end HH:mm (local)
input bool              I_DND_TUE_EN = true;                      // Use Tuesday window
input string            I_DND_TUE_START = "03:40";                 // Tuesday begin HH:mm (local)
input string            I_DND_TUE_END = "05:20";                   // Tuesday end HH:mm (local)
input bool              I_DND_WED_EN = true;                      // Use Wednesday window
input string            I_DND_WED_START = "03:40";                 // Wednesday begin HH:mm (local)
input string            I_DND_WED_END = "05:20";                   // Wednesday end HH:mm (local)
input bool              I_DND_THU_EN = true;                      // Use Thursday window
input string            I_DND_THU_START = "03:40";                 // Thursday begin HH:mm (local)
input string            I_DND_THU_END = "05:20";                   // Thursday end HH:mm (local)
input bool              I_DND_FRI_EN = true;                      // Use Friday window
input string            I_DND_FRI_START = "03:40";                 // Friday begin HH:mm (local)
input string            I_DND_FRI_END = "05:20";                   // Friday end HH:mm (local)
input bool              I_DND_WEEKEND_ENABLED = true;             // Weekend strip; combined with daily rows (OR)
input string            I_DND_WEEKEND_START_SAT = "03:40";         // Saturday time (local): START — enter DND
input string            I_DND_WEEKEND_END_MON = "05:20";           // Monday time (local): END — leave DND

ServerSocket *G_SERVER = NULL;
ClientSocket *G_PEER = NULL;

string G_SYMBOL = "";
bool   G_HANDSHAKE_OK = false;
bool   G_OPEN_SIGNAL_REQUESTED = false;
bool   G_CLOSE_SIGNAL_REQUESTED = false;
string G_OPEN_SIGNAL_REASON = "UI_BUTTON";
string G_CLOSE_SIGNAL_REASON = "UI_BUTTON";
string G_PENDING_OPEN_INTENT_TAG = "UI_BUTTON";

// Pair state (master side)
bool   G_PAIR_ACTIVE = false;
string G_PAIR_KEY = "";
int    G_PAIR_MASTER_TICKET = -1;
int    G_PAIR_SLAVE_TICKET = -1;
bool   G_SLAVE_PAIR_OPEN_REPORT = false;
int    G_SLAVE_EA_OPEN_COUNT = 0;
ulong  G_LAST_SLAVE_PAIR_STATUS_MS = 0;
ulong  G_PAIR_OPENED_MS = 0;
ulong  G_PAIR_OPEN_INTENT_MS = 0;
bool   G_DEGRADED = false;
int    G_RESCUE_ATTEMPTS_USED = 0;

// Open transaction state (master side)
bool   G_OPEN_TX_ACTIVE = false;
string G_OPEN_TX_ID = "";
ulong  G_OPEN_OVERALL_DEADLINE_MS = 0;
ulong  G_OPEN_SLAVE_WAIT_DEADLINE_MS = 0;
int    G_OPEN_RETRY_LEFT = 0;
bool   G_OPEN_MASTER_OK = false;
int    G_OPEN_MASTER_TICKET = -1;
bool   G_OPEN_SLAVE_OK = false;
int    G_OPEN_SLAVE_TICKET = -1;
int    G_OPEN_LAST_ERROR_MASTER = 0;
int    G_OPEN_LAST_ERROR_SLAVE = 0;
string G_OPEN_SIDE = "";
double G_OPEN_LOT_SLAVE = 0.0;
ulong  G_OPEN_DISCONNECT_DEADLINE_MS = 0;

// Close transaction state (master side)
bool   G_CLOSE_TX_ACTIVE = false;
string G_CLOSE_TX_ID = "";
string G_CLOSE_REASON = "";
ulong  G_CLOSE_OVERALL_DEADLINE_MS = 0;
ulong  G_CLOSE_SLAVE_WAIT_DEADLINE_MS = 0;
int    G_CLOSE_RETRY_LEFT = 0;
bool   G_CLOSE_MASTER_OK = false;
bool   G_CLOSE_SLAVE_OK = false;
int    G_CLOSE_LAST_ERROR_MASTER = 0;
int    G_CLOSE_LAST_ERROR_SLAVE = 0;
double G_CLOSE_SLAVE_BALANCE = 0.0;
double G_DYN_BAL_PREV_SUM     = 0.0;
bool   G_DYN_BAL_PREV_VALID   = false;
string G_OPEN_LOCK_KEY = "";
double G_OPEN_LOCK_TOKEN = 0.0;
string G_CLOSE_LOCK_KEY = "";
double G_CLOSE_LOCK_TOKEN = 0.0;
bool   G_FORCE_FLAT_ACTIVE = false;
string G_FORCE_FLAT_TX_ID = "";
string G_FORCE_FLAT_REASON = "";
ulong  G_FORCE_FLAT_WAIT_DEADLINE_MS = 0;
int    G_FORCE_FLAT_RETRY_LEFT = 0;
ulong  G_FORCE_FLAT_RETRY_READY_MS = 0;

// Slave local state
string G_SLAVE_PENDING_OPEN_TXID = "";
int    G_SLAVE_PENDING_OPEN_TICKET = -1;
ulong  G_SLAVE_PENDING_OPEN_DEADLINE_MS = 0;
string G_SLAVE_LAST_OPEN_TXID = "";
int    G_SLAVE_LAST_OPEN_OK = -1; // -1 unknown, 0 fail, 1 success
int    G_SLAVE_LAST_OPEN_TICKET = -1;
int    G_SLAVE_LAST_OPEN_ERR = 0;
ulong  G_SLAVE_LAST_OPEN_STARTED_MS = 0;
string G_SLAVE_PAIR_KEY = "";
int    G_SLAVE_PAIR_TICKET = -1;

bool   G_SLAVE_DUP_CHANNEL_SHUTDOWN = false;

ENUM_SIDE G_DIFF_AUTO_EFF_SIDE = SIDE_BUY;
bool      G_DIFF_AUTO_SIDE_LOCKED = false;
bool      G_DIFF_AUTO_EVER_OPENED = false;

double    G_DIFF_SELF_BID = 0.0, G_DIFF_SELF_ASK = 0.0;
ulong     G_DIFF_SELF_MS = 0;
ulong     G_DIFF_SELF_LAST_TICK_MSC = 0;
double    G_DIFF_SLAVE_BID = 0.0, G_DIFF_SLAVE_ASK = 0.0;
ulong     G_DIFF_SLAVE_MS = 0;
ulong     G_DIFF_SLAVE_QUOTE_MSC = 0;
int       G_DIFF_SLAVE_TRADE_MODE = -1; // From each SLAVE frame (8 fields); -1 until first accepted frame
bool      G_DIFF_SLAVE_QUOTE_OK = false;
ulong     G_QMON_START_MS = 0;
ulong     G_QMON_MASTER_TICKS = 0;
ulong     G_QMON_SLAVE_FRAMES = 0;
double    G_QMON_EMA_GAP_M = 0.0;
double    G_QMON_EMA_GAP_S = 0.0;
int       G_QMON_N_M = 0;
int       G_QMON_N_S = 0;
double    G_DIFF_SLAVE_STREAM_PROFIT = 0.0;
double    G_DIFF_MASTER_MAGIC_PL = 0.0;

ulong     G_DIFF_LAST_OPEN_SIGNAL_MS = 0;
ulong     G_DIFF_LAST_CLOSE_SIGNAL_MS = 0;

double    G_DIFF_SIGNAL_SNAP_OPEN_PTS = 0.0;
double    G_DIFF_SIGNAL_SNAP_CLOSE_PTS = 0.0;
double    G_DIFF_HUD_LAST_AVG_OPEN = 0.0;
double    G_DIFF_HUD_LAST_AVG_CLOSE = 0.0;
string    G_DIFF_LAST_OPEN_INTENT_TAG = "UI_BUTTON";

double    G_DIFF_MED_OPEN[16], G_DIFF_MED_CLOSE[16];
int       G_DIFF_MED_OPEN_IDX = 0, G_DIFF_MED_OPEN_COUNT = 0;
int       G_DIFF_MED_CLOSE_IDX = 0, G_DIFF_MED_CLOSE_COUNT = 0;

double    G_DIFF_EMA_OPEN = 0.0, G_DIFF_EMA_CLOSE = 0.0;
bool      G_DIFF_EMA_OPEN_INIT = false, G_DIFF_EMA_CLOSE_INIT = false;

ulong     G_DIFF_LAST_AVG_OPEN_SIG_MS = 0, G_DIFF_LAST_AVG_CLOSE_SIG_MS = 0;

bool      G_DIFF_OPEN_PENDING = false;
double    G_DIFF_OPEN_SNAP_AVG = 0.0;
int       G_DIFF_OPEN_OK_COUNT = 0;
ulong     G_DIFF_OPEN_DEAD_MS = 0;

bool      G_DIFF_CLOSE_PENDING = false;
double    G_DIFF_CLOSE_SNAP_AVG = 0.0;
int       G_DIFF_CLOSE_OK_COUNT = 0;
ulong     G_DIFF_CLOSE_DEAD_MS = 0;

bool      G_DIFF_RAW_OPEN_PEND = false;
int       G_DIFF_RAW_OPEN_CNT = 0;
ulong     G_DIFF_RAW_OPEN_START = 0;

bool      G_DIFF_RAW_CLOSE_PEND = false;
int       G_DIFF_RAW_CLOSE_CNT = 0;
ulong     G_DIFF_RAW_CLOSE_START = 0;

bool      G_DIFF_OPEN_ZONE_OK = false;
int       G_DIFF_OPEN_ZP = 0, G_DIFF_OPEN_ZN = 0;
bool      G_DIFF_CLOSE_ZONE_OK = false;
int       G_DIFF_CLOSE_ZP = 0, G_DIFF_CLOSE_ZN = 0;

bool   G_SYNC_LOG_FILE_WARNED = false;

bool   G_CLOSE_ONLY_SCHEDULE_ACTIVE = false;
bool   G_CLOSE_ONLY_MANUAL_ON = false;
bool   G_CLOSE_ONLY_SCHEDULE_ACTIVE_PREV = false;
bool   G_CLOSE_ONLY_SCHEDULE_INIT = false;
bool   G_DND_SCHEDULE_ACTIVE = false;
bool   G_DND_MANUAL_ON = false;
bool   G_DND_SCHEDULE_ACTIVE_PREV = false;
bool   G_DND_SCHEDULE_INIT = false;
int    G_WEEKEND_FLAT_LAST_KEY = 0;
ulong  G_LAST_ORPHAN_RECOVERY_MS = 0;
int    G_ORPHAN_DETECT_STREAK = 0;
ulong  G_LAST_PAIR_CLOSE_MS = 0;

// Dynamic lot state (master side)
double G_DYN_LOT              = 0.0;
int    G_DYN_PROFIT_STREAK    = 0;
int    G_DYN_LOSS_STREAK      = 0;
int    G_DYN_LOOP_COUNT       = 0;
double G_DYN_STABLE_LOT       = 0.0;
bool   G_DYN_STABLE_LOCK      = false;
int    G_DYN_LAST_ADJ_DIR     = 0;
double G_DYN_LAST_ADJ_FROM    = 0.0;
bool   G_DYN_LAST_CLOSE_SCHEDULED = false;
double G_SLAVE_BALANCE_REPORT = 0.0;
bool   G_SLAVE_BALANCE_VALID  = false;

string SyncPortTag()
{
   return StringFormat("[SFX-SYNC:%d]", (int)I_PORT);
}

string SyncVersionTag()
{
   return StringFormat("[ver:%s]", SFX_SYNC_EA_VERSION);
}

int OrderMagic()
{
   return (int)I_PORT;
}

string Mq4TrimLeadingWs(const string s)
{
   int n = (int)StringLen(s);
   int i = 0;
   for(; i < n; i++)
   {
      ushort ch = StringGetCharacter(s, i);
      if(ch != ' ' && ch != 9)
         break;
   }
   if(i <= 0)
      return s;
   return StringSubstr(s, i);
}

string NormalizeLogTail(const string message_line)
{
   const string LEGACY = "[SFX-SYNC]";
   if(StringFind(message_line, LEGACY, 0) != 0)
      return message_line;
   string rest = StringSubstr(message_line, StringLen(LEGACY));
   return Mq4TrimLeadingWs(rest);
}

void ExpertPrintLn(const string message_line)
{
   Print(SyncPortTag() + " " + SyncVersionTag() + " " + NormalizeLogTail(message_line));
}

ulong NowMs()
{
   return (ulong)GetTickCount();
}

bool PairWithinSettleGrace()
{
   if(G_PAIR_OPEN_INTENT_MS == 0) return false;
   return (NowMs() - G_PAIR_OPEN_INTENT_MS) < (ulong)MathMax(1000, I_PAIR_SETTLE_GRACE_MS);
}

double DynBrokerLotStep()
{
   double bs = MarketInfo(G_SYMBOL, MODE_LOTSTEP);
   if(bs <= 0.0)
      bs = 0.01;
   return bs;
}

double DynEffectiveStep()
{
   return MathMax(0.01, DynBrokerLotStep());
}

double DynNormalizeLot(const double x)
{
   double step = DynEffectiveStep();
   double snapped = MathRound(x / step) * step;
   snapped = NormalizeDouble(snapped, 2);

   double lo = NormalizeDouble(I_DYN_LOT_MIN, 2);
   double hi = NormalizeDouble(I_DYN_LOT_MAX, 2);
   double broker_min = MarketInfo(G_SYMBOL, MODE_MINLOT);
   double broker_max = MarketInfo(G_SYMBOL, MODE_MAXLOT);
   if(broker_min > 0.0 && broker_min > lo) lo = NormalizeDouble(broker_min, 2);
   if(broker_max > 0.0 && broker_max < hi) hi = NormalizeDouble(broker_max, 2);
   if(hi < lo) hi = lo;

   if(snapped < lo) snapped = lo;
   if(snapped > hi) snapped = hi;
   return NormalizeDouble(snapped, 2);
}

bool DynLotEqual(const double a, const double b)
{
   return MathAbs(a - b) < 0.0000001;
}

double DynActiveLot()
{
   if(!I_DYN_LOT_ENABLED)
      return I_LOT;
   return G_DYN_LOT;
}

void DynRefreshHud(); // forward
void DynResetState()
{
   G_DYN_LOT             = DynNormalizeLot(I_LOT);
   G_DYN_BAL_PREV_VALID  = false;
   G_DYN_BAL_PREV_SUM    = 0.0;
   G_DYN_PROFIT_STREAK   = 0;
   G_DYN_LOSS_STREAK     = 0;
   G_DYN_LOOP_COUNT      = 0;
   G_DYN_STABLE_LOCK     = false;
   G_DYN_STABLE_LOT      = 0.0;
   G_DYN_LAST_ADJ_DIR    = 0;
   G_DYN_LAST_ADJ_FROM   = 0.0;
   G_DYN_LAST_CLOSE_SCHEDULED = false;
}

void DynInitOnAttach()
{
   DynResetState();
   if(I_DYN_LOT_ENABLED)
   {
      double step = DynEffectiveStep();
      if(I_DYN_LOT_STEP_UP < step || I_DYN_LOT_STEP_DOWN < step)
      {
         SyncLog(StringFormat(
            "[DYNLOT] warning: input step (up=%.2f dn=%.2f) below broker/effective step=%.2f — will snap",
            I_DYN_LOT_STEP_UP, I_DYN_LOT_STEP_DOWN, step));
      }
      SyncLog(StringFormat("[DYNLOT] init enabled lot=%.2f min=%.2f max=%.2f step_up=%.2f step_dn=%.2f n=%d m=%d y=%d step_eff=%.2f",
         G_DYN_LOT, I_DYN_LOT_MIN, I_DYN_LOT_MAX,
         I_DYN_LOT_STEP_UP, I_DYN_LOT_STEP_DOWN,
         I_DYN_LOT_PROFIT_STREAK_N, I_DYN_LOT_LOSS_STREAK_M, I_DYN_LOT_STABLE_LOOP_Y,
         step));
   }
}

void DynTryIncrease()
{
   if(G_DYN_STABLE_LOCK)
   {
      SyncLog(StringFormat("[DYNLOT] increase blocked: stable-lock at %.2f (current=%.2f)",
                           G_DYN_STABLE_LOT, G_DYN_LOT));
      return;
   }
   double prev = G_DYN_LOT;
   double next = DynNormalizeLot(prev + I_DYN_LOT_STEP_UP);
   if(DynLotEqual(next, prev))
   {
      SyncLog(StringFormat("[DYNLOT] increase clamped at max=%.2f (no change)", prev));
      return;
   }
   G_DYN_LAST_ADJ_FROM = prev;
   G_DYN_LAST_ADJ_DIR  = 1;
   G_DYN_LOT = next;
   SyncLog(StringFormat("[DYNLOT] inc %.2f -> %.2f", prev, next));
}

void DynTryDecrease()
{
   double prev = G_DYN_LOT;
   double next = DynNormalizeLot(prev - I_DYN_LOT_STEP_DOWN);

   if(G_DYN_LAST_ADJ_DIR == 1 && DynLotEqual(next, G_DYN_LAST_ADJ_FROM))
   {
      G_DYN_LOOP_COUNT++;
      if(!G_DYN_STABLE_LOCK && G_DYN_LOOP_COUNT >= MathMax(1, I_DYN_LOT_STABLE_LOOP_Y))
      {
         G_DYN_STABLE_LOCK = true;
         G_DYN_STABLE_LOT  = next;
         SyncLog(StringFormat("[DYNLOT] STABLE-LOCK engaged at %.2f (loops=%d)",
                              G_DYN_STABLE_LOT, G_DYN_LOOP_COUNT));
      }
   }

   if(G_DYN_STABLE_LOCK && next < G_DYN_STABLE_LOT - 0.0000001)
   {
      SyncLog(StringFormat("[DYNLOT] STABLE-LOCK released: dec %.2f below stable=%.2f",
                           next, G_DYN_STABLE_LOT));
      G_DYN_STABLE_LOCK = false;
      G_DYN_LOOP_COUNT  = 0;
   }

   if(DynLotEqual(next, prev))
   {
      SyncLog(StringFormat("[DYNLOT] decrease clamped at min=%.2f (no change)", prev));
      return;
   }
   G_DYN_LAST_ADJ_FROM = prev;
   G_DYN_LAST_ADJ_DIR  = -1;
   G_DYN_LOT = next;
   SyncLog(StringFormat("[DYNLOT] dec %.2f -> %.2f", prev, next));
}

void DynOnPairClosed(const bool scheduled)
{
   if(!I_DYN_LOT_ENABLED) return;

   const double masterBal = AccountBalance();
   const bool haveSlave   = (G_CLOSE_SLAVE_BALANCE > 0.0 || G_SLAVE_BALANCE_VALID);
   const double slaveBal  = (G_CLOSE_SLAVE_BALANCE > 0.0) ? G_CLOSE_SLAVE_BALANCE : (G_SLAVE_BALANCE_VALID ? G_SLAVE_BALANCE_REPORT : 0.0);
   const double sumNow    = masterBal + slaveBal;

   if(scheduled && !I_DYN_LOT_COUNT_SCHEDULED)
   {
      G_DYN_BAL_PREV_SUM   = sumNow;
      G_DYN_BAL_PREV_VALID = haveSlave;
      SyncLog(StringFormat("[DYNLOT] scheduled close — baseline refresh sum=%.2f (slave_valid=%s)",
                           sumNow, haveSlave ? "true" : "false"));
      return;
   }

   if(!G_DYN_BAL_PREV_VALID || !haveSlave)
   {
      G_DYN_BAL_PREV_SUM   = sumNow;
      G_DYN_BAL_PREV_VALID = haveSlave;
      SyncLog(StringFormat("[DYNLOT] baseline set sum=%.2f (slave_valid=%s)",
                           sumNow, haveSlave ? "true" : "false"));
      return;
   }

   const double delta = sumNow - G_DYN_BAL_PREV_SUM;
   if(delta > 0.0)
   {
      G_DYN_PROFIT_STREAK++;
      G_DYN_LOSS_STREAK = 0;
      SyncLog(StringFormat("[DYNLOT] round PROFIT delta=%.2f streak=%d/%d sum=%.2f prev_sum=%.2f",
                           delta, G_DYN_PROFIT_STREAK, I_DYN_LOT_PROFIT_STREAK_N, sumNow, G_DYN_BAL_PREV_SUM));
      if(G_DYN_PROFIT_STREAK >= MathMax(1, I_DYN_LOT_PROFIT_STREAK_N))
      {
         DynTryIncrease();
         G_DYN_PROFIT_STREAK = 0;
      }
   }
   else if(delta < 0.0)
   {
      G_DYN_LOSS_STREAK++;
      G_DYN_PROFIT_STREAK = 0;
      SyncLog(StringFormat("[DYNLOT] round LOSS delta=%.2f streak=%d/%d sum=%.2f prev_sum=%.2f",
                           delta, G_DYN_LOSS_STREAK, I_DYN_LOT_LOSS_STREAK_M, sumNow, G_DYN_BAL_PREV_SUM));
      if(G_DYN_LOSS_STREAK >= MathMax(1, I_DYN_LOT_LOSS_STREAK_M))
      {
         DynTryDecrease();
         G_DYN_LOSS_STREAK = 0;
      }
   }
   else
   {
      SyncLog(StringFormat("[DYNLOT] round FLAT delta=0 sum=%.2f prev_sum=%.2f", sumNow, G_DYN_BAL_PREV_SUM));
   }

   G_DYN_BAL_PREV_SUM = sumNow;
}

string DynHudLine()
{
   if(!I_DYN_LOT_ENABLED)
      return StringFormat("DynLot: OFF (fixed=%.2f)\n", I_LOT);
   string stable_tail = "";
   if(G_DYN_STABLE_LOCK)
      stable_tail = StringFormat(" STABLE-LOCK@%.2f (inc-blocked)", G_DYN_STABLE_LOT);
   return StringFormat(
      "DynLot: ON cur=%.2f [min=%.2f max=%.2f step+=%.2f step-=%.2f] up=%d/%d dn=%d/%d loop=%d/%d%s\n",
      G_DYN_LOT, I_DYN_LOT_MIN, I_DYN_LOT_MAX,
      I_DYN_LOT_STEP_UP, I_DYN_LOT_STEP_DOWN,
      G_DYN_PROFIT_STREAK, I_DYN_LOT_PROFIT_STREAK_N,
      G_DYN_LOSS_STREAK,   I_DYN_LOT_LOSS_STREAK_M,
      G_DYN_LOOP_COUNT,    I_DYN_LOT_STABLE_LOOP_Y,
      stable_tail);
}

void DynRefreshHud()
{
}

bool DynCloseReasonIsScheduled(const string reason)
{
   if(reason == "WEEKEND_FLATTEN") return true;
   if(reason == "SCHEDULE")        return true;
   if(reason == "DISCONNECT")      return true;
   if(reason == "PAIR_BROKEN")     return true;
   if(reason == "PAIR_STATUS_STALE") return true;
   if(reason == "CLOSE_PATH_RECONCILE") return true;
   if(reason == "SLAVE_ORPHAN_RECONCILE") return true;
   return false;
}

void CloseOnlyRefreshButton();
void DoNotDisturbRefreshButton();
void ClearDegradedRefreshButton();
bool TryClearDegraded(const string reason);
bool MasterHasAnyLiveEaLeg();

string DiffHudMasterCommentTail();

string DiffHudSignalOpenProgressBlock();
string DiffHudSignalCloseProgressBlock();

bool DiffIsMasterAuto()
{
   return (I_MASTER_SIDE == SIDE_AUTO);
}

ENUM_SIDE DiffEffectiveMasterSide()
{
   if(!DiffIsMasterAuto())
      return I_MASTER_SIDE;
   return G_DIFF_AUTO_EFF_SIDE;
}

bool DiffMasterBuyEffective()
{
   return (DiffEffectiveMasterSide() == SIDE_BUY);
}

string LockScopeName()
{
   if(I_LOCK_SCOPE == LOCK_SCOPE_GROUP_GLOBAL)
      return "GROUP_GLOBAL";
   if(I_LOCK_SCOPE == LOCK_SCOPE_PAIR_ANY_ACTION)
      return "PAIR_ANY_ACTION";
   return "PAIR_ACTION";
}

string LockActionStateText(const string key, const string own_key, const double own_token)
{
   if(StringLen(key) == 0)
      return "n/a";
   if(StringLen(own_key) > 0 && own_key == key && own_token > 0.0)
      return "own";
   if(!GlobalVariableCheck(key))
      return "free";
   double held = GlobalVariableGet(key);
   if(held <= 0.0)
      return "free";
   ulong held_ms = (ulong)MathFloor(MathMax(0.0, held));
   ulong now_ms = NowMs();
   ulong age_ms = (now_ms > held_ms) ? (now_ms - held_ms) : 0;
   return StringFormat("busy/%I64ums", age_ms);
}

string LockHudMasterCommentLine()
{
   if(!I_LOCK_ENABLED)
      return "Lock: OFF\n";

   string open_key = BuildActionLockKey("OPEN");
   string close_key = BuildActionLockKey("CLOSE");
   string open_state = LockActionStateText(open_key, G_OPEN_LOCK_KEY, G_OPEN_LOCK_TOKEN);
   string close_state = LockActionStateText(close_key, G_CLOSE_LOCK_KEY, G_CLOSE_LOCK_TOKEN);
   return StringFormat(
      "Lock: ON group=%s scope=%s stale=%dms | O=%s C=%s\n",
      LockGroupName(), LockScopeName(), MathMax(1, I_LOCK_STALE_MS), open_state, close_state
   );
}

void RefreshChartComment()
{
   string lines = SyncPortTag() + "\n\n";
   lines += StringFormat(
      "Config: version=%s lot=%s open=%s(%d) close=%s(%d)\n\n",
      SFX_SYNC_EA_VERSION,
      DoubleToString(I_LOT, 2),
      OpenModeToString(I_OPEN_MODE), (int)I_OPEN_MODE,
      CloseModeToString(I_CLOSE_MODE), (int)I_CLOSE_MODE
   );
   if(I_ROLE == ROLE_SOURCE_MASTER)
   {
      lines += "ROLE: MASTER\n";
      lines += StringFormat("Master listen port: %d\n\n", (int)I_PORT);
      if(G_SERVER != NULL && !G_SERVER.Created())
         lines += "Status: FAILED to listen — port in use / permissions.\n";
      else if(G_SERVER == NULL)
         lines += "Status: Starting listener...\n";
      else if(G_PEER == NULL)
         lines += StringFormat("Status: Listening TCP %d — waiting for slave...\n", (int)I_PORT);
      else if(!G_PEER.IsSocketConnected())
         lines += "Status: Slave TCP lost — resetting / will listen again...\n";
      else if(!G_HANDSHAKE_OK)
         lines += "Status: Slave connected (TCP) — waiting HELLO / secret...\n";
      else
      {
         lines += "Status: CONNECTED — slave handshake OK.\n\n";
         if(G_DEGRADED)
            lines += "PAIR: DEGRADED — auto-clears after schedule edge, or press CLEAR DEGRADED button.\n";
         else if(G_PAIR_ACTIVE)
            lines += StringFormat("PAIR: active (master ticket %d)\n", G_PAIR_MASTER_TICKET);
         else if(G_OPEN_TX_ACTIVE)
            lines += "PAIR: OPEN transaction in progress...\n";
         else if(G_CLOSE_TX_ACTIVE)
            lines += "PAIR: CLOSE transaction in progress...\n";
         else
            lines += "PAIR: idle — no active hedge pair.\n";

         lines += "\n";
         if(DiffIsMasterAuto())
            lines += StringFormat("SIDE_AUTO search=%s eff=%s ever_open=%s\n",
                                  (!G_DIFF_AUTO_SIDE_LOCKED ? "yes" : "no"),
                                  (G_DIFF_AUTO_EFF_SIDE == SIDE_BUY ? "BUY" : "SELL"),
                                  (G_DIFF_AUTO_EVER_OPENED ? "yes" : "no"));
         else
            lines += StringFormat("Master open side: %s\n", I_MASTER_SIDE == SIDE_BUY ? "BUY" : "SELL");

         lines += "\n";
         if(I_DND_SCHEDULE_MASTER && G_DND_SCHEDULE_ACTIVE)
            lines += "DND: SCHEDULE (local) — blocks opens and closes (highest priority)\n";
         else if(G_DND_MANUAL_ON)
            lines += "DND: manual — blocks opens and closes (highest priority)\n";
         else
            lines += "DND: off\n";

         if(I_CLOSE_ONLY_SCHEDULE_MASTER && G_CLOSE_ONLY_SCHEDULE_ACTIVE)
            lines += "Close-only: SCHEDULE (local) — blocks new opens\n";
         else if(G_CLOSE_ONLY_MANUAL_ON)
            lines += "Close-only: manual — blocks new opens\n";
         else
            lines += "Close-only: off (new opens allowed)\n";

         string open_guard_code = "";
         string open_guard_detail = "";
         if(MasterOpenGuardReason(open_guard_code, open_guard_detail))
            lines += StringFormat("Open-guard: %s (%s)\n", open_guard_code, open_guard_detail);
         else
            lines += "Open-guard: READY\n";

         lines += "\n";
         lines += LockHudMasterCommentLine();
         lines += DynHudLine();
         lines += DiffHudMasterCommentTail();
         lines += DiffHudSignalOpenProgressBlock();
         lines += DiffHudSignalCloseProgressBlock();
      }
   }
   else
   {
      lines += "ROLE: SLAVE\n";
      lines += StringFormat("Slave connects to Master port: %d\n", (int)I_PORT);
      lines += StringFormat("Master host (I_MASTER_IP): %s\n\n", I_MASTER_IP);
      if(G_SLAVE_DUP_CHANNEL_SHUTDOWN)
      {
         lines += "Status: MASTER REJECT — channel already has a slave.\n";
         lines += "(PAIR_CHANNEL_OCCUPIED) Reload EA or use another port.\n";
      }
      else if(G_PEER == NULL)
         lines += "Status: Creating socket to master...\n";
      else if(!G_PEER.IsSocketConnected())
      {
         lines += "Status: Cannot reach master (TCP).\n";
         lines += "Wait for master listener / check IP, port, firewall.\n";
      }
      else if(!G_HANDSHAKE_OK)
      {
         lines += "Status: TCP up — HELLO sent — waiting HELLO_ACK...\n";
      }
      else
      {
         lines += "Status: CONNECTED — master handshake OK.\n\n";
         if(StringLen(G_SLAVE_PAIR_KEY) > 0 || G_SLAVE_PAIR_TICKET > 0)
            lines += StringFormat("PAIR: slave ticket %d\n", G_SLAVE_PAIR_TICKET);
         else if(StringLen(G_SLAVE_PENDING_OPEN_TXID) > 0 || G_SLAVE_PENDING_OPEN_TICKET > 0)
            lines += "PAIR: awaiting COMMIT after open...\n";
         else
            lines += "PAIR: idle — awaiting master commands.\n";
      }
   }

   if(I_ROLE == ROLE_SOURCE_MASTER)
   {
      RefreshDiffHud();
      CloseOnlyRefreshButton();
      DoNotDisturbRefreshButton();
      ClearDegradedRefreshButton();
   }

   Comment(lines);
}

string SyncLogFileName()
{
   const string role = (I_ROLE == ROLE_SOURCE_MASTER) ? "MASTER" : "SLAVE";
   return StringFormat("%s_%s_Acc%d.log", SFX_SYNC_LOG_FILE_STEM, role, AccountNumber());
}

void SyncClearLogFiles()
{
   if(!I_SYNC_LOG_CLEAR_ON_INIT)
      return;
   const int acct = AccountNumber();
   const string fn_master = StringFormat("%s_MASTER_Acc%d.log", SFX_SYNC_LOG_FILE_STEM, acct);
   const string fn_slave = StringFormat("%s_SLAVE_Acc%d.log", SFX_SYNC_LOG_FILE_STEM, acct);
   if(FileIsExist(fn_master, 0))
      FileDelete(fn_master, 0);
   if(FileIsExist(fn_slave, 0))
      FileDelete(fn_slave, 0);
}

bool SyncAppendFileLine(const string line)
{
   string fn = SyncLogFileName();
   int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   int h = FileOpen(fn, flags);
   if(h == INVALID_HANDLE)
   {
      if(!G_SYNC_LOG_FILE_WARNED)
      {
         G_SYNC_LOG_FILE_WARNED = true;
         ExpertPrintLn(StringFormat("[SFX-SYNC] Log file open failed err=%d file=%s", GetLastError(), fn));
      }
      return false;
   }
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, line);
   FileWrite(h, "\r\n");
   FileFlush(h);
   FileClose(h);
   return true;
}

void SyncLog(const string message_line)
{
   string stamp = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
   SyncAppendFileLine(stamp + "\t" + SyncPortTag() + " " + SyncVersionTag() + " " + NormalizeLogTail(message_line));
}

void SyncLogSessionStart()
{
   string fn = SyncLogFileName();
   const string dir = "Terminal Data\\MQL4\\Files";
   string hdr = StringFormat(
      "[SFX-SYNC] ========== session START role=%s account=%d symbol=%s log=%s (see %s) ==========",
      (I_ROLE == ROLE_SOURCE_MASTER) ? "MASTER" : "SLAVE",
      AccountNumber(),
      G_SYMBOL,
      fn,
      dir
   );
   SyncLog(hdr);
}

void SyncLogSessionStop(const int reason)
{
   SyncLog(StringFormat("[SFX-SYNC] ========== session STOP deinit_reason=%d ==========", reason));
}

string NewTxId()
{
   return StringFormat("%d_%I64u_%d", AccountNumber(), NowMs(), MathRand() % 100000);
}

string LockGroupName()
{
   string group = I_LOCK_GROUP;
   StringTrimLeft(group);
   StringTrimRight(group);
   if(StringLen(group) == 0)
      group = "DEFAULT";
   return group;
}

string BuildActionLockKey(const string action)
{
   string group = LockGroupName();
   if(I_LOCK_SCOPE == LOCK_SCOPE_GROUP_GLOBAL)
      return StringFormat("SFX:LOCK:%s", group);
   if(I_LOCK_SCOPE == LOCK_SCOPE_PAIR_ANY_ACTION)
      return StringFormat("SFX:LOCK:%s:%s", group, G_SYMBOL);
   return StringFormat("SFX:LOCK:%s:%s:%s", group, G_SYMBOL, action);
}

double NewLockToken()
{
   long chart_id = ChartID();
   int chart_tail = (int)(chart_id % 1000);
   if(chart_tail < 0)
      chart_tail = -chart_tail;
   return (double)NowMs() +
          ((double)chart_tail / 1000.0) +
          ((double)((int)I_PORT % 100) / 100000.0) +
          ((double)(MathRand() % 10) / 1000000.0);
}

void LockDebugLog(const string event_name, const string action, const string key, const string note)
{
   if(!I_LOCK_ENABLED || !I_LOCK_DEBUG_LOG)
      return;
   string line = StringFormat("[SFX-SYNC] [LOCK][%s][%s] key=%s %s", action, event_name, key, note);
   ExpertPrintLn(line);
   SyncLog(line);
}

bool TryAcquireActionLock(const string action, const string reason, string &key_out, double &token_out)
{
   key_out = "";
   token_out = 0.0;
   if(!I_LOCK_ENABLED)
      return true;

   key_out = BuildActionLockKey(action);
   token_out = NewLockToken();
   const int stale_ms = MathMax(1, I_LOCK_STALE_MS);
   const ulong now_ms = NowMs();

   if(!GlobalVariableCheck(key_out))
      GlobalVariableSet(key_out, 0.0);

   if(GlobalVariableSetOnCondition(key_out, token_out, 0.0))
   {
      LockDebugLog("ACQUIRE_OK", action, key_out, StringFormat("reason=%s token=%.6f", reason, token_out));
      return true;
   }

   double held = GlobalVariableGet(key_out);
   ulong held_ms = (ulong)MathFloor(MathMax(0.0, held));
   ulong age_ms = (now_ms > held_ms) ? (now_ms - held_ms) : 0;
   if(age_ms >= (ulong)stale_ms && GlobalVariableSetOnCondition(key_out, token_out, held))
   {
      LockDebugLog("STALE_RECOVER", action, key_out, StringFormat("reason=%s age_ms=%I64u old=%.6f new=%.6f", reason, age_ms, held, token_out));
      return true;
   }

   LockDebugLog("ACQUIRE_BUSY", action, key_out, StringFormat("reason=%s held=%.6f age_ms=%I64u", reason, held, age_ms));
   key_out = "";
   token_out = 0.0;
   return false;
}

void ReleaseActionLock(const string action, const string reason, string &key_ref, double &token_ref)
{
   if(!I_LOCK_ENABLED)
   {
      key_ref = "";
      token_ref = 0.0;
      return;
   }
   if(StringLen(key_ref) == 0 || token_ref <= 0.0)
   {
      key_ref = "";
      token_ref = 0.0;
      return;
   }

   bool released = false;
   bool skip_not_owner = false;
   if(GlobalVariableCheck(key_ref))
   {
      double held = GlobalVariableGet(key_ref);
      if(MathAbs(held - token_ref) <= 0.000001)
         released = GlobalVariableSetOnCondition(key_ref, 0.0, held);
      else
         skip_not_owner = true;
   }

   if(released)
      LockDebugLog("RELEASE_OK", action, key_ref, StringFormat("reason=%s", reason));
   else if(skip_not_owner)
      LockDebugLog("RELEASE_SKIP_NOT_OWNER", action, key_ref, StringFormat("reason=%s token=%.6f", reason, token_ref));

   key_ref = "";
   token_ref = 0.0;
}

void ReleaseAllActionLocks(const string reason)
{
   ReleaseActionLock("OPEN", reason, G_OPEN_LOCK_KEY, G_OPEN_LOCK_TOKEN);
   ReleaseActionLock("CLOSE", reason, G_CLOSE_LOCK_KEY, G_CLOSE_LOCK_TOKEN);
}

string SideToString(const ENUM_SIDE side)
{
   if(side == SIDE_AUTO)
      return "AUTO";
   return side == SIDE_BUY ? "BUY" : "SELL";
}

string OpenModeToString(const ENUM_OPEN_MODE mode)
{
   if(mode == OPEN_MASTER_FIRST)
      return "OPEN_MASTER_FIRST";
   return "OPEN_BALANCED";
}

string CloseModeToString(const ENUM_CLOSE_MODE mode)
{
   if(mode == CLOSE_MASTER_FIRST)
      return "CLOSE_MASTER_FIRST";
   if(mode == CLOSE_MASTER_FIRST_WITH_RESCUE)
      return "CLOSE_MASTER_FIRST_WITH_RESCUE";
   return "CLOSE_BALANCED";
}

int SideToOrderType(const ENUM_SIDE side)
{
   return side == SIDE_BUY ? OP_BUY : OP_SELL;
}

ENUM_SIDE OppositeSide(const ENUM_SIDE side)
{
   return (side == SIDE_BUY) ? SIDE_SELL : SIDE_BUY;
}

bool SplitSemicolonFields(const string msg, string &parts[])
{
   ArrayResize(parts, 0);
   if(StringLen(msg) == 0)
      return false;
   return (StringSplit(msg, ';', parts) > 0);
}

void HandleMasterIncomingPacket(const string msg);
void HandleSlaveIncomingPacket(const string msg);
void MarkDegraded(const string reason);
void SlaveCheckPendingOpenTimeout();
void MasterRecoverOrphanLegsIfNeeded();
void MasterHandleDisconnectDuringTransactions();
void ArmPostCloseOpenGuard(const string reason);
bool MasterOpenGuardReason(string &code, string &detail);
bool MasterCloseGuardReason(string &code, string &detail);
int CountEaOpenOrdersOnSlaveSymbol();
void ResetForceFlatState();
void StartForceFlatSlave(const string reason);
void MonitorForceFlatState();
void RefreshDiffHud();

void DispatchMasterRaw(const string raw)
{
   string packs[];
   int n = StringSplit(raw, '~', packs);
   for(int i = 0; i < n; i++)
   {
      if(StringLen(packs[i]) == 0)
         continue;
      HandleMasterIncomingPacket(packs[i]);
   }
}

void DispatchSlaveRaw(const string raw)
{
   string packs[];
   int n = StringSplit(raw, '~', packs);
   for(int i = 0; i < n; i++)
   {
      if(StringLen(packs[i]) == 0)
         continue;
      HandleSlaveIncomingPacket(packs[i]);
   }
}

bool SendMsg(ClientSocket *client, const string msg)
{
   if(client == NULL) return false;
   if(!client.IsSocketConnected()) return false;
   return client.Send(msg + "~");
}

void CloseClient(ClientSocket *&client)
{
   if(client != NULL)
   {
      delete client;
      client = NULL;
   }
}

void MasterDrainExtraSlaves()
{
   if(G_SERVER == NULL || G_PEER == NULL || !G_PEER.IsSocketConnected() || !G_HANDSHAKE_OK)
      return;
   const int max_drain = 16;
   for(int i = 0; i < max_drain; i++)
   {
      ClientSocket *extra = G_SERVER.Accept();
      if(extra == NULL)
         break;
      SendMsg(extra, "CHANNEL_REJECT;PAIR_CHANNEL_OCCUPIED");
      delete extra;
      ExpertPrintLn("[SFX-SYNC] Duplicate slave connection rejected (PAIR_CHANNEL_OCCUPIED)");
      SyncLog("[SFX-SYNC] CHANNEL_REJECT duplicate slave (PAIR_CHANNEL_OCCUPIED)");
   }
}

bool ParseMsg(const string raw, string &parts[])
{
   string packets[];
   ArrayResize(packets, 0);
   StringSplit(raw, '~', packets);
   if(ArraySize(packets) <= 0) return false;
   string msg = packets[0];
   if(StringLen(msg) == 0) return false;
   ArrayResize(parts, 0);
   return StringSplit(msg, ';', parts) > 0;
}

int OpenOrder(const int type, const double lots, int &err_out)
{
   err_out = 0;
   const ulong opened_after_ms = NowMs();
   string sym = G_SYMBOL;
   RefreshRates();
   double price = (type == OP_BUY) ? MarketInfo(sym, MODE_ASK) : MarketInfo(sym, MODE_BID);
   int ticket = OrderSend(sym, type, lots, price, I_SLIPPAGE, 0, 0, "", OrderMagic(), 0, clrNONE);
   if(ticket < 0)
   {
      err_out = GetLastError();
      const ENUM_SIDE side = (type == OP_BUY) ? SIDE_BUY : SIDE_SELL;
      int recovered_ticket = -1;
      if(IsMt4OpenTransientError(err_out))
      {
         const ulong wait_ms = (ulong)MathMax(200, I_SLAVE_OPEN_TIMEOUT_MS);
         const ulong until_ms = NowMs() + wait_ms;
         // Broker can timeout/requote while order is already accepted upstream.
         while(NowMs() <= until_ms)
         {
            if(RecoverMasterOpenTicketMt4(side, opened_after_ms, recovered_ticket))
               return recovered_ticket;
            Sleep(40);
         }
      }
      else
      {
         // One-shot safety net for non-transient errors in case the order was actually accepted.
         if(RecoverMasterOpenTicketMt4(side, opened_after_ms, recovered_ticket))
            return recovered_ticket;
      }
   }
   return ticket;
}

bool IsMt4CloseTransientError(const int err)
{
   switch(err)
   {
      case 128: // ERR_TRADE_TIMEOUT
      case 129: // ERR_INVALID_PRICE
      case 135: // ERR_PRICE_CHANGED
      case 136: // ERR_OFF_QUOTES
      case 137: // ERR_BROKER_BUSY
      case 138: // ERR_REQUOTE
      case 146: // ERR_TRADE_CONTEXT_BUSY
         return true;
      default:
         return false;
   }
}

bool IsMt4OpenTransientError(const int err)
{
   switch(err)
   {
      case 128: // ERR_TRADE_TIMEOUT
      case 129: // ERR_INVALID_PRICE
      case 135: // ERR_PRICE_CHANGED
      case 136: // ERR_OFF_QUOTES
      case 137: // ERR_BROKER_BUSY
      case 138: // ERR_REQUOTE
      case 146: // ERR_TRADE_CONTEXT_BUSY
         return true;
      default:
         return false;
   }
}

bool RecoverMasterOpenTicketMt4(const ENUM_SIDE side, const ulong opened_after_ms, int &ticket_out)
{
   ticket_out = -1;
   const int want_type = (side == SIDE_BUY) ? OP_BUY : OP_SELL;
   const long min_open_sec = (long)(opened_after_ms / 1000);
   int best_ticket = -1;
   datetime best_time = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != G_SYMBOL)
         continue;
      if(OrderMagicNumber() != OrderMagic())
         continue;
      if(OrderType() != want_type)
         continue;
      const long open_sec = (long)OrderOpenTime();
      if(open_sec + 1 < min_open_sec)
         continue;
      if(OrderOpenTime() >= best_time)
      {
         best_time = OrderOpenTime();
         best_ticket = OrderTicket();
      }
   }
   if(best_ticket <= 0)
      return false;
   ticket_out = best_ticket;
   return true;
}

bool CloseTicketIfOpenWithPolicy(const int ticket, const bool retry_transient)
{
   if(ticket <= 0) return false;
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return true;
   if(OrderCloseTime() != 0)
      return true;
   if(OrderMagicNumber() != OrderMagic()) return true;
   if(OrderSymbol() != G_SYMBOL) return true;
   int type = OrderType();
   double lots = OrderLots();
   const int max_att = retry_transient ? MathMax(1, I_ORDER_CLOSE_RETRY_COUNT) : 1;
   const int max_block_ms = MathMax(0, I_ORDER_CLOSE_MAX_BLOCK_MS);
   const ulong started_ms = NowMs();
   for(int k = 0; k < max_att; k++)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return true;
      if(OrderCloseTime() != 0)
         return true;
      RefreshRates();
      double price = (type == OP_BUY) ? MarketInfo(G_SYMBOL, MODE_BID) : MarketInfo(G_SYMBOL, MODE_ASK);
      ResetLastError();
      if(OrderClose(ticket, lots, price, I_SLIPPAGE, clrNONE))
         return true;
      const int err = GetLastError();
      if(!IsMt4CloseTransientError(err))
         return false;
      if(k + 1 < max_att && I_ORDER_CLOSE_RETRY_INTERVAL_MS > 0)
      {
         if(max_block_ms > 0)
         {
            const ulong elapsed_ms = (NowMs() >= started_ms) ? (NowMs() - started_ms) : 0;
            if((int)elapsed_ms >= max_block_ms)
               break;
            const int remain_ms = max_block_ms - (int)elapsed_ms;
            const int nap_ms = MathMin(I_ORDER_CLOSE_RETRY_INTERVAL_MS, remain_ms);
            if(nap_ms <= 0)
               break;
            Sleep(nap_ms);
         }
         else
         {
            Sleep(I_ORDER_CLOSE_RETRY_INTERVAL_MS);
         }
      }
   }
   return false;
}

bool CloseTicketIfOpen(const int ticket)
{
   return CloseTicketIfOpenWithPolicy(ticket, true);
}

bool MasterPairLegTicketLive(const int ticket)
{
   if(ticket <= 0) return false;
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return false;
   if(OrderCloseTime() != 0) return false;
   if(OrderMagicNumber() != OrderMagic()) return false;
   if(OrderSymbol() != G_SYMBOL) return false;
   const int typ = OrderType();
   return (typ == OP_BUY || typ == OP_SELL);
}

bool IsTicketOpen(const int ticket)
{
   if(ticket <= 0) return false;
   const int n = OrdersTotal();
   for(int i = n - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if((int)OrderTicket() != ticket)
         continue;
      if(OrderCloseTime() != 0)
         return false;
      if(OrderMagicNumber() != OrderMagic())
         return false;
      if(OrderSymbol() != G_SYMBOL)
         return false;
      int type = OrderType();
      return (type == OP_BUY || type == OP_SELL);
   }
   return false;
}

int CloseOnlyParseHmToMinutes(const string s)
{
   int n = (int)StringLen(s);
   int i = 0;
   for(; i < n; i++)
   {
      if(StringGetCharacter(s, i) != ' ')
         break;
   }
   string t = StringSubstr(s, i);
   int c = StringFind(t, ":", 0);
   if(c <= 0)
      return -1;
   int h = (int)StringToInteger(StringSubstr(t, 0, c));
   int mi = (int)StringToInteger(StringSubstr(t, c + 1));
   if(h < 0 || h > 23 || mi < 0 || mi > 59)
      return -1;
   return h * 60 + mi;
}

void CloseOnlyGetDayParams(const int dow, bool &en, int &sm, int &em)
{
   en = false;
   sm = -1;
   em = -1;
   switch(dow)
   {
      case 0:
         break;
      case 1:
         en = I_CLOSE_ONLY_MON_EN;
         sm = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_MON_START);
         em = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_MON_END);
         break;
      case 2:
         en = I_CLOSE_ONLY_TUE_EN;
         sm = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_TUE_START);
         em = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_TUE_END);
         break;
      case 3:
         en = I_CLOSE_ONLY_WED_EN;
         sm = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_WED_START);
         em = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_WED_END);
         break;
      case 4:
         en = I_CLOSE_ONLY_THU_EN;
         sm = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_THU_START);
         em = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_THU_END);
         break;
      case 5:
         en = I_CLOSE_ONLY_FRI_EN;
         sm = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_FRI_START);
         em = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_FRI_END);
         break;
      case 6:
         break;
      default:
         break;
   }
}

int CloseOnlyPrevDow(const int dow)
{
   if(dow == 0)
      return 6;
   return dow - 1;
}

bool CloseOnlyInSameDayWindow(const int now_m, const int s, const int e, const bool en)
{
   if(!en || s < 0 || e < 0)
      return false;
   if(s < e)
      return (now_m >= s && now_m < e);
   return false;
}

bool CloseOnlyInOvernightEvening(const int now_m, const int s, const int e, const bool en)
{
   if(!en || s < 0 || e < 0)
      return false;
   if(s <= e)
      return false;
   return (now_m >= s);
}

bool CloseOnlyInOvernightMorning(const int now_m, const int s, const int e, const bool en)
{
   if(!en || s < 0 || e < 0)
      return false;
   if(s <= e)
      return false;
   return (now_m < e);
}

bool CloseOnlyInWeekendWindow(const int dow, const int now_m)
{
   if(!I_CLOSE_ONLY_WEEKEND_ENABLED)
      return false;
   const int start_m = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_WEEKEND_START_SAT);
   const int end_m = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_WEEKEND_END_MON);
   if(start_m < 0 || end_m < 0)
      return false;

   if(dow == 6)
      return (now_m >= start_m);
   if(dow == 0)
      return true;
   if(dow == 1)
      return (now_m < end_m);
   return false;
}

void CloseOnlyUpdateSchedule()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
   {
      G_CLOSE_ONLY_SCHEDULE_ACTIVE = false;
      return;
   }
   if(!I_CLOSE_ONLY_SCHEDULE_MASTER)
   {
      G_CLOSE_ONLY_SCHEDULE_ACTIVE = false;
      return;
   }

   datetime tl = TimeLocal();
   int dow = TimeDayOfWeek(tl);
   if(dow < 0)
      dow = 0;
   if(dow > 6)
      dow %= 7;
   int now_m = TimeHour(tl) * 60 + TimeMinute(tl);

   bool en_t = false;
   int st = -1, et = -1;
   CloseOnlyGetDayParams(dow, en_t, st, et);

   bool en_y = false;
   int sy = -1, ey = -1;
   CloseOnlyGetDayParams(CloseOnlyPrevDow(dow), en_y, sy, ey);

   bool active = false;
   if(CloseOnlyInSameDayWindow(now_m, st, et, en_t))
      active = true;
   if(CloseOnlyInOvernightEvening(now_m, st, et, en_t))
      active = true;
   if(CloseOnlyInOvernightMorning(now_m, sy, ey, en_y))
      active = true;
   if(CloseOnlyInWeekendWindow(dow, now_m))
      active = true;

   G_CLOSE_ONLY_SCHEDULE_ACTIVE = active;

   if(!G_CLOSE_ONLY_SCHEDULE_INIT)
   {
      G_CLOSE_ONLY_SCHEDULE_INIT = true;
      G_CLOSE_ONLY_SCHEDULE_ACTIVE_PREV = G_CLOSE_ONLY_SCHEDULE_ACTIVE;
   }
   else if(G_CLOSE_ONLY_SCHEDULE_ACTIVE != G_CLOSE_ONLY_SCHEDULE_ACTIVE_PREV)
   {
      G_CLOSE_ONLY_SCHEDULE_ACTIVE_PREV = G_CLOSE_ONLY_SCHEDULE_ACTIVE;
      SyncLog(StringFormat("[SFX-SYNC] close_only schedule (local) -> %s", G_CLOSE_ONLY_SCHEDULE_ACTIVE ? "ACTIVE" : "inactive"));
      // Auto-clear DEGRADED on schedule end edge. Safe guards inside TryClearDegraded prevent
      // accidental reset while transactions or live legs remain.
      if(!G_CLOSE_ONLY_SCHEDULE_ACTIVE && G_DEGRADED)
         TryClearDegraded("CLOSE_ONLY_SCHEDULE_ENDED");
   }
}

bool CloseOnlyMasterBlocksPairOpen()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return false;
   if(G_CLOSE_ONLY_SCHEDULE_ACTIVE)
      return true;
   if(G_CLOSE_ONLY_MANUAL_ON)
      return true;
   return false;
}

void DoNotDisturbGetDayParams(const int dow, bool &en, int &sm, int &em)
{
   en = false;
   sm = -1;
   em = -1;
   switch(dow)
   {
      case 0:
         break;
      case 1:
         en = I_DND_MON_EN;
         sm = CloseOnlyParseHmToMinutes(I_DND_MON_START);
         em = CloseOnlyParseHmToMinutes(I_DND_MON_END);
         break;
      case 2:
         en = I_DND_TUE_EN;
         sm = CloseOnlyParseHmToMinutes(I_DND_TUE_START);
         em = CloseOnlyParseHmToMinutes(I_DND_TUE_END);
         break;
      case 3:
         en = I_DND_WED_EN;
         sm = CloseOnlyParseHmToMinutes(I_DND_WED_START);
         em = CloseOnlyParseHmToMinutes(I_DND_WED_END);
         break;
      case 4:
         en = I_DND_THU_EN;
         sm = CloseOnlyParseHmToMinutes(I_DND_THU_START);
         em = CloseOnlyParseHmToMinutes(I_DND_THU_END);
         break;
      case 5:
         en = I_DND_FRI_EN;
         sm = CloseOnlyParseHmToMinutes(I_DND_FRI_START);
         em = CloseOnlyParseHmToMinutes(I_DND_FRI_END);
         break;
      case 6:
         break;
      default:
         break;
   }
}

bool DoNotDisturbInWeekendWindow(const int dow, const int now_m)
{
   if(!I_DND_WEEKEND_ENABLED)
      return false;
   const int start_m = CloseOnlyParseHmToMinutes(I_DND_WEEKEND_START_SAT);
   const int end_m = CloseOnlyParseHmToMinutes(I_DND_WEEKEND_END_MON);
   if(start_m < 0 || end_m < 0)
      return false;

   if(dow == 6)
      return (now_m >= start_m);
   if(dow == 0)
      return true;
   if(dow == 1)
      return (now_m < end_m);
   return false;
}

void DoNotDisturbUpdateSchedule()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
   {
      G_DND_SCHEDULE_ACTIVE = false;
      return;
   }
   if(!I_DND_SCHEDULE_MASTER)
   {
      G_DND_SCHEDULE_ACTIVE = false;
      return;
   }

   datetime tl = TimeLocal();
   int dow = TimeDayOfWeek(tl);
   if(dow < 0)
      dow = 0;
   if(dow > 6)
      dow %= 7;
   int now_m = TimeHour(tl) * 60 + TimeMinute(tl);

   bool en_t = false;
   int st = -1, et = -1;
   DoNotDisturbGetDayParams(dow, en_t, st, et);

   bool en_y = false;
   int sy = -1, ey = -1;
   DoNotDisturbGetDayParams(CloseOnlyPrevDow(dow), en_y, sy, ey);

   bool active = false;
   if(CloseOnlyInSameDayWindow(now_m, st, et, en_t))
      active = true;
   if(CloseOnlyInOvernightEvening(now_m, st, et, en_t))
      active = true;
   if(CloseOnlyInOvernightMorning(now_m, sy, ey, en_y))
      active = true;
   if(DoNotDisturbInWeekendWindow(dow, now_m))
      active = true;

   G_DND_SCHEDULE_ACTIVE = active;

   if(!G_DND_SCHEDULE_INIT)
   {
      G_DND_SCHEDULE_INIT = true;
      G_DND_SCHEDULE_ACTIVE_PREV = G_DND_SCHEDULE_ACTIVE;
   }
   else if(G_DND_SCHEDULE_ACTIVE != G_DND_SCHEDULE_ACTIVE_PREV)
   {
      G_DND_SCHEDULE_ACTIVE_PREV = G_DND_SCHEDULE_ACTIVE;
      SyncLog(StringFormat("[SFX-SYNC] dnd schedule (local) -> %s", G_DND_SCHEDULE_ACTIVE ? "ACTIVE" : "inactive"));
   }
}

bool DoNotDisturbMasterBlocksTrading()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return false;
   if(G_DND_SCHEDULE_ACTIVE)
      return true;
   if(G_DND_MANUAL_ON)
      return true;
   return false;
}

void ArmPostCloseOpenGuard(const string reason)
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   G_LAST_PAIR_CLOSE_MS = NowMs();
   SyncLog(StringFormat("[SFX-SYNC] OPEN_GUARD armed after close reason=%s hold_ms=%d",
                        reason, MathMax(0, I_REOPEN_GUARD_AFTER_CLOSE_MS)));
}

bool MasterOpenGuardReason(string &code, string &detail)
{
   code = "READY";
   detail = "open permitted";
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return false;

   if(G_DND_SCHEDULE_ACTIVE)
   {
      code = "DND_SCHEDULE_ACTIVE";
      detail = "scheduled DND blocks opens and closes";
      return true;
   }
   if(G_DND_MANUAL_ON)
   {
      code = "DND_MANUAL_ACTIVE";
      detail = "manual DND blocks opens and closes";
      return true;
   }
   if(G_CLOSE_ONLY_SCHEDULE_ACTIVE)
   {
      code = "CLOSE_ONLY_SCHEDULE_ACTIVE";
      detail = "scheduled close-only blocks new opens";
      return true;
   }
   if(G_CLOSE_ONLY_MANUAL_ON)
   {
      code = "CLOSE_ONLY_MANUAL_ACTIVE";
      detail = "manual close-only blocks new opens";
      return true;
   }
   if(G_DEGRADED && I_BLOCK_NEW_OPEN_WHEN_DEGRADED)
   {
      code = "DEGRADED_LOCK";
      detail = "new opens are blocked while degraded";
      return true;
   }
   if(I_REOPEN_GUARD_AFTER_CLOSE_MS > 0 && G_LAST_PAIR_CLOSE_MS > 0)
   {
      const ulong elapsed_ms = (NowMs() > G_LAST_PAIR_CLOSE_MS) ? (NowMs() - G_LAST_PAIR_CLOSE_MS) : 0;
      const ulong hold_ms = (ulong)MathMax(0, I_REOPEN_GUARD_AFTER_CLOSE_MS);
      if(elapsed_ms < hold_ms)
      {
         code = "POST_CLOSE_GUARD";
         detail = StringFormat("wait %I64ums before reopening", hold_ms - elapsed_ms);
         return true;
      }
   }
   return false;
}

bool MasterCloseGuardReason(string &code, string &detail)
{
   code = "READY";
   detail = "close permitted";
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return false;

   if(G_DND_SCHEDULE_ACTIVE)
   {
      code = "DND_SCHEDULE_ACTIVE";
      detail = "scheduled DND blocks opens and closes";
      return true;
   }
   if(G_DND_MANUAL_ON)
   {
      code = "DND_MANUAL_ACTIVE";
      detail = "manual DND blocks opens and closes";
      return true;
   }
   return false;
}

void DoNotDisturbRefreshButton()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(ObjectFind(0, "SFX_DND_MODE") < 0)
      return;
   const bool sch = (I_DND_SCHEDULE_MASTER && G_DND_SCHEDULE_ACTIVE);
   string tip = "Toggle manual do-not-disturb on master (blocks new open and close actions).";
   color bg = clrWhite;
   string txt = "DND MODE";
   if(sch)
   {
      bg = C'255,45,45';
      tip = "Scheduled do-not-disturb (local time). Manual cannot cancel until schedule window ends.";
   }
   else if(G_DND_MANUAL_ON)
   {
      bg = C'255,45,45';
   }
   color fg = clrBlack;
   if(sch || G_DND_MANUAL_ON)
      fg = clrWhite;
   ObjectSetString(0, "SFX_DND_MODE", OBJPROP_TEXT, txt);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_COLOR, fg);
   ObjectSetString(0, "SFX_DND_MODE", OBJPROP_TOOLTIP, tip);
}

void CloseOnlyRefreshButton()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(ObjectFind(0, "SFX_CLOSE_ONLY") < 0)
      return;
   const bool sch = (I_CLOSE_ONLY_SCHEDULE_MASTER && G_CLOSE_ONLY_SCHEDULE_ACTIVE);
   string tip = "Toggle manual close-only on master (blocks new synced opens; closes still allowed). Rescue hedge not blocked.";
   color bg = clrWhite;
   string txt = "CLOSE ONLY MODE";
   if(sch)
   {
      bg = C'255,45,45';
      tip = "Scheduled close-only (local time). Manual cannot cancel until schedule window ends.";
   }
   else if(G_CLOSE_ONLY_MANUAL_ON)
   {
      bg = C'255,45,45';
   }
   color fg = clrBlack;
   if(sch || G_CLOSE_ONLY_MANUAL_ON)
      fg = clrWhite;
   ObjectSetString(0, "SFX_CLOSE_ONLY", OBJPROP_TEXT, txt);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_COLOR, fg);
   ObjectSetString(0, "SFX_CLOSE_ONLY", OBJPROP_TOOLTIP, tip);
}

void ClearDegradedRefreshButton()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(ObjectFind(0, "SFX_CLEAR_DEGRADED") < 0)
      return;
   color bg, fg, border;
   string txt, tip;
   if(G_DEGRADED)
   {
      bg = C'255,140,40';
      fg = clrWhite;
      border = C'200,110,30';
      txt = "CLEAR DEGRADED";
      tip = "Manually clear DEGRADED lock. Allowed only when no transaction and no live EA leg remain.";
   }
   else
   {
      bg = C'225,225,225';
      fg = C'130,130,130';
      border = C'200,200,200';
      txt = "DEGRADED: OK";
      tip = "No degraded state. Button is informational only.";
   }
   ObjectSetString(0, "SFX_CLEAR_DEGRADED", OBJPROP_TEXT, txt);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_COLOR, fg);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_BORDER_COLOR, border);
   ObjectSetString(0, "SFX_CLEAR_DEGRADED", OBJPROP_TOOLTIP, tip);
}

#include <SumoFx/FXH-SYNC-HEADER-MQL4.mqh>

void ResetOpenTxState()
{
   ReleaseActionLock("OPEN", "RESET_OPEN_TX", G_OPEN_LOCK_KEY, G_OPEN_LOCK_TOKEN);
   G_OPEN_TX_ACTIVE = false;
   G_OPEN_TX_ID = "";
   G_OPEN_OVERALL_DEADLINE_MS = 0;
   G_OPEN_SLAVE_WAIT_DEADLINE_MS = 0;
   G_OPEN_RETRY_LEFT = 0;
   G_OPEN_MASTER_OK = false;
   G_OPEN_MASTER_TICKET = -1;
   G_OPEN_SLAVE_OK = false;
   G_OPEN_SLAVE_TICKET = -1;
   G_OPEN_LAST_ERROR_MASTER = 0;
   G_OPEN_LAST_ERROR_SLAVE = 0;
   G_OPEN_SIDE = "";
   G_OPEN_LOT_SLAVE = 0.0;
   G_OPEN_DISCONNECT_DEADLINE_MS = 0;
}

void ResetCloseTxState()
{
   ReleaseActionLock("CLOSE", "RESET_CLOSE_TX", G_CLOSE_LOCK_KEY, G_CLOSE_LOCK_TOKEN);
   G_CLOSE_TX_ACTIVE = false;
   G_CLOSE_TX_ID = "";
   G_CLOSE_REASON = "";
   G_CLOSE_OVERALL_DEADLINE_MS = 0;
   G_CLOSE_SLAVE_WAIT_DEADLINE_MS = 0;
   G_CLOSE_RETRY_LEFT = 0;
   G_CLOSE_MASTER_OK = false;
   G_CLOSE_SLAVE_OK = false;
   G_CLOSE_LAST_ERROR_MASTER = 0;
   G_CLOSE_LAST_ERROR_SLAVE = 0;
   G_CLOSE_SLAVE_BALANCE = 0.0;
}

void CloseOnlyCloseAllMasterOrders()
{
   const int magic = OrderMagic();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderCloseTime() != 0)
         continue;
      if(OrderMagicNumber() != magic)
         continue;
      if(OrderSymbol() != G_SYMBOL)
         continue;
      const int typ = OrderType();
      if(typ != OP_BUY && typ != OP_SELL)
         continue;
      CloseTicketIfOpen((int)OrderTicket());
   }
}

void CloseOnlyWeekendResetPair()
{
   if(G_OPEN_TX_ACTIVE)
      ResetOpenTxState();
   if(G_CLOSE_TX_ACTIVE)
      ResetCloseTxState();
   G_PAIR_ACTIVE = false;
   G_PAIR_KEY = "";
   G_PAIR_MASTER_TICKET = -1;
   G_PAIR_SLAVE_TICKET = -1;
   G_SLAVE_PAIR_OPEN_REPORT = false;
   G_LAST_SLAVE_PAIR_STATUS_MS = 0;
   G_PAIR_OPENED_MS = 0;
   G_PAIR_OPEN_INTENT_MS = 0;
   G_PENDING_OPEN_INTENT_TAG = "UI_BUTTON";
   G_DEGRADED = false;
   G_RESCUE_ATTEMPTS_USED = 0;
   if(DiffIsMasterAuto())
      DiffAutoUnlockSearching();
}

void CloseOnlyTryWeekendCloseAll()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(!I_CLOSE_ONLY_WEEKEND_ENABLED)
      return;
   if(!I_CLOSE_ONLY_WEEKEND_START_CLOSE_ALL)
      return;
   if(G_PEER == NULL || !G_PEER.IsSocketConnected() || !G_HANDSHAKE_OK)
      return;

   const datetime tl = TimeLocal();
   if(TimeDayOfWeek(tl) != 6)
      return;

   const int start_m = CloseOnlyParseHmToMinutes(I_CLOSE_ONLY_WEEKEND_START_SAT);
   if(start_m < 0)
      return;
   const int now_m = TimeHour(tl) * 60 + TimeMinute(tl);
   if(now_m < start_m)
      return;

   const int sat_key = TimeYear(tl) * 10000 + TimeMonth(tl) * 100 + TimeDay(tl);
   if(G_WEEKEND_FLAT_LAST_KEY == sat_key)
      return;

   CloseOnlyCloseAllMasterOrders();
   CloseOnlyWeekendResetPair();
   SendMsg(G_PEER, "WEEKEND_FLATTEN");
   G_WEEKEND_FLAT_LAST_KEY = sat_key;
   SyncLog("[SFX-SYNC] WEEKEND_FLATTEN executed (master flat all EA orders + notified slave)");
}

void SlaveCloseAllOrders()
{
   const int magic = OrderMagic();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderCloseTime() != 0)
         continue;
      if(OrderMagicNumber() != magic)
         continue;
      if(OrderSymbol() != G_SYMBOL)
         continue;
      const int typ = OrderType();
      if(typ != OP_BUY && typ != OP_SELL)
         continue;
      CloseTicketIfOpen((int)OrderTicket());
   }
}

int CountEaOpenOrdersOnSlaveSymbol()
{
   const int magic = OrderMagic();
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderCloseTime() != 0)
         continue;
      if(OrderMagicNumber() != magic)
         continue;
      if(OrderSymbol() != G_SYMBOL)
         continue;
      const int typ = OrderType();
      if(typ != OP_BUY && typ != OP_SELL)
         continue;
      count++;
   }
   return count;
}

void SlaveWeekendReset()
{
   G_SLAVE_PAIR_KEY = "";
   G_SLAVE_PAIR_TICKET = -1;
   G_SLAVE_PENDING_OPEN_TXID = "";
   G_SLAVE_PENDING_OPEN_TICKET = -1;
   G_SLAVE_PENDING_OPEN_DEADLINE_MS = 0;
   G_SLAVE_LAST_OPEN_TXID = "";
   G_SLAVE_LAST_OPEN_OK = -1;
   G_SLAVE_LAST_OPEN_TICKET = -1;
   G_SLAVE_LAST_OPEN_ERR = 0;
   G_SLAVE_LAST_OPEN_STARTED_MS = 0;
}

void SlaveCheckPendingOpenTimeout()
{
   if(StringLen(G_SLAVE_PENDING_OPEN_TXID) == 0 || G_SLAVE_PENDING_OPEN_TICKET <= 0)
   {
      G_SLAVE_PENDING_OPEN_DEADLINE_MS = 0;
      return;
   }
   if(G_SLAVE_PENDING_OPEN_DEADLINE_MS == 0)
      G_SLAVE_PENDING_OPEN_DEADLINE_MS = NowMs() + (ulong)MathMax(300, I_SLAVE_PENDING_COMMIT_TIMEOUT_MS);
   if(NowMs() <= G_SLAVE_PENDING_OPEN_DEADLINE_MS)
      return;

   const string txid = G_SLAVE_PENDING_OPEN_TXID;
   const int ticket = G_SLAVE_PENDING_OPEN_TICKET;
   const bool closed = CloseTicketIfOpenWithPolicy(ticket, false);
   const string timeout_ln = StringFormat(
      "[SFX-SYNC] SLAVE pending open timeout tx_id=%s ticket=%d closed=%s",
      txid, ticket, closed ? "true" : "false"
   );
   SyncLog(timeout_ln);
   ExpertPrintLn(timeout_ln);
   G_SLAVE_PENDING_OPEN_TXID = "";
   G_SLAVE_PENDING_OPEN_TICKET = -1;
   G_SLAVE_PENDING_OPEN_DEADLINE_MS = 0;
}

void MasterRecoverOrphanLegsIfNeeded()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(G_PAIR_ACTIVE || G_OPEN_TX_ACTIVE || G_CLOSE_TX_ACTIVE)
      return;
   if(PairWithinSettleGrace())
      return;
   if(I_ORPHAN_RECOVERY_COOLDOWN_MS > 0 && G_LAST_ORPHAN_RECOVERY_MS > 0)
   {
      if((NowMs() - G_LAST_ORPHAN_RECOVERY_MS) < (ulong)I_ORPHAN_RECOVERY_COOLDOWN_MS)
         return;
   }

   int orphan_tickets[];
   ArrayResize(orphan_tickets, 0);
   const int n = OrdersTotal();
   for(int i = n - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderCloseTime() != 0)
         continue;
      if(OrderMagicNumber() != OrderMagic())
         continue;
      if(OrderSymbol() != G_SYMBOL)
         continue;
      const int typ = OrderType();
      if(typ != OP_BUY && typ != OP_SELL)
         continue;
      const int idx = ArraySize(orphan_tickets);
      ArrayResize(orphan_tickets, idx + 1);
      orphan_tickets[idx] = (int)OrderTicket();
   }
   if(ArraySize(orphan_tickets) <= 0)
   {
      G_ORPHAN_DETECT_STREAK = 0;
      return;
   }

   const int need_cycles = MathMax(1, I_ORPHAN_CONFIRM_CYCLES);
   G_ORPHAN_DETECT_STREAK++;
   if(G_ORPHAN_DETECT_STREAK < need_cycles)
   {
      SyncLog(StringFormat("[SFX-SYNC] ORPHAN detected; waiting confirm cycle %d/%d", G_ORPHAN_DETECT_STREAK, need_cycles));
      return;
   }

   G_LAST_ORPHAN_RECOVERY_MS = NowMs();
   SyncLog(StringFormat("[SFX-SYNC] ORPHAN master leg detected count=%d", ArraySize(orphan_tickets)));
   bool all_closed = true;
   bool any_closed = false;
   for(int j = 0; j < ArraySize(orphan_tickets); j++)
   {
      const int tk = orphan_tickets[j];
      if(!CloseTicketIfOpenWithPolicy(tk, false))
      {
         all_closed = false;
         SyncLog(StringFormat("[SFX-SYNC] ORPHAN close failed ticket=%d", tk));
      }
      else
      {
         any_closed = true;
      }
   }
   if(all_closed)
      SyncLog("[SFX-SYNC] ORPHAN recovery: all master orphan legs closed");
   else
      MarkDegraded("ORPHAN_MASTER_CLOSE_FAIL");
   if(any_closed)
      ArmPostCloseOpenGuard("ORPHAN_RECOVERY");
   G_ORPHAN_DETECT_STREAK = 0;
}

void MasterHandleDisconnectDuringTransactions()
{
   if(G_CLOSE_TX_ACTIVE)
   {
      SyncLog(StringFormat("[SFX-SYNC] CLOSE reset due to disconnect tx_id=%s", G_CLOSE_TX_ID));
      ResetCloseTxState();
   }
   ResetForceFlatState();
}

void ResetForceFlatState()
{
   G_FORCE_FLAT_ACTIVE = false;
   G_FORCE_FLAT_TX_ID = "";
   G_FORCE_FLAT_REASON = "";
   G_FORCE_FLAT_WAIT_DEADLINE_MS = 0;
   G_FORCE_FLAT_RETRY_LEFT = 0;
   G_FORCE_FLAT_RETRY_READY_MS = 0;
}

void StartForceFlatSlave(const string reason)
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(G_FORCE_FLAT_ACTIVE || G_OPEN_TX_ACTIVE || G_CLOSE_TX_ACTIVE)
      return;
   if(G_PEER == NULL || !G_PEER.IsSocketConnected() || !G_HANDSHAKE_OK)
      return;
   G_FORCE_FLAT_ACTIVE = true;
   G_FORCE_FLAT_TX_ID = NewTxId();
   G_FORCE_FLAT_REASON = reason;
   G_FORCE_FLAT_RETRY_LEFT = MathMax(0, I_FORCE_FLAT_RETRY_COUNT);
   G_FORCE_FLAT_RETRY_READY_MS = 0;
   G_FORCE_FLAT_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(300, I_FORCE_FLAT_TIMEOUT_MS);
   SendMsg(G_PEER, StringFormat("FORCE_FLAT;%s;%s", G_FORCE_FLAT_TX_ID, reason));
   SyncLog(StringFormat("[SFX-SYNC] FORCE_FLAT sent tx_id=%s reason=%s retries=%d",
                        G_FORCE_FLAT_TX_ID, reason, G_FORCE_FLAT_RETRY_LEFT));
}

void MonitorForceFlatState()
{
   if(!G_FORCE_FLAT_ACTIVE)
      return;
   if(NowMs() <= G_FORCE_FLAT_WAIT_DEADLINE_MS)
      return;

   if(G_FORCE_FLAT_RETRY_LEFT > 0)
   {
      if(G_FORCE_FLAT_RETRY_READY_MS == 0)
      {
         G_FORCE_FLAT_RETRY_READY_MS = NowMs() + (ulong)MathMax(100, I_FORCE_FLAT_RETRY_INTERVAL_MS);
         return;
      }
      if(NowMs() < G_FORCE_FLAT_RETRY_READY_MS)
         return;

      SendMsg(G_PEER, StringFormat("FORCE_FLAT;%s;%s", G_FORCE_FLAT_TX_ID, G_FORCE_FLAT_REASON));
      G_FORCE_FLAT_RETRY_LEFT--;
      G_FORCE_FLAT_RETRY_READY_MS = 0;
      G_FORCE_FLAT_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(300, I_FORCE_FLAT_TIMEOUT_MS);
      SyncLog(StringFormat("[SFX-SYNC] FORCE_FLAT retry tx_id=%s retries_left=%d",
                           G_FORCE_FLAT_TX_ID, G_FORCE_FLAT_RETRY_LEFT));
      return;
   }

   SyncLog(StringFormat("[SFX-SYNC] FORCE_FLAT timeout tx_id=%s reason=%s",
                        G_FORCE_FLAT_TX_ID, G_FORCE_FLAT_REASON));
   MarkDegraded("FORCE_FLAT_TIMEOUT");
   ResetForceFlatState();
}

string BuildOpenIntent()
{
   const double lot_now = DynActiveLot();
   return StringFormat(
      "OPEN_INTENT;%s;%s;%s;%.2f;%.2f;%d;%d",
      G_OPEN_TX_ID,
      G_SYMBOL,
      G_OPEN_SIDE,
      lot_now,
      lot_now,
      I_SLIPPAGE,
      I_OPEN_ROLLBACK_TIMEOUT_MS
   );
}

string BuildCloseIntent()
{
   return StringFormat("CLOSE_INTENT;%s;%s;%s", G_CLOSE_TX_ID, G_CLOSE_REASON, G_PAIR_KEY);
}

string DiffOpenParenLabel()
{
   return StringFormat("DIFF_OPEN(%.2f)", G_DIFF_SIGNAL_SNAP_OPEN_PTS);
}

string DiffCloseParenLabel()
{
   return StringFormat("DIFF_CLOSE(%.2f)", G_DIFF_SIGNAL_SNAP_CLOSE_PTS);
}

void PrintLogMasterOpenIntent(string tag)
{
   string intent_label = tag;
   if(tag == "DIFF_OPEN")
      intent_label = DiffOpenParenLabel();
   const double lot_now = DynActiveLot();
   string line = StringFormat(
      "[SFX-SYNC] OPEN_INTENT_OUT %s tx_id=%s symbol=%s side_master=%s lot_m=%.2f lot_s=%.2f open_mode=%d",
      intent_label, G_OPEN_TX_ID, G_SYMBOL, G_OPEN_SIDE, lot_now, lot_now, (int)I_OPEN_MODE
   );
   ExpertPrintLn(line);
   SyncLog(line);
}

void PrintLogMasterCloseBegin(string reason)
{
   string reason_out = reason;
   if(reason == "DIFF_CLOSE")
      reason_out = DiffCloseParenLabel();
   ExpertPrintLn(StringFormat(
      "CLOSE_BEGIN tx_id=%s reason=%s pair_key=%s mticket=%d close_mode=%d",
      G_CLOSE_TX_ID, reason_out, G_PAIR_KEY, G_PAIR_MASTER_TICKET, (int)I_CLOSE_MODE));
   SyncLog(StringFormat("[SFX-SYNC] CLOSE started tx_id=%s mode=%d reason=%s",
                           G_CLOSE_TX_ID, (int)I_CLOSE_MODE, reason_out));
}

void PrintLogMasterCloseIntent(string tag)
{
   string reason_disp = G_CLOSE_REASON;
   if(G_CLOSE_REASON == "DIFF_CLOSE")
      reason_disp = DiffCloseParenLabel();
   string line = StringFormat(
      "[SFX-SYNC] CLOSE_INTENT_OUT %s tx_id=%s reason=%s pair_key=%s",
      tag, G_CLOSE_TX_ID, reason_disp, G_PAIR_KEY
   );
   ExpertPrintLn(line);
   SyncLog(line);
}

void MarkDegraded(const string reason)
{
   G_DEGRADED = true;
   SyncLog(StringFormat("[SFX-SYNC] DEGRADED: %s", reason));
}

// Scan local terminal for any live EA leg (same magic + symbol).
// Used as a safety guard before clearing degraded state.
bool MasterHasAnyLiveEaLeg()
{
   const int magic = OrderMagic();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderCloseTime() != 0)
         continue;
      if(OrderMagicNumber() != magic)
         continue;
      if(OrderSymbol() != G_SYMBOL)
         continue;
      const int typ = OrderType();
      if(typ != OP_BUY && typ != OP_SELL)
         continue;
      return true;
   }
   return false;
}

// Attempt to clear DEGRADED only when the system is in a safe steady state:
// no in-flight transactions, no force-flat, and no live local EA leg.
// Returns true if cleared, false if any guard blocked the action (with log).
bool TryClearDegraded(const string reason)
{
   if(!G_DEGRADED)
      return false;
   string block = "";
   if(G_OPEN_TX_ACTIVE)         block = "OPEN_TX_ACTIVE";
   else if(G_CLOSE_TX_ACTIVE)   block = "CLOSE_TX_ACTIVE";
   else if(G_FORCE_FLAT_ACTIVE) block = "FORCE_FLAT_ACTIVE";
   else if(MasterHasAnyLiveEaLeg()) block = "LIVE_EA_LEG_FOUND";
   if(StringLen(block) > 0)
   {
      SyncLog(StringFormat("[SFX-SYNC] DEGRADED clear skipped reason=%s blocker=%s", reason, block));
      return false;
   }
   G_DEGRADED = false;
   G_PAIR_ACTIVE = false;
   G_PAIR_KEY = "";
   G_PAIR_MASTER_TICKET = -1;
   G_PAIR_SLAVE_TICKET = -1;
   G_SLAVE_PAIR_OPEN_REPORT = false;
   G_LAST_SLAVE_PAIR_STATUS_MS = 0;
   G_PAIR_OPENED_MS = 0;
   G_PAIR_OPEN_INTENT_MS = 0;
   G_RESCUE_ATTEMPTS_USED = 0;
   if(DiffIsMasterAuto())
      DiffAutoUnlockSearching();
   SyncLog(StringFormat("[SFX-SYNC] DEGRADED cleared reason=%s", reason));
   return true;
}

bool TryRescueHedge()
{
   if(I_CLOSE_MODE != CLOSE_MASTER_FIRST_WITH_RESCUE) return false;
   const int max_att = MathMax(0, I_RESCUE_MAX_ATTEMPTS);
   if(G_RESCUE_ATTEMPTS_USED >= max_att)
   {
      if(max_att > 0)
         ExpertPrintLn(StringFormat("[SFX-SYNC] Rescue hedge skipped — max_attempts=%d exhausted", max_att));
      return false;
   }

   G_RESCUE_ATTEMPTS_USED++;
   int err = 0;
   int type = SideToOrderType(DiffEffectiveMasterSide());
   int rescue_ticket = OpenOrder(type, DynActiveLot(), err);
   if(rescue_ticket > 0)
   {
      G_PAIR_MASTER_TICKET = rescue_ticket;
      G_PAIR_ACTIVE = true;
      G_DEGRADED = false;
      string ln_ok = StringFormat("[SFX-SYNC] Rescue hedge success ticket=%d attempt=%d", rescue_ticket, G_RESCUE_ATTEMPTS_USED);
      ExpertPrintLn(ln_ok);
      SyncLog(ln_ok);
      G_RESCUE_ATTEMPTS_USED = 0;
      return true;
   }
   string ln_fail = StringFormat("[SFX-SYNC] Rescue hedge failed err=%d attempt=%d", err, G_RESCUE_ATTEMPTS_USED);
   ExpertPrintLn(ln_fail);
   SyncLog(ln_fail);
   return false;
}

void FinalizeOpenCommit()
{
   G_PAIR_ACTIVE = true;
   G_PAIR_KEY = G_OPEN_TX_ID;
   G_PAIR_MASTER_TICKET = G_OPEN_MASTER_TICKET;
   G_PAIR_SLAVE_TICKET = G_OPEN_SLAVE_TICKET;
   G_SLAVE_PAIR_OPEN_REPORT = true;
   G_LAST_SLAVE_PAIR_STATUS_MS = NowMs();
   G_PAIR_OPENED_MS = NowMs();
   G_DEGRADED = false;
   G_RESCUE_ATTEMPTS_USED = 0;
   SendMsg(G_PEER, StringFormat("COMMIT;%s", G_OPEN_TX_ID));
   string diff_commit = (G_DIFF_LAST_OPEN_INTENT_TAG == "DIFF_OPEN") ? (" " + DiffOpenParenLabel()) : "";
   SyncLog(StringFormat("[SFX-SYNC] OPEN committed pair_key=%s%s", G_PAIR_KEY, diff_commit));
   ExpertPrintLn(StringFormat("[SFX-SYNC] COMMIT pair_key=%s symbol=%s mticket=%d slave_ticket=%d%s",
                                 G_PAIR_KEY, G_SYMBOL, G_PAIR_MASTER_TICKET, G_PAIR_SLAVE_TICKET, diff_commit));
   DiffArmCooldownsAfterOpenPairCommit();
   if(DiffIsMasterAuto())
      G_DIFF_AUTO_EVER_OPENED = true;
   ResetOpenTxState();
}

void RollbackOpenNow(const string why)
{
   if(!G_OPEN_TX_ACTIVE) return;
   SendMsg(G_PEER, StringFormat("ROLLBACK;%s", G_OPEN_TX_ID));
   bool master_leg_closed = false;
   if(G_OPEN_MASTER_OK && G_OPEN_MASTER_TICKET > 0)
      master_leg_closed = CloseTicketIfOpen(G_OPEN_MASTER_TICKET);
   if(master_leg_closed)
      ArmPostCloseOpenGuard("OPEN_ROLLBACK");
   const string rollback_ln = StringFormat(
      "[SFX-SYNC] OPEN rollback tx_id=%s reason=%s master_ticket=%d master_closed=%s",
      G_OPEN_TX_ID, why, G_OPEN_MASTER_TICKET, master_leg_closed ? "true" : "false"
   );
   SyncLog(rollback_ln);
   ExpertPrintLn(rollback_ln);
   G_PAIR_OPEN_INTENT_MS = 0;
   ResetOpenTxState();
}

void CompleteCloseSuccess()
{
   if(G_PAIR_MASTER_TICKET > 0 && MasterPairLegTicketLive(G_PAIR_MASTER_TICKET))
   {
      SyncLog("[SFX-SYNC] CLOSE complete deferred: master leg still open (force pair-broken retry)");
      G_PAIR_SLAVE_TICKET = -1;
      G_SLAVE_PAIR_OPEN_REPORT = false;
      G_LAST_SLAVE_PAIR_STATUS_MS = NowMs();
      ResetCloseTxState();
      return;
   }
   string cr = G_CLOSE_REASON;
   string cr_disp = cr;
   if(cr == "DIFF_CLOSE")
      cr_disp = DiffCloseParenLabel();
   SyncLog(StringFormat("[SFX-SYNC] CLOSE success pair_key=%s reason=%s", G_PAIR_KEY, cr_disp));
   ExpertPrintLn(StringFormat("[SFX-SYNC] CLOSE success pair_key=%s reason=%s", G_PAIR_KEY, cr_disp));
   G_PAIR_ACTIVE = false;
   G_PAIR_KEY = "";
   G_PAIR_MASTER_TICKET = -1;
   G_PAIR_SLAVE_TICKET = -1;
   G_SLAVE_PAIR_OPEN_REPORT = false;
   G_LAST_SLAVE_PAIR_STATUS_MS = 0;
   G_PAIR_OPENED_MS = 0;
   G_PAIR_OPEN_INTENT_MS = 0;
   G_DEGRADED = false;
   G_RESCUE_ATTEMPTS_USED = 0;
   if(DiffIsMasterAuto())
      DiffAutoUnlockSearching();
   ArmPostCloseOpenGuard("PAIR_CLOSE_SUCCESS");
   DynOnPairClosed(G_DYN_LAST_CLOSE_SCHEDULED);
   G_DYN_LAST_CLOSE_SCHEDULED = false;
   ResetCloseTxState();
}

void HandleCloseFailure(const string why)
{
   SyncLog(StringFormat("[SFX-SYNC] CLOSE failed reason=%s", why));
   if(why == "SLAVE_CLOSE_FAIL" || why == "SLAVE_CLOSE_TIMEOUT")
      StartForceFlatSlave("CLOSE_PATH_RECONCILE");
   if(I_CLOSE_MODE == CLOSE_MASTER_FIRST_WITH_RESCUE)
   {
      ExpertPrintLn(StringFormat("[SFX-SYNC] CLOSE failed reason=%s — trying rescue hedge", why));
      if(TryRescueHedge())
      {
         ResetCloseTxState();
         return;
      }
   }
   MarkDegraded(why);
   ResetCloseTxState();
}

void StartOpenTransaction()
{
   if(I_ROLE != ROLE_SOURCE_MASTER) return;
   string guard_code = "";
   string guard_detail = "";
   if(MasterOpenGuardReason(guard_code, guard_detail))
   {
      SyncLog(StringFormat("[SFX-SYNC] OPEN blocked code=%s detail=%s", guard_code, guard_detail));
      return;
   }
   if(G_PAIR_ACTIVE)
   {
      SyncLog("[SFX-SYNC] OPEN skipped: pair already active");
      return;
   }
   if(G_PEER == NULL || !G_PEER.IsSocketConnected())
   {
      SyncLog("[SFX-SYNC] Cannot open: slave not connected");
      return;
   }
   if(G_OPEN_TX_ACTIVE || G_CLOSE_TX_ACTIVE) return;

   string open_tag = G_PENDING_OPEN_INTENT_TAG;
   if(StringLen(open_tag) == 0)
      open_tag = "UI_BUTTON";
   G_DIFF_LAST_OPEN_INTENT_TAG = open_tag;
   G_PENDING_OPEN_INTENT_TAG = "UI_BUTTON";
   if(open_tag == "DIFF_OPEN")
      G_DIFF_LAST_OPEN_SIGNAL_MS = NowMs();

   string open_lock_key = "";
   double open_lock_token = 0.0;
   if(!TryAcquireActionLock("OPEN", open_tag, open_lock_key, open_lock_token))
   {
      SyncLog(StringFormat("[SFX-SYNC] OPEN dropped: lock busy group=%s scope=%d reason=%s", LockGroupName(), (int)I_LOCK_SCOPE, open_tag));
      return;
   }
   G_OPEN_LOCK_KEY = open_lock_key;
   G_OPEN_LOCK_TOKEN = open_lock_token;

   if(DiffIsMasterAuto() && !G_DIFF_AUTO_SIDE_LOCKED)
      DiffAutoLockManualBest();

   ENUM_SIDE exec_side = DiffEffectiveMasterSide();

   G_OPEN_TX_ID = NewTxId();
   G_OPEN_TX_ACTIVE = true;
   G_OPEN_OVERALL_DEADLINE_MS = NowMs() + (ulong)MathMax(1000, I_OPEN_ROLLBACK_TIMEOUT_MS);
   G_OPEN_SLAVE_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(200, I_SLAVE_OPEN_TIMEOUT_MS);
   G_OPEN_RETRY_LEFT = MathMax(0, I_SLAVE_OPEN_RETRY_COUNT);
   G_OPEN_MASTER_OK = false;
   G_OPEN_MASTER_TICKET = -1;
   G_OPEN_SLAVE_OK = false;
   G_OPEN_SLAVE_TICKET = -1;
   G_OPEN_LAST_ERROR_MASTER = 0;
   G_OPEN_LAST_ERROR_SLAVE = 0;
   G_OPEN_SIDE = SideToString(exec_side);
   G_OPEN_LOT_SLAVE = DynActiveLot();

   int err = 0;
   string master_open_diff_snap = (open_tag == "DIFF_OPEN") ? (" " + DiffOpenParenLabel()) : "";
   if(I_OPEN_MODE == OPEN_BALANCED)
   {
      PrintLogMasterOpenIntent(open_tag);
      G_PAIR_OPEN_INTENT_MS = NowMs();
      SendMsg(G_PEER, BuildOpenIntent());
      const int max_attempts = 1 + MathMax(0, I_MASTER_OPEN_RETRY_COUNT_BALANCED);
      const ulong open_started_ms = NowMs();
      for(int attempt = 1; attempt <= max_attempts; attempt++)
      {
         G_OPEN_MASTER_TICKET = OpenOrder(SideToOrderType(exec_side), DynActiveLot(), err);
         G_OPEN_MASTER_OK = (G_OPEN_MASTER_TICKET > 0);
         if(!G_OPEN_MASTER_OK)
         {
            int recovered_ticket = -1;
            if(RecoverMasterOpenTicketMt4(exec_side, open_started_ms, recovered_ticket))
            {
               G_OPEN_MASTER_TICKET = recovered_ticket;
               G_OPEN_MASTER_OK = true;
               err = 0;
               SyncLog(StringFormat("[SFX-SYNC] OPEN_BALANCED master recovered tx_id=%s attempt=%d ticket=%d",
                                    G_OPEN_TX_ID, attempt, G_OPEN_MASTER_TICKET));
               ExpertPrintLn(StringFormat("[SFX-SYNC] OPEN_BALANCED master recovered tx_id=%s attempt=%d ticket=%d",
                                          G_OPEN_TX_ID, attempt, G_OPEN_MASTER_TICKET));
            }
         }
         G_OPEN_LAST_ERROR_MASTER = err;
         const string attempt_ln = StringFormat(
            "[SFX-SYNC] OPEN_BALANCED master result tx_id=%s attempt=%d/%d ok=%s ticket=%d err=%d%s",
            G_OPEN_TX_ID, attempt, max_attempts, G_OPEN_MASTER_OK ? "true" : "false",
            G_OPEN_MASTER_TICKET, err, master_open_diff_snap
         );
         SyncLog(attempt_ln);
         ExpertPrintLn(attempt_ln);
         if(G_OPEN_MASTER_OK)
            break;
         if(!IsMt4OpenTransientError(err))
         {
            SyncLog(StringFormat("[SFX-SYNC] OPEN_BALANCED master retry stop tx_id=%s err=%d non_transient", G_OPEN_TX_ID, err));
            ExpertPrintLn(StringFormat("[SFX-SYNC] OPEN_BALANCED master retry stop tx_id=%s err=%d non_transient", G_OPEN_TX_ID, err));
            break;
         }
         if(attempt < max_attempts && I_MASTER_OPEN_RETRY_INTERVAL_MS > 0)
            Sleep(I_MASTER_OPEN_RETRY_INTERVAL_MS);
      }
      if(!G_OPEN_MASTER_OK) { RollbackOpenNow("MASTER_OPEN_FAIL"); return; }
   }
   else
   {
      G_OPEN_MASTER_TICKET = OpenOrder(SideToOrderType(exec_side), DynActiveLot(), err);
      G_OPEN_MASTER_OK = (G_OPEN_MASTER_TICKET > 0);
      G_OPEN_LAST_ERROR_MASTER = err;
      SyncLog(StringFormat("[SFX-SYNC] OPEN_MASTER_FIRST master result tx_id=%s ok=%s ticket=%d err=%d%s", G_OPEN_TX_ID, G_OPEN_MASTER_OK ? "true" : "false", G_OPEN_MASTER_TICKET, err, master_open_diff_snap));
      if(!G_OPEN_MASTER_OK) { RollbackOpenNow("MASTER_OPEN_FAIL"); return; }
      PrintLogMasterOpenIntent(open_tag);
      G_PAIR_OPEN_INTENT_MS = NowMs();
      SendMsg(G_PEER, BuildOpenIntent());
   }
}

void StartCloseTransaction(const string reason)
{
   if(I_ROLE != ROLE_SOURCE_MASTER) return;
   string guard_code = "";
   string guard_detail = "";
   if(MasterCloseGuardReason(guard_code, guard_detail))
   {
      SyncLog(StringFormat("[SFX-SYNC] CLOSE blocked code=%s detail=%s", guard_code, guard_detail));
      return;
   }
   if(G_CLOSE_TX_ACTIVE || G_OPEN_TX_ACTIVE) return;
   if(!G_PAIR_ACTIVE)
   {
      SyncLog("[SFX-SYNC] CLOSE skipped: no active pair");
      return;
   }
   if(G_PEER == NULL || !G_PEER.IsSocketConnected())
   {
      SyncLog("[SFX-SYNC] CLOSE skipped: slave disconnected");
      return;
   }

   string close_lock_key = "";
   double close_lock_token = 0.0;
   if(!TryAcquireActionLock("CLOSE", reason, close_lock_key, close_lock_token))
   {
      SyncLog(StringFormat("[SFX-SYNC] CLOSE dropped: lock busy group=%s scope=%d reason=%s", LockGroupName(), (int)I_LOCK_SCOPE, reason));
      return;
   }
   G_CLOSE_LOCK_KEY = close_lock_key;
   G_CLOSE_LOCK_TOKEN = close_lock_token;

   if(reason == "DIFF_CLOSE")
      G_DIFF_LAST_CLOSE_SIGNAL_MS = NowMs();
   G_DYN_LAST_CLOSE_SCHEDULED = DynCloseReasonIsScheduled(reason);

   G_CLOSE_TX_ID = NewTxId();
   G_CLOSE_REASON = reason;
   G_CLOSE_TX_ACTIVE = true;
   G_CLOSE_OVERALL_DEADLINE_MS = NowMs() + (ulong)MathMax(1000, I_OPEN_ROLLBACK_TIMEOUT_MS);
   G_CLOSE_SLAVE_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(200, I_SLAVE_CLOSE_TIMEOUT_MS);
   G_CLOSE_RETRY_LEFT = MathMax(0, I_SLAVE_CLOSE_RETRY_COUNT);
   G_CLOSE_MASTER_OK = false;
   G_CLOSE_SLAVE_OK = false;
   G_CLOSE_LAST_ERROR_MASTER = 0;
   G_CLOSE_LAST_ERROR_SLAVE = 0;

   PrintLogMasterCloseBegin(reason);

   bool master_closed = true;
   if(I_CLOSE_MODE == CLOSE_BALANCED)
   {
      PrintLogMasterCloseIntent("initial_balanced_slave_first");
      SendMsg(G_PEER, BuildCloseIntent());
   }

   // Always attempt close by tracked ticket. Do not gate on IsTicketOpen(): a false negative
   // would skip CloseTicketIfOpen while leaving master_closed=true, orphaning the master leg.
   if(G_PAIR_MASTER_TICKET > 0)
      master_closed = CloseTicketIfOpenWithPolicy(G_PAIR_MASTER_TICKET, (I_CLOSE_MODE == CLOSE_BALANCED));

   G_CLOSE_MASTER_OK = master_closed;
   if(!G_CLOSE_MASTER_OK)
   {
      G_CLOSE_LAST_ERROR_MASTER = GetLastError();
      HandleCloseFailure("MASTER_CLOSE_FAIL");
      return;
   }

   if(I_CLOSE_MODE != CLOSE_BALANCED)
   {
      PrintLogMasterCloseIntent("master_first_after_master");
      SendMsg(G_PEER, BuildCloseIntent());
   }
}

void HandleMasterIncomingPacket(const string msg)
{
   string p[];
   if(!SplitSemicolonFields(msg, p)) return;
   if(ArraySize(p) <= 0) return;

   if(p[0] == "HELLO" && ArraySize(p) >= 3)
   {
      if(p[1] != I_SECRET)
      {
         SendMsg(G_PEER, "HELLO_ACK;NO");
         CloseClient(G_PEER);
         return;
      }
      string peer_version = (ArraySize(p) >= 4) ? p[3] : "";
      if(peer_version != SFX_SYNC_EA_VERSION)
      {
         string ln = StringFormat(
            "[SFX-SYNC] HELLO version mismatch local=%s peer=%s — rejecting and detaching",
            SFX_SYNC_EA_VERSION,
            StringLen(peer_version) > 0 ? peer_version : "<unknown>");
         SyncLog(ln);
         ExpertPrintLn(ln);
         Alert(StringFormat("[SFX-SYNC] Version mismatch local=%s peer=%s — EA detaching",
                            SFX_SYNC_EA_VERSION,
                            StringLen(peer_version) > 0 ? peer_version : "<unknown>"));
         SendMsg(G_PEER, StringFormat("HELLO_ACK;VERSION_MISMATCH;%s", SFX_SYNC_EA_VERSION));
         CloseClient(G_PEER);
         ExpertRemove();
         return;
      }
      G_HANDSHAKE_OK = true;
      SendMsg(G_PEER, StringFormat("HELLO_ACK;YES;%s", SFX_SYNC_EA_VERSION));
      ExpertPrintLn(StringFormat("Handshake OK slave_account=%s ver=%s", p[2], peer_version));
      SyncLog(StringFormat("[SFX-SYNC] Slave handshake success account=%s ver=%s", p[2], peer_version));
      return;
   }

   if(p[0] == "PAIR_STATUS" && ArraySize(p) >= 4)
   {
      string pair_key_in = p[1];
      int slave_ticket_in = (int)StringToInteger(p[2]);
      bool slave_open_in = ((int)StringToInteger(p[3]) == 1);
      int slave_ea_open_count = slave_open_in ? 1 : 0;
      if(ArraySize(p) >= 5)
         slave_ea_open_count = MathMax(0, (int)StringToInteger(p[4]));
      bool accept = true;

      // Ignore key-mismatch frames unless they still reference the tracked slave ticket.
      // This prevents pre-COMMIT stale clear-state frames from forcing immediate PAIR_BROKEN closes.
      if(G_PAIR_ACTIVE && StringLen(G_PAIR_KEY) > 0 && pair_key_in != G_PAIR_KEY)
      {
         bool clear_state = (!slave_open_in && slave_ticket_in <= 0);
         bool pair_old_enough =
            (G_PAIR_OPENED_MS > 0 &&
             (NowMs() - G_PAIR_OPENED_MS) >= (ulong)MathMax(0, I_PAIR_CLEAR_CROSSKEY_MIN_AGE_SEC) * 1000);
         bool same_tracked_ticket = (slave_ticket_in > 0 && slave_ticket_in == G_PAIR_SLAVE_TICKET);
         if(!same_tracked_ticket && !(clear_state && pair_old_enough))
            accept = false;
      }
      if(!accept)
         return;

      if(!slave_open_in && slave_ticket_in <= 0)
         G_PAIR_SLAVE_TICKET = -1;
      else
         G_PAIR_SLAVE_TICKET = slave_ticket_in;
      G_SLAVE_PAIR_OPEN_REPORT = slave_open_in;
      G_SLAVE_EA_OPEN_COUNT = slave_ea_open_count;
      G_LAST_SLAVE_PAIR_STATUS_MS = NowMs();
      return;
   }

   if(p[0] == "SLAVE")
   {
      if(ArraySize(p) < 9)
         return;
      const ulong prev_s = G_DIFF_SLAVE_MS;
      const ulong nowm = NowMs();
      G_DIFF_SLAVE_BID = DiffNormQuotePrice(StringToDouble(p[1]));
      G_DIFF_SLAVE_ASK = DiffNormQuotePrice(StringToDouble(p[2]));
      G_DIFF_SLAVE_QUOTE_MSC = (ulong)StringToDouble(p[4]);
      G_DIFF_SLAVE_TRADE_MODE = (int)StringToInteger(p[5]);
      G_DIFF_SLAVE_STREAM_PROFIT = StringToDouble(p[7]);
      G_SLAVE_BALANCE_REPORT = StringToDouble(p[8]);
      G_SLAVE_BALANCE_VALID = true;
      G_DIFF_SLAVE_MS = nowm;
      G_DIFF_SLAVE_QUOTE_OK =
         (G_DIFF_SLAVE_BID > 0.0 && G_DIFF_SLAVE_ASK > 0.0 && G_DIFF_SLAVE_ASK >= G_DIFF_SLAVE_BID);
      G_QMON_SLAVE_FRAMES++;
      if(prev_s > 0 && (nowm - prev_s) > 0 && (nowm - prev_s) < 300000)
         DiffQuoteMonitorOnSlaveGap(nowm - prev_s);
      return;
   }

   if(p[0] == "OPEN_RESULT" && ArraySize(p) >= 5)
   {
      if(!G_OPEN_TX_ACTIVE) return;
      if(p[1] != G_OPEN_TX_ID) return;
      G_OPEN_SLAVE_OK = ((int)StringToInteger(p[2]) == 1);
      G_OPEN_SLAVE_TICKET = (int)StringToInteger(p[3]);
      G_OPEN_LAST_ERROR_SLAVE = (int)StringToInteger(p[4]);

      SyncLog(StringFormat("[SFX-SYNC] Slave open result tx_id=%s ok=%s ticket=%d err=%d", G_OPEN_TX_ID, G_OPEN_SLAVE_OK ? "true" : "false", G_OPEN_SLAVE_TICKET, G_OPEN_LAST_ERROR_SLAVE));

      if(G_OPEN_MASTER_OK && G_OPEN_SLAVE_OK)
      {
         FinalizeOpenCommit();
      }
      else if(G_OPEN_MASTER_OK && !G_OPEN_SLAVE_OK && G_OPEN_RETRY_LEFT > 0)
      {
         PrintLogMasterOpenIntent("retry_slave_fail_result");
         SendMsg(G_PEER, BuildOpenIntent());
         G_OPEN_RETRY_LEFT--;
         G_OPEN_SLAVE_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(100, I_SLAVE_OPEN_RETRY_INTERVAL_MS);
      }
      else if(G_OPEN_MASTER_OK && !G_OPEN_SLAVE_OK && PairWithinSettleGrace())
      {
         PrintLogMasterOpenIntent("retry_within_grace");
         SendMsg(G_PEER, BuildOpenIntent());
         G_OPEN_SLAVE_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(100, I_SLAVE_OPEN_RETRY_INTERVAL_MS);
      }
      else
      {
         RollbackOpenNow("SLAVE_OPEN_FAIL");
      }
      return;
   }

   if(p[0] == "CLOSE_RESULT" && ArraySize(p) >= 5)
   {
      if(!G_CLOSE_TX_ACTIVE) return;
      if(p[1] != G_CLOSE_TX_ID) return;
      G_CLOSE_SLAVE_OK = ((int)StringToInteger(p[2]) == 1);
      G_CLOSE_LAST_ERROR_SLAVE = (int)StringToInteger(p[4]);
      G_CLOSE_SLAVE_BALANCE = (ArraySize(p) >= 6) ? StringToDouble(p[5]) : 0.0;
      if(G_CLOSE_MASTER_OK && G_CLOSE_SLAVE_OK) CompleteCloseSuccess();
      else HandleCloseFailure("SLAVE_CLOSE_FAIL");
      return;
   }

   if(p[0] == "FORCE_FLAT_RESULT" && ArraySize(p) >= 5)
   {
      if(!G_FORCE_FLAT_ACTIVE)
         return;
      if(p[1] != G_FORCE_FLAT_TX_ID)
         return;
      bool ok = ((int)StringToInteger(p[2]) == 1);
      int remain = MathMax(0, (int)StringToInteger(p[3]));
      int closed = MathMax(0, (int)StringToInteger(p[4]));
      double force_slave_bal = (ArraySize(p) >= 6) ? StringToDouble(p[5]) : 0.0;
      SyncLog(StringFormat("[SFX-SYNC] FORCE_FLAT result tx_id=%s ok=%s remain=%d closed=%d bal=%.2f",
                           G_FORCE_FLAT_TX_ID, ok ? "true" : "false", remain, closed, force_slave_bal));
      if(ok && remain == 0)
      {
         G_SLAVE_PAIR_OPEN_REPORT = false;
         G_SLAVE_EA_OPEN_COUNT = 0;
         G_PAIR_SLAVE_TICKET = -1;
         ArmPostCloseOpenGuard("FORCE_FLAT_SYNC");
         ResetForceFlatState();
      }
      else if(G_FORCE_FLAT_RETRY_LEFT <= 0)
      {
         MarkDegraded("FORCE_FLAT_FAIL");
         ResetForceFlatState();
      }
      else
      {
         G_FORCE_FLAT_WAIT_DEADLINE_MS = NowMs() + 1;
      }
      return;
   }
}

void HandleSlaveIncomingPacket(const string msg)
{
   string p[];
   if(!SplitSemicolonFields(msg, p)) return;
   if(ArraySize(p) <= 0) return;

   if(p[0] == "CHANNEL_REJECT" && ArraySize(p) >= 2)
   {
      const string code = p[1];
      ExpertPrintLn(StringFormat("[SFX-SYNC] Rejected by master: %s", code));
      SyncLog(StringFormat("[SFX-SYNC] CHANNEL_REJECT code=%s", code));
      if(code == "PAIR_CHANNEL_OCCUPIED")
         G_SLAVE_DUP_CHANNEL_SHUTDOWN = true;
      G_HANDSHAKE_OK = false;
      CloseClient(G_PEER);
      return;
   }

   if(p[0] == "HELLO_ACK" && ArraySize(p) >= 2)
   {
      if(p[1] == "VERSION_MISMATCH")
      {
         string peer_v = (ArraySize(p) >= 3) ? p[2] : "<unknown>";
         string ln = StringFormat(
            "[SFX-SYNC] HELLO_ACK VERSION_MISMATCH local=%s master=%s — detaching",
            SFX_SYNC_EA_VERSION, peer_v);
         SyncLog(ln);
         ExpertPrintLn(ln);
         Alert(StringFormat("[SFX-SYNC] Version mismatch local=%s master=%s — EA detaching",
                            SFX_SYNC_EA_VERSION, peer_v));
         G_HANDSHAKE_OK = false;
         CloseClient(G_PEER);
         ExpertRemove();
         return;
      }
      G_HANDSHAKE_OK = (p[1] == "YES");
      if(G_HANDSHAKE_OK)
      {
         string peer_v = (ArraySize(p) >= 3) ? p[2] : "<unknown>";
         ExpertPrintLn(StringFormat("Handshake OK: connected to source master ver=%s.", peer_v));
         SyncLog(StringFormat("[SFX-SYNC] Connected to source master ver=%s", peer_v));
      }
      else
         ExpertPrintLn("Handshake refused: HELLO_ACK NO (check I_SECRET matches master).");
      return;
   }

   if(p[0] == "WEEKEND_FLATTEN")
   {
      SlaveCloseAllOrders();
      SlaveWeekendReset();
      SyncLog("[SFX-SYNC] WEEKEND_FLATTEN: slave flat all EA orders on symbol");
      return;
   }

   if(p[0] == "FORCE_FLAT" && ArraySize(p) >= 2)
   {
      string txid = p[1];
      string why = (ArraySize(p) >= 3) ? p[2] : "FORCE_FLAT";
      int before_n = CountEaOpenOrdersOnSlaveSymbol();
      SlaveCloseAllOrders();
      SlaveWeekendReset();
      int after_n = CountEaOpenOrdersOnSlaveSymbol();
      int closed_n = MathMax(0, before_n - after_n);
      bool ok = (after_n == 0);
      const double bal = AccountBalance();
      SendMsg(G_PEER, StringFormat("FORCE_FLAT_RESULT;%s;%d;%d;%d;%.2f", txid, ok ? 1 : 0, after_n, closed_n, bal));
      SyncLog(StringFormat("[SFX-SYNC] FORCE_FLAT_IN tx_id=%s reason=%s before=%d after=%d bal=%.2f",
                           txid, why, before_n, after_n, bal));
      return;
   }

   if(p[0] == "OPEN_INTENT" && ArraySize(p) >= 8)
   {
      string txid = p[1];
      string side = p[3];
      double lot_slave = StringToDouble(p[5]);
      int type = (side == "BUY") ? OP_SELL : OP_BUY;
      string ln = StringFormat("[SFX-SYNC] OPEN_INTENT_IN tx_id=%s symbol=%s master_side=%s lot_slave=%.2f exec_type=%d",
                               txid, G_SYMBOL, side, lot_slave, type);
      ExpertPrintLn(ln);
      SyncLog(ln);

      if(txid == G_SLAVE_PENDING_OPEN_TXID)
      {
         bool still_ok = IsTicketOpen(G_SLAVE_PENDING_OPEN_TICKET);
         if(still_ok)
         {
            G_SLAVE_PENDING_OPEN_DEADLINE_MS = NowMs() + (ulong)MathMax(300, I_SLAVE_PENDING_COMMIT_TIMEOUT_MS);
            SendMsg(G_PEER, StringFormat("OPEN_RESULT;%s;%d;%d;%d", txid, 1, G_SLAVE_PENDING_OPEN_TICKET, 0));
            return;
         }
      }

      // Idempotent guard: duplicate OPEN_INTENT with same tx_id must not open another order.
      if(txid == G_SLAVE_LAST_OPEN_TXID && G_SLAVE_LAST_OPEN_OK >= 0)
      {
         // Recovery on duplicate: if cached result was fail or has no ticket, scan trades again.
         // Covers cases where broker accepted the order but EA could not capture the ticket on first attempt.
         if(G_SLAVE_LAST_OPEN_OK == 0 || G_SLAVE_LAST_OPEN_TICKET <= 0)
         {
            int recovered_ticket = -1;
            const ENUM_SIDE rec_side = (type == OP_BUY) ? SIDE_BUY : SIDE_SELL;
            const ulong since_ms = (G_SLAVE_LAST_OPEN_STARTED_MS > 0) ? G_SLAVE_LAST_OPEN_STARTED_MS : 0;
            if(RecoverMasterOpenTicketMt4(rec_side, since_ms, recovered_ticket) && recovered_ticket > 0)
            {
               G_SLAVE_LAST_OPEN_OK = 1;
               G_SLAVE_LAST_OPEN_TICKET = recovered_ticket;
               G_SLAVE_LAST_OPEN_ERR = 0;
               SyncLog(StringFormat("[SFX-SYNC] OPEN_INTENT duplicate replay recovered tx_id=%s ticket=%d",
                                    txid, recovered_ticket));
            }
         }
         if(G_SLAVE_LAST_OPEN_OK == 1 && G_SLAVE_LAST_OPEN_TICKET > 0)
         {
            G_SLAVE_PENDING_OPEN_TXID = txid;
            G_SLAVE_PENDING_OPEN_TICKET = G_SLAVE_LAST_OPEN_TICKET;
            G_SLAVE_PENDING_OPEN_DEADLINE_MS = NowMs() + (ulong)MathMax(300, I_SLAVE_PENDING_COMMIT_TIMEOUT_MS);
         }
         SyncLog(StringFormat("[SFX-SYNC] OPEN_INTENT duplicate replay tx_id=%s ok=%d ticket=%d err=%d",
                              txid, G_SLAVE_LAST_OPEN_OK, G_SLAVE_LAST_OPEN_TICKET, G_SLAVE_LAST_OPEN_ERR));
         SendMsg(G_PEER, StringFormat("OPEN_RESULT;%s;%d;%d;%d",
                                      txid, G_SLAVE_LAST_OPEN_OK, G_SLAVE_LAST_OPEN_TICKET, G_SLAVE_LAST_OPEN_ERR));
         return;
      }

      G_SLAVE_LAST_OPEN_STARTED_MS = NowMs();
      int err = 0;
      int tk = OpenOrder(type, lot_slave, err);
      bool ok = (tk > 0);
      G_SLAVE_PENDING_OPEN_TXID = txid;
      G_SLAVE_PENDING_OPEN_TICKET = tk;
      G_SLAVE_PENDING_OPEN_DEADLINE_MS = (ok ? (NowMs() + (ulong)MathMax(300, I_SLAVE_PENDING_COMMIT_TIMEOUT_MS)) : 0);
      G_SLAVE_LAST_OPEN_TXID = txid;
      G_SLAVE_LAST_OPEN_OK = ok ? 1 : 0;
      G_SLAVE_LAST_OPEN_TICKET = tk;
      G_SLAVE_LAST_OPEN_ERR = err;

      SendMsg(G_PEER, StringFormat("OPEN_RESULT;%s;%d;%d;%d", txid, ok ? 1 : 0, tk, err));
      return;
   }

   if(p[0] == "ROLLBACK" && ArraySize(p) >= 2)
   {
      string txid = p[1];
      if(txid == G_SLAVE_PENDING_OPEN_TXID && G_SLAVE_PENDING_OPEN_TICKET > 0)
      {
         CloseTicketIfOpen(G_SLAVE_PENDING_OPEN_TICKET);
         const string rollback_applied_ln = StringFormat(
            "[SFX-SYNC] ROLLBACK applied tx_id=%s sticket=%d",
            txid, G_SLAVE_PENDING_OPEN_TICKET
         );
         SyncLog(rollback_applied_ln);
         ExpertPrintLn(rollback_applied_ln);
      }
      G_SLAVE_PENDING_OPEN_TICKET = -1;
      G_SLAVE_PENDING_OPEN_TXID = "";
      G_SLAVE_PENDING_OPEN_DEADLINE_MS = 0;
      if(txid == G_SLAVE_LAST_OPEN_TXID)
      {
         G_SLAVE_LAST_OPEN_TXID = "";
         G_SLAVE_LAST_OPEN_OK = -1;
         G_SLAVE_LAST_OPEN_TICKET = -1;
         G_SLAVE_LAST_OPEN_ERR = 0;
         G_SLAVE_LAST_OPEN_STARTED_MS = 0;
      }
      return;
   }

   if(p[0] == "COMMIT" && ArraySize(p) >= 2)
   {
      if(p[1] == G_SLAVE_PENDING_OPEN_TXID)
      {
         G_SLAVE_PAIR_KEY = p[1];
         G_SLAVE_PAIR_TICKET = G_SLAVE_PENDING_OPEN_TICKET;
         G_SLAVE_PENDING_OPEN_TXID = "";
         G_SLAVE_PENDING_OPEN_TICKET = -1;
         G_SLAVE_PENDING_OPEN_DEADLINE_MS = 0;
         ExpertPrintLn(StringFormat("[SFX-SYNC] COMMIT applied pair_key=%s symbol=%s sticket=%d",
                                       G_SLAVE_PAIR_KEY, G_SYMBOL, G_SLAVE_PAIR_TICKET));
      }
      else
      {
         SyncLog(StringFormat("[SFX-SYNC] COMMIT ignored: tx_id=%s pending_tx=%s",
                              p[1], G_SLAVE_PENDING_OPEN_TXID));
      }
      return;
   }

   if(p[0] == "CLOSE_INTENT" && ArraySize(p) >= 4)
   {
      string txid = p[1];
      string close_reason_in = (ArraySize(p) >= 3) ? p[2] : "";
      string pair_key = p[3];
      string ln = StringFormat("[SFX-SYNC] CLOSE_INTENT_IN tx_id=%s reason=%s pair_key=%s sticket=%d",
                               txid, close_reason_in, pair_key, G_SLAVE_PAIR_TICKET);
      ExpertPrintLn(ln);
      SyncLog(ln);
      bool ok = false;
      int err = 0;
      double slave_pnl = 0.0;
      if(StringLen(G_SLAVE_PAIR_KEY) == 0 || G_SLAVE_PAIR_TICKET <= 0)
      {
         err = -9101; // no active pair
      }
      else if(G_SLAVE_PAIR_KEY != pair_key)
      {
         err = -9102; // pair key mismatch
         SyncLog(StringFormat("[SFX-SYNC] CLOSE_INTENT rejected pair_key mismatch local=%s remote=%s",
                              G_SLAVE_PAIR_KEY, pair_key));
      }
      else
      {
         const int ticket_to_close = G_SLAVE_PAIR_TICKET;
         ok = CloseTicketIfOpen(ticket_to_close);
         if(!ok)
            err = GetLastError();
         else
         {
            G_SLAVE_PAIR_TICKET = -1;
            G_SLAVE_PAIR_KEY = "";
         }
      }
      const double bal = AccountBalance();
      SendMsg(G_PEER, StringFormat("CLOSE_RESULT;%s;%d;%d;%d;%.2f", txid, ok ? 1 : 0, G_SLAVE_PAIR_TICKET, err, bal));
      return;
   }
}

void MasterLoop()
{
   DoNotDisturbUpdateSchedule();
   CloseOnlyUpdateSchedule();
   CloseOnlyTryWeekendCloseAll();

   if(G_SERVER == NULL)
   {
      G_SERVER = new ServerSocket(I_PORT, false);
      if(G_SERVER == NULL || !G_SERVER.Created())
      {
         SyncLog(StringFormat("[SFX-SYNC] Server socket create failed on port=%d", (int)I_PORT));
         return;
      }
      SyncLog(StringFormat("[SFX-SYNC] Source master listening on port=%d", (int)I_PORT));
   }

   if(G_PEER == NULL)
   {
      ClientSocket *tmp = G_SERVER.Accept();
      if(tmp != NULL)
      {
         G_PEER = tmp;
         G_HANDSHAKE_OK = false;
      }
   }

   MasterDrainExtraSlaves();

   DiffRefreshHudMetricsOnly();

   if(G_PEER != NULL && G_PEER.IsSocketConnected())
   {
      string msg = "";
      do
      {
         msg = G_PEER.Receive("~");
         if(StringLen(msg) > 0)
            HandleMasterIncomingPacket(msg);
      }
      while(StringLen(msg) > 0);

      DiffMasterTick();
      MasterRecoverOrphanLegsIfNeeded();
      MonitorForceFlatState();

      if(!G_PAIR_ACTIVE && !G_OPEN_TX_ACTIVE && !G_CLOSE_TX_ACTIVE && !G_FORCE_FLAT_ACTIVE
         && !PairWithinSettleGrace())
      {
         if(G_SLAVE_EA_OPEN_COUNT > 0 || G_SLAVE_PAIR_OPEN_REPORT || G_PAIR_SLAVE_TICKET > 0)
            StartForceFlatSlave("SLAVE_ORPHAN_RECONCILE");
      }

      if(G_OPEN_SIGNAL_REQUESTED && G_HANDSHAKE_OK)
      {
         string open_r = G_OPEN_SIGNAL_REASON;
         if(StringLen(open_r) == 0)
            open_r = "UI_BUTTON";
         G_PENDING_OPEN_INTENT_TAG = open_r;
         G_OPEN_SIGNAL_REQUESTED = false;
         G_OPEN_SIGNAL_REASON = "UI_BUTTON";
         StartOpenTransaction();
      }
      if(G_CLOSE_SIGNAL_REQUESTED && G_HANDSHAKE_OK)
      {
         string close_r = G_CLOSE_SIGNAL_REASON;
         if(StringLen(close_r) == 0)
            close_r = "UI_BUTTON";
         G_CLOSE_SIGNAL_REQUESTED = false;
         G_CLOSE_SIGNAL_REASON = "UI_BUTTON";
         StartCloseTransaction(close_r);
      }

      // Post-commit leg mismatch -> immediate PAIR_BROKEN close-sync.
      if(G_PAIR_ACTIVE && !G_CLOSE_TX_ACTIVE && !G_OPEN_TX_ACTIVE)
      {
         ulong now_ms = NowMs();
         bool master_open = MasterPairLegTicketLive(G_PAIR_MASTER_TICKET);
         bool slave_status_stale =
            (G_LAST_SLAVE_PAIR_STATUS_MS > 0 &&
             (now_ms - G_LAST_SLAVE_PAIR_STATUS_MS) > (ulong)MathMax(200, I_PAIR_STATUS_STALE_MS));
         bool peer_link_ok = (G_PEER != NULL && G_PEER.IsSocketConnected() && G_HANDSHAKE_OK);
         bool slave_stream_fresh =
            (G_DIFF_SLAVE_MS > 0 &&
             (now_ms - G_DIFF_SLAVE_MS) <= (ulong)MathMax(I_PAIR_STATUS_STALE_MS, I_DIFF_QUOTES_FRESH_MS * 2));
         if(!PairWithinSettleGrace())
         {
            if(master_open != G_SLAVE_PAIR_OPEN_REPORT)
               StartCloseTransaction("PAIR_BROKEN");
            else if(master_open && G_PAIR_SLAVE_TICKET <= 0)
               StartCloseTransaction("PAIR_BROKEN");
            else if(master_open && slave_status_stale && peer_link_ok && slave_stream_fresh)
               StartCloseTransaction("PAIR_STATUS_STALE");
         }
         else if(master_open && slave_status_stale && peer_link_ok && slave_stream_fresh)
            StartCloseTransaction("PAIR_STATUS_STALE");
      }

      if(G_OPEN_TX_ACTIVE)
      {
         if(NowMs() > G_OPEN_OVERALL_DEADLINE_MS)
            RollbackOpenNow("OPEN_OVERALL_TIMEOUT");
         else if(!G_OPEN_SLAVE_OK && NowMs() > G_OPEN_SLAVE_WAIT_DEADLINE_MS)
         {
            if(G_OPEN_RETRY_LEFT > 0)
            {
               PrintLogMasterOpenIntent("retry_slave_result");
               SendMsg(G_PEER, BuildOpenIntent());
               G_OPEN_RETRY_LEFT--;
               G_OPEN_SLAVE_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(100, I_SLAVE_OPEN_RETRY_INTERVAL_MS);
            }
            else if(PairWithinSettleGrace())
            {
               PrintLogMasterOpenIntent("retry_within_grace");
               SendMsg(G_PEER, BuildOpenIntent());
               G_OPEN_SLAVE_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(100, I_SLAVE_OPEN_RETRY_INTERVAL_MS);
            }
            else
            {
               RollbackOpenNow("SLAVE_OPEN_TIMEOUT");
            }
         }
      }

      if(G_CLOSE_TX_ACTIVE)
      {
         if(NowMs() > G_CLOSE_OVERALL_DEADLINE_MS)
            HandleCloseFailure("CLOSE_OVERALL_TIMEOUT");
         else if(!G_CLOSE_SLAVE_OK && NowMs() > G_CLOSE_SLAVE_WAIT_DEADLINE_MS)
         {
            if(G_CLOSE_RETRY_LEFT > 0)
            {
               PrintLogMasterCloseIntent("retry_slave_result");
               SendMsg(G_PEER, BuildCloseIntent());
               G_CLOSE_RETRY_LEFT--;
               G_CLOSE_SLAVE_WAIT_DEADLINE_MS = NowMs() + (ulong)MathMax(100, I_SLAVE_CLOSE_RETRY_INTERVAL_MS);
            }
            else
            {
               HandleCloseFailure("SLAVE_CLOSE_TIMEOUT");
            }
         }
      }
   }
   else
   {
      CloseClient(G_PEER);
      G_HANDSHAKE_OK = false;
      if(G_OPEN_TX_ACTIVE)
      {
         if(G_OPEN_DISCONNECT_DEADLINE_MS == 0)
         {
            ulong grace_end = NowMs() + (ulong)MathMax(1000, I_OPEN_TX_DISCONNECT_GRACE_MS);
            if(G_OPEN_OVERALL_DEADLINE_MS > 0)
               grace_end = MathMin(grace_end, G_OPEN_OVERALL_DEADLINE_MS);
            G_OPEN_DISCONNECT_DEADLINE_MS = grace_end;
            SyncLog(StringFormat("[SFX-SYNC] OPEN disconnect grace started tx_id=%s", G_OPEN_TX_ID));
         }
         else if(NowMs() >= G_OPEN_DISCONNECT_DEADLINE_MS)
         {
            if(G_OPEN_MASTER_OK && G_OPEN_MASTER_TICKET > 0)
            {
               const bool closed = CloseTicketIfOpenWithPolicy(G_OPEN_MASTER_TICKET, false);
               SyncLog(StringFormat("[SFX-SYNC] OPEN disconnect grace expired tx_id=%s ticket=%d closed=%s",
                                    G_OPEN_TX_ID, G_OPEN_MASTER_TICKET, closed ? "true" : "false"));
               if(closed)
                  ArmPostCloseOpenGuard("OPEN_DISCONNECT_ROLLBACK");
            }
            else
            {
               SyncLog(StringFormat("[SFX-SYNC] OPEN disconnect grace expired (no master leg) tx_id=%s", G_OPEN_TX_ID));
            }
            G_OPEN_DISCONNECT_DEADLINE_MS = 0;
            ResetOpenTxState();
         }
      }
      MasterHandleDisconnectDuringTransactions();
      MasterRecoverOrphanLegsIfNeeded();
      G_SLAVE_EA_OPEN_COUNT = 0;
      G_SLAVE_PAIR_OPEN_REPORT = false;
      G_PAIR_SLAVE_TICKET = -1;
   }
}

void SlaveLoop()
{
   if(G_SLAVE_DUP_CHANNEL_SHUTDOWN)
      return;

   SlaveCheckPendingOpenTimeout();

   if(G_PEER == NULL)
   {
      G_PEER = new ClientSocket(I_MASTER_IP, I_PORT);
      G_HANDSHAKE_OK = false;
      if(G_PEER != NULL && G_PEER.IsSocketConnected())
      {
         SendMsg(G_PEER, StringFormat("HELLO;%s;%d;%s", I_SECRET, AccountNumber(), SFX_SYNC_EA_VERSION));
      }
   }

   if(G_PEER != NULL && G_PEER.IsSocketConnected())
   {
      string msg = "";
      do
      {
         msg = G_PEER.Receive("~");
         if(StringLen(msg) > 0)
            HandleSlaveIncomingPacket(msg);
      }
      while(StringLen(msg) > 0);

      SlaveCheckPendingOpenTimeout();

      bool slave_pair_open = IsTicketOpen(G_SLAVE_PAIR_TICKET);
      int ea_open_n = CountEaOpenOrdersOnSlaveSymbol();
      SendMsg(G_PEER, StringFormat("PAIR_STATUS;%s;%d;%d;%d", G_SLAVE_PAIR_KEY, G_SLAVE_PAIR_TICKET, slave_pair_open ? 1 : 0, ea_open_n));
   }
   else
   {
      CloseClient(G_PEER);
      G_HANDSHAKE_OK = false;
   }
}

void CreateButtons()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;

   if(ObjectFind(0, "SFX_OPEN_NOW") < 0)
      ObjectCreate(0, "SFX_OPEN_NOW", OBJ_BUTTON, 0, 0, 0);
   if(ObjectFind(0, "SFX_CLOSE_NOW") < 0)
      ObjectCreate(0, "SFX_CLOSE_NOW", OBJ_BUTTON, 0, 0, 0);
   if(ObjectFind(0, "SFX_CLOSE_ONLY") < 0)
      ObjectCreate(0, "SFX_CLOSE_ONLY", OBJ_BUTTON, 0, 0, 0);
   if(ObjectFind(0, "SFX_DND_MODE") < 0)
      ObjectCreate(0, "SFX_DND_MODE", OBJ_BUTTON, 0, 0, 0);
   if(ObjectFind(0, "SFX_DYN_LOT_RESET") < 0)
      ObjectCreate(0, "SFX_DYN_LOT_RESET", OBJ_BUTTON, 0, 0, 0);
   if(ObjectFind(0, "SFX_CLEAR_DEGRADED") < 0)
      ObjectCreate(0, "SFX_CLEAR_DEGRADED", OBJ_BUTTON, 0, 0, 0);

   // CORNER_RIGHT_UPPER: inset from chart right; extra margin clears price scale on OBJ_BUTTON.
   const int bx = 8 + 126;
   const int bw = 128;
   const int bh = 26;
   const int btn_gap = 6;
   const int y_open = 160;
   const int y_close = y_open + bh + btn_gap;
   const int y_co = y_close + bh + btn_gap;
   const int y_dnd = y_co + bh + btn_gap;
   const int y_dyn = y_dnd + bh + btn_gap;
   const int y_deg = y_dyn + bh + btn_gap;

   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_YDISTANCE, y_open);
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_XSIZE, bw);
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_YSIZE, bh);
   ObjectSetString(0, "SFX_OPEN_NOW", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_COLOR, C'48,95,72');
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_BGCOLOR, C'170,215,190');
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_BORDER_COLOR, C'130,175,155');
   ObjectSetInteger(0, "SFX_OPEN_NOW", OBJPROP_BACK, false);
   ObjectSetString(0, "SFX_OPEN_NOW", OBJPROP_TEXT, "OPEN");

   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_YDISTANCE, y_close);
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_XSIZE, bw);
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_YSIZE, bh);
   ObjectSetString(0, "SFX_CLOSE_NOW", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_COLOR, C'110,58,58');
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_BGCOLOR, C'232,195,195');
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_BORDER_COLOR, C'200,165,165');
   ObjectSetInteger(0, "SFX_CLOSE_NOW", OBJPROP_BACK, false);
   ObjectSetString(0, "SFX_CLOSE_NOW", OBJPROP_TEXT, "CLOSE");

   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_YDISTANCE, y_co);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_XSIZE, bw);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_YSIZE, bh);
   ObjectSetString(0, "SFX_CLOSE_ONLY", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_BACK, false);
   ObjectSetString(0, "SFX_CLOSE_ONLY", OBJPROP_TEXT, "CLOSE ONLY MODE");

   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_YDISTANCE, y_dnd);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_XSIZE, bw);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_YSIZE, bh);
   ObjectSetString(0, "SFX_DND_MODE", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_BACK, false);
   ObjectSetString(0, "SFX_DND_MODE", OBJPROP_TEXT, "DND MODE");

   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_YDISTANCE, y_dyn);
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_XSIZE, bw);
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_YSIZE, bh);
   ObjectSetString(0, "SFX_DYN_LOT_RESET", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_BGCOLOR, C'215,205,170');
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_BORDER_COLOR, C'180,170,140');
   ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_BACK, false);
   ObjectSetString(0, "SFX_DYN_LOT_RESET", OBJPROP_TEXT, "RESET DYN LOT");

   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_YDISTANCE, y_deg);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_XSIZE, bw);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_YSIZE, bh);
   ObjectSetString(0, "SFX_CLEAR_DEGRADED", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_COLOR, C'130,130,130');
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_BGCOLOR, C'225,225,225');
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_BORDER_COLOR, C'200,200,200');
   ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_BACK, false);
   ObjectSetString(0, "SFX_CLEAR_DEGRADED", OBJPROP_TEXT, "DEGRADED: OK");

   ChartRedraw();
}

void DestroyUiButtons()
{
   if(ObjectFind(0, "SFX_OPEN_NOW") >= 0)
      ObjectDelete(0, "SFX_OPEN_NOW");
   if(ObjectFind(0, "SFX_CLOSE_NOW") >= 0)
      ObjectDelete(0, "SFX_CLOSE_NOW");
   if(ObjectFind(0, "SFX_CLOSE_ONLY") >= 0)
      ObjectDelete(0, "SFX_CLOSE_ONLY");
   if(ObjectFind(0, "SFX_DND_MODE") >= 0)
      ObjectDelete(0, "SFX_DND_MODE");
   if(ObjectFind(0, "SFX_DYN_LOT_RESET") >= 0)
      ObjectDelete(0, "SFX_DYN_LOT_RESET");
   if(ObjectFind(0, "SFX_CLEAR_DEGRADED") >= 0)
      ObjectDelete(0, "SFX_CLEAR_DEGRADED");
   DestroyDiffUi();
   ChartRedraw();
}

int OnInit()
{
   MathSrand((int)TimeLocal());
   G_SYMBOL = Symbol();
   G_SYNC_LOG_FILE_WARNED = false;
   G_SLAVE_DUP_CHANNEL_SHUTDOWN = false;
   DiffQuoteMonitorInit();
   DiffInitRoleDefaults();
   DynInitOnAttach();
   SyncClearLogFiles();
   CreateButtons();
   SyncLogSessionStart();
   EventSetMillisecondTimer((uint)MathMax(50, I_LOOP_MS));
   RefreshChartComment();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
   DestroyUiButtons();
   SyncLogSessionStop(reason);
   EventKillTimer();
   ReleaseAllActionLocks("EA_DEINIT");
   CloseClient(G_PEER);
   if(G_SERVER != NULL)
   {
      delete G_SERVER;
      G_SERVER = NULL;
   }
}

void OnTimer()
{
   if(I_ROLE == ROLE_SOURCE_MASTER) MasterLoop();
   else SlaveLoop();
   RefreshChartComment();
}

void OnTick()
{
   if(I_ROLE == ROLE_SOURCE_MASTER)
      G_QMON_MASTER_TICKS++;
   else if(!G_SLAVE_DUP_CHANNEL_SHUTDOWN && G_HANDSHAKE_OK && G_PEER != NULL && G_PEER.IsSocketConnected())
      SlaveSendQuoteStream();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "SFX_OPEN_NOW" && I_ROLE == ROLE_SOURCE_MASTER)
   {
      G_OPEN_SIGNAL_REASON = "UI_BUTTON";
      G_OPEN_SIGNAL_REQUESTED = true;
   }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "SFX_CLOSE_NOW" && I_ROLE == ROLE_SOURCE_MASTER)
   {
      G_CLOSE_SIGNAL_REASON = "UI_BUTTON";
      G_CLOSE_SIGNAL_REQUESTED = true;
   }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "SFX_CLOSE_ONLY" && I_ROLE == ROLE_SOURCE_MASTER)
   {
      ObjectSetInteger(0, "SFX_CLOSE_ONLY", OBJPROP_STATE, false);
      if(I_CLOSE_ONLY_SCHEDULE_MASTER && G_CLOSE_ONLY_SCHEDULE_ACTIVE)
      {
         SyncLog("[SFX-SYNC] close_only manual toggle ignored (schedule active)");
      }
      else
      {
         G_CLOSE_ONLY_MANUAL_ON = !G_CLOSE_ONLY_MANUAL_ON;
         SyncLog(StringFormat("[SFX-SYNC] close_only manual -> %s", G_CLOSE_ONLY_MANUAL_ON ? "ON" : "OFF"));
      }
      ChartRedraw();
   }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "SFX_DND_MODE" && I_ROLE == ROLE_SOURCE_MASTER)
   {
      ObjectSetInteger(0, "SFX_DND_MODE", OBJPROP_STATE, false);
      if(I_DND_SCHEDULE_MASTER && G_DND_SCHEDULE_ACTIVE)
      {
         SyncLog("[SFX-SYNC] dnd manual toggle ignored (schedule active)");
      }
      else
      {
         G_DND_MANUAL_ON = !G_DND_MANUAL_ON;
         SyncLog(StringFormat("[SFX-SYNC] dnd manual -> %s", G_DND_MANUAL_ON ? "ON" : "OFF"));
      }
      ChartRedraw();
   }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "SFX_DYN_LOT_RESET" && I_ROLE == ROLE_SOURCE_MASTER)
   {
      ObjectSetInteger(0, "SFX_DYN_LOT_RESET", OBJPROP_STATE, false);
      DynResetState();
      SyncLog(StringFormat("[DYNLOT] reset by HUD button (lot=%.2f)", G_DYN_LOT));
      ChartRedraw();
   }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "SFX_CLEAR_DEGRADED" && I_ROLE == ROLE_SOURCE_MASTER)
   {
      ObjectSetInteger(0, "SFX_CLEAR_DEGRADED", OBJPROP_STATE, false);
      if(!G_DEGRADED)
         SyncLog("[SFX-SYNC] DEGRADED clear ignored: not degraded");
      else
         TryClearDegraded("UI_BUTTON");
      ChartRedraw();
   }
}

