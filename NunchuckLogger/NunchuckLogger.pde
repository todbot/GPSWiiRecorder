// 
// NunchuckLogger -- An LCD UI showing Wii nunchuck acceleration data,
//                   and logs it to the EEPROM.
//             It also accumulates that data and spits it out on command
//             to a serial device periodically polling it.
//
// 2008, Tod E. Kurt, http://todbot.com/blog/
//
// NOTE: This is a work-in-progress. It doesn't work yet.
//
// Operation:
// - Arduino polls the nunchuck periodically, saving raw acceleration data
// - When Z is pressed, accel buffer is scanned for min/max
// - Min/max is then saved with a timestamp to EEPROM
// - When a 'p' is received on the Serial port, the saved 
//  
//
// Using:
//   Joystick Up   : show max accel values
//   Joystick Down : show min accel values 
//   C button      : set the zero-offset 
//   Z button      : on release, take a snapshot to EEPROM
//
// Note: this currently uses a special wii nunchuck library called 
//       "wiichuck_funcs.h" which is optimized for small memory use and
//       doesn't depend on the Wire library.  Instead, there's an accompanying
//       "twi_funcs.h" that is a minimal TWI (I2C) library.
//
//
//  LCD display layout
//   0123456789012345
//  +----------------+  +----------------+  +----------------+ 
// 0|0      hh:dd:ss*|  |12     hh:dd:ss*|  |                |
// 1|g:+1.9,+2.3,-4.5|  |g:+1.9,+2.3,-4.5|  |g:+1.9,+2.3,-4.5|
//  +----------------+  +----------------+  +----------------+
//

// setting DEBUG to 1 will output stuff to serial port so you can 
// experiment without needing a Serial LCD
#define DEBUG 1

#define ledPin    13
#define lcdoutPin  7

// min and max of accelerometer readings for each axis
// as they measure +1g or -1g
// these are my (tod) values 
// (not currently used in the code)
#define ACC_XM1G   73  // x-axis -1g measurement
#define ACC_XP1G  183  // x-axis +1g measurement
#define ACC_YM1G   69
#define ACC_YP1G  177
#define ACC_ZM1G   81
#define ACC_ZP1G  191


#include "LCDSerial.h"

LCDSerial lcdSerial =  LCDSerial(lcdoutPin);

// node that code-includes like this one must occur after some real code in 
// Arduino 0012 or it won't compile.
#include "wiichuck_funcs.h"

// sensor data in form:
// "|xxyyzz|xxyyzz|....\n"
// where 'xx','yy','zz'. are each a byte in ascii hex, 3-bytes per data payload
// spaced in time equally between GPS readings
// terminated with newline
// every this many millisecs, read sensors, should be even mult of 1000
// this MUST match the same defines in the user of this (e.g. GPSWiiLogger)
#define sensorUpdatesPerSec 10
#define sensorUpdateMillis (1000/sensorUpdatesPerSec)
#define SENSORBUFFSIZE (3*sensorUpdatesPerSec)

// overhead 
#define sensorUpdateMillisWFudge (sensorUpdateMillis - 10)

uint8_t sensorbuff[SENSORBUFFSIZE];
uint8_t sensorbuffidx;
uint8_t sensor_max[3];
uint8_t sensor_min[3];
uint8_t sensor_offsets[3] =   // zero-offsets, with initial guess
    {
        127,127,127
        //128,  // x
        //143,  // y
        //180   // z
    };
#define sensor_range 4   // wii nunchuck accelerometer is +/- 2g => 4g total
// see http://wiire.org/Chips/LIS3L02AL

#define BUFFSIZE 75
char buffer[BUFFSIZE];      // this is the double buffer
uint8_t bufferidx;

char timebuff[7] = "hhddss";

uint8_t i;
unsigned long lasttime;
unsigned long lastctrltime;
uint8_t disp_mode;   // 0 = rec/play, 1 = max, 2 = min, 3 = lat/ong
uint8_t rec_mode = 0;    // 1 = record, 0 = pause/stop
uint8_t key_down;
uint8_t display_gees;
uint8_t take_snapshot;
uint8_t event_count;
// 512 bytes of EEPROM, 2-bytes for timestamp, 3-bytes for xyz accel data
#define event_count_max (512/(2+3))   

#define DISP_REC 0
#define DISP_MAX 1
#define DISP_MIN 2
#define DISP_GPS 3


void setup() 
{
    pinMode( ledPin, OUTPUT);
    digitalWrite( ledPin, HIGH);

    Serial.begin(4800);          // This goes to data logger
    Serial.println("NunchuckLogger");

    lcdSerial.begin(9600);       // this goes to the LCD, don't change baud!
    lcdSerial.clearScreen();
    lcdSerial.print("NunchuckLogger");

    wiichuck_setpowerpins();
    delay(100);
    wiichuck_begin();

    // initialize any data that needs to be specific values
    memset(sensor_max, 0, 3);
    memset(sensor_min, 255,3);

    delay(1000);
    digitalWrite( ledPin, LOW);
    lcdSerial.clearScreen();
}

// returns ascii hex nibble
char toHex(uint8_t h)
{
    h &= 0xf;
    if( h < 10 ) 
        return (h + '0');
    return (h - 10 + 'A');
}

// turn an unsigned byte into a character string
void formatUint8(char* buff, uint8_t v)
{
    buff[0] = ((v/100) %10) + '0';
    buff[1] = ((v/10)  %10) + '0';
    buff[2] = ((v/1)   %10) + '0';
    buff[3] = 0;
}

// turn a signed byte into a character string
void formatInt8(char* buff, int8_t v)
{
    buff[0] = (v>0) ? '+':'-';
    v = abs(v);
    buff[1] = ((v/100) %10) + '0';
    buff[2] = ((v/10)  %10) + '0';
    buff[3] = ((v/1)   %10) + '0';
    buff[4] = 0;
}
// turn a signed float byte into a character string
// this likely has lots of bugs
void formatFloat8(char* buff, int8_t v, float range)
{
    buff[0] = (v>0) ? '+':'-';
    v = abs(v);
    float f = (v*range/127)/2;
    buff[1] = (int)f + '0';
    buff[2] = '.';
    buff[3] = ((int)(f*10) %10) + '0';
    buff[4] = 0;
}

// turn milliseconds into HHMMSS string
void millisToTimeStr( char* buff, unsigned long millis )
{
    long secs = millis/1000;
    long mins = secs/60;
    int hours = mins/60;
    secs = secs % 60;
    mins = mins % 60;
    buff[0] = (hours/10)+ '0';  // hours tens
    buff[1] = (hours%10)+ '0';  // hours ones
    buff[2] = (mins/10) + '0';  // mins tens
    buff[3] = (mins%10) + '0';  // mins ones
    buff[4] = (secs/10) + '0';  // secs tens
    buff[5] = (secs%10) + '0';  // secs ones
    buff[6] = 0;
}

//
void analyzeSensorBuff()
{
    uint8_t xa,ya,za;
    Serial.println("snap:");
    /*
    for( i=0; i< sensorUpdatesPerSec; i++) {
        uint8_t si = (i*3);
        sensorbuff[si+0];
        sensorbuff[si+1];
        sensorbuff[si+2];

    }
    */
    for( uint8_t i=0; i<3; i++ ) { 

    }

    memset(sensor_max, 0, 3);   // reset maxs to 0
    memset(sensor_min, 255,3);  // reset mins to 255
    event_count++;
    if( event_count == event_count_max ) {
        event_count = 0;
    }
}

//
void loop()
{
    char c;

    digitalWrite(ledPin, LOW);

    // check to see if it's time to read sensorsx
    unsigned long thistime = millis();
    if( (thistime - lasttime) >= sensorUpdateMillisWFudge ) { 
        lasttime = thistime;
        digitalWrite(ledPin, HIGH); // turn off  LED so it pulses
        
        // Acquire sensor readings
        wiichuck_get_data();
        for( i=0; i<3; i++ ) { // loop thru x,y,z parts
            uint8_t v = wiichuck_accelbuf[i];
            if( v > sensor_max[i] && v!=255 ) sensor_max[i] = v;
            if( v < sensor_min[i] && v!=0   ) sensor_min[i] = v;
        }

        // Save data
        memcpy(sensorbuff+sensorbuffidx, wiichuck_accelbuf, 3);
        sensorbuffidx += 3;
        // if at end of buffer, potentially analyze & reset buffptr
        if( sensorbuffidx >= SENSORBUFFSIZE ) {
            sensorbuffidx = 0;  // just loop, what else we gonna do?
            if( take_snapshot ) {
                analyzeSensorBuff();
                take_snapshot = 0;
            }
        }

        // Do UI Parsing
        if( wiichuck_cbutton() ) {      // C button == clr min/max & reset zero
            memset(sensor_max, 0, 3);   // reset maxs to 0
            memset(sensor_min, 255,3);  // reset mins to 255
            //for( i=0; i<3; i++ ) 
            //    sensor_offsets[i] = wiichuck_accelbuf[i];  // FIXME: wrong
        }

        if( wiichuck_zbutton() ) {      // Z button == stop/start recording
            key_down = 1;               // keydown is for debounce
        }
        if( !wiichuck_zbutton()  && key_down ) {
            take_snapshot = 1;  // prepare to analyze & take snapshot
            key_down = 0;       // key not down anymore
        }
        
        // pick display mode based on inputs
        if( wiichuck_joyy() > 0xA0 )         disp_mode = DISP_MAX;
        else if( wiichuck_joyy() < 0x40 )    disp_mode = DISP_MIN;
        else                                 disp_mode = DISP_REC;

        // move stick to the right changes readout style
        if( wiichuck_joyx() > 0xA0 )
            display_gees = !display_gees;

        // Write to LCD
        lcdSerial.gotoPos(0,0);  // line 1
        if( disp_mode == DISP_MAX )
            lcdSerial.print("Max");
        else if( disp_mode == DISP_MIN ) 
            lcdSerial.print("Min");
        else 
            lcdSerial.print( event_count,DEC );

        // write time in upper right hand corner
        lcdSerial.gotoPos(0,7);
        millisToTimeStr( timebuff, thistime );
        lcdSerial.print( timebuff[0] );
        lcdSerial.print( timebuff[1] );
        lcdSerial.print( ':' );
        lcdSerial.print( timebuff[2] );
        lcdSerial.print( timebuff[3] );
        lcdSerial.print( ':' );
        lcdSerial.print( timebuff[4] );
        lcdSerial.print( timebuff[5] );
        
        // write accelerometer values
        lcdSerial.gotoPos(1,0); // line 2
        lcdSerial.print("g:");
        char buff[5];
        for( i=0; i<3; i++) {
            uint8_t v;
            if( disp_mode==DISP_MAX ) v = sensor_max[i];
            else if( disp_mode==DISP_MIN ) v = sensor_min[i];
            else v = wiichuck_accelbuf[i];
            if( display_gees ) {
                int8_t vo = v - sensor_offsets[i];
                formatFloat8( buff, vo, sensor_range ); // range is +/- 2g => 4
            } else { 
                formatInt8( buff, v - 127);
            }
            lcdSerial.print( buff );
            if(i!=2) lcdSerial.print(',');
        }

#if DEBUG > 0
        displayToSerial();     // if you have no serial LCD, you can still play
#endif
    }  // sensor update
    
    // get sensor dump commands from serial (e.g. GPSWiiLogger)
    int n = Serial.available();
    if( n >= 1 ) {                 // command is "d", 1 bytes 
        char c = Serial.read();
        if( c != 'd' && c!='D' )  // command byte
            return;

        delay(5); // this is needed or SoftSerial reading this will choke 
        Serial.print( (rec_mode) ? 'r':'s' );
        // fill buffer with text version of sensor data
        bufferidx = 0;
        for( i=0; i< sensorUpdatesPerSec; i++) {
            uint8_t si = (i*3);
            buffer[bufferidx+0] = '|';
            buffer[bufferidx+1] = toHex(sensorbuff[si+0]>>4);
            buffer[bufferidx+2] = toHex(sensorbuff[si+0]);
            buffer[bufferidx+3] = toHex(sensorbuff[si+1]>>4);
            buffer[bufferidx+4] = toHex(sensorbuff[si+1]);
            buffer[bufferidx+5] = toHex(sensorbuff[si+2]>>4);
            buffer[bufferidx+6] = toHex(sensorbuff[si+2]);
            bufferidx+=7;
        }
        buffer[bufferidx++] = '\r';
        buffer[bufferidx]   = '\n';
        buffer[bufferidx+1] = 0;
        
        Serial.print(buffer); // dump it out

        sensorbuffidx = 0;   // reset
        memset(sensorbuff, 0, sizeof(sensorbuff));

        lastctrltime = millis(); // say we saw a command
    }
        
}

#if DEBUG > 0
// if you don't have a serial port, you can still see the output with this
void displayToSerial(void)
{
    char buff[5];
    uint8_t* p;

    if( disp_mode == DISP_MAX )
        Serial.print("Max");
    else if( disp_mode == DISP_MIN ) 
        Serial.print("Min");
    else 
        Serial.print( event_count,DEC );
    Serial.print(":");
    Serial.print(timebuff);
    Serial.print(" g:");

    // serial port analog to LCD output
    for( i=0; i<3; i++) {
        uint8_t v;
        if( disp_mode==DISP_MAX ) v = sensor_max[i];
        else if( disp_mode==DISP_MIN ) v = sensor_min[i];
        else v = wiichuck_accelbuf[i];
        if( display_gees ) {  // FIXME: this is the wrong way to do it
            int8_t vo = v - sensor_offsets[i];
            formatFloat8( buff, vo, sensor_range ); // range is +/- 2g => 4
        } else { 
            formatInt8( buff, v - 127);
        }
        Serial.print( buff );
        if(i!=2) Serial.print(',');
    }

    // pick which data set we're looking at
    if( disp_mode==DISP_MAX ) p = sensor_max;
    else if( disp_mode==DISP_MIN ) p = sensor_min;
    else p = wiichuck_accelbuf;

    Serial.print("\traw:");
    for( i=0; i<3; i++) {
        uint8_t v = p[i];
        formatUint8(buff, v);
        Serial.print( buff );
        Serial.print('(');
        Serial.print( v - sensor_offsets[i], DEC);
        Serial.print(')');
        if(i!=2) Serial.print(',');
    }
    Serial.println();
}

#endif
