//+------------------------------------------------------------------+
//|                                              ProfitMonitor-MT5.mq5 |
//|                                    Copyright 2024, Profit Monitor |
//|                                                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Profit Monitor"
#property version   "1.00"

// Input parameters
input string API_URL = "https://profit-monitor.vercel.app/api/webhook"; // API endpoint URL
input int SendInterval = 30; // Send interval in seconds (30 = 30 seconds)
input int Unit = 0; // Unit/Label for grouping (1, 2, 3, etc.)
bool EnableLogging = false; // Enable console logging

// Global variables
int timerInterval = 1; // Check every 1 second

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
    
    if(EnableLogging) {
        Print("Profit Monitor MT5 EA initialized");
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
    EventKillTimer();
    if(EnableLogging) {
        Print("Profit Monitor MT5 EA deinitialized");
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
}

//+------------------------------------------------------------------+
//| Send account data to API                                         |
//+------------------------------------------------------------------+
void SendAccountData()
{
    // Get account information
    string accountNumber = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
    string accountName = AccountInfoString(ACCOUNT_NAME);
    string brokerName = AccountInfoString(ACCOUNT_COMPANY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Create GMT+7 timestamp using local time for consistency
    datetime localTime = TimeLocal();
    string timestamp = CreateGMT7Timestamp(localTime);
    
    // Create JSON payload
    string jsonData = CreateJSONPayload(accountNumber, accountName, brokerName, balance, equity, timestamp, Unit);
    
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
string CreateJSONPayload(string accountNum, string accountName, string broker, double balance, double equity, string timestamp, int unit)
{
    string json = "{";
    json += "\"account_number\":\"" + accountNum + "\",";
    json += "\"account_name\":\"" + EscapeJSON(accountName) + "\",";
    json += "\"broker_name\":\"" + EscapeJSON(broker) + "\",";
    json += "\"balance\":" + DoubleToString(balance, 2) + ",";
    json += "\"equity\":" + DoubleToString(equity, 2) + ",";
    json += "\"unit\":" + IntegerToString(unit) + ",";
    json += "\"timestamp\":\"" + timestamp + "\"";
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
