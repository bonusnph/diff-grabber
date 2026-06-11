// Slave stream (required): SLAVE;bid;ask;symbol;quote_msc;trade_mode;srv_ms;profit;balance~
#ifndef __FXH_SYNC_HEADER_MQL5_MQH__
#define __FXH_SYNC_HEADER_MQL5_MQH__

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
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG && I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_RAW_STABILITY)
      return "";
   if(G_PAIR_ACTIVE)
      return "";

   const bool modeAvg = (I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_AVG);
   string lines = "\nOPEN signal (";
   lines += modeAvg ? "AVG" : "RAW stability";
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
   if(I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_AVG && I_DIFF_SIGNAL_MODE_VAL != DIFF_SIGNAL_RAW_STABILITY)
      return "";
   if(!G_PAIR_ACTIVE)
      return "";

   const bool modeAvg = (I_DIFF_SIGNAL_MODE_VAL == DIFF_SIGNAL_AVG);
   string lines = "\nCLOSE signal (";
   lines += modeAvg ? "AVG" : "RAW stability";
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

void DiffQueueOpen()
{
   G_OPEN_SIGNAL_REASON = "DIFF_OPEN";
   G_OPEN_SIGNAL_REQUESTED = true;
}

void DiffQueueClose()
{
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

void DestroyDiffUi()
{
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
