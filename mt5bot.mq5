//+------------------------------------------------------------------+
//|                                      BFA_REALTIME_MONITOR.mq5    |
//|                              Real-time WebSocket Communication   |
//+------------------------------------------------------------------+
#property copyright "BFA REALTIME MONITOR"
#property version   "3.00"
#property strict

//--- Input Parameters
input group "=== WEBSOCKET SETTINGS ==="
input string InpWebSocketUrl = "ws://localhost:8080"; // WebSocket Server URL (change to your server)
input bool InpInstantRemoval = true; // Instantly remove signals when conditions not met

input group "=== INDICATOR SETTINGS ==="
input int InpBBPeriod = 20;
input double InpBBDeviation = 2.0;
input int InpSMAPeriod = 10;
input int InpEMAPeriod = 10;

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

//--- Global Variables
struct SymbolData
{
   string name;
   bool enabled;
   bool isBoom;
   bool wasValidM30;   // Previous state
   bool wasValidH1;
   bool isValidM30;    // Current state
   bool isValidH1;
};

SymbolData symbols[];
int totalSymbols = 12;
int handleBB, handleSMA, handleEMA;

//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(symbols, totalSymbols);
   
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
   
   handleBB = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   handleSMA = iMA(_Symbol, PERIOD_CURRENT, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   handleEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleBB == INVALID_HANDLE || handleSMA == INVALID_HANDLE || handleEMA == INVALID_HANDLE)
   {
      Print("Error creating indicators!");
      return(INIT_FAILED);
   }
   
   ChartIndicatorAdd(0, 0, handleBB);
   ChartIndicatorAdd(0, 0, handleSMA);
   ChartIndicatorAdd(0, 0, handleEMA);
   
   CreateIndicatorLines();
   
   Print("╔════════════════════════════════════════╗");
   Print("║  BFA REALTIME MONITOR INITIALIZED      ║");
   Print("╚════════════════════════════════════════╝");
   Print("📡 WebSocket: ", InpWebSocketUrl);
   Print("📊 Monitoring: ", GetEnabledSymbolsCount(), " symbols");
   Print("⚡ Mode: INSTANT (Zero delay)");
   
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
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastUpdate = 0;
   datetime currentTime = TimeCurrent();
   
   if(currentTime - lastUpdate > 60)
   {
      int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
      if(visibleBars > 100) visibleBars = 100;
      DrawIndicatorValues(visibleBars);
      lastUpdate = currentTime;
   }
   
   // Check all symbols on every tick for instant response
   for(int i = 0; i < totalSymbols; i++)
   {
      if(!symbols[i].enabled) continue;
      
      CheckAndUpdateSignal(symbols[i].name, PERIOD_M30, symbols[i].isBoom, i, false);
      CheckAndUpdateSignal(symbols[i].name, PERIOD_H1, symbols[i].isBoom, i, true);
   }
}

//+------------------------------------------------------------------+
void CheckAndUpdateSignal(string symbolName, ENUM_TIMEFRAMES timeframe, bool isBoom, int symbolIndex, bool isH1)
{
   int hBB = iBands(symbolName, timeframe, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   int hSMA = iMA(symbolName, timeframe, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   int hEMA = iMA(symbolName, timeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hBB == INVALID_HANDLE || hSMA == INVALID_HANDLE || hEMA == INVALID_HANDLE)
   {
      if(hBB != INVALID_HANDLE) IndicatorRelease(hBB);
      if(hSMA != INVALID_HANDLE) IndicatorRelease(hSMA);
      if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
      return;
   }
   
   if(BarsCalculated(hBB) < 3 || BarsCalculated(hSMA) < 3 || BarsCalculated(hEMA) < 3)
   {
      IndicatorRelease(hBB);
      IndicatorRelease(hSMA);
      IndicatorRelease(hEMA);
      return;
   }
   
   double bbMiddle[], smaValues[], emaValues[];
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(smaValues, true);
   ArraySetAsSeries(emaValues, true);
   
   if(CopyBuffer(hBB, 0, 0, 3, bbMiddle) != 3 ||
      CopyBuffer(hSMA, 0, 0, 3, smaValues) != 3 ||
      CopyBuffer(hEMA, 0, 0, 3, emaValues) != 3)
   {
      IndicatorRelease(hBB);
      IndicatorRelease(hSMA);
      IndicatorRelease(hEMA);
      return;
   }
   
   bool conditionsMet = false;
   string tradeType = "";
   
   if(isBoom)
   {
      conditionsMet = (bbMiddle[0] < bbMiddle[1]) && (emaValues[0] < bbMiddle[0]) && (emaValues[0] < smaValues[0]);
      tradeType = "SELL";
   }
   else
   {
      conditionsMet = (bbMiddle[0] > bbMiddle[1]) && (emaValues[0] > bbMiddle[0]) && (emaValues[0] > smaValues[0]);
      tradeType = "BUY";
   }
   
   // Get previous and current states
   bool wasValid = isH1 ? symbols[symbolIndex].wasValidH1 : symbols[symbolIndex].wasValidM30;
   bool isValid = conditionsMet;
   
   // Update current state
   if(isH1)
      symbols[symbolIndex].isValidH1 = isValid;
   else
      symbols[symbolIndex].isValidM30 = isValid;
   
   // Detect state changes
   if(isValid && !wasValid)
   {
      // NEW SIGNAL - Send immediately
      string h4Trend = AnalyzeTrend(symbolName, PERIOD_H4);
      string d1Trend = AnalyzeTrend(symbolName, PERIOD_D1);
      double minLot = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
      double minMargin = CalculateMargin(symbolName, minLot);
      
      SendSignalToWebSocket(symbolName, timeframe, tradeType, h4Trend, d1Trend, minLot, minMargin);
      
      Print("🚨 NEW: ", symbolName, " ", EnumToString(timeframe), " ", tradeType);
   }
   else if(!isValid && wasValid && InpInstantRemoval)
   {
      // SIGNAL INVALID - Remove immediately
      RemoveSignalFromWebSocket(symbolName, timeframe);
      
      Print("❌ REMOVED: ", symbolName, " ", EnumToString(timeframe));
   }
   else if(isValid && wasValid)
   {
      // SIGNAL STILL VALID - Update (refresh)
      string h4Trend = AnalyzeTrend(symbolName, PERIOD_H4);
      string d1Trend = AnalyzeTrend(symbolName, PERIOD_D1);
      double minLot = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
      double minMargin = CalculateMargin(symbolName, minLot);
      
      SendSignalToWebSocket(symbolName, timeframe, tradeType, h4Trend, d1Trend, minLot, minMargin);
   }
   
   // Update previous state
   if(isH1)
      symbols[symbolIndex].wasValidH1 = isValid;
   else
      symbols[symbolIndex].wasValidM30 = isValid;
   
   IndicatorRelease(hBB);
   IndicatorRelease(hSMA);
   IndicatorRelease(hEMA);
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
   
   string json = "{";
   json += "\"type\":\"signal\",";
   json += "\"symbol\":\"" + displaySymbol + "\",";
   json += "\"timeframe\":\"" + tf + "\",";
   json += "\"trade_type\":\"" + tradeType + "\",";
   json += "\"h4_trend\":\"" + h4Trend + "\",";
   json += "\"d1_trend\":\"" + d1Trend + "\",";
   json += "\"min_lot\":" + DoubleToString(minLot, 2) + ",";
   json += "\"min_margin\":" + DoubleToString(minMargin, 2);
   json += "}";
   
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
   
   string json = "{";
   json += "\"type\":\"remove_signal\",";
   json += "\"symbol\":\"" + displaySymbol + "\",";
   json += "\"timeframe\":\"" + tf + "\"";
   json += "}";
   
   SendToWebSocket(json);
}

//+------------------------------------------------------------------+
void SendToWebSocket(string json)
{
   // Note: MT5 doesn't natively support WebSocket protocol
   // We use HTTP POST as a workaround - the server will handle it
   string url = InpWebSocketUrl;
   StringReplace(url, "ws://", "http://");
   StringReplace(url, "wss://", "https://");
   
   char post[], result[];
   StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, ArraySize(post) - 1);
   
   string headers = "Content-Type: application/json\r\n";
   
   int res = WebRequest("POST", url, headers, 2000, post, result, headers);
   
   if(res == -1)
   {
      int error = GetLastError();
      if(error == 4060)
         Print("⚠️ Enable WebRequest for: ", url);
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
int GetEnabledSymbolsCount()
{
   int count = 0;
   for(int i = 0; i < totalSymbols; i++)
      if(symbols[i].enabled) count++;
   return count;
}
//+------------------------------------------------------------------+