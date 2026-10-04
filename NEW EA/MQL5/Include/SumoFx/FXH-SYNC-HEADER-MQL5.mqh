// Slave stream (required): SLAVE;bid;ask;symbol;quote_msc;trade_mode;srv_ms;profit;balance~
#ifndef __FXH_SYNC_HEADER_MQL5_MQH__
#define __FXH_SYNC_HEADER_MQL5_MQH__

#ifndef SFX_SYNC_PROTOCOL_VERSION
#define SFX_SYNC_PROTOCOL_VERSION SFX_SYNC_EA_VERSION
#endif

double SumMagicSymbolPnl()
{
   double sum = 0.0;
   const long magic = (long)OrderMagic();
   for(int i = (int)PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != G_SYMBOL)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      // MT4 adds OrderProfit+OrderSwap+OrderCommission; MT5 exposes commission per deal (POSITION_COMMISSION deprecated).
      sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return sum;
}

double DiffPoint()
{
   double pt = SymbolInfoDouble(G_SYMBOL, SYMBOL_POINT);
   if(pt <= 0.0)
      pt = _Point;
   return pt;
}

// Align master/slave quote magnitudes before diff: 4–5 digit symbols → 5 dp; 2–3 → 2 dp; otherwise use broker digits.
int DiffQuoteNormDigits()
{
   const int d = (int)SymbolInfoInteger(G_SYMBOL, SYMBOL_DIGITS);
   if(d >= 4 && d <= 5)
      return 5;
   if(d >= 2 && d <= 3)
      return 2;
   return d;
}

double DiffNormQuotePrice(const double price)
{
   return NormalizeDouble(price, DiffQuoteNormDigits());
}

int DiffSpreadPts(const double bid, const double ask)
{
   double pt = DiffPoint();
   if(pt <= 0.0)
      return 999999;
   double sp = ask - bid;
   if(sp < 0.0)
      sp = 0.0;
   return (int)MathRound(sp / pt);
}

// Mirrors MQL4 IsTradeAllowed(): EA may trade (not symbol-specific).
bool DiffTerminalTradeAllowedLikeMql4()
{
   return (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) && (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
}

bool DiffSymbolTradableForDiff()
{
   return DiffTerminalTradeAllowedLikeMql4();
}

void DiffQuoteMonitorOnMasterGap(const ulong delta_ms)
{
   G_QMON_N_M++;
   const double a_up = 0.14;
   const double a_dn = 0.032;
   const double d = (double)delta_ms;
   if(G_QMON_N_M <= 1)
      G_QMON_EMA_GAP_M = d;
   else
   {
      const double a = (d >= G_QMON_EMA_GAP_M) ? a_up : a_dn;
      G_QMON_EMA_GAP_M = a * d + (1.0 - a) * G_QMON_EMA_GAP_M;
   }
   DiffQuoteMonitorRenormalizeCountersIfNearOverflow();
}

void DiffQuoteMonitorOnSlaveGap(const ulong delta_ms)
{
   G_QMON_N_S++;
   const double a_up = 0.14;
   const double a_dn = 0.032;
   const double d = (double)delta_ms;
   if(G_QMON_N_S <= 1)
      G_QMON_EMA_GAP_S = d;
   else
   {
      const double a = (d >= G_QMON_EMA_GAP_S) ? a_up : a_dn;
      G_QMON_EMA_GAP_S = a * d + (1.0 - a) * G_QMON_EMA_GAP_S;
   }
   DiffQuoteMonitorRenormalizeCountersIfNearOverflow();
}

void DiffQuoteMonitorRenormalizeCountersIfNearOverflow()
{
   const int cap = 2000000000;
   if(G_QMON_N_M < cap && G_QMON_N_S < cap)
      return;
   bool wasWarm = false;
   if(I_DIFF_QUOTES_FRESH_AUTO && I_DIFF_QF_AUTO_WARMUP_N > 0 &&
      G_QMON_N_M >= I_DIFF_QF_AUTO_WARMUP_N && G_QMON_N_S >= I_DIFF_QF_AUTO_WARMUP_N)
      wasWarm = true;
   G_QMON_N_M = 0;
   G_QMON_N_S = 0;
   if(wasWarm && I_DIFF_QF_AUTO_WARMUP_N > 0)
   {
      G_QMON_N_M = I_DIFF_QF_AUTO_WARMUP_N;
      G_QMON_N_S = I_DIFF_QF_AUTO_WARMUP_N;
   }
}

void DiffQuoteMonitorInit()
{
   G_QMON_START_MS = NowMs();
   G_QMON_MASTER_TICKS = 0;
   G_QMON_SLAVE_FRAMES = 0;
   G_QMON_EMA_GAP_M = 0.0;
   G_QMON_EMA_GAP_S = 0.0;
   G_QMON_N_M = 0;
   G_QMON_N_S = 0;
}

bool DiffAutoFreshWarmupComplete()
{
   if(!I_DIFF_QUOTES_FRESH_AUTO)
      return false;
   if(I_DIFF_QF_AUTO_WARMUP_N <= 0)
      return false;
   if(G_QMON_N_M < I_DIFF_QF_AUTO_WARMUP_N || G_QMON_N_S < I_DIFF_QF_AUTO_WARMUP_N)
      return false;
   return true;
}

long DiffAutoFreshMsUnclampedLong()
{
   const double base = MathMax(G_QMON_EMA_GAP_M, G_QMON_EMA_GAP_S);
   return (long)MathFloor(base * I_DIFF_QF_AUTO_MUL + (double)I_DIFF_QF_AUTO_MARGIN_MS);
}

// HUD: |master_obs_age_ms - slave_obs_age_ms| at NowMs(); -1 if either side has no observation timestamp yet.
int DiffHudQuoteObsAgeSkewMs()
{
   const ulong nw = NowMs();
   if(G_DIFF_SELF_MS == 0 || G_DIFF_SLAVE_MS == 0)
      return -1;
   long age_self = (long)(nw - G_DIFF_SELF_MS);
   long age_slave = (long)(nw - G_DIFF_SLAVE_MS);
   long skew = age_self - age_slave;
   if(skew < 0)
      skew = -skew;
   return (int)skew;
}

int DiffEffectiveQuotesFreshMs()
{
   if(!I_DIFF_QUOTES_FRESH_AUTO)
      return I_DIFF_QUOTES_FRESH_MS;
   if(!DiffAutoFreshWarmupComplete())
      return I_DIFF_QUOTES_FRESH_MS;
   long v = DiffAutoFreshMsUnclampedLong();
   int mn = I_DIFF_QF_AUTO_MIN_MS;
   int mx = I_DIFF_QF_AUTO_MAX_MS;
   if(mn < 50)
      mn = 50;
   if(mx < mn)
      mx = mn;
   if(v < (long)mn)
      v = (long)mn;
   if(v > (long)mx)
      v = (long)mx;
   return (int)v;
}

void DiffRefreshMasterQuotes()
{
   MqlTick tk;
   double bid = 0.0, ask = 0.0;
   ulong qm = 0;
   if(SymbolInfoTick(G_SYMBOL, tk))
   {
      bid = tk.bid;
      ask = tk.ask;
      qm = tk.time_msc;
      if(qm == 0)
         qm = (ulong)tk.time * 1000UL;
   }
   else
   {
      bid = SymbolInfoDouble(G_SYMBOL, SYMBOL_BID);
      ask = SymbolInfoDouble(G_SYMBOL, SYMBOL_ASK);
      const datetime tq = (datetime)SymbolInfoInteger(G_SYMBOL, SYMBOL_TIME);
      qm = (ulong)tq * 1000UL;
   }
   G_DIFF_SELF_BID = DiffNormQuotePrice(bid);
   G_DIFF_SELF_ASK = DiffNormQuotePrice(ask);
   const bool newTick = (qm > 0 && qm != G_DIFF_SELF_LAST_TICK_MSC);
   if(newTick)
      G_DIFF_SELF_LAST_TICK_MSC = qm;
   const bool trad = DiffSymbolTradableForDiff();
   bool bump = false;
   if(newTick)
      bump = true;
   else if(trad)
      bump = true;
   if(!bump)
      return;
   const ulong nowm = NowMs();
   if(G_DIFF_SELF_MS > 0 && (nowm - G_DIFF_SELF_MS) > 0 && (nowm - G_DIFF_SELF_MS) < 300000)
      DiffQuoteMonitorOnMasterGap(nowm - G_DIFF_SELF_MS);
   G_DIFF_SELF_MS = nowm;
}

double DiffOpenPtsFor(const bool masterBuy)
{
   double pt = DiffPoint();
   if(pt <= 0.0)
      return 0.0;
   const double mb = G_DIFF_SELF_BID, ma = G_DIFF_SELF_ASK, sb = G_DIFF_SLAVE_BID, sa = G_DIFF_SLAVE_ASK;
   const double diff = masterBuy ? (sb - ma) : (mb - sa);
   return diff / pt;
}

double DiffClosePtsFor(const bool masterBuy)
{
   double pt = DiffPoint();
   if(pt <= 0.0)
      return 0.0;
   const double mb = G_DIFF_SELF_BID, ma = G_DIFF_SELF_ASK, sb = G_DIFF_SLAVE_BID, sa = G_DIFF_SLAVE_ASK;
   const double diff = masterBuy ? (mb - sa) : (sb - ma);
   return diff / pt;
}

double DiffOpenPts()
{
   return DiffOpenPtsFor(DiffMasterBuyEffective());
}

double DiffClosePts()
{
   return DiffClosePtsFor(DiffMasterBuyEffective());
}

string DiffHudFormatQuoteTugBar(const double slaveShare)
{
   double sh = slaveShare;
   if(sh < 0.0)
      sh = 0.0;
   if(sh > 1.0)
      sh = 1.0;
   const int W = 17;
   int pos = (int)MathRound(sh * (double)(W - 1));
   if(pos < 0)
      pos = 0;
   if(pos >= W)
      pos = W - 1;
   string bar = "M";
   for(int i = 0; i < W; i++)
   {
      if(i == pos)
         bar += "|";
      else if(i < pos)
         bar += "#";
      else
         bar += ".";
   }
   bar += "S";
   return bar;
}

string DiffHudQuoteMonitorBlock()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return "";
   if(!G_HANDSHAKE_OK)
      return "\nQUOTE MONITOR: (no slave yet)\n";
   const ulong nw = NowMs();
   const ulong el = (nw > G_QMON_START_MS) ? (nw - G_QMON_START_MS) : (ulong)1;
   const double rm = (double)G_QMON_MASTER_TICKS * 60000.0 / (double)el;
   const double rs = (double)G_QMON_SLAVE_FRAMES * 60000.0 / (double)el;
   double share = 0.5;
   if(rm + rs > 1e-9)
      share = rs / (rm + rs);
   const int eff = DiffEffectiveQuotesFreshMs();
   const int skewHud = DiffHudQuoteObsAgeSkewMs();
   const string skewStr = (skewHud < 0) ? "n/a" : StringFormat("%dms", skewHud);
   const string mode = I_DIFF_QUOTES_FRESH_AUTO ? "AUTO" : "MANUAL";
   const int ageM = (G_DIFF_SELF_MS > 0) ? (int)(nw - G_DIFF_SELF_MS) : -1;
   const int ageS = (G_DIFF_SLAVE_MS > 0) ? (int)(nw - G_DIFF_SLAVE_MS) : -1;
   ResetLastError();
   int master_tm = (int)SymbolInfoInteger(G_SYMBOL, SYMBOL_TRADE_MODE);
   if(GetLastError() != 0)
   {
      ResetLastError();
      master_tm = DiffTerminalTradeAllowedLikeMql4() ? 4 : 0;
   }
   string s = "\n";
   s += StringFormat("QUOTE MONITOR: ticks M=%I64u S=%I64u  ~evt/min M=%.0f S=%.0f\n",
                     G_QMON_MASTER_TICKS, G_QMON_SLAVE_FRAMES, rm, rs);
   s = s + StringFormat("  EMA gap ms M=%.1f S=%.1f  fresh=%dms [%s]  skew=%s  ", G_QMON_EMA_GAP_M, G_QMON_EMA_GAP_S, eff, mode, skewStr) +
       DiffHudFormatQuoteTugBar(share) + "\n";
   s += StringFormat(
      "  obs.age ms M=%d S=%d  master qmsc=%I64u master.SYMBOL_TRADE_MODE=%d  slave qmsc=%I64u slave.SYMBOL_TRADE_MODE=%d\n",
      ageM, ageS, G_DIFF_SELF_LAST_TICK_MSC, master_tm, G_DIFF_SLAVE_QUOTE_MSC, G_DIFF_SLAVE_TRADE_MODE);
   const int digs = DiffQuoteNormDigits();
   s += StringFormat("  price  M bid=%s ask=%s  |  S bid=%s ask=%s\n",
                     DoubleToString(G_DIFF_SELF_BID, digs), DoubleToString(G_DIFF_SELF_ASK, digs),
                     DoubleToString(G_DIFF_SLAVE_BID, digs), DoubleToString(G_DIFF_SLAVE_ASK, digs));
   return s;
}

bool DiffSlaveStreamTradeAllowed()
{
   if(G_DIFF_SLAVE_TRADE_MODE < 0)
      return false;
   return (G_DIFF_SLAVE_TRADE_MODE != 0);
}

bool DiffQuotesFresh()
{
   const int lim = DiffEffectiveQuotesFreshMs();
   const ulong nw = NowMs();
   if(!G_DIFF_SLAVE_QUOTE_OK)
      return false;
   if(G_DIFF_SELF_MS == 0 || G_DIFF_SLAVE_MS == 0)
      return false;
   if(!DiffSlaveStreamTradeAllowed())
      return false;
   const long age_self = (long)(nw - G_DIFF_SELF_MS);
   const long age_slave = (long)(nw - G_DIFF_SLAVE_MS);
   return age_self <= (long)lim && age_slave <= (long)lim;
}

bool DiffHudOpenCooldownRemainMs(ulong &remMsOut)
{
   remMsOut = 0;
   if(I_DIFF_OPEN_COOLDOWN_SEC <= 0)
      return false;
   if(G_DIFF_LAST_OPEN_SIGNAL_MS == 0)
      return false;
   const ulong nw = NowMs();
   const ulong cdMs = (ulong)I_DIFF_OPEN_COOLDOWN_SEC * 1000UL;
   if((nw - G_DIFF_LAST_OPEN_SIGNAL_MS) >= cdMs)
      return false;
   remMsOut = cdMs - (nw - G_DIFF_LAST_OPEN_SIGNAL_MS);
   return true;
}

bool DiffHudAvgOpenCooldownRemainMs(ulong &remMsOut)
{
   remMsOut = 0;
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG || I_DIFF_AVG_SIGNAL_COOLDOWN_MS <= 0)
      return false;
   if(G_DIFF_LAST_AVG_OPEN_SIG_MS == 0)
      return false;
   const ulong nw = NowMs();
   const ulong cdMs = (ulong)I_DIFF_AVG_SIGNAL_COOLDOWN_MS;
   if((nw - G_DIFF_LAST_AVG_OPEN_SIG_MS) >= cdMs)
      return false;
   remMsOut = cdMs - (nw - G_DIFF_LAST_AVG_OPEN_SIG_MS);
   return true;
}

bool DiffHudAvgCloseCooldownRemainMs(ulong &remMsOut)
{
   remMsOut = 0;
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG || I_DIFF_AVG_SIGNAL_COOLDOWN_MS <= 0)
      return false;
   if(G_DIFF_LAST_AVG_CLOSE_SIG_MS == 0)
      return false;
   const ulong nw = NowMs();
   const ulong cdMs = (ulong)I_DIFF_AVG_SIGNAL_COOLDOWN_MS;
   if((nw - G_DIFF_LAST_AVG_CLOSE_SIG_MS) >= cdMs)
      return false;
   remMsOut = cdMs - (nw - G_DIFF_LAST_AVG_CLOSE_SIG_MS);
   return true;
}

bool DiffHudCloseCooldownRemainMs(ulong &remMsOut)
{
   remMsOut = 0;
   if(I_DIFF_CLOSE_COOLDOWN_SEC <= 0)
      return false;
   if(G_DIFF_LAST_CLOSE_SIGNAL_MS == 0)
      return false;
   const ulong nw = NowMs();
   const ulong cdMs = (ulong)I_DIFF_CLOSE_COOLDOWN_SEC * 1000UL;
   if((nw - G_DIFF_LAST_CLOSE_SIGNAL_MS) >= cdMs)
      return false;
   remMsOut = cdMs - (nw - G_DIFF_LAST_CLOSE_SIGNAL_MS);
   return true;
}

string DiffHudFormatRemainMs(const ulong remMs)
{
   if(remMs >= 60000)
      return StringFormat("%um %02us left", (uint)(remMs / 60000), (uint)((remMs / 1000) % 60));
   if(remMs >= 1000)
      return StringFormat("%us left", (uint)(remMs / 1000));
   return StringFormat("%ums left", (uint)remMs);
}

string DiffHudStaleSpreadTags()
{
   string parts = "";
   if(!DiffQuotesFresh())
      parts = "stale";
   const int sSelf = DiffSpreadPts(G_DIFF_SELF_BID, G_DIFF_SELF_ASK);
   const int sPeer = DiffSpreadPts(G_DIFF_SLAVE_BID, G_DIFF_SLAVE_ASK);
   const bool om = sSelf > I_DIFF_MAX_SPREAD_SELF;
   const bool op = sPeer > I_DIFF_MAX_SPREAD_PEER;
   if(om || op)
   {
      if(StringLen(parts) > 0)
         parts += "; ";
      if(om && op)
         parts += StringFormat("spread master %d > max %d, slave %d > max %d",
                               sSelf, I_DIFF_MAX_SPREAD_SELF, sPeer, I_DIFF_MAX_SPREAD_PEER);
      else if(om)
         parts += StringFormat("spread master %d > max %d", sSelf, I_DIFF_MAX_SPREAD_SELF);
      else
         parts += StringFormat("spread slave %d > max %d", sPeer, I_DIFF_MAX_SPREAD_PEER);
   }
   return parts;
}

string DiffHudWarningSuffixTags(const bool includeOpenCd, const bool includeCloseCd)
{
   string parts = DiffHudStaleSpreadTags();
   if(includeOpenCd)
   {
      ulong remO = 0;
      if(DiffHudOpenCooldownRemainMs(remO))
      {
         if(StringLen(parts) > 0)
            parts += "; ";
         parts += "cooldown open";
      }
      ulong remA = 0;
      if(DiffHudAvgOpenCooldownRemainMs(remA))
      {
         if(StringLen(parts) > 0)
            parts += "; ";
         parts += "avg open cd";
      }
   }
   if(includeCloseCd)
   {
      ulong remC = 0;
      if(DiffHudCloseCooldownRemainMs(remC))
      {
         if(StringLen(parts) > 0)
            parts += "; ";
         parts += "cooldown close";
      }
      ulong remAc = 0;
      if(DiffHudAvgCloseCooldownRemainMs(remAc))
      {
         if(StringLen(parts) > 0)
            parts += "; ";
         parts += "avg close cd";
      }
   }
   if(StringLen(parts) == 0)
      return "";
   return " — " + parts;
}

string DiffHudWarningSuffixOpen()
{
   return DiffHudWarningSuffixTags(true, false);
}

string DiffHudWarningSuffixClose()
{
   return DiffHudWarningSuffixTags(false, true);
}

string DiffHudWarningSuffixPl()
{
   return DiffHudWarningSuffixTags(false, false);
}

bool     G_NEG_ARMED_OPEN = false;
double   G_NEG_SNAP_OPEN = 0.0;
bool     G_NEG_ARMED_CLOSE = false;
double   G_NEG_SNAP_CLOSE = 0.0;
int      G_NEG_STREAK_OPEN = 0;
int      G_NEG_STREAK_CLOSE = 0;
bool     G_NEG_TRIGGER_OPEN = false;
bool     G_NEG_TRIGGER_CLOSE = false;
datetime G_NEG_HIST_TIME[5];
int      G_NEG_HIST_OPEN[5];
double   G_NEG_HIST_PTS[5];
int      G_NEG_HIST_COUNT = 0;
bool     G_FA_LAST_REALIZED_OK = false;
double   G_FA_LAST_REALIZED_PTS = 0.0;

#define SFX_NEG_GV_MAX 63
#define SFX_NOTIFY_MSG_MAX 255
#define SFX_NOTIFY_QUEUE_FILE "SFX-SYNC-notify-queue.txt"

int NegDiffNeedCount();
void NegDiffMaybeTouchDaily();

int      G_NEG_GV_TOUCH_DAY = -1;
bool     G_NOTIFY_PUSH_OK = false;
string   G_HUD_BANNER = "";
ulong    G_HUD_BANNER_UNTIL_MS = 0;
string   G_NOTIFY_HUD_STICKY = "";
string   G_NEG_HUD_STICKY = "";
bool     G_NOTIFY_PAIR_BROKEN_EPISODE = false;
string   G_NOTIFY_FILE_PENDING = "";
int      G_NOTIFY_SEQ = 0;

string NotifyTrim(const string s)
{
   string t = s;
   t = StringTrimLeft(t);
   t = StringTrimRight(t);
   return t;
}

string NotifyClip255(const string s)
{
   if(StringLen(s) <= SFX_NOTIFY_MSG_MAX)
      return s;
   return StringSubstr(s, 0, SFX_NOTIFY_MSG_MAX);
}

string NotifyRoleName()
{
   return (I_ROLE == ROLE_SOURCE_MASTER) ? "MASTER" : "SLAVE";
}

bool NotifyPushWanted()
{
   return (I_NOTIFY_CHANNEL == NOTIFY_MT_PUSH || I_NOTIFY_CHANNEL == NOTIFY_BOTH);
}

bool NotifyTelegramWanted()
{
   return (I_NOTIFY_CHANNEL == NOTIFY_TELEGRAM || I_NOTIFY_CHANNEL == NOTIFY_BOTH);
}

bool NotifyPushActive()
{
   return (NotifyPushWanted() && G_NOTIFY_PUSH_OK);
}

bool NotifyIsMasterSender()
{
   return (I_ROLE == ROLE_SOURCE_MASTER);
}

void NotifyHudStickyAppend(const string msg)
{
   if(StringLen(msg) <= 0)
      return;
   if(StringLen(G_NOTIFY_HUD_STICKY) <= 0)
      G_NOTIFY_HUD_STICKY = msg;
   else if(StringFind(G_NOTIFY_HUD_STICKY, msg) < 0)
      G_NOTIFY_HUD_STICKY += " | " + msg;
}

void HudBannerSet(const string msg, const int hold_sec)
{
   G_HUD_BANNER = msg;
   G_HUD_BANNER_UNTIL_MS = NowMs() + (ulong)MathMax(1, hold_sec) * 1000;
}

string HudBannerBlock()
{
   string out = "";
   if(StringLen(G_NEG_HUD_STICKY) > 0)
      out += "\nNEG: " + G_NEG_HUD_STICKY + "\n";
   if(StringLen(G_NOTIFY_HUD_STICKY) > 0)
      out += "\nNOTIFY: " + G_NOTIFY_HUD_STICKY + "\n";
   if(StringLen(G_HUD_BANNER) > 0 && NowMs() <= G_HUD_BANNER_UNTIL_MS)
      out += "\nNOTIFY: " + G_HUD_BANNER + "\n";
   return out;
}

long NotifyAccountLogin()
{
   return (long)AccountInfoInteger(ACCOUNT_LOGIN);
}

string NotifySanitizeLine(const string s)
{
   string t = s;
   StringReplace(t, "\r", " ");
   StringReplace(t, "\n", " ");
   StringReplace(t, "\t", " ");
   return t;
}

#ifndef SFX_SYNC_LITE
void NotifySendPush(const string text)
{
   if(!NotifyIsMasterSender())
      return;
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return;
   ResetLastError();
   if(!SendNotification(text))
   {
      const int err = GetLastError();
      const string ln = StringFormat("[SFX-SYNC] SendNotification failed err=%d", err);
      Print(ln);
      SyncLog(ln);
   }
}

bool NotifyQueueFileAppend(const string line)
{
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_QUEUE_FILE,
                          FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return false;
   FileSeek(h, 0, SEEK_END);
   const uint wrote = FileWriteString(h, line);
   FileClose(h);
   return (wrote > 0);
}

void NotifyQueueEnqueue(const string text)
{
   if(!NotifyIsMasterSender())
      return;
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return;
   G_NOTIFY_SEQ++;
   const string id = StringFormat("%I64u-%d-%I64d-%d",
                                 NowMs(),
                                 (int)I_PORT,
                                 (long)ChartID(),
                                 G_NOTIFY_SEQ);
   const string line = id + "\t" + NotifySanitizeLine(text) + "\n";
   if(!NotifyQueueFileAppend(line))
      G_NOTIFY_FILE_PENDING = line;
}

void NotifyQueueRetryPending()
{
   if(!NotifyIsMasterSender())
      return;
   if(StringLen(G_NOTIFY_FILE_PENDING) <= 0)
      return;
   if(NotifyQueueFileAppend(G_NOTIFY_FILE_PENDING))
      G_NOTIFY_FILE_PENDING = "";
}

void NotifySendChannels(const string text)
{
   if(!NotifyIsMasterSender())
      return;
   if(I_NOTIFY_CHANNEL == NOTIFY_OFF)
      return;
   const string msg = NotifyClip255(text);
   if(NotifyPushActive())
      NotifySendPush(msg);
   if(NotifyTelegramWanted())
      NotifyQueueEnqueue(msg);
}

string NotifyNegDiffForceText(const bool isOpen, const int streak, const double pts)
{
   return NotifyClip255(StringFormat(
      "SFX-SYNC v%s NEG_DIFF_FORCE %s %s p%d login=%I64d %s pts=%.1f th=%d streak=%d/%d %s. Close-only is ON — check and decide whether to resume.",
      SFX_SYNC_EA_VERSION,
      isOpen ? "OPEN" : "CLOSE",
      G_SYMBOL,
      (int)I_PORT,
      NotifyAccountLogin(),
      NotifyRoleName(),
      pts,
      I_NEG_DIFF_FORCE_PTS,
      streak,
      NegDiffNeedCount(),
      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)));
}

void NotifyNegDiffForceAlert(const bool isOpen, const int streak, const double pts)
{
   NotifySendChannels(NotifyNegDiffForceText(isOpen, streak, pts));
}
#endif

// Call sites remain; push/Telegram are not sent from these events.
void NotifyEvent(const string ev, const string extra)
{
   if(StringLen(ev) + StringLen(extra) < 0)
      return;
}

void NotifyEventAndFlushTg(const string ev, const string extra)
{
   NotifyEvent(ev, extra);
}

void NotifyOnTimer()
{
#ifndef SFX_SYNC_LITE
   NotifyQueueRetryPending();
#endif
   NegDiffMaybeTouchDaily();
}

void NotifyPairBrokenOnce(const string extra)
{
   if(G_NOTIFY_PAIR_BROKEN_EPISODE)
      return;
   G_NOTIFY_PAIR_BROKEN_EPISODE = true;
   if(StringLen(extra) < 0)
      return;
}

void NotifyPairBrokenReset()
{
   G_NOTIFY_PAIR_BROKEN_EPISODE = false;
}

void NotifyCloseRejectedDuringForceFlat()
{
   const string msg = "CLOSE rejected during force-flat, press again after it finishes";
   const string ln = "[SFX-SYNC] " + msg;
   Print(ln);
   SyncLog(ln);
   HudBannerSet(msg, 6);
#ifndef SFX_SYNC_LITE
   Alert(ln);
#endif
}

void NotifyOnInit()
{
   G_NOTIFY_PUSH_OK = false;
   G_NOTIFY_HUD_STICKY = "";
   G_NOTIFY_FILE_PENDING = "";
   G_NOTIFY_SEQ = 0;
   G_NOTIFY_PAIR_BROKEN_EPISODE = false;
   if(I_NOTIFY_CHANNEL == NOTIFY_OFF)
      return;
#ifndef SFX_SYNC_LITE
   if(!NotifyIsMasterSender())
      return;

   if(NotifyPushWanted())
   {
      if(TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED) == 0)
      {
         const string warn = "[SFX-SYNC] MT push selected but Notifications are OFF. Enable Tools > Options > Notifications and enter the MetaQuotes ID from the mobile app.";
         Print(warn);
         SyncLog(warn);
         Alert(warn);
         HudBannerSet("MT push: Notifications / MetaQuotes ID not configured", 20);
         NotifyHudStickyAppend("MT push: Notifications / MetaQuotes ID not configured");
      }
      else
         G_NOTIFY_PUSH_OK = true;
   }

   if(NotifyTelegramWanted())
   {
      const string warn = "[SFX-SYNC] Telegram selected: attach SFX-SYNC-NOTIFIER on another chart. Token/chat id live in the notifier (Common Files token file). Allow WebRequest https://api.telegram.org on that terminal.";
      Print(warn);
      SyncLog(warn);
      Alert(warn);
      HudBannerSet("Telegram: attach SFX-SYNC-NOTIFIER on another chart", 20);
      NotifyHudStickyAppend("Telegram: attach SFX-SYNC-NOTIFIER");
   }

   if(I_NOTIFY_TEST_ON_INIT)
   {
      NotifySendChannels(NotifyClip255(StringFormat(
         "SFX-SYNC v%s NOTIFY_TEST %s p%d login=%I64d %s init",
         SFX_SYNC_EA_VERSION,
         G_SYMBOL,
         (int)I_PORT,
         NotifyAccountLogin(),
         NotifyRoleName())));
   }
#endif
}

int NegDiffNeedCount()
{
   return MathMax(1, I_NEG_DIFF_FORCE_COUNT);
}

bool NegDiffForceLatched()
{
   return (I_NEG_DIFF_FORCE_ENABLED && (G_NEG_TRIGGER_OPEN || G_NEG_TRIGGER_CLOSE));
}

void NegDiffPushHist(const bool isOpen, const double pts)
{
   for(int i = 4; i >= 1; i--)
   {
      G_NEG_HIST_TIME[i] = G_NEG_HIST_TIME[i - 1];
      G_NEG_HIST_OPEN[i] = G_NEG_HIST_OPEN[i - 1];
      G_NEG_HIST_PTS[i] = G_NEG_HIST_PTS[i - 1];
   }
   G_NEG_HIST_TIME[0] = TimeCurrent();
   G_NEG_HIST_OPEN[0] = isOpen ? 1 : 0;
   G_NEG_HIST_PTS[0] = pts;
   if(G_NEG_HIST_COUNT < 5)
      G_NEG_HIST_COUNT++;
}

void NegDiffClearMemory()
{
   G_NEG_ARMED_OPEN = false;
   G_NEG_SNAP_OPEN = 0.0;
   G_NEG_ARMED_CLOSE = false;
   G_NEG_SNAP_CLOSE = 0.0;
   G_NEG_STREAK_OPEN = 0;
   G_NEG_STREAK_CLOSE = 0;
   G_NEG_TRIGGER_OPEN = false;
   G_NEG_TRIGGER_CLOSE = false;
   G_NEG_HIST_COUNT = 0;
   for(int i = 0; i < 5; i++)
   {
      G_NEG_HIST_TIME[i] = 0;
      G_NEG_HIST_OPEN[i] = 0;
      G_NEG_HIST_PTS[i] = 0.0;
   }
}

void NegDiffArmOpen(const bool masterBuy)
{
   if(!I_NEG_DIFF_FORCE_ENABLED || I_ROLE != ROLE_SOURCE_MASTER)
   {
      G_NEG_ARMED_OPEN = false;
      return;
   }
   G_NEG_SNAP_OPEN = 0.0;
   G_NEG_ARMED_OPEN = true;
   if(masterBuy)
      return;
}

void NegDiffArmClose(const bool masterBuy)
{
   if(!I_NEG_DIFF_FORCE_ENABLED || I_ROLE != ROLE_SOURCE_MASTER)
   {
      G_NEG_ARMED_CLOSE = false;
      return;
   }
   G_NEG_SNAP_CLOSE = 0.0;
   G_NEG_ARMED_CLOSE = true;
   if(masterBuy)
      return;
}

void NegDiffDisarmOpen()
{
   G_NEG_ARMED_OPEN = false;
   G_NEG_SNAP_OPEN = 0.0;
}

void NegDiffDisarmClose()
{
   G_NEG_ARMED_CLOSE = false;
   G_NEG_SNAP_CLOSE = 0.0;
}

void NegDiffLatchCloseOnly(const bool queueFlatten)
{
   G_CLOSE_ONLY_MANUAL_ON = true;
   if(queueFlatten && G_PAIR_ACTIVE)
   {
      G_CLOSE_SIGNAL_REASON = "NEG_DIFF_FORCE";
      G_CLOSE_SIGNAL_REQUESTED = true;
   }
}

void NegDiffApply(const bool isOpen)
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(isOpen)
   {
      if(!G_NEG_ARMED_OPEN)
         return;
   }
   else if(!G_NEG_ARMED_CLOSE)
      return;

   if(isOpen)
      NegDiffDisarmOpen();
   else
      NegDiffDisarmClose();
   if(!I_NEG_DIFF_FORCE_ENABLED)
      return;
   // Unknown fills are not a hit and do not reset the streak.
   if(!G_FA_LAST_REALIZED_OK)
      return;

   const double pts = G_FA_LAST_REALIZED_PTS;
   const bool hit = (pts <= (double)I_NEG_DIFF_FORCE_PTS);
   int streak = isOpen ? G_NEG_STREAK_OPEN : G_NEG_STREAK_CLOSE;
   if(hit)
   {
      streak++;
      NegDiffPushHist(isOpen, pts);
   }
   else
      streak = 0;
   if(isOpen)
      G_NEG_STREAK_OPEN = streak;
   else
      G_NEG_STREAK_CLOSE = streak;

   if(hit && streak >= NegDiffNeedCount())
   {
      const bool already = isOpen ? G_NEG_TRIGGER_OPEN : G_NEG_TRIGGER_CLOSE;
      if(isOpen)
         G_NEG_TRIGGER_OPEN = true;
      else
         G_NEG_TRIGGER_CLOSE = true;
      // Close-only only: never flatten the live pair from this trigger.
      NegDiffLatchCloseOnly(false);
      SyncLog(StringFormat("[SFX-SYNC] neg-diff force trigger side=%s streak=%d realized_pts=%.1f",
                           isOpen ? "OPEN" : "CLOSE", streak, pts));
      // One alert per unlatched->latched transition. A restored latch does not re-send.
#ifndef SFX_SYNC_LITE
      if(!already)
         NotifyNegDiffForceAlert(isOpen, streak, pts);
#endif
   }
   NegDiffPersistState();
}

string NegDiffSanitizeSym(const string raw)
{
   string out = raw;
   StringReplace(out, ".", "_");
   StringReplace(out, " ", "_");
   StringReplace(out, "-", "_");
   StringReplace(out, "/", "_");
   StringReplace(out, "\\", "_");
   StringReplace(out, ":", "_");
   return out;
}

string NegDiffSanitizeSymLegacy(const string raw)
{
   string out = raw;
   StringReplace(out, ".", "_");
   StringReplace(out, " ", "_");
   return out;
}

int NegDiffHash32(const string s)
{
   long h = 5381;
   const int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      h = (h * 33) + (long)StringGetCharacter(s, i);
      h = h % 1000000007;
      if(h < 0)
         h = -h;
   }
   return (int)h;
}

string NegDiffAccountId()
{
   return StringFormat("%I64d", AccountInfoInteger(ACCOUNT_LOGIN));
}

string NegDiffPortSymPart()
{
   const string acc = NegDiffAccountId();
   const string port = IntegerToString((int)I_PORT);
   const string sym = NegDiffSanitizeSym(G_SYMBOL);
   const string probe = StringFormat("SFXNEG_%s_%s_%s_CLOSEL", acc, port, sym);
   if(StringLen(probe) <= SFX_NEG_GV_MAX)
      return sym;
   return "H" + IntegerToString(NegDiffHash32(G_SYMBOL + "|" + acc + "|" + port));
}

string NegDiffGvKeyLegacy(const string side)
{
   return StringFormat("SFXNEG_%s_%s_%s", NegDiffAccountId(), NegDiffSanitizeSymLegacy(G_SYMBOL), side);
}

string NegDiffGvKey(const string side)
{
   return StringFormat("SFXNEG_%s_%s_%s_%s",
                       NegDiffAccountId(),
                       IntegerToString((int)I_PORT),
                       NegDiffPortSymPart(),
                       side);
}

string NegDiffGvKeyMig()
{
   const string acc = NegDiffAccountId();
   const string port = IntegerToString((int)I_PORT);
   const string sym = NegDiffSanitizeSym(G_SYMBOL);
   string key = StringFormat("SFXNMIG_%s_%s_%s", acc, port, sym);
   if(StringLen(key) <= SFX_NEG_GV_MAX)
      return key;
   return StringFormat("SFXNMIG_%s_%s_H%s", acc, port,
                       IntegerToString(NegDiffHash32(G_SYMBOL + "|" + acc + "|" + port)));
}

string NegDiffGvKeyClear()
{
   return StringFormat("SFXNCLR_%s_%s_%s",
                       NegDiffAccountId(),
                       IntegerToString((int)I_PORT),
                       IntegerToString(NegDiffHash32(G_SYMBOL + "|" + NegDiffAccountId() + "|" + IntegerToString((int)I_PORT))));
}

bool NegDiffHaveKeys(const bool port_keys)
{
   if(port_keys)
      return (GlobalVariableCheck(NegDiffGvKey("OPEN")) ||
              GlobalVariableCheck(NegDiffGvKey("CLOSE")) ||
              GlobalVariableCheck(NegDiffGvKey("OPENL")) ||
              GlobalVariableCheck(NegDiffGvKey("CLOSEL")));
   return (GlobalVariableCheck(NegDiffGvKeyLegacy("OPEN")) ||
           GlobalVariableCheck(NegDiffGvKeyLegacy("CLOSE")) ||
           GlobalVariableCheck(NegDiffGvKeyLegacy("OPENL")) ||
           GlobalVariableCheck(NegDiffGvKeyLegacy("CLOSEL")));
}

bool NegDiffLatchOnKey(const string key)
{
   return (GlobalVariableCheck(key) && GlobalVariableGet(key) >= 0.5);
}

void NegDiffCopyGv(const string from_key, const string to_key)
{
   if(GlobalVariableCheck(from_key))
      GlobalVariableSet(to_key, GlobalVariableGet(from_key));
}

void NegDiffMigrateLegacyIfNeeded()
{
   const string mig = NegDiffGvKeyMig();
   if(GlobalVariableCheck(mig) && GlobalVariableGet(mig) >= 0.5)
      return;
   if(NegDiffHaveKeys(true))
   {
      GlobalVariableSet(mig, 1.0);
      return;
   }
   if(!NegDiffHaveKeys(false))
      return;
   NegDiffCopyGv(NegDiffGvKeyLegacy("OPEN"), NegDiffGvKey("OPEN"));
   NegDiffCopyGv(NegDiffGvKeyLegacy("CLOSE"), NegDiffGvKey("CLOSE"));
   NegDiffCopyGv(NegDiffGvKeyLegacy("OPENL"), NegDiffGvKey("OPENL"));
   NegDiffCopyGv(NegDiffGvKeyLegacy("CLOSEL"), NegDiffGvKey("CLOSEL"));
   GlobalVariableSet(mig, 1.0);
   SyncLog(StringFormat(
      "[SFX-SYNC] neg-diff migrated legacy GV -> per-port keys login=%s port=%d symbol=%s (legacy keys kept)",
      NegDiffAccountId(), (int)I_PORT, G_SYMBOL));
}

void NegDiffClearPortKeys()
{
   GlobalVariableDel(NegDiffGvKey("OPEN"));
   GlobalVariableDel(NegDiffGvKey("CLOSE"));
   GlobalVariableDel(NegDiffGvKey("OPENL"));
   GlobalVariableDel(NegDiffGvKey("CLOSEL"));
}

void NegDiffPersistState()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   GlobalVariableSet(NegDiffGvKey("OPEN"), (double)G_NEG_STREAK_OPEN);
   GlobalVariableSet(NegDiffGvKey("CLOSE"), (double)G_NEG_STREAK_CLOSE);
   GlobalVariableSet(NegDiffGvKey("OPENL"), G_NEG_TRIGGER_OPEN ? 1.0 : 0.0);
   GlobalVariableSet(NegDiffGvKey("CLOSEL"), G_NEG_TRIGGER_CLOSE ? 1.0 : 0.0);
}

void NegDiffClearPersistedState()
{
   NegDiffClearPortKeys();
}

void NegDiffWarnDisabledLatch()
{
   const bool latch = (NegDiffLatchOnKey(NegDiffGvKey("OPENL")) ||
                       NegDiffLatchOnKey(NegDiffGvKey("CLOSEL")) ||
                       NegDiffLatchOnKey(NegDiffGvKeyLegacy("OPENL")) ||
                       NegDiffLatchOnKey(NegDiffGvKeyLegacy("CLOSEL")));
   if(!latch)
      return;
   const string ln = "[SFX-SYNC] I_NEG_DIFF_FORCE_ENABLED=false but persisted SFXNEG latch keys exist (port or legacy). Not applied. Delete via F3 Global Variables if leftover.";
   Print(ln);
   SyncLog(ln);
   const string latch_hud = "I_NEG_DIFF_FORCE_ENABLED=false but SFXNEG latch keys exist (not applied)";
   if(StringLen(G_NEG_HUD_STICKY) > 0 && StringFind(G_NEG_HUD_STICKY, latch_hud) < 0)
      G_NEG_HUD_STICKY += " | " + latch_hud;
   else if(StringLen(G_NEG_HUD_STICKY) <= 0)
      G_NEG_HUD_STICKY = latch_hud;
}

void NegDiffTouchOne(const string key)
{
   if(GlobalVariableCheck(key))
      GlobalVariableSet(key, GlobalVariableGet(key));
}

void NegDiffTouchPersistedKeys()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   NegDiffTouchOne(NegDiffGvKey("OPEN"));
   NegDiffTouchOne(NegDiffGvKey("CLOSE"));
   NegDiffTouchOne(NegDiffGvKey("OPENL"));
   NegDiffTouchOne(NegDiffGvKey("CLOSEL"));
   NegDiffTouchOne(NegDiffGvKeyMig());
   NegDiffTouchOne(NegDiffGvKeyClear());
   NegDiffTouchOne(NegDiffGvKeyLegacy("OPEN"));
   NegDiffTouchOne(NegDiffGvKeyLegacy("CLOSE"));
   NegDiffTouchOne(NegDiffGvKeyLegacy("OPENL"));
   NegDiffTouchOne(NegDiffGvKeyLegacy("CLOSEL"));
}

void NegDiffMaybeTouchDaily()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int day = dt.year * 400 + dt.day_of_year;
   if(G_NEG_GV_TOUCH_DAY == day)
      return;
   G_NEG_GV_TOUCH_DAY = day;
   NegDiffTouchPersistedKeys();
}

void NegDiffRestoreState()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(!I_NEG_DIFF_FORCE_CLEAR_STATE)
   {
      GlobalVariableDel(NegDiffGvKeyClear());
      G_NEG_HUD_STICKY = "";
   }
   else
   {
      const string clr = NegDiffGvKeyClear();
      G_NEG_HUD_STICKY = "Set I_NEG_DIFF_FORCE_CLEAR_STATE back to false";
      if(!(GlobalVariableCheck(clr) && GlobalVariableGet(clr) > 0.0))
      {
         NegDiffClearMemory();
         NegDiffClearPortKeys();
         GlobalVariableSet(NegDiffGvKeyMig(), 1.0);
         GlobalVariableSet(clr, (double)TimeCurrent());
         const string ln = "[SFX-SYNC] neg-diff this-port keys cleared (I_NEG_DIFF_FORCE_CLEAR_STATE one-shot). Set the input back to false. Legacy SFXNEG keys were left in place.";
         Print(ln);
         SyncLog(ln);
         Alert("[SFX-SYNC] CLEAR_STATE done for this port. Set I_NEG_DIFF_FORCE_CLEAR_STATE back to false.");
         NegDiffTouchPersistedKeys();
         return;
      }
   }
   if(!I_NEG_DIFF_FORCE_ENABLED)
   {
      NegDiffWarnDisabledLatch();
      NegDiffTouchPersistedKeys();
      return;
   }

   NegDiffMigrateLegacyIfNeeded();

   const string kOpen = NegDiffGvKey("OPEN");
   const string kClose = NegDiffGvKey("CLOSE");
   const string kOpenL = NegDiffGvKey("OPENL");
   const string kCloseL = NegDiffGvKey("CLOSEL");
   const bool have = (GlobalVariableCheck(kOpen) || GlobalVariableCheck(kClose) ||
                      GlobalVariableCheck(kOpenL) || GlobalVariableCheck(kCloseL));
   if(!have)
   {
      NegDiffTouchPersistedKeys();
      return;
   }

   if(GlobalVariableCheck(kOpen))
      G_NEG_STREAK_OPEN = (int)MathMax(0, GlobalVariableGet(kOpen));
   if(GlobalVariableCheck(kClose))
      G_NEG_STREAK_CLOSE = (int)MathMax(0, GlobalVariableGet(kClose));
   if(GlobalVariableCheck(kOpenL))
      G_NEG_TRIGGER_OPEN = (GlobalVariableGet(kOpenL) >= 0.5);
   if(GlobalVariableCheck(kCloseL))
      G_NEG_TRIGGER_CLOSE = (GlobalVariableGet(kCloseL) >= 0.5);
   if(G_NEG_TRIGGER_OPEN || G_NEG_TRIGGER_CLOSE)
      G_CLOSE_ONLY_MANUAL_ON = true;
   SyncLog(StringFormat("[SFX-SYNC] neg-diff restored open=%d/%s close=%d/%s latch=%s port=%d",
                        G_NEG_STREAK_OPEN, G_NEG_TRIGGER_OPEN ? "TRIGGER" : "ok",
                        G_NEG_STREAK_CLOSE, G_NEG_TRIGGER_CLOSE ? "TRIGGER" : "ok",
                        (G_NEG_TRIGGER_OPEN || G_NEG_TRIGGER_CLOSE) ? "ON" : "off",
                        (int)I_PORT));
   NegDiffTouchPersistedKeys();
}

void NegDiffOnManualCloseOnlyOff()
{
   NegDiffClearMemory();
   NegDiffPersistState();
   GlobalVariableSet(NegDiffGvKeyMig(), 1.0);
   NegDiffTouchPersistedKeys();
   SyncLog("[SFX-SYNC] neg-diff force counters cleared (close-only turned off)");
}

string NegDiffHudBlock()
{
   if(!I_NEG_DIFF_FORCE_ENABLED || I_ROLE != ROLE_SOURCE_MASTER)
      return "";
   const int need = NegDiffNeedCount();
   const int leftOpen = MathMax(0, need - G_NEG_STREAK_OPEN);
   const int leftClose = MathMax(0, need - G_NEG_STREAK_CLOSE);
   string out = "\n";
   out += "NEG DIFF FORCE: on (realized fills)\n";
   out += StringFormat("OPEN streak %d/%d left %d\n", G_NEG_STREAK_OPEN, need, leftOpen);
   out += StringFormat("CLOSE streak %d/%d left %d\n", G_NEG_STREAK_CLOSE, need, leftClose);
   if(G_NEG_TRIGGER_OPEN)
      out += "TRIGGER OPEN\n";
   if(G_NEG_TRIGGER_CLOSE)
      out += "TRIGGER CLOSE\n";
   for(int i = 0; i < G_NEG_HIST_COUNT; i++)
   {
      out += StringFormat("NEG %s %.1f %s\n",
                          G_NEG_HIST_OPEN[i] != 0 ? "OPEN" : "CLOSE",
                          G_NEG_HIST_PTS[i],
                          TimeToString(G_NEG_HIST_TIME[i], TIME_DATE | TIME_MINUTES | TIME_SECONDS));
   }
   return out;
}

string DiffHudMasterCommentTail()
{
   string out = "";
   if(!DiffQuotesFresh())
      out += "DIFF HUD: quotes stale\n";
   const int sSelf = DiffSpreadPts(G_DIFF_SELF_BID, G_DIFF_SELF_ASK);
   const int sPeer = DiffSpreadPts(G_DIFF_SLAVE_BID, G_DIFF_SLAVE_ASK);
   const bool om = sSelf > I_DIFF_MAX_SPREAD_SELF;
   const bool op = sPeer > I_DIFF_MAX_SPREAD_PEER;
   if(om || op)
   {
      if(StringLen(out) > 0)
         out += "\n";
      if(om && op)
         out += StringFormat("DIFF HUD: spread over limit (master %d > max %d, slave %d > max %d)\n",
                             sSelf, I_DIFF_MAX_SPREAD_SELF, sPeer, I_DIFF_MAX_SPREAD_PEER);
      else if(om)
         out += StringFormat("DIFF HUD: spread over limit (master %d > max %d)\n", sSelf, I_DIFF_MAX_SPREAD_SELF);
      else
         out += StringFormat("DIFF HUD: spread over limit (slave %d > max %d)\n", sPeer, I_DIFF_MAX_SPREAD_PEER);
   }
   ulong remO = 0;
   if(DiffHudOpenCooldownRemainMs(remO))
   {
      if(StringLen(out) > 0)
         out += "\n";
      const ulong perO = (ulong)I_DIFF_OPEN_COOLDOWN_SEC * 1000UL;
      out += StringFormat("DIFF HUD: auto-open cooldown %s (period %u s, after last DIFF_OPEN)\n",
                          DiffHudFormatRemainMs(remO), (uint)(perO / 1000));
   }
   ulong remA = 0;
   if(DiffHudAvgOpenCooldownRemainMs(remA))
   {
      if(StringLen(out) > 0)
         out += "\n";
      out += StringFormat("DIFF HUD: AVG open cooldown %s (period %d ms)\n", DiffHudFormatRemainMs(remA),
                          I_DIFF_AVG_SIGNAL_COOLDOWN_MS);
   }
   ulong remC = 0;
   if(DiffHudCloseCooldownRemainMs(remC))
   {
      if(StringLen(out) > 0)
         out += "\n";
      const ulong perC = (ulong)I_DIFF_CLOSE_COOLDOWN_SEC * 1000UL;
      out += StringFormat("DIFF HUD: auto-close cooldown %s (period %u s, after last DIFF_CLOSE)\n",
                          DiffHudFormatRemainMs(remC), (uint)(perC / 1000));
   }
   ulong remAc = 0;
   if(DiffHudAvgCloseCooldownRemainMs(remAc))
   {
      if(StringLen(out) > 0)
         out += "\n";
      out += StringFormat("DIFF HUD: AVG close cooldown %s (period %d ms)\n", DiffHudFormatRemainMs(remAc),
                          I_DIFF_AVG_SIGNAL_COOLDOWN_MS);
   }
   out += DiffHudQuoteMonitorBlock();
   out += DpmHudBlock();
   out += NegDiffHudBlock();
   return out;
}

bool DiffHudSpreadGateOk()
{
   if(!G_DIFF_SLAVE_QUOTE_OK)
      return false;
   if(!DiffQuotesFresh())
      return false;
   if(DiffSpreadPts(G_DIFF_SELF_BID, G_DIFF_SELF_ASK) > I_DIFF_MAX_SPREAD_SELF)
      return false;
   if(DiffSpreadPts(G_DIFF_SLAVE_BID, G_DIFF_SLAVE_ASK) > I_DIFF_MAX_SPREAD_PEER)
      return false;
   return true;
}

string DiffHudFormatProgressBar(const double pctRaw)
{
   double pct = pctRaw;
   if(pct < 0.0)
      pct = 0.0;
   if(pct > 100.0)
      pct = 100.0;
   const int W = 12;
   int filled = (int)MathRound(pct / 100.0 * (double)W);
   if(filled < 0)
      filled = 0;
   if(filled > W)
      filled = W;
   string bar = "[";
   for(int i = 0; i < W; i++)
      bar += (i < filled ? "#" : ".");
   bar += "]";
   return StringFormat("%s %d%%", bar, (int)MathRound(pct));
}

void DiffArmCooldownsAfterOpenPairCommit()
{
   const ulong nw = NowMs();
   if(I_DIFF_OPEN_COOLDOWN_SEC > 0)
      G_DIFF_LAST_OPEN_SIGNAL_MS = nw;
   else
      G_DIFF_LAST_OPEN_SIGNAL_MS = 0;
   if(I_DIFF_CLOSE_COOLDOWN_SEC > 0)
      G_DIFF_LAST_CLOSE_SIGNAL_MS = nw;
   else
      G_DIFF_LAST_CLOSE_SIGNAL_MS = 0;
   if(I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_AVG && I_DIFF_AVG_SIGNAL_COOLDOWN_MS > 0)
   {
      G_DIFF_LAST_AVG_OPEN_SIG_MS = nw;
      G_DIFF_LAST_AVG_CLOSE_SIG_MS = nw;
   }
   else
   {
      G_DIFF_LAST_AVG_OPEN_SIG_MS = 0;
      G_DIFF_LAST_AVG_CLOSE_SIG_MS = 0;
   }
}

string DiffHudSignalOpenProgressBlock()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return "";
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG && I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_RAW_STABILITY
      && I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_TIME_GATE)
      return "";
   if(G_PAIR_ACTIVE)
      return "";

   const bool modeAvg = (I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_AVG);
   const bool modeTg  = (I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_TIME_GATE);
   string lines = "\nOPEN signal (";
   lines += modeAvg ? "AVG" : (modeTg ? "TIME GATE" : "RAW stability");
   lines += ")\n\n";

   if(!I_DIFF_SYNC_ENABLED)
      lines += " (diff autosync off — reference only)\n\n";

   if(G_PEER == NULL || !G_PEER.IsSocketConnected() || !G_HANDSHAKE_OK)
   {
      lines += " waiting TCP / handshake\n";
      return lines;
   }

   if(DiffIsMasterAuto() && !G_DIFF_AUTO_SIDE_LOCKED)
   {
      const int th0 = I_DIFF_OPEN_THRESHOLD_PTS;
      const double dB = DiffOpenPtsFor(true);
      const double dS = DiffOpenPtsFor(false);
      lines += StringFormat(" SIDE_AUTO: side lock needs raw >= %d (BUY %.1f / SELL %.1f)\n\n", th0, dB, dS);
   }

   ulong remOCd = 0;
   if(DiffHudOpenCooldownRemainMs(remOCd))
   {
      const ulong perO = (ulong)I_DIFF_OPEN_COOLDOWN_SEC * 1000UL;
      const ulong nwC = NowMs();
      double pctE = 0.0;
      if(perO > 0)
         pctE = 100.0 * (double)(nwC - G_DIFF_LAST_OPEN_SIGNAL_MS) / (double)perO;
      if(pctE > 100.0)
         pctE = 100.0;
      lines += StringFormat(" open cooldown: %s of %u s  ", DiffHudFormatRemainMs(remOCd), (uint)(perO / 1000));
      lines += DiffHudFormatProgressBar(pctE);
      lines += " elapsed\n\n";
   }
   ulong remACd = 0;
   if(DiffHudAvgOpenCooldownRemainMs(remACd))
   {
      const ulong perA = (ulong)I_DIFF_AVG_SIGNAL_COOLDOWN_MS;
      const ulong nwA = NowMs();
      double pctA = 0.0;
      if(perA > 0)
         pctA = 100.0 * (double)(nwA - G_DIFF_LAST_AVG_OPEN_SIG_MS) / (double)perA;
      if(pctA > 100.0)
         pctA = 100.0;
      lines += StringFormat(" AVG signal cooldown: %s of %d ms  ", DiffHudFormatRemainMs(remACd),
                            I_DIFF_AVG_SIGNAL_COOLDOWN_MS);
      lines += DiffHudFormatProgressBar(pctA);
      lines += " elapsed\n\n";
   }

   if(!DiffHudSpreadGateOk())
   {
      lines += " gated — fix quotes / spread (see DIFF HUD)\n";
      return lines;
   }

   const double diffOpen = DiffOpenPtsFor(DiffMasterBuyEffective());
   const int th = I_DIFF_OPEN_THRESHOLD_PTS;

   if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_OPEN_ZONE_OK)
      lines += StringFormat(" zone filter: not OK (open diff %.1f)\n\n", DiffOpenPts());

   if(modeAvg)
   {
      const double thrEff = (double)(th + I_DIFF_HYSTERESIS_PTS);
      double avgDisp = G_DIFF_HUD_LAST_AVG_OPEN;
      if(!G_DIFF_EMA_OPEN_INIT)
         avgDisp = diffOpen;
      double pctArm = (thrEff > 0.0) ? (100.0 * avgDisp / thrEff) : 0.0;
      if(pctArm > 100.0)
         pctArm = 100.0;
      lines += StringFormat(" raw %.1f | avg %.1f / need %.1f\n\n", diffOpen, avgDisp, thrEff);
      lines += " toward avg arm: ";
      lines += DiffHudFormatProgressBar(pctArm);
      lines += "\n\n";

      if(G_DIFF_OPEN_PENDING)
      {
         const int needT = MathMax(1, I_DIFF_CONFIRM_TICKS);
         double pctC = 100.0 * (double)G_DIFF_OPEN_OK_COUNT / (double)needT;
         if(pctC > 100.0)
            pctC = 100.0;
         lines += StringFormat(" confirm ticks %d/%d: ", G_DIFF_OPEN_OK_COUNT, needT);
         lines += DiffHudFormatProgressBar(pctC);
         lines += "\n\n";
         if(I_DIFF_REAL_CONFIRM)
         {
            const double needRaw = MathMax(G_DIFF_OPEN_SNAP_AVG, thrEff) + (double)I_DIFF_EPSILON_PTS;
            lines += StringFormat(" real-confirm needs raw >= %.1f — now %.1f (%s)\n", needRaw, diffOpen,
                                  (diffOpen >= needRaw ? "ok" : "hold"));
         }
      }
   }
   else if(modeTg)
   {
      const double reset = (double)th - (double)I_DIFF_TIME_GATE_HYSTERESIS_OFFSET;
      double pctIn = (th > 0) ? (100.0 * diffOpen / (double)th) : 0.0;
      if(pctIn > 100.0) pctIn = 100.0;
      lines += StringFormat(" raw %.1f / gate %.1f (below %.1f resets)\n\n", diffOpen, (double)th, reset);
      lines += " toward threshold: ";
      lines += DiffHudFormatProgressBar(pctIn);
      lines += "\n\n";
      if(G_DIFF_TG_OPEN_PEND)
      {
         const ulong nwTg = NowMs();
         const ulong el   = (nwTg > G_DIFF_TG_OPEN_START_MS) ? (nwTg - G_DIFF_TG_OPEN_START_MS) : 0;
         const int   gate = MathMax(1, I_DIFF_TIME_GATE_OPEN_MS);
         double pctT = 100.0 * (double)el / (double)gate;
         if(pctT > 100.0) pctT = 100.0;
         lines += StringFormat(" held %u / %d ms: ", (uint)el, gate);
         lines += DiffHudFormatProgressBar(pctT);
         lines += "\n";
      }
   }
   else
   {
      const double enter = (double)th;
      const double reset = enter - (double)I_DIFF_RAW_HYSTERESIS_OFFSET;
      double pctStage = (enter > 0.0) ? (100.0 * diffOpen / enter) : 0.0;
      if(pctStage > 100.0)
         pctStage = 100.0;
      lines += StringFormat(" raw %.1f / enter %.1f (below %.1f drops streak)\n\n", diffOpen, enter, reset);
      lines += " toward enter: ";
      lines += DiffHudFormatProgressBar(pctStage);
      lines += "\n\n";
      if(G_DIFF_RAW_OPEN_PEND && I_DIFF_RAW_STABILITY_TIMEOUT_MS > 0)
      {
         const ulong nw = NowMs();
         const ulong el = (nw > G_DIFF_RAW_OPEN_START) ? (nw - G_DIFF_RAW_OPEN_START) : 0;
         lines += StringFormat(" streak age: %u / %d ms\n\n", (uint)el, I_DIFF_RAW_STABILITY_TIMEOUT_MS);
      }
      if(G_DIFF_RAW_OPEN_PEND)
      {
         const int needR = MathMax(1, I_DIFF_RAW_STABILITY_TICKS);
         double pctR = 100.0 * (double)G_DIFF_RAW_OPEN_CNT / (double)needR;
         if(pctR > 100.0)
            pctR = 100.0;
         lines += StringFormat(" stability ticks %d/%d: ", G_DIFF_RAW_OPEN_CNT, needR);
         lines += DiffHudFormatProgressBar(pctR);
         lines += "\n";
      }
   }
   return lines;
}

string DiffHudSignalCloseProgressBlock()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return "";
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG && I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_RAW_STABILITY
      && I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_TIME_GATE)
      return "";
   if(!G_PAIR_ACTIVE)
      return "";

   const bool modeAvg = (I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_AVG);
   const bool modeTg  = (I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_TIME_GATE);
   string lines = "\nCLOSE signal (";
   lines += modeAvg ? "AVG" : (modeTg ? "TIME GATE" : "RAW stability");
   lines += ")\n\n";

   if(!I_DIFF_SYNC_ENABLED)
      lines += " (diff autosync off — reference only)\n\n";

   ulong remCCd = 0;
   if(DiffHudCloseCooldownRemainMs(remCCd))
   {
      const ulong perC = (ulong)I_DIFF_CLOSE_COOLDOWN_SEC * 1000UL;
      const ulong nwCc = NowMs();
      double pctEc = 0.0;
      if(perC > 0)
         pctEc = 100.0 * (double)(nwCc - G_DIFF_LAST_CLOSE_SIGNAL_MS) / (double)perC;
      if(pctEc > 100.0)
         pctEc = 100.0;
      lines += StringFormat(" close cooldown: %s of %u s  ", DiffHudFormatRemainMs(remCCd),
                            (uint)(perC / 1000));
      lines += DiffHudFormatProgressBar(pctEc);
      lines += " elapsed\n\n";
   }
   ulong remAvgCCd = 0;
   if(DiffHudAvgCloseCooldownRemainMs(remAvgCCd))
   {
      const ulong perAc = (ulong)I_DIFF_AVG_SIGNAL_COOLDOWN_MS;
      const ulong nwAvgC = NowMs();
      double pctAvgC = 0.0;
      if(perAc > 0)
         pctAvgC = 100.0 * (double)(nwAvgC - G_DIFF_LAST_AVG_CLOSE_SIG_MS) / (double)perAc;
      if(pctAvgC > 100.0)
         pctAvgC = 100.0;
      lines += StringFormat(" AVG close cooldown: %s of %d ms  ", DiffHudFormatRemainMs(remAvgCCd),
                            I_DIFF_AVG_SIGNAL_COOLDOWN_MS);
      lines += DiffHudFormatProgressBar(pctAvgC);
      lines += " elapsed\n\n";
   }

   if(G_PEER == NULL || !G_PEER.IsSocketConnected() || !G_HANDSHAKE_OK)
   {
      lines += " waiting TCP / handshake\n";
      return lines;
   }

   if(!DiffHudSpreadGateOk())
   {
      lines += " gated — fix quotes / spread (see DIFF HUD)\n";
      return lines;
   }

   const double diffClose = DiffClosePtsFor(DiffMasterBuyEffective());
   const int thC = I_DIFF_CLOSE_THRESHOLD_PTS;

   if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_CLOSE_ZONE_OK)
      lines += StringFormat(" zone filter: not OK (close diff %.1f)\n\n", DiffClosePts());

   if(modeAvg)
   {
      const double thrEff = (double)(thC + I_DIFF_HYSTERESIS_PTS);
      double avgDisp = G_DIFF_HUD_LAST_AVG_CLOSE;
      if(!G_DIFF_EMA_CLOSE_INIT)
         avgDisp = diffClose;
      double pctArm = (thrEff > 0.0) ? (100.0 * avgDisp / thrEff) : 0.0;
      if(pctArm > 100.0)
         pctArm = 100.0;
      lines += StringFormat(" raw %.1f | avg %.1f / need %.1f\n\n", diffClose, avgDisp, thrEff);
      lines += " toward avg arm (close): ";
      lines += DiffHudFormatProgressBar(pctArm);
      lines += "\n\n";

      if(G_DIFF_CLOSE_PENDING)
      {
         const int needT = MathMax(1, I_DIFF_CONFIRM_TICKS);
         double pctC = 100.0 * (double)G_DIFF_CLOSE_OK_COUNT / (double)needT;
         if(pctC > 100.0)
            pctC = 100.0;
         lines += StringFormat(" confirm ticks %d/%d: ", G_DIFF_CLOSE_OK_COUNT, needT);
         lines += DiffHudFormatProgressBar(pctC);
         lines += "\n\n";
         if(I_DIFF_REAL_CONFIRM)
         {
            const double needRaw = MathMax(G_DIFF_CLOSE_SNAP_AVG, thrEff) + (double)I_DIFF_EPSILON_PTS;
            lines += StringFormat(" real-confirm needs raw >= %.1f — now %.1f (%s)\n", needRaw, diffClose,
                                  (diffClose >= needRaw ? "ok" : "hold"));
         }
      }
   }
   else if(modeTg)
   {
      const double resetC = (double)thC - (double)I_DIFF_TIME_GATE_HYSTERESIS_OFFSET;
      double pctIn = (thC > 0) ? (100.0 * diffClose / (double)thC) : 0.0;
      if(pctIn > 100.0) pctIn = 100.0;
      lines += StringFormat(" raw %.1f / gate %.1f (below %.1f resets)\n\n", diffClose, (double)thC, resetC);
      lines += " toward threshold: ";
      lines += DiffHudFormatProgressBar(pctIn);
      lines += "\n\n";
      if(G_DIFF_TG_CLOSE_PEND)
      {
         const ulong nwTgC = NowMs();
         const ulong elC   = (nwTgC > G_DIFF_TG_CLOSE_START_MS) ? (nwTgC - G_DIFF_TG_CLOSE_START_MS) : 0;
         const int   gateC = MathMax(1, I_DIFF_TIME_GATE_CLOSE_MS);
         double pctTc = 100.0 * (double)elC / (double)gateC;
         if(pctTc > 100.0) pctTc = 100.0;
         lines += StringFormat(" held %u / %d ms: ", (uint)elC, gateC);
         lines += DiffHudFormatProgressBar(pctTc);
         lines += "\n";
      }
   }
   else
   {
      const double enter = (double)thC;
      const double reset = enter - (double)I_DIFF_RAW_HYSTERESIS_OFFSET;
      double pctStage = (enter > 0.0) ? (100.0 * diffClose / enter) : 0.0;
      if(pctStage > 100.0)
         pctStage = 100.0;
      lines += StringFormat(" raw %.1f / enter %.1f (below %.1f drops streak)\n\n", diffClose, enter, reset);
      lines += " toward enter (close): ";
      lines += DiffHudFormatProgressBar(pctStage);
      lines += "\n\n";
      if(G_DIFF_RAW_CLOSE_PEND && I_DIFF_RAW_STABILITY_TIMEOUT_MS > 0)
      {
         const ulong nw = NowMs();
         const ulong el = (nw > G_DIFF_RAW_CLOSE_START) ? (nw - G_DIFF_RAW_CLOSE_START) : 0;
         lines += StringFormat(" streak age: %u / %d ms\n\n", (uint)el, I_DIFF_RAW_STABILITY_TIMEOUT_MS);
      }
      if(G_DIFF_RAW_CLOSE_PEND)
      {
         const int needR = MathMax(1, I_DIFF_RAW_STABILITY_TICKS);
         double pctR = 100.0 * (double)G_DIFF_RAW_CLOSE_CNT / (double)needR;
         if(pctR > 100.0)
            pctR = 100.0;
         lines += StringFormat(" stability ticks %d/%d: ", G_DIFF_RAW_CLOSE_CNT, needR);
         lines += DiffHudFormatProgressBar(pctR);
         lines += "\n";
      }
   }
   return lines;
}

void DiffResetOpenZoneCounters()
{
   G_DIFF_OPEN_ZONE_OK = false;
   G_DIFF_OPEN_ZP = 0;
   G_DIFF_OPEN_ZN = 0;
}

void DiffResetCloseZoneCounters()
{
   G_DIFF_CLOSE_ZONE_OK = false;
   G_DIFF_CLOSE_ZP = 0;
   G_DIFF_CLOSE_ZN = 0;
}

void DiffZoneScan(const double cur, const int threshold, bool &stable_out, int &pc, int &nc)
{
   const double pos_th = (double)threshold * 0.5;
   if(cur >= pos_th)
   {
      pc++;
      nc = 0;
   }
   else if(cur <= (double)I_DIFF_ZONE_NEGATIVE_THRESHOLD)
   {
      nc++;
      pc = 0;
   }
   stable_out = (pc >= I_DIFF_ZONE_STABILITY_TICKS && nc == 0);
}

void DiffPushMedOpen(const double v)
{
   int maxN = I_DIFF_PREFILTER_WINDOW;
   if(maxN > 16)
      maxN = 16;
   if(maxN < 3)
      maxN = 3;
   if((maxN % 2) == 0)
      maxN++;
   if(G_DIFF_MED_OPEN_COUNT < maxN)
      G_DIFF_MED_OPEN_COUNT++;
   G_DIFF_MED_OPEN[G_DIFF_MED_OPEN_IDX] = v;
   G_DIFF_MED_OPEN_IDX++;
   if(G_DIFF_MED_OPEN_IDX >= maxN)
      G_DIFF_MED_OPEN_IDX = 0;
}

double DiffGetMedOpen()
{
   int maxN = I_DIFF_PREFILTER_WINDOW;
   if(maxN > 16)
      maxN = 16;
   if(maxN < 1)
      maxN = 1;
   int useN = (G_DIFF_MED_OPEN_COUNT < maxN) ? G_DIFF_MED_OPEN_COUNT : maxN;
   if(useN <= 0)
      return 0.0;
   double tmp[16];
   ArrayInitialize(tmp, 0.0);
   int pos = G_DIFF_MED_OPEN_IDX;
   for(int i = 0; i < useN; i++)
   {
      int j = pos - 1 - i;
      if(j < 0)
         j += maxN;
      tmp[i] = G_DIFF_MED_OPEN[j];
   }
   for(int a = 1; a < useN; a++)
   {
      double key = tmp[a];
      int b = a - 1;
      while(b >= 0 && tmp[b] > key)
      {
         tmp[b + 1] = tmp[b];
         b--;
      }
      tmp[b + 1] = key;
   }
   const int mid = useN / 2;
   if((useN % 2) == 1)
      return tmp[mid];
   return 0.5 * (tmp[mid - 1] + tmp[mid]);
}

void DiffPushMedClose(const double v)
{
   int maxN = I_DIFF_PREFILTER_WINDOW;
   if(maxN > 16)
      maxN = 16;
   if(maxN < 3)
      maxN = 3;
   if((maxN % 2) == 0)
      maxN++;
   if(G_DIFF_MED_CLOSE_COUNT < maxN)
      G_DIFF_MED_CLOSE_COUNT++;
   G_DIFF_MED_CLOSE[G_DIFF_MED_CLOSE_IDX] = v;
   G_DIFF_MED_CLOSE_IDX++;
   if(G_DIFF_MED_CLOSE_IDX >= maxN)
      G_DIFF_MED_CLOSE_IDX = 0;
}

double DiffGetMedClose()
{
   int maxN = I_DIFF_PREFILTER_WINDOW;
   if(maxN > 16)
      maxN = 16;
   if(maxN < 1)
      maxN = 1;
   int useN = (G_DIFF_MED_CLOSE_COUNT < maxN) ? G_DIFF_MED_CLOSE_COUNT : maxN;
   if(useN <= 0)
      return 0.0;
   double tmp[16];
   ArrayInitialize(tmp, 0.0);
   int pos = G_DIFF_MED_CLOSE_IDX;
   for(int i = 0; i < useN; i++)
   {
      int j = pos - 1 - i;
      if(j < 0)
         j += maxN;
      tmp[i] = G_DIFF_MED_CLOSE[j];
   }
   for(int a = 1; a < useN; a++)
   {
      double key = tmp[a];
      int b = a - 1;
      while(b >= 0 && tmp[b] > key)
      {
         tmp[b + 1] = tmp[b];
         b--;
      }
      tmp[b + 1] = key;
   }
   const int mid = useN / 2;
   if((useN % 2) == 1)
      return tmp[mid];
   return 0.5 * (tmp[mid - 1] + tmp[mid]);
}

double DiffSmoothOpen(const double realDiff)
{
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG)
      return realDiff;
   double filtered = realDiff;
   const int w = I_DIFF_PREFILTER_WINDOW;
   if(I_DIFF_USE_PREFILTER_MEDIAN && w >= 3 && (w % 2) == 1)
   {
      DiffPushMedOpen(realDiff);
      filtered = DiffGetMedOpen();
   }
   else
   {
      DiffPushMedOpen(realDiff);
      filtered = realDiff;
   }
   const double alpha = 2.0 / ((double)I_DIFF_AVG_PERIOD + 1.0);
   if(!G_DIFF_EMA_OPEN_INIT)
   {
      G_DIFF_EMA_OPEN = filtered;
      G_DIFF_EMA_OPEN_INIT = true;
   }
   else
      G_DIFF_EMA_OPEN = G_DIFF_EMA_OPEN + alpha * (filtered - G_DIFF_EMA_OPEN);
   return G_DIFF_EMA_OPEN;
}

double DiffSmoothClose(const double realDiff)
{
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG)
      return realDiff;
   double filtered = realDiff;
   const int w = I_DIFF_PREFILTER_WINDOW;
   if(I_DIFF_USE_PREFILTER_MEDIAN && w >= 3 && (w % 2) == 1)
   {
      DiffPushMedClose(realDiff);
      filtered = DiffGetMedClose();
   }
   else
   {
      DiffPushMedClose(realDiff);
      filtered = realDiff;
   }
   const double alpha = 2.0 / ((double)I_DIFF_AVG_PERIOD + 1.0);
   if(!G_DIFF_EMA_CLOSE_INIT)
   {
      G_DIFF_EMA_CLOSE = filtered;
      G_DIFF_EMA_CLOSE_INIT = true;
   }
   else
      G_DIFF_EMA_CLOSE = G_DIFF_EMA_CLOSE + alpha * (filtered - G_DIFF_EMA_CLOSE);
   return G_DIFF_EMA_CLOSE;
}

void DiffResetOpenSmoothing()
{
   G_DIFF_EMA_OPEN = 0.0;
   G_DIFF_EMA_OPEN_INIT = false;
   G_DIFF_MED_OPEN_COUNT = 0;
   G_DIFF_MED_OPEN_IDX = 0;
   ArrayInitialize(G_DIFF_MED_OPEN, 0.0);
   G_DIFF_OPEN_PENDING = false;
   G_DIFF_OPEN_OK_COUNT = 0;
   G_DIFF_RAW_OPEN_PEND = false;
   G_DIFF_RAW_OPEN_CNT = 0;
}

void DiffResetCloseSmoothing()
{
   G_DIFF_EMA_CLOSE = 0.0;
   G_DIFF_EMA_CLOSE_INIT = false;
   G_DIFF_MED_CLOSE_COUNT = 0;
   G_DIFF_MED_CLOSE_IDX = 0;
   ArrayInitialize(G_DIFF_MED_CLOSE, 0.0);
   G_DIFF_CLOSE_PENDING = false;
   G_DIFF_CLOSE_OK_COUNT = 0;
   G_DIFF_RAW_CLOSE_PEND = false;
   G_DIFF_RAW_CLOSE_CNT = 0;
}

void DiffResetAllSmooth()
{
   DiffResetOpenSmoothing();
   DiffResetCloseSmoothing();
   DiffResetOpenZoneCounters();
   DiffResetCloseZoneCounters();
}

void DiffAutoUnlockSearching()
{
   if(!DiffIsMasterAuto())
      return;
   G_DIFF_AUTO_SIDE_LOCKED = false;
   G_DIFF_AUTO_EVER_OPENED = false;
   DiffResetAllSmooth();
}

bool DiffAutoTryResolveLock(const int open_th)
{
   if(!DiffIsMasterAuto())
      return true;
   if(G_DIFF_AUTO_SIDE_LOCKED)
      return true;

   const double dB = DiffOpenPtsFor(true);
   const double dS = DiffOpenPtsFor(false);
   const bool bR = dB >= (double)open_th;
   const bool sR = dS >= (double)open_th;
   if(!bR && !sR)
      return false;

   if(bR && sR)
      G_DIFF_AUTO_EFF_SIDE = (dB >= dS) ? SIDE_BUY : SIDE_SELL;
   else if(bR)
      G_DIFF_AUTO_EFF_SIDE = SIDE_BUY;
   else
      G_DIFF_AUTO_EFF_SIDE = SIDE_SELL;

   G_DIFF_AUTO_SIDE_LOCKED = true;
   G_DIFF_AUTO_EVER_OPENED = false;
   DiffResetOpenSmoothing();
   return true;
}

void DiffAutoLockManualBest()
{
   if(!DiffIsMasterAuto() || G_DIFF_AUTO_SIDE_LOCKED)
      return;
   const double dB = DiffOpenPtsFor(true);
   const double dS = DiffOpenPtsFor(false);
   G_DIFF_AUTO_EFF_SIDE = (dB >= dS) ? SIDE_BUY : SIDE_SELL;
   G_DIFF_AUTO_SIDE_LOCKED = true;
   G_DIFF_AUTO_EVER_OPENED = false;
   DiffResetOpenSmoothing();
}

void DiffRefreshHudMetricsOnly()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   DiffRefreshMasterQuotes();
   G_DIFF_MASTER_MAGIC_PL = SumMagicSymbolPnl();
}

// ──────────────────────────────────────────────────────────────
// Drift Persistence Monitor (DPM)
// ──────────────────────────────────────────────────────────────

string DpmCsvFileName()
{
   return StringFormat("DPM_%I64d_%s.csv", AccountInfoInteger(ACCOUNT_LOGIN), G_SYMBOL);
}

string DpmResolveMasterSide()
{
   if(I_MASTER_SIDE == SIDE_BUY)
      return "BUY";
   if(I_MASTER_SIDE == SIDE_SELL)
      return "SELL";
   if(G_DIFF_AUTO_SIDE_LOCKED)
      return (G_DIFF_AUTO_EFF_SIDE == SIDE_BUY) ? "BUY" : "SELL";
   return "";
}

void DpmRecordEvent(const bool isOpen, const int lvl, const int thPts,
                    const double snap, const double peak, const ulong durMs,
                    const int fired, const string side)
{
   DpmEvent ev;
   ev.isOpen       = isOpen;
   ev.level        = lvl + 1;
   ev.thresholdPts = thPts;
   ev.snapPts      = snap;
   ev.peakPts      = peak;
   ev.durationMs   = durMs;
   ev.fired        = fired;
   ev.signalMode   = (int)I_DIFF_SIGNAL_MODE_VAL;
   ev.masterSpread = DiffSpreadPts(G_DIFF_SELF_BID, G_DIFF_SELF_ASK);
   ev.slaveSpread  = DiffSpreadPts(G_DIFF_SLAVE_BID, G_DIFF_SLAVE_ASK);
   ev.avgSnap      = isOpen ? G_DIFF_HUD_LAST_AVG_OPEN : G_DIFF_HUD_LAST_AVG_CLOSE;
   ev.masterSide   = side;
   ev.eventTime    = TimeCurrent();

   G_DPM_RING[G_DPM_RING_HEAD] = ev;
   G_DPM_RING_HEAD = (G_DPM_RING_HEAD + 1) % 50;
   if(G_DPM_RING_COUNT < 50)
      G_DPM_RING_COUNT++;

   if(isOpen)
   {
      G_DPM_OPEN_EVT_COUNT[lvl]++;
      G_DPM_OPEN_EVT_LAST_MS[lvl] = durMs;
      if(G_DPM_OPEN_EVT_COUNT[lvl] == 1 || durMs < G_DPM_OPEN_EVT_MIN_MS[lvl])
         G_DPM_OPEN_EVT_MIN_MS[lvl] = durMs;
      if(durMs > G_DPM_OPEN_EVT_MAX_MS[lvl])
         G_DPM_OPEN_EVT_MAX_MS[lvl] = durMs;
      G_DPM_OPEN_EVT_SUM_MS[lvl] += (double)durMs;
   }
   else
   {
      G_DPM_CLOSE_EVT_COUNT[lvl]++;
      G_DPM_CLOSE_EVT_LAST_MS[lvl] = durMs;
      if(G_DPM_CLOSE_EVT_COUNT[lvl] == 1 || durMs < G_DPM_CLOSE_EVT_MIN_MS[lvl])
         G_DPM_CLOSE_EVT_MIN_MS[lvl] = durMs;
      if(durMs > G_DPM_CLOSE_EVT_MAX_MS[lvl])
         G_DPM_CLOSE_EVT_MAX_MS[lvl] = durMs;
      G_DPM_CLOSE_EVT_SUM_MS[lvl] += (double)durMs;
   }

   if(I_DPM_CSV_ENABLED)
   {
      const string ts = StringFormat("%s.%03u",
                                     TimeToString(ev.eventTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                                     (uint)(durMs % 1000));
      const string row = StringFormat("%s,%s,%s,%s,%d,%d,%.4f,%.4f,%u,%d,%d,%d,%d,%.4f\n",
                                      ts, G_SYMBOL,
                                      isOpen ? "OPEN_ABOVE" : "CLOSE_ABOVE",
                                      side,
                                      ev.level, thPts,
                                      snap, peak,
                                      (uint)durMs,
                                      fired,
                                      ev.signalMode,
                                      ev.masterSpread, ev.slaveSpread,
                                      ev.avgSnap);
      G_DPM_CSV_BUFFER += row;
      G_DPM_CSV_PENDING = true;
   }
}

void DpmObserveLevel(const double diff, const int thPts, const int lvl,
                     const bool isOpen, const ulong nw, const string side)
{
   bool   above   = isOpen ? G_DPM_OPEN_ABOVE[lvl]    : G_DPM_CLOSE_ABOVE[lvl];
   ulong  startMs = isOpen ? G_DPM_OPEN_START_MS[lvl] : G_DPM_CLOSE_START_MS[lvl];
   double peak    = isOpen ? G_DPM_OPEN_PEAK[lvl]     : G_DPM_CLOSE_PEAK[lvl];
   double snap    = isOpen ? G_DPM_OPEN_SNAP[lvl]     : G_DPM_CLOSE_SNAP[lvl];
   bool   fired   = isOpen ? G_DPM_OPEN_FIRED[lvl]    : G_DPM_CLOSE_FIRED[lvl];

   if(diff >= (double)thPts)
   {
      if(!above)
      {
         above   = true;
         startMs = nw;
         snap    = diff;
         peak    = diff;
         fired   = false;
      }
      else if(diff > peak)
         peak = diff;
   }
   else
   {
      if(above)
      {
         if(StringLen(side) > 0)
         {
            const ulong dur = (nw > startMs) ? (nw - startMs) : 0;
            DpmRecordEvent(isOpen, lvl, thPts, snap, peak, dur, fired ? 1 : 0, side);
         }
         above = false;
         fired = false;
      }
   }

   if(isOpen)
   {
      G_DPM_OPEN_ABOVE[lvl]    = above;
      G_DPM_OPEN_START_MS[lvl] = startMs;
      G_DPM_OPEN_PEAK[lvl]     = peak;
      G_DPM_OPEN_SNAP[lvl]     = snap;
      G_DPM_OPEN_FIRED[lvl]    = fired;
   }
   else
   {
      G_DPM_CLOSE_ABOVE[lvl]    = above;
      G_DPM_CLOSE_START_MS[lvl] = startMs;
      G_DPM_CLOSE_PEAK[lvl]     = peak;
      G_DPM_CLOSE_SNAP[lvl]     = snap;
      G_DPM_CLOSE_FIRED[lvl]    = fired;
   }
}

void DpmMasterTick(const ulong nw)
{
   const string side = DpmResolveMasterSide();

   const double diffO = DiffOpenPtsFor(DiffMasterBuyEffective());
   const double diffC = DiffClosePtsFor(DiffMasterBuyEffective());

   int openTh[3];
   openTh[0] = I_DPM_OPEN_TH1;
   openTh[1] = I_DPM_OPEN_TH2;
   openTh[2] = I_DPM_OPEN_TH3;

   int closeTh[3];
   closeTh[0] = I_DPM_CLOSE_TH1;
   closeTh[1] = I_DPM_CLOSE_TH2;
   closeTh[2] = I_DPM_CLOSE_TH3;

   for(int i = 0; i < 3; i++)
   {
      if(I_DPM_TRACK_OPEN)
         DpmObserveLevel(diffO, openTh[i], i, true, nw, side);
      if(I_DPM_TRACK_CLOSE)
         DpmObserveLevel(diffC, closeTh[i], i, false, nw, side);
   }
}

void DpmNotifyFired(const bool isOpen)
{
   if(!I_DPM_ENABLED)
      return;
   for(int i = 0; i < 3; i++)
   {
      if(isOpen && G_DPM_OPEN_ABOVE[i])
         G_DPM_OPEN_FIRED[i] = true;
      if(!isOpen && G_DPM_CLOSE_ABOVE[i])
         G_DPM_CLOSE_FIRED[i] = true;
   }
}

void DpmEnsureCsvHeader()
{
   if(G_DPM_CSV_HEADER_WRITTEN)
      return;
   const string fname = DpmCsvFileName();
   int hCheck = FileOpen(fname, FILE_READ | FILE_SHARE_READ | FILE_ANSI);
   const bool isEmpty = (hCheck == INVALID_HANDLE || FileSize(hCheck) == 0);
   if(hCheck != INVALID_HANDLE)
      FileClose(hCheck);
   if(isEmpty)
   {
      int hw = FileOpen(fname, FILE_WRITE | FILE_SHARE_READ | FILE_ANSI);
      if(hw != INVALID_HANDLE)
      {
         FileWriteString(hw,
            "event_timestamp,symbol,action,master_side,threshold_level,threshold_pts,"
            "actual_diff_start_pts,peak_diff_pts,drift_duration_ms,fired_trade,"
            "signal_mode_active,master_spread_pts,slave_spread_pts,avg_diff_snap\n");
         FileClose(hw);
      }
   }
   G_DPM_CSV_HEADER_WRITTEN = true;
}

void DpmFlushCsv()
{
   if(!G_DPM_CSV_PENDING || StringLen(G_DPM_CSV_BUFFER) == 0)
   {
      G_DPM_CSV_PENDING = false;
      return;
   }
   DpmEnsureCsvHeader();
   const string fname = DpmCsvFileName();
   int h = FileOpen(fname, FILE_WRITE | FILE_READ | FILE_SHARE_READ | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      G_DPM_CSV_PENDING = false;
      G_DPM_CSV_BUFFER  = "";
      return;
   }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, G_DPM_CSV_BUFFER);
   FileClose(h);
   G_DPM_CSV_BUFFER  = "";
   G_DPM_CSV_PENDING = false;
}

string DpmHudStatsLine(const bool isOpen, const int lvl)
{
   const int   cnt   = isOpen ? G_DPM_OPEN_EVT_COUNT[lvl]   : G_DPM_CLOSE_EVT_COUNT[lvl];
   const ulong last  = isOpen ? G_DPM_OPEN_EVT_LAST_MS[lvl] : G_DPM_CLOSE_EVT_LAST_MS[lvl];
   const ulong mn    = isOpen ? G_DPM_OPEN_EVT_MIN_MS[lvl]  : G_DPM_CLOSE_EVT_MIN_MS[lvl];
   const ulong mx    = isOpen ? G_DPM_OPEN_EVT_MAX_MS[lvl]  : G_DPM_CLOSE_EVT_MAX_MS[lvl];
   const double sum  = isOpen ? G_DPM_OPEN_EVT_SUM_MS[lvl]  : G_DPM_CLOSE_EVT_SUM_MS[lvl];
   const int    th   = isOpen ? (lvl == 0 ? I_DPM_OPEN_TH1 : (lvl == 1 ? I_DPM_OPEN_TH2 : I_DPM_OPEN_TH3))
                               : (lvl == 0 ? I_DPM_CLOSE_TH1 : (lvl == 1 ? I_DPM_CLOSE_TH2 : I_DPM_CLOSE_TH3));
   const ulong avg   = (cnt > 0) ? (ulong)(sum / (double)cnt) : 0;
   return StringFormat(" lv%d(%dpt): last=%ums avg=%ums min=%ums max=%ums n=%d\n",
                       lvl + 1, th, (uint)last, (uint)avg, (uint)mn, (uint)mx, cnt);
}

string DpmHudBlock()
{
   if(!I_DPM_ENABLED || I_ROLE != ROLE_SOURCE_MASTER)
      return "";
   string out = "\n[ DPM ]\n";
   if(I_DPM_TRACK_OPEN)
   {
      out += " Open:\n";
      for(int i = 0; i < 3; i++)
         out += DpmHudStatsLine(true, i);
   }
   if(I_DPM_TRACK_CLOSE)
   {
      out += " Close:\n";
      for(int i = 0; i < 3; i++)
         out += DpmHudStatsLine(false, i);
   }
   if(I_DPM_HUD_ROWS > 0 && G_DPM_RING_COUNT > 0)
   {
      out += "\n Recent events:\n";
      const int show = MathMin(I_DPM_HUD_ROWS, G_DPM_RING_COUNT);
      for(int r = 0; r < show; r++)
      {
         int idx = G_DPM_RING_HEAD - 1 - r;
         if(idx < 0) idx += 50;
         DpmEvent ev = G_DPM_RING[idx];
         out += StringFormat("  %s | %s lv%d | %s | start=%.1fpt peak=%.1fpt | %ums | fired=%d\n",
                             TimeToString(ev.eventTime, TIME_MINUTES | TIME_SECONDS),
                             ev.isOpen ? "OPEN " : "CLOSE",
                             ev.level,
                             ev.masterSide,
                             ev.snapPts, ev.peakPts,
                             (uint)ev.durationMs,
                             ev.fired);
      }
   }
   return out;
}

void DiffQueueOpen()
{
   DpmNotifyFired(true);
   G_OPEN_SIGNAL_REASON = "DIFF_OPEN";
   G_OPEN_SIGNAL_REQUESTED = true;
}

void DiffQueueClose()
{
   DpmNotifyFired(false);
   G_CLOSE_SIGNAL_REASON = "DIFF_CLOSE";
   G_CLOSE_SIGNAL_REQUESTED = true;
}

void DiffMasterTick()
{
   if(!I_DIFF_SYNC_ENABLED)
      return;
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;

   if(!G_HANDSHAKE_OK || G_PEER == NULL || !G_PEER.IsSocketConnected())
      return;

   if(DiffIsMasterAuto())
   {
      if(G_DIFF_AUTO_SIDE_LOCKED && !G_DIFF_AUTO_EVER_OPENED && !G_PAIR_ACTIVE && !G_OPEN_TX_ACTIVE)
      {
         const double ld = DiffOpenPtsFor(G_DIFF_AUTO_EFF_SIDE == SIDE_BUY);
         if(ld < 0.0)
            DiffAutoUnlockSearching();
      }
      if(G_DIFF_AUTO_SIDE_LOCKED && G_DIFF_AUTO_EVER_OPENED && !G_PAIR_ACTIVE && !G_OPEN_TX_ACTIVE && !G_CLOSE_TX_ACTIVE)
         DiffAutoUnlockSearching();
   }

   if(G_OPEN_TX_ACTIVE || G_CLOSE_TX_ACTIVE)
      return;

   if(!G_DIFF_SLAVE_QUOTE_OK)
      return;

   if(!DiffQuotesFresh())
      return;

   if(DiffSpreadPts(G_DIFF_SELF_BID, G_DIFF_SELF_ASK) > I_DIFF_MAX_SPREAD_SELF)
      return;
   if(DiffSpreadPts(G_DIFF_SLAVE_BID, G_DIFF_SLAVE_ASK) > I_DIFF_MAX_SPREAD_PEER)
      return;

   if(I_DIFF_ZONE_STABILITY_ENABLED)
   {
      const double dOz = DiffOpenPts();
      const double dCz = DiffClosePts();
      DiffZoneScan(dOz, I_DIFF_OPEN_THRESHOLD_PTS, G_DIFF_OPEN_ZONE_OK, G_DIFF_OPEN_ZP, G_DIFF_OPEN_ZN);
      DiffZoneScan(dCz, I_DIFF_CLOSE_THRESHOLD_PTS, G_DIFF_CLOSE_ZONE_OK, G_DIFF_CLOSE_ZP, G_DIFF_CLOSE_ZN);
   }
   else
   {
      G_DIFF_OPEN_ZONE_OK = true;
      G_DIFF_CLOSE_ZONE_OK = true;
   }

   if(!G_PAIR_ACTIVE)
   {
      const ulong nw = NowMs();
      if((nw - G_DIFF_LAST_OPEN_SIGNAL_MS) < (ulong)I_DIFF_OPEN_COOLDOWN_SEC * (ulong)1000)
         return;

      const int th = I_DIFF_OPEN_THRESHOLD_PTS;
      if(DiffIsMasterAuto())
      {
         if(!DiffAutoTryResolveLock(th))
            return;
      }

      const double diffOpen = DiffOpenPtsFor(DiffMasterBuyEffective());
      bool fire = false;

      if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_OPEN_ZONE_OK)
      {
         DiffResetOpenSmoothing();
         return;
      }

      if(I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_AVG)
      {
         if(I_DIFF_AVG_SIGNAL_COOLDOWN_MS > 0 && (nw - G_DIFF_LAST_AVG_OPEN_SIG_MS) < (ulong)I_DIFF_AVG_SIGNAL_COOLDOWN_MS)
            return;
         const double avgOpen = DiffSmoothOpen(diffOpen);
         G_DIFF_HUD_LAST_AVG_OPEN = avgOpen;
         const double thrEff = (double)(th + I_DIFF_HYSTERESIS_PTS);

         if(!G_DIFF_OPEN_PENDING)
         {
            if(avgOpen >= thrEff && (!I_DIFF_ZONE_STABILITY_ENABLED || G_DIFF_OPEN_ZONE_OK))
            {
               G_DIFF_OPEN_PENDING = true;
               G_DIFF_OPEN_SNAP_AVG = avgOpen;
               G_DIFF_OPEN_OK_COUNT = 0;
               G_DIFF_OPEN_DEAD_MS = nw + (ulong)I_DIFF_CONFIRM_TIMEOUT_MS;
            }
            return;
         }

         if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_OPEN_ZONE_OK)
         {
            G_DIFF_OPEN_PENDING = false;
            G_DIFF_OPEN_OK_COUNT = 0;
            return;
         }

         bool ok = true;
         if(I_DIFF_REAL_CONFIRM)
         {
            const double need = MathMax(G_DIFF_OPEN_SNAP_AVG, thrEff) + (double)I_DIFF_EPSILON_PTS;
            ok = (diffOpen >= need);
         }
         else
            ok = (avgOpen >= thrEff);
         if(ok)
            G_DIFF_OPEN_OK_COUNT++;
         else
            G_DIFF_OPEN_OK_COUNT = 0;

         if(G_DIFF_OPEN_OK_COUNT >= I_DIFF_CONFIRM_TICKS)
         {
            fire = true;
            G_DIFF_OPEN_PENDING = false;
            G_DIFF_LAST_AVG_OPEN_SIG_MS = nw;
            if(I_DIFF_ZONE_STABILITY_ENABLED)
               DiffResetOpenZoneCounters();
         }
         else if(I_DIFF_CONFIRM_TIMEOUT_MS > 0 && nw > G_DIFF_OPEN_DEAD_MS)
         {
            G_DIFF_OPEN_PENDING = false;
            G_DIFF_OPEN_OK_COUNT = 0;
         }
      }
      else if(I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_RAW_STABILITY)
      {
         const double enter = (double)th;
         const double reset = enter - (double)I_DIFF_RAW_HYSTERESIS_OFFSET;
         if(!G_DIFF_RAW_OPEN_PEND)
         {
            if(diffOpen >= enter && (!I_DIFF_ZONE_STABILITY_ENABLED || G_DIFF_OPEN_ZONE_OK))
            {
               G_DIFF_RAW_OPEN_PEND = true;
               G_DIFF_RAW_OPEN_CNT = 1;
               G_DIFF_RAW_OPEN_START = nw;
            }
            return;
         }
         if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_OPEN_ZONE_OK)
         {
            G_DIFF_RAW_OPEN_PEND = false;
            G_DIFF_RAW_OPEN_CNT = 0;
            return;
         }
         if(diffOpen < reset)
         {
            G_DIFF_RAW_OPEN_PEND = false;
            G_DIFF_RAW_OPEN_CNT = 0;
            return;
         }
         G_DIFF_RAW_OPEN_CNT++;
         if(G_DIFF_RAW_OPEN_CNT >= I_DIFF_RAW_STABILITY_TICKS)
         {
            fire = true;
            G_DIFF_RAW_OPEN_PEND = false;
            if(I_DIFF_ZONE_STABILITY_ENABLED)
               DiffResetOpenZoneCounters();
         }
         if((nw - G_DIFF_RAW_OPEN_START) > (ulong)I_DIFF_RAW_STABILITY_TIMEOUT_MS)
         {
            G_DIFF_RAW_OPEN_PEND = false;
            G_DIFF_RAW_OPEN_CNT = 0;
         }
      }
      else if(I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_TIME_GATE)
      {
         const double reset = (double)th - (double)I_DIFF_TIME_GATE_HYSTERESIS_OFFSET;
         if(!G_DIFF_TG_OPEN_PEND)
         {
            if(diffOpen >= (double)th && (!I_DIFF_ZONE_STABILITY_ENABLED || G_DIFF_OPEN_ZONE_OK))
            {
               G_DIFF_TG_OPEN_PEND     = true;
               G_DIFF_TG_OPEN_START_MS = nw;
            }
            return;
         }
         if(diffOpen < reset || (I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_OPEN_ZONE_OK))
         {
            G_DIFF_TG_OPEN_PEND = false;
            return;
         }
         if(I_DIFF_TIME_GATE_TIMEOUT_MS > 0 && (nw - G_DIFF_TG_OPEN_START_MS) > (ulong)I_DIFF_TIME_GATE_TIMEOUT_MS)
         {
            G_DIFF_TG_OPEN_PEND = false;
            return;
         }
         if((nw - G_DIFF_TG_OPEN_START_MS) >= (ulong)I_DIFF_TIME_GATE_OPEN_MS)
         {
            fire = true;
            G_DIFF_TG_OPEN_PEND = false;
            if(I_DIFF_ZONE_STABILITY_ENABLED)
               DiffResetOpenZoneCounters();
         }
      }
      else
      {
         if(diffOpen < (double)th)
            return;
         if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_OPEN_ZONE_OK)
            return;
         fire = true;
         if(I_DIFF_ZONE_STABILITY_ENABLED)
            DiffResetOpenZoneCounters();
      }

      if(fire)
      {
         G_DIFF_SIGNAL_SNAP_OPEN_PTS = diffOpen;
         if(CloseOnlyMasterBlocksPairOpen())
            return;
         DiffQueueOpen();
      }
      return;
   }

   const ulong nw2 = NowMs();
   if((nw2 - G_DIFF_LAST_CLOSE_SIGNAL_MS) < (ulong)I_DIFF_CLOSE_COOLDOWN_SEC * (ulong)1000)
      return;

   if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_CLOSE_ZONE_OK)
   {
      DiffResetCloseSmoothing();
      return;
   }

   const double diffClose = DiffClosePtsFor(DiffMasterBuyEffective());
   bool fireC = false;

   if(I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_AVG)
   {
      if(I_DIFF_AVG_SIGNAL_COOLDOWN_MS > 0 && (nw2 - G_DIFF_LAST_AVG_CLOSE_SIG_MS) < (ulong)I_DIFF_AVG_SIGNAL_COOLDOWN_MS)
         return;
      const double avgC = DiffSmoothClose(diffClose);
      G_DIFF_HUD_LAST_AVG_CLOSE = avgC;
      const double thrEff = (double)(I_DIFF_CLOSE_THRESHOLD_PTS + I_DIFF_HYSTERESIS_PTS);

      if(!G_DIFF_CLOSE_PENDING)
      {
         if(avgC >= thrEff && (!I_DIFF_ZONE_STABILITY_ENABLED || G_DIFF_CLOSE_ZONE_OK))
         {
            G_DIFF_CLOSE_PENDING = true;
            G_DIFF_CLOSE_SNAP_AVG = avgC;
            G_DIFF_CLOSE_OK_COUNT = 0;
            G_DIFF_CLOSE_DEAD_MS = nw2 + (ulong)I_DIFF_CONFIRM_TIMEOUT_MS;
         }
         return;
      }

      if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_CLOSE_ZONE_OK)
      {
         G_DIFF_CLOSE_PENDING = false;
         G_DIFF_CLOSE_OK_COUNT = 0;
         return;
      }

      bool ok = true;
      if(I_DIFF_REAL_CONFIRM)
      {
         const double need = MathMax(G_DIFF_CLOSE_SNAP_AVG, thrEff) + (double)I_DIFF_EPSILON_PTS;
         ok = (diffClose >= need);
      }
      else
         ok = (avgC >= thrEff);
      if(ok)
         G_DIFF_CLOSE_OK_COUNT++;
      else
         G_DIFF_CLOSE_OK_COUNT = 0;

      if(G_DIFF_CLOSE_OK_COUNT >= I_DIFF_CONFIRM_TICKS)
      {
         fireC = true;
         G_DIFF_CLOSE_PENDING = false;
         G_DIFF_LAST_AVG_CLOSE_SIG_MS = nw2;
         if(I_DIFF_ZONE_STABILITY_ENABLED)
            DiffResetCloseZoneCounters();
      }
      else if(I_DIFF_CONFIRM_TIMEOUT_MS > 0 && nw2 > G_DIFF_CLOSE_DEAD_MS)
      {
         G_DIFF_CLOSE_PENDING = false;
         G_DIFF_CLOSE_OK_COUNT = 0;
      }
   }
   else if(I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_RAW_STABILITY)
   {
      const double enter = (double)I_DIFF_CLOSE_THRESHOLD_PTS;
      const double reset = enter - (double)I_DIFF_RAW_HYSTERESIS_OFFSET;
      if(!G_DIFF_RAW_CLOSE_PEND)
      {
         if(diffClose >= enter && (!I_DIFF_ZONE_STABILITY_ENABLED || G_DIFF_CLOSE_ZONE_OK))
         {
            G_DIFF_RAW_CLOSE_PEND = true;
            G_DIFF_RAW_CLOSE_CNT = 1;
            G_DIFF_RAW_CLOSE_START = nw2;
         }
         return;
      }
      if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_CLOSE_ZONE_OK)
      {
         G_DIFF_RAW_CLOSE_PEND = false;
         G_DIFF_RAW_CLOSE_CNT = 0;
         return;
      }
      if(diffClose < reset)
      {
         G_DIFF_RAW_CLOSE_PEND = false;
         G_DIFF_RAW_CLOSE_CNT = 0;
         return;
      }
      G_DIFF_RAW_CLOSE_CNT++;
      if(G_DIFF_RAW_CLOSE_CNT >= I_DIFF_RAW_STABILITY_TICKS)
      {
         fireC = true;
         G_DIFF_RAW_CLOSE_PEND = false;
         if(I_DIFF_ZONE_STABILITY_ENABLED)
            DiffResetCloseZoneCounters();
      }
      if((nw2 - G_DIFF_RAW_CLOSE_START) > (ulong)I_DIFF_RAW_STABILITY_TIMEOUT_MS)
      {
         G_DIFF_RAW_CLOSE_PEND = false;
         G_DIFF_RAW_CLOSE_CNT = 0;
      }
   }
   else if(I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_TIME_GATE)
   {
      const double resetC = (double)I_DIFF_CLOSE_THRESHOLD_PTS - (double)I_DIFF_TIME_GATE_HYSTERESIS_OFFSET;
      if(!G_DIFF_TG_CLOSE_PEND)
      {
         if(diffClose >= (double)I_DIFF_CLOSE_THRESHOLD_PTS && (!I_DIFF_ZONE_STABILITY_ENABLED || G_DIFF_CLOSE_ZONE_OK))
         {
            G_DIFF_TG_CLOSE_PEND     = true;
            G_DIFF_TG_CLOSE_START_MS = nw2;
         }
         return;
      }
      if(diffClose < resetC || (I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_CLOSE_ZONE_OK))
      {
         G_DIFF_TG_CLOSE_PEND = false;
         return;
      }
      if(I_DIFF_TIME_GATE_TIMEOUT_MS > 0 && (nw2 - G_DIFF_TG_CLOSE_START_MS) > (ulong)I_DIFF_TIME_GATE_TIMEOUT_MS)
      {
         G_DIFF_TG_CLOSE_PEND = false;
         return;
      }
      if((nw2 - G_DIFF_TG_CLOSE_START_MS) >= (ulong)I_DIFF_TIME_GATE_CLOSE_MS)
      {
         fireC = true;
         G_DIFF_TG_CLOSE_PEND = false;
         if(I_DIFF_ZONE_STABILITY_ENABLED)
            DiffResetCloseZoneCounters();
      }
   }
   else
   {
      if(diffClose < (double)I_DIFF_CLOSE_THRESHOLD_PTS)
         return;
      if(I_DIFF_ZONE_STABILITY_ENABLED && !G_DIFF_CLOSE_ZONE_OK)
         return;
      fireC = true;
      if(I_DIFF_ZONE_STABILITY_ENABLED)
         DiffResetCloseZoneCounters();
   }

   if(fireC)
   {
      G_DIFF_SIGNAL_SNAP_CLOSE_PTS = diffClose;
      DiffQueueClose();
   }
}

void SlaveSendQuoteStream()
{
   if(G_PEER == NULL || !G_PEER.IsSocketConnected() || !G_HANDSHAKE_OK)
      return;
   if(G_SLAVE_DUP_CHANNEL_SHUTDOWN)
      return;
   MqlTick tk;
   double bid = 0.0, ask = 0.0;
   ulong qmsc = 0;
   if(SymbolInfoTick(G_SYMBOL, tk))
   {
      bid = DiffNormQuotePrice(tk.bid);
      ask = DiffNormQuotePrice(tk.ask);
      qmsc = tk.time_msc;
      if(qmsc == 0)
         qmsc = (ulong)tk.time * 1000UL;
   }
   else
   {
      bid = DiffNormQuotePrice(SymbolInfoDouble(G_SYMBOL, SYMBOL_BID));
      ask = DiffNormQuotePrice(SymbolInfoDouble(G_SYMBOL, SYMBOL_ASK));
      const datetime tt = (datetime)SymbolInfoInteger(G_SYMBOL, SYMBOL_TIME);
      qmsc = (ulong)tt * 1000UL;
   }
   const double pl = SumMagicSymbolPnl();
   ResetLastError();
   int slave_tm = (int)SymbolInfoInteger(G_SYMBOL, SYMBOL_TRADE_MODE);
   if(GetLastError() != 0)
   {
      ResetLastError();
      slave_tm = DiffTerminalTradeAllowedLikeMql4() ? 4 : 0;
   }
   const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   SendMsg(G_PEER,
           StringFormat("SLAVE;%.10f;%.10f;%s;%I64u;%d;%I64u;%.5f;%.2f",
                        bid, ask, G_SYMBOL, qmsc, slave_tm, NowMs(), pl, bal));
}

void DiffEnsureLabel(const string name, const int xdist, const int ydist, const int fontPx)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontPx);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xdist);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, ydist);
}

void CreateDiffUi()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   // Right edge: small XDISTANCE with ANCHOR_RIGHT_UPPER (labels extend left). Buttons keep bx.
   const int dx = 8;
   const int y_open_dx = 28;
   const int y_open_val = 44;
   const int y_close_dx = 72;
   const int y_close_val = 88;
   const int y_pl_dx = 116;
   const int y_pl_val = 132;
   DiffEnsureLabel("SFX_DX_OPEN_TITLE", dx, y_open_dx, 8);
   DiffEnsureLabel("SFX_DX_OPEN_VALUE", dx, y_open_val, 10);
   DiffEnsureLabel("SFX_DX_CLOSE_TITLE", dx, y_close_dx, 8);
   DiffEnsureLabel("SFX_DX_CLOSE_VALUE", dx, y_close_val, 10);
   DiffEnsureLabel("SFX_DX_PL_TITLE", dx, y_pl_dx, 8);
   DiffEnsureLabel("SFX_DX_PL_VALUE", dx, y_pl_val, 10);
}

void SetDiffHudTitleMode(const bool autosync_armed)
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   const string wO = DiffHudWarningSuffixOpen();
   const string wC = DiffHudWarningSuffixClose();
   const string oTitle =
      (autosync_armed ? "DIFF OPEN (pts)" : "DIFF OPEN (display only)") + wO;
   const string cTitle =
      (autosync_armed ? "DIFF CLOSE (pts)" : "DIFF CLOSE (display only)") + wC;
   ObjectSetString(0, "SFX_DX_OPEN_TITLE", OBJPROP_TEXT, oTitle);
   ObjectSetString(0, "SFX_DX_CLOSE_TITLE", OBJPROP_TEXT, cTitle);
   ObjectSetString(0, "SFX_DX_PL_TITLE", OBJPROP_TEXT, "P/L");
}

// Capture globals live in the expert, above OpenOrder. This module only reads them.
// event_timestamp is TimeLocal / GetLocalTime (VPS), not TimeCurrent (broker server).
#define FILL_AUDIT_SCHEMA_VER "v2"
#define FILL_AUDIT_CSV_HEADER "event_timestamp,symbol,master_account,slave_account,action,reason,pair_id,tx_id,master_side,master_ticket,slave_ticket,signal_pts,master_bid,master_ask,slave_bid,slave_ask,master_request,master_fill,master_slip_pts,master_slip_class,slave_request,slave_fill,slave_slip_pts,slave_slip_class,realized_pts,gap_pts,flagged,prices_ok,master_exec_ms,slave_exec_ms,pair_span_ms,open_mode,close_mode"

struct SfxSystemTime
{
   ushort wYear;
   ushort wMonth;
   ushort wDayOfWeek;
   ushort wDay;
   ushort wHour;
   ushort wMinute;
   ushort wSecond;
   ushort wMilliseconds;
};

#import "kernel32.dll"
   void GetLocalTime(SfxSystemTime &st);
#import

bool   G_FA_ACTIVE = false;
bool   G_FA_FINALIZED = false;
bool   G_FA_IS_OPEN = false;
string G_FA_ACTION = "";
string G_FA_REASON = "";
string G_FA_PAIR_ID = "";
string G_FA_TX = "";
bool   G_FA_MASTER_BUY = false;
double G_FA_SIGNAL = 0.0;
double G_FA_M_BID = 0.0;
double G_FA_M_ASK = 0.0;
double G_FA_S_BID = 0.0;
double G_FA_S_ASK = 0.0;
bool   G_FA_MASTER_OK = false;
double G_FA_MASTER_REQ = 0.0;
double G_FA_MASTER_FILL = 0.0;
int    G_FA_MASTER_SLIP = 0;
bool   G_FA_SLAVE_OK = false;
double G_FA_SLAVE_REQ = 0.0;
double G_FA_SLAVE_FILL = 0.0;
int    G_FA_SLAVE_SLIP = 0;
int    G_FA_MASTER_TICKET = 0;
int    G_FA_SLAVE_TICKET = 0;
bool   G_FA_MASTER_EXEC_SET = false;
ulong  G_FA_MASTER_EXEC_MS = 0;
bool   G_FA_SLAVE_EXEC_SET = false;
ulong  G_FA_SLAVE_EXEC_MS = 0;
ulong  G_FA_BEGUN_MS = 0;
int    G_FA_COUNT = 0;
int    G_FA_STREAK = 0;
ulong  G_FA_DETAIL_UNTIL = 0;
string G_FA_DETAIL_TEXT = "";
bool   G_FA_CSV_PENDING = false;
string G_FA_CSV_BUFFER = "";
bool   G_FA_CSV_HEADER = false;
bool   G_FA_SIGNAL_OK = false;

void FillAuditClearCapture()
{
   G_FILL_CAP_VALID = false;
   G_FILL_CAP_IS_BUY = false;
   G_FILL_CAP_REQUEST = 0.0;
   G_FILL_CAP_FILL = 0.0;
   G_FILL_CAP_EXEC_SET = false;
   G_FILL_CAP_EXEC_MS = 0;
}

void FillAuditSetExecMs(const ulong execMs)
{
   G_FILL_CAP_EXEC_SET = true;
   G_FILL_CAP_EXEC_MS = execMs;
}

void FillAuditStoreCapture(const bool isBuy, const double request, const double fill, const bool ok)
{
   G_FILL_CAP_IS_BUY = isBuy;
   G_FILL_CAP_REQUEST = request;
   G_FILL_CAP_FILL = (ok ? fill : 0.0);
   G_FILL_CAP_VALID = (ok && request > 0.0 && fill > 0.0);
}

void FillAuditRememberReplay()
{
   G_FILL_REPLAY_REQ = G_FILL_CAP_REQUEST;
   G_FILL_REPLAY_FILL = G_FILL_CAP_FILL;
   G_FILL_REPLAY_EXEC_SET = G_FILL_CAP_EXEC_SET;
   G_FILL_REPLAY_EXEC_MS = G_FILL_CAP_EXEC_MS;
}

string FillAuditPackOpenResult(const string txid, const int ok, const int ticket, const int err, const bool replay)
{
   const double req = replay ? G_FILL_REPLAY_REQ : G_FILL_CAP_REQUEST;
   const double fill = replay ? G_FILL_REPLAY_FILL : G_FILL_CAP_FILL;
   const ulong execMs = replay ? G_FILL_REPLAY_EXEC_MS : G_FILL_CAP_EXEC_MS;
   return StringFormat("OPEN_RESULT;%s;%d;%d;%d;%.8f;%.8f;%I64u", txid, ok, ticket, err, req, fill, execMs);
}

string FillAuditPackCloseResult(const string txid, const int ok, const int ticket, const int err, const double bal)
{
   return StringFormat("CLOSE_RESULT;%s;%d;%d;%d;%.2f;%.8f;%.8f;%I64u",
                       txid, ok, ticket, err, bal, G_FILL_CAP_REQUEST, G_FILL_CAP_FILL, G_FILL_CAP_EXEC_MS);
}

double FillAuditDealPrice(const ulong deal)
{
   if(deal == 0)
      return 0.0;
   if(!HistoryDealSelect(deal))
   {
      HistorySelect(TimeCurrent() - 60, TimeCurrent() + 1);
      if(!HistoryDealSelect(deal))
         return 0.0;
   }
   return HistoryDealGetDouble(deal, DEAL_PRICE);
}

void FillAuditNoteMt5Fill(const bool isBuy, const double request, const ulong deal, const double resultPrice, const ulong positionTicket)
{
   double fill = FillAuditDealPrice(deal);
   if(fill <= 0.0 && positionTicket > 0 && PositionSelectByTicket(positionTicket))
      fill = PositionGetDouble(POSITION_PRICE_OPEN);
   FillAuditStoreCapture(isBuy, request, fill, fill > 0.0 && request > 0.0);
}

void FillAuditNoteRecoveredPosition(const ulong ticket)
{
   double fill = 0.0;
   if(ticket > 0 && PositionSelectByTicket(ticket))
      fill = PositionGetDouble(POSITION_PRICE_OPEN);
   if(fill > 0.0 && G_FILL_CAP_REQUEST > 0.0)
      FillAuditStoreCapture(G_FILL_CAP_IS_BUY, G_FILL_CAP_REQUEST, fill, true);
}

bool FillAuditMasterPositionIsBuy(const int ticket)
{
   if(ticket > 0 && PositionSelectByTicket((ulong)ticket))
      return ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   return DiffMasterBuyEffective();
}

int FillAuditSlipPts(const bool isBuy, const double request, const double fill)
{
   const double pt = DiffPoint();
   if(pt <= 0.0 || request <= 0.0 || fill <= 0.0)
      return 0;
   // Positive means a worse fill for that order: buy filled higher, sell filled lower.
   const double raw = isBuy ? (fill - request) : (request - fill);
   return (int)MathRound(raw / pt);
}

string FillAuditSlipClass(const bool hasPrice, const int slipPts)
{
   if(!hasPrice)
      return "";
   if(slipPts > 0)
      return "WORSE";
   if(slipPts < 0)
      return "BETTER";
   return "FLAT";
}

double FillAuditRealizedPts(const bool isOpen, const bool masterBuy, const double masterFill, const double slaveFill)
{
   const double pt = DiffPoint();
   if(pt <= 0.0)
      return 0.0;
   const double diff = isOpen
                       ? (masterBuy ? (slaveFill - masterFill) : (masterFill - slaveFill))
                       : (masterBuy ? (masterFill - slaveFill) : (slaveFill - masterFill));
   return diff / pt;
}

string FillAuditSignedInt(const int v)
{
   if(v > 0)
      return StringFormat("+%d", v);
   return IntegerToString(v);
}

string G_AUDIT_SLAVE_ACCOUNT = "";

string FillAuditCsvFileName()
{
   return StringFormat("FILL_AUDIT_%s_%I64d_%s.csv", FILL_AUDIT_SCHEMA_VER,
                      AccountInfoInteger(ACCOUNT_LOGIN), G_SYMBOL);
}

string FillAuditEventTimestamp()
{
   SfxSystemTime st;
   GetLocalTime(st);
   return StringFormat("%04d.%02d.%02d %02d:%02d:%02d.%03d",
                      st.wYear, st.wMonth, st.wDay,
                      st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
}

string FillAuditCsvPrice(const bool ok, const double px)
{
   if(!ok || px <= 0.0)
      return "";
   return StringFormat("%.8f", px);
}

string FillAuditCsvDouble(const bool ok, const double v, const int digits)
{
   if(!ok)
      return "";
   return DoubleToString(v, digits);
}

string FillAuditCsvSlipPts(const bool ok, const int slip)
{
   if(!ok)
      return "";
   return IntegerToString(slip);
}

string FillAuditCsvTicket(const int ticket)
{
   if(ticket <= 0)
      return "";
   return IntegerToString(ticket);
}

void FillAuditNoteTickets(const int masterTicket, const int slaveTicket)
{
   if(masterTicket > 0)
      G_FA_MASTER_TICKET = masterTicket;
   if(slaveTicket > 0)
      G_FA_SLAVE_TICKET = slaveTicket;
}

void FillAuditResetSession()
{
   G_FA_SIGNAL_OK = false;
   G_FA_MASTER_OK = false;
   G_FA_SLAVE_OK = false;
   G_FA_MASTER_REQ = 0.0;
   G_FA_MASTER_FILL = 0.0;
   G_FA_MASTER_SLIP = 0;
   G_FA_SLAVE_REQ = 0.0;
   G_FA_SLAVE_FILL = 0.0;
   G_FA_SLAVE_SLIP = 0;
   G_FA_MASTER_TICKET = 0;
   G_FA_SLAVE_TICKET = 0;
   G_FA_MASTER_EXEC_SET = false;
   G_FA_MASTER_EXEC_MS = 0;
   G_FA_SLAVE_EXEC_SET = false;
   G_FA_SLAVE_EXEC_MS = 0;
   G_FA_LAST_REALIZED_OK = false;
   G_FA_LAST_REALIZED_PTS = 0.0;
}

void FillAuditQueueRow(const bool pricesOk, const double realized, const double gap, const int flagged, const bool bothLegsOk)
{
   if(!I_FILL_AUDIT_ENABLED)
      return;
   const ulong nw = NowMs();
   const string ts = FillAuditEventTimestamp();
   const ulong spanMs = (G_FA_BEGUN_MS > 0 && nw >= G_FA_BEGUN_MS) ? (nw - G_FA_BEGUN_MS) : 0;
   const string masterExec = G_FA_MASTER_EXEC_SET ? StringFormat("%I64u", G_FA_MASTER_EXEC_MS) : "";
   const string slaveExec = G_FA_SLAVE_EXEC_SET ? StringFormat("%I64u", G_FA_SLAVE_EXEC_MS) : "";
   const string masterAccount = StringFormat("%I64d", AccountInfoInteger(ACCOUNT_LOGIN));
   const string action = (StringLen(G_FA_ACTION) > 0) ? G_FA_ACTION : (G_FA_IS_OPEN ? "OPEN" : "CLOSE");
   const string row = StringFormat(
      "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%d,%s,%s,%I64u,%s,%s\n",
      ts, G_SYMBOL, masterAccount, G_AUDIT_SLAVE_ACCOUNT,
      action, G_FA_REASON, G_FA_PAIR_ID, G_FA_TX,
      G_FA_MASTER_BUY ? "BUY" : "SELL",
      FillAuditCsvTicket(G_FA_MASTER_TICKET),
      FillAuditCsvTicket(G_FA_SLAVE_TICKET),
      FillAuditCsvDouble(G_FA_SIGNAL_OK, G_FA_SIGNAL, 4),
      FillAuditCsvPrice(G_FA_M_BID > 0.0, G_FA_M_BID),
      FillAuditCsvPrice(G_FA_M_ASK > 0.0, G_FA_M_ASK),
      FillAuditCsvPrice(G_FA_S_BID > 0.0, G_FA_S_BID),
      FillAuditCsvPrice(G_FA_S_ASK > 0.0, G_FA_S_ASK),
      FillAuditCsvPrice(G_FA_MASTER_REQ > 0.0, G_FA_MASTER_REQ),
      FillAuditCsvPrice(G_FA_MASTER_OK, G_FA_MASTER_FILL),
      FillAuditCsvSlipPts(G_FA_MASTER_OK, G_FA_MASTER_SLIP),
      FillAuditSlipClass(G_FA_MASTER_OK, G_FA_MASTER_SLIP),
      FillAuditCsvPrice(G_FA_SLAVE_REQ > 0.0, G_FA_SLAVE_REQ),
      FillAuditCsvPrice(G_FA_SLAVE_OK, G_FA_SLAVE_FILL),
      FillAuditCsvSlipPts(G_FA_SLAVE_OK, G_FA_SLAVE_SLIP),
      FillAuditSlipClass(G_FA_SLAVE_OK, G_FA_SLAVE_SLIP),
      FillAuditCsvDouble(pricesOk, realized, 4),
      FillAuditCsvDouble(pricesOk, gap, 4),
      flagged,
      (bothLegsOk && pricesOk) ? 1 : 0,
      masterExec, slaveExec, spanMs,
      OpenModeToString(I_OPEN_MODE), CloseModeToString(I_CLOSE_MODE));
   G_FA_CSV_BUFFER += row;
   G_FA_CSV_PENDING = true;
}

void FillAuditFinish(const bool bothLegsOk)
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(!G_FA_ACTIVE || G_FA_FINALIZED)
      return;
   G_FA_FINALIZED = true;

   const bool pricesOk = bothLegsOk && G_FA_MASTER_OK && G_FA_SLAVE_OK;
   double realized = 0.0;
   double gap = 0.0;
   int flagged = 0;
   G_FA_LAST_REALIZED_OK = pricesOk;
   G_FA_LAST_REALIZED_PTS = 0.0;
   if(pricesOk)
   {
      realized = FillAuditRealizedPts(G_FA_IS_OPEN, G_FA_MASTER_BUY, G_FA_MASTER_FILL, G_FA_SLAVE_FILL);
      G_FA_LAST_REALIZED_PTS = realized;
      gap = G_FA_SIGNAL - realized;
      if(I_FILL_AUDIT_ENABLED && gap >= (double)MathMax(0, I_FILL_AUDIT_GAP_PTS))
      {
         flagged = 1;
         G_FA_COUNT++;
         G_FA_STREAK++;
         const int hold = MathMax(0, I_FILL_AUDIT_HOLD_SEC);
         G_FA_DETAIL_TEXT = StringFormat(
            "SLIPPAGE %s gap %.1f (sig %.1f -> fill %.1f) M%s S%s | n=%d streak=%d",
            G_FA_IS_OPEN ? "OPEN" : "CLOSE",
            gap, G_FA_SIGNAL, realized,
            G_FA_MASTER_OK ? FillAuditSignedInt(G_FA_MASTER_SLIP) : "?",
            G_FA_SLAVE_OK ? FillAuditSignedInt(G_FA_SLAVE_SLIP) : "?",
            G_FA_COUNT, G_FA_STREAK);
         G_FA_DETAIL_UNTIL = NowMs() + (ulong)hold * 1000UL;
      }
      else if(I_FILL_AUDIT_ENABLED)
         G_FA_STREAK = 0;
   }
   FillAuditQueueRow(pricesOk, realized, gap, flagged, bothLegsOk);
   G_FA_ACTIVE = false;
}

void FillAuditBegin(const bool isOpen, const string txId, const bool masterBuy, const string reasonTag)
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(G_FA_ACTIVE && !G_FA_FINALIZED)
      FillAuditFinish(false);

   G_FA_ACTIVE = true;
   G_FA_FINALIZED = false;
   G_FA_IS_OPEN = isOpen;
   G_FA_ACTION = isOpen ? "OPEN" : "CLOSE";
   G_FA_REASON = reasonTag;
   G_FA_PAIR_ID = isOpen ? txId : G_PAIR_KEY;
   G_FA_TX = txId;
   G_FA_BEGUN_MS = NowMs();
   G_FA_MASTER_BUY = masterBuy;
   G_FA_M_BID = G_DIFF_SELF_BID;
   G_FA_M_ASK = G_DIFF_SELF_ASK;
   G_FA_S_BID = G_DIFF_SLAVE_BID;
   G_FA_S_ASK = G_DIFF_SLAVE_ASK;
   if(isOpen && reasonTag == "DIFF_OPEN")
      G_FA_SIGNAL = G_DIFF_SIGNAL_SNAP_OPEN_PTS;
   else if(!isOpen && reasonTag == "DIFF_CLOSE")
      G_FA_SIGNAL = G_DIFF_SIGNAL_SNAP_CLOSE_PTS;
   else
      G_FA_SIGNAL = isOpen ? DiffOpenPtsFor(masterBuy) : DiffClosePtsFor(masterBuy);
   FillAuditResetSession();
   G_FA_SIGNAL_OK = true;
   if(!isOpen)
   {
      G_FA_MASTER_TICKET = G_PAIR_MASTER_TICKET;
      G_FA_SLAVE_TICKET = G_PAIR_SLAVE_TICKET;
   }
}

void FillAuditTakeMasterLeg()
{
   if(!G_FA_ACTIVE || G_FA_FINALIZED)
      return;
   if(G_FILL_CAP_EXEC_SET)
   {
      G_FA_MASTER_EXEC_SET = true;
      G_FA_MASTER_EXEC_MS = G_FILL_CAP_EXEC_MS;
   }
   if(G_FILL_CAP_REQUEST > 0.0)
      G_FA_MASTER_REQ = G_FILL_CAP_REQUEST;
   if(!G_FILL_CAP_VALID)
   {
      G_FA_MASTER_OK = false;
      G_FA_MASTER_FILL = 0.0;
      G_FA_MASTER_SLIP = 0;
      return;
   }
   G_FA_MASTER_OK = true;
   G_FA_MASTER_FILL = G_FILL_CAP_FILL;
   G_FA_MASTER_SLIP = FillAuditSlipPts(G_FILL_CAP_IS_BUY, G_FILL_CAP_REQUEST, G_FILL_CAP_FILL);
}

void FillAuditNoteSlavePrices(const double request, const double fill, const ulong execMs, const bool hasExec)
{
   if(!G_FA_ACTIVE || G_FA_FINALIZED)
      return;
   if(hasExec && (execMs > 0 || (request > 0.0 && fill > 0.0)))
   {
      G_FA_SLAVE_EXEC_SET = true;
      G_FA_SLAVE_EXEC_MS = execMs;
   }
   if(request > 0.0)
      G_FA_SLAVE_REQ = request;
   if(request <= 0.0 || fill <= 0.0)
   {
      G_FA_SLAVE_OK = false;
      G_FA_SLAVE_FILL = 0.0;
      G_FA_SLAVE_SLIP = 0;
      return;
   }
   const bool slaveBuy = G_FA_IS_OPEN ? !G_FA_MASTER_BUY : G_FA_MASTER_BUY;
   G_FA_SLAVE_OK = true;
   G_FA_SLAVE_FILL = fill;
   G_FA_SLAVE_SLIP = FillAuditSlipPts(slaveBuy, request, fill);
}

void FillAuditLogEvent(const string action, const string reason, const string pairId, const string txId,
                       const bool masterBuy, const int masterTicket, const int slaveTicket,
                       const bool takeMasterCapture, const bool bothLegsOk)
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(G_FA_ACTIVE && !G_FA_FINALIZED)
      FillAuditFinish(false);

   G_FA_ACTIVE = true;
   G_FA_FINALIZED = false;
   G_FA_IS_OPEN = false;
   G_FA_ACTION = action;
   G_FA_REASON = reason;
   G_FA_PAIR_ID = pairId;
   G_FA_TX = txId;
   G_FA_BEGUN_MS = NowMs();
   G_FA_MASTER_BUY = masterBuy;
   G_FA_M_BID = G_DIFF_SELF_BID;
   G_FA_M_ASK = G_DIFF_SELF_ASK;
   G_FA_S_BID = G_DIFF_SLAVE_BID;
   G_FA_S_ASK = G_DIFF_SLAVE_ASK;
   G_FA_SIGNAL = 0.0;
   G_FA_SIGNAL_OK = false;
   FillAuditResetSession();
   G_FA_MASTER_TICKET = masterTicket;
   G_FA_SLAVE_TICKET = slaveTicket;
   if(takeMasterCapture)
      FillAuditTakeMasterLeg();
   FillAuditFinish(bothLegsOk);
}

void FillAuditEnsureCsvHeader()
{
   if(G_FA_CSV_HEADER)
      return;
   const string fname = FillAuditCsvFileName();
   int hCheck = FileOpen(fname, FILE_READ | FILE_SHARE_READ | FILE_ANSI);
   const bool isEmpty = (hCheck == INVALID_HANDLE || FileSize(hCheck) == 0);
   if(hCheck != INVALID_HANDLE)
      FileClose(hCheck);
   if(isEmpty)
   {
      int hw = FileOpen(fname, FILE_WRITE | FILE_SHARE_READ | FILE_ANSI);
      if(hw != INVALID_HANDLE)
      {
         FileWriteString(hw, FILL_AUDIT_CSV_HEADER);
         FileWriteString(hw, "\n");
         FileClose(hw);
      }
   }
   G_FA_CSV_HEADER = true;
}

void FillAuditFlushCsvNow()
{
   if(!G_FA_CSV_PENDING || StringLen(G_FA_CSV_BUFFER) == 0)
   {
      G_FA_CSV_PENDING = false;
      return;
   }
   FillAuditEnsureCsvHeader();
   const string fname = FillAuditCsvFileName();
   int h = FileOpen(fname, FILE_WRITE | FILE_READ | FILE_SHARE_READ | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      G_FA_CSV_PENDING = false;
      G_FA_CSV_BUFFER = "";
      return;
   }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, G_FA_CSV_BUFFER);
   FileClose(h);
   G_FA_CSV_BUFFER = "";
   G_FA_CSV_PENDING = false;
}

void FillAuditFlushCsv()
{
   if(!I_FILL_AUDIT_ENABLED || I_ROLE != ROLE_SOURCE_MASTER)
      return;
   if(G_OPEN_TX_ACTIVE || G_CLOSE_TX_ACTIVE)
      return;
   FillAuditFlushCsvNow();
}

void FillAuditRefreshHud()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;
   const string name = "SFX_SLIPPAGE_FLAG";
   if(!I_FILL_AUDIT_ENABLED)
   {
      ObjectDelete(0, name);
      return;
   }
   string text = "";
   const bool detailOn = (StringLen(G_FA_DETAIL_TEXT) > 0 && I_FILL_AUDIT_HOLD_SEC > 0 && NowMs() <= G_FA_DETAIL_UNTIL);
   if(detailOn)
      text = G_FA_DETAIL_TEXT;
   else if(G_FA_COUNT > 0)
      text = StringFormat("SLIPPAGE n=%d streak=%d", G_FA_COUNT, G_FA_STREAK);
   if(StringLen(text) == 0)
   {
      ObjectDelete(0, name);
      return;
   }
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 18);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DestroyDiffUi()
{
   FillAuditFlushCsvNow();
   ObjectDelete(0, "SFX_SLIPPAGE_FLAG");
   ObjectDelete(0, "SFX_DX_OPEN_TITLE");
   ObjectDelete(0, "SFX_DX_OPEN_VALUE");
   ObjectDelete(0, "SFX_DX_CLOSE_TITLE");
   ObjectDelete(0, "SFX_DX_CLOSE_VALUE");
   ObjectDelete(0, "SFX_DX_PL_TITLE");
   ObjectDelete(0, "SFX_DX_PL_VALUE");
}

void RefreshDiffHud()
{
   if(I_ROLE != ROLE_SOURCE_MASTER)
      return;

   CreateDiffUi();

   SetDiffHudTitleMode(I_DIFF_SYNC_ENABLED);

   const double rawO = DiffOpenPts();
   const double rawC = DiffClosePts();

   color cO = (rawO > 0.0 ? clrDarkGreen : (rawO < 0.0 ? clrRed : clrSilver));
   color cC = (rawC > 0.0 ? clrDarkGreen : (rawC < 0.0 ? clrRed : clrSilver));
   const string warnOpen = DiffHudWarningSuffixOpen();
   const string warnClose = DiffHudWarningSuffixClose();
   const string warnPl = DiffHudWarningSuffixPl();
   ObjectSetString(0, "SFX_DX_OPEN_VALUE", OBJPROP_TEXT, StringFormat("%.0f%s", rawO, warnOpen));
   ObjectSetInteger(0, "SFX_DX_OPEN_VALUE", OBJPROP_COLOR, cO);
   ObjectSetString(0, "SFX_DX_CLOSE_VALUE", OBJPROP_TEXT, StringFormat("%.0f%s", rawC, warnClose));
   ObjectSetInteger(0, "SFX_DX_CLOSE_VALUE", OBJPROP_COLOR, cC);
   const double pl_sum = G_DIFF_MASTER_MAGIC_PL + G_DIFF_SLAVE_STREAM_PROFIT;
   color pl_c = pl_sum > 0.0 ? clrDarkGreen : (pl_sum < 0.0 ? clrFireBrick : clrSilver);
   ObjectSetString(0, "SFX_DX_PL_VALUE", OBJPROP_TEXT, StringFormat("%.2f%s", pl_sum, warnPl));
   ObjectSetInteger(0, "SFX_DX_PL_VALUE", OBJPROP_COLOR, pl_c);
   FillAuditRefreshHud();
}

void DiffInitRoleDefaults()
{
   if(!DiffIsMasterAuto())
   {
      G_DIFF_AUTO_EFF_SIDE = I_MASTER_SIDE;
      G_DIFF_AUTO_SIDE_LOCKED = true;
      G_DIFF_AUTO_EVER_OPENED = false;
   }
   else
   {
      G_DIFF_AUTO_SIDE_LOCKED = false;
      G_DIFF_AUTO_EVER_OPENED = false;
   }
}

#endif
