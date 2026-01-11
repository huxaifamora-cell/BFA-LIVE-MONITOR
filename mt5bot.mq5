//+------------------------------------------------------------------+
//|                                      BFA_REALTIME_MONITOR.mq5    |
//|                              Real-time WebSocket Communication   |
//+------------------------------------------------------------------+
#property copyright "BFA REALTIME MONITOR"
#property version   "3.50"
#property strict

//--- Input Parameters
input group "=== WEBSOCKET SETTINGS ==="
input string InpWebSocketUrl = "wss://bfa-live-monitor.onrender.com"; // WebSocket Server URL
input bool InpInstantRemoval = true; // Instantly remove signals when conditions not met
input int InpHeartbeatInterval = 30; // Heartbeat interval (seconds)
input int InpReconnectAttempts = 3; // Max reconnection attempts

input group "=== SIGNAL LOGIC SETTINGS ==="
input int InpBBPeriod = 20;
input double InpBBDeviation = 2.0;
input int InpSMAPeriod = 10;
input int InpEMAPeriod = 10;
input int InpSlopeBars = 5;
input double InpMinSlopeThreshold = 0.0;

input group "=== INDICATOR COLORS ==="
input color InpBBColor = clrGreen;
input color InpSMAColor = clrRed;
input color InpEMAColor = clrBlue;
input int InpBBWidth = 1;
input int InpSMAWidth = 2;
input int InpEMAWidth = 2;

input group "=== SYMBOL MONITORING ==="
input bool InpMonitorBoom1000 = true;
input bool InpMonitorBoom900 = true;
input bool InpMonitorBoom600 = true;
input bool InpMonitorBoom500 = true;
input bool InpMonitorBoom300 = true;
input bool InpMonitorBoom150 = true;
input bool InpMonitorCrash1000 = true;
input bool InpMonitorCrash900 = true;
input bool InpMonitorCrash600 = true;
input bool InpMonitorCrash500 = true;
input bool InpMonitorCrash300 = true;
input bool InpMonitorCrash150 = true;

input group "=== DEBUG SETTINGS ==="
input bool InpEnableDebugLog = false;

//--- Global Variables
struct ActiveSignal
{
   string symbol;
   string timeframe;
   string tradeType;
   string h4Trend;
   string d1Trend;
   double minLot;
   double minMargin;
   int priority;
   datetime timestamp;
   bool active;
};

struct SymbolData
{
   string name;
   bool enabled;
   bool isBoom;
   bool wasValidM30;
   bool wasValidH1;
   bool isValidM30;
   bool isValidH1;
   int hBB_M30;
   int hSMA_M30;
   int hEMA_M30;
   int hBB_H1;
   int hSMA_H1;
   int hEMA_H1;
};

SymbolData symbols[];
ActiveSignal activeSignals[];
int totalSymbols = 12;
int handleBB, handleSMA, handleEMA;

// Connection management
datetime lastHeartbeat = 0;
datetime lastSuccessfulRequest = 0;
bool isConnected = false;
int consecutiveFailures = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(symbols, totalSymbols);
   ArrayResize(activeSignals, 0);
   
   symbols[0].name = "Boom 1000 Index"; symbols[0].enabled = InpMonitorBoom1000; symbols[0].isBoom = true;
   symbols[1].name = "Boom 900 Index"; symbols[1].enabled = InpMonitorBoom900; symbols[1].isBoom = true;
   symbols[2].name = "Boom 600 Index"; symbols[2].enabled = InpMonitorBoom600; symbols[2].isBoom = true;
   symbols[3].name = "Boom 500 Index"; symbols[3].enabled = InpMonitorBoom500; symbols[3].isBoom = true;
   symbols[4].name = "Boom 300 Index"; symbols[4].enabled = InpMonitorBoom300; symbols[4].isBoom = true;
   symbols[5].name = "Boom 150 Index"; symbols[5].enabled = InpMonitorBoom150; symbols[5].isBoom = true;
   symbols[6].name = "Crash 1000 Index"; symbols[6].enabled = InpMonitorCrash1000; symbols[6].isBoom = false;
   symbols[7].name = "Crash 900 Index"; symbols[7].enabled = InpMonitorCrash900; symbols[7].isBoom = false;
   symbols[8].name = "Crash 600 Index"; symbols[8].enabled = InpMonitorCrash600; symbols[8].isBoom = false;
   symbols[9].name = "Crash 500 Index"; symbols[9].enabled = InpMonitorCrash500; symbols[9].isBoom = false;
   symbols[10].name = "Crash 300 Index"; symbols[10].enabled = InpMonitorCrash300; symbols[10].isBoom = false;
   symbols[11].name = "Crash 150 Index"; symbols[11].enabled = InpMonitorCrash150; symbols[11].isBoom = false;
   
   Print("🔧 Creating indicator handles for all symbols...");
   int successCount = 0;
   
   for(int i = 0; i < totalSymbols; i++)
   {
      symbols[i].wasValidM30 = false;
      symbols[i].wasValidH1 = false;
      symbols[i].isValidM30 = false;
      symbols[i].isValidH1 = false;
      
      if(!symbols[i].enabled) 
      {
         symbols[i].hBB_M30 = INVALID_HANDLE;
         symbols[i].hSMA_M30 = INVALID_HANDLE;
         symbols[i].hEMA_M30 = INVALID_HANDLE;
         symbols[i].hBB_H1 = INVALID_HANDLE;
         symbols[i].hSMA_H1 = INVALID_HANDLE;
         symbols[i].hEMA_H1 = INVALID_HANDLE;
         continue;
      }
      
      if(!SymbolSelect(symbols[i].name, true))
      {
         Print("⚠️ Failed to select symbol: ", symbols[i].name);
         symbols[i].enabled = false;
         continue;
      }
      
      symbols[i].hBB_M30 = iBands(symbols[i].name, PERIOD_M30, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      symbols[i].hSMA_M30 = iMA(symbols[i].name, PERIOD_M30, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      symbols[i].hEMA_M30 = iMA(symbols[i].name, PERIOD_M30, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      
      symbols[i].hBB_H1 = iBands(symbols[i].name, PERIOD_H1, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      symbols[i].hSMA_H1 = iMA(symbols[i].name, PERIOD_H1, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      symbols[i].hEMA_H1 = iMA(symbols[i].name, PERIOD_H1, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      
      if(symbols[i].hBB_M30 == INVALID_HANDLE || symbols[i].hSMA_M30 == INVALID_HANDLE || 
         symbols[i].hEMA_M30 == INVALID_HANDLE || symbols[i].hBB_H1 == INVALID_HANDLE || 
         symbols[i].hSMA_H1 == INVALID_HANDLE || symbols[i].hEMA_H1 == INVALID_HANDLE)
      {
         Print("❌ Failed to create indicators for ", symbols[i].name);
         symbols[i].enabled = false;
         continue;
      }
      
      successCount++;
      Print("✅ ", symbols[i].name, " - handles created");
   }
   
   Print("✅ Successfully created handles for ", successCount, " symbols");
   
   handleBB = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   handleSMA = iMA(_Symbol, PERIOD_CURRENT, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   handleEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleBB == INVALID_HANDLE || handleSMA == INVALID_HANDLE || handleEMA == INVALID_HANDLE)
   {
      Print("❌ Error creating chart indicators!");
      return(INIT_FAILED);
   }
   
   ChartIndicatorAdd(0, 0, handleBB);
   ChartIndicatorAdd(0, 0, handleSMA);
   ChartIndicatorAdd(0, 0, handleEMA);
   
   CreateIndicatorLines();
   
   Print("╔════════════════════════════════════════╗");
   Print("║  BFA REALTIME MONITOR v3.50            ║");
   Print("║  WITH CONNECTION MANAGEMENT            ║");
   Print("╚════════════════════════════════════════╝");
   Print("📡 WebSocket: ", InpWebSocketUrl);
   Print("💓 Heartbeat: Every ", InpHeartbeatInterval, " seconds");
   Print("🔄 Reconnect attempts: ", InpReconnectAttempts);
   
   string httpUrl = InpWebSocketUrl;
   StringReplace(httpUrl, "wss://", "https://");
   StringReplace(httpUrl, "ws://", "http://");
   Print("📤 HTTP Endpoint: ", httpUrl);
   Print("📊 Active symbols: ", successCount, " boom & crash");
   Print("✅ Initialized successfully!");
   
   // Test initial connection
   Print("🔌 Testing initial connection...");
   if(SendHeartbeat())
   {
      Print("✅ Connected to server!");
      isConnected = true;
   }
   else
   {
      Print("⚠️ Initial connection failed - will retry");
      isConnected = false;
   }
   
   Print("⏳ Waiting 3 seconds for indicators to initialize...");
   Sleep(3000);
   
   Print("🔍 Performing initial signal scan...");
   int foundSignals = 0;
   for(int i = 0; i < totalSymbols; i++)
   {
      if(!symbols[i].enabled) continue;
      
      CheckAndUpdateSignal(i, false);
      if(symbols[i].isValidM30) foundSignals++;
      
      CheckAndUpdateSignal(i, true);
      if(symbols[i].isValidH1) foundSignals++;
   }
   Print("✅ Initial scan complete! Found ", foundSignals, " active signals.");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void CreateIndicatorLines()
{
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(bars < 100) return;
   
   for(int i = 0; i < 100; i++)
   {
      ObjectDelete(0, "BB_Upper_" + IntegerToString(i));
      ObjectDelete(0, "BB_Middle_" + IntegerToString(i));
      ObjectDelete(0, "BB_Lower_" + IntegerToString(i));
      ObjectDelete(0, "SMA_" + IntegerToString(i));
      ObjectDelete(0, "EMA_" + IntegerToString(i));
   }
   
   if(BarsCalculated(handleBB) < 2 || BarsCalculated(handleSMA) < 2 || BarsCalculated(handleEMA) < 2)
      return;
   
   int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(visibleBars > 100) visibleBars = 100;
   
   DrawIndicatorValues(visibleBars);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void DrawIndicatorValues(int barsCount)
{
   double bbUpper[], bbMiddle[], bbLower[], sma[], ema[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(sma, true);
   ArraySetAsSeries(ema, true);
   
   if(CopyBuffer(handleBB, 1, 0, barsCount, bbUpper) <= 0) return;
   if(CopyBuffer(handleBB, 0, 0, barsCount, bbMiddle) <= 0) return;
   if(CopyBuffer(handleBB, 2, 0, barsCount, bbLower) <= 0) return;
   if(CopyBuffer(handleSMA, 0, 0, barsCount, sma) <= 0) return;
   if(CopyBuffer(handleEMA, 0, 0, barsCount, ema) <= 0) return;
   
   datetime time[];
   ArraySetAsSeries(time, true);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, barsCount, time);
   
   for(int i = 0; i < barsCount - 1; i++)
   {
      CreateTrendLine("BB_Upper_" + IntegerToString(i), time[i+1], bbUpper[i+1], time[i], bbUpper[i], InpBBColor, InpBBWidth);
      CreateTrendLine("BB_Middle_" + IntegerToString(i), time[i+1], bbMiddle[i+1], time[i], bbMiddle[i], InpBBColor, InpBBWidth + 1);
      CreateTrendLine("BB_Lower_" + IntegerToString(i), time[i+1], bbLower[i+1], time[i], bbLower[i], InpBBColor, InpBBWidth);
      CreateTrendLine("SMA_" + IntegerToString(i), time[i+1], sma[i+1], time[i], sma[i], InpSMAColor, InpSMAWidth);
      CreateTrendLine("EMA_" + IntegerToString(i), time[i+1], ema[i+1], time[i], ema[i], InpEMAColor, InpEMAWidth);
   }
}

//+------------------------------------------------------------------+
void CreateTrendLine(string name, datetime time1, double price1, datetime time2, double price2, color clr, int width)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < totalSymbols; i++)
   {
      if(symbols[i].hBB_M30 != INVALID_HANDLE) IndicatorRelease(symbols[i].hBB_M30);
      if(symbols[i].hSMA_M30 != INVALID_HANDLE) IndicatorRelease(symbols[i].hSMA_M30);
      if(symbols[i].hEMA_M30 != INVALID_HANDLE) IndicatorRelease(symbols[i].hEMA_M30);
      if(symbols[i].hBB_H1 != INVALID_HANDLE) IndicatorRelease(symbols[i].hBB_H1);
      if(symbols[i].hSMA_H1 != INVALID_HANDLE) IndicatorRelease(symbols[i].hSMA_H1);
      if(symbols[i].hEMA_H1 != INVALID_HANDLE) IndicatorRelease(symbols[i].hEMA_H1);
   }
   
   for(int i = 0; i < 100; i++)
   {
      ObjectDelete(0, "BB_Upper_" + IntegerToString(i));
      ObjectDelete(0, "BB_Middle_" + IntegerToString(i));
      ObjectDelete(0, "BB_Lower_" + IntegerToString(i));
      ObjectDelete(0, "SMA_" + IntegerToString(i));
      ObjectDelete(0, "EMA_" + IntegerToString(i));
   }
   
   if(handleBB != INVALID_HANDLE) IndicatorRelease(handleBB);
   if(handleSMA != INVALID_HANDLE) IndicatorRelease(handleSMA);
   if(handleEMA != INVALID_HANDLE) IndicatorRelease(handleEMA);
   
   ChartRedraw(0);
   Print("BFA Monitor stopped - all handles released");
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastUpdate = 0;
   static datetime lastBarTime = 0;
   datetime currentTime = TimeCurrent();
   
   // Connection health check & heartbeat
   CheckConnectionHealth();
   
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   bool newBar = (currentBarTime != lastBarTime);
   
   if(newBar)
   {
      lastBarTime = currentBarTime;
      if(InpEnableDebugLog)
         Print("📊 New M1 bar detected - scanning all symbols...");
   }
   
   for(int i = 0; i < totalSymbols; i++)
   {
      if(!symbols[i].enabled) continue;
      
      CheckAndUpdateSignal(i, false);
      CheckAndUpdateSignal(i, true);
   }
   
   if(currentTime - lastUpdate > 60)
   {
      int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
      if(visibleBars > 100) visibleBars = 100;
      DrawIndicatorValues(visibleBars);
      lastUpdate = currentTime;
   }
}

//+------------------------------------------------------------------+
void CheckConnectionHealth()
{
   datetime currentTime = TimeCurrent();
   
   // Send heartbeat at regular intervals
   if(currentTime - lastHeartbeat >= InpHeartbeatInterval)
   {
      bool success = SendHeartbeat();
      
      if(success)
      {
         if(!isConnected)
         {
            Print("✅ Reconnected to server!");
            isConnected = true;
            consecutiveFailures = 0;
            
            // Resync all active signals
            ResyncAllSignals();
         }
      }
      else
      {
         consecutiveFailures++;
         
         if(isConnected)
         {
            Print("⚠️ Connection issue detected (attempt ", consecutiveFailures, ")");
         }
         
         if(consecutiveFailures >= InpReconnectAttempts)
         {
            if(isConnected)
            {
               Print("❌ Connection lost after ", consecutiveFailures, " failures");
               isConnected = false;
            }
         }
      }
      
      lastHeartbeat = currentTime;
   }
}

//+------------------------------------------------------------------+
bool SendHeartbeat()
{
   string json = "{\"type\":\"heartbeat\",\"timestamp\":" + IntegerToString((int)TimeCurrent()) + 
                 ",\"active_signals\":" + IntegerToString(ArraySize(activeSignals)) + "}";
   
   return SendToWebSocket(json);
}

//+------------------------------------------------------------------+
void ResyncAllSignals()
{
   Print("🔄 Resyncing ", ArraySize(activeSignals), " active signals...");
   
   int successCount = 0;
   for(int i = 0; i < ArraySize(activeSignals); i++)
   {
      if(!activeSignals[i].active) continue;
      
      string json = "{\"type\":\"signal\"," +
                    "\"symbol\":\"" + activeSignals[i].symbol + "\"," +
                    "\"timeframe\":\"" + activeSignals[i].timeframe + "\"," +
                    "\"trade_type\":\"" + activeSignals[i].tradeType + "\"," +
                    "\"h4_trend\":\"" + activeSignals[i].h4Trend + "\"," +
                    "\"d1_trend\":\"" + activeSignals[i].d1Trend + "\"," +
                    "\"min_lot\":" + DoubleToString(activeSignals[i].minLot, 2) + "," +
                    "\"min_margin\":" + DoubleToString(activeSignals[i].minMargin, 2) + "," +
                    "\"priority\":" + IntegerToString(activeSignals[i].priority) + "," +
                    "\"timestamp\":" + IntegerToString((int)activeSignals[i].timestamp) + "}";
      
      if(SendToWebSocket(json))
         successCount++;
      
      Sleep(100); // Small delay between requests
   }
   
   Print("✅ Resynced ", successCount, "/", ArraySize(activeSignals), " signals");
}

//+------------------------------------------------------------------+
double CalculateBBSlope(double &bbMiddle[], int bars)
{
   if(bars < 2) return 0;
   
   double totalChange = 0;
   int validChanges = 0;
   
   for(int i = 0; i < bars - 1; i++)
   {
      if(bbMiddle[i] != EMPTY_VALUE && bbMiddle[i + 1] != EMPTY_VALUE &&
         bbMiddle[i] != 0 && bbMiddle[i + 1] != 0)
      {
         double change = bbMiddle[i] - bbMiddle[i + 1];
         totalChange += change;
         validChanges++;
      }
   }
   
   if(validChanges == 0) return 0;
   
   return totalChange / validChanges;
}

//+------------------------------------------------------------------+
void CheckAndUpdateSignal(int symbolIndex, bool isH1)
{
   if(!symbols[symbolIndex].enabled) return;
   
   string symbolName = symbols[symbolIndex].name;
   bool isBoom = symbols[symbolIndex].isBoom;
   ENUM_TIMEFRAMES timeframe = isH1 ? PERIOD_H1 : PERIOD_M30;
   
   int hBB = isH1 ? symbols[symbolIndex].hBB_H1 : symbols[symbolIndex].hBB_M30;
   int hSMA = isH1 ? symbols[symbolIndex].hSMA_H1 : symbols[symbolIndex].hSMA_M30;
   int hEMA = isH1 ? symbols[symbolIndex].hEMA_H1 : symbols[symbolIndex].hEMA_M30;
   
   if(hBB == INVALID_HANDLE || hSMA == INVALID_HANDLE || hEMA == INVALID_HANDLE)
   {
      if(InpEnableDebugLog)
         Print("❌ Invalid handles for ", symbolName, " ", EnumToString(timeframe));
      return;
   }
   
   int barsNeeded = MathMax(InpSlopeBars + 2, 5);
   
   int symbolBars = Bars(symbolName, timeframe);
   if(symbolBars < barsNeeded)
   {
      if(InpEnableDebugLog)
         Print("⏳ Not enough bars for ", symbolName, " - need ", barsNeeded, ", have ", symbolBars);
      return;
   }
   
   int bbCalc = BarsCalculated(hBB);
   int smaCalc = BarsCalculated(hSMA);
   int emaCalc = BarsCalculated(hEMA);
   
   if(bbCalc < barsNeeded || smaCalc < barsNeeded || emaCalc < barsNeeded)
   {
      if(InpEnableDebugLog)
         Print("⏳ Waiting for calculations: ", symbolName, 
               " BB:", bbCalc, " SMA:", smaCalc, " EMA:", emaCalc, " (need:", barsNeeded, ")");
      return;
   }
   
   double bbMiddle[], smaValues[], emaValues[];
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(smaValues, true);
   ArraySetAsSeries(emaValues, true);
   
   int bbCopied = CopyBuffer(hBB, 0, 0, barsNeeded, bbMiddle);
   int smaCopied = CopyBuffer(hSMA, 0, 0, barsNeeded, smaValues);
   int emaCopied = CopyBuffer(hEMA, 0, 0, barsNeeded, emaValues);
   
   if(bbCopied != barsNeeded || smaCopied != barsNeeded || emaCopied != barsNeeded)
   {
      if(InpEnableDebugLog)
         Print("❌ Buffer copy failed for ", symbolName, 
               " - BB:", bbCopied, " SMA:", smaCopied, " EMA:", emaCopied, " (need:", barsNeeded, ")");
      return;
   }
   
   bool dataValid = true;
   for(int i = 0; i < MathMin(3, barsNeeded); i++)
   {
      if(bbMiddle[i] == EMPTY_VALUE || bbMiddle[i] == 0 ||
         smaValues[i] == EMPTY_VALUE || smaValues[i] == 0 ||
         emaValues[i] == EMPTY_VALUE || emaValues[i] == 0)
      {
         dataValid = false;
         break;
      }
   }
   
   if(!dataValid)
   {
      if(InpEnableDebugLog)
         Print("❌ Invalid data for ", symbolName, 
               " - BB[0]=", bbMiddle[0], " SMA[0]=", smaValues[0], " EMA[0]=", emaValues[0]);
      return;
   }
   
   double bbSlope = CalculateBBSlope(bbMiddle, InpSlopeBars);
   double absSlope = MathAbs(bbSlope);
   
   bool conditionsMet = false;
   string tradeType = "";
   
   if(isBoom)
   {
      bool condition1_BBSlopeDown = (bbSlope < 0);
      bool condition2_SlopeMeetsThreshold = (absSlope >= InpMinSlopeThreshold);
      bool condition3_EMABelowBB = (emaValues[0] < bbMiddle[0]);
      bool condition4_EMABelowSMA = (emaValues[0] < smaValues[0]);
      
      conditionsMet = condition1_BBSlopeDown && 
                      condition2_SlopeMeetsThreshold && 
                      condition3_EMABelowBB && 
                      condition4_EMABelowSMA;
      tradeType = "SELL";
      
      if(InpEnableDebugLog)
      {
         string tf = EnumToString(timeframe);
         StringReplace(tf, "PERIOD_", "");
         
         Print("🔍 ", symbolName, " ", tf, " BOOM:",
               " Slope:", DoubleToString(bbSlope, 6), (condition1_BBSlopeDown ? "✅" : "❌"),
               " Threshold:", DoubleToString(absSlope, 6), (condition2_SlopeMeetsThreshold ? "✅" : "❌"),
               " EMA<BB:", DoubleToString(emaValues[0] - bbMiddle[0], 2), (condition3_EMABelowBB ? "✅" : "❌"),
               " EMA<SMA:", DoubleToString(emaValues[0] - smaValues[0], 2), (condition4_EMABelowSMA ? "✅" : "❌"),
               " Result:", (conditionsMet ? "VALID" : "INVALID"));
      }
   }
   else
   {
      bool condition1_BBSlopeUp = (bbSlope > 0);
      bool condition2_SlopeMeetsThreshold = (absSlope >= InpMinSlopeThreshold);
      bool condition3_EMAAboveBB = (emaValues[0] > bbMiddle[0]);
      bool condition4_EMAAboveSMA = (emaValues[0] > smaValues[0]);
      
      conditionsMet = condition1_BBSlopeUp && 
                      condition2_SlopeMeetsThreshold && 
                      condition3_EMAAboveBB && 
                      condition4_EMAAboveSMA;
      tradeType = "BUY";
      
      if(InpEnableDebugLog)
      {
         string tf = EnumToString(timeframe);
         StringReplace(tf, "PERIOD_", "");
         
         Print("🔍 ", symbolName, " ", tf, " CRASH:",
               " Slope:", DoubleToString(bbSlope, 6), (condition1_BBSlopeUp ? "✅" : "❌"),
               " Threshold:", DoubleToString(absSlope, 6), (condition2_SlopeMeetsThreshold ? "✅" : "❌"),
               " EMA>BB:", DoubleToString(emaValues[0] - bbMiddle[0], 2), (condition3_EMAAboveBB ? "✅" : "❌"),
               " EMA>SMA:", DoubleToString(emaValues[0] - smaValues[0], 2), (condition4_EMAAboveSMA ? "✅" : "❌"),
               " Result:", (conditionsMet ? "VALID" : "INVALID"));
      }
   }
   
   bool wasValid = isH1 ? symbols[symbolIndex].wasValidH1 : symbols[symbolIndex].wasValidM30;
   bool isValid = conditionsMet;
   
   if(isValid && !wasValid)
   {
      string h4Trend = AnalyzeTrend(symbolName, PERIOD_H4);
      string d1Trend = AnalyzeTrend(symbolName, PERIOD_D1);
      double minLot = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
      double minMargin = CalculateMargin(symbolName, minLot);
      
      AddActiveSignal(symbolName, timeframe, tradeType, h4Trend, d1Trend, minLot, minMargin);
      SendSignalToWebSocket(symbolName, timeframe, tradeType, h4Trend, d1Trend, minLot, minMargin);
      
      string tf = EnumToString(timeframe);
      StringReplace(tf, "PERIOD_", "");
      Print("✅ NEW SIGNAL: ", symbolName, " ", tf, " ", tradeType, 
            " | Slope: ", DoubleToString(bbSlope, 6),
            " | EMA: ", DoubleToString(emaValues[0], 2),
            " | BB: ", DoubleToString(bbMiddle[0], 2),
            " | SMA: ", DoubleToString(smaValues[0], 2));
   }
   else if(!isValid && wasValid && InpInstantRemoval)
   {
      RemoveActiveSignal(symbolName, timeframe);
      RemoveSignalFromWebSocket(symbolName, timeframe);
      
      string tf = EnumToString(timeframe);
      StringReplace(tf, "PERIOD_", "");
      Print("❌ REMOVED: ", symbolName, " ", tf, " (conditions no longer met)");
   }
   
   if(isH1)
   {
      symbols[symbolIndex].isValidH1 = isValid;
      symbols[symbolIndex].wasValidH1 = isValid;
   }
   else
   {
      symbols[symbolIndex].isValidM30 = isValid;
      symbols[symbolIndex].wasValidM30 = isValid;
   }
}

//+------------------------------------------------------------------+
void AddActiveSignal(string symbolName, ENUM_TIMEFRAMES timeframe, string tradeType,
                     string h4Trend, string d1Trend, double minLot, double minMargin)
{
   string displaySymbol = symbolName;
   StringReplace(displaySymbol, " Index", "");
   StringReplace(displaySymbol, " ", "");
   StringToUpper(displaySymbol);
   
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");
   
   // Check if signal already exists
   for(int i = 0; i < ArraySize(activeSignals); i++)
   {
      if(activeSignals[i].symbol == displaySymbol && activeSignals[i].timeframe == tf)
      {
         // Update existing signal
         activeSignals[i].tradeType = tradeType;
         activeSignals[i].h4Trend = h4Trend;
         activeSignals[i].d1Trend = d1Trend;
         activeSignals[i].minLot = minLot;
         activeSignals[i].minMargin = minMargin;
         activeSignals[i].timestamp = TimeCurrent();
         activeSignals[i].active = true;
         return;
      }
   }
   
   // Add new signal
   int newSize = ArraySize(activeSignals) + 1;
   ArrayResize(activeSignals, newSize);
   
   activeSignals[newSize - 1].symbol = displaySymbol;
   activeSignals[newSize - 1].timeframe = tf;
   activeSignals[newSize - 1].tradeType = tradeType;
   activeSignals[newSize - 1].h4Trend = h4Trend;
   activeSignals[newSize - 1].d1Trend = d1Trend;
   activeSignals[newSize - 1].minLot = minLot;
   activeSignals[newSize - 1].minMargin = minMargin;
   activeSignals[newSize - 1].priority = (timeframe == PERIOD_H1) ? 2 : 1;
   activeSignals[newSize - 1].timestamp = TimeCurrent();
   activeSignals[newSize - 1].active = true;
}

//+------------------------------------------------------------------+
void RemoveActiveSignal(string symbolName, ENUM_TIMEFRAMES timeframe)
{
   string displaySymbol = symbolName;
   StringReplace(displaySymbol, " Index", "");
   StringReplace(displaySymbol, " ", "");
   StringToUpper(displaySymbol);
   
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");
   
   for(int i = 0; i < ArraySize(activeSignals); i++)
   {
      if(activeSignals[i].symbol == displaySymbol && activeSignals[i].timeframe == tf)
      {
         activeSignals[i].active = false;
         return;
      }
   }
}

//+------------------------------------------------------------------+
void SendSignalToWebSocket(string symbolName, ENUM_TIMEFRAMES timeframe, string tradeType,
                           string h4Trend, string d1Trend, double minLot, double minMargin)
{
   string displaySymbol = symbolName;
   StringReplace(displaySymbol, " Index", "");
   StringReplace(displaySymbol, " ", "");
   StringToUpper(displaySymbol);
   
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");
   
   int priority = (timeframe == PERIOD_H1) ? 2 : 1;
   datetime currentTime = TimeCurrent();
   
   string json = "{\"type\":\"signal\"," +
                 "\"symbol\":\"" + displaySymbol + "\"," +
                 "\"timeframe\":\"" + tf + "\"," +
                 "\"trade_type\":\"" + tradeType + "\"," +
                 "\"h4_trend\":\"" + h4Trend + "\"," +
                 "\"d1_trend\":\"" + d1Trend + "\"," +
                 "\"min_lot\":" + DoubleToString(minLot, 2) + "," +
                 "\"min_margin\":" + DoubleToString(minMargin, 2) + "," +
                 "\"priority\":" + IntegerToString(priority) + "," +
                 "\"timestamp\":" + IntegerToString((int)currentTime) + "}";
   
   SendToWebSocket(json);
}

//+------------------------------------------------------------------+
void RemoveSignalFromWebSocket(string symbolName, ENUM_TIMEFRAMES timeframe)
{
   string displaySymbol = symbolName;
   StringReplace(displaySymbol, " Index", "");
   StringReplace(displaySymbol, " ", "");
   StringToUpper(displaySymbol);
   
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");
   
   string json = "{\"type\":\"remove_signal\"," +
                 "\"action\":\"remove\"," +
                 "\"symbol\":\"" + displaySymbol + "\"," +
                 "\"timeframe\":\"" + tf + "\"}";
   
   if(InpEnableDebugLog)
      Print("📤 Sending removal: ", json);
   SendToWebSocket(json);
}

//+------------------------------------------------------------------+
bool SendToWebSocket(string json

{
   string url = InpWebSocketUrl;
   StringReplace(url, "ws://", "http://");
   StringReplace(url, "wss://", "https://");
   
   char post[], result[];
   
   int len = StringToCharArray(json, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0)
      ArrayResize(post, len - 1);
   
   string headers = "Content-Type: application/json\r\n";
   
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, headers);
   
   if(res == -1)
   {
      int error = GetLastError();
      
      if(InpEnableDebugLog)
         Print("❌ WebRequest ERROR: ", error);
      
      if(error == 4060)
      {
         Print("⚠️ WebRequest NOT enabled! Add to whitelist: ", url);
      }
      else if(error == 5200)
      {
         if(InpEnableDebugLog)
            Print("⚠️ Connection failed: ", url);
      }
      
      return false;
   }
   else if(res == 200)
   {
      lastSuccessfulRequest = TimeCurrent();
      string response = CharArrayToString(result);
      if(StringLen(response) > 0 && InpEnableDebugLog)
         Print("✅ Server: ", response);
      return true;
   }
   else
   {
      if(InpEnableDebugLog)
      {
         Print("⚠️ HTTP ", res);
         string response = CharArrayToString(result);
         if(StringLen(response) > 0)
            Print("Response: ", response);
      }
      return false;
   }
}

//+------------------------------------------------------------------+
string AnalyzeTrend(string symbolName, ENUM_TIMEFRAMES timeframe)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(symbolName, timeframe, 0, InpBBPeriod + InpEMAPeriod + 5, rates);
   if(copied < InpBBPeriod + 5) return "No Data";
   
   double bbMiddle[];
   ArrayResize(bbMiddle, InpBBPeriod);
   ArraySetAsSeries(bbMiddle, true);
   
   for(int i = 0; i < 5; i++)
   {
      double sum = 0;
      for(int j = 0; j < InpBBPeriod; j++)
         sum += rates[i + j].close;
      bbMiddle[i] = sum / InpBBPeriod;
   }
   
   double emaValues[];
   ArrayResize(emaValues, copied);
   ArraySetAsSeries(emaValues, false);
   
   double multiplier = 2.0 / (InpEMAPeriod + 1);
   emaValues[0] = rates[copied - 1].close;
   
   for(int i = 1; i < copied; i++)
      emaValues[i] = (rates[copied - 1 - i].close * multiplier) + (emaValues[i - 1] * (1 - multiplier));
   
   ArraySetAsSeries(emaValues, true);
   
   double bbSlope = bbMiddle[0] - bbMiddle[1];
   double emaDistance = 0;
   if(bbMiddle[0] != 0)
      emaDistance = ((emaValues[0] - bbMiddle[0]) / bbMiddle[0]) * 100;
   
   double absDistance = MathAbs(emaDistance);
   string strength = "";
   
   if(absDistance > 0.15) strength = "Strong";
   else if(absDistance > 0.08) strength = "Moderate";
   else if(absDistance > 0.03) strength = "Weak";
   else strength = "Very Weak";
   
   if(bbSlope > 0) return strength + " Uptrend";
   else if(bbSlope < 0) return strength + " Downtrend";
   else return "Sideways";
}

//+------------------------------------------------------------------+
double CalculateMargin(string symbolName, double lotSize)
{
   double margin = 0;
   double price = SymbolInfoDouble(symbolName, SYMBOL_ASK);
   if(price == 0) return 0;
   
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbolName, lotSize, price, margin))
   {
      double contractSize = SymbolInfoDouble(symbolName, SYMBOL_TRADE_CONTRACT_SIZE);
      long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
      if(leverage == 0) leverage = 1;
      margin = (contractSize * lotSize * price) / leverage;
   }
   
   return margin;
}
//+------------------------------------------------------------------+
