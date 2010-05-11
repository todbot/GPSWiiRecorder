/*
 * AFSoftSerial_funcs.h --  A static C version of Limor Fried's AFSoftSerial 
 *                          Arduino library. 
 *
 * Use this when you are memory constrained.
 * It's not as clean, but can be tuned to be smaller.
 *
 * Defines you can set
 *  AFSS_BAUD         -- baud rate to operate at (defaults to 9600)
 *  AFSS_TX_PIN       -- pin to transmit on
 *  AFSS_RX_PIN       -- pin to receive on
 *  AFSS_DISABLE_READ -- removes read code & buffer, for transmit-only uses
 *  AFSS_MAX_RX_BUFF  -- size of RX buffer
 *  AFSS_EXTRA_PRINT_FUNCS -- extra printing functions, like Serial.print(...)
 *
 */
/*
  SoftwareSerial.h - Software serial library
  Copyright (c) 2006 David A. Mellis.  All right reserved.

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

#ifndef AFSoftSerial_funcs_h
#define AFSoftSerial_funcs_h

#include <inttypes.h>

#ifndef AFSS_BAUD
#define AFSS_BAUD 9600
#endif

#if   AFSS_BAUD == 115200
#define _bitDelay 4
#elif AFSS_BAUD == 57600
#define _bitDelay 14
#elif AFSS_BAUD == 38400
#define _bitDelay 24
#elif AFSS_BAUD == 31250
#define _bitDelay 31
#elif AFSS_BAUD == 19200
#define _bitDelay 54
#elif AFSS_BAUD == 9600
#define _bitDelay 113
#elif AFSS_BAUD == 4800
#define _bitDelay 232
#elif AFSS_BAUD == 2400
#define _bitDelay 470
#endif

#define _transmitPin AFSS_TX_PIN
#define _receivePin  AFSS_RX_PIN

static char _receive_buffer[AFSS_MAX_RX_BUFF]; 
static uint8_t _receive_buffer_index;


#if (F_CPU == 16000000)
static void afss_whackDelay(uint16_t delay) { 
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

/****************************************************************************
 * Interrupts
 ****************************************************************************/
#ifndef AFSS_DISABLE_READ

static void afss_recv(void)
{ 
    char i, d = 0; 
    if (digitalRead(_receivePin)) 
        return;       // not ready! 
    afss_whackDelay(_bitDelay - 8);
    for (i=0; i<8; i++) { 
        //PORTB |= _BV(5); 
        afss_whackDelay(_bitDelay*2 - 6);  // digitalread takes some time
        //PORTB &= ~_BV(5); 
        if (digitalRead(_receivePin)) 
            d |= (1 << i); 
    } 
    afss_whackDelay(_bitDelay*2);
    if (_receive_buffer_index >=  AFSS_MAX_RX_BUFF)
        return;
    _receive_buffer[_receive_buffer_index] = d; // save data 
    _receive_buffer_index++;  // got a byte 
} 

SIGNAL(SIG_PIN_CHANGE0)
{
    if ((_receivePin >=8) && (_receivePin <= 13)) {
        afss_recv();
    }
}
SIGNAL(SIG_PIN_CHANGE2)
{
    if (_receivePin <8) {
        afss_recv();
    }
}
#endif

/****************************************************************************
 * User API
 ****************************************************************************/

static void AFSoftSerial_begin()
{
  pinMode(_transmitPin, OUTPUT);
  digitalWrite(_transmitPin, HIGH);

#ifndef AFSS_DISABLE_READ
  pinMode(_receivePin, INPUT); 
  digitalWrite(_receivePin, HIGH);  // pullup!
#endif
  afss_whackDelay(_bitDelay*2); // if we were low this establishes the end
}

#ifndef AFSS_DISABLE_READ
static int AFSoftSerial_read(void)
{
  uint8_t d,i;

  if (! _receive_buffer_index)
    return -1;

  d = _receive_buffer[0]; // grab first byte
  // if we were awesome we would do some nifty queue action
  // sadly, i dont care
  for (i=0; i<_receive_buffer_index; i++) {
    _receive_buffer[i] = _receive_buffer[i+1];
  }
  _receive_buffer_index--;
  return d;
}

static uint8_t AFSoftSerial_available(void)
{
  return _receive_buffer_index;
}
#endif

static void AFSoftSerial_print(uint8_t b)
{
  byte mask;

  cli();  // turn off interrupts for a clean txmit

  digitalWrite(_transmitPin, LOW);  // startbit
  afss_whackDelay(_bitDelay*2);

  for (mask = 0x01; mask; mask <<= 1) {
    if (b & mask){ // choose bit
      digitalWrite(_transmitPin,HIGH); // send 1
    }
    else{
      digitalWrite(_transmitPin,LOW); // send 1
    }
    afss_whackDelay(_bitDelay*2);
  }
  
  digitalWrite(_transmitPin, HIGH);
  sei();  // turn interrupts back on. hooray!
  afss_whackDelay(_bitDelay*2);
}

static void AFSoftSerial_print(const char *s)
{
    while (*s)
        AFSoftSerial_print(*s++);
}

// We can not compile these to save some ROM space
#ifdef AFSS_EXTRA_PRINT_FUNCS 

void AFSoftSerial_print(char c)
{
    AFSoftSerial_print((uint8_t) c);
}

void AFSoftSerial_print(int n)
{
    AFSoftSerial_print((long) n);
}

void AFSoftSerial_print(unsigned int n)
{
    AFSoftSerial_print((unsigned long) n);
}

void AFSoftSerial_print(long n)
{
    if (n < 0) {
        AFSoftSerial_print('-');
        n = -n;
    }
    AFSoftSerial_printNumber(n, 10);
}

void AFSoftSerial_print(unsigned long n)
{
  AFSoftSerial_printNumber(n, 10);
}

void AFSoftSerial_print(long n, int base)
{
    if (base == 0)
        AFSoftSerial_print((char) n);
    else if (base == 10)
        AFSoftSerial_print(n);
    else
        AFSoftSerial_printNumber(n, base);
}

void AFSoftSerial_println(void)
{
    AFSoftSerial_print('\r');
    AFSoftSerial_print('\n');  
}

void AFSoftSerial_println(char c)
{
    AFSoftSerial_print(c);
    AFSoftSerial_println();  
}

void AFSoftSerial_println(const char c[])
{
  AFSoftSerial_print(c);
  AFSoftSerial_println();
}

void AFSoftSerial_println(uint8_t b)
{
    AFSoftSerial_print(b);
    AFSoftSerial_println();
}

void AFSoftSerial_println(int n)
{
    AFSoftSerial_print(n);
    AFSoftSerial_println();
}

void AFSoftSerial_println(long n)
{
    AFSoftSerial_print(n);
    AFSoftSerial_println();  
}

void AFSoftSerial_println(unsigned long n)
{
    AFSoftSerial_print(n);
    AFSoftSerial_println();  
}

void AFSoftSerial_println(long n, int base)
{
    AFSoftSerial_print(n, base);
    AFSoftSerial_println();
}


// Private Methods /////////////////////////////////////////////////////////////

static void AFSoftSerial_printNumber(unsigned long n, uint8_t base)
{
    unsigned char buf[8 * sizeof(long)]; // Assumes 8-bit chars. 
    unsigned long i = 0;
    
    if (n == 0) {
        AFSoftSerial_print('0');
        return;
    } 
    
    while (n > 0) {
        buf[i++] = n % base;
        n /= base;
    }

    for (; i > 0; i--)
        AFSoftSerial_print((char) (buf[i - 1] < 10 ? '0' + buf[i - 1] : 'A' + buf[i - 1] - 10));
}

#endif

#endif

