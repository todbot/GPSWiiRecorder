//
//  GPSWiiLogger --
//
//  2008, Tod E. Kurt, http://todbot.com/blog/
//  
//  adapted from Limor Fried's GPSLogger from:
//    http://www.ladyada.net/make/gpsshield/download.html  
//
//

// this is a generic logger that does checksum testing so the data 
// written should be always good
// Assumes a sirf III chipset logger attached to pin 0 and 1

// set this to 1 to watch output from GPS for testing
#define DEBUG 0

//#define LOG_RMC_FIXONLY 0  // turned off only logging on fix for John

#include "AF_SDLog.h"

#include "util.h"
#include <avr/pgmspace.h>
#include <avr/sleep.h>

#define pwrSerPin 6              // provide a fake Vcc for serial ANDer
#define led1Pin 4                // LED1 connected to digital pin 4
#define led2Pin 3                // LED2 connected to digital pin 3
#define powerPin 2               // GPS power control

// this MUST match the same defines in GPSWiiUI
// every this many millisecs, read sensors, should be even mult of 1000
#define sensorUpdatesPerSec 10
#define sensorUpdateMillis (1000/sensorUpdatesPerSec)
#define sensorPacketSize 7   // "|xxyyzz" 7 bytes
#define sensorBuffSize ((sensorPacketSize*sensorUpdatesPerSec)+5)

// Reduce Arduino's Serial RAM footprint!
// set RX_BUFFER_SIZE to 32 in ..../hardware/cores/arduino/wiring_serial.c


AF_SDLog card;
File f;


// we buffer one NMEA sentense at a time, 
// 83 bytes is longer than the max length
#define BUFFSIZE 75 
char buffer[BUFFSIZE];      // this is the double buffer
uint8_t bufferidx = 0;

#define LOG_RMC_FIXONLY 1  // log only when we get RMC's with fix?
#define RMC_ON   "$PSRF103,4,0,1,1*21\r\n"   // cmd to turn RMC on (1 hz rate)
#define WAAS_ON  "$PSRF151,1*3F\r\n"         // cmd to turn WAAS on
#define GGA_OFF  "$PSRF103,0,0,0,1*24\r\n"   // cmd to turn GGA off
#define GSA_OFF  "$PSRF103,2,0,0,1*26\r\n"   // cmd to turn GSA off
#define GSV_OFF  "$PSRF103,3,0,0,1*27\r\n"   // cmd to turn GSV off


uint8_t fix = 0; // current fix data
uint8_t logging = 0; // 1 == log to disk, 0 = no
uint8_t i;


// read a Hex value and return the decimal equivalent
uint8_t parseHex(char c) 
{
    if (c >= '0' && c <= '9') 
        return (c - '0');
    if (c >= 'A' && c <= 'F')
        return (c - 'A')+10;
    return 0;
}

// blink out an error code
void error(uint8_t errno) {
    while(1) {
        for (i=0; i<errno; i++) {    
            digitalWrite(led1Pin, HIGH);
            digitalWrite(led2Pin, HIGH);
            delay(100);
            digitalWrite(led1Pin, LOW);   
            digitalWrite(led2Pin, LOW);   
            delay(100);
        }
        for (; i<10; i++) {
            delay(200);
        }      
    } 
}

//
void setup()                    // run once, when the sketch starts
{
    delay(2000);                   // slow humans need help sometimes

    Serial.begin(4800);
    putstring_nl("GPSWiilogger");
    pinMode(led1Pin, OUTPUT);      // sets the digital pin as output
    pinMode(led2Pin, OUTPUT);      // sets the digital pin as output
    pinMode(powerPin, OUTPUT);
    pinMode(pwrSerPin, OUTPUT);
    digitalWrite(powerPin, LOW);
    digitalWrite(pwrSerPin, HIGH); // create a fake power supply
  
    if (!card.init_card()) {
        putstring_nl("Card init. failed!"); 
        error(1);
    }
    if (!card.open_partition()) {
        putstring_nl("No partition!"); 
        error(2);
    }
    if (!card.open_filesys()) {
        putstring_nl("Can't open filesys"); 
        error(3);
    }
    if (!card.open_dir("/")) {
        putstring_nl("Can't open /"); 
        error(4);
    }
  
    strcpy(buffer, "GPSLOG00.TXT");
    for (buffer[6] = '0'; buffer[6] <= '9'; buffer[6]++) {
        for (buffer[7] = '0'; buffer[7] <= '9'; buffer[7]++) {
            //putstring("\n\rtrying to open ");Serial.println(buffer);
            f = card.open_file(buffer);
            if (!f)
                break;        // found a file!      
            card.close_file(f);
        }
        if (!f) 
            break;
    }

    if(!card.create_file(buffer)) {
        putstring("couldnt create "); Serial.println(buffer);
        error(5);
    }
    f = card.open_file(buffer);
    if (!f) {
        putstring("error opening "); Serial.println(buffer);
        card.close_file(f);
        error(6);
    }
    putstring("writing to "); Serial.println(buffer);

    delay(1000);  // wait for everything to finish waking up

    putstring("\r\n");
    putstring(GSV_OFF); // turn off GSV
    putstring(GSA_OFF); // turn off GSA
    putstring(GGA_OFF); // turn off GGA
    putstring(WAAS_ON); // turn on WAAS
    putstring(RMC_ON);  // turn on RMC

    putstring_nl("ready!");
}

//
void loop()
{
    char c;
    uint8_t sum;
  
    // read one 'line' from GPS
    if (Serial.available()) {
        c = Serial.read();
        if (bufferidx == 0) {
            while (c != '$')
                c = Serial.read(); // wait till we get a $, start of GPS data
        }
        buffer[bufferidx] = c;

        if (c == '\n') {
            buffer[bufferidx+1] = 0; // terminate it
#if DEBUG > 1
            Serial.print(buffer);    // debug
#endif
            if (buffer[bufferidx-4] != '*') {
                // no checksum?
                Serial.print('*', BYTE);
                bufferidx = 0;
                return;
            }
            // get checksum
            sum = parseHex(buffer[bufferidx-3]) * 16;
            sum += parseHex(buffer[bufferidx-2]);
      
            // check checksum 
            for (i=1; i < (bufferidx-4); i++) {
                sum ^= buffer[i];
            }
            if (sum != 0) {         // checksum mismatch
                Serial.print('~', BYTE);
                bufferidx = 0;
                return;
            }
            // got good data!

            if (strstr(buffer, "GPRMC")) {   // verify we have RMC line
                // find out if we got a fix
                char *p = buffer;
                p = strchr(p, ',')+1;
                p = strchr(p, ',')+1;       // skip to 3rd item
        
                if (p[0] == 'V') {                // 'V' == no valid fix
                    digitalWrite(led1Pin, LOW);
                    fix = 0;
                } else {
                    digitalWrite(led1Pin, HIGH);  // otherwise, gotta fix
                    fix = 1;
                }
            }
#if LOG_RMC_FIXONLY 
            if (!fix) {
                Serial.print('_', BYTE);
                //logging = 0; // bufferidx = 0;  // return;
            } 
#endif

            // rad, got good GPS data. lets log the GPS line
#if DEBUG
            Serial.print(buffer);
#endif
            if( logging ) {
                Serial.print('#', BYTE);
                digitalWrite(led2Pin, HIGH);      // indicate we're writing
                if(card.write_file(f,(uint8_t *)buffer, bufferidx)!=bufferidx){
                    putstring_nl("can't write!");
                    return;
                }
                digitalWrite(led2Pin, LOW);       // writing done
            }
            bufferidx = 0;  // indicate we used up the buffer

            // send request for data and get sensor line response
            // request command to get sensor data format: "sHHMMSS\n" 
            // s is ether 's' or 'S': 's' = recording, 'S' = stopped
            // HHMMSS is hours,mins,secs from GPS
            // response is a line of data where first character can be
            // flag back to us, telling us to stop logging any data ('s')
            // or to log both GPS and sensor data ('r')
            buffer[7+6] = 0; // null-terminate GPS timestamp so we can send it
            Serial.print( (logging) ? 's':'S');  
            Serial.println(buffer+7); // send timestamp to sensor
            while(1) {       // haha, while(1)!  but we'll escape... eventually
                c = Serial.read();
                if( c==-1 ) continue;  // nothing on serial port, try again
                if( (c=='\n') || bufferidx==BUFFSIZE-1 ) { // we're done!
                    buffer[bufferidx] = 0;  // gotta null-terminate strings
                    break;
                }
                buffer[bufferidx++] = c;  // save data char from sensor
            }

            // first char from sensor is potential command, so
            // look at command from sensor pod
            if( buffer[0] == 's' )        logging = 0;
            else if( buffer[0] == 'r' )   logging = 1;
            // else, could have other commands here too
            //bufferidx--; // eat that first command char

            // now write sensor line
#if DEBUG
            Serial.print(buffer+1);
#endif
            if( logging ) {
                Serial.print('|', BYTE);
                digitalWrite(led2Pin, HIGH);      // indicate we're writing
                if(card.write_file(f,(uint8_t *)buffer, bufferidx)!=bufferidx){
                    putstring_nl("can't write!");
                    return;
                }
                digitalWrite(led2Pin, LOW);       // writing done
            }
            bufferidx = 0;
            return;
        }
        bufferidx++; 
        if (bufferidx == BUFFSIZE-1) {  // oops, buffer overrun,
            Serial.print('!', BYTE);    // not much we can do but say ouch
            bufferidx = 0;              // and reset
        }
    } else {
        // no serial available.  do nothing
    }
  
}

