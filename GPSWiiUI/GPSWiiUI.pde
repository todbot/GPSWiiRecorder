// 
// GPSWiiUI -- An LCD UI showing Wii nunchuck acceleration data.
//             It also accumulates that data and spits it out on command
//             to a serial device periodically polling it.
//
// 2008, Tod E. Kurt, http://todbot.com/blog/
//
// Using:
//   Joystick Up   : show max accel values
//   Joystick Down : show min accel values
//   Joystick Right: toggle displaying acceleration in g's or raw values 
//   C button      : clear min/max
//   Z button      : stop/start recording (not implemented yet)
//
// The right-most digit on the first line is the acknowledgement from 
// GPSWiiLogger.  It is either a '.' (paused ack) or ':' (recording ack)
//
// Note: this currently uses a special wii nunchuck library called 
//       "wiichuck_funcs.h" which is optimized for small memory use and
//       doesn't depend on the Wire library.  Instead, there's an accompanying
//       "twi_funcs.h" that is a minimal TWI (I2C) library.
//
//
//  LCD display layout 
//   0123456789012345
//  .----------------. 
// 0|Rec    hh:dd:ss.| 
// 1|g:xxxx,yyyy,zzzz| 
//  '----------------' 
//


#define ledPin    13
#define lcdoutPin  7

#include "LCDSerial.h"

LCDSerial lcdSerial =  LCDSerial(lcdoutPin);

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
uint8_t display_gees = 0;

#define DISP_REC 0
#define DISP_MAX 1
#define DISP_MIN 2
#define DISP_GPS 3

char gps_status = '.';


void setup() 
{
    pinMode( ledPin, OUTPUT);
    digitalWrite( ledPin, HIGH);

    Serial.begin(4800);          // This goes to data logger
    Serial.println("GPSWiiUI");

    lcdSerial.begin(9600);       // this goes to the LCD, don't change baud!
    lcdSerial.clearScreen();
    lcdSerial.print("GPSWiiUI");

    //frameBufferFixSpaces();
    
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
static char toHex(uint8_t h)
{
    h &= 0xf;
    if( h < 10 ) 
        return (h + '0');
    return (h - 10 + 'A');
}

//
static void formatInt8(char* buff, int8_t v)
{
    buff[0] = (v>0) ? '+':'-';
    buff[1] = ((abs(v)/100) %10) + '0';
    buff[2] = ((abs(v)/10)  %10) + '0';
    buff[3] = ((abs(v)/1)   %10) + '0';
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

static void millisToTimeStr( char* buff, unsigned long millis )
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

void loop()
{
    char c;

    digitalWrite(ledPin, LOW);
    
    unsigned long thistime = millis();
    if( (thistime - lasttime) >= sensorUpdateMillisWFudge ) { 
        lasttime = thistime;
        digitalWrite(ledPin, HIGH); // turn off "good data" LED so it pulses
        
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
        if( sensorbuffidx == SENSORBUFFSIZE ) {
            sensorbuffidx = 0;  // just loop, what else we gonna do?
            gps_status = ' ';
        }

        // Do UI Parsing
        if( wiichuck_cbutton() ) {      // C button == clear min/max
            memset(sensor_max, 0, 3);   // reset maxs to 0
            memset(sensor_min, 255,3);  // reset mins to 255
            display_gees = !display_gees;
            //for( i=0; i<3; i++ ) 
            //    sensor_offsets[i] = wiichuck_accelbuf[i];  // FIXME: wrong
        }

        if( wiichuck_zbutton() ) {      // Z button == stop/start recording
            key_down = 1;               // keydown is for debounce
        }
        if( !wiichuck_zbutton()  && key_down ) {
            rec_mode = !rec_mode;
            key_down = 0;
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
            lcdSerial.print( (rec_mode) ? "Rec":"Stp");

        lcdSerial.gotoPos(0,7);
        // if no time from controller
        if( thistime - lastctrltime > 5000 ) {
            millisToTimeStr( timebuff, thistime );
        } 
        
        lcdSerial.print( timebuff[0] );
        lcdSerial.print( timebuff[1] );
        lcdSerial.print( ':' );
        lcdSerial.print( timebuff[2] );
        lcdSerial.print( timebuff[3] );
        lcdSerial.print( ':' );
        lcdSerial.print( timebuff[4] );
        lcdSerial.print( timebuff[5] );
        
        lcdSerial.gotoPos(1,0); // line 2
        lcdSerial.print((display_gees)?"g:":"w:");
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

        // indicate status
        lcdSerial.gotoPos(0,15);
        lcdSerial.print(gps_status);
    }

    
    // get sensor dump commands from serial (e.g. GPSWiiLogger)
    int n = Serial.available();
    if( n > 6 ) {       // "s221359", 7 bytes 
        char c = Serial.read();
        if( c != 's' && c!='S' )  // command byte
            return;
        // one dot means we're paused, two means we're recording
        gps_status = (c=='S') ? '.' : ':';

        // do rest of parsing, for time
        for( i=0; i<6; i++ )
            timebuff[i] = Serial.read();
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

/*
void loopold()
{
    unsigned long t = millis();

    // scribble in the frame buffer
    if( (t - lasttime) > 175 ) {
        lasttime = t;
        strcpy(line1, "[--------------]");
        line1[ball] = '*';
        ball+= ballinc;
        if( ball == 14 ) ballinc=-1;
        if( ball == 1 ) ballinc = 1;
    }

    ultoa( t, line2, 10);

    frameBufferFixSpaces();

    // dump the frame buffer to display
    lcdSerial.gotoLineOne();
    lcdSerial.print(line1);
    lcdSerial.gotoLineTwo();
    lcdSerial.print(line2);

    delay(100);
}
*/

