//+------------------------------------------------------------------+
//|                                            SFX-SYNC-NOTIFIER.mq5 |
//| Standalone Telegram sender for SFX-SYNC. Attach on any other     |
//| chart so WebRequest cannot stall the trading EA.                 |
//+------------------------------------------------------------------+
#define SFX_SYNC_NOTIFIER_VERSION "1.28"

#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   SFX_SYNC_NOTIFIER_VERSION
#property description "SFX-SYNC Telegram notifier. Token/chat id live here, never in SFX-SYNC."

#define SFX_NOTIFY_QUEUE_FILE "SFX-SYNC-notify-queue.txt"
#define SFX_NOTIFY_SENT_FILE  "SFX-SYNC-notify-sent.txt"
#define SFX_NOTIFY_SENT_CAP   400
#define SFX_NOTIFY_TG_TIMEOUT_MS 5000
#define SFX_NOTIFY_TG_RETRY_MAX_SEC 300
#define SFX_NOTIFY_TG_BACKOFF_DEFAULT_SEC 30
#define SFX_NOTIFY_FAIL_PRINT_MS 60000

input string I_TG_BOT_TOKEN = "";              // Optional token; prefer I_TG_TOKEN_FILE (never logged)
input string I_TG_CHAT_ID = "";                // Telegram chat id (user or -group)
input string I_TG_TOKEN_FILE = "SFX-SYNC-telegram-token.txt"; // Common Files token if I_TG_BOT_TOKEN empty
input int    I_POLL_SEC = 2;                   // Queue poll interval (seconds)

string G_RESOLVED_TOKEN = "";
bool   G_TG_OK = false;
string G_SENT_IDS[400];
int    G_SENT_N = 0;
ulong  G_BACKOFF_UNTIL_MS = 0;
int    G_ERR_BACKOFF_SEC = 5;
bool   G_FAIL_LOGGED = false;
bool   G_429_LOGGED = false;
ulong  G_LAST_FAIL_PRINT_MS = 0;
ulong  G_429_LAST_PRINT_MS = 0;

ulong NowMs()
{
   return (ulong)GetTickCount();
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
      const int c = (int)bytes[i];
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

bool SentIdKnown(const string id)
{
   for(int i = 0; i < G_SENT_N; i++)
   {
      if(G_SENT_IDS[i] == id)
         return true;
   }
   return false;
}

void SentIdRemember(const string id)
{
   if(StringLen(id) <= 0 || SentIdKnown(id))
      return;
   if(G_SENT_N >= SFX_NOTIFY_SENT_CAP)
   {
      for(int i = 1; i < SFX_NOTIFY_SENT_CAP; i++)
         G_SENT_IDS[i - 1] = G_SENT_IDS[i];
      G_SENT_N = SFX_NOTIFY_SENT_CAP - 1;
   }
   G_SENT_IDS[G_SENT_N] = id;
   G_SENT_N++;
}

void SentIdsLoad()
{
   G_SENT_N = 0;
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_SENT_FILE,
                          FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
   {
      const string line = NotifyTrim(FileReadString(h));
      if(StringLen(line) > 0)
         SentIdRemember(line);
   }
   FileClose(h);
}

bool SentIdPersist(const string id)
{
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_SENT_FILE,
                          FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return false;
   FileSeek(h, 0, SEEK_END);
   const uint wrote = FileWriteString(h, id + "\n");
   FileClose(h);
   return (wrote > 0);
}

void MarkSent(const string id)
{
   SentIdRemember(id);
   SentIdPersist(id);
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
   uchar postData[];
   uchar resultData[];
   string resultHeaders;
   StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);
   ResetLastError();
   const int http = WebRequest("POST", url, headers, SFX_NOTIFY_TG_TIMEOUT_MS, postData, resultData, resultHeaders);
   const int err = GetLastError();
   if(http == 429)
   {
      int sec = NotifyExtractRetryAfterSec(resultHeaders);
      if(sec <= 0)
         sec = NotifyExtractRetryAfterSec(CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8));
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

void ProcessQueueOnce()
{
   if(!G_TG_OK)
      return;
   if(G_BACKOFF_UNTIL_MS > 0 && NowMs() < G_BACKOFF_UNTIL_MS)
      return;
   ResetLastError();
   const int h = FileOpen(SFX_NOTIFY_QUEUE_FILE,
                          FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return;
   string pending_id = "";
   string pending_text = "";
   while(!FileIsEnding(h))
   {
      const string raw = FileReadString(h);
      const string line = NotifyTrim(raw);
      if(StringLen(line) <= 0)
         continue;
      const int tab = StringFind(line, "\t");
      if(tab <= 0)
         continue;
      const string id = StringSubstr(line, 0, tab);
      const string text = StringSubstr(line, tab + 1);
      if(SentIdKnown(id))
         continue;
      pending_id = id;
      pending_text = text;
      break;
   }
   FileClose(h);
   if(StringLen(pending_id) <= 0)
      return;
   const int rc = NotifyTelegramPost(pending_text);
   if(rc > 0)
      MarkSent(pending_id);
}

int OnInit()
{
   G_RESOLVED_TOKEN = "";
   G_TG_OK = false;
   G_BACKOFF_UNTIL_MS = 0;
   G_ERR_BACKOFF_SEC = 5;
   G_FAIL_LOGGED = false;
   G_429_LOGGED = false;
   G_LAST_FAIL_PRINT_MS = 0;
   G_429_LAST_PRINT_MS = 0;
   SentIdsLoad();

   string token = NotifyTrim(I_TG_BOT_TOKEN);
   if(StringLen(token) == 0)
      token = NotifyReadTokenFile();
   const string chat = NotifyTrim(I_TG_CHAT_ID);

   if(StringLen(token) > 0 && !NotifyTokenCharsetOk(token))
   {
      const string warn = "[SFX-SYNC-NOTIFIER] Telegram token has characters outside [0-9A-Za-z:_-] — Telegram disabled.";
      Print(warn);
      Alert(warn);
      EventSetTimer(MathMax(1, I_POLL_SEC));
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
      EventSetTimer(MathMax(1, I_POLL_SEC));
      return INIT_SUCCEEDED;
   }

   G_RESOLVED_TOKEN = token;
   G_TG_OK = true;
   Print("[SFX-SYNC-NOTIFIER] ready; polling Common Files queue SFX-SYNC-notify-queue.txt");
   EventSetTimer((int)MathMax(1, I_POLL_SEC));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   ProcessQueueOnce();
}
