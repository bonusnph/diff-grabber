//+------------------------------------------------------------------+
//|                                                 Diff-Grabber.mq4 |
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
// input string input_shared_dir               = "";            // Scope: Both — legacy (unused); Common Files is used by default
// input string input_symbol                   = "";            // Scope: Both — empty uses current chart symbol
// input bool   input_verbose_journal_logs     = true;          // Scope: Both — emit concise Journal logs for key events

// File logging (per-channel)
// input bool   input_enable_file_logs         = true;          // Scope: Both — write debug logs to Common Files
// input int    input_log_retain_hours         = 24;            // Scope: Both — retain logs newer than N hours

// Display monitor width (pixels)
// input int    input_display_width_pixels      = 520;          // Scope: Both — width of Display Monitor background (pixels)

// Master decision parameters
// input int    input_slippage_points          = 10;            // Scope: Both — slippage (points)
input MasterSide input_master_side          = SIDE_SELL;      // Scope: Master — master direction (Slave auto-opposite)
input double input_lot_master               = 0.01;          // Scope: Master — lot size for master orders
input double input_lot_slave                = 0.01;          // Scope: Master — advised lot for Slave; Slave ignores local lot input
input int    input_open_threshold_points    = 30;            // Scope: Master — open threshold (points)
input int    input_close_threshold_points   = 30;            // Scope: Master — close threshold (points)
// input int    input_open_cooldown_seconds    = 7200;           // Scope: Master — open cooldown after an open
// input int    input_close_cooldown_seconds   = 60;            // Scope: Master — close cooldown after both sides opened
// input int    input_max_open_pairs           = 1;             // Scope: Master — max concurrent pairs

// Averaged diff gating (Master-only)
input bool   input_avg_filter_enabled       = false;         // Scope: Master — enable EMA-based averaged diff gating
// input int    input_avg_period               = 9;             // Scope: Master — EMA period (ticks)
// input bool   input_use_prefilter_median     = true;          // Scope: Master — apply median pre-filter before EMA
// input int    input_prefilter_window         = 3;             // Scope: Master — median window (odd 3/5)
// input bool   input_real_confirm_enabled     = true;          // Scope: Master — require real diff confirmation after averaged trigger
// input int    input_confirm_ticks            = 2;             // Scope: Master — consecutive ticks to confirm
// input int    input_confirm_timeout_ms       = 300;           // Scope: Master — max wait for confirmation (ms)
// input int    input_diff_hysteresis_points   = 0;             // Scope: Master — hysteresis added to thresholds when averaging is enabled (points)
// input int    input_epsilon_diff_points      = 1;             // Scope: Master — small margin for real confirm (points)
// input int    input_avg_signal_cooldown_ms   = 400;           // Scope: Master — signal-level cooldown after order (ms)

// Quality guards
// input int    input_max_spread_points_self   = 50;            // Scope: Master — block if own spread exceeds (points)
// input int    input_max_spread_points_peer   = 50;            // Scope: Master — check peer spread before opening (points)
// input int    input_quotes_fresh_ms          = 400;           // Scope: Master — maximum acceptable quote age (ms)
// input int    input_file_poll_ms             = 5;             // Scope: Master — background file polling cadence (ms)
// input int    input_magic_number_base        = 123456;        // Scope: Master — magic base per channel/symbol
// input bool   input_retry_on_requote         = true;          // Scope: Master — retry on requote/off quotes
// input int    input_max_retries              = 20;             // Scope: Master — max retry attempts

// Smart Sync timeouts
// input int    input_cmd_expire_ms            = 30000;         // Scope: Master — command expiry (ms)
// input int    input_ack_timeout_ms           = 10000;          // Scope: Master — ack wait timeout (ms)
// input int    input_heartbeat_timeout_ms     = 3000;          // Scope: Master — peer heartbeat stale threshold (ms)
// input ReconcileMode input_reconcile_mode   = RECONCILE_CLOSE;// Scope: Master — desync handling policy (CLOSE/REOPEN)
// input int    input_reconcile_interval_ms    = 500;           // Scope: Master — reconcile cadence (ms)
// input int    input_reconcile_freeze_seconds = 8;             // Scope: Master — freeze reconcile after both sides opened (seconds)
// input int    input_journal_rotate_max_kb    = 256;           // Scope: Master — journal rotation size (KB)

// Dry Run (configured on Master only; Slave uses master's config automatically)
// input bool   input_dry_run_enabled          = false;         // Scope: Master — enable Dry Run (no real trading)
// input DryRunHandshakeMode input_dry_run_handshake_mode = DRY_NONE; // Scope: Master — NONE/WRITE_CMD_ONLY/WRITE_CMD_AND_FAKE_ACK
// input int    input_dry_run_inject_delay_ms  = 0;             // Scope: Master — inject IO delay (ms)
// input int    input_dry_run_drop_rate_percent= 0;             // Scope: Master — chance to drop cmd/ack writes (%)
// input int    input_dry_run_override_cmd_expire_ms = 0;       // Scope: Master — override cmd expiry in Dry Run (ms)
// input bool   input_dry_run_suppress_heartbeat   = false;     // Scope: Master — suppress heartbeat for testing

// Debug UI (Master only)
// input bool   input_debug_buttons_enabled     = false;        // Scope: Master — show Open/Close test buttons (simulates diffOpen/diffClose)

// Extended controls (Master-only; synced to Slave via config):
// input double input_min_balance_usd           = 0.00;         // Scope: Master — minimum balance required on BOTH peers to allow new open

// -----------------------------
// Globals
// -----------------------------
string g_symbol;
int    g_digits;
double g_point;
int    g_magic;
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
// Reconcile timer
ulong  g_last_reconcile_ms = 0;
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

double PointsFromPriceDiff(double priceDiff)
{
   if(g_point <= 0.0) return 0.0;
   return priceDiff / g_point;
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
   
   // CRITICAL: Skip reconcile during grace period to prevent immediate close after open
   if(NowMs() < g_open_grace_until_ms) { 
      g_prev_self_pairs = CountOpenPairs(); 
      g_prev_peer_pairs = PeerOpenCount(); 
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
   if(manualDrop) LogEvent("RECONCILE_SKIP", StringFormat("reason=MANUAL_DROP;selfNow=%d;peerNow=%d;prevSelf=%d;prevPeer=%d", selfNow, peerNow, g_prev_self_pairs, g_prev_peer_pairs));
   // Skip entirely while waiting for slave ACK within timeout window (unless manual drop)
   if(!manualDrop && g_waiting_slave_open_ack && (NowMs()-g_pending_open_created_ms) <= (ulong)input_ack_timeout_ms) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
   // Grace period just after peer ack open (unless manual drop)
   if(!manualDrop && g_last_peer_open_ack_ms>0 && (NowMs()-g_last_peer_open_ack_ms) < (ulong)input_ack_timeout_ms) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
   // In debug hold, reconcile only when manual close detected (pair count drop)
   if(input_debug_buttons_enabled && g_debug_hold_open)
   {
      if(!manualDrop) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
   }
   if((NowMs()-g_last_reconcile_ms) < (ulong)input_reconcile_interval_ms) { g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return; }
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
         // ENHANCED: Add throttling to prevent reconcile loop
         static ulong last_peer_close_ms = 0;
         if((NowMs() - last_peer_close_ms) < 2000) { // 2 second throttle
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
         string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
         string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, pickPair, "CLOSE_ONE", created_ms, expire_ms);
         FileWriteAllAtomic(PathCloseCmd(), line);
         LogEvent("RECONCILE_CLOSE_PEER_EXTRA", StringFormat("pair_id=%s;cmd_id=%s", pickPair, cmd_id));
         if(DryEnabled()) { if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf);} g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
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
   string line = StringFormat("%I64u,%d,%d,%d,%s,%.2f,%.2f\n", NowMs(), __MQLBUILD__, AccountNumber(), g_magic, "1.0.0", bal, eq);
   FileWriteAll(PathHeartbeatSelf(), line);

   // Also write a compact account status file
   string acc = StringFormat("1,%.2f,%.2f,%I64u\n", bal, eq, NowMs());
   FileWriteAll(PathAccountStatusSelf(), acc);
}

void WriteMasterConfig()
{
   if(!(input_role==ROLE_MASTER)) return;
   // version,symbol,master_side,lot_master,lot_slave,open_th,close_th,cooldown,max_pairs,updated_ms,dry_enabled,dry_mode,dry_delay_ms,dry_drop,dry_override_expire_ms,dry_suppress_hb,
   // max_spread_self,max_spread_peer,quotes_fresh_ms,file_poll_ms,retry_on_requote,max_retries,cmd_expire_ms,ack_timeout_ms,heartbeat_timeout_ms,reconcile_mode,reconcile_interval_ms
   ulong updated_ms = NowMs();
   string line = StringFormat("1,%s,%s,%.2f,%.2f,%d,%d,%d,%d,%I64u,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f\n",
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
      input_min_balance_usd);
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
   int p = StringFind(s, ",");
   if(p<0) return false;
   string ts = StringSubstr(s, 0, p);
   // Use floating conversion to preserve 64-bit millisecond timestamp
   peer_ms = (ulong)StrToDouble(ts);
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
double g_master_min_balance_usd = 0.0;

bool ReadMasterConfigForSlave()
{
   if(input_role==ROLE_MASTER) return false;
   string s; if(!FileReadAll(PathConfigMaster(), s)) return false;
   string f[]; int n = StringSplit(TrimAll(s), ',', f);
   if(n < 10) return false;
   if(n >= 16)
   {
      g_master_dry_enabled = (StrToInteger(f[10])!=0);
      g_master_dry_mode = (int)StrToInteger(f[11]);
      g_master_dry_delay_ms = (int)StrToInteger(f[12]);
      g_master_dry_drop = (int)StrToInteger(f[13]);
      g_master_dry_override_expire_ms = (int)StrToInteger(f[14]);
      g_master_dry_suppress_heartbeat = (StrToInteger(f[15])!=0);
   }
   if(n >= 29)
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
      g_master_min_balance_usd = StrToDouble(f[28]);
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
   return PointsFromPriceDiff(diff);
}

double DiffClosePoints()
{
   // Always compute in Master orientation
   bool masterBuy = IsMasterSideBuyEffective();
   double m_bid,m_ask,s_bid,s_ask; GetMasterSlaveQuotes(m_bid,m_ask,s_bid,s_ask);
   double diff = masterBuy ? (m_bid - s_ask) : (s_bid - m_ask);
   return PointsFromPriceDiff(diff);
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
   // When debug hold is active (user forced open), do not auto-open more pairs
   if(input_debug_buttons_enabled && g_debug_hold_open) return;
   if(!g_peer_alive) return; // do not operate without peer
   if((int)(TimeCurrent() - g_last_open_time) < input_open_cooldown_seconds) return;
   if(CountOpenPairs() >= input_max_open_pairs) return;
   if(!ReadPeerQuotes()) return;
   if(!QuotesFresh()) return;
   if(!SelfSpreadOk()) return;
   if(!PeerSpreadOk()) return;

   // Min balance checks on both peers (fail-safe: require fresh peer info)
   if(input_min_balance_usd > 0.0)
   {
      double m_bal = AccountBalance(); double s_bal=0.0; ulong s_ts=0;
      bool s_ok = ReadPeerBalanceFresh(s_bal, s_ts);
      if(m_bal < input_min_balance_usd) return;
      if(!s_ok || s_bal < input_min_balance_usd) return;
   }

   // Pre-send recheck: compute diff now
   double diffOpen = DiffOpenPoints();
   bool triggerOpen = false;
   if(!input_avg_filter_enabled)
   {
      if(diffOpen < input_open_threshold_points) return;
      triggerOpen = true;
   }
   else
   {
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

   if(!triggerOpen) return;
   // Generate id but DO NOT write open_cmd until master opened successfully
   string cmd_id = NewCmdId();
   g_last_cmd_id = cmd_id;

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
   // In debug mode, keep positions open until user clicks Close Now
   if(input_debug_buttons_enabled && g_debug_hold_open) return;
   
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
   if(!input_avg_filter_enabled)
   {
      if(diffClose < input_close_threshold_points) return;
      triggerClose = true;
   }
   else
   {
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

   if(!triggerClose) return;

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
   ulong created_ms = (ulong)StrToInteger(fields[9]);
   int expire_ms    = (int)StrToInteger(fields[10]);

   // Idempotency: skip if already acknowledged/processed this cmd
   string sAckOpen;
   if(FileReadAll(PathOpenAckSelf(), sAckOpen))
   {
      string af[]; int an = StringSplit(TrimAll(sAckOpen), ',', af);
      if(an>=2 && af[1]==cmd_id) { if(input_verbose_journal_logs) Print("[Slave] Skip open_cmd idempotent ACK for cmd_id=", cmd_id); return; }
   }
   if(g_last_processed_open_cmd_id == cmd_id) { if(input_verbose_journal_logs) Print("[Slave] Skip open_cmd duplicate cmd_id=", cmd_id); return; }
   g_last_processed_open_cmd_id = cmd_id;

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
      if(input_verbose_journal_logs) Print("[Slave] open_cmd expired cmd_id=", cmd_id, " age_ms=", age_ms, " expire_ms=", expire_ms);
      return;
   }

   // Opposite side to master
   bool slaveBuy = (mside=="BUY") ? false : true;

   if(input_verbose_journal_logs) Print("[Slave] Execute open cmd_id=", cmd_id, " pair=", pair_id, " side=", ((slaveBuy)?"SELL":"BUY"), " lot=", DoubleToString(lot_slave, 2));
   // Dry run ack only
   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      {
         int latency = DryDelayMs();
         if(latency>0) Sleep(latency);
         string ackSelf = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0);
         FileWriteAllAtomic(PathOpenAckSelf(), ackSelf);
         if(input_verbose_journal_logs) Print("[Slave] DryRun ACK ok for cmd_id=", cmd_id);
      }
      return;
   }

   // Real trade
   g_pending_order_comment = ""; // do not expose pairing in comment
   g_pending_pair_id = pair_id;
   int ticket=-1; double price=0.0;
   bool ok = PlaceOrderMaster(slaveBuy, lot_slave, ticket, price);
   g_pending_pair_id = "";
   string ack = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ack);
   LogEvent("OPEN_ACK_SLAVE", StringFormat("cmd_id=%s;ok=%d;price=%.5f;err=%d", cmd_id, ok?1:0, price, ok?0:GetLastError()));
   if(input_verbose_journal_logs)
   {
      if(ok) Print("[Slave] Order placed OK cmd_id=", cmd_id, " ticket=", ticket, " price=", DoubleToString(price, g_digits));
      else   Print("[Slave] Order failed cmd_id=", cmd_id, " err=", GetLastError());
   }
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
   string s;
   if(!FileReadAll(PathCloseCmd(), s)) return;
   // format: version,cmd_id,seq,pair_id,reason,created_ms,expire_ms[,audit...]
   string fields[];
   int n = StringSplit(TrimAll(s), ',', fields);
   if(n < 7) return;
   string cmd_id = fields[1];
   string pair_id = fields[3];
   ulong created_ms = (ulong)StrToInteger(fields[5]);
   int expire_ms = (int)StrToInteger(fields[6]);

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
      ok = CloseSelfByPairId(pair_id);
      if(ok){ PairMapSelfDeleteByPairId(pair_id); WritePositions(); }
   }
   else
   {
      ok = CloseAllByMagic();
      PairMapSelfClearAll();
      WritePositions();
   }
   // Include minimal audit in ACK
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:GetLastError());
   FileWriteAll(PathCloseAckSelf(), ack);
}

void WritePositions()
{
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
   }
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
   ObjectSet(bg, OBJPROP_BACK, true);
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
      ObjectSet(b1, OBJPROP_XDISTANCE, BTN_X);
      ObjectSet(b1, OBJPROP_YDISTANCE, BTN_Y1);
      ObjectSet(b1, OBJPROP_XSIZE, BTN_W);
      ObjectSet(b1, OBJPROP_YSIZE, BTN_H);
      ObjectSetText(b1, "Open Now", 8, "Arial", clrBlack);

      string b2 = OBJ_PREFIX + "BTN_CLOSE";
      ObjectCreate(0, b2, OBJ_BUTTON, 0, 0, 0);
      ObjectSet(b2, OBJPROP_CORNER, 0);
      ObjectSet(b2, OBJPROP_XDISTANCE, BTN_X);
      ObjectSet(b2, OBJPROP_YDISTANCE, BTN_Y2);
      ObjectSet(b2, OBJPROP_XSIZE, BTN_W);
      ObjectSet(b2, OBJPROP_YSIZE, BTN_H);
      ObjectSetText(b2, "Close Now", 8, "Arial", clrBlack);
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

void DisplayUpdate()
{
   string role = (input_role==ROLE_MASTER)?"MASTER":"SLAVE";
   int spread = SpreadPointsSelf();
   double dOpen = DiffOpenPoints();
   double dClose = DiffClosePoints();
   double aOpen = input_avg_filter_enabled ? SmoothedOpenDiff(dOpen) : dOpen;
   double aClose = input_avg_filter_enabled ? SmoothedCloseDiff(dClose) : dClose;
   int line = 0;
   DisplaySetLine(line++, StringFormat("role=%s  channel=%s  symbol=%s", role, input_channel_id, g_symbol));
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
      // Slave: prefer showing authoritative values from master open_cmd if available; otherwise hide
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
      string avgLine = input_avg_filter_enabled ? StringFormat("AVG ON | EMA-%d%s | H=%d E=%d CF=%d CD=%dms",
         input_avg_period, (input_use_prefilter_median?StringFormat(" + Med-%d", input_prefilter_window):""),
         input_diff_hysteresis_points, input_epsilon_diff_points, input_confirm_ticks, input_avg_signal_cooldown_ms) : "AVG OFF | RealOnly";
      DisplaySetLine(line++, avgLine);
      
      // Enhanced status display with detailed averaging info
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
      else
      {
         // Simple display for non-averaging mode
         string stOpen = "READY";
         string stClose = "READY";
         DisplaySetLine(line++, StringFormat("Open: Real=%.1f Thr=%d | %s", dOpen, input_open_threshold_points, stOpen));
         DisplaySetLine(line++, StringFormat("Close: Real=%.1f Thr=%d | %s", dClose, input_close_threshold_points, stClose));
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
      // DisplaySetLine(line++, StringFormat("open_cooldown=%ds left=%s  close_cooldown=%ds left=%s",
      //   input_open_cooldown_seconds, cdLeft, input_close_cooldown_seconds, (closeLeft>=0?IntegerToString(closeLeft):"0")));
      DisplaySetLine(line++, StringFormat("max_pairs=%d  open_now=%d", input_max_open_pairs, CountOpenPairs()));
      
      // Performance Metrics
         double success_rate = (g_total_opens>0) ? ((double)g_successful_opens / g_total_opens * 100.0) : 0.0;
         ulong avg_ack = (g_total_opens>0) ? g_avg_ack_time_ms : 0;
         DisplaySetLine(line++, StringFormat("Success Rate: %.1f%% (%I64u/%I64u) AvgAck: %I64ums", 
                        success_rate, g_successful_opens, g_total_opens, avg_ack));
         DisplaySetLine(line++, StringFormat("Rollbacks: %I64u", g_rollback_count));
   }
   int effMode = DryMode();
   string effModeStr = (effMode==DRY_NONE?"NONE":(effMode==DRY_WRITE_CMD_ONLY?"WRITE_CMD_ONLY":"WRITE_CMD_AND_FAKE_ACK"));
   DisplaySetLine(line++, StringFormat("dry_run=%s mode=%s", (DryEnabled()?"ON":"OFF"), effModeStr));
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
}

// ---------------------------------
// Debug: master force open/close now
// ---------------------------------
void MasterOpenNow()
{
   if(!(input_role==ROLE_MASTER)) return;

   string cmd_id = NewCmdId();
   g_last_cmd_id = cmd_id;
   ulong created_ms = NowMs();
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0) ? DryOverrideExpireMs() : input_cmd_expire_ms;
   if(expire_ms <= 0) expire_ms = 60000; // Default 60 seconds if invalid (increased for timezone safety)
   string line = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d\n",
                              cmd_id, (long)g_seq, cmd_id, g_symbol,
                              ((input_master_side==SIDE_BUY)?"BUY":"SELL"),
                              input_lot_master, input_lot_slave, input_slippage_points,
                              created_ms, expire_ms, input_open_threshold_points, input_close_threshold_points);
   FileWriteAllAtomic(PathOpenCmd(), line);
   g_waiting_slave_open_ack = true; g_pending_open_cmd_id = cmd_id; g_pending_open_created_ms = created_ms; g_rollback_initiated=false;
   g_last_peer_open_ack_ms = 0; // reset grace timer
   // Prepare order comment to carry pair id into both sides
   g_pending_order_comment = "MS:OPEN|PAIR:" + cmd_id;

   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      {
         string ackSelf = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0);
         FileWriteAllAtomic(PathOpenAckSelf(), ackSelf);
      }
      g_last_open_time = TimeCurrent();
      g_pending_pair_id = "";
      return;
   }

   int ticket=-1; double price=0.0;
   bool ok = PlaceOrderMaster((input_master_side==SIDE_BUY), input_lot_master, ticket, price);
   string ack = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ack);
   if(ok)
   {
      g_last_open_time = TimeCurrent();
      // Upsert mapping and cache for pair-wise reconciliation and positions output
      PairMapSelfUpsert(cmd_id, ticket);
      CacheUpsert(cmd_id, ticket);
      WritePositions();
      CompactPairMapSelf();
   }
   g_pending_pair_id = "";
   if(input_debug_buttons_enabled) g_debug_hold_open = true;
}

void MasterCloseNow()
{
   if(!(input_role==ROLE_MASTER)) return;
   g_debug_hold_open = false;

   string cmd_id = NewCmdId(); ulong created_ms = NowMs();
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0) ? DryOverrideExpireMs() : input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
   FileWriteAllAtomic(PathCloseCmd(), line);

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

// Click handler for debug buttons
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!input_debug_buttons_enabled) return;
   if(!(input_role==ROLE_MASTER)) return;
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == OBJ_PREFIX + "BTN_OPEN") { MasterOpenNow(); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == OBJ_PREFIX + "BTN_CLOSE") { MasterCloseNow(); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
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

   FolderEnsure();
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
   WriteHeartbeat();
   UpdatePeerStatus();
   if(!g_role_conflict) WriteRoleLock();
   
   // Position tracking - CRITICAL สำหรับ reconciliation
   WritePositions();
   CacheCompactCurrentOrders();
   CompactPairMapSelf();
   RebuildPairMapSelfFromCache();
   WritePositions(); // เขียนอีกครั้งหลัง rebuild
   
   // Reconciliation - CRITICAL สำหรับ sync
   MasterReconcilePositions();
   if(input_role==ROLE_SLAVE)
   {
      SlaveLocalReconcile();
   }
   
   // === LESS CRITICAL - ทุก 3 วินาที ===
   if(timer_count % 3 == 0)
   {
      LogsCleanupRetention();
      WriteMasterConfig();
      ReadMasterConfigForSlave();
   }
   
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