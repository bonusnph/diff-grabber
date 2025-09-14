//+------------------------------------------------------------------+
//|                                             FXH-Diff-Grabber.mq4 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// =============================
// EA Heading Master–Slave (MT4)
// - Cross-terminal file sync via Common Files
// - Master/Slave roles
// - Open/Close thresholds by points
// - Cooldown, max open pairs
// - Smart Sync (lightweight) and Dry Run mode
// - Display Monitor using labels (no Comment)
// =============================

// -----------------------------
// Inputs
// -----------------------------
enum Role { ROLE_MASTER = 0, ROLE_SLAVE = 1 };
enum ReconcileMode { RECONCILE_CLOSE = 0, RECONCILE_REOPEN = 1 };
enum DryRunHandshakeMode { DRY_NONE = 0, DRY_WRITE_CMD_ONLY = 1, DRY_WRITE_CMD_AND_FAKE_ACK = 2 };
enum MasterSide { SIDE_BUY = 0, SIDE_SELL = 1 };
input Role   input_role                     = ROLE_MASTER;   // Scope: Both — select EA role (ROLE_MASTER or ROLE_SLAVE)
input string input_channel_id               = "A01";         // Scope: Both — channel identifier (must match across peers)
string input_shared_dir               = "";            // Scope: Both — legacy (unused); Common Files is used by default
string input_symbol                   = "";            // Scope: Both — empty uses current chart symbol
bool   input_verbose_journal_logs     = true;          // Scope: Both — emit concise Journal logs for key events

// File logging (per-channel)
bool   input_enable_file_logs         = true;          // Scope: Both — write debug logs to Common Files
int    input_log_retain_hours         = 24;            // Scope: Both — retain logs newer than N hours

// Display monitor width (pixels)
int    input_display_width_pixels      = 520;          // Scope: Both — width of Display Monitor background (pixels)

// Master decision parameters
int    input_slippage_points          = 10;            // Scope: Both — slippage (points)
input MasterSide input_master_side          = SIDE_SELL;     // Scope: Master — master direction (Slave auto-opposite)
input double input_lot                      = 0.01;          // Scope: Both — lot size for orders (applies to Master and Slave)
#define input_lot_master input_lot
#define input_lot_slave  input_lot
input int    input_open_threshold_points    = 30;            // Scope: Master — open threshold (points)
input int    input_close_threshold_points   = 30;            // Scope: Master — close threshold (points)
int    input_open_cooldown_seconds    = 5400;           // Scope: Master — open cooldown after an open
int    input_close_cooldown_seconds   = 300;            // Scope: Master — close cooldown after both sides opened
int    input_max_open_pairs           = 1;             // Scope: Master — max concurrent pairs

// Raw stability check (alternative to averaging - Master only)
bool   input_raw_stability_enabled   = false;         // Scope: Master — enable raw stability check (alternative to averaging)
int    input_raw_stability_ticks     = 3;             // Scope: Master — consecutive stable ticks required
int    input_raw_stability_timeout_ms = 500;          // Scope: Master — max wait time for stability confirmation (ms)
int    input_raw_hysteresis_offset   = 10;           // Scope: Master — hysteresis offset below threshold for reset (points)

// Averaged diff gating (Master-only)
input bool   input_avg_filter_enabled       = false;         // Scope: Master — enable EMA-based averaged diff gating
int    input_avg_period               = 9;             // Scope: Master — EMA period (ticks)
bool   input_use_prefilter_median     = true;          // Scope: Master — apply median pre-filter before EMA
int    input_prefilter_window         = 3;             // Scope: Master — median window (odd 3/5)
bool   input_real_confirm_enabled     = true;          // Scope: Master — require real diff confirmation after averaged trigger
int    input_confirm_ticks            = 2;             // Scope: Master — consecutive ticks to confirm
int    input_confirm_timeout_ms       = 300;           // Scope: Master — max wait for confirmation (ms)
int    input_diff_hysteresis_points   = 0;             // Scope: Master — hysteresis added to thresholds when averaging is enabled (points)
int    input_epsilon_diff_points      = 1;             // Scope: Master — small margin for real confirm (points)
int    input_avg_signal_cooldown_ms   = 400;           // Scope: Master — signal-level cooldown after order (ms)

// Quality guards
int    input_max_spread_points_self   = 50;            // Scope: Master — block if own spread exceeds (points)
int    input_max_spread_points_peer   = 50;            // Scope: Master — check peer spread before opening (points)
int    input_quotes_fresh_ms          = 400;           // Scope: Master — maximum acceptable quote age (ms)
int    input_file_poll_ms             = 5;             // Scope: Master — background file polling cadence (ms)
int    input_magic_number_base        = 900100;        // Scope: Master — magic base per channel/symbol
bool   input_retry_on_requote         = true;          // Scope: Master — retry on requote/off quotes
int    input_max_retries              = 20;             // Scope: Master — max retry attempts

// Smart Sync timeouts
int    input_cmd_expire_ms            = 30000;         // Scope: Master — command expiry (ms)
int    input_ack_timeout_ms           = 10000;          // Scope: Master — ack wait timeout (ms)
int    input_heartbeat_timeout_ms     = 3000;          // Scope: Master — peer heartbeat stale threshold (ms)
ReconcileMode input_reconcile_mode   = RECONCILE_CLOSE;// Scope: Master — desync handling policy (CLOSE/REOPEN)
int    input_reconcile_interval_ms    = 500;           // Scope: Master — reconcile cadence (ms)
int    input_reconcile_freeze_seconds = 8;             // Scope: Master — freeze reconcile after both sides opened (seconds)
int    input_journal_rotate_max_kb    = 256;           // Scope: Master — journal rotation size (KB)

// Dry Run (configured on Master only; Slave uses master's config automatically)
bool   input_dry_run_enabled          = false;         // Scope: Master — enable Dry Run (no real trading)
DryRunHandshakeMode input_dry_run_handshake_mode = DRY_NONE; // Scope: Master — NONE/WRITE_CMD_ONLY/WRITE_CMD_AND_FAKE_ACK
int    input_dry_run_inject_delay_ms  = 0;             // Scope: Master — inject IO delay (ms)
int    input_dry_run_drop_rate_percent= 0;             // Scope: Master — chance to drop cmd/ack writes (%)
int    input_dry_run_override_cmd_expire_ms = 0;       // Scope: Master — override cmd expiry in Dry Run (ms)
bool   input_dry_run_suppress_heartbeat   = false;     // Scope: Master — suppress heartbeat for testing

// Debug UI (Master only)
bool   input_debug_buttons_enabled     = true;        // Scope: Master — show Open/Close test buttons (simulates diffOpen/diffClose)

// Extended controls (Master-only; synced to Slave via config):
double input_min_balance_master_usd    = 0.00;         // Scope: Master — minimum balance required on Master to allow new open
double input_min_balance_slave_usd     = 0.00;         // Scope: Master — minimum balance required on Slave to allow new open
double input_initial_capital_usd       = 0.00;         // Scope: Master — initial capital for profit calculation

// Account Authorization via Google Sheets
string input_auth_sheet_url            = "https://script.google.com/macros/s/AKfycbwu4NytwY2ycRFsonoyEJFJICqT-ooS6Wszb5LTY3PEysF1hxXMEZ0ThgAlzUlCZr1gdg/exec";           // Scope: Both — Google Sheets CSV export URL for account authorization
bool   input_auth_enabled              = true;        // Scope: Both — enable account authorization check

// Scheduled Close Only Mode (Master only)
input bool   input_scheduled_close_only_enabled = true;    // Scope: Master — enable scheduled close only mode
input string input_close_only_start_time        = "03:00";  // Scope: Master — start time for close only mode (HH:mm format)
input string input_close_only_end_time          = "06:00";  // Scope: Master — end time for close only mode (HH:mm format)

// Weekend Close Only (Master only; enforced regardless of input_scheduled_close_only_enabled)
bool   input_sat_close_only_enabled       = true;     // Scope: Master — enable weekend close-only schedule (Sat start -> Mon end)
string input_sat_close_only_start_time    = "00:57";  // Scope: Master — Saturday start time (HH:mm)
string input_mon_close_only_end_time      = "08:03";  // Scope: Master — Monday end time (HH:mm)

// -----------------------------
// Globals
// -----------------------------
string g_symbol;

// Auto-detected initial capital
double g_auto_initial_capital = 0.0;
bool g_auto_capital_detected = false;

// Cached slave balance (to avoid STALE flickering)
double g_cached_slave_balance = 0.0;
bool g_has_slave_balance = false;
// Cached slave equity (to avoid flicker when peer inactive)
double g_cached_slave_equity = 0.0;
bool g_has_slave_equity = false;
int    g_digits;
double g_point;
int    g_magic;
// Peer pricing granularity
int    g_peer_digits = -1;
double g_peer_point = 0.0;
// Anchor time when both sides confirmed open (used for close cooldown)
datetime g_last_pair_both_open_time = 0;

// Price cache
double g_self_bid = 0.0, g_self_ask = 0.0;
double g_peer_bid = 0.0, g_peer_ask = 0.0;
ulong  g_self_quote_ms = 0, g_peer_quote_ms = 0;
ulong  g_peer_hb_ms = 0;
bool   g_peer_alive = false;

// Sequence / command
long   g_seq = 0;
string g_last_cmd_id = "";
datetime g_last_open_time = 0;
// Ack watchdog (slave acknowledgment tracking)
bool    g_waiting_slave_open_ack = false;
string  g_pending_open_cmd_id = "";
ulong   g_pending_open_created_ms = 0;
bool    g_rollback_initiated = false;
// Timestamp of latest slave ACK arrival after open
ulong  g_last_peer_open_ack_ms = 0;
// Slave last-open tracking for robust local reconcile guard (MT4)
ulong  g_slave_last_open_ms = 0;
string g_slave_last_processed_cmd = "";

// Display state
int g_display_last_lines = 0;
// Cached master command snapshot for Slave display
bool   g_have_master_cmd = false;
string g_last_cmd_side = "";     // BUY/SELL of master
double g_last_cmd_lot_master = 0.0;
double g_last_cmd_lot_slave  = 0.0;
ulong  g_last_cmd_seen_ms = 0;
bool   g_have_master_th = false;
int    g_last_cmd_open_th = 0;
int    g_last_cmd_close_th = 0;
// Idempotency guards
string g_last_processed_open_cmd_id = "";
string g_last_processed_close_cmd_id = "";
// Debug: hold open until user presses Close Now
bool   g_debug_hold_open = false;
// Close Only mode: prevent new orders but allow existing orders to close
bool   g_close_only_mode = false;
bool   g_scheduled_close_only_active = false;  // Current state of scheduled close only mode
// Cache for scheduled close only optimization
int    g_cached_start_minutes = -1;
int    g_cached_end_minutes = -1;
string g_cached_start_time = "";
string g_cached_end_time = "";
// Cache for weekend close-only optimization (Sat start -> Mon end)
int    g_cached_sat_start_minutes = -1;
int    g_cached_mon_end_minutes = -1;
string g_cached_sat_start_time = "";
string g_cached_mon_end_time = "";
// Reconcile timer
ulong  g_last_reconcile_ms = 0;
// Master reconcile grace period tracking
ulong  g_master_last_open_ms = 0;
string g_master_last_cmd = "";
// Master-provided dry-run settings
bool  g_master_dry_enabled = false;
int   g_master_dry_mode = 0;
int   g_master_dry_delay_ms = 0;
int   g_master_dry_override_expire_ms = 0;
bool  g_master_dry_suppress_heartbeat = false;
int   g_master_dry_drop = 0;
// Master-provided guards/timeouts
int   g_master_max_spread_self = 0;
int   g_master_max_spread_peer = 0;
int   g_master_quotes_fresh_ms = 1000;
int   g_master_file_poll_ms = 20;
int   g_master_retry_on_requote = 1;
int   g_master_max_retries = 2;
int   g_master_cmd_expire_ms = 3000;
int   g_master_ack_timeout_ms = 2000;
int   g_master_heartbeat_timeout_ms = 3000;
int   g_master_reconcile_mode = (int)RECONCILE_CLOSE;
int   g_master_reconcile_interval_ms = 1000;
// Single-instance guard
bool  g_role_conflict = false;
// Consolidated grace window after any open to avoid premature close/reconcile
ulong g_open_grace_until_ms = 0;
int   g_reconcile_mismatch_streak = 0;
// Pending order comment to carry pair_id
string g_pending_order_comment = "";
string g_pending_pair_id = "";
int   g_prev_self_pairs = 0;
int   g_prev_peer_pairs = 0;
// Logs housekeeping
ulong g_last_log_cleanup_ms = 0;

// Account Authorization globals
bool   g_account_authorized = false;
datetime g_account_expires_at = 0;
ulong  g_last_auth_check_ms = 0;
string g_auth_error_message = "";
bool   g_auth_check_in_progress = false;

// Averaging state (EMA + optional Median pre-filter)
double g_ema_open = 0.0; bool g_ema_open_init = false;
double g_ema_close = 0.0; bool g_ema_close_init = false;
double g_med_buf_open[16]; int g_med_open_count = 0; int g_med_open_idx = 0;
double g_med_buf_close[16]; int g_med_close_count = 0; int g_med_close_idx = 0;

// Real confirm state machines
bool   g_open_pending = false; double g_open_snapshot_avg = 0.0; int g_open_ok_count = 0; ulong g_open_deadline_ms = 0;
bool   g_close_pending = false; double g_close_snapshot_avg = 0.0; int g_close_ok_count = 0; ulong g_close_deadline_ms = 0;

// Signal-level cooldown timestamps
ulong  g_last_avg_open_signal_ms = 0;
ulong  g_last_avg_close_signal_ms = 0;

// Peak diff statistics and histograms (master only)
double g_peak_open_real = 0.0;
double g_peak_close_real = 0.0;
#define DIFF_HIST_MAX_POINTS 300
ulong  g_hist_open_counts[DIFF_HIST_MAX_POINTS+1];
ulong  g_hist_close_counts[DIFF_HIST_MAX_POINTS+1];
int    g_mode_open_index = 0;
ulong  g_mode_open_count = 0;
int    g_mode_close_index = 0;
ulong  g_mode_close_count = 0;
// Weighted suggest parameters/state (master only)
double g_weighted_alpha = 1.5;
int    g_weighted_window = 5;
int    g_weighted_min_count = 5;
int    g_weighted_open_suggest = 0;
int    g_weighted_close_suggest = 0;
ulong  g_last_weighted_suggest_ms = 0;
int    g_weighted_refresh_ms = 1800000; // 30 minutes

// Raw stability state (alternative to averaging)
bool   g_raw_open_pending = false;
int    g_raw_open_stable_count = 0;
ulong  g_raw_open_start_ms = 0;

bool   g_raw_close_pending = false;
int    g_raw_close_stable_count = 0;
ulong  g_raw_close_start_ms = 0;

// In-memory cache: pair_id <-> ticket (current symbol/magic)
string g_cache_pair_ids[];
int    g_cache_tickets[];

int CacheFindIndexByPairId(const string pair_id)
{
   int n = ArraySize(g_cache_pair_ids);
   for(int i=0;i<n;i++){ if(g_cache_pair_ids[i]==pair_id) return i; }
   return -1;
}

int CacheFindIndexByTicket(const int ticket)
{
   int n = ArraySize(g_cache_tickets);
   for(int i=0;i<n;i++){ if(g_cache_tickets[i]==ticket) return i; }
   return -1;
}

void CacheUpsert(const string pair_id, const int ticket)
{
   int idx = CacheFindIndexByPairId(pair_id);
   if(idx>=0){ g_cache_tickets[idx] = ticket; return; }
   int n = ArraySize(g_cache_pair_ids); ArrayResize(g_cache_pair_ids, n+1); ArrayResize(g_cache_tickets, n+1);
   g_cache_pair_ids[n] = pair_id; g_cache_tickets[n] = ticket;
}

void CacheDeleteByPairId(const string pair_id)
{
   int idx = CacheFindIndexByPairId(pair_id); if(idx<0) return;
   int n = ArraySize(g_cache_pair_ids); int last = n-1;
   if(idx!=last){ g_cache_pair_ids[idx]=g_cache_pair_ids[last]; g_cache_tickets[idx]=g_cache_tickets[last]; }
   ArrayResize(g_cache_pair_ids, last); ArrayResize(g_cache_tickets, last);
}

void CacheClearAll(){ ArrayResize(g_cache_pair_ids, 0); ArrayResize(g_cache_tickets, 0); }

void CacheCompactCurrentOrders()
{
   bool keep[]; int n = ArraySize(g_cache_pair_ids); ArrayResize(keep, n); for(int i=0;i<n;i++) keep[i]=false;
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic) continue;
      int idx = CacheFindIndexByTicket(OrderTicket()); if(idx>=0) keep[idx]=true;
   }
   string np[]; int nt[]; int k=0; ArrayResize(np, 0); ArrayResize(nt, 0);
   for(int i=0;i<n;i++)
   {
      if(keep[i])
      {
         ArrayResize(np,k+1); ArrayResize(nt,k+1);
         np[k]=g_cache_pair_ids[i]; nt[k]=g_cache_tickets[i];
         k++;
      }
   }
   // Rebuild target arrays by resizing and copying (avoid direct array assignment)
   ArrayResize(g_cache_pair_ids, 0); ArrayResize(g_cache_tickets, 0);
   int m = ArraySize(np);
   ArrayResize(g_cache_pair_ids, m); ArrayResize(g_cache_tickets, m);
   for(int i=0;i<m;i++) { g_cache_pair_ids[i]=np[i]; g_cache_tickets[i]=nt[i]; }
}

bool DryEnabled(){ return (input_role==ROLE_MASTER) ? input_dry_run_enabled : g_master_dry_enabled; }
int  DryMode(){ return (input_role==ROLE_MASTER) ? (int)input_dry_run_handshake_mode : g_master_dry_mode; }
int  DryDelayMs(){ return (input_role==ROLE_MASTER) ? input_dry_run_inject_delay_ms : g_master_dry_delay_ms; }
int  DryOverrideExpireMs(){ return (input_role==ROLE_MASTER) ? input_dry_run_override_cmd_expire_ms : g_master_dry_override_expire_ms; }
bool DrySuppressHeartbeat(){ return (input_role==ROLE_MASTER) ? input_dry_run_suppress_heartbeat : g_master_dry_suppress_heartbeat; }
int  EffectiveQuotesFreshMs(){ return (input_role==ROLE_MASTER) ? input_quotes_fresh_ms : g_master_quotes_fresh_ms; }
int  EffectiveHeartbeatTimeoutMs(){ return (input_role==ROLE_MASTER) ? input_heartbeat_timeout_ms : g_master_heartbeat_timeout_ms; }

// Paths (Common Files)
// Relative path to Common\Files
string PathChannelRoot()
{
   return StringFormat("EAChannels\\channel_%s\\", input_channel_id);
}

// Absolute path for display only
string PathChannelRootAbs()
{
   string common = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
   string sep = DetectSep(common);
   return common + sep + "Files" + sep + "EAChannels" + sep + "channel_" + input_channel_id + sep;
}

string PathQuotesSelf()
{
   return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "quotes_master.csv" : "quotes_slave.csv");
}

string PathQuotesPeer()
{
   return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "quotes_slave.csv" : "quotes_master.csv");
}

string PathOpenCmd()            { return PathChannelRoot() + "open_cmd.csv"; }
string PathOpenAckSelf()        { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "open_ack_master.csv" : "open_ack_slave.csv"); }
string PathOpenAckPeer()        { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "open_ack_slave.csv" : "open_ack_master.csv"); }
string PathCloseCmd()           { return PathChannelRoot() + "close_cmd.csv"; }
string PathCloseAckSelf()       { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "close_ack_master.csv" : "close_ack_slave.csv"); }
string PathCloseAckPeer()       { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "close_ack_slave.csv" : "close_ack_master.csv"); }
string PathPositionsSelf()      { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "positions_master.csv" : "positions_slave.csv"); }
string PathPositionsPeer()      { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "positions_slave.csv" : "positions_master.csv"); }
string PathHeartbeatSelf()      { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "heartbeat_master.csv" : "heartbeat_slave.csv"); }
string PathHeartbeatPeer()      { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "heartbeat_slave.csv" : "heartbeat_master.csv"); }
string PathDryRunMetrics()      { return PathChannelRoot() + "dryrun_metrics.csv"; }
string PathDryRunDecisions()    { return PathChannelRoot() + "dryrun_decisions.csv"; }
string PathConfigMaster()       { return PathChannelRoot() + "config_master.csv"; }
string PathRoleLock()          { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "lock_master.csv":"lock_slave.csv"); }
string PathPairMapSelf()       { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "pair_map_master.csv":"pair_map_slave.csv"); }
string PathPairMapPeer()       { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "pair_map_slave.csv":"pair_map_master.csv"); }
string PathAccountStatusSelf()  { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "account_master.csv":"account_slave.csv"); }
string PathAccountStatusPeer()  { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "account_slave.csv":"account_master.csv"); }

// -----------------------------
// Logs (daily append + retention)
// -----------------------------
string PathLogsDir() { return PathChannelRoot() + "logs\\"; }

// Daily histogram storage
string PathHistogramDir() { return PathChannelRoot() + "histogram\\"; }

bool HistogramEnsureDir()
{
   return FolderCreate(StringFormat("EAChannels\\channel_%s\\histogram", input_channel_id), FILE_COMMON);
}

string FormatDateYYYYMMDD(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
}

string PathHistogramDailyFileFor(const string yyyymmdd)
{
   return PathHistogramDir() + StringFormat("hist_%s.csv", yyyymmdd);
}

string PathDailyLogFile()
{
   MqlDateTime dt; TimeToStruct(TimeLocal(), dt);
   return PathLogsDir() + StringFormat("log_%04d%02d%02d.csv", dt.year, dt.mon, dt.day);
}

bool LogsEnsureDir()
{
   return FolderCreate(StringFormat("EAChannels\\channel_%s\\logs", input_channel_id), FILE_COMMON);
}

int LogAppendLine(const string line)
{
   if(!input_enable_file_logs) return 0;
   LogsEnsureDir();
   string fp = PathDailyLogFile();
   int h = FileOpen(fp, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      h = FileOpen(fp, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h == INVALID_HANDLE) return GetLastError();
   }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line);
   FileClose(h);
   return 0;
}

string RoleName() { return (input_role==ROLE_MASTER)? "MASTER":"SLAVE"; }

void LogEvent(const string event, const string details)
{
   string logMsg = StringFormat("[%s/%s] %s: %s", RoleName(), input_channel_id, event, details);
   Print(logMsg);
   
   if(!input_enable_file_logs) return;
   string line = StringFormat("%I64u,%s,%s,%s,%s\n", NowMs(), RoleName(), input_channel_id, g_symbol, event + "," + details);
   LogAppendLine(line);
}

void LogsCleanupRetention()
{
   if(!input_enable_file_logs) return;
   if(input_log_retain_hours <= 0) return;
   if((NowMs() - g_last_log_cleanup_ms) < (ulong)60000*30) return; // every 30 minutes
   g_last_log_cleanup_ms = NowMs();
   for(int d=2; d<=31; ++d)
   {
      datetime t = (datetime)(TimeLocal() - (d*24*60*60));
      if(d*24 <= input_log_retain_hours) continue;
      MqlDateTime dt; TimeToStruct(TimeLocal() - (d*24*60*60), dt);
      string oldPath = PathLogsDir() + StringFormat("log_%04d%02d%02d.csv", dt.year, dt.mon, dt.day);
      FileDelete(oldPath, FILE_COMMON);
   }
}

// Upsert pair_id->ticket into our mapping (avoid stale duplicates)
void PairMapSelfUpsert(const string pair_id, const int ticket)
{
   string existing; string out=""; bool replaced=false;
   if(FileReadAll(PathPairMapSelf(), existing))
   {
      string lines[]; int ln = StringSplit(TrimAll(existing), '\n', lines);
      for(int i=0;i<ln;i++)
      {
         string row = TrimAll(lines[i]); if(StringLen(row)==0) continue;
         string cols[]; int cn = StringSplit(row, ',', cols);
         if(cn>=2 && cols[0]==pair_id)
         {
            out += StringFormat("%s,%d\n", pair_id, ticket);
            replaced = true;
         }
         else
         {
            out += row + "\n";
         }
      }
   }
   if(!replaced) out += StringFormat("%s,%d\n", pair_id, ticket);
   FileWriteAllAtomic(PathPairMapSelf(), out);
}

// Remove stale map rows whose tickets are no longer open
void CompactPairMapSelf()
{
   string openSet = ",";
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic) continue;
      openSet += IntegerToString(OrderTicket()) + ",";
   }
   string mapC; if(!FileReadAll(PathPairMapSelf(), mapC)) return;
   string ml[]; int mn=StringSplit(TrimAll(mapC), '\n', ml);
   string seen = ","; string outRev="";
   for(int i=mn-1;i>=0; --i)
   {
      string row = TrimAll(ml[i]); if(StringLen(row)==0) continue;
      string cols[]; int cn=StringSplit(row, ',', cols); if(cn<2) continue;
      string pid = cols[0]; string tStr = cols[1];
      if(StringFind(openSet, ","+tStr+",") < 0) continue; // keep only open tickets
      if(StringFind(seen, ","+pid+",") >= 0) continue; // keep last per pair_id
      seen += pid + ",";
      outRev = row + "\n" + outRev;
   }
   string current = TrimAll(mapC);
   string next = TrimAll(outRev);
   if(current == next) return; // no changes, avoid rewrite
   FileWriteAllAtomic(PathPairMapSelf(), outRev);
}

// Rebuild mapping file strictly from current open orders and in-memory cache
void RebuildPairMapSelfFromCache()
{
   string existing; string lines[]; int ln=0;
   if(FileReadAll(PathPairMapSelf(), existing)) ln = StringSplit(TrimAll(existing), '\n', lines);
   // collect entries
   string pids[]; int tks[]; int cnt=0; ArrayResize(pids,0); ArrayResize(tks,0);
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic) continue;
      int tkt = OrderTicket();
      string pid = "";
      int cidx = CacheFindIndexByTicket(tkt); if(cidx>=0) pid = g_cache_pair_ids[cidx];
      if(pid=="")
      {
         for(int k=0;k<ln;k++)
         {
            string cols[]; int cn = StringSplit(TrimAll(lines[k]), ',', cols);
            if(cn>=2){ if((int)StrToInteger(cols[1])==tkt){ pid = cols[0]; break; } }
         }
      }
      if(pid=="" || pid=="N/A") continue;
      ArrayResize(pids, cnt+1); ArrayResize(tks, cnt+1); pids[cnt]=pid; tks[cnt]=tkt; cnt++;
   }
   // sort by ticket asc for deterministic order
   for(int i=0;i<cnt;i++)
   {
      int minIdx=i; for(int j=i+1;j<cnt;j++){ if(tks[j] < tks[minIdx]) minIdx=j; }
      if(minIdx!=i){ int tt=tks[i]; tks[i]=tks[minIdx]; tks[minIdx]=tt; string tp=pids[i]; pids[i]=pids[minIdx]; pids[minIdx]=tp; }
   }
   string out=""; for(int i=0;i<cnt;i++){ out += StringFormat("%s,%d\n", pids[i], tks[i]); }
   if(TrimAll(existing) == TrimAll(out)) return; // no changes
   FileWriteAllAtomic(PathPairMapSelf(), out);
}

// -----------------------------
// Account Authorization Functions
// -----------------------------

// HTTP request function for MQL4 (using WebRequest)
bool HttpGetRequest(const string url, string &response)
{
   response = "";
   
   // Reset last error
   ResetLastError();
   
   // Prepare headers
   string headers = "User-Agent: MetaTrader EA Authorization Client/1.0\r\n";
   
   // Make HTTP request
   char data[], result[];
   string result_headers;
   
   int res = WebRequest("GET", url, headers, 5000, data, result, result_headers);
   
   if(res == -1)
   {
      int error = GetLastError();
      g_auth_error_message = StringFormat("WebRequest failed: %d", error);
      if(input_verbose_journal_logs)
         Print("[AUTH] WebRequest error: ", error, " - Make sure URL is in allowed list");
      return false;
   }
   
   if(res != 200)
   {
      g_auth_error_message = StringFormat("HTTP error: %d", res);
      if(input_verbose_journal_logs)
         Print("[AUTH] HTTP error: ", res);
      return false;
   }
   
   response = CharArrayToString(result);
   return true;
}

// Parse CSV response and check account authorization
bool ParseAuthorizationData(const string csv_data, const int account_number, datetime &expires_out)
{
   expires_out = 0;
   
   if(StringLen(csv_data) == 0)
   {
      g_auth_error_message = "Empty response from authorization server";
      return false;
   }
   
   string lines[];
   int line_count = StringSplit(csv_data, '\n', lines);
   
   // Skip header line (if exists)
   int start_line = 0;
   if(line_count > 0)
   {
      string first_line = TrimAll(lines[0]);
      if(StringFind(first_line, "account") >= 0 || StringFind(first_line, "Account") >= 0)
         start_line = 1;
   }
   
   for(int i = start_line; i < line_count; i++)
   {
      string line = TrimAll(lines[i]);
      if(StringLen(line) == 0) continue;
      
      string fields[];
      int field_count = StringSplit(line, ',', fields);
      
      if(field_count >= 2)
      {
         int csv_account = (int)StrToInteger(TrimAll(fields[0]));
         if(csv_account == account_number)
         {
            // Found matching account
            if(field_count >= 2)
            {
               string expire_str = TrimAll(fields[1]);
               
               // Parse expiration date (expected format: YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
               if(StringLen(expire_str) >= 10)
               {
                  // Extract date parts
                  string date_part = StringSubstr(expire_str, 0, 10);
                  string date_fields[];
                  if(StringSplit(date_part, '-', date_fields) == 3)
                  {
                     int year = (int)StrToInteger(date_fields[0]);
                     int month = (int)StrToInteger(date_fields[1]);
                     int day = (int)StrToInteger(date_fields[2]);
                     
                     // Create datetime (set to end of day for safety)
                     expires_out = StrToTime(StringFormat("%04d.%02d.%02d 23:59:59", year, month, day));
                     
                     if(expires_out > 0)
                     {
                        return true;
                     }
                  }
               }
               
               // If date parsing failed, try direct StrToTime
               expires_out = StrToTime(expire_str);
               return (expires_out > 0);
            }
            return true; // Account found but no expiration date
         }
      }
   }
   
   g_auth_error_message = StringFormat("Account %d not found in authorization list", account_number);
   return false;
}

// Check account authorization
bool CheckAccountAuthorization()
{
   if(!input_auth_enabled || StringLen(input_auth_sheet_url) == 0)
   {
      g_account_authorized = true;
      g_auth_error_message = "";
      return true;
   }
   
   if(g_auth_check_in_progress)
   {
      if(input_verbose_journal_logs)
         Print("[AUTH] Authorization check already in progress");
      return g_account_authorized;
   }
   
   g_auth_check_in_progress = true;
   
   int account_num = AccountNumber();
   string response;
   
   LogEvent("AUTH_CHECK_START", StringFormat("account=%d", account_num));
   
   if(!HttpGetRequest(input_auth_sheet_url, response))
   {
      g_auth_check_in_progress = false;
      LogEvent("AUTH_CHECK_FAILED", StringFormat("account=%d;error=%s", account_num, g_auth_error_message));
      return false;
   }
   
   datetime expires_at = 0;
   bool authorized = ParseAuthorizationData(response, account_num, expires_at);
   
   if(authorized)
   {
      // Check if account is expired
      datetime now = TimeCurrent();
      if(expires_at > 0 && now > expires_at)
      {
         authorized = false;
         g_auth_error_message = StringFormat("Account %d expired on %s", account_num, TimeToString(expires_at));
      }
      else
      {
         g_account_expires_at = expires_at;
         g_auth_error_message = "";
      }
   }
   
   g_account_authorized = authorized;
   g_last_auth_check_ms = NowMs();
   g_auth_check_in_progress = false;
   
   string status = authorized ? "AUTHORIZED" : "DENIED";
   string expire_info = (expires_at > 0) ? TimeToString(expires_at) : "NO_EXPIRY";
   
   LogEvent("AUTH_CHECK_RESULT", StringFormat("account=%d;status=%s;expires=%s;error=%s", 
            account_num, status, expire_info, g_auth_error_message));
   
   return authorized;
}

// Check if we need to refresh authorization (every 24 hours)
bool ShouldRefreshAuthorization()
{
   if(!input_auth_enabled) return false;
   
   // Check every 24 hours (86400000 ms)
   ulong now = NowMs();
   return (now - g_last_auth_check_ms) >= 86400000;
}

// -----------------------------
// Utils
// -----------------------------
ulong NowMs()
{
   // Approx: TimeLocal in seconds + GetTickCount modulo
   return (ulong)TimeLocal()*1000 + (ulong)GetTickCount() % 1000;
}

string DetectSep(const string base)
{
   return (StringFind(base, "\\")>=0) ? "\\" : "/";
}

bool FolderEnsure()
{
   // Create under Common\Files so all terminals share
   bool ok1 = FolderCreate("EAChannels", FILE_COMMON);
   bool ok2 = FolderCreate(StringFormat("EAChannels\\channel_%s", input_channel_id), FILE_COMMON);
   return (ok1 && ok2);
}

int FileWriteAll(const string relPath, const string content)
{
   // Write text file in Common Files area
   int h = FileOpen(relPath, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return GetLastError();
   FileWriteString(h, content);
   FileClose(h);
   return 0;
}

int FileWriteAllAtomic(const string relPath, const string content)
{
   // Write to tmp then move to target to minimize partial reads
   string tmp = relPath + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return GetLastError();
   FileWriteString(h, content);
   FileClose(h);
   // Try atomic move first; if not supported, fallback to direct write
   bool mv = FileMove(tmp, FILE_COMMON, relPath, FILE_COMMON);
   if(!mv)
   {
      int err = FileWriteAll(relPath, content);
      FileDelete(tmp, FILE_COMMON);
      return err;
   }
   return 0;
}
bool FileReadAll(const string relPath, string &out)
{
   out = "";
   int h = FileOpen(relPath, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;
   int size = (int)FileSize(h);
   out = FileReadString(h, size);
   FileClose(h);
   return true;
}

// Write daily histogram once at end of day (local time), master only
void MaybeWriteDailyHistogram()
{
   if(!(input_role==ROLE_MASTER)) return;
   string today = FormatDateYYYYMMDD(TimeLocal());
   static string last_written_day = "";
   static datetime last_check_ts = 0;
   if(TimeLocal() == last_check_ts) return;
   last_check_ts = TimeLocal();
   if(last_written_day == "") { last_written_day = today; return; }
   if(today != last_written_day)
   {
      string ymd = last_written_day;
      HistogramEnsureDir();
      string path = PathHistogramDailyFileFor(ymd);
      string buf = "type,index,count\n";
      for(int i=0;i<=DIFF_HIST_MAX_POINTS;i++)
      {
         if(g_hist_open_counts[i]>0) buf += StringFormat("open,%d,%I64u\n", i, g_hist_open_counts[i]);
      }
      for(int j=0;j<=DIFF_HIST_MAX_POINTS;j++)
      {
         if(g_hist_close_counts[j]>0) buf += StringFormat("close,%d,%I64u\n", j, g_hist_close_counts[j]);
      }
      buf += StringFormat("summary,peak_open,%.1f\n", g_peak_open_real);
      buf += StringFormat("summary,peak_close,%.1f\n", g_peak_close_real);
      buf += StringFormat("summary,mode_open,%d\n", g_mode_open_index);
      buf += StringFormat("summary,mode_close,%d\n", g_mode_close_index);
      buf += StringFormat("summary,weighted_open,%d\n", g_weighted_open_suggest);
      buf += StringFormat("summary,weighted_close,%d\n", g_weighted_close_suggest);
      FileWriteAllAtomic(path, buf);
      for(int k=0;k<=DIFF_HIST_MAX_POINTS;k++){ g_hist_open_counts[k]=0; g_hist_close_counts[k]=0; }
      g_peak_open_real=0.0; g_peak_close_real=0.0;
      g_mode_open_index=0; g_mode_open_count=0; g_mode_close_index=0; g_mode_close_count=0;
      g_weighted_open_suggest=0; g_weighted_close_suggest=0;
      last_written_day = today;
   }
}

double PointsFromPriceDiff(double priceDiff)
{
   if(g_point <= 0.0) return 0.0;
   return priceDiff / g_point;
}

// Choose coarser point between self and peer for cross-broker consistency
double EffectivePoint()
{
   if(g_peer_point > 0.0)
      return MathMax(g_point, g_peer_point);
   return g_point;
}

bool IsMasterSideBuyEffective()
{
   if(input_role==ROLE_MASTER)
      return (input_master_side==SIDE_BUY);
   // Slave: prefer side from master's command/config if available
   if(g_have_master_cmd || g_have_master_th || g_last_cmd_seen_ms>0)
      return (g_last_cmd_side=="BUY");
   // Fallback to local input if no data yet
   return (input_master_side==SIDE_BUY);
}

void GetMasterSlaveQuotes(double &m_bid, double &m_ask, double &s_bid, double &s_ask)
{
   if(input_role==ROLE_MASTER)
   {
      m_bid = g_self_bid; m_ask = g_self_ask;
      s_bid = g_peer_bid; s_ask = g_peer_ask;
   }
   else
   {
      m_bid = g_peer_bid; m_ask = g_peer_ask;
      s_bid = g_self_bid; s_ask = g_self_ask;
   }
}

// Helper: trim both sides (MT4 has no StringTrim)
string TrimAll(const string src)
{
   string t = src;
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
}

// Find the newest order ticket for current symbol/magic (hedge accounts)
int GetNewestOrderTicket()
{
   int bestTicket = -1; datetime bestTime = 0;
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic) continue;
      datetime t = OrderOpenTime();
      if(t >= bestTime){ bestTime = t; bestTicket = OrderTicket(); }
   }
   return bestTicket;
}

string DryModeToString(DryRunHandshakeMode mode)
{
   switch(mode)
   {
      case DRY_NONE: return "NONE";
      case DRY_WRITE_CMD_ONLY: return "WRITE_CMD_ONLY";
      case DRY_WRITE_CMD_AND_FAKE_ACK: return "WRITE_CMD_AND_FAKE_ACK";
   }
   return "NONE";
}

string ReconcileModeToString(ReconcileMode mode)
{
   switch(mode)
   {
      case RECONCILE_CLOSE: return "CLOSE";
      case RECONCILE_REOPEN: return "REOPEN";
   }
   return "CLOSE";
}

int SpreadPointsSelf()
{
   return (int)MathRound(PointsFromPriceDiff(MathMax(0.0, g_self_ask - g_self_bid)));
}

// Parse time string in HH:mm format to minutes since midnight
int ParseTimeToMinutes(const string timeStr)
{
   int colonPos = StringFind(timeStr, ":");
   if(colonPos < 0 || colonPos >= StringLen(timeStr) - 1) return -1;
   
   string hourStr = StringSubstr(timeStr, 0, colonPos);
   string minStr = StringSubstr(timeStr, colonPos + 1);
   
   int hour = (int)StrToInteger(hourStr);
   int minute = (int)StrToInteger(minStr);
   
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
   
   return hour * 60 + minute;
}

// Saturday helpers
bool IsSaturday()
{
   MqlDateTime dt; TimeToStruct(TimeLocal(), dt);
   return (dt.day_of_week == 6);
}

// Quiet window on Saturday morning: block open/close between 03:00-08:00
bool IsInSaturdayQuietWindow()
{
   if(!IsSaturday()) return false;
   MqlDateTime dt; TimeToStruct(TimeLocal(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = 3*60;  // 03:00
   int endMinutes   = 8*60;  // 08:00
   return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
}

// Check if current time is within scheduled close only period
bool IsInScheduledCloseOnlyPeriod()
{
   if(!input_scheduled_close_only_enabled) return false;
   if(!(input_role==ROLE_MASTER)) return false;
   
   int startMinutes = ParseTimeToMinutes(input_close_only_start_time);
   int endMinutes = ParseTimeToMinutes(input_close_only_end_time);
   
   if(startMinutes < 0 || endMinutes < 0) return false;
   
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   
   if(startMinutes == endMinutes) return false; // Invalid: same start and end time
   
   if(startMinutes < endMinutes)
   {
      // Same day: e.g., 08:00 - 17:00
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   }
   else
   {
      // Cross midnight: e.g., 23:00 - 08:00
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
   }
}

// Update scheduled close only mode state (optimized with caching)
void UpdateScheduledCloseOnlyMode()
{
   if(!(input_role==ROLE_MASTER)) return;
   if(!input_scheduled_close_only_enabled && !input_sat_close_only_enabled) return;
   
   // Update caches for general schedule
   if(input_scheduled_close_only_enabled)
   {
      if(g_cached_start_time != input_close_only_start_time || g_cached_end_time != input_close_only_end_time)
      {
         g_cached_start_time = input_close_only_start_time;
         g_cached_end_time = input_close_only_end_time;
         g_cached_start_minutes = ParseTimeToMinutes(input_close_only_start_time);
         g_cached_end_minutes = ParseTimeToMinutes(input_close_only_end_time);
      }
   }
   // Update caches for weekend schedule (Sat start -> Mon end)
   if(input_sat_close_only_enabled)
   {
      if(g_cached_sat_start_time != input_sat_close_only_start_time || g_cached_mon_end_time != input_mon_close_only_end_time)
      {
         g_cached_sat_start_time = input_sat_close_only_start_time;
         g_cached_mon_end_time = input_mon_close_only_end_time;
         g_cached_sat_start_minutes = ParseTimeToMinutes(input_sat_close_only_start_time);
         g_cached_mon_end_minutes = ParseTimeToMinutes(input_mon_close_only_end_time);
      }
   }
   
   // Compute activity
   MqlDateTime dt; TimeToStruct(TimeLocal(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   bool wasActive = g_scheduled_close_only_active;
   
   bool generalActive = false;
   if(input_scheduled_close_only_enabled && g_cached_start_minutes >= 0 && g_cached_end_minutes >= 0)
   {
      if(g_cached_start_minutes == g_cached_end_minutes) generalActive = false;
      else if(g_cached_start_minutes < g_cached_end_minutes)
         generalActive = (currentMinutes >= g_cached_start_minutes && currentMinutes < g_cached_end_minutes);
      else
         generalActive = (currentMinutes >= g_cached_start_minutes || currentMinutes < g_cached_end_minutes);
   }
   // Weekend active window: from Saturday start time through all Sunday until Monday end time
   bool weekendActive = false;
   if(input_sat_close_only_enabled && g_cached_sat_start_minutes >= 0 && g_cached_mon_end_minutes >= 0)
   {
      int dow = dt.day_of_week; // 0=Sunday ... 6=Saturday (MT4)
      if(dow == 6)
      {
         // Saturday: active from start time onward
         if(g_cached_sat_start_minutes == g_cached_mon_end_minutes) weekendActive = false;
         else if(g_cached_sat_start_minutes < g_cached_mon_end_minutes)
            weekendActive = (currentMinutes >= g_cached_sat_start_minutes);
         else
            weekendActive = (currentMinutes >= g_cached_sat_start_minutes);
      }
      else if(dow == 0)
      {
         // Sunday: always active entire day
         weekendActive = true;
      }
      else if(dow == 1)
      {
         // Monday: active until end time
         if(g_cached_sat_start_minutes == g_cached_mon_end_minutes) weekendActive = false;
         else if(g_cached_sat_start_minutes < g_cached_mon_end_minutes)
            weekendActive = (currentMinutes < g_cached_mon_end_minutes);
         else
            weekendActive = (currentMinutes < g_cached_mon_end_minutes);
      }
   }
   
   g_scheduled_close_only_active = (generalActive || weekendActive);
   if(g_scheduled_close_only_active)
   {
      g_close_only_mode = true;
   }
   else
   {
      int graceMin = 5;
      bool inGraceGeneral=false, inGraceWeekend=false;
      if(input_scheduled_close_only_enabled && g_cached_start_minutes >= 0 && g_cached_end_minutes >= 0)
      {
         int endPlus = (g_cached_end_minutes + graceMin) % 1440;
         if(g_cached_start_minutes < g_cached_end_minutes)
            inGraceGeneral = (currentMinutes >= g_cached_end_minutes && currentMinutes < (g_cached_end_minutes + graceMin));
         else if(g_cached_start_minutes > g_cached_end_minutes)
            inGraceGeneral = (currentMinutes >= g_cached_end_minutes || currentMinutes < endPlus);
      }
      // Grace: after Monday end time only
      if(input_sat_close_only_enabled && dt.day_of_week == 1 && g_cached_mon_end_minutes >= 0)
      {
         int endPlusM = (g_cached_mon_end_minutes + graceMin) % 1440;
         inGraceWeekend = (currentMinutes >= g_cached_mon_end_minutes && currentMinutes < endPlusM);
      }
      if(inGraceGeneral || inGraceWeekend)
      {
         g_close_only_mode = false;
      }
   }
   
   if(wasActive != g_scheduled_close_only_active)
   {
      LogEvent("SCHEDULED_CLOSE_ONLY", StringFormat("active=%s;general=%s-%s;weekend=%s-%s;current=%02d:%02d;mode=%s",
               g_scheduled_close_only_active?"true":"false",
               input_close_only_start_time, input_close_only_end_time,
               input_sat_close_only_start_time, input_mon_close_only_end_time,
               dt.hour, dt.min, g_close_only_mode?"ON":"OFF"));
   }
}

// Check if user can manually toggle close only mode (not during scheduled period)
bool CanUserToggleCloseOnly()
{
   if(!input_scheduled_close_only_enabled && !input_sat_close_only_enabled) return true;
   return !g_scheduled_close_only_active;
}

// -----------------------------
// Trading helpers (MT4)
// -----------------------------
int SlippageToDigitsPoints()
{
   return input_slippage_points;
}

int CountOpenPairs()
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()==g_symbol && OrderMagicNumber()==g_magic)
         count++;
   }
   return count;
}

bool PlaceOrderMaster(const bool isBuy, const double lots, int &ticket_out, double &price_out)
{
   ticket_out = -1;
   price_out = 0.0;
   int retries = input_retry_on_requote ? MathMax(1, input_max_retries) : 1;
   for(int r=0; r<retries; ++r)
   {
      RefreshRates();
      int slippage = SlippageToDigitsPoints();
      string cmt = ""; // do not expose pairing info in comment
      if(isBuy)
      {
         price_out = Ask;
         ticket_out = OrderSend(g_symbol, OP_BUY, lots, price_out, slippage, 0, 0, cmt, g_magic, 0, clrGreen);
      }
      else
      {
         price_out = Bid;
         ticket_out = OrderSend(g_symbol, OP_SELL, lots, price_out, slippage, 0, 0, cmt, g_magic, 0, clrRed);
      }
      if(ticket_out>0)
         return true;
      int err = GetLastError();
      if(err==ERR_OFF_QUOTES || err==ERR_REQUOTE)
      {
         Sleep(100);
         continue;
      }
      return false;
   }
   return false;
}

bool CloseAllByMagic()
{
   bool ok = true;
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic)
         continue;
      double price = (OrderType()==OP_BUY) ? Bid : Ask;
      int slippage = SlippageToDigitsPoints();
      if(!OrderClose(OrderTicket(), OrderLots(), price, slippage, clrYellow))
         ok = false;
   }
   return ok;
}

bool CloseSelfByPairId(const string pair_id)
{
   // 1) Try in-memory cache first
   int cidx = CacheFindIndexByPairId(pair_id);
   if(cidx>=0)
   {
      int t = g_cache_tickets[cidx];
      if(t>0 && OrderSelect(t, SELECT_BY_TICKET))
      {
         if(OrderSymbol()==g_symbol && OrderMagicNumber()==g_magic)
         {
            double price = (OrderType()==OP_BUY) ? Bid : Ask;
            int slippage = SlippageToDigitsPoints();
            return OrderClose(OrderTicket(), OrderLots(), price, slippage, clrYellow);
         }
      }
   }
   // 2) Try map file pair_id -> ticket
   string content; if(FileReadAll(PathPairMapSelf(), content))
   {
      string lines[]; int ln = StringSplit(TrimAll(content), '\n', lines);
      for(int i=0;i<ln;i++)
      {
         string cols[]; int cn = StringSplit(TrimAll(lines[i]), ',', cols);
         if(cn<2) continue; if(cols[0] != pair_id) continue;
         int t = (int)StrToInteger(cols[1]); if(t<=0) continue;
         if(!OrderSelect(t, SELECT_BY_TICKET)) continue;
         if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic) continue;
         double price = (OrderType()==OP_BUY) ? Bid : Ask;
         int slippage = SlippageToDigitsPoints();
         return OrderClose(OrderTicket(), OrderLots(), price, slippage, clrYellow);
      }
   }
   // 3) Fallback: scan positions_self.csv for ticket with this pair_id
   string posC; if(FileReadAll(PathPositionsSelf(), posC))
   {
      string rows[]; int rn = StringSplit(TrimAll(posC), '\n', rows);
      for(int i=0;i<rn;i++)
      {
         string cols[]; int cn = StringSplit(TrimAll(rows[i]), ',', cols);
         if(cn<2) continue; if(cols[0]!=pair_id) continue;
         int t = (int)StrToInteger(cols[1]); if(t<=0) continue;
         if(!OrderSelect(t, SELECT_BY_TICKET)) continue;
         if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic) continue;
         double price = (OrderType()==OP_BUY) ? Bid : Ask;
         int slippage = SlippageToDigitsPoints();
         return OrderClose(OrderTicket(), OrderLots(), price, slippage, clrYellow);
      }
   }
   return false;
}

void PairMapSelfDeleteByPairId(const string pair_id)
{
   string existing; string out="";
   if(FileReadAll(PathPairMapSelf(), existing))
   {
      string lines[]; int ln = StringSplit(TrimAll(existing), '\n', lines);
      for(int i=0;i<ln;i++)
      {
         string row = TrimAll(lines[i]); if(StringLen(row)==0) continue;
         string cols[]; int cn = StringSplit(row, ',', cols);
         if(cn>=2 && cols[0]==pair_id) continue;
         out += row + "\n";
      }
      FileWriteAllAtomic(PathPairMapSelf(), out);
   }
}

void PairMapSelfClearAll(){ FileWriteAllAtomic(PathPairMapSelf(), ""); }

// Removed CloseOneByMagic in favor of CloseSelfByPairId + mapping

int PeerOpenCount()
{
   string s; if(!FileReadAll(PathPositionsPeer(), s)) return -1;
   string rows[]; int n = StringSplit(TrimAll(s), '\n', rows);
   int count=0;
   for(int i=0;i<n;i++)
   {
      string line = TrimAll(rows[i]); if(StringLen(line)==0) continue;
      string c[]; int cn = StringSplit(line, ',', c);
      if(cn>=2 && c[0]!="" && c[0]!="N/A") count++;
   }
   return count;
}

void MasterReconcilePositions()
{
   if(!(input_role==ROLE_MASTER)) return;
   if(!g_peer_alive) return; // require peer alive to avoid acting on stale files
   if(IsInSaturdayQuietWindow()) return; // Saturday quiet window: skip reconcile
   
   // CRITICAL: Skip reconcile during grace period to prevent immediate close after open
   if(NowMs() < g_open_grace_until_ms) { 
      int selfNowTmp = CountOpenPairs(); 
      int peerNowTmp = PeerOpenCount(); 
      if(peerNowTmp<0) return; 
      bool manualDropTmp = (peerNowTmp < g_prev_peer_pairs) && (selfNowTmp > 0);
      if(manualDropTmp)
      {
         LogEvent("RECONCILE_PEER_MANUAL_CLOSE", StringFormat("peer_closed_manually;self=%d;peer=%d", selfNowTmp, peerNowTmp));
         LogEvent("CLOSE_TRIGGER", StringFormat("source=RECONCILE_PEER_MANUAL;self=%d;peer=%d", selfNowTmp, peerNowTmp));
         string cmd_id0 = NewCmdId(); ulong created_ms0 = NowMs(); int expire_ms0 = input_cmd_expire_ms;
         string line0 = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id0, (long)g_seq, "N/A", "CLOSE", created_ms0, expire_ms0);
         FileWriteAllAtomic(PathCloseCmd(), line0);
         LogEvent("RECONCILE_MASTER_FOLLOW_CLOSE", StringFormat("cmd_id=%s;reason=PEER_MANUAL_CLOSE", cmd_id0));
         if(DryEnabled()){
            if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf0 = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id0, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf0);} 
            g_prev_self_pairs=selfNowTmp; g_prev_peer_pairs=peerNowTmp; 
            return; 
         }
         bool ok0 = CloseAllByMagic(); CompactPairMapSelf(); WritePositions(); 
         string ack20 = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id0, (long)g_seq, "N/A", ok0?1:0, ok0?0:GetLastError()); 
         FileWriteAll(PathCloseAckSelf(), ack20);
         g_prev_self_pairs=selfNowTmp; g_prev_peer_pairs=peerNowTmp; 
         return;
      }
      g_prev_self_pairs = selfNowTmp; 
      g_prev_peer_pairs = peerNowTmp; 
      return; 
   }
   
   // ENHANCED: Add grace period after master opens order to prevent immediate reconcile
   if(g_last_cmd_id != g_master_last_cmd && g_last_cmd_id != "")
   {
      g_master_last_open_ms = NowMs();
      g_master_last_cmd = g_last_cmd_id;
      LogEvent("RECONCILE_GRACE_START", StringFormat("cmd_id=%s;freeze_seconds=%d", g_last_cmd_id, input_reconcile_freeze_seconds));
   }
   // Skip reconcile after master sends open command
   ulong grace_elapsed = (g_master_last_open_ms > 0) ? (NowMs() - g_master_last_open_ms) : 999999;
   ulong grace_limit = (ulong)(input_reconcile_freeze_seconds * 1000);
   if(g_master_last_open_ms > 0 && grace_elapsed < grace_limit) 
   {
      int selfNowTmp2 = CountOpenPairs(); 
      int peerNowTmp2 = PeerOpenCount(); 
      if(peerNowTmp2<0) return; 
      bool manualDropTmp2 = (peerNowTmp2 < g_prev_peer_pairs) && (selfNowTmp2 > 0);
      if(manualDropTmp2)
      {
         LogEvent("RECONCILE_PEER_MANUAL_CLOSE", StringFormat("peer_closed_manually;self=%d;peer=%d", selfNowTmp2, peerNowTmp2));
         LogEvent("CLOSE_TRIGGER", StringFormat("source=RECONCILE_PEER_MANUAL;self=%d;peer=%d", selfNowTmp2, peerNowTmp2));
         string cmd_id1 = NewCmdId(); ulong created_ms1 = NowMs(); int expire_ms1 = input_cmd_expire_ms;
         string line1 = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id1, (long)g_seq, "N/A", "CLOSE", created_ms1, expire_ms1);
         FileWriteAllAtomic(PathCloseCmd(), line1);
         LogEvent("RECONCILE_MASTER_FOLLOW_CLOSE", StringFormat("cmd_id=%s;reason=PEER_MANUAL_CLOSE", cmd_id1));
         if(DryEnabled()){
            if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf1 = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id1, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf1);} 
            g_prev_self_pairs=selfNowTmp2; g_prev_peer_pairs=peerNowTmp2; 
            return; 
         }
         bool ok1 = CloseAllByMagic(); CompactPairMapSelf(); WritePositions(); 
         string ack21 = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id1, (long)g_seq, "N/A", ok1?1:0, ok1?0:GetLastError()); 
         FileWriteAll(PathCloseAckSelf(), ack21);
         g_prev_self_pairs=selfNowTmp2; g_prev_peer_pairs=peerNowTmp2; 
         return;
      }
      LogEvent("RECONCILE_GRACE_SKIP", StringFormat("elapsed_ms=%I64u;limit_ms=%I64u;remaining_ms=%I64u", 
               grace_elapsed, grace_limit, grace_limit - grace_elapsed));
      g_prev_self_pairs = selfNowTmp2; 
      g_prev_peer_pairs = peerNowTmp2; 
      return;
   }
   
   // Keep mapping/positions fresh before diffing
   RebuildPairMapSelfFromCache();
   WritePositions();
   // Compute counts early to detect manual drop
   int selfNow = CountOpenPairs(); int peerNow = PeerOpenCount(); if(peerNow<0) return;
   // Freeze reconcile briefly after both sides opened to avoid post-open thrash
   if(g_last_pair_both_open_time>0)
   {
      int el = (int)(TimeCurrent() - g_last_pair_both_open_time);
      if(el < input_reconcile_freeze_seconds) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
   }
     bool manualDrop = (selfNow < g_prev_self_pairs) || (peerNow < g_prev_peer_pairs);
  if(manualDrop) LogEvent("RECONCILE_MANUAL_DROP", StringFormat("selfNow=%d;peerNow=%d;prevSelf=%d;prevPeer=%d", selfNow, peerNow, g_prev_self_pairs, g_prev_peer_pairs));
  
  // Handle manual drops immediately - if peer closed manually, master should close too
  if(manualDrop && peerNow < g_prev_peer_pairs && selfNow > 0)
  {
     LogEvent("RECONCILE_PEER_MANUAL_CLOSE", StringFormat("peer_closed_manually;self=%d;peer=%d", selfNow, peerNow));
     LogEvent("CLOSE_TRIGGER", StringFormat("source=RECONCILE_PEER_MANUAL;self=%d;peer=%d", selfNow, peerNow));
     string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
     string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
     FileWriteAllAtomic(PathCloseCmd(), line);
     LogEvent("RECONCILE_MASTER_FOLLOW_CLOSE", StringFormat("cmd_id=%s;reason=PEER_MANUAL_CLOSE", cmd_id));
     if(DryEnabled()){ if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf);} g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
     bool ok = CloseAllByMagic(); CompactPairMapSelf(); 
     string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:GetLastError()); 
     FileWriteAll(PathCloseAckSelf(), ack);
     g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; 
     return;
  }
  
  // Skip entirely while waiting for slave ACK within timeout window (unless manual drop)
  if(!manualDrop && g_waiting_slave_open_ack && (NowMs()-g_pending_open_created_ms) <= (ulong)input_ack_timeout_ms) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
  // Grace period just after peer ack open (unless manual drop)
  if(!manualDrop && g_last_peer_open_ack_ms>0 && (NowMs()-g_last_peer_open_ack_ms) < (ulong)input_ack_timeout_ms) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
   // In debug hold, reconcile only when manual close detected (pair count drop)
   if(input_debug_buttons_enabled && g_debug_hold_open)
   {
      if(!manualDrop) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
   }
   // Enhanced throttling: increase minimum interval to 3 seconds
   ulong min_reconcile_interval = MathMax((ulong)input_reconcile_interval_ms, 3000);
   if((NowMs()-g_last_reconcile_ms) < min_reconcile_interval) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
   g_last_reconcile_ms = NowMs();
   int self = selfNow; int peer = peerNow;
   // If within ack window and count differs by only 1, skip (normal in-flight open) unless manual drop
   int diff = (self>peer)? (self-peer) : (peer-self);
   if(!manualDrop && diff<=1 && (NowMs()-g_pending_open_created_ms) <= (ulong)input_ack_timeout_ms) { g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }

   // If exactly one mismatch, fix the specific side only (pair-wise reconcile)
   if(diff==1)
   {
      if(self < peer)
      {
         // ENHANCED: Add aggressive throttling to prevent reconcile loop
         static ulong last_peer_close_ms = 0;
         if((NowMs() - last_peer_close_ms) < 5000) { // 5 second throttle
            g_prev_self_pairs=self; g_prev_peer_pairs=peer; 
            return;
         }
         
         // CRITICAL: Skip pair-wise reconcile during grace period after master opens
         ulong grace_elapsed_pair = (g_master_last_open_ms > 0) ? (NowMs() - g_master_last_open_ms) : 999999;
         ulong grace_limit_pair = (ulong)(input_reconcile_freeze_seconds * 1000);
         if(g_master_last_open_ms > 0 && grace_elapsed_pair < grace_limit_pair) 
         {
            LogEvent("RECONCILE_PAIRWISE_GRACE_SKIP", StringFormat("elapsed_ms=%I64u;limit_ms=%I64u", grace_elapsed_pair, grace_limit_pair));
            g_prev_self_pairs=self; g_prev_peer_pairs=peer; 
            return;
         }
         
         last_peer_close_ms = NowMs();
         
         // Pick pair_id from peer positions that does not exist on self; fallback via peer map by ticket
         string peerPos, selfPos; string pRows[]; string sRows[]; int pn=0, sn=0;
         if(FileReadAll(PathPositionsPeer(), peerPos)) pn = StringSplit(TrimAll(peerPos), '\n', pRows);
         if(FileReadAll(PathPositionsSelf(), selfPos)) sn = StringSplit(TrimAll(selfPos), '\n', sRows);
         string pickPair="";
         for(int i=0;i<pn && pickPair=="";++i){ string cols[]; int cn=StringSplit(TrimAll(pRows[i]), ',', cols); if(cn>=1){ string pid=cols[0]; bool found=false; for(int j=0;j<sn;++j){ string c2[]; int c2n=StringSplit(TrimAll(sRows[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } } if(!found && pid!="N/A" && pid!="") pickPair=pid; } }
         if(pickPair=="")
         {
            // Fallback: resolve pair_id via ticket from peer positions and peer map
            for(int i=0;i<pn && pickPair=="";++i)
            {
               string cols[]; int cn=StringSplit(TrimAll(pRows[i]), ',', cols);
               if(cn>=2)
               {
                  string tStr=cols[1]; string mapC;
                  if(FileReadAll(PathPairMapPeer(), mapC))
                  {
                     string ml[]; int mn=StringSplit(TrimAll(mapC), '\n', ml);
                     for(int m=0;m<mn && pickPair=="";++m)
                     {
                        string mc[]; int mcn=StringSplit(TrimAll(ml[m]), ',', mc);
                        if(mcn>=2 && mc[1]==tStr && mc[0]!="" && mc[0]!="N/A") pickPair=mc[0];
                     }
                  }
               }
            }
         }
         if(pickPair=="")
         {
            // simple peer-first fallback
            for(int i=0;i<pn;++i){ string cols[]; int cn=StringSplit(TrimAll(pRows[i]), ',', cols); if(cn>=1 && cols[0]!="N/A" && cols[0]!=""){ pickPair=cols[0]; break; } }
         }
         if(pickPair=="") { g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
         LogEvent("CLOSE_TRIGGER", StringFormat("source=RECONCILE_PEER_EXTRA;pair_id=%s", pickPair));
         string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
         // Replace CLOSE_ONE with conservative CLOSE (close all) to avoid pair-wise race
         LogEvent("RECONCILE_PAIRWISE_TO_CLOSE_ALL", StringFormat("peer_extra_pair=%s", pickPair));
         string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
         FileWriteAllAtomic(PathCloseCmd(), line);
         if(DryEnabled() && DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf);} 
         g_prev_self_pairs=self; g_prev_peer_pairs=peer; return;
      }
      else // self > peer
      {
         // Pick pair_id from self positions that does not exist on peer; fallback via self map by ticket
         string peerPos, selfPos; string pRows[]; string sRows[]; int pn=0, sn=0;
         if(FileReadAll(PathPositionsPeer(), peerPos)) pn = StringSplit(TrimAll(peerPos), '\n', pRows);
         if(FileReadAll(PathPositionsSelf(), selfPos)) sn = StringSplit(TrimAll(selfPos), '\n', sRows);
         string pickPair="";
         for(int i=0;i<sn && pickPair=="";++i){ string cols[]; int cn=StringSplit(TrimAll(sRows[i]), ',', cols); if(cn>=1){ string pid=cols[0]; bool found=false; for(int j=0;j<pn;++j){ string c2[]; int c2n=StringSplit(TrimAll(pRows[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } } if(!found && pid!="N/A" && pid!="") pickPair=pid; } }
         if(pickPair=="")
         {
            for(int i=0;i<sn && pickPair=="";++i)
            {
               string cols[]; int cn=StringSplit(TrimAll(sRows[i]), ',', cols);
               if(cn>=2)
               {
                  string tStr=cols[1]; string mapC;
                  if(FileReadAll(PathPairMapSelf(), mapC))
                  {
                     string ml[]; int mn=StringSplit(TrimAll(mapC), '\n', ml);
                     for(int m=0;m<mn && pickPair=="";++m)
                     {
                        string mc[]; int mcn=StringSplit(TrimAll(ml[m]), ',', mc);
                        if(mcn>=2 && mc[1]==tStr && mc[0]!="" && mc[0]!="N/A") pickPair=mc[0];
                     }
                  }
               }
            }
         }
         // Additional fallback: compare pair_map_self vs pair_map_peer to find pair_id missing on peer
         if(pickPair=="")
         {
            string selfMap, peerMap; if(FileReadAll(PathPairMapSelf(), selfMap) && FileReadAll(PathPairMapPeer(), peerMap))
            {
               string sLines[], pLines[]; int sn2=StringSplit(TrimAll(selfMap), '\n', sLines); int pn2=StringSplit(TrimAll(peerMap), '\n', pLines);
               for(int si=0; si<sn2 && pickPair==""; ++si)
               {
                  string sc[]; int scn=StringSplit(TrimAll(sLines[si]), ',', sc); if(scn<1) continue; string pid=sc[0]; if(pid==""||pid=="N/A") continue;
                  bool onPeer=false; for(int pj=0; pj<pn2; ++pj){ string pc[]; int pcn=StringSplit(TrimAll(pLines[pj]), ',', pc); if(pcn>=1 && pc[0]==pid){ onPeer=true; break; } }
                  if(!onPeer) pickPair=pid;
               }
            }
         }
         if(pickPair=="") { g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
         bool ok1 = CloseSelfByPairId(pickPair);
         if(ok1){ PairMapSelfDeleteByPairId(pickPair); WritePositions(); CompactPairMapSelf(); }
         string cmd_id = NewCmdId(); string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok1?1:0, ok1?0:GetLastError()); FileWriteAll(PathCloseAckSelf(), ack);
         LogEvent("RECONCILE_CLOSE_SELF_EXTRA", StringFormat("pair_id=%s;ok=%d;err=%d", pickPair, ok1?1:0, ok1?0:GetLastError()));
         g_prev_self_pairs=self; g_prev_peer_pairs=peer; return;
      }
   }
   if(self==peer) { g_reconcile_mismatch_streak = 0; g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
   // Require mismatch to persist across multiple checks to avoid transient closes
   g_reconcile_mismatch_streak++;
   if(g_reconcile_mismatch_streak < 2) { g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
   g_reconcile_mismatch_streak = 0;
   LogEvent("CLOSE_TRIGGER", StringFormat("source=RECONCILE_FORCE_BOTH;self=%d;peer=%d", self, peer));
   string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
   FileWriteAllAtomic(PathCloseCmd(), line);
   LogEvent("RECONCILE_FORCE_BOTH_CLOSE", StringFormat("cmd_id=%s;self=%d;peer=%d", cmd_id, self, peer));
   if(DryEnabled()){ if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf);} g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
   bool ok = CloseAllByMagic(); CompactPairMapSelf(); WritePositions(); string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:GetLastError()); FileWriteAll(PathCloseAckSelf(), ack);
}

// Slave-side self-heal: if self has more pairs than peer, close the extra pair(s) locally
void SlaveLocalReconcile()
{
   if(input_role==ROLE_MASTER) return;
   if(!g_peer_alive) return;
   if(IsInSaturdayQuietWindow()) return; // Saturday quiet window: skip local reconcile
   
   // CRITICAL: Add dynamic grace period to prevent immediate close after slave opens order
   if(g_last_processed_open_cmd_id != g_slave_last_processed_cmd && g_last_processed_open_cmd_id != "")
   {
      g_slave_last_open_ms = NowMs();
      g_slave_last_processed_cmd = g_last_processed_open_cmd_id;
   }
   // Dynamic guard window: max(ack_timeout+2s, close_cooldown, 15s)
   int guard_ack_ms = (g_master_ack_timeout_ms>0 ? g_master_ack_timeout_ms : input_ack_timeout_ms) + 2000;
   int guard_close_ms = (g_master_close_cooldown_seconds>0 ? g_master_close_cooldown_seconds*1000 : input_close_cooldown_seconds*1000);
   int guard_ms = (int)MathMax((double)guard_ack_ms, (double)MathMax(guard_close_ms, 15000));
   if(g_slave_last_open_ms > 0 && (NowMs() - g_slave_last_open_ms) < (ulong)guard_ms) return;
   
   if((NowMs()-g_last_reconcile_ms) < (ulong)EffectiveHeartbeatTimeoutMs()/2) return; // light throttle
   g_last_reconcile_ms = NowMs();
   int self = CountOpenPairs(); int peer = PeerOpenCount(); if(peer<0) return;
   if(self <= peer) return;
   string peerPos, selfPos; string pRows[]; string sRows[]; int pn=0, sn=0;
   if(FileReadAll(PathPositionsPeer(), peerPos)) pn = StringSplit(TrimAll(peerPos), '\n', pRows);
   if(FileReadAll(PathPositionsSelf(), selfPos)) sn = StringSplit(TrimAll(selfPos), '\n', sRows);
   string pickPair="";
   for(int i=0;i<sn && pickPair=="";++i)
   {
      string cols[]; int cn=StringSplit(TrimAll(sRows[i]), ',', cols); if(cn>=1)
      {
         string pid=cols[0]; bool found=false; for(int j=0;j<pn;++j){ string c2[]; int c2n=StringSplit(TrimAll(pRows[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } }
         if(!found && pid!="N/A" && pid!="") pickPair=pid;
      }
   }
   if(pickPair=="")
   {
      for(int i=0;i<sn && pickPair=="";++i)
      {
         string cols[]; int cn=StringSplit(TrimAll(sRows[i]), ',', cols); if(cn>=2)
         {
            string tStr=cols[1]; string mapContent; if(FileReadAll(PathPairMapSelf(), mapContent))
            {
               string ml[]; int mn=StringSplit(TrimAll(mapContent), '\n', ml);
               for(int m=0;m<mn && pickPair=="";++m){ string mc[]; int mcn=StringSplit(TrimAll(ml[m]), ',', mc); if(mcn>=2){ if(mc[1]==tStr && mc[0]!="" && mc[0]!="N/A") pickPair=mc[0]; } }
            }
         }
      }
   }
   if(pickPair=="") return;
   bool ok1 = CloseSelfByPairId(pickPair);
   if(ok1){ PairMapSelfDeleteByPairId(pickPair); WritePositions(); CompactPairMapSelf(); }

   // Try to close any other extras in the same cycle
   int self2 = CountOpenPairs(); int peer2 = PeerOpenCount(); if(peer2>=0 && self2>peer2)
   {
      string peerPos2, selfPos2; string pRows2[]; string sRows2[]; int pn2=0, sn2=0;
      if(FileReadAll(PathPositionsPeer(), peerPos2)) pn2 = StringSplit(TrimAll(peerPos2), '\n', pRows2);
      if(FileReadAll(PathPositionsSelf(), selfPos2)) sn2 = StringSplit(TrimAll(selfPos2), '\n', sRows2);
      for(int i=0;i<sn2; ++i)
      {
         string c[]; int cn=StringSplit(TrimAll(sRows2[i]), ',', c); if(cn<1) continue; string pid=c[0]; if(pid==""||pid=="N/A") continue;
         bool found=false; for(int j=0;j<pn2;++j){ string c2[]; int c2n=StringSplit(TrimAll(pRows2[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } }
         if(!found)
         {
            if(CloseSelfByPairId(pid)){ PairMapSelfDeleteByPairId(pid); WritePositions(); CompactPairMapSelf(); }
         }
      }
   }
}

// -----------------------------
// Protocol helpers
// -----------------------------
string NewCmdId()
{
   g_seq++;
   return StringFormat("%s_%I64u_%u", input_channel_id, (long)TimeLocal(), (uint)g_seq);
}

void WriteHeartbeat()
{
   if(DrySuppressHeartbeat()) return;
   // Include basic account metrics so peer can read balance
   double bal = AccountBalance(); double eq = AccountEquity();
   string line = StringFormat("%I64u,%d,%d,%d,%s,%.2f,%.2f,%d,%.10f\n", NowMs(), __MQLBUILD__, AccountNumber(), g_magic, "1.0.0", bal, eq, g_digits, g_point);
   FileWriteAll(PathHeartbeatSelf(), line);

   // Also write a compact account status file
   string acc = StringFormat("1,%.2f,%.2f,%I64u\n", bal, eq, NowMs());
   FileWriteAll(PathAccountStatusSelf(), acc);
}

void WriteMasterConfig()
{
   if(!(input_role==ROLE_MASTER)) return;
   // version,symbol,master_side,lot_master,lot_slave,open_th,close_th,cooldown,max_pairs,updated_ms,dry_enabled,dry_mode,dry_delay_ms,dry_drop,dry_override_expire_ms,dry_suppress_hb,
   // max_spread_self,max_spread_peer,quotes_fresh_ms,file_poll_ms,retry_on_requote,max_retries,cmd_expire_ms,ack_timeout_ms,heartbeat_timeout_ms,reconcile_mode,reconcile_interval_ms,close_cooldown_seconds,min_balance_master_usd,min_balance_slave_usd
   ulong updated_ms = NowMs();
   string line = StringFormat("1,%s,%s,%.2f,%.2f,%d,%d,%d,%d,%I64u,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f\n",
      g_symbol,
      ((input_master_side==SIDE_BUY)?"BUY":"SELL"),
      input_lot_master,
      input_lot_slave,
      input_open_threshold_points,
      input_close_threshold_points,
      input_open_cooldown_seconds,
      input_max_open_pairs,
      updated_ms,
      (input_dry_run_enabled?1:0),
      (int)input_dry_run_handshake_mode,
      input_dry_run_inject_delay_ms,
      input_dry_run_drop_rate_percent,
      input_dry_run_override_cmd_expire_ms,
      (input_dry_run_suppress_heartbeat?1:0),
      input_max_spread_points_self,
      input_max_spread_points_peer,
      input_quotes_fresh_ms,
      input_file_poll_ms,
      (input_retry_on_requote?1:0),
      input_max_retries,
      input_cmd_expire_ms,
      input_ack_timeout_ms,
      input_heartbeat_timeout_ms,
      (int)input_reconcile_mode,
      input_reconcile_interval_ms,
      input_close_cooldown_seconds,
      input_min_balance_master_usd,
      input_min_balance_slave_usd);
   FileWriteAll(PathConfigMaster(), line);
}

// -----------------------------
// Role lock (single-instance per channel/role)
// -----------------------------
bool AcquireRoleLock()
{
   // If an existing lock is fresh, treat as conflict
   string s;
   if(FileReadAll(PathRoleLock(), s))
   {
      int p = StringFind(s, ",");
      string ts = (p>=0) ? StringSubstr(s, 0, p) : TrimAll(s);
      ulong ts_ms = (ulong)StrToDouble(ts);
      if((NowMs() - ts_ms) <= (ulong)EffectiveHeartbeatTimeoutMs())
         return false;
   }
   // Write our lock
   string line = StringFormat("%I64u,%d,%d\n", NowMs(), AccountNumber(), g_magic);
   FileWriteAll(PathRoleLock(), line);
   return true;
}

void WriteRoleLock()
{
   string line = StringFormat("%I64u,%d,%d\n", NowMs(), AccountNumber(), g_magic);
   FileWriteAll(PathRoleLock(), line);
}

bool ReadPeerHeartbeat(ulong &peer_ms)
{
   string s;
   if(!FileReadAll(PathHeartbeatPeer(), s)) return false;
   string f[]; int n = StringSplit(TrimAll(s), ',', f);
   if(n < 1) return false;
   // Use floating conversion to preserve 64-bit millisecond timestamp
   peer_ms = (ulong)StrToDouble(f[0]);
   // Optional: peer digits/point appended by the other side
   if(n >= 9)
   {
      int pd = (int)StrToInteger(f[7]);
      double pp = StrToDouble(f[8]);
      if(pd >= 0) g_peer_digits = pd;
      if(pp > 0.0) g_peer_point = pp;
   }
   return true;
}

void UpdatePeerStatus()
{
   ulong hb = 0;
   if(ReadPeerHeartbeat(hb))
   {
      g_peer_hb_ms = hb;
      g_peer_alive = ((NowMs() - g_peer_hb_ms) <= (ulong)EffectiveHeartbeatTimeoutMs());
   }
   else
   {
      g_peer_alive = false;
   }
}

void WriteQuotes()
{
   RefreshRates();
   g_self_bid = MarketInfo(g_symbol, MODE_BID);
   g_self_ask = MarketInfo(g_symbol, MODE_ASK);
   g_self_quote_ms = NowMs();
   string line = StringFormat("%I64u,%.10f,%.10f\n", g_self_quote_ms, g_self_bid, g_self_ask);
   FileWriteAll(PathQuotesSelf(), line);
}

bool ReadPeerQuotes()
{
   string s;
   if(!FileReadAll(PathQuotesPeer(), s)) return false;
   // expect: epoch_ms,bid,ask
   int p1 = StringFind(s, ",");
   if(p1<0) return false;
   int p2 = StringFind(s, ",", p1+1);
   if(p2<0) return false;
   string ts = StringSubstr(s, 0, p1);
   string sbid = StringSubstr(s, p1+1, p2-p1-1);
   string sask = StringSubstr(s, p2+1);
   // Use floating conversion to preserve 64-bit millisecond timestamp
   g_peer_quote_ms = (ulong)StrToDouble(ts);
   g_peer_bid = StrToDouble(sbid);
   g_peer_ask = StrToDouble(sask);
   return true;
}

// Master-provided new settings (for Slave)
int    g_master_close_cooldown_seconds = 0;
double g_master_min_balance_master_usd = 0.0;
double g_master_min_balance_slave_usd = 0.0;

bool ReadMasterConfigForSlave()
{
   if(input_role==ROLE_MASTER) return false;
   string s; if(!FileReadAll(PathConfigMaster(), s)) return false;
   string f[]; int n = StringSplit(TrimAll(s), ',', f);
   if(n < 10) return false;
   // f[0]=version, f[1]=symbol, f[2]=side, f[3]=lotM, f[4]=lotS, f[5]=open_th, f[6]=close_th, f[7]=cooldown, f[8]=max_pairs, f[9]=updated_ms
   g_have_master_cmd = true;
   g_last_cmd_side = f[2];
   g_last_cmd_lot_master = StrToDouble(f[3]);
   g_last_cmd_lot_slave  = StrToDouble(f[4]);
   g_have_master_th = true;
   g_last_cmd_open_th = (int)StrToInteger(f[5]);
   g_last_cmd_close_th = (int)StrToInteger(f[6]);
   g_last_cmd_seen_ms = NowMs();
   // Optional dry-run fields from master
   if(n >= 16)
   {
      g_master_dry_enabled = (StrToInteger(f[10])!=0);
      g_master_dry_mode = (int)StrToInteger(f[11]);
      g_master_dry_delay_ms = (int)StrToInteger(f[12]);
      g_master_dry_drop = (int)StrToInteger(f[13]);
      g_master_dry_override_expire_ms = (int)StrToInteger(f[14]);
      g_master_dry_suppress_heartbeat = (StrToInteger(f[15])!=0);
   }
   // Guards/Timeouts starting from index 16 if present
   if(n >= 30)
   {
      g_master_max_spread_self = (int)StrToInteger(f[16]);
      g_master_max_spread_peer = (int)StrToInteger(f[17]);
      g_master_quotes_fresh_ms = (int)StrToInteger(f[18]);
      g_master_file_poll_ms = (int)StrToInteger(f[19]);
      g_master_retry_on_requote = (int)StrToInteger(f[20]);
      g_master_max_retries = (int)StrToInteger(f[21]);
      g_master_cmd_expire_ms = (int)StrToInteger(f[22]);
      g_master_ack_timeout_ms = (int)StrToInteger(f[23]);
      g_master_heartbeat_timeout_ms = (int)StrToInteger(f[24]);
      g_master_reconcile_mode = (int)StrToInteger(f[25]);
      g_master_reconcile_interval_ms = (int)StrToInteger(f[26]);
      // New fields
      g_master_close_cooldown_seconds = (int)StrToInteger(f[27]);
      g_master_min_balance_master_usd = StrToDouble(f[28]);
      g_master_min_balance_slave_usd = StrToDouble(f[29]);
   }
   return true;
}

int SelfSpreadOk()
{
   if(SpreadPointsSelf() <= input_max_spread_points_self) return 1;
   return 0;
}

int PeerSpreadOk()
{
   // Best-effort: compute from last peer bid/ask
   if(g_peer_ask<=0 || g_peer_bid<=0) return 0;
   double sp = g_peer_ask - g_peer_bid;
   int sp_points = (int)MathRound(PointsFromPriceDiff(MathMax(0.0, sp)));
   return (sp_points <= input_max_spread_points_peer) ? 1 : 0;
}

bool QuotesFresh()
{
   ulong now = NowMs();
   int age_self = (int)(now - g_self_quote_ms);
   int age_peer = (int)(now - g_peer_quote_ms);
   int freshMs = EffectiveQuotesFreshMs();
   return (age_self <= freshMs && age_peer <= freshMs);
}

bool ReadPeerBalanceFresh(double &bal_out, ulong &ts_out)
{
   bal_out = 0.0; ts_out = 0;
   string s; if(!FileReadAll(PathAccountStatusPeer(), s)) return false;
   string f[]; int n = StringSplit(TrimAll(s), ',', f);
   if(n<4) return false;
   // format: version,balance,equity,updated_ms
   bal_out = StrToDouble(f[1]);
   ts_out = (ulong)StrToDouble(f[3]);
   // freshness: require within EffectiveHeartbeatTimeoutMs
   if((NowMs()-ts_out) > (ulong)EffectiveHeartbeatTimeoutMs()) return false;
   return true;
}

double DiffOpenPoints()
{
   // Always compute in Master orientation
   bool masterBuy = IsMasterSideBuyEffective();
   double m_bid,m_ask,s_bid,s_ask; GetMasterSlaveQuotes(m_bid,m_ask,s_bid,s_ask);
   double diff = masterBuy ? (s_bid - m_ask) : (m_bid - s_ask);
   double pt = EffectivePoint(); if(pt <= 0.0) pt = g_point;
   return diff / pt;
}

double DiffClosePoints()
{
   // Always compute in Master orientation
   bool masterBuy = IsMasterSideBuyEffective();
   double m_bid,m_ask,s_bid,s_ask; GetMasterSlaveQuotes(m_bid,m_ask,s_bid,s_ask);
   double diff = masterBuy ? (m_bid - s_ask) : (s_bid - m_ask);
   double pt = EffectivePoint(); if(pt <= 0.0) pt = g_point;
   return diff / pt;
}

// -----------------------------
// Averaging helpers (EMA + Median pre-filter)
// -----------------------------

void PushMedianOpen(const double v)
{
   int maxN = (input_prefilter_window>16?16:input_prefilter_window);
   if(maxN<3) maxN = 3;
   if((maxN % 2)==0) maxN++;
   if(g_med_open_count < maxN) g_med_open_count++;
   g_med_buf_open[g_med_open_idx] = v;
   g_med_open_idx++; if(g_med_open_idx>=maxN) g_med_open_idx=0;
}

double GetMedianOpen(const int window)
{
   int maxN = (window>16?16:window);
   if(maxN<1) return g_med_buf_open[(g_med_open_idx>0)?(g_med_open_idx-1):0];
   int useN = (g_med_open_count<maxN? g_med_open_count : maxN);
   if(useN<=0) return 0.0;
   double tmp[16]; ArrayInitialize(tmp, 0.0);
   int pos = g_med_open_idx;
   for(int i=0;i<useN;i++) { int j = pos - 1 - i; if(j<0) j += maxN; tmp[i] = g_med_buf_open[j]; }
   for(int i=1;i<useN;i++){ double key=tmp[i]; int k=i-1; while(k>=0 && tmp[k]>key){ tmp[k+1]=tmp[k]; k--; } tmp[k+1]=key; }
   int mid = useN/2; if((useN%2)==1) return tmp[mid]; else return 0.5*(tmp[mid-1]+tmp[mid]);
}

void PushMedianClose(const double v)
{
   int maxN = (input_prefilter_window>16?16:input_prefilter_window);
   if(maxN<3) maxN = 3;
   if((maxN % 2)==0) maxN++;
   if(g_med_close_count < maxN) g_med_close_count++;
   g_med_buf_close[g_med_close_idx] = v;
   g_med_close_idx++; if(g_med_close_idx>=maxN) g_med_close_idx=0;
}

double GetMedianClose(const int window)
{
   int maxN = (window>16?16:window);
   if(maxN<1) return g_med_buf_close[(g_med_close_idx>0)?(g_med_close_idx-1):0];
   int useN = (g_med_close_count<maxN? g_med_close_count : maxN);
   if(useN<=0) return 0.0;
   double tmp[16]; ArrayInitialize(tmp, 0.0);
   int pos = g_med_close_idx;
   for(int i=0;i<useN;i++) { int j = pos - 1 - i; if(j<0) j += maxN; tmp[i] = g_med_buf_close[j]; }
   for(int i=1;i<useN;i++){ double key=tmp[i]; int k=i-1; while(k>=0 && tmp[k]>key){ tmp[k+1]=tmp[k]; k--; } tmp[k+1]=key; }
   int mid = useN/2; if((useN%2)==1) return tmp[mid]; else return 0.5*(tmp[mid-1]+tmp[mid]);
}

double SmoothedOpenDiff(const double realDiff)
{
   if(!input_avg_filter_enabled) return realDiff;
   double filtered = realDiff;
   if(input_use_prefilter_median && input_prefilter_window>=3 && (input_prefilter_window%2)==1)
   {
      PushMedianOpen(realDiff);
      filtered = GetMedianOpen(input_prefilter_window);
   }
   else
   {
      PushMedianOpen(realDiff);
      filtered = realDiff;
   }
   double alpha = 2.0 / (input_avg_period + 1.0);
   if(!g_ema_open_init){ g_ema_open = filtered; g_ema_open_init = true; }
   else { g_ema_open = g_ema_open + alpha * (filtered - g_ema_open); }
   return g_ema_open;
}

double SmoothedCloseDiff(const double realDiff)
{
   if(!input_avg_filter_enabled) return realDiff;
   double filtered = realDiff;
   if(input_use_prefilter_median && input_prefilter_window>=3 && (input_prefilter_window%2)==1)
   {
      PushMedianClose(realDiff);
      filtered = GetMedianClose(input_prefilter_window);
   }
   else
   {
      PushMedianClose(realDiff);
      filtered = realDiff;
   }
   double alpha = 2.0 / (input_avg_period + 1.0);
   if(!g_ema_close_init){ g_ema_close = filtered; g_ema_close_init = true; }
   else { g_ema_close = g_ema_close + alpha * (filtered - g_ema_close); }
   return g_ema_close;
}

void MaybeOpenPair()
{
   if(g_role_conflict) return;
   if(!(input_role==ROLE_MASTER)) return;
   // Account authorization check
   if(input_auth_enabled && !g_account_authorized) return;
   // Update scheduled close only mode state
   UpdateScheduledCloseOnlyMode();
   // Close Only mode: prevent new orders
   if(g_close_only_mode) return;
   // Saturday quiet window: block any opens
   if(IsInSaturdayQuietWindow()) return;
   if(!g_peer_alive) return; // do not operate without peer
   if((int)(TimeCurrent() - g_last_open_time) < input_open_cooldown_seconds) return;
   if(CountOpenPairs() >= input_max_open_pairs) return;
   if(!ReadPeerQuotes()) return;
   if(!QuotesFresh()) return;
   if(!SelfSpreadOk()) return;
   if(!PeerSpreadOk()) return;

   // Min balance checks on both peers (fail-safe: require fresh peer info)
   if(input_min_balance_master_usd > 0.0 || input_min_balance_slave_usd > 0.0)
   {
      double m_bal = AccountBalance(); double s_bal=0.0; ulong s_ts=0;
      bool s_ok = ReadPeerBalanceFresh(s_bal, s_ts);
      
      // Check master balance requirement
      if(input_min_balance_master_usd > 0.0 && m_bal < input_min_balance_master_usd) return;
      
      // Check slave balance requirement
      if(input_min_balance_slave_usd > 0.0)
      {
         if(!s_ok || s_bal < input_min_balance_slave_usd) return;
      }
   }

   // Pre-send recheck: compute diff now
   double diffOpen = DiffOpenPoints();
   bool triggerOpen = false;
   
   // PRIORITY: Averaging > Raw Stability > Simple
   if(input_avg_filter_enabled)
   {
      // Averaging logic (highest priority)
      if(input_avg_signal_cooldown_ms > 0 && (NowMs() - g_last_avg_open_signal_ms) < (ulong)input_avg_signal_cooldown_ms) return;
      double avgOpen = SmoothedOpenDiff(diffOpen);
      double thrEff = (double)(input_open_threshold_points + input_diff_hysteresis_points);
      if(!g_open_pending)
      {
         if(avgOpen >= thrEff)
         {
            g_open_pending = true; g_open_snapshot_avg = avgOpen; g_open_ok_count = 0; g_open_deadline_ms = NowMs() + (ulong)input_confirm_timeout_ms;
         }
         return;
      }
      else
      {
         bool ok = true;
         if(input_real_confirm_enabled)
         {
            double need = MathMax(g_open_snapshot_avg, thrEff) + (double)input_epsilon_diff_points;
            ok = (diffOpen >= need);
         }
         else
         {
            ok = (avgOpen >= thrEff);
         }
         if(ok) g_open_ok_count++; else g_open_ok_count = 0;
         if(g_open_ok_count >= input_confirm_ticks)
         {
            triggerOpen = true; g_open_pending = false; g_last_avg_open_signal_ms = NowMs();
         }
         else
         {
            if(input_confirm_timeout_ms>0 && NowMs() > g_open_deadline_ms) { g_open_pending = false; g_open_ok_count = 0; }
            if(!triggerOpen) return;
         }
      }
   }
   else if(input_raw_stability_enabled)
   {
      // Raw stability logic (second priority)
      double enterThreshold = (double)input_open_threshold_points;
      double resetThreshold = (double)(input_open_threshold_points - input_raw_hysteresis_offset);
      
      if(!g_raw_open_pending)
      {
         if(diffOpen >= enterThreshold)
         {
            g_raw_open_pending = true;
            g_raw_open_stable_count = 1;
            g_raw_open_start_ms = NowMs();
            LogEvent("RAW_OPEN_START", StringFormat("diff=%.1f;count=1;reset_at=%.1f", 
                     diffOpen, resetThreshold));
         }
         return;
      }
      else
      {
         if(diffOpen < resetThreshold)
         {
            g_raw_open_pending = false;
            g_raw_open_stable_count = 0;
            LogEvent("RAW_OPEN_RESET", StringFormat("diff=%.1f;below_reset=%.1f", 
                     diffOpen, resetThreshold));
            return;
         }
         
         g_raw_open_stable_count++;
         LogEvent("RAW_OPEN_TICK", StringFormat("diff=%.1f;count=%d/%d", 
                  diffOpen, g_raw_open_stable_count, input_raw_stability_ticks));
         
         if(g_raw_open_stable_count >= input_raw_stability_ticks)
         {
            triggerOpen = true;
            g_raw_open_pending = false;
            LogEvent("RAW_OPEN_CONFIRMED", StringFormat("diff=%.1f;final_count=%d", 
                     diffOpen, g_raw_open_stable_count));
         }
         
         if((NowMs() - g_raw_open_start_ms) > (ulong)input_raw_stability_timeout_ms)
         {
            g_raw_open_pending = false;
            g_raw_open_stable_count = 0;
            LogEvent("RAW_OPEN_TIMEOUT", StringFormat("elapsed_ms=%I64u", 
                     NowMs() - g_raw_open_start_ms));
         }
         
         if(!triggerOpen) return;
      }
   }
   else
   {
      // Simple instant logic (lowest priority)
      if(diffOpen < input_open_threshold_points) return;
      triggerOpen = true;
   }


   if(!triggerOpen) return;
   // Generate id but DO NOT write open_cmd until master opened successfully
   string cmd_id = NewCmdId();
   g_last_cmd_id = cmd_id;
   
   // Log the trigger source for automatic opens
   string triggerSource = "UNKNOWN";
   if(input_avg_filter_enabled) triggerSource = "AUTO_AVERAGING";
   else if(input_raw_stability_enabled) triggerSource = "AUTO_RAW_STABILITY";
   else triggerSource = "AUTO_SIMPLE";
   LogEvent("OPEN_TRIGGER", StringFormat("source=%s;cmd_id=%s;diffOpen=%.1f", triggerSource, cmd_id, DiffOpenPoints()));

   // Dry run path still respects new ordering (ack after pretend open)
   if(DryEnabled())
   {
      // Pretend master open succeeded
      g_last_open_time = TimeCurrent();
      // Write open_cmd with audit
      ulong created_ms = NowMs();
      // CRITICAL FIX: Ensure expire_ms is always positive and reasonable
      int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0) ? DryOverrideExpireMs() : input_cmd_expire_ms;
      if(expire_ms <= 0) expire_ms = 60000; // Default 60 seconds if invalid (increased for timezone safety)
      string lineDR = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.1f\n",
         cmd_id,(long)g_seq,cmd_id,g_symbol,((input_master_side==SIDE_BUY)?"BUY":"SELL"),input_lot_master,input_lot_slave,input_slippage_points,created_ms,expire_ms,input_open_threshold_points,input_close_threshold_points,
         g_self_bid,g_self_ask,g_peer_bid,g_peer_ask,diffOpen);
      FileWriteAllAtomic(PathOpenCmd(), lineDR);
      LogEvent("OPEN_CMD", StringFormat("cmd_id=%s;side=%s;lotM=%.2f;lotS=%.2f;expire_ms=%d;mb=%.5f;ma=%.5f;sb=%.5f;sa=%.5f", cmd_id, ((input_master_side==SIDE_BUY)?"BUY":"SELL"), input_lot_master, input_lot_slave, expire_ms, g_self_bid, g_self_ask, g_peer_bid, g_peer_ask));
      g_waiting_slave_open_ack = true; g_pending_open_cmd_id = cmd_id; g_pending_open_created_ms = created_ms; g_rollback_initiated=false; 
      // ENHANCED: Set extended grace period to prevent immediate close
      g_open_grace_until_ms = NowMs() + (ulong)MathMax(input_ack_timeout_ms + 2000, input_close_cooldown_seconds * 1000);
      g_early_warning_sent = false; // reset warning flag
      // Ack self
      string ackSelf = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0);
      FileWriteAllAtomic(PathOpenAckSelf(), ackSelf);
      LogEvent("OPEN_ACK_MASTER", StringFormat("cmd_id=%s;ok=1;price=0.0;err=0", cmd_id));
      return;
   }

   // Real trading on master side only: send order first
   int ticket=-1; double price=0.0; bool ok = PlaceOrderMaster((input_master_side==SIDE_BUY), input_lot_master, ticket, price);
   string ackSelf2 = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ackSelf2);
   LogEvent("OPEN_ACK_MASTER", StringFormat("cmd_id=%s;ok=%d;price=%.5f;err=%d", cmd_id, ok?1:0, price, ok?0:GetLastError()));
   if(!ok)
   {
      // Enforce open cooldown on fail
      g_last_open_time = TimeCurrent();
      return;
   }

   // Master open succeeded -> write mapping and notify slave
   g_last_open_time = TimeCurrent();
   PairMapSelfUpsert(cmd_id, ticket);
   CacheUpsert(cmd_id, ticket);
   WritePositions(); CompactPairMapSelf();

   // Write open_cmd with audit fields
   {
      ulong created_ms = NowMs();
         // CRITICAL FIX: Ensure expire_ms is always positive and reasonable
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0) ? DryOverrideExpireMs() : input_cmd_expire_ms;
   if(expire_ms <= 0) expire_ms = 60000; // Default 60 seconds if invalid (increased for timezone safety)
   string line = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.1f\n",
         cmd_id,(long)g_seq,cmd_id,g_symbol,((input_master_side==SIDE_BUY)?"BUY":"SELL"),input_lot_master,input_lot_slave,input_slippage_points,created_ms,expire_ms,input_open_threshold_points,input_close_threshold_points,
         g_self_bid,g_self_ask,g_peer_bid,g_peer_ask,diffOpen);
      FileWriteAllAtomic(PathOpenCmd(), line);
      LogEvent("OPEN_CMD", StringFormat("cmd_id=%s;side=%s;lotM=%.2f;lotS=%.2f;expire_ms=%d;mb=%.5f;ma=%.5f;sb=%.5f;sa=%.5f", cmd_id, ((input_master_side==SIDE_BUY)?"BUY":"SELL"), input_lot_master, input_lot_slave, created_ms, g_self_bid, g_self_ask, g_peer_bid, g_peer_ask));
      g_waiting_slave_open_ack = true; g_pending_open_cmd_id = cmd_id; g_pending_open_created_ms = created_ms; g_rollback_initiated=false; 
      // ENHANCED: Set extended grace period to prevent immediate close
      g_open_grace_until_ms = NowMs() + (ulong)MathMax(input_ack_timeout_ms + 2000, input_close_cooldown_seconds * 1000);
      g_early_warning_sent = false; // reset warning flag
   }
}

bool TryReadPeerOpenAck(string &ack_cmd_id, int &ok_out)
{
   string s;
   if(!FileReadAll(PathOpenAckPeer(), s)) return false;
   string fields[];
   int n = StringSplit(TrimAll(s), ',', fields);
   if(n < 6) return false;
   ack_cmd_id = fields[1];
   // fields: 0=ver,1=cmd_id,2=seq,3=pair,4=price,5=ok,6=error
   ok_out = (n>=6) ? (int)StrToInteger(fields[5]) : 0;
   if(ok_out==1) g_last_peer_open_ack_ms = NowMs();
   return true;
}

void MasterRollbackOpen()
{
   if(g_rollback_initiated) return;
   g_rollback_initiated = true;
   LogEvent("CLOSE_TRIGGER", StringFormat("source=ROLLBACK_TIMEOUT;pending_cmd=%s", g_pending_open_cmd_id));
   string close_id = NewCmdId();
   ulong created_ms = NowMs();
   int expire_ms = input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n",
                              close_id,
                              (long)g_seq,
                              "N/A",
                              "CLOSE",
                              created_ms,
                              expire_ms);
   FileWriteAllAtomic(PathCloseCmd(), line);
   bool ok = CloseAllByMagic();
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", close_id, (long)g_seq, "N/A", ok?1:0, ok?0:GetLastError());
   FileWriteAll(PathCloseAckSelf(), ack);
   // reset waiting state
   g_waiting_slave_open_ack = false;
   g_pending_open_cmd_id = "";
}

// Global variable สำหรับ early warning
bool g_early_warning_sent = false;

// Performance Metrics
ulong g_total_opens = 0;
ulong g_successful_opens = 0;
ulong g_rollback_count = 0;
ulong g_avg_ack_time_ms = 0;
ulong g_total_ack_time_ms = 0;

void UpdateOpenMetrics(ulong ack_time_ms, bool success)
{
   g_total_opens++;
   if(success) 
   {
      g_successful_opens++;
      g_total_ack_time_ms += ack_time_ms;
      g_avg_ack_time_ms = g_total_ack_time_ms / g_successful_opens;
   }
   else
   {
      g_rollback_count++;
   }
}

void MasterWatchdogOpen()
{
   if(!g_waiting_slave_open_ack) return;
   // In debug hold mode, do not rollback open; wait until user presses Close Now
   if(input_debug_buttons_enabled && g_debug_hold_open) return;
   
   // CRITICAL FIX: Prevent timestamp underflow that causes massive elapsed values
   ulong now_ms = NowMs();
   if(now_ms < g_pending_open_created_ms || g_pending_open_created_ms == 0) {
      // Clock went backwards, overflow, or uninitialized - reset the timer
      g_pending_open_created_ms = now_ms;
      LogEvent("WATCHDOG_RESET", StringFormat("cmd_id=%s;reason=TIMESTAMP_FIX", g_pending_open_cmd_id));
      return;
   }
   ulong elapsed = now_ms - g_pending_open_created_ms;
   
   // Early warning ที่ 50% ของ timeout
   if(elapsed > (ulong)(input_ack_timeout_ms * 0.5) && !g_early_warning_sent)
   {
      LogEvent("SLAVE_SLOW_WARNING", StringFormat("cmd_id=%s;elapsed_ms=%I64u", 
                g_pending_open_cmd_id, elapsed));
      g_early_warning_sent = true;
   }
   
   // timeout
   if(elapsed > (ulong)input_ack_timeout_ms)
   {
      // ตรวจสอบ market condition ก่อน rollback
      double currentSpread = SpreadPointsSelf();
      
      // ถ้า spread ปกติ ให้เวลาเพิ่มอีกนิด (แต่ไม่เกิน 50%)
      if(currentSpread <= input_max_spread_points_self && 
         elapsed < (ulong)(input_ack_timeout_ms * 1.5))
      {
         LogEvent("ROLLBACK_DELAYED", StringFormat("cmd_id=%s;elapsed_ms=%I64u;spread=%d", 
                   g_pending_open_cmd_id, elapsed, currentSpread));
         return; // รออีกนิด
      }
      
      LogEvent("ROLLBACK_TIMEOUT", StringFormat("cmd_id=%s;elapsed_ms=%I64u;spread=%d", 
                g_pending_open_cmd_id, elapsed, currentSpread));
      UpdateOpenMetrics(elapsed, false); // บันทึก rollback
      MasterRollbackOpen();
      return;
   }
   
   // check peer ack
   string ack_id; int ok;
   if(TryReadPeerOpenAck(ack_id, ok))
   {
      if(ack_id == g_pending_open_cmd_id)
      {
         if(ok==1)
         {
            LogEvent("OPEN_ACK_PEER", StringFormat("cmd_id=%s;ok=1;elapsed_ms=%I64u", ack_id, elapsed));
            UpdateOpenMetrics(elapsed, true); // บันทึก success
            // success from slave
            g_waiting_slave_open_ack = false;
            g_pending_open_cmd_id = "";
            g_early_warning_sent = false; // reset warning flag
            // Start close cooldown anchor at the moment both sides confirmed open
            g_last_pair_both_open_time = TimeCurrent();
            // ENHANCED: Extend grace period after successful peer ACK to prevent immediate close
            g_open_grace_until_ms = NowMs() + (ulong)MathMax(input_close_cooldown_seconds * 1000, 15000); // อย่างน้อย 15 วินาที
         }
         else
         {
            LogEvent("OPEN_ACK_PEER", StringFormat("cmd_id=%s;ok=0;elapsed_ms=%I64u", ack_id, elapsed));
            LogEvent("OPEN_ROLLBACK", StringFormat("cmd_id=%s;reason=PEER_FAIL", ack_id));
            UpdateOpenMetrics(elapsed, false); // บันทึก peer fail
            // slave failed -> rollback
            MasterRollbackOpen();
         }
      }
   }
}

void MaybeClosePair()
{
   if(g_role_conflict) return;
   if(!(input_role==ROLE_MASTER)) return;
   // Account authorization check
   if(input_auth_enabled && !g_account_authorized) return;
   // Saturday quiet window: block any closes
   if(IsInSaturdayQuietWindow()) return;
   
   // CRITICAL: Enhanced protection against immediate close after open
   // Do not auto-close while waiting for slave to acknowledge an open
   if(g_waiting_slave_open_ack) return;
   
   // Extended grace period after open command sent (with buffer)
   if(g_pending_open_created_ms > 0 && (NowMs() - g_pending_open_created_ms) < (ulong)(input_ack_timeout_ms + 2000)) return;
   
   // Grace period after peer ACK received
   if(g_last_peer_open_ack_ms>0 && (NowMs()-g_last_peer_open_ack_ms) < (ulong)input_ack_timeout_ms) return;
   
   // Consolidated grace window across bursts of opens
   if(NowMs() < g_open_grace_until_ms) return;
   
   // Close only if we actually have open trades to avoid immediate close-after-open effect
   if(CountOpenPairs()<=0) return;
   
   // Close cooldown: avoid normal auto-close until elapsed; do not block reconcile paths elsewhere
   // If a pair was both-side opened recently, this timestamp should have been set; we set/update it upon successful open + peer ack in watchdog
   if(g_last_pair_both_open_time>0)
   {
      if((int)(TimeCurrent() - g_last_pair_both_open_time) < input_close_cooldown_seconds)
         return;
   }
   if(!ReadPeerQuotes()) return;
   if(!QuotesFresh()) return;
   double diffClose = DiffClosePoints();
   bool triggerClose = false;
   
   // PRIORITY: Averaging > Raw Stability > Simple
   if(input_avg_filter_enabled)
   {
      // Averaging logic for close (highest priority)
      if(input_avg_signal_cooldown_ms > 0 && (NowMs() - g_last_avg_close_signal_ms) < (ulong)input_avg_signal_cooldown_ms) return;
      double avgClose = SmoothedCloseDiff(diffClose);
      double thrEff = (double)(input_close_threshold_points + input_diff_hysteresis_points);
      if(!g_close_pending)
      {
         if(avgClose >= thrEff)
         {
            g_close_pending = true; g_close_snapshot_avg = avgClose; g_close_ok_count = 0; g_close_deadline_ms = NowMs() + (ulong)input_confirm_timeout_ms;
         }
         return;
      }
      else
      {
         bool ok = true;
         if(input_real_confirm_enabled)
         {
            double need = MathMax(g_close_snapshot_avg, thrEff) + (double)input_epsilon_diff_points;
            ok = (diffClose >= need);
         }
         else
         {
            ok = (avgClose >= thrEff);
         }
         if(ok) g_close_ok_count++; else g_close_ok_count = 0;
         if(g_close_ok_count >= input_confirm_ticks)
         {
            triggerClose = true; g_close_pending = false; g_last_avg_close_signal_ms = NowMs();
         }
         else
         {
            if(input_confirm_timeout_ms>0 && NowMs() > g_close_deadline_ms) { g_close_pending = false; g_close_ok_count = 0; }
            if(!triggerClose) return;
         }
      }
   }
   else if(input_raw_stability_enabled)
   {
      // Raw stability logic for close (second priority)
      double enterThreshold = (double)input_close_threshold_points;
      double resetThreshold = (double)(input_close_threshold_points - input_raw_hysteresis_offset);
      
      if(!g_raw_close_pending)
      {
         if(diffClose >= enterThreshold)
         {
            g_raw_close_pending = true;
            g_raw_close_stable_count = 1;
            g_raw_close_start_ms = NowMs();
            LogEvent("RAW_CLOSE_START", StringFormat("diff=%.1f;count=1;reset_at=%.1f", 
                     diffClose, resetThreshold));
         }
         return;
      }
      else
      {
         if(diffClose < resetThreshold)
         {
            g_raw_close_pending = false;
            g_raw_close_stable_count = 0;
            LogEvent("RAW_CLOSE_RESET", StringFormat("diff=%.1f;below_reset=%.1f", 
                     diffClose, resetThreshold));
            return;
         }
         
         g_raw_close_stable_count++;
         LogEvent("RAW_CLOSE_TICK", StringFormat("diff=%.1f;count=%d/%d", 
                  diffClose, g_raw_close_stable_count, input_raw_stability_ticks));
         
         if(g_raw_close_stable_count >= input_raw_stability_ticks)
         {
            triggerClose = true;
            g_raw_close_pending = false;
            LogEvent("RAW_CLOSE_CONFIRMED", StringFormat("diff=%.1f;final_count=%d", 
                     diffClose, g_raw_close_stable_count));
         }
         
         if((NowMs() - g_raw_close_start_ms) > (ulong)input_raw_stability_timeout_ms)
         {
            g_raw_close_pending = false;
            g_raw_close_stable_count = 0;
            LogEvent("RAW_CLOSE_TIMEOUT", StringFormat("elapsed_ms=%I64u", 
                     NowMs() - g_raw_close_start_ms));
         }
         
         if(!triggerClose) return;
      }
   }
   else
   {
      // Simple instant logic (lowest priority)
      if(diffClose < input_close_threshold_points) return;
      triggerClose = true;
   }


   if(!triggerClose) return;

   // Log the trigger source for automatic closes
   string triggerSource = "UNKNOWN";
   if(input_avg_filter_enabled) triggerSource = "AUTO_AVERAGING";
   else if(input_raw_stability_enabled) triggerSource = "AUTO_RAW_STABILITY";
   else triggerSource = "AUTO_SIMPLE";
   LogEvent("CLOSE_TRIGGER", StringFormat("source=%s;diffClose=%.1f", triggerSource, DiffClosePoints()));

   string cmd_id = NewCmdId();
   ulong created_ms = NowMs();
   // CRITICAL FIX: Ensure expire_ms is always positive and reasonable
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0) ? DryOverrideExpireMs() : input_cmd_expire_ms;
   if(expire_ms <= 0) expire_ms = 60000; // Default 60 seconds if invalid (increased for timezone safety)
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n",
                              cmd_id,
                              (long)g_seq,
                              "N/A",
                              "CLOSE",
                              created_ms,
                              expire_ms);
   bool write_cmd = true;
   if(DryEnabled() && DryMode()==DRY_NONE)
      write_cmd = false;
   if(write_cmd)
   {
      FileWriteAllAtomic(PathCloseCmd(), line);
      // Enhanced logging to track close triggers
      LogEvent("CLOSE_CMD", StringFormat("cmd_id=%s;reason=AUTO;diffClose=%.1f;threshold=%d;action=CLOSE", cmd_id, diffClose, input_close_threshold_points));
   }

   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      {
         int latency = DryDelayMs();
         if(latency>0) Sleep(latency);
         string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0);
         FileWriteAll(PathCloseAckSelf(), ackSelf);
      }
      return;
   }

   // Real close all by magic (simplified)
   bool ok = CloseAllByMagic();
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:GetLastError());
   FileWriteAll(PathCloseAckSelf(), ack);
   LogEvent("CLOSE_ACK_MASTER", StringFormat("cmd_id=%s;ok=%d;err=%d", cmd_id, ok?1:0, ok?0:GetLastError()));
}

void SlaveProcessOpenCmd()
{
   if(g_role_conflict) return;
   if(input_role==ROLE_MASTER) return;
   // Account authorization check
   if(input_auth_enabled && !g_account_authorized) return;
   string s;
   if(!FileReadAll(PathOpenCmd(), s)) { if(input_verbose_journal_logs) Print("[Slave] open_cmd.csv not found or not readable"); return; }
   // Very simple parse; assume last line is the command (single-line file)
   // format: version,cmd_id,seq,pair_id,symbol,master_side,lot_master,lot_slave,slippage,created_ms,expire_ms
   string fields[];
   int n = StringSplit(TrimAll(s), ',', fields);
   if(n < 11)
   {
      // malformed command; acknowledge failure to allow master rollback
      string ackBad = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", "UNKNOWN", (long)g_seq, "N/A", "0.0", 0, 400);
      FileWriteAllAtomic(PathOpenAckSelf(), ackBad);
      if(input_verbose_journal_logs) Print("[Slave] Malformed open_cmd (n<11), wrote ACK fail 400");
      return;
   }
   string cmd_id = fields[1];
   string pair_id= fields[3];
   string sym    = fields[4];
   string mside  = fields[5];
   double lot_slave = StrToDouble(fields[7]);
   ulong created_ms = (ulong)StrToDouble(fields[9]);
   int expire_ms    = (int)StrToInteger(fields[10]);

   // Saturday quiet window: ACK fail to let master rollback
   if(IsInSaturdayQuietWindow())
   {
      string ackSat = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 0, 451);
      FileWriteAllAtomic(PathOpenAckSelf(), ackSat);
      LogEvent("OPEN_ACK_SLAVE", StringFormat("cmd_id=%s;ok=0;err=%d;reason=SATURDAY_QUIET", cmd_id, 451));
      if(input_verbose_journal_logs) Print("[Slave] Saturday quiet window, reject open cmd_id=", cmd_id);
      return;
   }

   // Idempotency: skip if already acknowledged/processed this cmd
   string sAckOpen;
   if(FileReadAll(PathOpenAckSelf(), sAckOpen))
   {
      string af[]; int an = StringSplit(TrimAll(sAckOpen), ',', af);
      if(an>=2 && af[1]==cmd_id) return;
   }
   if(g_last_processed_open_cmd_id == cmd_id) return;
   g_last_processed_open_cmd_id = cmd_id;
   // Mark slave last-open timestamp immediately to guard local reconcile
   g_slave_last_open_ms = NowMs();

   // cache for display
   g_have_master_cmd = true;
   g_last_cmd_side = mside;
   g_last_cmd_lot_master = StrToDouble(fields[6]);
   g_last_cmd_lot_slave  = lot_slave;
   g_last_cmd_seen_ms = NowMs();
   if(n >= 13)
   {
      g_have_master_th = true;
      g_last_cmd_open_th = (int)StrToInteger(fields[11]);
      g_last_cmd_close_th = (int)StrToInteger(fields[12]);
   }
   else
   {
      g_have_master_th = false;
   }

   // CRITICAL FIX: Use absolute expiration timestamp instead of relative time
   ulong current_ms = NowMs();
   ulong age_ms = (current_ms >= created_ms) ? (current_ms - created_ms) : 0;
   if(age_ms > (ulong)expire_ms)
   {
      // Acknowledge expired so master can rollback
      string ackExpired = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 0, 408);
      FileWriteAllAtomic(PathOpenAckSelf(), ackExpired);
      LogEvent("OPEN_ACK_SLAVE", StringFormat("cmd_id=%s;ok=0;err=%d;reason=EXPIRED;age_ms=%I64u;expire_ms=%d", cmd_id, 408, age_ms, expire_ms));
      return;
   }

   // Policy: ignore CLOSE_ONE from master to prevent premature unilateral close
   if(StringFind(fields[4], "CLOSE_ONE") == 0)
   {
      LogEvent("CLOSE_ONE_IGNORED_POLICY", StringFormat("cmd_id=%s;pair_id=%s", cmd_id, pair_id));
      string ackIgnore = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 0, 461);
      FileWriteAll(PathCloseAckSelf(), ackIgnore);
      return;
   }

   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      {
         int latency = DryDelayMs();
         if(latency>0) Sleep(latency);
         string ackSelf = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0);
         FileWriteAllAtomic(PathOpenAckSelf(), ackSelf);
      }
      return;
   }

   // Real trade
   g_pending_order_comment = ""; // do not expose pairing in comment
   g_pending_pair_id = pair_id;
   int ticket=-1; double price=0.0;
   bool ok = PlaceOrderMaster(mside=="BUY", lot_slave, ticket, price);
   g_pending_pair_id = "";
   string ack = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ack);
   LogEvent("OPEN_ACK_SLAVE", StringFormat("cmd_id=%s;ok=%d;price=%.5f;err=%d", cmd_id, ok?1:0, price, ok?0:GetLastError()));
   if(ok)
   {
      PairMapSelfUpsert(pair_id, ticket);
      CacheUpsert(pair_id, ticket);
      WritePositions();
      CompactPairMapSelf();
   }
}

void SlaveProcessCloseCmd()
{
   if(g_role_conflict) return;
   if(input_role==ROLE_MASTER) return;
   // Account authorization check
   if(input_auth_enabled && !g_account_authorized) return;
   string s;
   if(!FileReadAll(PathCloseCmd(), s)) return;
   // format: version,cmd_id,seq,pair_id,reason,created_ms,expire_ms[,audit...]
   string fields[];
   int n = StringSplit(TrimAll(s), ',', fields);
   if(n < 7) return;
   string cmd_id = fields[1];
   string pair_id = fields[3];
   ulong created_ms = (ulong)StrToDouble(fields[5]);
   int expire_ms = (int)StrToInteger(fields[6]);

    // Saturday quiet window: do not close; ack with fail
   if(IsInSaturdayQuietWindow())
   {
      string ackSat = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 0, 451);
      FileWriteAll(PathCloseAckSelf(), ackSat);
      LogEvent("CLOSE_ACK_SLAVE", StringFormat("cmd_id=%s;ok=0;err=%d;reason=SATURDAY_QUIET", cmd_id, 451));
      return;
   }

    // Idempotency: skip if already acknowledged/processed this close
    string sAckClose;
    if(FileReadAll(PathCloseAckSelf(), sAckClose))
    {
       string af[]; int an = StringSplit(TrimAll(sAckClose), ',', af);
       if(an>=2 && af[1]==cmd_id) return;
    }
    if(g_last_processed_close_cmd_id == cmd_id) return;
    g_last_processed_close_cmd_id = cmd_id;
   // CRITICAL FIX: Use absolute expiration timestamp instead of relative time
   ulong current_ms = NowMs();
   ulong age_ms = (current_ms >= created_ms) ? (current_ms - created_ms) : 0;
   if(age_ms > (ulong)expire_ms)
      return; // expired

   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      {
         int latency = DryDelayMs();
         if(latency>0) Sleep(latency);
         string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0);
         FileWriteAll(PathCloseAckSelf(), ackSelf);
      }
      return;
   }

   bool ok = false;
   if(StringFind(fields[4], "CLOSE_ONE") == 0)
   {
      LogEvent("SLAVE_CLOSE_ONE", StringFormat("cmd_id=%s;pair_id=%s;reason=%s", cmd_id, pair_id, fields[4]));
      ok = CloseSelfByPairId(pair_id);
      if(ok){ PairMapSelfDeleteByPairId(pair_id); WritePositions(); }
   }
   else
   {
      LogEvent("SLAVE_CLOSE_ALL", StringFormat("cmd_id=%s;reason=%s", cmd_id, fields[4]));
      ok = CloseAllByMagic();
      PairMapSelfClearAll();
      WritePositions();
   }
   // Include minimal audit in ACK
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:GetLastError());
   FileWriteAll(PathCloseAckSelf(), ack);
   LogEvent("CLOSE_ACK_SLAVE", StringFormat("cmd_id=%s;ok=%d;err=%d", cmd_id, ok?1:0, ok?0:GetLastError()));
}

void WritePositions()
{
   // Track manual closes by detecting missing orders
   static int g_prev_order_count = -1;
   int current_count = 0;
   
   // Build a map from ticket -> pair_id by cache first, then pair_map file
   string mapContent; string mapLines[]; int mapLn=0;
   if(FileReadAll(PathPairMapSelf(), mapContent))
      mapLn = StringSplit(TrimAll(mapContent), '\n', mapLines);
   string buf = "";
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=g_symbol || OrderMagicNumber()!=g_magic) continue;
      int tkt = OrderTicket();
      string pid = "N/A";
      int cidx = CacheFindIndexByTicket(tkt); if(cidx>=0) pid = g_cache_pair_ids[cidx];
      for(int k=0; k<mapLn; ++k)
      {
         string cols[]; int cn = StringSplit(TrimAll(mapLines[k]), ',', cols);
         if(cn<2) continue;
         if((int)StrToInteger(cols[1]) == tkt) { pid = cols[0]; break; }
      }
      if(pid=="N/A")
      {
         int newest = GetNewestOrderTicket();
         if(newest==tkt)
         {
            for(int k=0; k<mapLn; ++k)
            {
               string cols[]; int cn = StringSplit(TrimAll(mapLines[k]), ',', cols);
               if(cn<2) continue;
               if((int)StrToInteger(cols[1]) == tkt) { pid = cols[0]; break; }
            }
         }
      }
      string side = (OrderType()==OP_BUY)?"BUY":"SELL";
      buf += StringFormat("%s,%d,%s,%s,%.2f,%.5f\n", pid, tkt, g_symbol, side, OrderLots(), OrderOpenPrice());
      current_count++;
   }
   
   // Detect manual close when order count decreases without command
   if(g_prev_order_count >= 0 && current_count < g_prev_order_count)
   {
      int closed_count = g_prev_order_count - current_count;
      // Additional debug: check if this is really a manual close or system issue
      LogEvent("MANUAL_CLOSE_DEBUG", StringFormat("role=%s;prev=%d;current=%d;total_orders=%d;symbol=%s;magic=%d", 
               RoleName(), g_prev_order_count, current_count, OrdersTotal(), g_symbol, g_magic));
      LogEvent("MANUAL_CLOSE_DETECTED", StringFormat("role=%s;closed_orders=%d;prev_count=%d;current_count=%d", 
               RoleName(), closed_count, g_prev_order_count, current_count));
   }
   g_prev_order_count = current_count;
   
   FileWriteAllAtomic(PathPositionsSelf(), buf);
}

// -----------------------------
// Display Monitor
// -----------------------------
string OBJ_PREFIX = "EA_MS_LABEL_";
int    DISPLAY_FONT_SIZE = 9;
int    DISPLAY_LINE_SPACING = 16; // pixels per line
int    DISPLAY_X = 6;
int    DISPLAY_Y_BASE = 24; // top padding
int    DISPLAY_FIRST_LINE_OFFSET = 1; // shift first LINE_0 below MAIN

// Debug buttons geometry (top-left beside monitor)
int    BTN_X = 540;
int    BTN_Y1 = 24;
int    BTN_Y2 = 48;
int    BTN_W = 96;
int    BTN_H = 18;

// Sum Equity display geometry (beside debug buttons)
int    EQUITY_X = 650;
int    EQUITY_Y = 24;
int    EQUITY_W = 200;
int    EQUITY_H = 42;

// Close Only button geometry (below display monitor)
int    CLOSE_ONLY_BTN_X = 6;
int    CLOSE_ONLY_BTN_Y = 240; // Will be adjusted dynamically based on monitor height
int    CLOSE_ONLY_BTN_W = 120;
int    CLOSE_ONLY_BTN_H = 24;

int CooldownRemainSeconds()
{
   if(!(input_role==ROLE_MASTER)) return -1;
   if(g_last_open_time<=0) return 0;
   int elapsed = (int)(TimeCurrent() - g_last_open_time);
   int remain = input_open_cooldown_seconds - elapsed;
   if(remain < 0) remain = 0;
   return remain;
}

void DisplayClearAll()
{
   for(int i=ObjectsTotal()-1; i>=0; --i)
   {
      string nm = ObjectName(i);
      if(StringFind(nm, OBJ_PREFIX) == 0)
         ObjectDelete(0, nm);
   }
}

void DisplayInit()
{
   // Clear and recreate to ensure clean z-order
   DisplayClearAll();
   // Create background first to keep it under following labels (z-order by creation time)
   string bg = OBJ_PREFIX + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(bg, OBJPROP_CORNER, 0);
   ObjectSet(bg, OBJPROP_XDISTANCE, 0);
   ObjectSet(bg, OBJPROP_YDISTANCE, 0);
   ObjectSet(bg, OBJPROP_XSIZE, input_display_width_pixels);
   ObjectSet(bg, OBJPROP_YSIZE, 210);
   ObjectSet(bg, OBJPROP_COLOR, clrWhite);
   ObjectSet(bg, OBJPROP_BACK, false);
   // Then create title label
   string name = OBJ_PREFIX + "MAIN";
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSet(name, OBJPROP_CORNER, 0);
   ObjectSet(name, OBJPROP_XDISTANCE, 6);
   ObjectSet(name, OBJPROP_YDISTANCE, DISPLAY_Y_BASE);
   ObjectSetText(name, "### Display Monitor ###", 9, "Arial", clrBlack);

   // Debug buttons (Master only)
   if(input_debug_buttons_enabled && (input_role==ROLE_MASTER))
   {
      string b1 = OBJ_PREFIX + "BTN_OPEN";
      ObjectCreate(0, b1, OBJ_BUTTON, 0, 0, 0);
      ObjectSet(b1, OBJPROP_CORNER, 0);
      ObjectSet(b1, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X);
      ObjectSet(b1, OBJPROP_YDISTANCE, CLOSE_ONLY_BTN_Y + CLOSE_ONLY_BTN_H + 8);
      ObjectSet(b1, OBJPROP_XSIZE, BTN_W);
      ObjectSet(b1, OBJPROP_YSIZE, BTN_H);
      ObjectSetText(b1, "Open Now", 8, "Arial", clrBlack);

      string b2 = OBJ_PREFIX + "BTN_CLOSE";
      ObjectCreate(0, b2, OBJ_BUTTON, 0, 0, 0);
      ObjectSet(b2, OBJPROP_CORNER, 0);
      ObjectSet(b2, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + BTN_W + 10);
      ObjectSet(b2, OBJPROP_YDISTANCE, CLOSE_ONLY_BTN_Y + CLOSE_ONLY_BTN_H + 8);
      ObjectSet(b2, OBJPROP_XSIZE, BTN_W);
      ObjectSet(b2, OBJPROP_YSIZE, BTN_H);
      ObjectSetText(b2, "Close Now", 8, "Arial", clrBlack);
      
      // Sum Equity Display (below debug buttons)
      string eq_bg = OBJ_PREFIX + "EQUITY_BG";
      ObjectCreate(0, eq_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSet(eq_bg, OBJPROP_CORNER, 0);
      ObjectSet(eq_bg, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X);
      ObjectSet(eq_bg, OBJPROP_YDISTANCE, CLOSE_ONLY_BTN_Y + CLOSE_ONLY_BTN_H + 8 + BTN_H + 8);
      ObjectSet(eq_bg, OBJPROP_XSIZE, EQUITY_W);
      ObjectSet(eq_bg, OBJPROP_YSIZE, EQUITY_H);
      ObjectSet(eq_bg, OBJPROP_COLOR, clrLightGray);
      ObjectSet(eq_bg, OBJPROP_BACK, false);
      
      string eq_label = OBJ_PREFIX + "EQUITY_LABEL";
      ObjectCreate(0, eq_label, OBJ_LABEL, 0, 0, 0);
      ObjectSet(eq_label, OBJPROP_CORNER, 0);
      ObjectSet(eq_label, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + 10);
      ObjectSet(eq_label, OBJPROP_YDISTANCE, CLOSE_ONLY_BTN_Y + CLOSE_ONLY_BTN_H + 8 + BTN_H + 8 + 5);
      ObjectSetText(eq_label, "Profit", 9, "Arial Bold", clrBlack);
      
      string eq_value = OBJ_PREFIX + "EQUITY_VALUE";
      ObjectCreate(0, eq_value, OBJ_LABEL, 0, 0, 0);
      ObjectSet(eq_value, OBJPROP_CORNER, 0);
      ObjectSet(eq_value, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + 10);
      ObjectSet(eq_value, OBJPROP_YDISTANCE, CLOSE_ONLY_BTN_Y + CLOSE_ONLY_BTN_H + 8 + BTN_H + 8 + 22);
      ObjectSetText(eq_value, "$0.00", 12, "Arial Bold", clrDarkGreen);
      
      // Realtime diffOpen/diffClose labels and values (below Profit)
      int diff_base_y = CLOSE_ONLY_BTN_Y + CLOSE_ONLY_BTN_H + 8 + BTN_H + 8 + EQUITY_H + 8;

      // Background for diff section (white)
      string diff_bg = OBJ_PREFIX + "DIFF_BG";
      ObjectCreate(0, diff_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSet(diff_bg, OBJPROP_CORNER, 0);
      ObjectSet(diff_bg, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X);
      ObjectSet(diff_bg, OBJPROP_YDISTANCE, diff_base_y - 6);
      ObjectSet(diff_bg, OBJPROP_XSIZE, EQUITY_W);
      ObjectSet(diff_bg, OBJPROP_YSIZE, 44);
      ObjectSet(diff_bg, OBJPROP_COLOR, clrWhite);
      ObjectSet(diff_bg, OBJPROP_BACK, false);
      string dopen_label = OBJ_PREFIX + "DIFF_OPEN_LABEL";
      ObjectCreate(0, dopen_label, OBJ_LABEL, 0, 0, 0);
      ObjectSet(dopen_label, OBJPROP_CORNER, 0);
      ObjectSet(dopen_label, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + 10);
      ObjectSet(dopen_label, OBJPROP_YDISTANCE, diff_base_y);
      ObjectSetText(dopen_label, "diffOpen", 9, "Arial Bold", clrBlack);

      string dopen_value = OBJ_PREFIX + "DIFF_OPEN_VALUE";
      ObjectCreate(0, dopen_value, OBJ_LABEL, 0, 0, 0);
      ObjectSet(dopen_value, OBJPROP_CORNER, 0);
      ObjectSet(dopen_value, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + 110);
      ObjectSet(dopen_value, OBJPROP_YDISTANCE, diff_base_y);
      ObjectSetText(dopen_value, "0.0", 12, "Arial Bold", clrBlack);

      string dclose_label = OBJ_PREFIX + "DIFF_CLOSE_LABEL";
      ObjectCreate(0, dclose_label, OBJ_LABEL, 0, 0, 0);
      ObjectSet(dclose_label, OBJPROP_CORNER, 0);
      ObjectSet(dclose_label, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + 10);
      ObjectSet(dclose_label, OBJPROP_YDISTANCE, diff_base_y + 20);
      ObjectSetText(dclose_label, "diffClose", 9, "Arial Bold", clrBlack);

      string dclose_value = OBJ_PREFIX + "DIFF_CLOSE_VALUE";
      ObjectCreate(0, dclose_value, OBJ_LABEL, 0, 0, 0);
      ObjectSet(dclose_value, OBJPROP_CORNER, 0);
      ObjectSet(dclose_value, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + 110);
      ObjectSet(dclose_value, OBJPROP_YDISTANCE, diff_base_y + 20);
      ObjectSetText(dclose_value, "0.0", 12, "Arial Bold", clrBlack);
   }

   // Close Only button (Master only)
   if(input_role==ROLE_MASTER)
   {
      string b3 = OBJ_PREFIX + "BTN_CLOSE_ONLY";
      ObjectCreate(0, b3, OBJ_BUTTON, 0, 0, 0);
      ObjectSet(b3, OBJPROP_CORNER, 0);
      ObjectSet(b3, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X);
      ObjectSet(b3, OBJPROP_YDISTANCE, CLOSE_ONLY_BTN_Y);
      ObjectSet(b3, OBJPROP_XSIZE, CLOSE_ONLY_BTN_W);
      ObjectSet(b3, OBJPROP_YSIZE, CLOSE_ONLY_BTN_H);
      ObjectSet(b3, OBJPROP_BGCOLOR, g_close_only_mode ? clrRed : clrWhite);
      ObjectSetText(b3, "Close Only", 9, "Arial", clrBlack);
   }
}

void DisplaySetLine(const int idx, const string text)
{
   string name = OBJ_PREFIX + "LINE_" + IntegerToString(idx);
   if(ObjectFind(0, name) == -1)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, 0);
      ObjectSet(name, OBJPROP_XDISTANCE, DISPLAY_X);
   }
   ObjectSet(name, OBJPROP_YDISTANCE, DISPLAY_Y_BASE + (idx+DISPLAY_FIRST_LINE_OFFSET)*DISPLAY_LINE_SPACING);
   ObjectSetText(name, text, DISPLAY_FONT_SIZE, "Arial", clrBlack);
}

// Soft-wrap a long text into multiple Display lines to avoid clipping
int EstimateMaxCharsPerLine()
{
   int pad = DISPLAY_X + 10; // left padding plus small right padding
   int w = input_display_width_pixels - pad;
   int approxCharPx = 6; // Approx width per character for Arial size 9
   if(w < 80) w = 80;
   return w / approxCharPx;
}

// Returns next line index after writing wrapped segments
int DisplaySetWrappedLines(int lineIndex, const string text)
{
   int maxChars = EstimateMaxCharsPerLine();
   string remaining = text;
   while(StringLen(remaining) > 0)
   {
      int len = StringLen(remaining);
      if(len <= maxChars)
      {
         DisplaySetLine(lineIndex++, remaining);
         break;
      }
      int cut = maxChars;
      // try cut on last space within window
      for(int i=cut; i>0; --i)
      {
         if(StringGetCharacter(remaining, i-1) == ' '){ cut = i; break; }
      }
      if(cut <= 0 || cut > len) cut = maxChars;
      string part = StringSubstr(remaining, 0, cut);
      DisplaySetLine(lineIndex++, part);
      remaining = TrimAll(StringSubstr(remaining, cut));
   }
   return lineIndex;
}

void DisplayTrimLines(const int keep)
{
   for(int i=keep; i<g_display_last_lines; ++i)
   {
      string name = OBJ_PREFIX + "LINE_" + IntegerToString(i);
      if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
   }
   g_display_last_lines = keep;
}

// Auto-detect initial capital from first available balance readings
void AutoDetectInitialCapital()
{
   if(g_auto_capital_detected) return;
   if(input_initial_capital_usd > 0.0) return; // User has set manual value
   
   double master_balance = AccountBalance();
   double slave_balance = 0.0;
   ulong slave_ts = 0;
   bool slave_ok = ReadPeerBalanceFresh(slave_balance, slave_ts);
   
   // Only auto-detect when we have both master and slave balance
   if(master_balance > 0.0 && slave_ok && slave_balance > 0.0)
   {
      g_auto_initial_capital = master_balance + slave_balance;
      g_auto_capital_detected = true;
      if(input_verbose_journal_logs)
         Print("Auto-detected initial capital: $", DoubleToString(g_auto_initial_capital, 2), 
               " (M:$", DoubleToString(master_balance, 2), " + S:$", DoubleToString(slave_balance, 2), ")");
   }
}

// Get effective initial capital (manual or auto-detected)
double GetEffectiveInitialCapital()
{
   if(input_initial_capital_usd > 0.0) return input_initial_capital_usd;
   return g_auto_initial_capital;
}

// Update cached slave balance if fresh data is available
void UpdateCachedSlaveBalance()
{
   double slave_balance = 0.0;
   ulong slave_ts = 0;
   bool slave_ok = ReadPeerBalanceFresh(slave_balance, slave_ts);
   
   if(slave_ok && slave_balance > 0.0)
   {
      g_cached_slave_balance = slave_balance;
      g_has_slave_balance = true;
   }
}

// Get fresh equity from peer account status file
bool ReadPeerEquityFresh(double &equity_out, ulong &ts_out)
{
   equity_out = 0.0; ts_out = 0;
   string s; if(!FileReadAll(PathAccountStatusPeer(), s)) return false;
   string f[]; int n = StringSplit(TrimAll(s), ',', f);
   if(n<4) return false;
   // format: version,balance,equity,updated_ms
   equity_out = StrToDouble(f[2]);
   ts_out = (ulong)StrToDouble(f[3]);
   // freshness: require within EffectiveHeartbeatTimeoutMs
   if((NowMs()-ts_out) > (ulong)EffectiveHeartbeatTimeoutMs()) return false;
   return true;
}

// Update cached slave equity if fresh data is available
void UpdateCachedSlaveEquity()
{
   double slave_equity = 0.0;
   ulong slave_ts = 0;
   bool slave_ok = ReadPeerEquityFresh(slave_equity, slave_ts);
   if(slave_ok && slave_equity > 0.0)
   {
      g_cached_slave_equity = slave_equity;
      g_has_slave_equity = true;
   }
}

// Get cached slave equity (returns last known value, never shows STALE)
double GetCachedSlaveEquity()
{
   return g_has_slave_equity ? g_cached_slave_equity : 0.0;
}

// Get sum of master and slave equity (realtime)
double GetSumEquity()
{
   double master_equity = AccountEquity();
   double slave_equity = 0.0;
   ulong slave_ts = 0;
   
   // Prefer fresh equity; when fresh, also refresh cache
   if(ReadPeerEquityFresh(slave_equity, slave_ts))
   {
      if(slave_equity > 0.0)
      {
         g_cached_slave_equity = slave_equity;
         g_has_slave_equity = true;
      }
      return master_equity + slave_equity;
   }
   
   // Fallback to cached slave equity to avoid flicker when peer inactive
   if(g_has_slave_equity)
      return master_equity + g_cached_slave_equity;
   
   // If no cache yet, return only master equity
   return master_equity;
}

// Get cached slave balance (returns last known value, never shows STALE)
double GetCachedSlaveBalance()
{
   return g_has_slave_balance ? g_cached_slave_balance : 0.0;
}

void DisplayUpdate()
{
   string role = (input_role==ROLE_MASTER)?"MASTER":"SLAVE";
   int spread = SpreadPointsSelf();
   double dOpen = DiffOpenPoints();
   double dClose = DiffClosePoints();
   double aOpen = input_avg_filter_enabled ? SmoothedOpenDiff(dOpen) : dOpen;
   double aClose = input_avg_filter_enabled ? SmoothedCloseDiff(dClose) : dClose;
   // Update peaks and histograms only on master with fresh quotes (lightweight O(1))
   if(input_role==ROLE_MASTER && QuotesFresh())
   {
      if(dOpen > g_peak_open_real) g_peak_open_real = dOpen;
      if(dClose > g_peak_close_real) g_peak_close_real = dClose;
      int idxO = (int)MathFloor(MathMax(0.0, dOpen)); if(idxO>DIFF_HIST_MAX_POINTS) idxO = DIFF_HIST_MAX_POINTS;
      int idxC = (int)MathFloor(MathMax(0.0, dClose)); if(idxC>DIFF_HIST_MAX_POINTS) idxC = DIFF_HIST_MAX_POINTS;
      g_hist_open_counts[idxO]++;
      if(g_hist_open_counts[idxO] > g_mode_open_count) { g_mode_open_count = g_hist_open_counts[idxO]; g_mode_open_index = idxO; }
      g_hist_close_counts[idxC]++;
      if(g_hist_close_counts[idxC] > g_mode_close_count) { g_mode_close_count = g_hist_close_counts[idxC]; g_mode_close_index = idxC; }
   }
   int line = 0;
   DisplaySetLine(line++, StringFormat("role=%s  channel=%s  symbol=%s", role, input_channel_id, g_symbol));
   
   // Account authorization status
   if(input_auth_enabled)
   {
      string auth_status = g_account_authorized ? "AUTHORIZED" : "DENIED";
      string expire_info = "";
      if(g_account_authorized && g_account_expires_at > 0)
      {
         datetime now = TimeCurrent();
         int days_left = (int)((g_account_expires_at - now) / 86400);
         expire_info = StringFormat(" (expires in %d days)", days_left);
      }
      else if(!g_account_authorized && StringLen(g_auth_error_message) > 0)
      {
         expire_info = StringFormat(" (%s)", g_auth_error_message);
      }
      DisplaySetLine(line++, StringFormat("auth=%s%s", auth_status, expire_info));
   }
   string syncTxt = g_peer_alive?"OK":"WAITING";
   int hb_age = (int)(NowMs() - g_peer_hb_ms);
   string activeTxt = g_peer_alive?"YES":"NO";
   DisplaySetLine(line++, StringFormat("sync=%s  peer_hb_age=%dms  active=%s", syncTxt, hb_age, activeTxt));
   line = DisplaySetWrappedLines(line, StringFormat("sync_path=%s", PathChannelRootAbs()));
   if(input_role==ROLE_MASTER)
   {
      DisplaySetLine(line++, StringFormat("lot(m/s)=%.2f/%.2f  side(M)=%s", input_lot_master, input_lot_slave, ((input_master_side==SIDE_BUY)?"BUY":"SELL")));
      DisplaySetLine(line++, StringFormat("open_th=%d  close_th=%d  spread=%d", input_open_threshold_points, input_close_threshold_points, spread));
   }
   else
   {
      if(!g_have_master_cmd) ReadMasterConfigForSlave();
      if(g_have_master_cmd)
      {
         string sideS = (g_last_cmd_side=="BUY")?"SELL":"BUY";
         DisplaySetLine(line++, StringFormat("lot(M/S)=%.2f/%.2f  side(S)=%s", g_last_cmd_lot_master, g_last_cmd_lot_slave, sideS));
         if(g_have_master_th)
            DisplaySetLine(line++, StringFormat("th(M): open=%d close=%d", g_last_cmd_open_th, g_last_cmd_close_th));
      }
      // Show only spread for Slave to avoid policy confusion
      DisplaySetLine(line++, StringFormat("spread=%d", spread));
   }
   if(input_role==ROLE_MASTER)
   {
            string modeStr = "";
      if(input_avg_filter_enabled)
         modeStr = StringFormat("AVG ON | EMA-%d%s | H=%d E=%d CF=%d CD=%dms",
                               input_avg_period, (input_use_prefilter_median?StringFormat(" + Med-%d", input_prefilter_window):""),
                               input_diff_hysteresis_points, input_epsilon_diff_points, input_confirm_ticks, input_avg_signal_cooldown_ms);
      else if(input_raw_stability_enabled)
         modeStr = StringFormat("RAW STABILITY | Ticks=%d Offset=%d Timeout=%dms", 
                               input_raw_stability_ticks, input_raw_hysteresis_offset, input_raw_stability_timeout_ms);
      else
         modeStr = "SIMPLE | RealOnly";

      DisplaySetLine(line++, modeStr);
      
      // Enhanced status display with detailed info
      if(input_avg_filter_enabled)
      {
         double thrOpenEff = (double)(input_open_threshold_points + input_diff_hysteresis_points);
         double thrCloseEff = (double)(input_close_threshold_points + input_diff_hysteresis_points);
         
         // Open status with detailed info
         string stOpen = "READY";
         string openDetail = "";
         if(g_open_pending)
         {
            int timeLeft = (int)((g_open_deadline_ms > NowMs()) ? (g_open_deadline_ms - NowMs()) : 0);
            double needReal = input_real_confirm_enabled ? 
               (MathMax(g_open_snapshot_avg, thrOpenEff) + (double)input_epsilon_diff_points) : thrOpenEff;
            stOpen = StringFormat("PENDING %d/%d (%.0fms)", g_open_ok_count, input_confirm_ticks, timeLeft);
            openDetail = StringFormat(" Need: Avg>=%.1f Real>=%.1f", thrOpenEff, needReal);
         }
         else if(aOpen >= thrOpenEff)
         {
            stOpen = "AVG_TRIGGERED";
            openDetail = StringFormat(" AvgOK: %.1f>=%.1f", aOpen, thrOpenEff);
         }
         
         // Close status with detailed info  
         string stClose = "READY";
         string closeDetail = "";
         if(g_close_pending)
         {
            int timeLeft = (int)((g_close_deadline_ms > NowMs()) ? (g_close_deadline_ms - NowMs()) : 0);
            double needReal = input_real_confirm_enabled ? 
               (MathMax(g_close_snapshot_avg, thrCloseEff) + (double)input_epsilon_diff_points) : thrCloseEff;
            stClose = StringFormat("PENDING %d/%d (%.0fms)", g_close_ok_count, input_confirm_ticks, timeLeft);
            closeDetail = StringFormat(" Need: Avg>=%.1f Real>=%.1f", thrCloseEff, needReal);
         }
         else if(aClose >= thrCloseEff)
         {
            stClose = "AVG_TRIGGERED";
            closeDetail = StringFormat(" AvgOK: %.1f>=%.1f", aClose, thrCloseEff);
         }
         
         DisplaySetLine(line++, StringFormat("Open: Real=%.1f Avg=%.1f Thr=%d+%d=%.0f | %s", 
            dOpen, aOpen, input_open_threshold_points, input_diff_hysteresis_points, thrOpenEff, stOpen));
         if(openDetail != "") DisplaySetLine(line++, "  " + openDetail);
         
         DisplaySetLine(line++, StringFormat("Close: Real=%.1f Avg=%.1f Thr=%d+%d=%.0f | %s", 
            dClose, aClose, input_close_threshold_points, input_diff_hysteresis_points, thrCloseEff, stClose));
         if(closeDetail != "") DisplaySetLine(line++, "  " + closeDetail);
         
         // Signal cooldown status
         if(input_avg_signal_cooldown_ms > 0)
         {
            int openCooldown = (int)((NowMs() > g_last_avg_open_signal_ms) ? 
               (NowMs() - g_last_avg_open_signal_ms) : 0);
            int closeCooldown = (int)((NowMs() > g_last_avg_close_signal_ms) ? 
               (NowMs() - g_last_avg_close_signal_ms) : 0);
            string cooldownStatus = "";
            if(openCooldown < (ulong)input_avg_signal_cooldown_ms)
               cooldownStatus += StringFormat("OpenCD:%dms ", input_avg_signal_cooldown_ms - openCooldown);
            if(closeCooldown < (ulong)input_avg_signal_cooldown_ms)
               cooldownStatus += StringFormat("CloseCD:%dms", input_avg_signal_cooldown_ms - closeCooldown);
            if(cooldownStatus != "") DisplaySetLine(line++, "Signal Cooldown: " + cooldownStatus);
         }
      }
      else if(input_raw_stability_enabled)
      {
         // Raw stability status display with realtime count
         string stOpen = "READY";
         string stClose = "READY";
         
         if(g_raw_open_pending)
         {
            int timeLeft = (int)((g_raw_open_start_ms + (ulong)input_raw_stability_timeout_ms > NowMs()) ? 
                                (g_raw_open_start_ms + (ulong)input_raw_stability_timeout_ms - NowMs()) : 0);
            stOpen = StringFormat("COUNT %d/%d (%.0fms)", g_raw_open_stable_count, input_raw_stability_ticks, timeLeft);
         }
         else if(dOpen >= input_open_threshold_points)
         {
            stOpen = "TRIGGERED";
         }
         
         if(g_raw_close_pending)
         {
            int timeLeft = (int)((g_raw_close_start_ms + (ulong)input_raw_stability_timeout_ms > NowMs()) ? 
                                (g_raw_close_start_ms + (ulong)input_raw_stability_timeout_ms - NowMs()) : 0);
            stClose = StringFormat("COUNT %d/%d (%.0fms)", g_raw_close_stable_count, input_raw_stability_ticks, timeLeft);
         }
         else if(dClose >= input_close_threshold_points)
         {
            stClose = "TRIGGERED";
         }
         
         // Show realtime diff and count status prominently
         DisplaySetLine(line++, StringFormat("Open: %.1f (Thr=%d Reset=%d) | %s", 
            dOpen, input_open_threshold_points, (input_open_threshold_points - input_raw_hysteresis_offset), stOpen));
         DisplaySetLine(line++, StringFormat("Close: %.1f (Thr=%d Reset=%d) | %s", 
            dClose, input_close_threshold_points, (input_close_threshold_points - input_raw_hysteresis_offset), stClose));
      }
      else
      {
         // Simple display for non-averaging mode
         string stOpen = (dOpen >= input_open_threshold_points) ? "TRIGGERED" : "READY";
         string stClose = (dClose >= input_close_threshold_points) ? "TRIGGERED" : "READY";
         DisplaySetLine(line++, StringFormat("Open: %.1f (Thr=%d) | %s", dOpen, input_open_threshold_points, stOpen));
         DisplaySetLine(line++, StringFormat("Close: %.1f (Thr=%d) | %s", dClose, input_close_threshold_points, stClose));
      }
   }
   else
   {
      DisplaySetLine(line++, StringFormat("diffOpen=%.1f  diffClose=%.1f  fresh=%s", dOpen, dClose, (QuotesFresh()?"OK":"STALE")));
   }
   if(g_role_conflict) DisplaySetLine(line++, "role_conflict=YES (single-instance per channel)");
   if(input_role==ROLE_MASTER)
   {
      int cd = CooldownRemainSeconds();
      string cdLeft = (cd>=0) ? IntegerToString(cd) : "-";
      // Close cooldown left
      int closeLeft = -1;
      {
         if(g_last_pair_both_open_time>0)
         {
            int el = (int)(TimeCurrent() - g_last_pair_both_open_time);
            int rem = input_close_cooldown_seconds - el; if(rem<0) rem=0; closeLeft = rem;
         }
      }
      // Split into two lines to avoid clipping on narrow charts
      /* DisplaySetLine(line++, StringFormat("open_cooldown=%ds left=%s  close_cooldown=%ds left=%s",
         input_open_cooldown_seconds, cdLeft, input_close_cooldown_seconds, (closeLeft>=0?IntegerToString(closeLeft):"0")));
      DisplaySetLine(line++, StringFormat("max_pairs=%d  open_now=%d", input_max_open_pairs, CountOpenPairs())); */
      
      // Performance Metrics
      /*   double success_rate = (g_total_opens>0) ? ((double)g_successful_opens / g_total_opens * 100.0) : 0.0;
         ulong avg_ack = (g_total_opens>0) ? g_avg_ack_time_ms : 0;
         DisplaySetLine(line++, StringFormat("Success Rate: %.1f%% (%I64u/%I64u) AvgAck: %I64ums", 
                        success_rate, g_successful_opens, g_total_opens, avg_ack));
         DisplaySetLine(line++, StringFormat("Rollbacks: %I64u", g_rollback_count));

      // Peak real diffs and histogram-based suggestions
      int peakOpenPts = (int)MathFloor(MathMax(0.0, g_peak_open_real));
      int peakClosePts = (int)MathFloor(MathMax(0.0, g_peak_close_real));
      DisplaySetLine(line++, StringFormat("Peak Real: open=%.1f close=%.1f", g_peak_open_real, g_peak_close_real));
      DisplaySetLine(line++, StringFormat("Mode Open[0..%d]=%d cnt=%I64u (suggest=%d)", peakOpenPts, g_mode_open_index, g_mode_open_count, g_mode_open_index));
      DisplaySetLine(line++, StringFormat("Mode Close[0..%d]=%d cnt=%I64u (suggest=%d)", peakClosePts, g_mode_close_index, g_mode_close_count, g_mode_close_index));
      if(g_weighted_open_suggest>0 || g_weighted_close_suggest>0)
      {
         DisplaySetLine(line++, StringFormat("Weighted Suggest: open=%d close=%d (alpha=%.1f W=%d min=%d)",
            g_weighted_open_suggest, g_weighted_close_suggest, g_weighted_alpha, g_weighted_window, g_weighted_min_count));
      } */
   }
   int effMode = DryMode();
   string effModeStr = (effMode==DRY_NONE?"NONE":(effMode==DRY_WRITE_CMD_ONLY?"WRITE_CMD_ONLY":"WRITE_CMD_AND_FAKE_ACK"));
   // DisplaySetLine(line++, StringFormat("dry_run=%s mode=%s", (DryEnabled()?"ON":"OFF"), effModeStr));
   if(input_role==ROLE_MASTER)
   {
      // Update scheduled close only mode state
      UpdateScheduledCloseOnlyMode();
      
      string closeOnlyStatus = "";
      if(input_scheduled_close_only_enabled)
      {
         string scheduleInfo = StringFormat("%s-%s", input_close_only_start_time, input_close_only_end_time);
         if(g_scheduled_close_only_active)
         {
            closeOnlyStatus = StringFormat("ON (SCHEDULED %s)", scheduleInfo);
         }
         else
         {
            // Outside scheduled period - show manual state
            string manualState = g_close_only_mode ? "ON" : "OFF";
            closeOnlyStatus = StringFormat("%s (MANUAL | SCHEDULE %s)", manualState, scheduleInfo);
         }
      }
      else
      {
         closeOnlyStatus = g_close_only_mode ? "ON (MANUAL)" : "OFF";
      }
      
      DisplaySetLine(line++, StringFormat("close_only_mode=%s", closeOnlyStatus));
      
      // Update cached slave balance and auto-detect initial capital if needed
      UpdateCachedSlaveBalance();
      AutoDetectInitialCapital();
      
      // Capital and profit display (Master only)
      /* double master_balance = AccountBalance();
      double slave_balance = GetCachedSlaveBalance();
      
      double sum_balance = master_balance + slave_balance;
      double effective_initial_capital = GetEffectiveInitialCapital();
      double net_profit = sum_balance - effective_initial_capital;
      
      string capital_source = (input_initial_capital_usd > 0.0) ? "Manual" : (g_auto_capital_detected ? "Auto" : "Pending");
      string slave_status = g_has_slave_balance ? "" : " [WAITING]";
      DisplaySetLine(line++, StringFormat("Initial Capital: $%.2f [%s]", effective_initial_capital, capital_source));
      DisplaySetLine(line++, StringFormat("Sum Balance: $%.2f (M:$%.2f + S:$%.2f%s)", 
         sum_balance, master_balance, slave_balance, slave_status));
      DisplaySetLine(line++, StringFormat("Net Profit: $%.2f", net_profit)); */
   }
   
   // Update Profit and Diff Displays (Master only, when debug buttons enabled)
   if(input_debug_buttons_enabled && input_role==ROLE_MASTER)
   {
      string eq_value = OBJ_PREFIX + "EQUITY_VALUE";
      if(ObjectFind(0, eq_value) != -1)
      {
         // Keep caches fresh opportunistically
         UpdateCachedSlaveEquity();
         UpdateCachedSlaveBalance();

         // Realtime sums
         double master_equity = AccountEquity();
         double master_balance = AccountBalance();
         double slave_equity = 0.0; ulong slave_eq_ts = 0; bool eq_ok = ReadPeerEquityFresh(slave_equity, slave_eq_ts);
         double slave_balance = 0.0; ulong slave_bal_ts = 0; bool bal_ok = ReadPeerBalanceFresh(slave_balance, slave_bal_ts);
         if(!eq_ok && g_has_slave_equity) slave_equity = g_cached_slave_equity;
         if(!bal_ok && g_has_slave_balance) slave_balance = g_cached_slave_balance;

         double sum_equity = master_equity + slave_equity;
         double sum_balance = master_balance + slave_balance;
         double profit_value = sum_equity - sum_balance;

         // Color by PnL
         color profit_color = (profit_value>0.0? clrDarkGreen : (profit_value<0.0? clrDarkRed : clrBlack));
         string profit_text = StringFormat("$%.2f", profit_value);
         ObjectSetText(eq_value, profit_text, 12, "Arial Bold", profit_color);

         // Update realtime diffOpen/diffClose values with color coding
         // Use precomputed dOpen/dClose from earlier in DisplayUpdate to avoid shadowing
         string dopen_value = OBJ_PREFIX + "DIFF_OPEN_VALUE";
         string dclose_value = OBJ_PREFIX + "DIFF_CLOSE_VALUE";
         color dOpenColor = (dOpen>0.0? clrDarkGreen : (dOpen<0.0? clrRed : clrBlack));
         color dCloseColor = (dClose>0.0? clrDarkGreen : (dClose<0.0? clrRed : clrBlack));
         if(ObjectFind(0, dopen_value) != -1)
            ObjectSetText(dopen_value, StringFormat("%.1f", dOpen), 12, "Arial Bold", dOpenColor);
         if(ObjectFind(0, dclose_value) != -1)
            ObjectSetText(dclose_value, StringFormat("%.1f", dClose), 12, "Arial Bold", dCloseColor);
      }
   }
   
   DisplayTrimLines(line);

   // Resize background to cover lines
   string bg = OBJ_PREFIX + "BG";
   if(ObjectFind(0, bg) != -1)
   {
      int h = (DISPLAY_FIRST_LINE_OFFSET + line) * DISPLAY_LINE_SPACING + 38;
      ObjectSet(bg, OBJPROP_XDISTANCE, 0);
      ObjectSet(bg, OBJPROP_YDISTANCE, 0);
      ObjectSet(bg, OBJPROP_XSIZE, input_display_width_pixels);
      ObjectSet(bg, OBJPROP_YSIZE, h);
      ObjectSet(bg, OBJPROP_COLOR, clrWhite);
      ObjectSet(bg, OBJPROP_BACK, false);
   }

   // Update Close Only button position and color (Master only)
   if(input_role==ROLE_MASTER)
   {
      string btnCloseOnly = OBJ_PREFIX + "BTN_CLOSE_ONLY";
      if(ObjectFind(0, btnCloseOnly) != -1)
      {
         int bg_height = (DISPLAY_FIRST_LINE_OFFSET + line) * DISPLAY_LINE_SPACING + 38;
         int btn_y = bg_height + 10; // 10 pixels below monitor
         ObjectSet(btnCloseOnly, OBJPROP_YDISTANCE, btn_y);
         
         // Update button color and text based on scheduled mode
         if(input_scheduled_close_only_enabled)
         {
            if(g_scheduled_close_only_active)
            {
               // During scheduled period - force ON, disable button
               ObjectSet(btnCloseOnly, OBJPROP_BGCOLOR, clrRed);
               ObjectSetText(btnCloseOnly, "Scheduled ON", 9, "Arial", clrBlack);
            }
            else
            {
               // Outside scheduled period - allow manual control
               ObjectSet(btnCloseOnly, OBJPROP_BGCOLOR, g_close_only_mode ? clrRed : clrWhite);
               string btnText = g_close_only_mode ? "Manual ON" : "Manual OFF";
               ObjectSetText(btnCloseOnly, btnText, 9, "Arial", clrBlack);
            }
         }
         else
         {
            ObjectSet(btnCloseOnly, OBJPROP_BGCOLOR, g_close_only_mode ? clrRed : clrWhite);
            ObjectSetText(btnCloseOnly, "Close Only", 9, "Arial", clrBlack);
         }

         // Reposition debug buttons under Close Only button (Master only)
         if(input_debug_buttons_enabled)
         {
            string btnOpen = OBJ_PREFIX + "BTN_OPEN";
            string btnClose = OBJ_PREFIX + "BTN_CLOSE";
            int open_y = btn_y + CLOSE_ONLY_BTN_H + 8;
            int close_y = open_y; // same row as open
            if(ObjectFind(0, btnOpen) != -1)
            {
               ObjectSet(btnOpen, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X);
               ObjectSet(btnOpen, OBJPROP_YDISTANCE, open_y);
            }
            if(ObjectFind(0, btnClose) != -1)
            {
               ObjectSet(btnClose, OBJPROP_XDISTANCE, CLOSE_ONLY_BTN_X + BTN_W + 10);
               ObjectSet(btnClose, OBJPROP_YDISTANCE, close_y);
            }
         }
      }
   }
}

// ---------------------------------
// Debug: master force open/close now
// ---------------------------------
void MasterOpenNow()
{
   if(!(input_role==ROLE_MASTER)) return;
   // Update scheduled close only mode state
   UpdateScheduledCloseOnlyMode();
   // Close Only mode: prevent new orders
   if(g_close_only_mode) return;

   string cmd_id = NewCmdId();
   g_last_cmd_id = cmd_id;
   LogEvent("OPEN_TRIGGER", StringFormat("source=MANUAL_BUTTON;cmd_id=%s", cmd_id));

   // Prepare timing
   ulong created_ms = NowMs();
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0) ? DryOverrideExpireMs() : input_cmd_expire_ms;
   if(expire_ms <= 0) expire_ms = 60000; // ensure sane expiry

   // Optional: set comment placeholder
   g_pending_order_comment = "MS:OPEN|PAIR:" + cmd_id;

   // Dry-run path mirrors auto flow ordering: pretend open first, then write open_cmd
   if(DryEnabled())
   {
      // Pretend master open succeeded
      g_last_open_time = TimeCurrent();
      // Write audited open_cmd
      double diffOpenAudit = DiffOpenPoints();
      string lineDR = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.1f\n",
         cmd_id,(long)g_seq,cmd_id,g_symbol,((input_master_side==SIDE_BUY)?"BUY":"SELL"),input_lot_master,input_lot_slave,input_slippage_points,created_ms,expire_ms,input_open_threshold_points,input_close_threshold_points,
         g_self_bid,g_self_ask,g_peer_bid,g_peer_ask,diffOpenAudit);
      FileWriteAllAtomic(PathOpenCmd(), lineDR);
      LogEvent("OPEN_CMD", StringFormat("cmd_id=%s;side=%s;lotM=%.2f;lotS=%.2f;expire_ms=%d;mb=%.5f;ma=%.5f;sb=%.5f;sa=%.5f", cmd_id, ((input_master_side==SIDE_BUY)?"BUY":"SELL"), input_lot_master, input_lot_slave, expire_ms, g_self_bid, g_self_ask, g_peer_bid, g_peer_ask));
      g_waiting_slave_open_ack = true; g_pending_open_cmd_id = cmd_id; g_pending_open_created_ms = created_ms; g_rollback_initiated=false; 
      g_last_peer_open_ack_ms = 0; // reset grace timer
      // Consolidated grace to prevent immediate close/reconcile
      g_open_grace_until_ms = NowMs() + (ulong)MathMax(input_ack_timeout_ms + 2000, input_close_cooldown_seconds * 1000);
      g_early_warning_sent = false;
      // Ack self
      string ackSelfDR = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0);
      FileWriteAllAtomic(PathOpenAckSelf(), ackSelfDR);
      LogEvent("OPEN_ACK_MASTER", StringFormat("cmd_id=%s;ok=1;price=0.0;err=0", cmd_id));
      // Do not force debug hold; allow auto-close to operate normally
      if(input_debug_buttons_enabled) g_debug_hold_open = false;
      g_pending_pair_id = "";
      return;
   }

   // Real trading: open first, then notify slave (align with auto flow)
   int ticket=-1; double price=0.0;
   bool ok = PlaceOrderMaster((input_master_side==SIDE_BUY), input_lot_master, ticket, price);
   string ackSelf = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ackSelf);
   LogEvent("OPEN_ACK_MASTER", StringFormat("cmd_id=%s;ok=%d;price=%.5f;err=%d", cmd_id, ok?1:0, price, ok?0:GetLastError()));
   if(!ok)
   {
      g_last_open_time = TimeCurrent();
      g_pending_pair_id = "";
      return;
   }

   // Master open succeeded -> write mapping and positions
   g_last_open_time = TimeCurrent();
   PairMapSelfUpsert(cmd_id, ticket);
   CacheUpsert(cmd_id, ticket);
   WritePositions();
   CompactPairMapSelf();

   // Notify slave with audited open_cmd and start ACK wait
   double diffOpenAudit2 = DiffOpenPoints();
   string line = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.1f\n",
         cmd_id,(long)g_seq,cmd_id,g_symbol,((input_master_side==SIDE_BUY)?"BUY":"SELL"),input_lot_master,input_lot_slave,input_slippage_points,created_ms,expire_ms,input_open_threshold_points,input_close_threshold_points,
         g_self_bid,g_self_ask,g_peer_bid,g_peer_ask,diffOpenAudit2);
   FileWriteAllAtomic(PathOpenCmd(), line);
   LogEvent("OPEN_CMD", StringFormat("cmd_id=%s;side=%s;lotM=%.2f;lotS=%.2f;expire_ms=%d;mb=%.5f;ma=%.5f;sb=%.5f;sa=%.5f", cmd_id, ((input_master_side==SIDE_BUY)?"BUY":"SELL"), input_lot_master, input_lot_slave, expire_ms, g_self_bid, g_self_ask, g_peer_bid, g_peer_ask));
   g_waiting_slave_open_ack = true; g_pending_open_cmd_id = cmd_id; g_pending_open_created_ms = created_ms; g_rollback_initiated=false; 
   // Consolidated grace to prevent immediate close/reconcile
   g_open_grace_until_ms = NowMs() + (ulong)MathMax(input_ack_timeout_ms + 2000, input_close_cooldown_seconds * 1000);
   g_early_warning_sent = false;

   g_pending_pair_id = "";
   // Do not force debug hold; allow auto-close to operate normally
   if(input_debug_buttons_enabled) g_debug_hold_open = false;
}

void MasterCloseNow()
{
   if(!(input_role==ROLE_MASTER)) return;
   g_debug_hold_open = false;
   
   // Block manual close during Saturday quiet window to avoid side-only close
   if(IsInSaturdayQuietWindow())
   {
      LogEvent("CLOSE_CMD_BLOCKED", "reason=SATURDAY_QUIET");
      return;
   }
   
   LogEvent("CLOSE_TRIGGER", "source=MANUAL_BUTTON");

   string cmd_id = NewCmdId(); ulong created_ms = NowMs();
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0) ? DryOverrideExpireMs() : input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
   FileWriteAllAtomic(PathCloseCmd(), line);
   LogEvent("CLOSE_CMD", StringFormat("cmd_id=%s;reason=MANUAL_BUTTON;action=CLOSE", cmd_id));

   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      {
         string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0);
         FileWriteAll(PathCloseAckSelf(), ackSelf);
      }
      return;
   }

   bool ok = CloseAllByMagic();
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:GetLastError());
   FileWriteAll(PathCloseAckSelf(), ack);
}

// Click handler for debug buttons and Close Only button
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!(input_role==ROLE_MASTER)) return;
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == OBJ_PREFIX + "BTN_CLOSE_ONLY")
      {
         // Update scheduled state first
         UpdateScheduledCloseOnlyMode();
         
         // Check if user can toggle (not during scheduled period)
         if(!CanUserToggleCloseOnly())
         {
            // Reset button state and show it's disabled during scheduled period
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            LogEvent("CLOSE_ONLY_BUTTON", "disabled_during_scheduled_period");
            return;
         }
         
         // Toggle Close Only mode (allow manual control outside scheduled period)
         g_close_only_mode = !g_close_only_mode;
         
         // Log the mode change
         string source = input_scheduled_close_only_enabled ? "manual_outside_schedule" : "manual";
         LogEvent("CLOSE_ONLY_MODE", StringFormat("enabled=%s;source=%s", g_close_only_mode ? "true" : "false", source));
         
         // Update button color immediately
         ObjectSet(sparam, OBJPROP_BGCOLOR, g_close_only_mode ? clrRed : clrWhite);
         // Reset button state (not pressed)
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(input_debug_buttons_enabled)
      {
         if(sparam == OBJ_PREFIX + "BTN_OPEN") { MasterOpenNow(); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
         else if(sparam == OBJ_PREFIX + "BTN_CLOSE") { MasterCloseNow(); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      }
   }
}

// -----------------------------
// Lifecycle
// -----------------------------
int OnInit()
{
   g_symbol = (input_symbol=="" ? Symbol() : input_symbol);
   g_digits = (int)MarketInfo(g_symbol, MODE_DIGITS);
   g_point  = MarketInfo(g_symbol, MODE_POINT);
   g_magic  = input_magic_number_base + (int)StringGetCharacter(input_channel_id, 0);

   // Require Auto Trading enabled at terminal and EA levels
   bool terminalAuto = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool programAuto = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   if(!terminalAuto || !programAuto)
   {
      if(input_verbose_journal_logs) Alert("Auto Trading is disabled. Enable AutoTrading and 'Allow live trading'.");
      return(INIT_FAILED);
   }

   FolderEnsure();
   
   // Account Authorization Check (first time)
   if(input_auth_enabled)
   {
      if(input_verbose_journal_logs)
         Print("[AUTH] Checking account authorization...");
      
      if(!CheckAccountAuthorization())
      {
         string error_msg = StringFormat("Account %d is not authorized: %s", AccountNumber(), g_auth_error_message);
         Print("[AUTH ERROR] ", error_msg);
         Alert("EA Authorization Failed: " + error_msg);
         return(INIT_FAILED);
      }
      
      if(input_verbose_journal_logs)
      {
         string expire_info = (g_account_expires_at > 0) ? 
            StringFormat(" (expires: %s)", TimeToString(g_account_expires_at)) : " (no expiry)";
         Print("[AUTH] Account ", AccountNumber(), " authorized", expire_info);
      }
   }
   
   if(!AcquireRoleLock()) { g_role_conflict = true; }
   DisplayInit();
   EventSetTimer(1); // 1-second timer for background tasks; OnTick handles fast path
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // best effort: release lock
   FileDelete(PathRoleLock(), FILE_COMMON);
   DisplayClearAll();
}

void OnTimer()
{
   static int timer_count = 0;
   timer_count++;
   
   // === CRITICAL OPERATIONS - ทุกครั้ง ===
   
   // Account Authorization Check (every 24 hours)
   if(ShouldRefreshAuthorization())
   {
      if(input_verbose_journal_logs)
         Print("[AUTH] Refreshing account authorization (24h check)...");
      
      if(!CheckAccountAuthorization())
      {
         string error_msg = StringFormat("Account %d authorization expired or revoked: %s", AccountNumber(), g_auth_error_message);
         Print("[AUTH ERROR] ", error_msg);
         Alert("EA Authorization Lost: " + error_msg);
         
         // Stop EA operations but don't deinitialize to allow manual intervention
         LogEvent("AUTH_REVOKED", StringFormat("account=%d;error=%s", AccountNumber(), g_auth_error_message));
      }
      else if(input_verbose_journal_logs)
      {
         string expire_info = (g_account_expires_at > 0) ? 
            StringFormat(" (expires: %s)", TimeToString(g_account_expires_at)) : " (no expiry)";
         Print("[AUTH] Account ", AccountNumber(), " authorization refreshed", expire_info);
      }
   }
   
   WriteHeartbeat();
   UpdatePeerStatus();
   if(!g_role_conflict) WriteRoleLock();
   
   // Position tracking - CRITICAL สำหรับ reconciliation
   WritePositions();
   CacheCompactCurrentOrders();
   CompactPairMapSelf();
   RebuildPairMapSelfFromCache();
   WritePositions(); // เขียนอีกครั้งหลัง rebuild
   
   // Reconciliation - ลดความถี่เป็นทุก 3 วินาที
   if(timer_count % 3 == 0)
   {
      MasterReconcilePositions();
      if(input_role==ROLE_SLAVE)
      {
         SlaveLocalReconcile();
      }
   }
   
   // === LESS CRITICAL - ทุก 3 วินาที ===
   if(timer_count % 3 == 0)
   {
      LogsCleanupRetention();
      WriteMasterConfig();
      if(!(input_role==ROLE_MASTER)) ReadMasterConfigForSlave();
   }
   
   // Weighted suggest refresh (master only, infrequent)
   if(input_role==ROLE_MASTER)
   {
      ulong noww = NowMs();
      if(noww - g_last_weighted_suggest_ms >= (ulong)g_weighted_refresh_ms)
      {
         g_last_weighted_suggest_ms = noww;
         int peakO = (int)MathFloor(MathMax(0.0, g_peak_open_real));
         int peakC = (int)MathFloor(MathMax(0.0, g_peak_close_real));
         int W = (g_weighted_window<1?1:g_weighted_window);
         if((W % 2)==0) W++;
         // Open weighted suggest
         double bestScoreO = -1.0; int bestIdxO = 0;
         for(int i=1;i<=peakO && i<=DIFF_HIST_MAX_POINTS;i++)
         {
            int lo = i - W; if(lo<1) lo=1; int hi = i + W; if(hi>DIFF_HIST_MAX_POINTS) hi=DIFF_HIST_MAX_POINTS; if(hi>peakO) hi=peakO;
            ulong sum=0; for(int j=lo;j<=hi;j++) sum += g_hist_open_counts[j];
            if(sum < (ulong)g_weighted_min_count) continue;
            double score = MathPow((double)i, g_weighted_alpha) * (double)sum;
            if(score > bestScoreO){ bestScoreO=score; bestIdxO=i; }
         }
         g_weighted_open_suggest = bestIdxO;
         // Close weighted suggest
         double bestScoreC = -1.0; int bestIdxC = 0;
         for(int i=1;i<=peakC && i<=DIFF_HIST_MAX_POINTS;i++)
         {
            int lo = i - W; if(lo<1) lo=1; int hi = i + W; if(hi>DIFF_HIST_MAX_POINTS) hi=DIFF_HIST_MAX_POINTS; if(hi>peakC) hi=peakC;
            ulong sum=0; for(int j=lo;j<=hi;j++) sum += g_hist_close_counts[j];
            if(sum < (ulong)g_weighted_min_count) continue;
            double score = MathPow((double)i, g_weighted_alpha) * (double)sum;
            if(score > bestScoreC){ bestScoreC=score; bestIdxC=i; }
         }
         g_weighted_close_suggest = bestIdxC;
      }
   }
   
   // === SCHEDULED CLOSE ONLY - ทุก 30 วินาที (เพื่อประสิทธิภาพ) ===
   if(timer_count % 30 == 0 && input_role==ROLE_MASTER && (input_scheduled_close_only_enabled || input_sat_close_only_enabled))
   {
      UpdateScheduledCloseOnlyMode();
   }
   
   // Check end-of-day histogram write
   MaybeWriteDailyHistogram();

   DisplayUpdate();
}

void OnTick()
{
   WriteQuotes();
   ReadPeerQuotes(); // refresh peer cache asap
   UpdatePeerStatus();
   if(input_role==ROLE_MASTER)
   {
      MaybeOpenPair();
      MaybeClosePair();
      MasterWatchdogOpen(); // ย้ายมาจาก OnTimer() เพื่อ check บ่อยขึ้น
   }
   else
   {
      ReadMasterConfigForSlave();
      SlaveProcessOpenCmd();
      SlaveProcessCloseCmd();
   }
   DisplayUpdate();
}