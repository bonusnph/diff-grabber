//+------------------------------------------------------------------+
//|                                                 Diff-Grabber.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// =============================
// EA Heading Master–Slave (MT5)
// - Cross-terminal file sync via Common Files
// - Master/Slave roles
// - Open/Close thresholds by points
// - Cooldown, max open pairs
// - Smart Sync (lightweight) and Dry Run mode
// - Display Monitor using labels (no Comment)
// - Hedge/Netting note: this skeleton assumes Hedge accounts for simplicity
// =============================

// -----------------------------
// Inputs
// -----------------------------
// Reconcile actions when desync detected
enum ReconcileMode { RECONCILE_CLOSE = 0, RECONCILE_REOPEN = 1 };
// Dry run handshake behavior for testing (configured on Master; Slave inherits)
enum DryRunHandshakeMode { DRY_NONE = 0, DRY_WRITE_CMD_ONLY = 1, DRY_WRITE_CMD_AND_FAKE_ACK = 2 };
// EA role selection
enum Role { ROLE_MASTER = 0, ROLE_SLAVE = 1 };
// Master fixed side direction
enum MasterSide { SIDE_BUY = 0, SIDE_SELL = 1 };
input Role   input_role                     = ROLE_MASTER;   // Scope: Both — select EA role (ROLE_MASTER or ROLE_SLAVE)
input string input_channel_id               = "A01";         // Scope: Both — channel identifier (must match across peers)
input string input_shared_dir               = "";            // Scope: Both — legacy (unused); Common Files is used by default
input string input_symbol                   = "";            // Scope: Both — empty uses current chart symbol
input bool   input_verbose_journal_logs     = true;          // Scope: Both — emit concise Journal logs for key events

// Display monitor width (pixels)
input int    input_display_width_pixels      = 520;           // Scope: Both — width of Display Monitor background (pixels)

// Master decision parameters
input int    input_slippage_points          = 10;            // Scope: Both — slippage (points)
input MasterSide input_master_side          = SIDE_BUY;      // Scope: Master — master direction (Slave auto-opposite)
input double input_lot_master               = 0.01;          // Scope: Master — lot size for master orders
input double input_lot_slave                = 0.01;          // Scope: Master — advised lot for Slave; Slave ignores local lot input
input int    input_open_threshold_points    = 30;            // Scope: Master — open threshold (points)
input int    input_close_threshold_points   = 30;            // Scope: Master — close threshold (points)
input int    input_open_cooldown_seconds    = 300;           // Scope: Master — open cooldown after an open
input int    input_close_cooldown_seconds   = 60;            // Scope: Master — close cooldown after both sides opened
input int    input_max_open_pairs           = 1;             // Scope: Master — max concurrent pairs

// Quality guards
input int    input_max_spread_points_self   = 50;            // Scope: Master — block if own spread exceeds (points)
input int    input_max_spread_points_peer   = 50;            // Scope: Master — check peer spread before opening (points)
input int    input_quotes_fresh_ms          = 400;           // Scope: Master — maximum acceptable quote age (ms)
input int    input_file_poll_ms             = 20;            // Scope: Master — background file polling cadence (ms)
input int    input_magic_number_base        = 900100;        // Scope: Master — magic base per channel/symbol
input bool   input_retry_on_requote         = true;          // Scope: Master — retry on requote/off quotes
input int    input_max_retries              = 20;            // Scope: Master — max retry attempts

// Smart Sync timeouts
input int    input_cmd_expire_ms            = 15000;         // Scope: Master — command expiry (ms)
input int    input_ack_timeout_ms           = 4000;          // Scope: Master — ack wait timeout (ms)
input int    input_heartbeat_timeout_ms     = 3000;          // Scope: Master — peer heartbeat stale threshold (ms)
input ReconcileMode input_reconcile_mode   = RECONCILE_CLOSE;// Scope: Master — desync handling policy (CLOSE/REOPEN)
input int    input_reconcile_interval_ms    = 500;           // Scope: Master — reconcile cadence (ms)
input int    input_reconcile_freeze_seconds = 2;             // Scope: Master — freeze reconcile for N seconds after both sides open
input int    input_journal_rotate_max_kb    = 256;           // Scope: Master — journal rotation max size (KB)

// Dry Run (configured on Master only; Slave uses master's config automatically)
input bool   input_dry_run_enabled          = false;         // Scope: Master — enable Dry Run (no real trading)
input DryRunHandshakeMode input_dry_run_handshake_mode = DRY_NONE; // Scope: Master — NONE/WRITE_CMD_ONLY/WRITE_CMD_AND_FAKE_ACK
input int    input_dry_run_inject_delay_ms  = 0;             // Scope: Master — inject IO latency (ms)
input int    input_dry_run_drop_rate_percent= 0;             // Scope: Master — random drop rate for cmd/ack writes (0-100)
input int    input_dry_run_override_cmd_expire_ms = 0;       // Scope: Master — override cmd expiry in dry run (ms)
input bool   input_dry_run_suppress_heartbeat   = false;     // Scope: Master — suppress heartbeat for testing

// Debug UI (Master only)
input bool   input_debug_buttons_enabled     = false;         // Scope: Master — show Open/Close test buttons (simulate diffOpen/diffClose)

// Extended controls (Master-only; synced to Slave via config)
input double input_min_balance_usd           = 0.00;          // Scope: Master — minimum balance required on BOTH peers to allow new open

// -----------------------------
// Globals
// -----------------------------
string g_symbol;
int    g_digits;
double g_point;
long   g_magic;

double g_self_bid = 0.0, g_self_ask = 0.0;
double g_peer_bid = 0.0, g_peer_ask = 0.0;
ulong  g_self_quote_ms = 0, g_peer_quote_ms = 0;
ulong  g_peer_hb_ms = 0;
bool   g_peer_alive = false;

long   g_seq = 0;
string g_last_cmd_id = "";
datetime g_last_open_time = 0;
// Ack watchdog (slave acknowledgment tracking)
bool    g_waiting_slave_open_ack = false;
string  g_pending_open_cmd_id = "";
ulong   g_pending_open_created_ms = 0;
bool    g_rollback_initiated = false;
// Timestamp of latest slave ACK arrival after open
ulong   g_last_peer_open_ack_ms = 0;
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
string  g_last_processed_open_cmd_id = "";
string  g_last_processed_close_cmd_id = "";
// Debug: hold open until user presses Close Now
bool    g_debug_hold_open = false;
// Reconcile timer
ulong  g_last_reconcile_ms = 0;
// Master-provided dry-run settings (used by Slave)
bool   g_master_dry_enabled = false;
int    g_master_dry_mode = 0; // DryRunHandshakeMode
int    g_master_dry_delay_ms = 0;
int    g_master_dry_drop = 0;
int    g_master_dry_override_expire_ms = 0;
bool   g_master_dry_suppress_heartbeat = false;
// Master-provided guards/timeouts
int    g_master_max_spread_self = 0;
int    g_master_max_spread_peer = 0;
int    g_master_quotes_fresh_ms = 1000;
int    g_master_file_poll_ms = 20;
int    g_master_retry_on_requote = 1;
int    g_master_max_retries = 2;
int    g_master_cmd_expire_ms = 3000;
int    g_master_ack_timeout_ms = 2000;
int    g_master_heartbeat_timeout_ms = 3000;
int    g_master_reconcile_mode = (int)RECONCILE_CLOSE;
int    g_master_reconcile_interval_ms = 1000;
// Single-instance guard
bool   g_role_conflict = false;
ulong  g_open_grace_until_ms = 0;
int    g_reconcile_mismatch_streak = 0;
int    g_prev_self_pairs = 0;
int    g_prev_peer_pairs = 0;
// Anchor time when both sides confirmed open (used for close cooldown)
datetime g_last_pair_both_open_time = 0;
// Master-provided new settings (for Slave consumption)
int    g_master_close_cooldown_seconds = 0;
double g_master_min_balance_usd = 0.0;

bool DryEnabled()
{
   return (input_role==ROLE_MASTER) ? input_dry_run_enabled : g_master_dry_enabled;
}

string PathAccountStatusSelf()   { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "account_master.csv":"account_slave.csv"); }
string PathAccountStatusPeer()   { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "account_slave.csv":"account_master.csv"); }

int DryMode()
{
   return (input_role==ROLE_MASTER) ? (int)input_dry_run_handshake_mode : g_master_dry_mode;
}

int DryDelayMs()
{
   return (input_role==ROLE_MASTER) ? input_dry_run_inject_delay_ms : g_master_dry_delay_ms;
}

int DryOverrideExpireMs()
{
   return (input_role==ROLE_MASTER) ? input_dry_run_override_cmd_expire_ms : g_master_dry_override_expire_ms;
}

bool DrySuppressHeartbeat()
{
   return (input_role==ROLE_MASTER) ? input_dry_run_suppress_heartbeat : g_master_dry_suppress_heartbeat;
}

int EffectiveQuotesFreshMs() { return (input_role==ROLE_MASTER)? input_quotes_fresh_ms : g_master_quotes_fresh_ms; }
int EffectiveHeartbeatTimeoutMs() { return (input_role==ROLE_MASTER)? input_heartbeat_timeout_ms : g_master_heartbeat_timeout_ms; }

// -----------------------------
// Paths in Common Files
// -----------------------------
string PathChannelRoot() { return StringFormat("EAChannels\\channel_%s\\", input_channel_id); }
string PathChannelRootAbs()
{
   string base = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
   string sep = DetectSep(base);
   return base + sep + "Files" + sep + "EAChannels" + sep + "channel_" + input_channel_id + sep;
}
string PathQuotesSelf()  { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "quotes_master.csv" : "quotes_slave.csv"); }
string PathQuotesPeer()  { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "quotes_slave.csv" : "quotes_master.csv"); }
string PathOpenCmd()     { return PathChannelRoot() + "open_cmd.csv"; }
string PathOpenAckSelf() { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "open_ack_master.csv" : "open_ack_slave.csv"); }
string PathOpenAckPeer() { return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "open_ack_slave.csv" : "open_ack_master.csv"); }
string PathCloseCmd()    { return PathChannelRoot() + "close_cmd.csv"; }
string PathCloseAckSelf(){ return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "close_ack_master.csv" : "close_ack_slave.csv"); }
string PathCloseAckPeer(){ return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "close_ack_slave.csv" : "close_ack_master.csv"); }
string PathPositionsSelf(){ return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "positions_master.csv" : "positions_slave.csv"); }
string PathPositionsPeer(){ return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "positions_slave.csv" : "positions_master.csv"); }
string PathHeartbeatSelf(){ return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "heartbeat_master.csv" : "heartbeat_slave.csv"); }
string PathHeartbeatPeer(){ return PathChannelRoot() + ((input_role==ROLE_MASTER) ? "heartbeat_slave.csv" : "heartbeat_master.csv"); }
string PathConfigMaster()  { return PathChannelRoot() + "config_master.csv"; }
string PathRoleLock()      { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "lock_master.csv":"lock_slave.csv"); }
string PathPairMapSelf()   { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "pair_map_master.csv":"pair_map_slave.csv"); }
string PathPairMapPeer()   { return PathChannelRoot() + ((input_role==ROLE_MASTER)? "pair_map_slave.csv":"pair_map_master.csv"); }

// -----------------------------
// In-memory cache: pair_id <-> ticket (current symbol/magic)
// -----------------------------
string g_cache_pair_ids[];
ulong  g_cache_tickets[];

int CacheFindIndexByPairId(const string pair_id)
{
  int n = ArraySize(g_cache_pair_ids);
  for(int i=0;i<n;i++){ if(g_cache_pair_ids[i]==pair_id) return i; }
  return -1;
}

int CacheFindIndexByTicket(const ulong ticket)
{
  int n = ArraySize(g_cache_tickets);
  for(int i=0;i<n;i++){ if(g_cache_tickets[i]==ticket) return i; }
  return -1;
}

void CacheUpsert(const string pair_id, const ulong ticket)
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

void CacheCompactCurrentPositions()
{
  // Keep only entries that still have an open position for this symbol/magic
  bool keep[]; int n = ArraySize(g_cache_pair_ids); ArrayResize(keep, n);
  for(int i=0;i<n;i++) keep[i]=false;
  for(int i=PositionsTotal()-1; i>=0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if(!PositionSelectByTicket(ticket)) continue;
    if((string)PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
    if((long)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
    int idx = CacheFindIndexByTicket(ticket); if(idx>=0) keep[idx]=true;
  }
  // Rebuild compacted arrays without direct assignment
  string np[]; ulong nt[]; int k=0; ArrayResize(np, 0); ArrayResize(nt, 0);
  for(int i=0;i<n;i++)
  {
    if(keep[i])
    {
      ArrayResize(np, k+1); ArrayResize(nt, k+1);
      np[k]=g_cache_pair_ids[i]; nt[k]=g_cache_tickets[i];
      k++;
    }
  }
  ArrayResize(g_cache_pair_ids, 0); ArrayResize(g_cache_tickets, 0);
  int m = ArraySize(np);
  ArrayResize(g_cache_pair_ids, m); ArrayResize(g_cache_tickets, m);
  for(int i=0;i<m;i++) { g_cache_pair_ids[i]=np[i]; g_cache_tickets[i]=nt[i]; }
}

// Upsert pair_id->ticket into our map file (append or update in-place)
void PairMapSelfUpsert(const string pair_id, const ulong ticket)
{
  string existing; string out=""; bool replaced=false;
  if(FileReadAll(PathPairMapSelf(), existing))
  {
    string lines[]; int ln=StringSplit(TrimAll(existing), '\n', lines);
    for(int i=0;i<ln;i++)
    {
      string row = TrimAll(lines[i]); if(StringLen(row)==0) continue;
      string cols[]; int cn=StringSplit(row, ',', cols);
      if(cn>=2 && cols[0]==pair_id)
      {
        out += StringFormat("%s,%I64d\n", pair_id, (long)ticket);
        replaced=true;
      }
      else
      {
        out += row + "\n";
      }
    }
  }
  if(!replaced) out += StringFormat("%s,%I64d\n", pair_id, (long)ticket);
  FileWriteAllAtomic(PathPairMapSelf(), out);
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
      if(cn>=2 && cols[0]==pair_id) continue; // skip this pair_id
      out += row + "\n";
    }
    FileWriteAllAtomic(PathPairMapSelf(), out);
  }
}

void PairMapSelfClearAll()
{
  FileWriteAllAtomic(PathPairMapSelf(), "");
}

// Remove stale map rows whose tickets are no longer open
void CompactPairMapSelf()
{
  // Build set of open tickets for this symbol/magic
  string openSet = ",";
  for(int i=PositionsTotal()-1; i>=0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if(!PositionSelectByTicket(ticket)) continue;
    if((string)PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
    if((long)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
    openSet += IntegerToString((long)ticket) + ",";
  }
  string mapC; if(!FileReadAll(PathPairMapSelf(), mapC)) return;
  string ml[]; int mn = StringSplit(TrimAll(mapC), '\n', ml);
  string seen = ","; string outRev="";
  for(int i=mn-1;i>=0; --i)
  {
    string row = TrimAll(ml[i]); if(StringLen(row)==0) continue;
    string cols[]; int cn = StringSplit(row, ',', cols); if(cn<2) continue;
    string pid = cols[0]; string tStr = cols[1];
    if(StringFind(openSet, ","+tStr+",") < 0) continue; // keep only open tickets
    if(StringFind(seen, ","+pid+",") >= 0) continue; // keep last occurrence per pair_id
    seen += pid + ",";
    outRev = row + "\n" + outRev;
  }
  string current = TrimAll(mapC);
  string next = TrimAll(outRev);
  if(current == next) return; // no changes, avoid rewrite
  FileWriteAllAtomic(PathPairMapSelf(), outRev);
}

// Rebuild mapping file strictly from current open positions and in-memory cache
void RebuildPairMapSelfFromCache()
{
  string existing; string lines[]; int ln = 0;
  if(FileReadAll(PathPairMapSelf(), existing)) ln = StringSplit(TrimAll(existing), '\n', lines);
  // collect entries
  string pids[]; ulong tks[]; int cnt=0; ArrayResize(pids,0); ArrayResize(tks,0);
  for(int i=PositionsTotal()-1; i>=0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if(!PositionSelectByTicket(ticket)) continue;
    if((string)PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
    if((long)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
    string pid = "";
    int cidx = CacheFindIndexByTicket(ticket); if(cidx>=0) pid = g_cache_pair_ids[cidx];
    if(pid=="")
    {
      for(int k=0;k<ln;k++)
      {
        string cols[]; int cn = StringSplit(TrimAll(lines[k]), ',', cols);
        if(cn>=2){ if((ulong)StringToInteger(cols[1])==ticket){ pid=cols[0]; break; } }
      }
    }
    if(pid=="" || pid=="N/A") continue;
    ArrayResize(pids, cnt+1); ArrayResize(tks, cnt+1); pids[cnt]=pid; tks[cnt]=ticket; cnt++;
  }
  // sort by ticket asc for deterministic order
  for(int i=0;i<cnt;i++)
  {
    int minIdx=i; for(int j=i+1;j<cnt;j++){ if(tks[j] < tks[minIdx]) minIdx=j; }
    if(minIdx!=i){ ulong tt=tks[i]; tks[i]=tks[minIdx]; tks[minIdx]=tt; string tp=pids[i]; pids[i]=pids[minIdx]; pids[minIdx]=tp; }
  }
  string out=""; for(int i=0;i<cnt;i++){ out += StringFormat("%s,%I64d\n", pids[i], (long)tks[i]); }
  if(TrimAll(existing) == TrimAll(out)) return; // no changes
  FileWriteAllAtomic(PathPairMapSelf(), out);
}

// -----------------------------
// Utils
// -----------------------------
ulong NowMs() { return (ulong)TimeLocal()*1000 + (ulong)GetTickCount64()%1000; }

string DetectSep(const string base) { return (StringFind(base, "\\")>=0) ? "\\" : "/"; }

bool FolderEnsure()
{
   // Ensure Common\Files directories exist for shared IO
   bool ok1 = FolderCreate("EAChannels", FILE_COMMON);
   bool ok2 = FolderCreate(StringFormat("EAChannels\\channel_%s", input_channel_id), FILE_COMMON);
   return (ok1 && ok2);
}

int FileWriteAll(const string relPath, const string content)
{
   int h = FileOpen(relPath, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return GetLastError();
   FileWriteString(h, content);
   FileFlush(h);
   FileClose(h);
   return 0;
}

int FileWriteAllAtomic(const string relPath, const string content)
{
   string tmp = relPath + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return GetLastError();
   FileWriteString(h, content);
   FileFlush(h);
   FileClose(h);
   bool mv = FileMove(tmp, FILE_COMMON, relPath, FILE_COMMON);
   if(!mv) return FileWriteAll(relPath, content);
   return 0;
}
bool FileReadAll(const string relPath, string &out)
{
   out = "";
   if(!FileIsExist(relPath, FILE_COMMON)) return false;
   int h = FileOpen(relPath, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return false;
   int size = (int)FileSize(h);
   out = FileReadString(h, size);
   FileClose(h);
   return true;
}

string NodeId()
{
   return StringFormat("%I64d_%I64d_%s", (long)AccountInfoInteger(ACCOUNT_LOGIN), (long)g_magic, g_symbol);
}

bool ReadRoleLock(string &owner, ulong &ts)
{
   string s; if(!FileReadAll(PathRoleLock(), s)) return false;
   int p = StringFind(s, ","); if(p<0) return false;
   owner = StringSubstr(s, 0, p);
   ts = (ulong)StringToInteger(StringSubstr(s, p+1));
   return true;
}

void WriteRoleLock()
{
   string line = StringFormat("%s,%I64u\n", NodeId(), NowMs());
   FileWriteAllAtomic(PathRoleLock(), line);
}

bool AcquireRoleLock()
{
   string owner; ulong ts=0;
   if(ReadRoleLock(owner, ts))
   {
      if((NowMs() - ts) <= (ulong)EffectiveHeartbeatTimeoutMs()*2) return false;
   }
   WriteRoleLock();
   return true;
}

// Helper: trim both sides (MQL5 has StringTrimLeft/Right)
string TrimAll(const string src)
{
   string t = src;
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
}

int SpreadPointsSelf()
{
   return (int)MathRound(MathMax(0.0, (g_self_ask - g_self_bid) / g_point));
}

bool IsMasterSideBuyEffective()
{
   if(input_role==ROLE_MASTER) return (input_master_side==SIDE_BUY);
   if(g_have_master_cmd || g_have_master_th || g_last_cmd_seen_ms>0)
      return (g_last_cmd_side=="BUY");
   return (input_master_side==SIDE_BUY);
}

void GetMasterSlaveQuotes(double &m_bid, double &m_ask, double &s_bid, double &s_ask)
{
   if(input_role==ROLE_MASTER)
   {
      m_bid=g_self_bid; m_ask=g_self_ask; s_bid=g_peer_bid; s_ask=g_peer_ask;
   }
   else
   {
      m_bid=g_peer_bid; m_ask=g_peer_ask; s_bid=g_self_bid; s_ask=g_self_ask;
   }
}

// -----------------------------
// Trading helpers (MT5)
// -----------------------------
bool PlaceOrder(const bool isBuy, const double lots, ulong &ticket_out, double &price_out)
{
   ticket_out = 0;
   price_out = 0.0;
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = g_symbol;
   req.deviation = input_slippage_points;
   req.magic = g_magic;
   req.volume = lots;
   req.comment = "";
   // Set filling/time modes compatible with the symbol to avoid "Unsupported filling mode"
   int fillingFlags = (int)SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
   if((fillingFlags & SYMBOL_FILLING_FOK) != 0) req.type_filling = ORDER_FILLING_FOK;
   else if((fillingFlags & SYMBOL_FILLING_IOC) != 0) req.type_filling = ORDER_FILLING_IOC;
   else req.type_filling = ORDER_FILLING_RETURN;
   req.type_time = ORDER_TIME_GTC;
   if(isBuy)
   {
      req.type = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   }
   else
   {
      req.type = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   }
   bool ok = OrderSend(req, res);
   if(ok) { ticket_out = res.order; price_out = req.price; }
   return ok;
}

bool CloseAllByMagic()
{
  bool ok = true;
  for(int i=PositionsTotal()-1; i>=0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if(!PositionSelectByTicket(ticket)) continue;
    if((string)PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
    if((long)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
    long type = PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
    req.action = TRADE_ACTION_DEAL;
    req.symbol = g_symbol;
    req.volume = volume;
    req.magic = g_magic;
    req.deviation = input_slippage_points;
    int fillingFlags2 = (int)SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
    if((fillingFlags2 & SYMBOL_FILLING_FOK) != 0) req.type_filling = ORDER_FILLING_FOK;
    else if((fillingFlags2 & SYMBOL_FILLING_IOC) != 0) req.type_filling = ORDER_FILLING_IOC;
    else req.type_filling = ORDER_FILLING_RETURN;
    req.type_time = ORDER_TIME_GTC;
    req.position = ticket;
    if(type == POSITION_TYPE_BUY) { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(g_symbol, SYMBOL_BID); }
    else { req.type = ORDER_TYPE_BUY; req.price = SymbolInfoDouble(g_symbol, SYMBOL_ASK); }
    if(!OrderSend(req, res)) ok = false;
  }
  return ok;
}

bool CloseSelfByPairId(const string pair_id)
{
  // 1) Try in-memory cache first
  int cidx = CacheFindIndexByPairId(pair_id);
  if(cidx>=0)
  {
    ulong ticket = g_cache_tickets[cidx];
    if(PositionSelectByTicket(ticket))
    {
      if((string)PositionGetString(POSITION_SYMBOL)==g_symbol && (long)PositionGetInteger(POSITION_MAGIC)==g_magic)
      {
        long type = PositionGetInteger(POSITION_TYPE);
        double volume = PositionGetDouble(POSITION_VOLUME);
        MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
        req.action = TRADE_ACTION_DEAL; req.symbol=g_symbol; req.volume=volume; req.magic=g_magic; req.deviation=input_slippage_points; req.position=ticket;
        int fillingFlags2 = (int)SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
        if((fillingFlags2 & SYMBOL_FILLING_FOK) != 0) req.type_filling = ORDER_FILLING_FOK; else if((fillingFlags2 & SYMBOL_FILLING_IOC) != 0) req.type_filling = ORDER_FILLING_IOC; else req.type_filling = ORDER_FILLING_RETURN;
        req.type_time = ORDER_TIME_GTC;
        if(type==POSITION_TYPE_BUY){ req.type=ORDER_TYPE_SELL; req.price=SymbolInfoDouble(g_symbol, SYMBOL_BID);} else { req.type=ORDER_TYPE_BUY; req.price=SymbolInfoDouble(g_symbol, SYMBOL_ASK);} 
        return OrderSend(req, res);
      }
    }
  }
  // 2) Try map file pair_id -> ticket
  string mapContent; if(FileReadAll(PathPairMapSelf(), mapContent))
  {
    string lines[]; int ln = StringSplit(TrimAll(mapContent), '\n', lines);
    for(int k=0;k<ln;k++)
    {
      string cols[]; int cn=StringSplit(TrimAll(lines[k]), ',', cols); if(cn<2) continue;
      if(cols[0]!=pair_id) continue;
      ulong ticket = (ulong)StringToInteger(cols[1]);
      if(PositionSelectByTicket(ticket))
      {
        if((string)PositionGetString(POSITION_SYMBOL)==g_symbol && (long)PositionGetInteger(POSITION_MAGIC)==g_magic)
        {
          long type = PositionGetInteger(POSITION_TYPE);
          double volume = PositionGetDouble(POSITION_VOLUME);
          MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
          req.action = TRADE_ACTION_DEAL; req.symbol=g_symbol; req.volume=volume; req.magic=g_magic; req.deviation=input_slippage_points; req.position=ticket;
          int fillingFlags2 = (int)SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
          if((fillingFlags2 & SYMBOL_FILLING_FOK) != 0) req.type_filling = ORDER_FILLING_FOK; else if((fillingFlags2 & SYMBOL_FILLING_IOC) != 0) req.type_filling = ORDER_FILLING_IOC; else req.type_filling = ORDER_FILLING_RETURN;
          req.type_time = ORDER_TIME_GTC;
          if(type==POSITION_TYPE_BUY){ req.type=ORDER_TYPE_SELL; req.price=SymbolInfoDouble(g_symbol, SYMBOL_BID);} else { req.type=ORDER_TYPE_BUY; req.price=SymbolInfoDouble(g_symbol, SYMBOL_ASK);} 
          return OrderSend(req, res);
        }
      }
    }
  }
  // 3) Fallback: scan positions_self.csv for ticket with this pair_id
  string posC; if(FileReadAll(PathPositionsSelf(), posC))
  {
    string rows[]; int rn = StringSplit(TrimAll(posC), '\n', rows);
    for(int i=0;i<rn;i++)
    {
      string cols[]; int cn = StringSplit(TrimAll(rows[i]), ',', cols); if(cn<2) continue;
      if(cols[0]!=pair_id) continue;
      ulong ticket = (ulong)StringToInteger(cols[1]);
      if(PositionSelectByTicket(ticket))
      {
        if((string)PositionGetString(POSITION_SYMBOL)==g_symbol && (long)PositionGetInteger(POSITION_MAGIC)==g_magic)
        {
          long type = PositionGetInteger(POSITION_TYPE);
          double volume = PositionGetDouble(POSITION_VOLUME);
          MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
          req.action = TRADE_ACTION_DEAL; req.symbol=g_symbol; req.volume=volume; req.magic=g_magic; req.deviation=input_slippage_points; req.position=ticket;
          int fillingFlags2 = (int)SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
          if((fillingFlags2 & SYMBOL_FILLING_FOK) != 0) req.type_filling = ORDER_FILLING_FOK; else if((fillingFlags2 & SYMBOL_FILLING_IOC) != 0) req.type_filling = ORDER_FILLING_IOC; else req.type_filling = ORDER_FILLING_RETURN;
          req.type_time = ORDER_TIME_GTC;
          if(type==POSITION_TYPE_BUY){ req.type=ORDER_TYPE_SELL; req.price=SymbolInfoDouble(g_symbol, SYMBOL_BID);} else { req.type=ORDER_TYPE_BUY; req.price=SymbolInfoDouble(g_symbol, SYMBOL_ASK);} 
          return OrderSend(req, res);
        }
      }
    }
  }
  return false;
}

// Find the newest position ticket for current symbol/magic (hedge accounts)
ulong GetNewestPositionTicket()
{
  ulong bestTicket = 0; long bestTime = 0;
  for(int i=PositionsTotal()-1; i>=0; --i)
  {
    ulong ticket = PositionGetTicket(i);
    if(!PositionSelectByTicket(ticket)) continue;
    if((string)PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
    if((long)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
    long t = (long)PositionGetInteger(POSITION_TIME);
    if(t >= bestTime){ bestTime = t; bestTicket = ticket; }
  }
  return bestTicket;
}

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
  // Skip only if not a manual drop
  if(!manualDrop && g_waiting_slave_open_ack && (NowMs()-g_pending_open_created_ms) <= (ulong)input_ack_timeout_ms) return;
  if(!manualDrop && g_last_peer_open_ack_ms>0 && (NowMs()-g_last_peer_open_ack_ms) < (ulong)input_ack_timeout_ms) return;
  // In debug hold, reconcile only when manual close detected (pair count drop)
  if(input_debug_buttons_enabled && g_debug_hold_open)
  {
    if(!manualDrop) return;
  }
  if((NowMs()-g_last_reconcile_ms) < (ulong)input_reconcile_interval_ms) return;
  g_last_reconcile_ms = NowMs();
  // Deterministic pair-wise diff first: act on any specific missing/excess pair id (one per cycle)
  {
    string peerPos, selfPos; string pRows[]; string sRows[]; int pn=0, sn=0;
    if(FileReadAll(PathPositionsPeer(), peerPos)) pn = StringSplit(TrimAll(peerPos), '\n', pRows);
    if(FileReadAll(PathPositionsSelf(), selfPos)) sn = StringSplit(TrimAll(selfPos), '\n', sRows);
    // extra on peer -> ask peer to close
    string pidExtraPeer="";
    for(int i=0;i<pn && pidExtraPeer==""; ++i){ string c[]; int cn=StringSplit(TrimAll(pRows[i]), ',', c); if(cn>=1){ string pid=c[0]; if(pid==""||pid=="N/A") continue; bool found=false; for(int j=0;j<sn; ++j){ string c2[]; int c2n=StringSplit(TrimAll(sRows[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } } if(!found) pidExtraPeer=pid; } }
    if(pidExtraPeer!="")
    {
      string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
      string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, pidExtraPeer, "CLOSE_ONE", created_ms, expire_ms);
      FileWriteAllAtomic(PathCloseCmd(), line);
      if(DryEnabled() && DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf=StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf);} 
      g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return;
    }
    // extra on self -> close self
    string pidExtraSelf="";
    for(int i=0;i<sn && pidExtraSelf==""; ++i){ string c[]; int cn=StringSplit(TrimAll(sRows[i]), ',', c); if(cn>=1){ string pid=c[0]; if(pid==""||pid=="N/A") continue; bool found=false; for(int j=0;j<pn; ++j){ string c2[]; int c2n=StringSplit(TrimAll(pRows[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } } if(!found) pidExtraSelf=pid; } }
    if(pidExtraSelf!="")
    {
      bool ok1 = CloseSelfByPairId(pidExtraSelf);
      if(ok1){ PairMapSelfDeleteByPairId(pidExtraSelf); WritePositions(); CompactPairMapSelf(); }
      string cmd_id = NewCmdId(); string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok1?1:0, ok1?0:(int)GetLastError()); FileWriteAll(PathCloseAckSelf(), ack);
      g_prev_self_pairs=selfNow; g_prev_peer_pairs=peerNow; return;
    }
  }
  int self = selfNow; int peer = peerNow;
  int diff = (self>peer)? (self-peer) : (peer-self);
  if(!manualDrop && diff<=1 && (NowMs()-g_pending_open_created_ms) <= (ulong)input_ack_timeout_ms) { g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
  if(self==peer) { g_reconcile_mismatch_streak = 0; g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
  // If exactly one mismatch, fix the specific side only (pair-wise reconcile)
  if(diff==1)
  {
    if(self < peer)
    {
      // Master has fewer -> instruct peer to close the extra pair using positions diff
      string peerPos, selfPos; string pRows[]; string sRows[]; int pn=0, sn=0;
      if(FileReadAll(PathPositionsPeer(), peerPos)) pn = StringSplit(TrimAll(peerPos), '\n', pRows);
      if(FileReadAll(PathPositionsSelf(), selfPos)) sn = StringSplit(TrimAll(selfPos), '\n', sRows);
      string pickPair="";
      for(int i=0;i<pn && pickPair=="";++i){ string cols[]; int cn=StringSplit(TrimAll(pRows[i]), ',', cols); if(cn>=1){ string pid=cols[0]; bool found=false; for(int j=0;j<sn;++j){ string c2[]; int c2n=StringSplit(TrimAll(sRows[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } } if(!found && pid!="N/A" && pid!="") pickPair=pid; } }
      // Fallback: resolve pair_id via ticket from peer positions and peer map
      if(pickPair=="")
      {
        for(int i=0;i<pn && pickPair=="";++i)
        {
          string cols[]; int cn=StringSplit(TrimAll(pRows[i]), ',', cols); if(cn>=2)
          {
            string tStr = cols[1]; string mapContent; if(FileReadAll(PathPairMapPeer(), mapContent))
            {
              string ml[]; int mn=StringSplit(TrimAll(mapContent), '\n', ml);
              for(int m=0;m<mn && pickPair=="";++m){ string mc[]; int mcn=StringSplit(TrimAll(ml[m]), ',', mc); if(mcn>=2){ if(mc[1]==tStr && mc[0]!="" && mc[0]!="N/A") pickPair=mc[0]; } }
            }
          }
        }
      }
      if(pickPair=="") { g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
      string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
      string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, pickPair, "CLOSE_ONE", created_ms, expire_ms);
      FileWriteAllAtomic(PathCloseCmd(), line);
      if(DryEnabled()) { if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf=StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf);} g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
      g_prev_self_pairs=self; g_prev_peer_pairs=peer; return;
    }
    else
    {
      // Master has more -> close self pair that is absent on peer
      string peerPos, selfPos; string pRows[]; string sRows[]; int pn=0, sn=0;
      if(FileReadAll(PathPositionsPeer(), peerPos)) pn = StringSplit(TrimAll(peerPos), '\n', pRows);
      if(FileReadAll(PathPositionsSelf(), selfPos)) sn = StringSplit(TrimAll(selfPos), '\n', sRows);
      string pickPair="";
      for(int i=0;i<sn && pickPair=="";++i){ string cols[]; int cn=StringSplit(TrimAll(sRows[i]), ',', cols); if(cn>=1){ string pid=cols[0]; bool found=false; for(int j=0;j<pn;++j){ string c2[]; int c2n=StringSplit(TrimAll(pRows[j]), ',', c2); if(c2n>=1 && c2[0]==pid){ found=true; break; } } if(!found && pid!="N/A" && pid!="") pickPair=pid; } }
      // Fallback: resolve self pair_id via ticket from self positions and self map
      if(pickPair=="")
      {
        for(int i=0;i<sn && pickPair=="";++i)
        {
          string cols[]; int cn=StringSplit(TrimAll(sRows[i]), ',', cols); if(cn>=2)
          {
            string tStr = cols[1]; string mapContent; if(FileReadAll(PathPairMapSelf(), mapContent))
            {
              string ml[]; int mn=StringSplit(TrimAll(mapContent), '\n', ml);
              for(int m=0;m<mn && pickPair=="";++m){ string mc[]; int mcn=StringSplit(TrimAll(ml[m]), ',', mc); if(mcn>=2){ if(mc[1]==tStr && mc[0]!="" && mc[0]!="N/A") pickPair=mc[0]; } }
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
      string cmd_id = NewCmdId(); string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok1?1:0, ok1?0:(int)GetLastError()); FileWriteAll(PathCloseAckSelf(), ack);
      g_prev_self_pairs=self; g_prev_peer_pairs=peer; return;
    }
  }
  // Require mismatch to persist across multiple checks to avoid transient closes
  g_reconcile_mismatch_streak++;
  if(g_reconcile_mismatch_streak < 2) { g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
  g_reconcile_mismatch_streak = 0;
  // Force both sides to close to maintain full hedge
  string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
  string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
  FileWriteAllAtomic(PathCloseCmd(), line);
  if(DryEnabled()){ if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf=StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAll(PathCloseAckSelf(), ackSelf);} g_prev_self_pairs=self; g_prev_peer_pairs=peer; return; }
  bool ok = CloseAllByMagic(); CompactPairMapSelf(); WritePositions(); string ack2 = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:(int)GetLastError()); FileWriteAll(PathCloseAckSelf(), ack2);
  g_prev_self_pairs=self; g_prev_peer_pairs=peer;
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
        { string ml[]; int mn=StringSplit(TrimAll(mapContent), '\n', ml);
          for(int m=0;m<mn && pickPair=="";++m){ string mc[]; int mcn=StringSplit(TrimAll(ml[m]), ',', mc); if(mcn>=2){ if(mc[1]==tStr && mc[0]!="" && mc[0]!="N/A") pickPair=mc[0]; } } }
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
string NewCmdId() { g_seq++; return StringFormat("%s_%I64d_%u", input_channel_id, (long)TimeLocal(), (uint)g_seq); }

void WriteHeartbeat()
{
   if(DrySuppressHeartbeat()) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE); double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string line = StringFormat("%I64u,%d,%I64d,%I64d,%s,%.2f,%.2f\n", NowMs(), __MQL5BUILD__, (long)AccountInfoInteger(ACCOUNT_LOGIN), (long)g_magic, "1.0.0", bal, eq);
   FileWriteAll(PathHeartbeatSelf(), line);
   string acc = StringFormat("1,%.2f,%.2f,%I64u\n", bal, eq, NowMs());
   FileWriteAll(PathAccountStatusSelf(), acc);
}

bool ReadMasterConfig()
{
   if(input_role==ROLE_MASTER) return false;
   string s; if(!FileReadAll(PathConfigMaster(), s)) return false;
   string f[]; int n = StringSplit(TrimAll(s), ',', f);
   if(n < 10) return false;
   // f[0]=version, f[1]=symbol, f[2]=side, f[3]=lotM, f[4]=lotS, f[5]=open_th, f[6]=close_th, f[7]=cooldown, f[8]=max_pairs, f[9]=updated_ms
   g_have_master_cmd = true;
   g_last_cmd_side = f[2];
   g_last_cmd_lot_master = StringToDouble(f[3]);
   g_last_cmd_lot_slave  = StringToDouble(f[4]);
   g_have_master_th = true;
   g_last_cmd_open_th = (int)StringToInteger(f[5]);
   g_last_cmd_close_th = (int)StringToInteger(f[6]);
   g_last_cmd_seen_ms = NowMs();
   // Optional dry-run fields from master
   if(n >= 16)
   {
      g_master_dry_enabled = (StringToInteger(f[10])!=0);
      g_master_dry_mode = (int)StringToInteger(f[11]);
      g_master_dry_delay_ms = (int)StringToInteger(f[12]);
      g_master_dry_drop = (int)StringToInteger(f[13]);
      g_master_dry_override_expire_ms = (int)StringToInteger(f[14]);
      g_master_dry_suppress_heartbeat = (StringToInteger(f[15])!=0);
   }
   // Guards/Timeouts starting from index 16 if present
   if(n >= 27)
   {
      g_master_max_spread_self = (int)StringToInteger(f[16]);
      g_master_max_spread_peer = (int)StringToInteger(f[17]);
      g_master_quotes_fresh_ms = (int)StringToInteger(f[18]);
      g_master_file_poll_ms = (int)StringToInteger(f[19]);
      g_master_retry_on_requote = (int)StringToInteger(f[20]);
      g_master_max_retries = (int)StringToInteger(f[21]);
      g_master_cmd_expire_ms = (int)StringToInteger(f[22]);
      g_master_ack_timeout_ms = (int)StringToInteger(f[23]);
      g_master_heartbeat_timeout_ms = (int)StringToInteger(f[24]);
      g_master_reconcile_mode = (int)StringToInteger(f[25]);
      g_master_reconcile_interval_ms = (int)StringToInteger(f[26]);
   }
   if(n >= 29)
   {
      g_master_close_cooldown_seconds = (int)StringToInteger(f[27]);
      g_master_min_balance_usd = StringToDouble(f[28]);
   }
   return true;
}

void WriteMasterConfig()
{
   if(!(input_role==ROLE_MASTER)) return;
   ulong updated_ms = NowMs();
   // version,symbol,master_side,lot_master,lot_slave,open_th,close_th,open_cooldown,max_pairs,updated_ms,
   // dry_enabled,dry_mode,dry_delay_ms,dry_drop_percent,dry_override_expire_ms,dry_suppress_hb,
   // max_spread_self,max_spread_peer,quotes_fresh_ms,file_poll_ms,retry_on_requote,max_retries,cmd_expire_ms,ack_timeout_ms,heartbeat_timeout_ms,reconcile_mode,reconcile_interval_ms,close_cooldown,min_balance
   string line = StringFormat("1,%s,%s,%.2f,%.2f,%d,%d,%d,%d,%I64u,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f\n",
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

bool ReadPeerHeartbeat(ulong &peer_ms)
{
   string s; if(!FileReadAll(PathHeartbeatPeer(), s)) return false;
   int p = StringFind(s, ","); if(p<0) return false;
   string ts = StringSubstr(s, 0, p);
   peer_ms = (ulong)StringToInteger(ts);
   return true;
}

void UpdatePeerStatus()
{
   ulong hb=0;
   if(ReadPeerHeartbeat(hb))
   {
      g_peer_hb_ms = hb;
      g_peer_alive = ((NowMs() - g_peer_hb_ms) <= (ulong)EffectiveHeartbeatTimeoutMs());
   }
   else g_peer_alive = false;
}

void WriteQuotes()
{
   SymbolInfoDouble(g_symbol, SYMBOL_BID, g_self_bid);
   SymbolInfoDouble(g_symbol, SYMBOL_ASK, g_self_ask);
   g_self_quote_ms = NowMs();
   string line = StringFormat("%I64u,%.10f,%.10f\n", g_self_quote_ms, g_self_bid, g_self_ask);
   FileWriteAll(PathQuotesSelf(), line);
}

bool ReadPeerQuotes()
{
   string s; if(!FileReadAll(PathQuotesPeer(), s)) return false;
   int p1 = StringFind(s, ","); if(p1<0) return false;
   int p2 = StringFind(s, ",", p1+1); if(p2<0) return false;
   g_peer_quote_ms = (ulong)StringToInteger(StringSubstr(s, 0, p1));
   g_peer_bid = StringToDouble(StringSubstr(s, p1+1, p2-p1-1));
   g_peer_ask = StringToDouble(StringSubstr(s, p2+1));
   return true;
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
  string f[]; int n = StringSplit(TrimAll(s), ',', f); if(n<4) return false;
  bal_out = StringToDouble(f[1]); ts_out = (ulong)StringToInteger(f[3]);
  if((NowMs()-ts_out) > (ulong)EffectiveHeartbeatTimeoutMs()) return false;
  return true;
}

double DiffOpenPoints()
{
   bool masterBuy = IsMasterSideBuyEffective();
   double m_bid,m_ask,s_bid,s_ask; GetMasterSlaveQuotes(m_bid,m_ask,s_bid,s_ask);
   double diff = masterBuy ? (s_bid - m_ask) : (m_bid - s_ask);
   return diff / g_point;
}

double DiffClosePoints()
{
   bool masterBuy = IsMasterSideBuyEffective();
   double m_bid,m_ask,s_bid,s_ask; GetMasterSlaveQuotes(m_bid,m_ask,s_bid,s_ask);
   double diff = masterBuy ? (m_bid - s_ask) : (s_bid - m_ask);
   return diff / g_point;
}

int CountOpenPairs()
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      if((string)PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
      count++;
   }
   return count;
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
   if(SpreadPointsSelf() > input_max_spread_points_self) return;
   // Peer spread check is approximate; rely on peer quotes
   double ps = (g_peer_ask - g_peer_bid) / g_point; if(ps > input_max_spread_points_peer) return;

   // Min balance checks on both peers (fail-safe: require fresh peer info)
   if(input_min_balance_usd > 0.0)
   {
      double m_bal = AccountInfoDouble(ACCOUNT_BALANCE); double s_bal=0.0; ulong s_ts=0;
      bool s_ok = ReadPeerBalanceFresh(s_bal, s_ts);
      if(m_bal < input_min_balance_usd) return;
      if(!s_ok || s_bal < input_min_balance_usd) return;
   }

   double diffOpen = DiffOpenPoints(); if(diffOpen < input_open_threshold_points) return;

   string cmd_id = NewCmdId(); g_last_cmd_id = cmd_id;

   // Dry run path: pretend master open succeeded then write open_cmd
   if(DryEnabled())
   {
      g_last_open_time = TimeCurrent();
      ulong created_ms = NowMs(); int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0)? DryOverrideExpireMs(): input_cmd_expire_ms;
      string lineDR = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.1f\n",
         cmd_id,(long)g_seq,cmd_id,g_symbol,((input_master_side==SIDE_BUY)?"BUY":"SELL"),input_lot_master,input_lot_slave,input_slippage_points,created_ms,expire_ms,input_open_threshold_points,input_close_threshold_points,
         g_self_bid,g_self_ask,g_peer_bid,g_peer_ask,diffOpen);
      FileWriteAllAtomic(PathOpenCmd(), lineDR);
      g_waiting_slave_open_ack=true; g_pending_open_cmd_id=cmd_id; g_pending_open_created_ms=created_ms; g_rollback_initiated=false;
      string ackSelf = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0);
      FileWriteAllAtomic(PathOpenAckSelf(), ackSelf);
      // Consolidated grace to avoid premature close/reconcile while awaiting/just after ACK
      g_last_peer_open_ack_ms = 0;
      g_open_grace_until_ms = NowMs() + (ulong)input_ack_timeout_ms;
      return;
   }

   // Real trading: send master order first
   ulong tkt=0; double price=0.0; bool ok = PlaceOrder((input_master_side==SIDE_BUY), input_lot_master, tkt, price);
   string ackSelf2 = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:(int)GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ackSelf2);
   if(!ok){ g_last_open_time = TimeCurrent(); return; }

   g_last_open_time = TimeCurrent();
   PairMapSelfUpsert(cmd_id, tkt); CacheUpsert(cmd_id, tkt); WritePositions(); CompactPairMapSelf();

   // Write open_cmd with audit
   ulong created_ms2 = NowMs(); int expire_ms2 = (DryEnabled() && DryOverrideExpireMs()>0)? DryOverrideExpireMs(): input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.1f\n",
      cmd_id,(long)g_seq,cmd_id,g_symbol,((input_master_side==SIDE_BUY)?"BUY":"SELL"),input_lot_master,input_lot_slave,input_slippage_points,created_ms2,expire_ms2,input_open_threshold_points,input_close_threshold_points,
      g_self_bid,g_self_ask,g_peer_bid,g_peer_ask,diffOpen);
   FileWriteAllAtomic(PathOpenCmd(), line);
   g_waiting_slave_open_ack=true; g_pending_open_cmd_id=cmd_id; g_pending_open_created_ms=created_ms2; g_rollback_initiated=false;
   // Consolidated grace to avoid premature close/reconcile while awaiting/just after ACK
   g_last_peer_open_ack_ms = 0;
   g_open_grace_until_ms = NowMs() + (ulong)input_ack_timeout_ms;
}

void MaybeClosePair()
{
   if(g_role_conflict) return;
   if(!(input_role==ROLE_MASTER)) return;
   // In debug mode, keep positions open until user clicks Close Now
   if(input_debug_buttons_enabled && g_debug_hold_open) return;
   // Do not auto-close while waiting for slave to acknowledge an open or just after it
   if(g_waiting_slave_open_ack && (NowMs()-g_pending_open_created_ms) <= (ulong)input_ack_timeout_ms) return;
   if(g_last_peer_open_ack_ms>0 && (NowMs()-g_last_peer_open_ack_ms) < (ulong)input_ack_timeout_ms) return;
   if(NowMs() < g_open_grace_until_ms) return;
   if(!ReadPeerQuotes()) return;
   if(!QuotesFresh()) return;
   // Close cooldown: avoid normal auto-close until elapsed; do not block reconcile paths elsewhere
   if(g_last_pair_both_open_time>0)
   {
      int el = (int)(TimeCurrent() - g_last_pair_both_open_time);
      if(el < input_close_cooldown_seconds) return;
   }
   double diffClose = DiffClosePoints(); if(diffClose < input_close_threshold_points) return;

   string cmd_id = NewCmdId(); ulong created_ms = NowMs();
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0)? DryOverrideExpireMs(): input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
   bool write_cmd = !(DryEnabled() && DryMode()==DRY_NONE);
   if(write_cmd) FileWriteAllAtomic(PathCloseCmd(), line);

   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      {
         int latency = DryDelayMs(); if(latency>0) Sleep(latency);
         string ackSelf = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0);
         FileWriteAllAtomic(PathCloseAckSelf(), ackSelf);
      }
      return;
   }

   bool ok = CloseAllByMagic(); CompactPairMapSelf(); WritePositions();
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:(int)GetLastError());
   FileWriteAllAtomic(PathCloseAckSelf(), ack);
}

void SlaveProcessOpenCmd()
{
   if(g_role_conflict) return;
   if(input_role==ROLE_MASTER) return;
   string s; if(!FileReadAll(PathOpenCmd(), s)) {
      // If command file missing for a while, no-op
      if(input_verbose_journal_logs) Print("[Slave] open_cmd.csv not found or not readable");
      return;
   }
   string fields[]; int n = StringSplit(TrimAll(s), ',', fields); if(n<11) {
      // malformed command; acknowledge failure
      string ackBad = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", "UNKNOWN", (long)g_seq, "N/A", "0.0", 0, 400);
      FileWriteAllAtomic(PathOpenAckSelf(), ackBad);
      if(input_verbose_journal_logs) Print("[Slave] Malformed open_cmd (n<11), wrote ACK fail 400");
      return;
   }
   string cmd_id = fields[1]; string pair_id = fields[3]; string sym=fields[4]; string mside=fields[5]; double lot_slave = StringToDouble(fields[7]);
   ulong created_ms = (ulong)StringToInteger(fields[9]); int expire_ms = (int)StringToInteger(fields[10]);
   // Idempotency: skip if already acknowledged/processed this cmd
   string sAckOpen; if(FileReadAll(PathOpenAckSelf(), sAckOpen)) { string af[]; int an = StringSplit(TrimAll(sAckOpen), ',', af); if(an>=2 && af[1]==cmd_id) { if(input_verbose_journal_logs) Print("[Slave] Skip open_cmd idempotent ACK for cmd_id=", cmd_id); return; } }
   if(g_last_processed_open_cmd_id == cmd_id) { if(input_verbose_journal_logs) Print("[Slave] Skip open_cmd duplicate cmd_id=", cmd_id); return; } g_last_processed_open_cmd_id = cmd_id;
   // cache for display
   g_have_master_cmd = true;
   g_last_cmd_side = mside;
   g_last_cmd_lot_master = StringToDouble(fields[6]);
   g_last_cmd_lot_slave  = lot_slave;
   g_last_cmd_seen_ms = NowMs();
   if(n >= 13)
   {
      g_have_master_th = true;
      g_last_cmd_open_th = (int)StringToInteger(fields[11]);
      g_last_cmd_close_th = (int)StringToInteger(fields[12]);
   }
   else g_have_master_th = false;
   // cache for display
   g_have_master_cmd = true;
   g_last_cmd_side = mside;
   g_last_cmd_lot_master = StringToDouble(fields[6]);
   g_last_cmd_lot_slave  = lot_slave;
   g_last_cmd_seen_ms = NowMs();
   if((NowMs()-created_ms) > (ulong)expire_ms)
   {
      // Acknowledge expired so master can rollback
      string ackExpired = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 0, 408);
      FileWriteAllAtomic(PathOpenAckSelf(), ackExpired);
      if(input_verbose_journal_logs) Print("[Slave] open_cmd expired cmd_id=", cmd_id, " age_ms=", (NowMs()-created_ms));
      return;
   }
   bool slaveBuy = (mside=="BUY")?false:true;
   if(input_verbose_journal_logs) Print("[Slave] Execute open cmd_id=", cmd_id, " pair=", pair_id, " side=", (slaveBuy?"SELL":"BUY"), " lot=", DoubleToString(lot_slave, 2));
   if(DryEnabled())
   {
      if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK)
      { int latency = DryDelayMs(); if(latency>0) Sleep(latency); string ackSelf = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0); FileWriteAllAtomic(PathOpenAckSelf(), ackSelf); if(input_verbose_journal_logs) Print("[Slave] DryRun ACK ok for cmd_id=", cmd_id); } return;
   }

   ulong tkt=0; double price=0.0; bool ok = PlaceOrder(slaveBuy, lot_slave, tkt, price);
   string ack = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:(int)GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ack);
   if(input_verbose_journal_logs) { if(ok) Print("[Slave] Order placed OK cmd_id=", cmd_id, " ticket=", (long)tkt, " price=", DoubleToString(price, g_digits)); else Print("[Slave] Order failed cmd_id=", cmd_id, " err=", GetLastError()); }
   if(ok){ PairMapSelfUpsert(pair_id, tkt); CacheUpsert(pair_id, tkt); WritePositions(); CompactPairMapSelf(); RebuildPairMapSelfFromCache(); WritePositions(); }
}

void SlaveProcessCloseCmd()
{
   if(g_role_conflict) return;
   if(input_role==ROLE_MASTER) return;
   string s; if(!FileReadAll(PathCloseCmd(), s)) return;
   string fields[]; int n = StringSplit(TrimAll(s), ',', fields); if(n<7) return;
   string cmd_id = fields[1]; string pair_id = fields[3]; ulong created_ms = (ulong)StringToInteger(fields[5]); int expire_ms=(int)StringToInteger(fields[6]);
   // Idempotency: skip if already acknowledged/processed this close
   string sAckClose; if(FileReadAll(PathCloseAckSelf(), sAckClose)) { string af[]; int an = StringSplit(TrimAll(sAckClose), ',', af); if(an>=2 && af[1]==cmd_id) return; }
   if(g_last_processed_close_cmd_id == cmd_id) return; g_last_processed_close_cmd_id = cmd_id;
   if((NowMs()-created_ms) > (ulong)expire_ms)
   {
      // expired close commands are acknowledged to help master reconcile
      string ackExpired = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 205);
      FileWriteAllAtomic(PathCloseAckSelf(), ackExpired);
      return;
   }

   if(DryEnabled())
   { if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ int latency=DryDelayMs(); if(latency>0) Sleep(latency); string ackSelf=StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAllAtomic(PathCloseAckSelf(), ackSelf);} return; }

   bool ok = false;
   if(StringFind(fields[4], "CLOSE_ONE")==0)
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
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:(int)GetLastError()); FileWriteAllAtomic(PathCloseAckSelf(), ack);
}

void WritePositions()
{
  string mapContent; string mapLines[]; int mapLn = 0; if(FileReadAll(PathPairMapSelf(), mapContent)) mapLn = StringSplit(TrimAll(mapContent), '\n', mapLines);
  // Build quick cache map for lookup
  int cn = ArraySize(g_cache_pair_ids);
  string buf = "";
  for(int i=PositionsTotal()-1; i>=0; --i)
  {
     ulong ticket = PositionGetTicket(i); if(!PositionSelectByTicket(ticket)) continue;
     if((string)PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
     if((long)PositionGetInteger(POSITION_MAGIC)!=g_magic) continue;
     string pid = "N/A";
     // Prefer in-memory cache first
     int cidx = CacheFindIndexByTicket(ticket); if(cidx>=0) pid = g_cache_pair_ids[cidx];
     for(int k=0;k<mapLn;k++){ string cols[]; int cn=StringSplit(TrimAll(mapLines[k]), ',', cols); if(cn>=2){ if((ulong)StringToInteger(cols[1])==ticket){ pid=cols[0]; break; } } }
     // Fallback: if still N/A, try newest position ticket mapping
     if(pid=="N/A")
     {
       ulong newest = GetNewestPositionTicket();
       if(newest==ticket)
       {
         for(int k=0;k<mapLn;k++){ string cols[]; int cn=StringSplit(TrimAll(mapLines[k]), ',', cols); if(cn>=2){ if((ulong)StringToInteger(cols[1])==ticket){ pid=cols[0]; break; } } }
       }
     }
     long type = PositionGetInteger(POSITION_TYPE);
     string side = (type==POSITION_TYPE_BUY)?"BUY":"SELL";
     double vol = PositionGetDouble(POSITION_VOLUME);
     double price = PositionGetDouble(POSITION_PRICE_OPEN);
     buf += StringFormat("%s,%I64d,%s,%s,%.2f,%.5f\n", pid, (long)ticket, g_symbol, side, vol, price);
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
// Debug buttons geometry
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
   for(int i=ObjectsTotal(0)-1; i>=0; --i)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, OBJ_PREFIX) == 0)
         ObjectDelete(0, nm);
   }
}

void DisplayInit()
{
   // Clear and recreate for stable z-order
   DisplayClearAll();
   // Background
   string bg = OBJ_PREFIX + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 0);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, input_display_width_pixels);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 210);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   // Title
   string name = OBJ_PREFIX + "MAIN";
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, DISPLAY_X);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, DISPLAY_Y_BASE);
   ObjectSetString(0, name, OBJPROP_TEXT, "### Display Monitor ###");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);

   // Debug buttons (Master only)
   if(input_debug_buttons_enabled && (input_role==ROLE_MASTER))
   {
      string b1 = OBJ_PREFIX + "BTN_OPEN";
      ObjectCreate(0, b1, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, b1, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, b1, OBJPROP_XDISTANCE, input_display_width_pixels + 20);
      ObjectSetInteger(0, b1, OBJPROP_YDISTANCE, BTN_Y1);
      ObjectSetInteger(0, b1, OBJPROP_XSIZE, BTN_W);
      ObjectSetInteger(0, b1, OBJPROP_YSIZE, BTN_H);
      ObjectSetString(0, b1, OBJPROP_TEXT, "Open Now");
      ObjectSetInteger(0, b1, OBJPROP_FONTSIZE, 8);

      string b2 = OBJ_PREFIX + "BTN_CLOSE";
      ObjectCreate(0, b2, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, b2, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, b2, OBJPROP_XDISTANCE, input_display_width_pixels + 20);
      ObjectSetInteger(0, b2, OBJPROP_YDISTANCE, BTN_Y2);
      ObjectSetInteger(0, b2, OBJPROP_XSIZE, BTN_W);
      ObjectSetInteger(0, b2, OBJPROP_YSIZE, BTN_H);
      ObjectSetString(0, b2, OBJPROP_TEXT, "Close Now");
      ObjectSetInteger(0, b2, OBJPROP_FONTSIZE, 8);
   }
}

void DisplaySetLine(const int idx, const string text)
{
   string name = OBJ_PREFIX + "LINE_" + IntegerToString(idx);
   if(ObjectFind(0, name) == -1)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, DISPLAY_X);
   }
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, DISPLAY_Y_BASE + (idx+DISPLAY_FIRST_LINE_OFFSET)*DISPLAY_LINE_SPACING);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, DISPLAY_FONT_SIZE);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
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
      for(int i=cut; i>0; --i)
      {
         if(StringGetCharacter(remaining, i-1) == ' '){ cut = i; break; }
      }
      if(cut <= 0 || cut > len) cut = maxChars;
      string part = StringSubstr(remaining, 0, cut);
      DisplaySetLine(lineIndex++, part);
      StringTrimLeft(remaining); // ensure no leading spaces after substr
      remaining = TrimAll(StringSubstr(remaining, cut));
   }
   return lineIndex;
}

void DisplayUpdate()
{
   string role = (input_role==ROLE_MASTER)?"MASTER":"SLAVE";
   int spread = SpreadPointsSelf();
   double dOpen = DiffOpenPoints();
   double dClose = DiffClosePoints();
   int line = 0;
   DisplaySetLine(line++, StringFormat("role=%s  channel=%s  symbol=%s", role, input_channel_id, g_symbol));
   line = DisplaySetWrappedLines(line, StringFormat("sync_path=%s", PathChannelRootAbs()));
   string syncTxt = g_peer_alive?"OK":"WAITING";
   int hb_age = (int)(NowMs() - g_peer_hb_ms);
   string activeTxt = g_peer_alive?"YES":"NO";
   DisplaySetLine(line++, StringFormat("sync=%s  peer_hb_age=%dms  active=%s", syncTxt, hb_age, activeTxt));
   if(input_role==ROLE_MASTER)
   {
      DisplaySetLine(line++, StringFormat("lot(m/s)=%.2f/%.2f  side(M)=%s", input_lot_master, input_lot_slave, ((input_master_side==SIDE_BUY)?"BUY":"SELL")));
      DisplaySetLine(line++, StringFormat("open_th=%d  close_th=%d  spread=%d", input_open_threshold_points, input_close_threshold_points, spread));
      int cd = CooldownRemainSeconds(); string cdLeft = (cd>=0)? IntegerToString(cd):"-";
      int closeLeft = -1; if(g_last_pair_both_open_time>0){ int el=(int)(TimeCurrent()-g_last_pair_both_open_time); int rem=input_close_cooldown_seconds-el; if(rem<0) rem=0; closeLeft=rem; }
      // Split into two lines to avoid clipping on narrow charts
      DisplaySetLine(line++, StringFormat("open_cooldown=%ds left=%s  close_cooldown=%ds left=%s",
         input_open_cooldown_seconds, cdLeft, input_close_cooldown_seconds, (closeLeft>=0?IntegerToString(closeLeft):"0")));
      DisplaySetLine(line++, StringFormat("max_pairs=%d  open_now=%d", input_max_open_pairs, CountOpenPairs()));
   }
   else
   {
      if(!g_have_master_cmd) ReadMasterConfig();
      if(g_have_master_cmd)
      {
         string sideS = (g_last_cmd_side=="BUY")?"SELL":"BUY";
         DisplaySetLine(line++, StringFormat("lot(M/S)=%.2f/%.2f  side(S)=%s", g_last_cmd_lot_master, g_last_cmd_lot_slave, sideS));
         if(g_have_master_th)
            DisplaySetLine(line++, StringFormat("th(M): open=%d close=%d", g_last_cmd_open_th, g_last_cmd_close_th));
      }
      DisplaySetLine(line++, StringFormat("spread=%d", spread));
      int closeLeftS=-1; if(g_last_pair_both_open_time>0){ int el=(int)(TimeCurrent()-g_last_pair_both_open_time); int rem=g_master_close_cooldown_seconds-el; if(rem<0) rem=0; closeLeftS=rem; }
      DisplaySetLine(line++, StringFormat("close_cooldown=%ds left=%s", g_master_close_cooldown_seconds, (closeLeftS>=0?IntegerToString(closeLeftS):"-")));
   }
   DisplaySetLine(line++, StringFormat("diffOpen=%.1f  diffClose=%.1f  fresh=%s", dOpen, dClose, (QuotesFresh()?"OK":"STALE")));
   if(g_role_conflict) DisplaySetLine(line++, "role_conflict=YES (single-instance per channel)" );
   int effMode = DryMode();
   string dryMode = (effMode==DRY_NONE?"NONE":(effMode==DRY_WRITE_CMD_ONLY?"WRITE_CMD_ONLY":"WRITE_CMD_AND_FAKE_ACK"));
   DisplaySetLine(line++, StringFormat("dry_run=%s mode=%s", (DryEnabled()?"ON":"OFF"), dryMode));

   string bg2 = OBJ_PREFIX + "BG";
   if(ObjectFind(0, bg2) != -1)
   {
     int h = (DISPLAY_FIRST_LINE_OFFSET + line) * DISPLAY_LINE_SPACING + 38;
     ObjectSetInteger(0, bg2, OBJPROP_XDISTANCE, 0);
     ObjectSetInteger(0, bg2, OBJPROP_YDISTANCE, 0);
     ObjectSetInteger(0, bg2, OBJPROP_XSIZE, input_display_width_pixels);
     ObjectSetInteger(0, bg2, OBJPROP_YSIZE, h);
     ObjectSetInteger(0, bg2, OBJPROP_COLOR, clrWhite);
     ObjectSetInteger(0, bg2, OBJPROP_BACK, false);
   }
}

// Debug actions (master only)
void MasterOpenNow()
{
   if(!(input_role==ROLE_MASTER)) return;

   string cmd_id = NewCmdId(); g_last_cmd_id = cmd_id; ulong created_ms = NowMs();
   int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0)? DryOverrideExpireMs(): input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%s,%.2f,%.2f,%d,%I64u,%d,%d,%d\n", cmd_id, (long)g_seq, cmd_id, g_symbol, ((input_master_side==SIDE_BUY)?"BUY":"SELL"), input_lot_master, input_lot_slave, input_slippage_points, created_ms, expire_ms, input_open_threshold_points, input_close_threshold_points);
   FileWriteAllAtomic(PathOpenCmd(), line);
   g_waiting_slave_open_ack = true; g_pending_open_cmd_id=cmd_id; g_pending_open_created_ms=created_ms; g_rollback_initiated=false;
   g_last_peer_open_ack_ms = 0; // reset grace timer
   g_open_grace_until_ms = NowMs() + (ulong)input_ack_timeout_ms;
   if(input_debug_buttons_enabled) g_debug_hold_open = true; // keep open until Close Now

   if(DryEnabled())
   { if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf = StringFormat("1,%s,%I64d,%s,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", "0.0", 1, 0); FileWriteAllAtomic(PathOpenAckSelf(), ackSelf);} g_last_open_time=TimeCurrent(); g_open_grace_until_ms = NowMs() + (ulong)input_ack_timeout_ms; return; }

   ulong tkt=0; double price=0.0; bool ok = PlaceOrder((input_master_side==SIDE_BUY), input_lot_master, tkt, price);
   string ack = StringFormat("1,%s,%I64d,%s,%.5f,%d,%d\n", cmd_id, (long)g_seq, "N/A", price, ok?1:0, ok?0:(int)GetLastError());
   FileWriteAllAtomic(PathOpenAckSelf(), ack);
   if(ok){ g_last_open_time = TimeCurrent(); PairMapSelfUpsert(cmd_id, tkt); CacheUpsert(cmd_id, tkt); WritePositions(); CompactPairMapSelf();}
}

void MasterCloseNow()
{
   if(!(input_role==ROLE_MASTER)) return;
   // Release the debug hold so close can proceed
   if(input_debug_buttons_enabled) g_debug_hold_open = false;
   string cmd_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = (DryEnabled() && DryOverrideExpireMs()>0)? DryOverrideExpireMs(): input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", cmd_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
   FileWriteAllAtomic(PathCloseCmd(), line);
   if(DryEnabled()){ if(DryMode()==DRY_WRITE_CMD_AND_FAKE_ACK){ string ackSelf=StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", 1, 0); FileWriteAllAtomic(PathCloseAckSelf(), ackSelf);} return; }
   bool ok = CloseAllByMagic(); CompactPairMapSelf(); WritePositions(); string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", cmd_id, (long)g_seq, "N/A", ok?1:0, ok?0:(int)GetLastError()); FileWriteAllAtomic(PathCloseAckSelf(), ack);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!input_debug_buttons_enabled) return; if(!(input_role==ROLE_MASTER)) return;
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam==OBJ_PREFIX+"BTN_OPEN") { MasterOpenNow(); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam==OBJ_PREFIX+"BTN_CLOSE") { MasterCloseNow(); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
   }
}

// -----------------------------
// Lifecycle
// -----------------------------
int OnInit()
{
   g_symbol = (input_symbol=="" ? _Symbol : input_symbol);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_magic  = input_magic_number_base + (int)StringGetCharacter(input_channel_id, 0);
   FolderEnsure();
   if(!AcquireRoleLock()) { g_role_conflict = true; }
   DisplayInit();
   // Use millisecond timer for faster file polling in MQL5
   if(input_file_poll_ms>=10) EventSetMillisecondTimer(input_file_poll_ms); else EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // best effort: release lock
   FileDelete(PathRoleLock(), FILE_COMMON);
   // Remove all chart objects only when EA is explicitly removed by user
   if(reason == REASON_REMOVE)
   {
      ObjectsDeleteAll(0, -1, -1);
      ChartRedraw(0);
   }
   DisplayClearAll();
}

bool TryReadPeerOpenAck(string &ack_cmd_id, int &ok_out)
{
   string s; if(!FileReadAll(PathOpenAckPeer(), s)) return false;
   string fields[]; int n = StringSplit(TrimAll(s), ',', fields); if(n<6) return false;
   ack_cmd_id = fields[1];
   // fields: 0=ver,1=cmd_id,2=seq,3=pair,4=price,5=ok,6=error
   ok_out = (n>=6) ? (int)StringToInteger(fields[5]) : 0;
   if(ok_out==1) g_last_peer_open_ack_ms = NowMs();
   return true;
}

void MasterRollbackOpen()
{
   if(g_rollback_initiated) return;
   g_rollback_initiated = true;
   string close_id = NewCmdId(); ulong created_ms = NowMs(); int expire_ms = input_cmd_expire_ms;
   string line = StringFormat("1,%s,%I64d,%s,%s,%I64u,%d\n", close_id, (long)g_seq, "N/A", "CLOSE", created_ms, expire_ms);
   FileWriteAll(PathCloseCmd(), line);
   bool ok = CloseAllByMagic();
   string ack = StringFormat("1,%s,%I64d,%s,%d,%d\n", close_id, (long)g_seq, "N/A", ok?1:0, ok?0:(int)GetLastError());
   FileWriteAll(PathCloseAckSelf(), ack);
   g_waiting_slave_open_ack = false; g_pending_open_cmd_id = "";
}

void MasterWatchdogOpen()
{
  if(!(input_role==ROLE_MASTER)) return;
  if(!g_waiting_slave_open_ack) return;
  // In debug hold mode, do not rollback open; wait until user presses Close Now
  if(input_debug_buttons_enabled && g_debug_hold_open) return;
  if((NowMs() - g_pending_open_created_ms) > (ulong)input_ack_timeout_ms) { MasterRollbackOpen(); return; }
  string ack_id; int ok;
  if(TryReadPeerOpenAck(ack_id, ok))
  {
    if(ack_id==g_pending_open_cmd_id)
    {
      if(ok==1) { g_waiting_slave_open_ack=false; g_pending_open_cmd_id=""; g_last_pair_both_open_time = TimeCurrent(); }
      else { MasterRollbackOpen(); }
    }
  }
}

void OnTimer()
{
   if(!(input_role==ROLE_MASTER)) ReadMasterConfig();
   WriteHeartbeat();
   UpdatePeerStatus();
   if(!g_role_conflict) WriteRoleLock();
   CacheCompactCurrentPositions();
   WritePositions();
   CompactPairMapSelf();
   RebuildPairMapSelfFromCache();
   WritePositions();
   MasterWatchdogOpen();
   MasterReconcilePositions();
   if(input_role==ROLE_MASTER) { MaybeClosePair(); }
   else { SlaveProcessOpenCmd(); SlaveProcessCloseCmd(); SlaveLocalReconcile(); }
   DisplayUpdate();
}

void OnTick()
{
   WriteQuotes();
   ReadPeerQuotes();
   UpdatePeerStatus();
   if(input_role==ROLE_MASTER) { MaybeOpenPair(); MaybeClosePair(); }
   else { SlaveProcessOpenCmd(); SlaveProcessCloseCmd(); }
   DisplayUpdate();
}