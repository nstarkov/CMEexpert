//+------------------------------------------------------------------+
//|                                                        first.mq4 |
//|                        Copyright 2015, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2015, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
//--- input parameters
input uint     fileRefresh=5;

#define MAX_LINE_IN_FILE 256
#define NORMAL_COUNT_COLUMN 14
#define MAX_ACTIVE_ORDERS 20

#define EUR_CORECTION_SL 0.0003 
#define AUD_CORECTION_SL 0.0012

#define EUR_COMPRESSING 0.00160
#define AUD_COMPRESSING 0.00170

enum strikeType
{
   INCORRECT_TYPE,
   CALL_TYPE,
   PUT_TYPE
};

struct strike
{
   strikeType type;
   double value;
   int volume;
   int openInterest;
   double settPrice;
};

struct cmeReport
{
   MqlDateTime date;
   string fileName;
   bool isValid;
   strike strikePutArr[];
   int strikePutCount;
   strike strikeCallArr[];
   int strikeCallCount;
};

enum
{
   MAJOR_CALL,
   MAJOR_PUT,
   MAJOR_CENTER,
   MAJOR_ALL
};

enum todayTrend
{
   TODAY_PUT,
   TODAY_CALL,
   TODAY_NOTSET
};

const string dirResFiles = "CME\\";
cmeReport curReport;
double majorLines[MAJOR_ALL];

int openedOrders[2];
int openedOrdersCount = 0;

int activeOrders[MAX_ACTIVE_ORDERS];
int activeOrdersCount = 0;

double closeBarValue = 0;
int firstActivatedTime = 0;

bool isAllOrdersActivated = false;

string Date2FileName(const MqlDateTime& a_date)
{
   string year = IntegerToString(a_date.year);
   string mon = IntegerToString(a_date.mon);
   string day = IntegerToString(a_date.day);
   string fileName = day + "." + mon + "." + year + ".txt";
   return fileName;
}

int ReadFileToArray(string &a_array[],string a_fileName)
{
   if (!FileIsExist(curReport.fileName)) {
 //     Print ("FileIsNotExist");
      return 0;
   }

   int fileHandle = FileOpen(curReport.fileName,FILE_READ);
   if (fileHandle == INVALID_HANDLE) {
      Print("Can't open file!");
      return 0;
   }
   ArrayResize(a_array, MAX_LINE_IN_FILE);
   int count = 0;
   while(!FileIsEnding(fileHandle)){
      a_array[count] = FileReadString(fileHandle);
      count++;
   }
   FileClose(fileHandle);
   return count;
}

double GetStrikeValue(strikeType a_type, string a_strike, double a_setPrice)
{
   int tmp = (StringCompare(Symbol(), "EURUSD") != 0) ? 100 : 10;
   double setPrice = a_setPrice * tmp;
   double strikeValue = StringToDouble(a_strike)*10;
   setPrice = setPrice * ((a_type == CALL_TYPE) ? 1 : -1);
   strikeValue = (strikeValue + setPrice)/10000;
   return strikeValue;
}

int Parse(string &a_array[],int a_linesCount, strike &a_strikeArr[])
{
   ushort usep = ' ';
   strikeType curType = INCORRECT_TYPE;
   int strikeCount = a_linesCount - 2;
   ArrayResize(a_strikeArr, strikeCount);
   int realStrikeCount = 0;

   for (int i=0; i<a_linesCount ;i++) {
      string splitString[];
      int splitCount = StringSplit(a_array[i], usep, splitString);
      if (splitCount == 0) {
         continue;
      }
      if (splitCount < NORMAL_COUNT_COLUMN) {
         if (!StringCompare(splitString[0], "CALL")) {
            curType = CALL_TYPE;
         } else {
            curType = PUT_TYPE;
         }
         continue;
      }
      if (curType == INCORRECT_TYPE) {
         Print("Error of parsing: curType == INCORRECT_TYPE.");
         break;
      }
      if (realStrikeCount == strikeCount) {
         Print ("Error of parsing: realStrikeCount != strikeCount.");
         break;
      }
      
      if (!StringCompare(splitString[5], "CAB")) {
         continue;
      }
      StringReplace(splitString[5],"+","");
      StringReplace(splitString[5],"-","");
      double settPrice = StringToDouble(splitString[5]);
      
      double value = GetStrikeValue(curType, splitString[0], settPrice);
      int openInterest = 0;
      if (StringCompare(splitString[10], "----") != 0){
         openInterest = StringToInteger(splitString[10]);
      }
      int volume = 0;
      if (StringCompare(splitString[9], "----") != 0) {
         volume = StringToInteger(splitString[9]);
      }
      value = NormalizeDouble(value,Digits());
      
      a_strikeArr[realStrikeCount].volume = volume;
      a_strikeArr[realStrikeCount].value = value;
      a_strikeArr[realStrikeCount].type = curType;
      a_strikeArr[realStrikeCount].openInterest = openInterest;  
      a_strikeArr[realStrikeCount].settPrice = settPrice;
      //Print(a_strikeArr[realStrikeCount].type," Strike: ", splitString[0], " value: " , value," volume: ", volume," openInterest: ", openInterest," settPrice: ", settPrice);
      realStrikeCount++;   
   }
   
   return realStrikeCount;
}
   
void CalcMajorLines(strike &a_strike[],int a_strikeCount)
{
   long maxCall = 0;
   long maxPut = 0;
   majorLines[MAJOR_CALL] = 0;
   majorLines[MAJOR_PUT] = 0;
   for(int i=0;i<a_strikeCount;i++) {
      long v = a_strike[i].volume * a_strike[i].settPrice;
      if (a_strike[i].type == CALL_TYPE && maxCall < v) {
         majorLines[MAJOR_CALL] = a_strike[i].value;
         //Print("NEW CALL MAX: ", a_strike[i].value, " volume:", a_strike[i].volume, " settPrice:", a_strike[i].settPrice);
         maxCall = v;
      } else if (a_strike[i].type == PUT_TYPE && maxPut < v) {
         majorLines[MAJOR_PUT] = a_strike[i].value;
         //Print("NEW PUT MAX: ", a_strike[i].value, " volume:", a_strike[i].volume, " settPrice:", a_strike[i].settPrice);
         maxPut = v;
      }
   }

   majorLines[MAJOR_CENTER] = NormalizeDouble(majorLines[MAJOR_PUT] + (majorLines[MAJOR_CALL] - majorLines[MAJOR_PUT])/2,Digits());
   Print ("CME Resource file loaded.");
   Print ("CALL: ", majorLines[MAJOR_CALL], ", CENTER: ", majorLines[MAJOR_CENTER], ", PUT: ", majorLines[MAJOR_PUT]);
}
//+------------------------------------------------------------------+
//| Read file                                                        |
//+------------------------------------------------------------------+
void LoadNewReport()
{
   curReport.isValid = false;
   curReport.strikeCallCount = 0;
   curReport.strikePutCount = 0;
   
   TimeCurrent(curReport.date);
   curReport.fileName = dirResFiles + Symbol() + "\\" + Date2FileName(curReport.date);
   //Print("File Name:", curReport.fileName);
   string fileArray[];
   int lines = ReadFileToArray(fileArray, curReport.fileName);
   curReport.isValid = (lines) ? true : false;
   if(!curReport.isValid) {
      return;
   }
   strike arr[]; 
   int count = Parse(fileArray, lines, arr);
   if (!count) {
      curReport.isValid = false;
      return;
   }
   
   CalcMajorLines(arr, count);
   
   int callTypeCount = 0;
   for ( ; arr[callTypeCount].type == CALL_TYPE; callTypeCount++) {}
   ArrayResize(curReport.strikeCallArr, callTypeCount);
   //Print("Size strikeCallArr: ", callTypeCount);
   ArrayResize(curReport.strikePutArr, count - callTypeCount);
   
   for ( int i=0; i<count; i++) 
   {
      if (!arr[i].volume || !arr[i].settPrice)
      {
         continue;
      }
      if (arr[i].type == CALL_TYPE)
      {
         bool isFound = false;
         for (int j=0; j<curReport.strikeCallCount; j++)
         {
            if (MathAbs(arr[i].value - curReport.strikeCallArr[j].value) < ((StringCompare(Symbol(), "EURUSD") != 0) ? AUD_COMPRESSING : EUR_COMPRESSING)) 
            {
               isFound = true;
               double k = (curReport.strikeCallArr[j].volume * curReport.strikeCallArr[j].settPrice)/(arr[i].volume*arr[i].settPrice);
               if (k >= 1) 
               {
                  double oneStep = (arr[i].value - curReport.strikeCallArr[j].value)/(NormalizeDouble(k,0) + 1);
                  curReport.strikeCallArr[j].value += oneStep;
               } 
               else if (k)
               {
                  double oneStep = (arr[i].value - curReport.strikeCallArr[j].value)/(NormalizeDouble(1/k,0)+ 1);
                  curReport.strikeCallArr[j].value += oneStep * NormalizeDouble(1/k,0);                  
               }
               curReport.strikeCallArr[j].value = NormalizeDouble(curReport.strikeCallArr[j].value,Digits());
               curReport.strikeCallArr[j].settPrice += arr[i].settPrice;
               curReport.strikeCallArr[j].volume += arr[i].volume;
               break;
            }
         }
         if (!isFound)
         {
            curReport.strikeCallArr[curReport.strikeCallCount] = arr[i];
            //Print("curReport.strikeCallCount: ", curReport.strikeCallCount);
            curReport.strikeCallCount++;
         }
      } 
      else
      {
         bool isFound = false;
         for (int j=0; j<curReport.strikePutCount; j++)
         {
            if (MathAbs(arr[i].value - curReport.strikePutArr[j].value) < ((StringCompare(Symbol(), "EURUSD") != 0) ? AUD_COMPRESSING : EUR_COMPRESSING)) 
            {
               double k = (curReport.strikePutArr[j].settPrice*curReport.strikePutArr[j].volume)/(arr[i].settPrice*arr[i].volume);
               if (k >= 1) 
               {
                  double oneStep = (arr[i].value - curReport.strikePutArr[j].value)/(NormalizeDouble(k,0) + 1);
                  curReport.strikePutArr[j].value += oneStep;
               } 
               else if (k)
               {
                  double oneStep = (arr[i].value - curReport.strikePutArr[j].value)/(NormalizeDouble(1/k,0)+ 1);
                  curReport.strikePutArr[j].value += oneStep * NormalizeDouble(1/k,0);                  
               }
               curReport.strikePutArr[j].value = NormalizeDouble(curReport.strikePutArr[j].value,Digits());
               curReport.strikePutArr[j].settPrice += arr[i].settPrice;
               curReport.strikePutArr[j].volume += arr[i].volume;
               isFound = true;
               break;
            }
         }
         if (!isFound)
         {
            curReport.strikePutArr[curReport.strikePutCount] = arr[i];
            curReport.strikePutCount++;
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
//---
   LoadNewReport();
//---
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }

void OpenOrders(bool isSell)
{
   double MA = iMA(NULL,0,280,0,MODE_SMA,PRICE_CLOSE,0);
   if (!openedOrdersCount) 
   {
      double lotSize = NormalizeDouble((AccountFreeMargin()/300000),2);
      lotSize = (lotSize < 0.01) ? 0.01 : lotSize;
      //lotSize = 0.1;
      if (isSell) 
      {
         for(int i=0; i < curReport.strikeCallCount; i++) 
         {
            bool maflag = (StringCompare(Symbol(), "EURUSD") != 0) ? true : (curReport.strikeCallArr[i].value > MA);
            if ( curReport.strikeCallArr[i].value > (majorLines[MAJOR_CENTER] + 0.0005) &&
               curReport.strikeCallArr[i].value > (Bid + 0.0005) && maflag &&
               openedOrdersCount < 2) 
            {
               double TP ;//= (curReport.strikeCallArr[i].value - majorLines[MAJOR_CENTER] > 0.0005) ? majorLines[MAJOR_CENTER] : curReport.strikeCallArr[i].value + 0.0005;
               double SL = curReport.strikeCallArr[i+2-openedOrdersCount].value;
               if ((SL - ((StringCompare(Symbol(), "EURUSD") != 0) ? AUD_CORECTION_SL : EUR_CORECTION_SL)) >= curReport.strikePutArr[i].value + 0.0005)
               {
                  SL -= ((StringCompare(Symbol(), "EURUSD") != 0) ? AUD_CORECTION_SL : EUR_CORECTION_SL);
               }
               TP = 0; //(StringCompare(Symbol(), "EURUSD") != 0) ? curReport.strikeCallArr[i].value - 4*(SL - curReport.strikeCallArr[i].value) : 0;
               openedOrders[openedOrdersCount] = OrderSend(Symbol(), OP_SELLLIMIT, 
                                                (openedOrdersCount)? 2*lotSize: lotSize, curReport.strikeCallArr[i].value + 0.0000, 
                                                0, SL, TP);
               if (openedOrders[openedOrdersCount] < 0) 
               {
                  Alert ("Sell Error: "+GetLastError());
               } 
               else 
               {
                  openedOrdersCount++;
               }
            }
         }
      } 
      else
      {
         for(int i=curReport.strikePutCount-1; i>=0 ;i--) 
         {
            bool maflag = (StringCompare(Symbol(), "EURUSD") != 0) ? true : (curReport.strikePutArr[i].value < MA);
            if ( curReport.strikePutArr[i].value < (majorLines[MAJOR_CENTER] - 0.0005) &&
                  (curReport.strikePutArr[i].value + 0.0005) < Ask && maflag &&
                  openedOrdersCount < 2) 
            {
               double TP ;//= (majorLines[MAJOR_CENTER] - curReport.strikePutArr[i].value > 0.0005) ? majorLines[MAJOR_CENTER] : curReport.strikeCallArr[i].value - 0.0005;
               double SL = curReport.strikePutArr[i-2+openedOrdersCount].value;
               if ((SL + ((StringCompare(Symbol(), "EURUSD") != 0) ? AUD_CORECTION_SL : EUR_CORECTION_SL)) <= curReport.strikePutArr[i].value - 0.0005)
               {
                  SL += ((StringCompare(Symbol(), "EURUSD") != 0) ? AUD_CORECTION_SL : EUR_CORECTION_SL);
               }
               TP =  0; //(StringCompare(Symbol(), "EURUSD") != 0) ? curReport.strikePutArr[i].value + 4*(curReport.strikePutArr[i].value - SL) : 0;
               openedOrders[openedOrdersCount] = OrderSend(Symbol(), OP_BUYLIMIT, 
                                                (openedOrdersCount)? 2*lotSize: lotSize, curReport.strikePutArr[i].value - 0.0000, 
                                                0, SL, TP);
               if (openedOrders[openedOrdersCount]<0) 
               {
                  Alert( "Bay ERROR: " + GetLastError());
               } 
               else 
               {
                  openedOrdersCount++;
               }
            }
         }
      }
   }
}

void CloseOrders()
{
   double TP = 0;
   for (int i=0; i<openedOrdersCount; i++) 
   {
      if(OrderSelect(openedOrders[i], SELECT_BY_TICKET)) 
      {
         if (OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT)
         {
            if(!OrderDelete(openedOrders[i])) 
            {
               Alert("OrderDelete: "+GetLastError());
            }
            continue;
         }
         else 
         {
            if (!OrderCloseTime())
            { 
                     if (!OrderClose(openedOrders[i],OrderLots(), (OrderType()==OP_BUY) ? Bid : Ask, 2))
                     {
                        Alert("OrderClose: "+GetLastError());
                     }
                     else
                     {
                        activeOrdersCount--;
                     }
               /*if (OrderProfit() < 0) 
               {
                  TP = OrderOpenPrice() + 0.00001;
                  double SL = (OrderType() == OP_BUY) ? OrderOpenPrice() - (OrderOpenPrice() - OrderStopLoss())/2 : OrderOpenPrice() + (OrderStopLoss() - OrderOpenPrice())/2;
                  if(!OrderModify(openedOrders[i], OrderOpenPrice(), SL, TP, 0))
                  { 
                     if( GetLastError() == 130 )
                     {
                        if (!OrderClose(openedOrders[i],OrderLots(), (OrderType()==OP_BUY) ? Bid : Ask, 2))
                        {
                           Alert("OrderClose: " + GetLastError());
                        }
                        continue;
                     }
                     Alert("OrderModify: "+ GetLastError());
                  } 
               }
               else
               {
                  if (!TP)
                  {
                     if (!OrderClose(openedOrders[i],OrderLots(), (OrderType()==OP_BUY) ? Bid : Ask, 2))
                     {
                        Alert("OrderClose: "+GetLastError());
                     }
                     else
                     {
                        activeOrdersCount--;
                     }
                  }
                  else
                  {
                     if(!OrderModify(openedOrders[i], OrderOpenPrice(), OrderStopLoss(), TP, 0))
                     { 
                        Alert("OrderModify: "+GetLastError());
                     }
                  }
               }*/
            }
         }
      } 
      else 
      {
          Alert("OrderSelect: " +GetLastError());
      }
   }
   openedOrdersCount = 0;
}

void FindActiveOrders()
{
   for (int i=0; i<openedOrdersCount; i++) 
   {
      if(OrderSelect(openedOrders[i], SELECT_BY_TICKET))
      {
         if (OrderType() == OP_BUY || OrderType() == OP_SELL)
         {
            if(!OrderCloseTime())
            {
               bool isFound = false;
               for(int j=0; j<activeOrdersCount ;j++)
               {
                  if (activeOrders[j] == openedOrders[i])
                  {
                     isFound = true;
                     break;
                  }    
               }
               if(!isFound)
               {  
                  activeOrders[activeOrdersCount] = openedOrders[i];
                  if (!activeOrdersCount)
                  {
                     MqlDateTime curTime;
                     TimeCurrent(curTime);
                     firstActivatedTime = curTime.hour;
                  }
                  Print("Add to active: ", openedOrders[i], " Count: ", activeOrdersCount);
                  activeOrdersCount++;
                  
               }
            }
         }
      }
      else 
      {
         Alert("OrderSelect: " +GetLastError());
      }
   }
}

void TrailingStop(bool isSell)
{
   for(int i=0; i<activeOrdersCount; i++)
   {
      if(OrderSelect(activeOrders[i], SELECT_BY_TICKET))
      {
         if(isSell)
         {
            if(OrderOpenPrice() > High[1])
            {
               if(!OrderCloseTime())
               {
                  if(!OrderModify(activeOrders[i], OrderOpenPrice(), High[1], OrderTakeProfit(), 0))
                  { 
                     Alert("OrderModify: "+ GetLastError());
                  }
               } 
            }
         }
         else
         {
            if(OrderOpenPrice() < Low[1])
            {
               if(!OrderCloseTime())
               {
                  if(!OrderModify(activeOrders[i], OrderOpenPrice(), Low[1], OrderTakeProfit(), 0))
                  { 
                     Alert("OrderModify: "+ GetLastError());
                  } 
               }
            }
         }
      }
      else 
      {
         Alert("OrderSelect: " +GetLastError());
      }
   }
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime todayDate;
   TimeCurrent(todayDate);
   bool newBar=false;
   if (todayDate.day_of_week == 6 || todayDate.day_of_week == 0) 
   {
      return;
   }
   static datetime time = Time[0];

   if(Time[0] > time)
   {
      time = Time[0]; //newbar, update time
      newBar = true;
   } 
   if (curReport.date.day != todayDate.day) 
   { //new day
      CloseOrders(); 
      closeBarValue = 0;
      firstActivatedTime = 0;
      activeOrdersCount = 0;
      isAllOrdersActivated = false;
      LoadNewReport();
   } 
   
   if (!curReport.isValid) 
   {  //invalid res. file 
      LoadNewReport(); //Try load again.
      if (!curReport.isValid) 
      {
 //        Print("Can't use the report for today.");
         return;
      }
   }
     
   double dayOpen = iOpen(Symbol(),PERIOD_D1,0);
   
   if (!openedOrdersCount && todayDate.hour >= 8) 
   {
      OpenOrders((majorLines[MAJOR_CENTER] > dayOpen));
   }
   
   if (!isAllOrdersActivated && newBar)
   {
         FindActiveOrders();
         if (activeOrdersCount == 2)
         {
            isAllOrdersActivated = true;
         }
   }
      
 
   if(newBar)
   {
      TrailingStop((majorLines[MAJOR_CENTER] > dayOpen));
   }
}
//+------------------------------------------------------------------+
