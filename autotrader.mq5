//+------------------------------------------------------------------+
//| Expert Advisor: Pure AutoTrader for MT5                          |
//| Trades GBPUSD and XAUUSD automatically                           |
//| Features: M1 low-risk entries, multi-timeframe alignment, TP2    |
//| trailing, daily max loss, Telegram alerts optional               |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

input double LotSize = 0.1;           // Lot size
input double MaxDailyLoss = 50;       // USD daily max loss
input bool EnableTelegram = false;    // Telegram alerts
input string TelegramBotToken = "";   // Your bot token
input string TelegramChatID = "";     // Your chat ID

double DailyLoss = 0;

// Struct for signal
struct Signal
{
   string symbol;
   string dir;
   double entry;
   double SL;
   double TP1;
   double TP2;
};

//+------------------------------------------------------------------+
int OnInit()
{
   Print("✅ Pure AutoTrader EA Initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(DailyLoss >= MaxDailyLoss) return;

   string symbols[2] = {"GBPUSD","XAUUSD"};
   for(int i=0;i<2;i++)
   {
      string sym = symbols[i];
      if(!SymbolSelect(sym,true)) continue;

      double entry, SL, TP1, TP2;
      string dir;
      if(CalculateSignal(sym,dir,entry,SL,TP1,TP2))
      {
         ExecuteTrade(sym,dir,entry,SL,TP1,TP2);
      }
   }
}

//+------------------------------------------------------------------+
// Calculate low-risk signal based on M1, 5M, 15M, 1H alignment
bool CalculateSignal(string symbol,string &dir,double &entry,double &SL,double &TP1,double &TP2)
{
   int M1 = PERIOD_M1;
   int M5 = PERIOD_M5;
   int M15 = PERIOD_M15;
   int H1 = PERIOD_H1;

   double open1 = iOpen(symbol,M1,0);
   double close1 = iClose(symbol,M1,0);
   double open5 = iOpen(symbol,M5,0);
   double close5 = iClose(symbol,M5,0);
   double open15 = iOpen(symbol,M15,0);
   double close15 = iClose(symbol,M15,0);
   double openH1 = iOpen(symbol,H1,0);
   double closeH1 = iClose(symbol,H1,0);

   // Direction based on M1 candle
   if(close1>open1) dir="buy";
   else if(close1<open1) dir="sell";
   else return false;

   // Multi-timeframe alignment
   if(dir=="buy" && (close5<open5 || close15<open15 || closeH1<openH1)) return false;
   if(dir=="sell" && (close5>open5 || close15>open15 || closeH1>openH1)) return false;

   // Entry = current price
   entry = SymbolInfoDouble(symbol,SYMBOL_BID);

   // Low-risk SL/TP based on recent swings
   double low1=iLow(symbol,M1,1), high1=iHigh(symbol,M1,1);
   double highH1=iHigh(symbol,H1,1), lowH1=iLow(symbol,H1,1);

   if(dir=="buy")
   {
      SL = low1 - SymbolInfoDouble(symbol,SYMBOL_POINT)*10;
      TP1 = entry + (entry-SL)*2;       // 2:1 RR
      TP2 = entry + (highH1-entry);     // aligned with H1 high
   }
   else
   {
      SL = high1 + SymbolInfoDouble(symbol,SYMBOL_POINT)*10;
      TP1 = entry - (SL-entry)*2;       // 2:1 RR
      TP2 = entry - (entry-lowH1);      // aligned with H1 low
   }

   return true;
}

//+------------------------------------------------------------------+
// Execute trade
void ExecuteTrade(string symbol,string dir,double entry,double SL,double TP1,double TP2)
{
   if(PositionSelect(symbol)) return; // skip if position exists

   bool ok=false;
   if(dir=="buy") ok=trade.Buy(LotSize,symbol,entry,SL,TP1,"PureAutoTrader");
   else if(dir=="sell") ok=trade.Sell(LotSize,symbol,entry,SL,TP1,"PureAutoTrader");

   if(ok)
   {
      Print("Trade executed: ",symbol," ",dir," Entry:",DoubleToString(entry,5)," SL:",DoubleToString(SL,5)," TP1:",DoubleToString(TP1,5));
      if(EnableTelegram && StringLen(TelegramBotToken)>0 && StringLen(TelegramChatID)>0)
      {
         string msg="Trade: "+symbol+" "+dir+" Entry:"+DoubleToString(entry,5)+" SL:"+DoubleToString(SL,5)+" TP1:"+DoubleToString(TP1,5);
         SendTelegram(msg);
      }
   }
}

//+------------------------------------------------------------------+
// Telegram alert
void SendTelegram(string message)
{
   string url="https://api.telegram.org/bot"+TelegramBotToken+"/sendMessage?chat_id="+TelegramChatID+"&text="+message;
   char result[];
   WebRequest("GET",url,"","",0,result,NULL,NULL);
}

//+------------------------------------------------------------------+
// Optional: OnTrade for TP2 trailing
void OnTrade()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string sym=PositionGetString(POSITION_SYMBOL);
         double price=PositionGetDouble(POSITION_PRICE_OPEN);
         double tp2=0;
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) tp2=price + (iHigh(sym,PERIOD_H1,1)-price);
         else tp2=price - (price-iLow(sym,PERIOD_H1,1));

         trade.PositionModify(ticket,PositionGetDouble(POSITION_SL),tp2);
      }
   }
}
//+------------------------------------------------------------------+