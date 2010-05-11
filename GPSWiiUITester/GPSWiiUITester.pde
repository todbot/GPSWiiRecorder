//
//  GPSWiiUITester -- a 'client' for GPSWiiUI, implemented in a way
//                    similar to what's done in GPSWiiLogger,
//                    meant as a technology demo
//
//  2008, Tod E. Kurt, http://todbot.com/blog/
//
//

#include "AFSoftSerial.h"

///extern uint8_t _receive_buffer;  // part of AFSoftSerial

// this MUST match the same defines in GPSWiiUI
// every this many millisecs, read sensors, should be even mult of 1000
#define sensorUpdatesPerSec 10
#define sensorUpdateMillis (1000/sensorUpdatesPerSec)
#define sensorPacketSize 7   // "|xxyyzz" 7 bytes
#define sensorBuffSize ((sensorPacketSize*sensorUpdatesPerSec)+5)

#define uiOutPin 7
#define uiInPin 6

unsigned long lasttime;

AFSoftSerial uiSerial = AFSoftSerial(uiInPin, uiOutPin);

#define BUFFSIZ sensorBuffSize
char buffer[sensorBuffSize];
uint8_t buffidx;
uint8_t i;

//
// standard Arduino setup
//
void setup() 
{
    Serial.begin(19200);     // this would normally be 4800 to the GPS
    uiSerial.begin(19200);  // talk to GPSWiiGUI uses SoftSerial defines above

    Serial.println("\r\nReady!");
}

//
// standard Arduino loop
//
void loop()
{
    unsigned long thistime = millis();
    if( (thistime - lasttime) >= 1000 ) { 
        lasttime = thistime;
        Serial.println("Getting sensor data");
        char buf[8] = "s123456";
        millisToTime( buf+1, thistime);
        uiSerial.print(buf);
        
        unsigned long t1 = millis();
        readline();
        Serial.print("readline delta:");
        Serial.print(millis()-t1, DEC);

        Serial.print(" bufi:");
        Serial.print(buffidx,DEC);
        Serial.print(" buff:");
        Serial.println(buffer);
    }
    
}

// converts standard millis val to a time str in "hhmmss" format
void millisToTime(char* buff, unsigned long m)
{
    long secs = m/1000;
    long mins = secs/60;
    int hours = mins/60;
    secs = secs % 60;
    mins = mins % 60;
    buff[0] = (hours/10)+ '0';
    buff[1] = (hours%10)+ '0';
    buff[2] = (mins/10) + '0';
    buff[3] = (mins%10) + '0';
    buff[4] = (secs/10) + '0';
    buff[5] = (secs%10) + '0';
    buff[6] = 0;
}

void readline(void) {
  char c;
  
  buffidx = 0; // start at begninning
  while (1) {
      c = uiSerial.read();
      if (c == -1)
        continue;
      if (c == '\n')
        continue;
      if ((buffidx == BUFFSIZ-1) || (c == '\r')) {
        buffer[buffidx] = 0;
        return;
      }
      buffer[buffidx++]= c;
  }
}
