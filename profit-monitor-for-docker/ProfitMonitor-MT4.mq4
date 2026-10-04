//+------------------------------------------------------------------+
//|                                             ProfitMonitor-MT4.mq4 |
//|                                    Copyright 2024, Profit Monitor |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Profit Monitor"
#property version   "1.05"
#property strict

// Input parameters
input string API_URL = "https://profit.sumofx.co/api/webhook"; // API endpoint URL
input int SendInterval = 10; // Send interval in seconds (30 = 30 seconds)
input int Unit = 0; // Unit/Label for grouping (1, 2, 3, etc.)
input bool I_NOTIFY_SENDER = false; // Notify sender: MT Push + Telegram from SFX-SYNC queue
input string I_TG_BOT_TOKEN = ""; // Optional token; prefer I_TG_TOKEN_FILE (plaintext in chart/.set; never logged)
input string I_TG_CHAT_ID = "-5310463849"; // Telegram chat id (user or -group)
input string I_TG_TOKEN_FILE = "SFX-SYNC-telegram-token.txt"; // Common Files token if I_TG_BOT_TOKEN empty
input int I_TG_TIMEOUT_MS = 3000; // Telegram WebRequest timeout (ms, clamped 1000-5000)
bool EnableLogging = false; // Enable console logging

// Global variables
int timerInterval = 1; // Check every 1 second

ulong NowMs()
{
   return (ulong)(GetMicrosecondCount() / 1000);
}

string NotifyTrim(const string s)
{
   string t = s;
   t = StringTrimLeft(t);
   t = StringTrimRight(t);
   return t;
}

bool NotifySenderTgBudgetOk()
{
   datetime now2 = TimeLocal();
   int remain = SendInterval - (int)(now2 % SendInterval);
   int to = I_TG_TIMEOUT_MS;
   if(to < 1000)
      to = 1000;
   if(to > 5000)
      to = 5000;
   int need = (to + 999) / 1000 + 1;
   return (remain > need);
}

// ==== BEGIN SFX-NOTIFY-SENDER L2/S2/Q2 ====
#define SFX_NOTIFY_QUEUE_FILE "SFX-SYNC-notify-queue.txt"
#define SFX_NOTIFY_QUEUE_OLD  "SFX-SYNC-notify-queue.txt.old"
#define SFX_NOTIFY_STATE_FILE "SFX-SYNC-notify-offset.txt"
#define SFX_NOTIFY_STATE_TMP  "SFX-SYNC-notify-offset.tmp"
#define SFX_NOTIFY_LOCK_FILE  "SFX-SYNC-notifier.lock"
#define SFX_NOTIFY_LEASE_FILE "SFX-SYNC-notify-lease.txt"
#define SFX_NOTIFY_READ_CHUNK 4096
#define SFX_NOTIFY_ROTATE_BYTES 65536
#define SFX_NOTIFY_TG_RETRY_MAX_SEC 300
#define SFX_NOTIFY_TG_BACKOFF_DEFAULT_SEC 30
#define SFX_NOTIFY_FAIL_PRINT_MS 60000
#define SFX_NOTIFY_LOCK_PRINT_MS 60000
#define LEASE_HB_SEC 5
#define LEASE_STALE_SEC 20
#define FATAL_COOLDOWN_SEC 1800
#define NS_OUTAGE_SKIP_SEC 300
#define NS_LEASE_ABSENT 0
#define NS_LEASE_EMPTY 1
#define NS_LEASE_FREE 2
#define NS_LEASE_OK 3
#define NS_LEASE_UNREADABLE 4
#define NS_ROLE_FOLLOWER 0
#define NS_ROLE_CLAIMING 1
#define NS_ROLE_HOLDER 2
#define NS_ROLE_DEAD 3

bool   G_NS_ACTIVE = false;
string G_NS_KIND = "";
string G_NS_LOG = "";
string G_NS_OWNER = "";
string G_NS_NONCE = "";
string G_NS_TOKEN = "";
string G_NS_FP = "";
string G_NS_LEASE_TMP = "";
int    G_NS_TG_TIMEOUT_MS = 5000;
int    G_NS_ROLE = NS_ROLE_FOLLOWER;
int    G_NS_LOCK = INVALID_HANDLE;
int    G_NS_HB = 0;
int    G_NS_GEN = 0;
bool   G_NS_CLAIM_FROM_STALE = false;
bool   G_NS_PUSH_AVAIL = false;
bool   G_NS_TG_AVAIL = false;
bool   G_NS_TG_PERM = false;
bool   G_NS_TG_PERM_LOGGED = false;
bool   G_NS_TG_SKIP400_LOGGED = false;
bool   G_NS_PUSH_ALERT_DONE = false;
bool   G_NS_QNEXT_LOGGED = false;
bool   G_NS_FAIL_LOGGED = false;
bool   G_NS_429_LOGGED = false;
bool   G_NS_INFLIGHT_HUD = false;
bool   G_NS_FATAL_ALERTED = false;
bool   G_NS_CH_SKIP_LOGGED_P = false;
bool   G_NS_CH_SKIP_LOGGED_T = false;
bool   G_NS_PUSH_UNAVAIL_LOGGED = false;
bool   G_NS_PUSH_BACKOFF_HARD = false;
bool   G_NS_TG_BACKOFF_HARD = false;
string G_NS_OUTAGE_LID = "";
ulong  G_NS_TG_OUTAGE_MS = 0;
ulong  G_NS_PUSH_OUTAGE_MS = 0;
int    G_NS_ERR_BACKOFF_SEC = 5;
ulong  G_NS_TG_BACKOFF_UNTIL = 0;
ulong  G_NS_PUSH_BACKOFF_UNTIL = 0;
ulong  G_NS_PUSH_LAST_MS = 0;
ulong  G_NS_PUSH_TS[8];
int    G_NS_PUSH_N = 0;
int    G_NS_PUSH_ERR_BACKOFF_SEC = 5;
ulong  G_NS_LAST_FAIL_PRINT_MS = 0;
ulong  G_NS_429_LAST_PRINT_MS = 0;
ulong  G_NS_PUSH_PRINT_MS = 0;
ulong  G_NS_PUSH_CHECK_MS = 0;
ulong  G_NS_LEGACY_PRINT_MS = 0;
ulong  G_NS_LAST_LEASE_READ_MS = 0;
ulong  G_NS_CONFIRM_UNTIL_MS = 0;
ulong  G_NS_BACKOFF_UNTIL_MS = 0;
ulong  G_NS_LAST_HB_MS = 0;
string G_NS_OBS_KEY = "";
ulong  G_NS_OBS_MS = 0;
string G_NS_FATAL_KEY = "";
ulong  G_NS_FATAL_SEEN_MS = 0;
long   G_NS_OFF = 0;
string G_NS_FIRST_ID = "";
string G_NS_LID = "";
int    G_NS_P = 0;
int    G_NS_T = 0;

string NotifyCharToStr(const int c);
string NotifyUtf16LeToString(uchar &bytes[], const int start, const int n);
string NotifyBytesToText(uchar &bytes[], const int n);
string NotifyFirstNonEmptyLine(const string raw);
bool   NotifyTokenCharsetOk(const string t);
string NotifyTokenFileExpectedPath();
string NotifyReadTokenFile();
string NotifyHex2(const int c);
string NotifyUrlEncode(const string s);
int    NotifyExtractRetryAfterSec(const string src);
string NotifyAsciiLower(const string s);
bool   NotifyIFind(const string hay, const string needle);
string NotifyExtractMigrateChatId(const string src);
bool   NotifyHttp400IsChatFatal(const string body);
int    FileReadChunk(const int h, uchar &buf[], const int maxn);
uint   NotifyFnv1a32(const string s);
string NotifyHex8u(const uint v);
string NotifyKvGet(const string field, const string key);
int    NotifyParseIntSafe(const string s);
void   NotifySenderLog(const string msg);
void   NotifySenderHud(const string msg);
void   NotifySenderRefreshFp();
bool   NotifyLeaseReadRaw(string &raw);
bool   NotifyLeaseParse(const string raw, string &owner, int &hb, int &gen, string &st, string &fp);
int    NotifyLeaseProbe(string &owner, int &hb, int &gen, string &st, string &fp);
void   NotifyLeaseTmpDelete();
bool   NotifyLeaseWrite(const string owner, const int hb, const int gen, const string st, const string fp);
bool   NotifyLeaseReadNow(string &owner, int &hb, int &gen, string &st, string &fp);
bool   NotifyLeaseReadNowRetry(string &owner, int &hb, int &gen, string &st, string &fp);
bool   NotifyLeaseConfirmOwn();
void   NotifyLegacyGuardRelease();
bool   NotifyLegacyGuardTry();
void   NotifyLeaseYieldToLegacy(const ulong now);
void   NotifyLeaseTmpCleanupOld();
void   NotifyLeaseBecomeFollower();
void   NotifyLeaseLost();
void   NotifyLeaseWriteFatal();
void   NotifyLeaseWriteFree();
void   NotifyOutageResetAll();
void   NotifyOutageNote(const bool is_push);
bool   NotifyOutageAged(const bool is_push);
void   NotifyStateClearMem();
bool   NotifyStateWrite();
bool   NotifyStateReadDisk(long &off, string &qid, string &lid, int &p, int &t, bool &have_s2);
void   NotifyStateLoadAsHolder();
int    QueueOpenRead();
int    LineIdFromBuf(uchar &buf[], const int n, string &id);
string QueueFirstLineId();
int    CountCompleteLines(const int h, const long upto);
bool   QueueAppendBytes(uchar &buf[], const int n);
void   RecoverRotateTail(const long qsize_at_check);
void   MaybeRotateQueue();
bool   BytesToLine(uchar &buf[], const int n, string &out_line, int &line_bytes);
bool   NotifyReadLineAtOffset(const long off, string &line, int &line_bytes, long &qsize);
void   NotifyParseQueueLine(const string field1, string &id, string &ch);
bool   NotifyPushQuotaOk();
void   NotifyPushQuotaNote();
void   NotifyPushRecheck();
bool   NotifyPushReady();
bool   NotifyTgReady();
void   NotifyAdvanceLine(const int line_bytes, const long qsize);
int    NotifySendPushOne(const string text);
int    NotifyTelegramPost(const string text);
void   NotifySenderProcessLine(const bool allow_push, const bool allow_tg);
void   NotifyLeaseFollowerTick();
void   NotifyLeaseConfirmClaim();
void   NotifyLeaseMaybeRenew();
void   NotifyLeaseMachine();
void   NotifySenderInit(const string kind, const int timeout_ms);
void   NotifySenderDeinit();
void   NotifySenderTick(const bool allow_push, const bool allow_tg);

string NotifyCharToStr(const int c)
{
   string ch = " ";
   StringSetCharacter(ch, 0, (ushort)c);
   return ch;
}

string NotifyUtf16LeToString(uchar &bytes[], const int start, const int n)
{
   string out = "";
   for(int i = start; i + 1 < n; i += 2)
   {
      const int c = (int)bytes[i] | ((int)bytes[i + 1] << 8);
      if(c == 0)
         break;
      if(c == 0xFEFF)
         continue;
      out += NotifyCharToStr(c);
   }
   return out;
}

string NotifyBytesToText(uchar &bytes[], const int n)
{
   if(n <= 0)
      return "";
   if(n >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
      return NotifyUtf16LeToString(bytes, 2, n);
   int start = 0;
   if(n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
      start = 3;
   return CharArrayToString(bytes, start, n - start, CP_UTF8);
}

string NotifyFirstNonEmptyLine(const string raw)
{
   string s = raw;
   if(StringLen(s) > 0 && StringGetCharacter(s, 0) == 0xFEFF)
      s = StringSubstr(s, 1);
   StringReplace(s, "\r\n", "\n");
   StringReplace(s, "\r", "\n");
   const int n = StringLen(s);
   string line = "";
   for(int i = 0; i < n; i++)
   {
      const int c = StringGetCharacter(s, i);
      if(c == '\n')
      {
         const string t = NotifyTrim(line);
         if(StringLen(t) > 0)
            return t;
         line = "";
      }
      else
         line += NotifyCharToStr(c);
   }
   return NotifyTrim(line);
}

bool NotifyTokenCharsetOk(const string t)
{
   const int n = StringLen(t);
   if(n <= 0)
      return false;
   for(int i = 0; i < n; i++)
   {
      const int c = StringGetCharacter(t, i);
      const bool ok = ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
                       (c >= 'a' && c <= 'z') || c == ':' || c == '_' || c == '-');
      if(!ok)
         return false;
   }
   return true;
}

string NotifyTokenFileExpectedPath()
{
   return TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + NotifyTrim(I_TG_TOKEN_FILE);
}

string NotifyReadTokenFile()
{
   const string path = NotifyTrim(I_TG_TOKEN_FILE);
   if(StringLen(path) == 0)
      return "";
   ResetLastError();
   const int h = FileOpen(path, FILE_READ|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return "";
   const int n = (int)FileSize(h);
   if(n <= 0)
   {
      FileClose(h);
      return "";
   }
   uchar bytes[];
   ArrayResize(bytes, n);
   for(int i = 0; i < n; i++)
      bytes[i] = (uchar)FileReadInteger(h, CHAR_VALUE);
   FileClose(h);
   return NotifyFirstNonEmptyLine(NotifyBytesToText(bytes, n));
}

string NotifyHex2(const int c)
{
   string hex = "0123456789ABCDEF";
   return StringSubstr(hex, (c >> 4) & 15, 1) + StringSubstr(hex, c & 15, 1);
}

string NotifyUrlEncode(const string s)
{
   uchar bytes[];
   const int n = StringToCharArray(s, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   int last = n;
   if(last > 0 && bytes[last - 1] == 0)
      last--;
   string out = "";
   for(int i = 0; i < last; i++)
   {
      int c = (int)bytes[i];
      if(c < 0)
         c += 256;
      const bool unres = ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
                          (c >= 'a' && c <= 'z') || c == '-' || c == '_' ||
                          c == '.' || c == '~');
      if(unres)
         out += CharToString((uchar)c);
      else
         out += "%" + NotifyHex2(c);
   }
   return out;
}

int NotifyExtractRetryAfterSec(const string src)
{
   int p = StringFind(src, "retry_after");
   if(p < 0)
      p = StringFind(src, "Retry-After");
   if(p < 0)
      return 0;
   const int n = StringLen(src);
   int i = p;
   while(i < n)
   {
      const int c = StringGetCharacter(src, i);
      if(c >= '0' && c <= '9')
         break;
      i++;
   }
   int val = 0;
   int digits = 0;
   while(i < n)
   {
      const int c = StringGetCharacter(src, i);
      if(c < '0' || c > '9')
         break;
      val = val * 10 + (c - '0');
      digits++;
      i++;
      if(digits >= 6)
         break;
   }
   return val;
}

string NotifyAsciiLower(const string s)
{
   string t = s;
   const int n = StringLen(t);
   for(int i = 0; i < n; i++)
   {
      const int c = StringGetCharacter(t, i);
      if(c >= 'A' && c <= 'Z')
         StringSetCharacter(t, i, (ushort)(c + 32));
   }
   return t;
}

bool NotifyIFind(const string hay, const string needle)
{
   return (StringFind(NotifyAsciiLower(hay), NotifyAsciiLower(needle)) >= 0);
}

string NotifyExtractMigrateChatId(const string src)
{
   const string lower = NotifyAsciiLower(src);
   const int p = StringFind(lower, "migrate_to_chat_id");
   if(p < 0)
      return "";
   const int n = StringLen(src);
   int i = p + 18;
   while(i < n)
   {
      const int c = StringGetCharacter(src, i);
      if(c == '-' || (c >= '0' && c <= '9'))
         break;
      i++;
   }
   string out = "";
   if(i < n && StringGetCharacter(src, i) == '-')
   {
      out = "-";
      i++;
   }
   int digits = 0;
   while(i < n)
   {
      const int c = StringGetCharacter(src, i);
      if(c < '0' || c > '9')
         break;
      out += NotifyCharToStr(c);
      digits++;
      i++;
      if(digits >= 20)
         break;
   }
   if(digits <= 0)
      return "";
   return out;
}

bool NotifyHttp400IsChatFatal(const string body)
{
   return (NotifyIFind(body, "chat not found") ||
           NotifyIFind(body, "migrate_to_chat_id") ||
           NotifyIFind(body, "upgraded to a supergroup") ||
           NotifyIFind(body, "chat_id is empty"));
}

int FileReadChunk(const int h, uchar &buf[], const int maxn)
{
   if(maxn <= 0)
      return 0;
   ArrayResize(buf, maxn);
   const int got = (int)FileReadArray(h, buf, 0, maxn);
   if(got <= 0)
   {
      ArrayResize(buf, 0);
      return 0;
   }
   if(got < maxn)
      ArrayResize(buf, got);
   return got;
}

uint NotifyFnv1a32(const string s)
{
   uint h = 2166136261;
   const int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      h = h ^ (uint)StringGetCharacter(s, i);
      h = h * 16777619;
   }
   return h;
}

string NotifyHex8u(const uint v)
{
   return StringFormat("%08X", v);
}

string NotifyKvGet(const string field, const string key)
{
   const string needle = ";" + key + "=";
   int p = StringFind(";" + field, needle);
   if(p < 0)
      return "";
   p = p + StringLen(needle) - 1;
   const int n = StringLen(field);
   string out = "";
   for(int i = p; i < n; i++)
   {
      const int c = StringGetCharacter(field, i);
      if(c == ';')
         break;
      out += NotifyCharToStr(c);
   }
   return out;
}

int NotifyParseIntSafe(const string s)
{
   if(StringLen(s) <= 0)
      return 0;
   return (int)StringToInteger(s);
}

void NotifySenderLog(const string msg)
{
   Print(G_NS_LOG + " " + msg);
}

void NotifySenderHud(const string msg)
{
   Comment(msg);
}

void NotifySenderRefreshFp()
{
   const string chat = NotifyTrim(I_TG_CHAT_ID);
   const string pok = G_NS_PUSH_AVAIL ? "1" : "0";
   G_NS_FP = NotifyHex8u(NotifyFnv1a32(G_NS_TOKEN + "|" + chat + "|" + pok));
}

bool NotifyLeaseReadRaw(string &raw)
{
   raw = "";
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_LEASE_FILE,
                          FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return false;
   raw = FileReadString(h);
   FileClose(h);
   raw = NotifyTrim(raw);
   return (StringLen(raw) > 0);
}

bool NotifyLeaseParse(const string raw, string &owner, int &hb, int &gen, string &st, string &fp)
{
   owner = "";
   hb = 0;
   gen = 0;
   st = "";
   fp = "";
   const string t = NotifyTrim(raw);
   if(StringLen(t) < 3)
      return false;
   if(StringSubstr(t, 0, 3) != "L2;")
      return false;
   owner = NotifyKvGet(t, "owner");
   hb = NotifyParseIntSafe(NotifyKvGet(t, "hb"));
   gen = NotifyParseIntSafe(NotifyKvGet(t, "gen"));
   st = NotifyKvGet(t, "st");
   fp = NotifyKvGet(t, "fp");
   if(StringLen(st) <= 0)
      return false;
   return true;
}

int NotifyLeaseProbe(string &owner, int &hb, int &gen, string &st, string &fp)
{
   owner = "";
   hb = 0;
   gen = 0;
   st = "";
   fp = "";
   if(!FileIsExist(SFX_NOTIFY_LEASE_FILE, FILE_COMMON))
      return NS_LEASE_ABSENT;
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_LEASE_FILE,
                          FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return NS_LEASE_UNREADABLE;
   string raw = FileReadString(h);
   FileClose(h);
   raw = NotifyTrim(raw);
   if(StringLen(raw) <= 0)
      return NS_LEASE_EMPTY;
   if(!NotifyLeaseParse(raw, owner, hb, gen, st, fp))
      return NS_LEASE_UNREADABLE;
   if(st == "FREE" || StringLen(owner) <= 0)
      return NS_LEASE_FREE;
   return NS_LEASE_OK;
}

void NotifyLeaseTmpDelete()
{
   if(StringLen(G_NS_LEASE_TMP) <= 0)
      return;
   FileDelete(G_NS_LEASE_TMP, FILE_COMMON);
}

bool NotifyLeaseWrite(const string owner, const int hb, const int gen, const string st, const string fp)
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(attempt > 0)
         Sleep(50 + (MathRand() % 51));
      ResetLastError();
      const int h = FileOpen(G_NS_LEASE_TMP, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h == INVALID_HANDLE)
         continue;
      FileWriteString(h, StringFormat("L2;owner=%s;hb=%d;gen=%d;st=%s;fp=%s\n",
                                      owner, hb, gen, st, fp));
      FileClose(h);
      if(FileMove(G_NS_LEASE_TMP, FILE_COMMON, SFX_NOTIFY_LEASE_FILE, FILE_COMMON|FILE_REWRITE))
         return true;
      NotifyLeaseTmpDelete();
   }
   return false;
}

bool NotifyLeaseReadNow(string &owner, int &hb, int &gen, string &st, string &fp)
{
   const int kind = NotifyLeaseProbe(owner, hb, gen, st, fp);
   return (kind == NS_LEASE_OK || kind == NS_LEASE_FREE);
}

bool NotifyLeaseReadNowRetry(string &owner, int &hb, int &gen, string &st, string &fp)
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(attempt > 0)
         Sleep(50 + (MathRand() % 51));
      const int kind = NotifyLeaseProbe(owner, hb, gen, st, fp);
      if(kind == NS_LEASE_UNREADABLE)
         continue;
      return (kind == NS_LEASE_OK || kind == NS_LEASE_FREE);
   }
   return false;
}

bool NotifyLeaseConfirmOwn()
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(attempt > 0)
         Sleep(50 + (MathRand() % 51));
      string owner = "";
      int hb = 0;
      int gen = 0;
      string st = "";
      string fp = "";
      const int kind = NotifyLeaseProbe(owner, hb, gen, st, fp);
      if(kind == NS_LEASE_OK)
      {
         if(owner != G_NS_OWNER)
            return false;
         if(st != "RUN" && st != "CLAIM")
            return false;
         G_NS_HB = hb;
         G_NS_GEN = gen;
         return true;
      }
      if(kind != NS_LEASE_UNREADABLE)
         return false;
   }
   return false;
}

void NotifyLegacyGuardRelease()
{
   if(G_NS_LOCK == INVALID_HANDLE)
      return;
   FileClose(G_NS_LOCK);
   G_NS_LOCK = INVALID_HANDLE;
}

bool NotifyLegacyGuardTry()
{
   if(G_NS_LOCK != INVALID_HANDLE)
      return true;
   ResetLastError();
   G_NS_LOCK = FileOpen(SFX_NOTIFY_LOCK_FILE, FILE_WRITE|FILE_BIN|FILE_COMMON);
   return (G_NS_LOCK != INVALID_HANDLE);
}

void NotifyLeaseYieldToLegacy(const ulong now)
{
   if(!NotifyLeaseConfirmOwn())
   {
      G_NS_BACKOFF_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 4001));
      NotifyLeaseBecomeFollower();
      return;
   }
   NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "FREE", G_NS_FP);
   const string hud = "YIELD_TO_LEGACY";
   NotifySenderLog(hud);
   NotifySenderHud(hud);
   G_NS_BACKOFF_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 4001));
   NotifyLeaseBecomeFollower();
}

void NotifyLeaseTmpCleanupOld()
{
   string fname = "";
   const long fh = FileFindFirst("SFX-SYNC-notify-lease.*.tmp", fname, FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   do
   {
      if(StringLen(G_NS_LEASE_TMP) > 0 && fname == G_NS_LEASE_TMP)
         continue;
      const datetime mt = (datetime)FileGetInteger(fname, FILE_MODIFY_DATE, true);
      if(mt > 0 && (TimeLocal() - mt) >= 60)
         FileDelete(fname, FILE_COMMON);
   }
   while(FileFindNext(fh, fname));
   FileFindClose(fh);
}

void NotifyOutageResetAll()
{
   G_NS_OUTAGE_LID = "";
   G_NS_TG_OUTAGE_MS = 0;
   G_NS_PUSH_OUTAGE_MS = 0;
}

void NotifyOutageNote(const bool is_push)
{
   const ulong now = NowMs();
   if(is_push)
   {
      if(G_NS_PUSH_OUTAGE_MS == 0)
         G_NS_PUSH_OUTAGE_MS = now;
   }
   else if(G_NS_TG_OUTAGE_MS == 0)
      G_NS_TG_OUTAGE_MS = now;
}

bool NotifyOutageAged(const bool is_push)
{
   const ulong start = is_push ? G_NS_PUSH_OUTAGE_MS : G_NS_TG_OUTAGE_MS;
   if(start == 0)
      return false;
   return ((NowMs() - start) >= (ulong)NS_OUTAGE_SKIP_SEC * 1000);
}

void NotifyLeaseBecomeFollower()
{
   NotifyLegacyGuardRelease();
   NotifyStateClearMem();
   G_NS_ROLE = NS_ROLE_FOLLOWER;
   G_NS_CLAIM_FROM_STALE = false;
   G_NS_CONFIRM_UNTIL_MS = 0;
}

void NotifyLeaseLost()
{
   NotifySenderLog("LEASE_LOST");
   NotifyLeaseBecomeFollower();
}

void NotifyLeaseWriteFatal()
{
   if(!NotifyLeaseConfirmOwn())
   {
      NotifyLeaseLost();
      return;
   }
   NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "FATAL", G_NS_FP);
   NotifyLegacyGuardRelease();
   NotifyStateClearMem();
   G_NS_ROLE = NS_ROLE_DEAD;
   if(!G_NS_FATAL_ALERTED)
   {
      const string msg = "NOTIFY sender FATAL (no usable channel) - fix config and re-attach";
      NotifySenderLog(msg);
      Alert(G_NS_LOG + " " + msg);
      NotifySenderHud(msg);
      G_NS_FATAL_ALERTED = true;
   }
}

void NotifyLeaseWriteFree()
{
   if(!NotifyLeaseConfirmOwn())
      return;
   NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "FREE", G_NS_FP);
}

void NotifyStateClearMem()
{
   G_NS_OFF = 0;
   G_NS_FIRST_ID = "";
   G_NS_LID = "";
   G_NS_P = 0;
   G_NS_T = 0;
}

bool NotifyStateWrite()
{
   if(!NotifyLeaseConfirmOwn())
   {
      NotifyLeaseLost();
      return false;
   }
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(attempt > 0)
         Sleep(50 + (MathRand() % 51));
      ResetLastError();
      const int h = FileOpen(SFX_NOTIFY_STATE_TMP, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h == INVALID_HANDLE)
         continue;
      FileWriteString(h, StringFormat("%I64d\t%s\n", G_NS_OFF, G_NS_FIRST_ID));
      FileWriteString(h, StringFormat("S2;lid=%s;p=%d;t=%d;own=%s\n",
                                      G_NS_LID, G_NS_P, G_NS_T, G_NS_OWNER));
      FileClose(h);
      if(FileMove(SFX_NOTIFY_STATE_TMP, FILE_COMMON, SFX_NOTIFY_STATE_FILE, FILE_COMMON|FILE_REWRITE))
         return true;
      FileDelete(SFX_NOTIFY_STATE_TMP, FILE_COMMON);
   }
   NotifySenderLog("offset/state save failed");
   return false;
}

bool NotifyStateReadDisk(long &off, string &qid, string &lid, int &p, int &t, bool &have_s2)
{
   off = 0;
   qid = "";
   lid = "";
   p = 0;
   t = 0;
   have_s2 = false;
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_STATE_FILE, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;
   const string l1 = NotifyTrim(FileReadString(h));
   string l2 = "";
   if(!FileIsEnding(h))
      l2 = NotifyTrim(FileReadString(h));
   FileClose(h);
   if(StringLen(l1) <= 0)
      return false;
   int tab = StringFind(l1, "\t");
   string num = l1;
   if(tab >= 0)
   {
      num = StringSubstr(l1, 0, tab);
      qid = NotifyTrim(StringSubstr(l1, tab + 1));
   }
   if(StringLen(num) <= 0)
      return false;
   for(int i = 0; i < StringLen(num); i++)
   {
      const int c = StringGetCharacter(num, i);
      if(c < '0' || c > '9')
         return false;
   }
   off = StringToInteger(num);
   if(off < 0)
      return false;
   if(StringLen(l2) >= 3 && StringSubstr(l2, 0, 3) == "S2;")
   {
      have_s2 = true;
      lid = NotifyKvGet(l2, "lid");
      p = NotifyParseIntSafe(NotifyKvGet(l2, "p"));
      t = NotifyParseIntSafe(NotifyKvGet(l2, "t"));
   }
   return true;
}

void NotifyStateLoadAsHolder()
{
   NotifyOutageResetAll();
   const bool have_state = FileIsExist(SFX_NOTIFY_STATE_FILE, FILE_COMMON);
   const bool have_tmp = FileIsExist(SFX_NOTIFY_STATE_TMP, FILE_COMMON);
   if(!have_state && !have_tmp)
   {
      const int qh = QueueOpenRead();
      long qsize = 0;
      if(qh != INVALID_HANDLE)
         qsize = (long)FileSize(qh);
      int skipped = 0;
      if(qh != INVALID_HANDLE)
         skipped = CountCompleteLines(qh, qsize);
      G_NS_OFF = qsize;
      G_NS_FIRST_ID = "";
      G_NS_LID = "";
      G_NS_P = 0;
      G_NS_T = 0;
      if(qh != INVALID_HANDLE)
      {
         FileSeek(qh, 0, SEEK_SET);
         uchar buf[];
         const int got = FileReadChunk(qh, buf, SFX_NOTIFY_READ_CHUNK);
         if(got > 0)
            LineIdFromBuf(buf, got, G_NS_FIRST_ID);
         FileClose(qh);
      }
      NotifyStateWrite();
      NotifySenderLog(StringFormat("first attach (no state): skipped %d existing queue line(s), offset=%I64d",
                                   skipped, G_NS_OFF));
      return;
   }

   long off = 0;
   string qid = "";
   string lid = "";
   int p = 0;
   int t = 0;
   bool have_s2 = false;
   bool parsed = NotifyStateReadDisk(off, qid, lid, p, t, have_s2);
   if(!parsed && have_tmp)
   {
      ResetLastError();
      const int th = FileOpen(SFX_NOTIFY_STATE_TMP, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(th != INVALID_HANDLE)
      {
         const string l1 = NotifyTrim(FileReadString(th));
         FileClose(th);
         int tab = StringFind(l1, "\t");
         string num = l1;
         if(tab >= 0)
         {
            num = StringSubstr(l1, 0, tab);
            qid = NotifyTrim(StringSubstr(l1, tab + 1));
         }
         bool ok = true;
         for(int i = 0; i < StringLen(num); i++)
         {
            const int c = StringGetCharacter(num, i);
            if(c < '0' || c > '9')
               ok = false;
         }
         if(ok && StringLen(num) > 0)
         {
            off = StringToInteger(num);
            parsed = true;
            have_s2 = false;
         }
      }
   }
   if(!parsed)
   {
      const int qh = QueueOpenRead();
      long qsize = 0;
      if(qh != INVALID_HANDLE)
         qsize = (long)FileSize(qh);
      G_NS_OFF = qsize;
      G_NS_FIRST_ID = "";
      G_NS_LID = "";
      G_NS_P = 0;
      G_NS_T = 0;
      if(qh != INVALID_HANDLE)
         FileClose(qh);
      NotifyStateWrite();
      NotifySenderLog("unreadable state: skipped backlog");
      return;
   }

   G_NS_OFF = off;
   G_NS_FIRST_ID = qid;
   if(have_s2)
   {
      G_NS_LID = lid;
      G_NS_P = p;
      G_NS_T = t;
   }
   else
   {
      G_NS_LID = "";
      G_NS_P = 2;
      G_NS_T = 0;
   }

   const string now_raw = QueueFirstLineId();
   string now_parsed = "";
   string now_ch = "";
   NotifyParseQueueLine(now_raw, now_parsed, now_ch);
   const int qh_now = QueueOpenRead();
   long qsize_now = 0;
   if(qh_now != INVALID_HANDLE)
   {
      qsize_now = (long)FileSize(qh_now);
      FileClose(qh_now);
   }
   if(qsize_now > 0 && qsize_now < G_NS_OFF)
   {
      G_NS_OFF = 0;
      G_NS_FIRST_ID = now_raw;
      G_NS_LID = "";
      G_NS_P = 0;
      G_NS_T = 0;
      NotifyStateWrite();
      NotifySenderLog("queue smaller than saved offset - reset offset to 0");
      return;
   }
   const bool match_raw = (G_NS_FIRST_ID == now_raw);
   const bool match_parsed = (StringLen(now_parsed) > 0 && G_NS_FIRST_ID == now_parsed);
   if(StringLen(G_NS_FIRST_ID) > 0 && StringLen(now_raw) > 0 && !match_raw && !match_parsed)
   {
      G_NS_OFF = 0;
      G_NS_FIRST_ID = now_raw;
      G_NS_LID = "";
      G_NS_P = 0;
      G_NS_T = 0;
      NotifyStateWrite();
      NotifySenderLog("queue first-line id changed - reset offset to 0");
   }
   else if(match_parsed && !match_raw && StringLen(now_raw) > 0)
   {
      G_NS_FIRST_ID = now_raw;
      NotifyStateWrite();
   }
}

int QueueOpenRead()
{
   ResetLastError();
   return FileOpen(SFX_NOTIFY_QUEUE_FILE,
                   FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
}

int LineIdFromBuf(uchar &buf[], const int n, string &id)
{
   int nl = -1;
   for(int i = 0; i < n; i++)
   {
      if((int)buf[i] == '\n')
      {
         nl = i;
         break;
      }
   }
   if(nl < 0)
      return 0;
   int end = nl;
   if(end > 0 && (int)buf[end - 1] == '\r')
      end--;
   string line = "";
   for(int j = 0; j < end; j++)
      line += NotifyCharToStr((int)buf[j]);
   line = NotifyTrim(line);
   const int tab = StringFind(line, "\t");
   if(tab <= 0)
      id = line;
   else
      id = StringSubstr(line, 0, tab);
   return (nl + 1);
}

string QueueFirstLineId()
{
   const int h = QueueOpenRead();
   if(h == INVALID_HANDLE)
      return "";
   uchar buf[];
   const int got = FileReadChunk(h, buf, SFX_NOTIFY_READ_CHUNK);
   FileClose(h);
   string id = "";
   if(got > 0)
      LineIdFromBuf(buf, got, id);
   return id;
}

int CountCompleteLines(const int h, const long upto)
{
   int n = 0;
   FileSeek(h, 0, SEEK_SET);
   long pos = 0;
   uchar buf[];
   while(pos < upto)
   {
      int want = SFX_NOTIFY_READ_CHUNK;
      if((long)want > (upto - pos))
         want = (int)(upto - pos);
      const int got = FileReadChunk(h, buf, want);
      if(got <= 0)
         break;
      for(int i = 0; i < got; i++)
      {
         if((int)buf[i] == '\n')
            n++;
      }
      pos += got;
   }
   return n;
}

bool QueueAppendBytes(uchar &buf[], const int n)
{
   if(n <= 0)
      return true;
   ResetLastError();
   int h = FileOpen(SFX_NOTIFY_QUEUE_FILE,
                    FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
   {
      ResetLastError();
      h = FileOpen(SFX_NOTIFY_QUEUE_FILE,
                   FILE_WRITE|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   }
   if(h == INVALID_HANDLE)
      return false;
   FileSeek(h, 0, SEEK_END);
   FileWriteArray(h, buf, 0, n);
   FileClose(h);
   return true;
}

void RecoverRotateTail(const long qsize_at_check)
{
   ResetLastError();
   const int oh = FileOpen(SFX_NOTIFY_QUEUE_OLD,
                           FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(oh == INVALID_HANDLE)
      return;
   const long oldsize = (long)FileSize(oh);
   if(oldsize <= qsize_at_check)
   {
      FileClose(oh);
      return;
   }
   FileSeek(oh, qsize_at_check, SEEK_SET);
   long remain = oldsize - qsize_at_check;
   uchar leftover[];
   int leftover_n = 0;
   while(remain > 0)
   {
      int want = SFX_NOTIFY_READ_CHUNK;
      if((long)want > remain)
         want = (int)remain;
      uchar chunk[];
      const int got = FileReadChunk(oh, chunk, want);
      if(got <= 0)
         break;
      remain -= got;
      uchar merged[];
      ArrayResize(merged, leftover_n + got);
      for(int i = 0; i < leftover_n; i++)
         merged[i] = leftover[i];
      for(int j = 0; j < got; j++)
         merged[leftover_n + j] = chunk[j];
      const int total = leftover_n + got;
      int last_nl = -1;
      for(int k = 0; k < total; k++)
      {
         if((int)merged[k] == '\n')
            last_nl = k;
      }
      if(last_nl >= 0)
      {
         uchar complete[];
         ArrayResize(complete, last_nl + 1);
         for(int c = 0; c <= last_nl; c++)
            complete[c] = merged[c];
         if(!QueueAppendBytes(complete, last_nl + 1))
            NotifySenderLog("rotate tail append failed");
         leftover_n = total - (last_nl + 1);
         ArrayResize(leftover, leftover_n);
         for(int r = 0; r < leftover_n; r++)
            leftover[r] = merged[last_nl + 1 + r];
      }
      else
      {
         leftover_n = total;
         ArrayResize(leftover, leftover_n);
         for(int r = 0; r < leftover_n; r++)
            leftover[r] = merged[r];
      }
   }
   FileClose(oh);
   if(leftover_n > 0)
      NotifySenderLog(StringFormat("rotate tail dropped %d leftover byte(s) without trailing newline", leftover_n));
}

void MaybeRotateQueue()
{
   if(!NotifyLeaseConfirmOwn())
   {
      NotifyLeaseLost();
      return;
   }
   const int rh = QueueOpenRead();
   if(rh == INVALID_HANDLE)
      return;
   const long qsize = (long)FileSize(rh);
   FileClose(rh);
   if(G_NS_OFF < qsize)
      return;
   if(qsize < SFX_NOTIFY_ROTATE_BYTES)
      return;
   ResetLastError();
   FileDelete(SFX_NOTIFY_QUEUE_OLD, FILE_COMMON);
   if(!FileMove(SFX_NOTIFY_QUEUE_FILE, FILE_COMMON, SFX_NOTIFY_QUEUE_OLD, FILE_COMMON))
      return;
   RecoverRotateTail(qsize);
   G_NS_OFF = 0;
   G_NS_FIRST_ID = QueueFirstLineId();
   G_NS_LID = "";
   G_NS_P = 0;
   G_NS_T = 0;
   NotifyStateWrite();
   NotifySenderLog("rotated queue file to SFX-SYNC-notify-queue.txt.old");
}

bool BytesToLine(uchar &buf[], const int n, string &out_line, int &line_bytes)
{
   int nl = -1;
   for(int i = 0; i < n; i++)
   {
      if((int)buf[i] == '\n')
      {
         nl = i;
         break;
      }
   }
   if(nl < 0)
      return false;
   line_bytes = nl + 1;
   int end = nl;
   if(end > 0 && (int)buf[end - 1] == '\r')
      end--;
   out_line = "";
   for(int j = 0; j < end; j++)
      out_line += NotifyCharToStr((int)buf[j]);
   return true;
}

bool NotifyReadLineAtOffset(const long off, string &line, int &line_bytes, long &qsize)
{
   line = "";
   line_bytes = 0;
   qsize = 0;
   const int h = QueueOpenRead();
   if(h == INVALID_HANDLE)
      return false;
   qsize = (long)FileSize(h);
   if(qsize < off)
   {
      FileClose(h);
      return false;
   }
   const long remain_all = qsize - off;
   if(remain_all <= 0)
   {
      FileClose(h);
      return false;
   }
   FileSeek(h, off, SEEK_SET);
   uchar buf[];
   int have = 0;
   long still = remain_all;
   bool have_line = false;
   while(still > 0 && !have_line)
   {
      int want = SFX_NOTIFY_READ_CHUNK;
      if((long)want > still)
         want = (int)still;
      uchar chunk[];
      const int got = FileReadChunk(h, chunk, want);
      if(got <= 0)
         break;
      still -= got;
      uchar merged[];
      ArrayResize(merged, have + got);
      for(int i = 0; i < have; i++)
         merged[i] = buf[i];
      for(int j = 0; j < got; j++)
         merged[have + j] = chunk[j];
      have += got;
      ArrayResize(buf, have);
      for(int k = 0; k < have; k++)
         buf[k] = merged[k];
      have_line = BytesToLine(buf, have, line, line_bytes);
   }
   FileClose(h);
   return have_line;
}

void NotifyParseQueueLine(const string field1, string &id, string &ch)
{
   id = "";
   ch = "T";
   const string f = NotifyTrim(field1);
   if(StringLen(f) <= 0)
      return;
   const int c0 = StringGetCharacter(f, 0);
   if(c0 == 'Q' && StringLen(f) >= 3)
   {
      int i = 1;
      int ver = 0;
      bool digits = false;
      while(i < StringLen(f))
      {
         const int c = StringGetCharacter(f, i);
         if(c < '0' || c > '9')
            break;
         ver = ver * 10 + (c - '0');
         digits = true;
         i++;
      }
      if(digits && i < StringLen(f) && StringGetCharacter(f, i) == ';')
      {
         if(ver > 2 && !G_NS_QNEXT_LOGGED)
         {
            NotifySenderLog(StringFormat("queue line Q%d; treating unknown newer format (ch if present)", ver));
            G_NS_QNEXT_LOGGED = true;
         }
         string rest = StringSubstr(f, i + 1);
         const int sc = StringFind(rest, ";");
         if(sc < 0)
            id = rest;
         else
         {
            id = StringSubstr(rest, 0, sc);
            const string kv = StringSubstr(rest, sc + 1);
            const string chv = NotifyKvGet("x;" + kv, "ch");
            if(chv == "P" || chv == "T" || chv == "B")
               ch = chv;
         }
         return;
      }
   }
   id = f;
   ch = "T";
}

bool NotifyPushQuotaOk()
{
   const ulong now = NowMs();
   if(G_NS_PUSH_LAST_MS != 0 && now >= G_NS_PUSH_LAST_MS && (now - G_NS_PUSH_LAST_MS) < 1000)
      return false;
   int n = 0;
   for(int i = 0; i < G_NS_PUSH_N; i++)
   {
      if(now >= G_NS_PUSH_TS[i] && (now - G_NS_PUSH_TS[i]) < 60000)
         n++;
   }
   if(n >= 8)
      return false;
   return true;
}

void NotifyPushQuotaNote()
{
   const ulong now = NowMs();
   G_NS_PUSH_LAST_MS = now;
   if(G_NS_PUSH_N < 8)
   {
      G_NS_PUSH_TS[G_NS_PUSH_N] = now;
      G_NS_PUSH_N++;
      return;
   }
   for(int i = 1; i < 8; i++)
      G_NS_PUSH_TS[i - 1] = G_NS_PUSH_TS[i];
   G_NS_PUSH_TS[7] = now;
}

void NotifyPushRecheck()
{
   const ulong now = NowMs();
   if(G_NS_PUSH_CHECK_MS != 0 && (now - G_NS_PUSH_CHECK_MS) < 60000)
      return;
   G_NS_PUSH_CHECK_MS = now;
   const bool en = (MQLInfoInteger(MQL_TESTER) == 0 &&
                    TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED) != 0);
   if(en != G_NS_PUSH_AVAIL)
   {
      G_NS_PUSH_AVAIL = en;
      NotifySenderRefreshFp();
      if(!en)
      {
         if(!G_NS_PUSH_UNAVAIL_LOGGED)
         {
            NotifySenderLog("MT Push WRONG_SETTINGS / Notifications OFF");
            G_NS_PUSH_UNAVAIL_LOGGED = true;
         }
      }
      else
         G_NS_PUSH_UNAVAIL_LOGGED = false;
   }
}

bool NotifyPushReady()
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return false;
   if(!G_NS_PUSH_AVAIL)
      return false;
   if(G_NS_PUSH_BACKOFF_UNTIL > 0 && NowMs() < G_NS_PUSH_BACKOFF_UNTIL)
      return false;
   if(!NotifyPushQuotaOk())
      return false;
   return true;
}

bool NotifyTgReady()
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return false;
   const string token = G_NS_TOKEN;
   const string chat = NotifyTrim(I_TG_CHAT_ID);
   if(StringLen(token) == 0 || StringLen(chat) == 0 || G_NS_TG_PERM || !G_NS_TG_AVAIL)
      return false;
   if(G_NS_TG_BACKOFF_UNTIL > 0 && NowMs() < G_NS_TG_BACKOFF_UNTIL)
      return false;
   if(!NotifySenderTgBudgetOk())
      return false;
   return true;
}

void NotifyAdvanceLine(const int line_bytes, const long qsize)
{
   G_NS_OFF += line_bytes;
   G_NS_P = 0;
   G_NS_T = 0;
   G_NS_LID = "";
   if(StringLen(G_NS_FIRST_ID) <= 0 && G_NS_OFF > 0)
      G_NS_FIRST_ID = QueueFirstLineId();
   NotifyStateWrite();
   if(G_NS_OFF >= qsize)
      MaybeRotateQueue();
}

int NotifySendPushOne(const string text)
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return 0;
   if(!G_NS_PUSH_AVAIL)
      return -1;
   if(G_NS_PUSH_BACKOFF_UNTIL > 0 && NowMs() < G_NS_PUSH_BACKOFF_UNTIL)
      return 0;
   if(!NotifyPushQuotaOk())
      return 0;
   ResetLastError();
   if(!SendNotification(text))
   {
      const int err = GetLastError();
      if(err == 4518 || err == 4253)
      {
         G_NS_PUSH_BACKOFF_UNTIL = NowMs() + 60000;
         G_NS_PUSH_BACKOFF_HARD = true;
         NotifySenderLog("MT Push TOO_FREQUENT backoff 60 s");
         return 0;
      }
      if(err == 4517 || err == 4252)
      {
         G_NS_PUSH_AVAIL = false;
         NotifySenderRefreshFp();
         return -1;
      }
      if(err == 4516 || err == 4251)
      {
         NotifySenderLog(StringFormat("MT Push WRONG_PARAMETER err=%d - skipping channel", err));
         return 2;
      }
      G_NS_PUSH_BACKOFF_UNTIL = NowMs() + (ulong)G_NS_PUSH_ERR_BACKOFF_SEC * 1000;
      G_NS_PUSH_BACKOFF_HARD = false;
      if(G_NS_PUSH_ERR_BACKOFF_SEC < SFX_NOTIFY_TG_RETRY_MAX_SEC)
      {
         G_NS_PUSH_ERR_BACKOFF_SEC *= 2;
         if(G_NS_PUSH_ERR_BACKOFF_SEC > SFX_NOTIFY_TG_RETRY_MAX_SEC)
            G_NS_PUSH_ERR_BACKOFF_SEC = SFX_NOTIFY_TG_RETRY_MAX_SEC;
      }
      NotifySenderLog(StringFormat("MT Push SEND_FAILED err=%d", err));
      return 0;
   }
   G_NS_PUSH_ERR_BACKOFF_SEC = 5;
   G_NS_PUSH_BACKOFF_UNTIL = 0;
   G_NS_PUSH_BACKOFF_HARD = false;
   NotifyPushQuotaNote();
   return 1;
}

int NotifyTelegramPost(const string text)
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return 0;
   const string token = G_NS_TOKEN;
   const string chat = NotifyTrim(I_TG_CHAT_ID);
   if(StringLen(token) == 0 || StringLen(chat) == 0 || G_NS_TG_PERM || !G_NS_TG_AVAIL)
      return -2;
   if(G_NS_TG_BACKOFF_UNTIL > 0 && NowMs() < G_NS_TG_BACKOFF_UNTIL)
      return -1;
   const string url = "https://api.telegram.org/bot" + token + "/sendMessage";
   const string body = "chat_id=" + NotifyUrlEncode(chat) + "&text=" + NotifyUrlEncode(text);
   const string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   char postData[];
   char resultData[];
   string resultHeaders;
   StringToCharArray(body, postData, 0, StringLen(body));
   if(!NotifySenderTgBudgetOk())
      return 3;
   ResetLastError();
   const int http = WebRequest("POST", url, headers, G_NS_TG_TIMEOUT_MS, postData, resultData, resultHeaders);
   const int err = GetLastError();
   if(http == 400)
   {
      const string resp = CharArrayToString(resultData);
      if(NotifyHttp400IsChatFatal(resp))
      {
         if(!G_NS_TG_PERM_LOGGED)
         {
            const string mig = NotifyExtractMigrateChatId(resp);
            string warn = G_NS_LOG + " Telegram HTTP 400 chat/config error - Telegram disabled until reinit";
            if(StringLen(mig) > 0)
               warn += ". New chat id from migrate_to_chat_id: " + mig;
            Print(warn);
            Alert(warn);
            G_NS_TG_PERM_LOGGED = true;
         }
         G_NS_TG_PERM = true;
         G_NS_TG_AVAIL = false;
         return -2;
      }
      const string skip = G_NS_LOG + " Telegram HTTP 400 - skipping this line";
      Print(skip);
      if(!G_NS_TG_SKIP400_LOGGED)
      {
         Alert(skip);
         G_NS_TG_SKIP400_LOGGED = true;
      }
      return 2;
   }
   if(http == 401 || http == 403 || http == 404)
   {
      if(!G_NS_TG_PERM_LOGGED)
      {
         const string warn = StringFormat(
            "%s Telegram permanent HTTP %d - Telegram disabled until reinit. Revoke and replace the bot token if this is 401.",
            G_NS_LOG, http);
         Print(warn);
         Alert(warn);
         G_NS_TG_PERM_LOGGED = true;
      }
      G_NS_TG_PERM = true;
      G_NS_TG_AVAIL = false;
      return -2;
   }
   if(http == 429)
   {
      int sec = NotifyExtractRetryAfterSec(resultHeaders);
      if(sec <= 0)
         sec = NotifyExtractRetryAfterSec(CharArrayToString(resultData));
      if(sec <= 0)
         sec = SFX_NOTIFY_TG_BACKOFF_DEFAULT_SEC;
      if(sec > SFX_NOTIFY_TG_RETRY_MAX_SEC)
         sec = SFX_NOTIFY_TG_RETRY_MAX_SEC;
      G_NS_TG_BACKOFF_UNTIL = NowMs() + (ulong)sec * 1000;
      G_NS_TG_BACKOFF_HARD = true;
      const ulong now429 = NowMs();
      if(!G_NS_429_LOGGED || (G_NS_429_LAST_PRINT_MS > 0 && (now429 - G_NS_429_LAST_PRINT_MS) >= (ulong)SFX_NOTIFY_FAIL_PRINT_MS))
      {
         NotifySenderLog(StringFormat("Telegram HTTP 429 backoff %d s (kept, not dropped)", sec));
         G_NS_429_LOGGED = true;
         G_NS_429_LAST_PRINT_MS = now429;
      }
      return -1;
   }
   if(http == -1 || http == 4014 || http == 4060 || http != 200)
   {
      const ulong now = NowMs();
      if(!G_NS_FAIL_LOGGED || (G_NS_LAST_FAIL_PRINT_MS > 0 && (now - G_NS_LAST_FAIL_PRINT_MS) >= (ulong)SFX_NOTIFY_FAIL_PRINT_MS))
      {
         NotifySenderLog(StringFormat("Telegram send failed http=%d err=%d (allow https://api.telegram.org)", http, err));
         G_NS_FAIL_LOGGED = true;
         G_NS_LAST_FAIL_PRINT_MS = now;
      }
      G_NS_TG_BACKOFF_UNTIL = NowMs() + (ulong)G_NS_ERR_BACKOFF_SEC * 1000;
      G_NS_TG_BACKOFF_HARD = false;
      if(G_NS_ERR_BACKOFF_SEC < SFX_NOTIFY_TG_RETRY_MAX_SEC)
      {
         G_NS_ERR_BACKOFF_SEC *= 2;
         if(G_NS_ERR_BACKOFF_SEC > SFX_NOTIFY_TG_RETRY_MAX_SEC)
            G_NS_ERR_BACKOFF_SEC = SFX_NOTIFY_TG_RETRY_MAX_SEC;
      }
      return -1;
   }
   G_NS_FAIL_LOGGED = false;
   G_NS_429_LOGGED = false;
   G_NS_ERR_BACKOFF_SEC = 5;
   G_NS_TG_BACKOFF_UNTIL = 0;
   G_NS_TG_BACKOFF_HARD = false;
   return 1;
}

void NotifySenderProcessLine(const bool allow_push, const bool allow_tg)
{
   if(G_NS_ROLE != NS_ROLE_HOLDER)
      return;
   if(!NotifyLeaseConfirmOwn())
   {
      NotifyLeaseLost();
      return;
   }

   string line = "";
   int line_bytes = 0;
   long qsize = 0;
   if(!NotifyReadLineAtOffset(G_NS_OFF, line, line_bytes, qsize))
   {
      if(qsize < G_NS_OFF)
      {
         G_NS_OFF = 0;
         G_NS_FIRST_ID = QueueFirstLineId();
         G_NS_LID = "";
         G_NS_P = 0;
         G_NS_T = 0;
         NotifyStateWrite();
         NotifySenderLog("queue smaller than saved offset - reset offset to 0");
         return;
      }
      MaybeRotateQueue();
      return;
   }

   const string trimmed = NotifyTrim(line);
   if(StringLen(trimmed) <= 0)
   {
      G_NS_OFF += line_bytes;
      G_NS_LID = "";
      G_NS_P = 0;
      G_NS_T = 0;
      if(StringLen(G_NS_FIRST_ID) <= 0 && G_NS_OFF > 0)
         G_NS_FIRST_ID = QueueFirstLineId();
      NotifyStateWrite();
      return;
   }
   const int tab = StringFind(trimmed, "\t");
   if(tab <= 0)
   {
      G_NS_OFF += line_bytes;
      G_NS_LID = "";
      G_NS_P = 0;
      G_NS_T = 0;
      if(StringLen(G_NS_FIRST_ID) <= 0 && G_NS_OFF > 0)
         G_NS_FIRST_ID = QueueFirstLineId();
      NotifyStateWrite();
      return;
   }

   const string field1 = StringSubstr(trimmed, 0, tab);
   const string text = StringSubstr(trimmed, tab + 1);
   string qid = "";
   string ch = "T";
   NotifyParseQueueLine(field1, qid, ch);

   if(StringLen(G_NS_LID) > 0 && G_NS_LID != qid)
   {
      G_NS_P = 0;
      G_NS_T = 0;
   }
   G_NS_LID = qid;

   if(G_NS_P == 1)
   {
      G_NS_P = 2;
      const string hudp = StringFormat("NOTIFY_INFLIGHT_UNCONFIRMED id=%s ch=P", G_NS_LID);
      NotifySenderLog(hudp);
      NotifySenderHud(hudp);
      G_NS_INFLIGHT_HUD = true;
      if(!NotifyStateWrite())
         return;
   }
   if(G_NS_T == 1)
   {
      G_NS_T = 2;
      const string hud = StringFormat("NOTIFY_INFLIGHT_UNCONFIRMED id=%s ch=T", G_NS_LID);
      NotifySenderLog(hud);
      NotifySenderHud(hud);
      G_NS_INFLIGHT_HUD = true;
      if(!NotifyStateWrite())
         return;
      NotifyAdvanceLine(line_bytes, qsize);
      return;
   }

   const bool wantP = (ch == "P" || ch == "B");
   const bool wantT = (ch == "T" || ch == "B");
   bool canP = G_NS_PUSH_AVAIL;
   bool canT = (G_NS_TG_AVAIL && !G_NS_TG_PERM);
   if(!canP && !canT)
   {
      NotifyLeaseWriteFatal();
      return;
   }
   if(wantP && G_NS_P != 2 && !canP)
   {
      G_NS_P = 2;
      const string warn = "MT Push requested by queue but this sender terminal has no MetaQuotes ID / Notifications OFF (Tools > Options > Notifications)";
      if(!G_NS_PUSH_UNAVAIL_LOGGED)
      {
         NotifySenderLog(warn);
         G_NS_PUSH_UNAVAIL_LOGGED = true;
      }
      if(!G_NS_PUSH_ALERT_DONE)
      {
         Alert(G_NS_LOG + " " + warn);
         G_NS_PUSH_ALERT_DONE = true;
      }
      if(!NotifyStateWrite())
         return;
   }
   if(wantT && G_NS_T != 2 && !canT)
   {
      G_NS_T = 2;
      if(!G_NS_CH_SKIP_LOGGED_T)
      {
         NotifySenderLog("Telegram unusable - skipping channel");
         G_NS_CH_SKIP_LOGGED_T = true;
      }
      if(!NotifyStateWrite())
         return;
   }

   if(wantP && G_NS_P == 0 && canP)
   {
      if(!allow_push)
         return;
      const ulong nowp = NowMs();
      const bool quota_block = !NotifyPushQuotaOk();
      const bool push_backoff = (G_NS_PUSH_BACKOFF_UNTIL > 0 && nowp < G_NS_PUSH_BACKOFF_UNTIL);
      const bool hard_wait = (quota_block || (push_backoff && G_NS_PUSH_BACKOFF_HARD));
      if(hard_wait)
      {
         NotifyOutageNote(true);
         return;
      }
      if(push_backoff)
      {
         NotifyOutageNote(true);
         if(!NotifyOutageAged(true))
            return;
         G_NS_PUSH_BACKOFF_UNTIL = 0;
      }
      if(!NotifyPushReady())
         return;
      G_NS_P = 1;
      if(!NotifyStateWrite())
      {
         G_NS_P = 0;
         return;
      }
      const int rc = NotifySendPushOne(text);
      if(rc == 1)
      {
         G_NS_P = 2;
         G_NS_PUSH_OUTAGE_MS = 0;
         if(!NotifyStateWrite())
            return;
      }
      else if(rc == 2)
      {
         G_NS_P = 2;
         if(!NotifyStateWrite())
            return;
      }
      else if(rc == -1)
      {
         G_NS_P = 2;
         canP = G_NS_PUSH_AVAIL;
         canT = (G_NS_TG_AVAIL && !G_NS_TG_PERM);
         if(!G_NS_PUSH_UNAVAIL_LOGGED)
         {
            NotifySenderLog("MT Push unavailable - skipping channel");
            G_NS_PUSH_UNAVAIL_LOGGED = true;
         }
         if(!NotifyStateWrite())
            return;
         if(!canP && !canT)
         {
            NotifyLeaseWriteFatal();
            return;
         }
      }
      else
      {
         NotifyOutageNote(true);
         G_NS_P = 0;
         NotifyStateWrite();
         if(G_NS_PUSH_BACKOFF_HARD)
            return;
         if(NotifyOutageAged(true))
         {
            G_NS_P = 2;
            const string skipp = StringFormat("PUSH_SKIPPED_OUTAGE id=%s", G_NS_LID);
            NotifySenderLog(skipp);
            NotifySenderHud(skipp);
            if(!NotifyStateWrite())
               return;
         }
         else
            return;
      }
   }

   if(wantT && G_NS_T == 0 && canT)
   {
      if(!allow_tg)
         return;
      const ulong nowt = NowMs();
      const bool tg_backoff = (G_NS_TG_BACKOFF_UNTIL > 0 && nowt < G_NS_TG_BACKOFF_UNTIL);
      const bool hard_wait = (tg_backoff && G_NS_TG_BACKOFF_HARD);
      if(hard_wait)
      {
         NotifyOutageNote(false);
         return;
      }
      if(tg_backoff)
      {
         NotifyOutageNote(false);
         if(!NotifyOutageAged(false))
            return;
         G_NS_TG_BACKOFF_UNTIL = 0;
      }
      if(!NotifyTgReady())
         return;
      G_NS_T = 1;
      if(!NotifyStateWrite())
      {
         G_NS_T = 0;
         return;
      }
      const int rc = NotifyTelegramPost(text);
      if(rc == 3)
      {
         G_NS_T = 0;
         NotifyStateWrite();
         return;
      }
      if(rc == 1)
      {
         G_NS_T = 2;
         G_NS_TG_OUTAGE_MS = 0;
         if(!NotifyStateWrite())
            return;
      }
      else if(rc == 2)
      {
         G_NS_T = 2;
         if(!NotifyStateWrite())
            return;
      }
      else if(rc == -2)
      {
         G_NS_T = 2;
         canP = G_NS_PUSH_AVAIL;
         canT = (G_NS_TG_AVAIL && !G_NS_TG_PERM);
         if(!G_NS_CH_SKIP_LOGGED_T)
         {
            NotifySenderLog("Telegram permanently disabled - skipping channel");
            G_NS_CH_SKIP_LOGGED_T = true;
         }
         if(!NotifyStateWrite())
            return;
         if(!canP && !canT)
         {
            NotifyLeaseWriteFatal();
            return;
         }
      }
      else
      {
         NotifyOutageNote(false);
         G_NS_T = 0;
         NotifyStateWrite();
         if(G_NS_TG_BACKOFF_HARD)
            return;
         if(NotifyOutageAged(false))
         {
            G_NS_T = 2;
            const string skipt = StringFormat("TG_SKIPPED_OUTAGE id=%s", G_NS_LID);
            NotifySenderLog(skipt);
            NotifySenderHud(skipt);
            if(!NotifyStateWrite())
               return;
         }
         else
            return;
      }
   }

   const bool pdone = (!wantP || G_NS_P == 2);
   const bool tdone = (!wantT || G_NS_T == 2);
   if(pdone && tdone)
      NotifyAdvanceLine(line_bytes, qsize);
}

void NotifyLeaseFollowerTick()
{
   const ulong now = NowMs();
   if(G_NS_BACKOFF_UNTIL_MS > 0 && now < G_NS_BACKOFF_UNTIL_MS)
      return;
   if(G_NS_LAST_LEASE_READ_MS != 0 && (now - G_NS_LAST_LEASE_READ_MS) < (ulong)LEASE_HB_SEC * 1000)
      return;
   G_NS_LAST_LEASE_READ_MS = now;

   string owner = "";
   int hb = 0;
   int gen = 0;
   string st = "";
   string fp = "";
   const int kind = NotifyLeaseProbe(owner, hb, gen, st, fp);
   if(kind == NS_LEASE_UNREADABLE)
      return;
   if(kind == NS_LEASE_OK && owner == G_NS_OWNER && (st == "RUN" || st == "CLAIM"))
   {
      G_NS_HB = hb;
      G_NS_GEN = gen;
      if(st == "CLAIM")
      {
         G_NS_ROLE = NS_ROLE_CLAIMING;
         G_NS_CONFIRM_UNTIL_MS = now;
         NotifyLeaseConfirmClaim();
         return;
      }
      if(!NotifyLegacyGuardTry())
      {
         NotifyLeaseYieldToLegacy(now);
         return;
      }
      G_NS_ROLE = NS_ROLE_HOLDER;
      G_NS_LAST_HB_MS = now;
      NotifyStateLoadAsHolder();
      NotifySenderLog("lease holder RUN");
      return;
   }
   if(kind == NS_LEASE_ABSENT || kind == NS_LEASE_EMPTY || kind == NS_LEASE_FREE)
   {
      G_NS_OBS_KEY = "";
      G_NS_CLAIM_FROM_STALE = false;
      G_NS_GEN = (kind == NS_LEASE_FREE) ? (gen + 1) : 1;
      G_NS_HB = 1;
      if(!NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "CLAIM", G_NS_FP))
         return;
      G_NS_ROLE = NS_ROLE_CLAIMING;
      G_NS_CONFIRM_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 2001));
      return;
   }

   if(st == "FATAL")
   {
      const string fkey = StringFormat("%d|%s", gen, fp);
      if(G_NS_FATAL_KEY != fkey)
      {
         G_NS_FATAL_KEY = fkey;
         G_NS_FATAL_SEEN_MS = now;
      }
      if(fp == G_NS_FP)
      {
         if((now - G_NS_FATAL_SEEN_MS) < (ulong)FATAL_COOLDOWN_SEC * 1000)
            return;
      }
      G_NS_CLAIM_FROM_STALE = false;
      G_NS_GEN = gen + 1;
      G_NS_HB = 1;
      if(!NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "CLAIM", G_NS_FP))
         return;
      G_NS_ROLE = NS_ROLE_CLAIMING;
      G_NS_CONFIRM_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 2001));
      return;
   }

   const string key = StringFormat("%s|%d|%d|%s", owner, hb, gen, st);
   if(key != G_NS_OBS_KEY)
   {
      G_NS_OBS_KEY = key;
      G_NS_OBS_MS = now;
      return;
   }
   if(G_NS_OBS_MS == 0 || (now - G_NS_OBS_MS) < (ulong)LEASE_STALE_SEC * 1000)
      return;

   G_NS_CLAIM_FROM_STALE = true;
   G_NS_GEN = gen + 1;
   G_NS_HB = 1;
   if(!NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "CLAIM", G_NS_FP))
      return;
   G_NS_ROLE = NS_ROLE_CLAIMING;
   G_NS_CONFIRM_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 2001));
}

void NotifyLeaseConfirmClaim()
{
   const ulong now = NowMs();
   if(now < G_NS_CONFIRM_UNTIL_MS)
      return;
   string owner = "";
   int hb = 0;
   int gen = 0;
   string st = "";
   string fp = "";
   bool claim_ok = false;
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(attempt > 0)
         Sleep(50 + (MathRand() % 51));
      const int kind = NotifyLeaseProbe(owner, hb, gen, st, fp);
      if(kind == NS_LEASE_UNREADABLE)
         continue;
      if(kind != NS_LEASE_OK || owner != G_NS_OWNER || st != "CLAIM" || gen != G_NS_GEN)
      {
         G_NS_BACKOFF_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 4001));
         NotifyLeaseBecomeFollower();
         return;
      }
      claim_ok = true;
      break;
   }
   if(!claim_ok)
   {
      G_NS_BACKOFF_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 4001));
      NotifyLeaseBecomeFollower();
      return;
   }
   if(!NotifyLegacyGuardTry())
   {
      if(!G_NS_CLAIM_FROM_STALE)
      {
         NotifyLeaseYieldToLegacy(now);
         return;
      }
   }
   G_NS_HB++;
   if(!NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "RUN", G_NS_FP))
   {
      NotifyLeaseBecomeFollower();
      return;
   }
   if(!NotifyLeaseReadNowRetry(owner, hb, gen, st, fp) || owner != G_NS_OWNER || st != "RUN")
   {
      G_NS_BACKOFF_UNTIL_MS = now + (ulong)(1000 + (MathRand() % 4001));
      NotifyLeaseBecomeFollower();
      return;
   }
   G_NS_ROLE = NS_ROLE_HOLDER;
   G_NS_LAST_HB_MS = now;
   NotifyStateLoadAsHolder();
   NotifySenderLog("lease holder RUN");
}

void NotifyLeaseMaybeRenew()
{
   const ulong now = NowMs();
   if(G_NS_LAST_HB_MS != 0 && (now - G_NS_LAST_HB_MS) < (ulong)LEASE_HB_SEC * 1000)
      return;
   if(!NotifyLeaseConfirmOwn())
   {
      NotifyLeaseLost();
      return;
   }
   if(!NotifyLegacyGuardTry())
   {
      NotifyLeaseYieldToLegacy(now);
      return;
   }
   G_NS_HB++;
   if(!NotifyLeaseWrite(G_NS_OWNER, G_NS_HB, G_NS_GEN, "RUN", G_NS_FP))
   {
      NotifyLeaseLost();
      return;
   }
   string owner = "";
   int hb = 0;
   int gen = 0;
   string st = "";
   string fp = "";
   if(!NotifyLeaseReadNowRetry(owner, hb, gen, st, fp) || owner != G_NS_OWNER || st != "RUN")
   {
      NotifyLeaseLost();
      return;
   }
   G_NS_LAST_HB_MS = now;
}

void NotifyLeaseMachine()
{
   if(G_NS_ROLE == NS_ROLE_DEAD)
      return;
   if(G_NS_ROLE == NS_ROLE_CLAIMING)
   {
      NotifyLeaseConfirmClaim();
      return;
   }
   if(G_NS_ROLE == NS_ROLE_HOLDER)
   {
      NotifyLeaseMaybeRenew();
      return;
   }
   NotifyLeaseFollowerTick();
}

void NotifySenderInit(const string kind, const int timeout_ms)
{
   G_NS_ACTIVE = true;
   G_NS_KIND = kind;
   if(StringFind(kind, "PM") == 0)
      G_NS_LOG = "[ProfitMonitor]";
   else
      G_NS_LOG = "[SFX-SYNC-NOTIFIER]";
   G_NS_TG_TIMEOUT_MS = timeout_ms;
   if(G_NS_TG_TIMEOUT_MS < 1000)
      G_NS_TG_TIMEOUT_MS = 1000;
   if(G_NS_TG_TIMEOUT_MS > 5000)
      G_NS_TG_TIMEOUT_MS = 5000;
   G_NS_ROLE = NS_ROLE_FOLLOWER;
   G_NS_LOCK = INVALID_HANDLE;
   G_NS_TG_PERM = false;
   G_NS_TG_PERM_LOGGED = false;
   G_NS_TG_SKIP400_LOGGED = false;
   G_NS_PUSH_ALERT_DONE = false;
   G_NS_QNEXT_LOGGED = false;
   G_NS_FAIL_LOGGED = false;
   G_NS_429_LOGGED = false;
   G_NS_INFLIGHT_HUD = false;
   G_NS_FATAL_ALERTED = false;
   G_NS_CH_SKIP_LOGGED_P = false;
   G_NS_CH_SKIP_LOGGED_T = false;
   G_NS_PUSH_UNAVAIL_LOGGED = false;
   G_NS_PUSH_BACKOFF_HARD = false;
   G_NS_TG_BACKOFF_HARD = false;
   NotifyOutageResetAll();
   G_NS_ERR_BACKOFF_SEC = 5;
   G_NS_PUSH_ERR_BACKOFF_SEC = 5;
   G_NS_TG_BACKOFF_UNTIL = 0;
   G_NS_PUSH_BACKOFF_UNTIL = 0;
   G_NS_PUSH_LAST_MS = 0;
   G_NS_PUSH_N = 0;
   G_NS_LAST_FAIL_PRINT_MS = 0;
   G_NS_429_LAST_PRINT_MS = 0;
   G_NS_PUSH_PRINT_MS = 0;
   G_NS_PUSH_CHECK_MS = 0;
   G_NS_LEGACY_PRINT_MS = 0;
   G_NS_LAST_LEASE_READ_MS = 0;
   G_NS_CONFIRM_UNTIL_MS = 0;
   G_NS_BACKOFF_UNTIL_MS = 0;
   G_NS_LAST_HB_MS = 0;
   G_NS_OBS_KEY = "";
   G_NS_OBS_MS = 0;
   G_NS_FATAL_KEY = "";
   G_NS_FATAL_SEEN_MS = 0;
   G_NS_CLAIM_FROM_STALE = false;
   NotifyStateClearMem();

   const long login = (long)AccountInfoInteger(ACCOUNT_LOGIN);
   MathSrand((int)(GetMicrosecondCount() ^ GetTickCount() ^ (int)ChartID() ^ (int)login));
   const uint us = (uint)GetMicrosecondCount();
   const int n1 = MathRand();
   const int n2 = MathRand();
   const int n3 = MathRand();
   G_NS_NONCE = StringFormat("%04X%04X%04X%04X",
                             (int)(us & 0xFFFF), n1 & 0xFFFF, n2 & 0xFFFF, n3 & 0xFFFF);
   const string path = TerminalInfoString(TERMINAL_DATA_PATH);
   const string ph = NotifyHex8u(NotifyFnv1a32(path));
   G_NS_OWNER = StringFormat("%s:%I64d:%s:%I64d:%s",
                             kind, login, ph, (long)ChartID(), G_NS_NONCE);
   G_NS_LEASE_TMP = "SFX-SYNC-notify-lease." + G_NS_NONCE + ".tmp";
   NotifyLeaseTmpCleanupOld();

   G_NS_PUSH_AVAIL = (MQLInfoInteger(MQL_TESTER) == 0 &&
                      TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED) != 0);

   string token = NotifyTrim(I_TG_BOT_TOKEN);
   if(StringLen(token) == 0)
      token = NotifyReadTokenFile();
   const string chat = NotifyTrim(I_TG_CHAT_ID);
   G_NS_TG_AVAIL = false;
   G_NS_TOKEN = "";
   if(StringLen(token) > 0 && !NotifyTokenCharsetOk(token))
   {
      const string warn = G_NS_LOG + " Telegram token has characters outside [0-9A-Za-z:_-] - Telegram disabled.";
      Print(warn);
      Alert(warn);
   }
   else if(StringLen(token) == 0 || StringLen(chat) == 0)
   {
      string why = (StringLen(token) == 0 && StringLen(chat) == 0)
         ? "bot token and chat id are empty"
         : (StringLen(token) == 0 ? "bot token is empty (input and Common Files token file)" : "chat id is empty");
      const string warn = G_NS_LOG + " Telegram disabled: " + why +
         ". Put the token in Common Files (never log it). Expected file: " + NotifyTokenFileExpectedPath() +
         ". Chat id via getUpdates. Allow WebRequest for https://api.telegram.org";
      Print(warn);
      Alert(G_NS_LOG + " Telegram disabled: " + why + ". Expected token file: " + NotifyTokenFileExpectedPath());
   }
   else
   {
      G_NS_TOKEN = token;
      G_NS_TG_AVAIL = true;
   }
   NotifySenderRefreshFp();
   NotifySenderLog("Common Files: " + TerminalInfoString(TERMINAL_COMMONDATA_PATH));
   NotifySenderLog("ready; one sender per Common Files via lease L2");
}

void NotifySenderDeinit()
{
   if(!G_NS_ACTIVE)
      return;
   if(G_NS_ROLE == NS_ROLE_HOLDER || G_NS_ROLE == NS_ROLE_CLAIMING)
      NotifyLeaseWriteFree();
   NotifyLeaseTmpDelete();
   NotifyLegacyGuardRelease();
   G_NS_ACTIVE = false;
   G_NS_ROLE = NS_ROLE_FOLLOWER;
   Comment("");
}

void NotifySenderTick(const bool allow_push, const bool allow_tg)
{
   if(!G_NS_ACTIVE)
      return;
   NotifyPushRecheck();
   NotifyLeaseMachine();
   if(G_NS_ROLE != NS_ROLE_HOLDER)
      return;
   if(!NotifyLeaseConfirmOwn())
   {
      NotifyLeaseLost();
      return;
   }
   NotifySenderProcessLine(allow_push, allow_tg);
}
// ==== END SFX-NOTIFY-SENDER ====


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(SendInterval < 10) {
        Print("Warning: Send interval too short, minimum is 10 seconds");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    EventSetTimer(timerInterval);
    
    if(I_NOTIFY_SENDER)
        NotifySenderInit("PM4", I_TG_TIMEOUT_MS);
    
    if(EnableLogging) {
        Print("Profit Monitor MT4 EA initialized");
        Print("API URL: ", API_URL);
        Print("Send Interval: ", SendInterval, " seconds");
        Print("Unit/Label: ", Unit);
        Print("Using TimeLocal for synchronized sending");
    }
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(I_NOTIFY_SENDER)
        NotifySenderDeinit();
    EventKillTimer();
    if(EnableLogging) {
        Print("Profit Monitor MT4 EA deinitialized");
    }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    datetime localTime = TimeLocal();
    
    // Check if current second aligns with SendInterval
    // This ensures all EAs send at the same time (synchronized)
    if(localTime % SendInterval == 0) {
        SendAccountData();
    }
    if(I_NOTIFY_SENDER)
    {
        datetime now2 = TimeLocal();
        int remain = SendInterval - (int)(now2 % SendInterval);
        int to = I_TG_TIMEOUT_MS;
        if(to < 1000)
            to = 1000;
        if(to > 5000)
            to = 5000;
        int need = (to + 999) / 1000 + 1;
        bool allow_tg = (remain > need);
        NotifySenderTick(true, allow_tg);
    }
}

//+------------------------------------------------------------------+
//| Send account data to API                                         |
//+------------------------------------------------------------------+
void SendAccountData()
{
    // Get account information
    string accountNumber = IntegerToString(AccountNumber());
    string accountName = AccountName();
    string brokerName = AccountCompany();
    double balance = AccountBalance();
    double equity = AccountEquity();
    
    // Determine broker time -> UTC offset so all open times are normalized
    int brokerOffsetSeconds = (int)(TimeCurrent() - TimeGMT());

    // Build open orders JSON array and track latest order for backward compatibility
    string lastSide = "UNKNOWN";
    double lastPrice = 0.0;
    double lastSize = 0.0;
    datetime latestOpenTime = 0;
    string ordersJson = "[";
    int orderCount = 0;
    int total = OrdersTotal();
    for(int i = 0; i < total; i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            int type = OrderType();
            if(type == OP_BUY || type == OP_SELL)
            {
                string side = (type == OP_BUY) ? "BUY" : "SELL";
                string symbol = OrderSymbol();
                double price = OrderOpenPrice();
                double lots = OrderLots();
                datetime openTime = OrderOpenTime();
                datetime openTimeUtc = openTime - brokerOffsetSeconds;
                int symDigits = (int)MarketInfo(symbol, MODE_DIGITS);
                if(symDigits <= 0) symDigits = Digits;
                string openTimeStr = CreateGMT7Timestamp(openTimeUtc);

                if(orderCount > 0) ordersJson += ",";
                ordersJson += "{";
                ordersJson += "\"symbol\":\"" + EscapeJSON(symbol) + "\",";
                ordersJson += "\"side\":\"" + side + "\",";
                ordersJson += "\"price\":" + DoubleToString(price, symDigits) + ",";
                ordersJson += "\"lots\":" + DoubleToString(lots, 2) + ",";
                ordersJson += "\"magic\":" + IntegerToString(OrderMagicNumber()) + ",";
                ordersJson += "\"openTime\":\"" + openTimeStr + "\"";
                ordersJson += "}";
                orderCount++;

                if(openTime >= latestOpenTime)
                {
                    latestOpenTime = openTime;
                    lastSide = side;
                    lastPrice = price;
                    lastSize = lots;
                }
            }
        }
    }
    ordersJson += "]";
    
    // Create GMT+7 timestamp using local time for consistency
    datetime localTime = TimeLocal();
    string timestamp = CreateGMT7Timestamp(localTime);
    
    // Create JSON payload
    string jsonData = CreateJSONPayload(accountNumber, accountName, brokerName, balance, equity, timestamp, Unit, lastSide, lastPrice, lastSize, ordersJson);
    
    if(EnableLogging) {
        Print("Sending account data:");
        Print("Account: ", accountNumber, " (", accountName, ")");
        Print("Broker: ", brokerName);
        Print("Balance: ", DoubleToString(balance, 2));
        Print("Equity: ", DoubleToString(equity, 2));
        Print("Unit: ", Unit);
        Print("Timestamp: ", timestamp);
    }
    
    // Send HTTP POST request
    SendHTTPRequest(jsonData);
}

//+------------------------------------------------------------------+
//| Create JSON payload                                              |
//+------------------------------------------------------------------+
string CreateJSONPayload(string accountNum, string accountName, string broker, double balance, double equity, string timestamp, int unit, string lastSide, double lastPrice, double lastSize, string ordersJson)
{
    string json = "{";
    json += "\"account_number\":\"" + accountNum + "\",";
    json += "\"account_name\":\"" + EscapeJSON(accountName) + "\",";
    json += "\"broker_name\":\"" + EscapeJSON(broker) + "\",";
    json += "\"balance\":" + DoubleToString(balance, 2) + ",";
    json += "\"equity\":" + DoubleToString(equity, 2) + ",";
    json += "\"unit\":" + IntegerToString(unit) + ",";
    json += "\"timestamp\":\"" + timestamp + "\",";
    json += "\"lastPositionSide\":\"" + lastSide + "\",";
    json += "\"lastPositionEntryPrice\":" + DoubleToString(lastPrice, Digits) + ",";
    json += "\"lastSize\":" + DoubleToString(lastSize, 2) + ",";
    json += "\"orders\":" + ordersJson;
    json += "}";
    
    return json;
}

//+------------------------------------------------------------------+
//| Escape JSON special characters                                   |
//+------------------------------------------------------------------+
string EscapeJSON(string text)
{
    string result = text;
    StringReplace(result, "\\", "\\\\");
    StringReplace(result, "\"", "\\\"");
    StringReplace(result, "\n", "\\n");
    StringReplace(result, "\r", "\\r");
    StringReplace(result, "\t", "\\t");
    return result;
}

//+------------------------------------------------------------------+
//| Create GMT+7 timestamp                                           |
//+------------------------------------------------------------------+
string CreateGMT7Timestamp(datetime time)
{
    // Add 7 hours for GMT+7 (Bangkok timezone)
    datetime gmt7Time = time + 7 * 3600;
    
    MqlDateTime dt;
    TimeToStruct(gmt7Time, dt);
    
    string timestamp = StringFormat("%04d-%02d-%02dT%02d:%02d:%02d+07:00",
        dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
    
    return timestamp;
}

//+------------------------------------------------------------------+
//| Send HTTP POST request                                           |
//+------------------------------------------------------------------+
void SendHTTPRequest(string jsonData)
{
    string headers = "Content-Type: application/json\r\n";
    
    char postData[];
    char resultData[];
    string resultHeaders;
    
    // Convert string to char array
    StringToCharArray(jsonData, postData, 0, StringLen(jsonData));
    
    // Send HTTP request
    int timeout = 5000; // 5 seconds timeout
    int result = WebRequest("POST", API_URL, headers, timeout, postData, resultData, resultHeaders);
    
    if(result == -1) {
        int error = GetLastError();
        if(EnableLogging) {
            Print("HTTP Request failed with error: ", error);
            Print("Make sure the URL is added to allowed URLs in Tools -> Options -> Expert Advisors");
        }
    } else {
        string response = CharArrayToString(resultData);
        if(EnableLogging) {
            Print("HTTP Response code: ", result);
            Print("Response: ", response);
        }
        
        if(result == 200) {
            if(EnableLogging) {
                Print("Account data sent successfully");
            }
        } else {
            if(EnableLogging) {
                Print("Server returned error code: ", result);
            }
        }
    }
}
