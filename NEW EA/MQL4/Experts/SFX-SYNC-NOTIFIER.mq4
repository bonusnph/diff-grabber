//+------------------------------------------------------------------+
//|                                            SFX-SYNC-NOTIFIER.mq4 |
//| Standalone Telegram sender for SFX-SYNC. Attach on any other     |
//| chart so WebRequest cannot stall the trading EA.                 |
//| One notifier per PC via SFX-SYNC-notifier.lock (all terminals).  |
//+------------------------------------------------------------------+
#define SFX_SYNC_NOTIFIER_VERSION "1.28"

#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   SFX_SYNC_NOTIFIER_VERSION
#property strict
#property description "SFX-SYNC Telegram notifier. Token/chat id live here, never in SFX-SYNC."

#define SFX_NOTIFY_QUEUE_FILE "SFX-SYNC-notify-queue.txt"
#define SFX_NOTIFY_QUEUE_OLD  "SFX-SYNC-notify-queue.txt.old"
#define SFX_NOTIFY_STATE_FILE "SFX-SYNC-notify-offset.txt"
#define SFX_NOTIFY_STATE_TMP  "SFX-SYNC-notify-offset.tmp"
#define SFX_NOTIFY_LOCK_FILE  "SFX-SYNC-notifier.lock"
#define SFX_NOTIFY_TG_TIMEOUT_MS 5000
#define SFX_NOTIFY_TG_RETRY_MAX_SEC 300
#define SFX_NOTIFY_TG_BACKOFF_DEFAULT_SEC 30
#define SFX_NOTIFY_FAIL_PRINT_MS 60000
#define SFX_NOTIFY_LOCK_PRINT_MS 60000
#define SFX_NOTIFY_ROTATE_BYTES 65536
#define SFX_NOTIFY_READ_CHUNK 4096

input string I_TG_BOT_TOKEN = "";              // Optional token; prefer I_TG_TOKEN_FILE (never logged)
input string I_TG_CHAT_ID = "";                // Telegram chat id (user or -group)
input string I_TG_TOKEN_FILE = "SFX-SYNC-telegram-token.txt"; // Common Files token if I_TG_BOT_TOKEN empty
input int    I_POLL_SEC = 2;                   // Queue poll interval (seconds)

string G_RESOLVED_TOKEN = "";
bool   G_TG_OK = false;
bool   G_PERM_DISABLED = false;
bool   G_PERM_LOGGED = false;
bool   G_SKIP400_LOGGED = false;
ulong  G_BACKOFF_UNTIL_MS = 0;
int    G_ERR_BACKOFF_SEC = 5;
bool   G_FAIL_LOGGED = false;
bool   G_429_LOGGED = false;
ulong  G_LAST_FAIL_PRINT_MS = 0;
ulong  G_429_LAST_PRINT_MS = 0;
long   G_QUEUE_OFFSET = 0;
string G_QUEUE_FIRST_ID = "";
int    G_LOCK_HANDLE = INVALID_HANDLE;
ulong  G_LOCK_LAST_PRINT_MS = 0;

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

bool OffsetParse(const string raw, long &off, string &qid)
{
   const string t = NotifyTrim(raw);
   if(StringLen(t) <= 0)
      return false;
   int tab = StringFind(t, "\t");
   string num = t;
   string id = "";
   if(tab >= 0)
   {
      num = StringSubstr(t, 0, tab);
      id = NotifyTrim(StringSubstr(t, tab + 1));
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
   qid = id;
   return true;
}

bool OffsetReadNamed(const string name, long &off, string &qid)
{
   ResetLastError();
   const int h = FileOpen(name, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;
   const string raw = FileReadString(h);
   FileClose(h);
   return OffsetParse(raw, off, qid);
}

bool OffsetSave()
{
   if(G_LOCK_HANDLE == INVALID_HANDLE)
      return false;
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_STATE_TMP, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false;
   FileWriteString(h, StringFormat("%I64d\t%s\n", G_QUEUE_OFFSET, G_QUEUE_FIRST_ID));
   FileClose(h);
   FileDelete(SFX_NOTIFY_STATE_FILE, FILE_COMMON);
   if(!FileMove(SFX_NOTIFY_STATE_TMP, FILE_COMMON, SFX_NOTIFY_STATE_FILE, FILE_COMMON))
      return false;
   return true;
}

void OffsetSaveChecked()
{
   if(!OffsetSave())
      Print("[SFX-SYNC-NOTIFIER] offset/state save failed");
}

void OffsetFirstAttach(const int qh, const long qsize, const string why)
{
   int skipped = 0;
   if(qh != INVALID_HANDLE)
      skipped = CountCompleteLines(qh, qsize);
   G_QUEUE_OFFSET = qsize;
   G_QUEUE_FIRST_ID = "";
   if(qh != INVALID_HANDLE)
   {
      FileSeek(qh, 0, SEEK_SET);
      uchar buf[];
      const int got = FileReadChunk(qh, buf, SFX_NOTIFY_READ_CHUNK);
      if(got > 0)
         LineIdFromBuf(buf, got, G_QUEUE_FIRST_ID);
   }
   OffsetSaveChecked();
   Print(StringFormat("[SFX-SYNC-NOTIFIER] first attach (%s): skipped %d existing queue line(s), offset=%I64d",
                      why, skipped, G_QUEUE_OFFSET));
}

void OffsetInitOnAttach()
{
   if(G_LOCK_HANDLE == INVALID_HANDLE)
      return;
   const int qh = QueueOpenRead();
   long qsize = 0;
   if(qh != INVALID_HANDLE)
      qsize = (long)FileSize(qh);

   const bool have_state = FileIsExist(SFX_NOTIFY_STATE_FILE, FILE_COMMON);
   const bool have_tmp = FileIsExist(SFX_NOTIFY_STATE_TMP, FILE_COMMON);
   long off = 0;
   string qid = "";
   bool parsed = false;
   if(have_state)
      parsed = OffsetReadNamed(SFX_NOTIFY_STATE_FILE, off, qid);
   if(!parsed && have_tmp)
      parsed = OffsetReadNamed(SFX_NOTIFY_STATE_TMP, off, qid);

   if(!parsed)
   {
      OffsetFirstAttach(qh, qsize, (!have_state && !have_tmp) ? "no state" : "unreadable state");
      if(qh != INVALID_HANDLE)
         FileClose(qh);
      return;
   }

   G_QUEUE_OFFSET = off;
   G_QUEUE_FIRST_ID = qid;
   string now_id = "";
   if(qh != INVALID_HANDLE)
   {
      FileSeek(qh, 0, SEEK_SET);
      uchar buf[];
      const int got = FileReadChunk(qh, buf, SFX_NOTIFY_READ_CHUNK);
      if(got > 0)
         LineIdFromBuf(buf, got, now_id);
      FileClose(qh);
   }

   if(qsize < G_QUEUE_OFFSET)
   {
      G_QUEUE_OFFSET = 0;
      G_QUEUE_FIRST_ID = now_id;
      OffsetSaveChecked();
      Print("[SFX-SYNC-NOTIFIER] queue smaller than saved offset - reset offset to 0");
      return;
   }
   if(StringLen(qid) > 0 && StringLen(now_id) > 0 && qid != now_id)
   {
      G_QUEUE_OFFSET = 0;
      G_QUEUE_FIRST_ID = now_id;
      OffsetSaveChecked();
      Print("[SFX-SYNC-NOTIFIER] queue first-line id changed - reset offset to 0");
   }
}

void NotifierLockRelease()
{
   if(G_LOCK_HANDLE == INVALID_HANDLE)
      return;
   FileClose(G_LOCK_HANDLE);
   G_LOCK_HANDLE = INVALID_HANDLE;
}

bool NotifierLockTry()
{
   if(G_LOCK_HANDLE != INVALID_HANDLE)
      return true;
   ResetLastError();
   G_LOCK_HANDLE = FileOpen(SFX_NOTIFY_LOCK_FILE, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(G_LOCK_HANDLE != INVALID_HANDLE)
   {
      OffsetInitOnAttach();
      return true;
   }
   const ulong now = NowMs();
   if(G_LOCK_LAST_PRINT_MS == 0 || (now - G_LOCK_LAST_PRINT_MS) >= (ulong)SFX_NOTIFY_LOCK_PRINT_MS)
   {
      Print("[SFX-SYNC-NOTIFIER] another notifier holds SFX-SYNC-notifier.lock - this instance will not send (one notifier per PC, all terminals)");
      G_LOCK_LAST_PRINT_MS = now;
   }
   return false;
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
            Print("[SFX-SYNC-NOTIFIER] rotate tail append failed");
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
      Print(StringFormat("[SFX-SYNC-NOTIFIER] rotate tail dropped %d leftover byte(s) without trailing newline", leftover_n));
}

void MaybeRotateQueue()
{
   const int rh = QueueOpenRead();
   if(rh == INVALID_HANDLE)
      return;
   const long qsize = (long)FileSize(rh);
   FileClose(rh);
   if(G_QUEUE_OFFSET < qsize)
      return;
   if(qsize < SFX_NOTIFY_ROTATE_BYTES)
      return;
   ResetLastError();
   FileDelete(SFX_NOTIFY_QUEUE_OLD, FILE_COMMON);
   if(!FileMove(SFX_NOTIFY_QUEUE_FILE, FILE_COMMON, SFX_NOTIFY_QUEUE_OLD, FILE_COMMON))
      return;
   RecoverRotateTail(qsize);
   G_QUEUE_OFFSET = 0;
   G_QUEUE_FIRST_ID = QueueFirstLineId();
   OffsetSaveChecked();
   Print("[SFX-SYNC-NOTIFIER] rotated queue file to SFX-SYNC-notify-queue.txt.old");
}

int NotifyTelegramPost(const string text)
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return 0;
   const string token = G_RESOLVED_TOKEN;
   const string chat = NotifyTrim(I_TG_CHAT_ID);
   if(StringLen(token) == 0 || StringLen(chat) == 0)
      return 0;
   const string url = "https://api.telegram.org/bot" + token + "/sendMessage";
   const string body = "chat_id=" + NotifyUrlEncode(chat) + "&text=" + NotifyUrlEncode(text);
   const string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   char postData[];
   char resultData[];
   string resultHeaders;
   StringToCharArray(body, postData, 0, StringLen(body));
   ResetLastError();
   const int http = WebRequest("POST", url, headers, SFX_NOTIFY_TG_TIMEOUT_MS, postData, resultData, resultHeaders);
   const int err = GetLastError();
   if(http == 400)
   {
      const string resp = CharArrayToString(resultData);
      if(NotifyHttp400IsChatFatal(resp))
      {
         if(!G_PERM_LOGGED)
         {
            const string mig = NotifyExtractMigrateChatId(resp);
            string warn = "[SFX-SYNC-NOTIFIER] Telegram HTTP 400 chat/config error - sending disabled until reinit (token not logged)";
            if(StringLen(mig) > 0)
               warn += ". New chat id from migrate_to_chat_id: " + mig;
            Print(warn);
            Alert(warn);
            G_PERM_LOGGED = true;
         }
         G_PERM_DISABLED = true;
         G_TG_OK = false;
         // Keep SFX-SYNC-notifier.lock until OnDeinit so a second instance does not send in parallel.
         return -2;
      }
      const string skip = "[SFX-SYNC-NOTIFIER] Telegram HTTP 400 - skipping this line (malformed payload, token not logged)";
      Print(skip);
      if(!G_SKIP400_LOGGED)
      {
         Alert(skip);
         G_SKIP400_LOGGED = true;
      }
      return 2;
   }
   if(http == 401 || http == 403 || http == 404)
   {
      if(!G_PERM_LOGGED)
      {
         const string warn = StringFormat(
            "[SFX-SYNC-NOTIFIER] Telegram permanent HTTP %d - sending disabled until reinit (token not logged). Revoke and replace the bot token if this is 401.",
            http);
         Print(warn);
         Alert(warn);
         G_PERM_LOGGED = true;
      }
      G_PERM_DISABLED = true;
      G_TG_OK = false;
      // Keep SFX-SYNC-notifier.lock until OnDeinit so a second instance does not send in parallel.
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
      G_BACKOFF_UNTIL_MS = NowMs() + (ulong)sec * 1000;
      const ulong now429 = NowMs();
      if(!G_429_LOGGED || (G_429_LAST_PRINT_MS > 0 && (now429 - G_429_LAST_PRINT_MS) >= (ulong)SFX_NOTIFY_FAIL_PRINT_MS))
      {
         Print(StringFormat("[SFX-SYNC-NOTIFIER] Telegram HTTP 429 backoff %d s (kept, not dropped)", sec));
         G_429_LOGGED = true;
         G_429_LAST_PRINT_MS = now429;
      }
      return -1;
   }
   if(http == -1 || http == 4014 || http == 4060 || http != 200)
   {
      const ulong now = NowMs();
      if(!G_FAIL_LOGGED || (G_LAST_FAIL_PRINT_MS > 0 && (now - G_LAST_FAIL_PRINT_MS) >= (ulong)SFX_NOTIFY_FAIL_PRINT_MS))
      {
         Print(StringFormat("[SFX-SYNC-NOTIFIER] Telegram send failed http=%d err=%d (allow https://api.telegram.org)", http, err));
         G_FAIL_LOGGED = true;
         G_LAST_FAIL_PRINT_MS = now;
      }
      G_BACKOFF_UNTIL_MS = NowMs() + (ulong)G_ERR_BACKOFF_SEC * 1000;
      if(G_ERR_BACKOFF_SEC < SFX_NOTIFY_TG_RETRY_MAX_SEC)
      {
         G_ERR_BACKOFF_SEC *= 2;
         if(G_ERR_BACKOFF_SEC > SFX_NOTIFY_TG_RETRY_MAX_SEC)
            G_ERR_BACKOFF_SEC = SFX_NOTIFY_TG_RETRY_MAX_SEC;
      }
      return 0;
   }
   G_FAIL_LOGGED = false;
   G_429_LOGGED = false;
   G_ERR_BACKOFF_SEC = 5;
   G_BACKOFF_UNTIL_MS = 0;
   return 1;
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

void ProcessQueueOnce()
{
   if(G_PERM_DISABLED || !G_TG_OK)
      return;
   if(!NotifierLockTry())
      return;
   if(G_BACKOFF_UNTIL_MS > 0 && NowMs() < G_BACKOFF_UNTIL_MS)
      return;

   const int h = QueueOpenRead();
   if(h == INVALID_HANDLE)
      return;
   const long qsize = (long)FileSize(h);
   if(qsize < G_QUEUE_OFFSET)
   {
      G_QUEUE_OFFSET = 0;
      FileSeek(h, 0, SEEK_SET);
      uchar idbuf[];
      const int got = FileReadChunk(h, idbuf, SFX_NOTIFY_READ_CHUNK);
      G_QUEUE_FIRST_ID = "";
      if(got > 0)
         LineIdFromBuf(idbuf, got, G_QUEUE_FIRST_ID);
      OffsetSaveChecked();
      Print("[SFX-SYNC-NOTIFIER] queue smaller than saved offset - reset offset to 0");
   }
   const long remain_all = qsize - G_QUEUE_OFFSET;
   if(remain_all <= 0)
   {
      FileClose(h);
      MaybeRotateQueue();
      return;
   }
   FileSeek(h, G_QUEUE_OFFSET, SEEK_SET);
   uchar buf[];
   int have = 0;
   long still = remain_all;
   bool have_line = false;
   string line = "";
   int line_bytes = 0;
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
   if(!have_line)
      return;

   const string trimmed = NotifyTrim(line);
   bool advance = false;
   if(StringLen(trimmed) <= 0)
      advance = true;
   else
   {
      const int tab = StringFind(trimmed, "\t");
      if(tab <= 0)
         advance = true;
      else
      {
         const string text = StringSubstr(trimmed, tab + 1);
         const int rc = NotifyTelegramPost(text);
         if(rc > 0)
            advance = true;
         else if(rc == -2)
            return;
      }
   }
   if(advance)
   {
      if(StringLen(G_QUEUE_FIRST_ID) <= 0 && G_QUEUE_OFFSET > 0)
         G_QUEUE_FIRST_ID = QueueFirstLineId();
      G_QUEUE_OFFSET += line_bytes;
      OffsetSaveChecked();
      if(G_QUEUE_OFFSET >= qsize)
         MaybeRotateQueue();
   }
}

int OnInit()
{
   G_RESOLVED_TOKEN = "";
   G_TG_OK = false;
   G_PERM_DISABLED = false;
   G_PERM_LOGGED = false;
   G_SKIP400_LOGGED = false;
   G_BACKOFF_UNTIL_MS = 0;
   G_ERR_BACKOFF_SEC = 5;
   G_FAIL_LOGGED = false;
   G_429_LOGGED = false;
   G_LAST_FAIL_PRINT_MS = 0;
   G_429_LAST_PRINT_MS = 0;
   G_LOCK_HANDLE = INVALID_HANDLE;
   G_LOCK_LAST_PRINT_MS = 0;
   G_QUEUE_OFFSET = 0;
   G_QUEUE_FIRST_ID = "";

   string token = NotifyTrim(I_TG_BOT_TOKEN);
   if(StringLen(token) == 0)
      token = NotifyReadTokenFile();
   const string chat = NotifyTrim(I_TG_CHAT_ID);

   if(StringLen(token) > 0 && !NotifyTokenCharsetOk(token))
   {
      const string warn = "[SFX-SYNC-NOTIFIER] Telegram token has characters outside [0-9A-Za-z:_-] - Telegram disabled.";
      Print(warn);
      Alert(warn);
      EventSetTimer((int)MathMax(1, I_POLL_SEC));
      return INIT_SUCCEEDED;
   }
   if(StringLen(token) == 0 || StringLen(chat) == 0)
   {
      string why = (StringLen(token) == 0 && StringLen(chat) == 0)
         ? "bot token and chat id are empty"
         : (StringLen(token) == 0 ? "bot token is empty (input and Common Files token file)" : "chat id is empty");
      const string warn = "[SFX-SYNC-NOTIFIER] Telegram disabled: " + why +
         ". Put the token in Common Files (never log it). Expected file: " + NotifyTokenFileExpectedPath() +
         ". Chat id via getUpdates. Allow WebRequest for https://api.telegram.org";
      Print(warn);
      Alert("[SFX-SYNC-NOTIFIER] Telegram disabled: " + why + ". Expected token file: " + NotifyTokenFileExpectedPath());
      EventSetTimer((int)MathMax(1, I_POLL_SEC));
      return INIT_SUCCEEDED;
   }

   G_RESOLVED_TOKEN = token;
   G_TG_OK = true;
   NotifierLockTry();
   Print("[SFX-SYNC-NOTIFIER] ready; polling Common Files queue (lock file SFX-SYNC-notifier.lock, one notifier per PC)");
   EventSetTimer((int)MathMax(1, I_POLL_SEC));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   NotifierLockRelease();
   EventKillTimer();
}

void OnTimer()
{
   ProcessQueueOnce();
}
