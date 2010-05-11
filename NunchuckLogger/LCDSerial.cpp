/*
  LCDSerial.cpp - Sparkfun LCD Serial comm using simple software serial 
  2008, Tod E. Kurt, http://todbot.com/blog/

  Based on:
  SoftwareSerial (2006) by David A. Mellis and
  AFSoftSerial (2008) by ladyada

  Copyright (c) 2006 David A. Mellis.  All right reserved. - hacked by ladyada 

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free Software
  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*/

/******************************************************************************
 * Includes
 ******************************************************************************/
#include <avr/interrupt.h>
#include "WConstants.h"

#include "LCDSerial.h"

#define LCD_CMD               ((uint8_t)0xFE)
#define LCD_CMD_CLEAR_SCREEN  ((uint8_t)0x01)
#define LCD_CMD_POS_LINE_ONE  ((uint8_t)128)
#define LCD_CMD_POS_LINE_TWO  ((uint8_t)192)

#define LCD_BACKLIGHT         ((uint8_t)0x7C)
#define LCD_BACKLIGHT_MIN     ((uint8_t)128)
#define LCD_BACKLIGHT_MAX     ((uint8_t)157)

#define putc(x) print((char)x)

static int _bitDelay;

#if (F_CPU == 16000000)
void LCDwhackDelay(uint16_t delay) { 
  uint8_t tmp=0;

  asm volatile("sbiw    %0, 0x01 \n\t"
	       "ldi %1, 0xFF \n\t"
	       "cpi %A0, 0xFF \n\t"
	       "cpc %B0, %1 \n\t"
	       "brne .-10 \n\t"
	       : "+r" (delay), "+a" (tmp)
	       : "0" (delay)
	       );
}
#endif


LCDSerial::LCDSerial(uint8_t transmitPin)
{
  _transmitPin = transmitPin;
  _baudRate = 0;
}

void LCDSerial::begin(long speed)
{
  pinMode(_transmitPin, OUTPUT);
  digitalWrite(_transmitPin, HIGH);

  _baudRate = speed;
  switch (_baudRate) {
  case 115200: // For xmit -only-!
    _bitDelay = 4; break;
  case 57600:
    _bitDelay = 14; break;
  case 38400:
    _bitDelay = 24; break;
  case 31250:
    _bitDelay = 31; break;
  case 19200:
    _bitDelay = 54; break;
  case 9600:
    _bitDelay = 113; break;
  case 4800:
    _bitDelay = 232; break;
  case 2400:
    _bitDelay = 470; break;
  default:
    _bitDelay = 0;
  }    

  LCDwhackDelay(_bitDelay*2); // if we were low this establishes the end

  // send ctrl-r to reset to 9600 baud?
}

// command functions

void LCDSerial::clearScreen(void) 
{
    putc( LCD_CMD );
    putc( LCD_CMD_CLEAR_SCREEN );
}

void LCDSerial::gotoLine(uint8_t line)
{
    putc( LCD_CMD );
    putc( (line) ? LCD_CMD_POS_LINE_TWO : LCD_CMD_POS_LINE_ONE);
}
void LCDSerial::gotoPos(uint8_t line, uint8_t pos)
{
    putc( LCD_CMD );
    putc( (pos + ((line) ? LCD_CMD_POS_LINE_TWO : LCD_CMD_POS_LINE_ONE)));
}

void LCDSerial::backlightOn(void)
{
    putc( LCD_BACKLIGHT );
    putc( LCD_BACKLIGHT_MAX );
}

void LCDSerial::backlightOff(void)
{
    putc( LCD_BACKLIGHT );
    putc( LCD_BACKLIGHT_MIN );
}

//
// the main method that does it all
//
void LCDSerial::print(uint8_t b)
{
  if (_baudRate == 0)
    return;
  byte mask;

  cli();  // turn off interrupts for a clean txmit

  digitalWrite(_transmitPin, LOW);  // startbit
  LCDwhackDelay(_bitDelay*2);

  for (mask = 0x01; mask; mask <<= 1) {
    if (b & mask){ // choose bit
      digitalWrite(_transmitPin,HIGH); // send 1
    }
    else{
      digitalWrite(_transmitPin,LOW); // send 1
    }
    LCDwhackDelay(_bitDelay*2);
  }
  
  digitalWrite(_transmitPin, HIGH);
  sei();  // turn interrupts back on. hooray!
  LCDwhackDelay(_bitDelay*2);
}

void LCDSerial::print(const char *s)
{
  while (*s)
    print(*s++);
}

void LCDSerial::print(char c)
{
  print((uint8_t) c);
}

void LCDSerial::print(int n)
{
  print((long) n);
}

void LCDSerial::print(unsigned int n)
{
  print((unsigned long) n);
}

void LCDSerial::print(long n)
{
  if (n < 0) {
    print('-');
    n = -n;
  }
  printNumber(n, 10);
}

void LCDSerial::print(unsigned long n)
{
  printNumber(n, 10);
}

void LCDSerial::print(long n, int base)
{
  if (base == 0)
    print((char) n);
  else if (base == 10)
    print(n);
  else
    printNumber(n, base);
}


// Private Methods ///////////////////////////////////////////////////////////

void LCDSerial::printNumber(unsigned long n, uint8_t base)
{
  unsigned char buf[8 * sizeof(long)]; // Assumes 8-bit chars. 
  unsigned long i = 0;

  if (n == 0) {
    print('0');
    return;
  } 

  while (n > 0) {
    buf[i++] = n % base;
    n /= base;
  }

  for (; i > 0; i--)
    print((char) (buf[i - 1] < 10 ? '0' + buf[i - 1] : 'A' + buf[i - 1] - 10));
}
