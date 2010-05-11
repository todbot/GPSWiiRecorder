/*
  twi.c - TWI/I2C library for Wiring & Arduino
  Copyright (c) 2006 Nicholas Zambetti.  All right reserved.

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

#ifndef TWI_FUNCS_H
#define TWI_FUNCS_H

#include <math.h>
#include <stdlib.h>
#include <inttypes.h>
#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/signal.h>
#include <util/twi.h>


#include <inttypes.h>

#ifndef CPU_FREQ
#define CPU_FREQ 16000000L
#endif

#ifndef TWI_FREQ
#define TWI_FREQ 100000L
#endif

#ifndef TWI_BUFFER_LENGTH
#define TWI_BUFFER_LENGTH 16
#endif

#define TWI_READY 0
#define TWI_MRX   1
#define TWI_MTX   2
#define TWI_SRX   3
#define TWI_STX   4

#ifndef cbi
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#endif

#ifndef sbi
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))
#endif

volatile uint8_t twi_state;
static uint8_t twi_slarw;

static uint8_t twi_masterBuffer[TWI_BUFFER_LENGTH];
volatile uint8_t twi_masterBufferIndex;
static uint8_t twi_masterBufferLength;


/* 
 * Function twi_init
 * Desc     readys twi pins and sets twi bitrate
 * Input    none
 * Output   none
 */
void twi_init(void)
{
    // initialize state
    twi_state = TWI_READY;

#if defined(__AVR_ATmega168__) || defined(__AVR_ATmega8__)
    // activate internal pull-ups for twi
    // as per note from atmega8 manual pg167
    sbi(PORTC, 4);
    sbi(PORTC, 5);
#else
    // activate internal pull-ups for twi
    // as per note from atmega128 manual pg204
    sbi(PORTD, 0);
    sbi(PORTD, 1);
#endif

    // initialize twi prescaler and bit rate
    cbi(TWSR, TWPS0);
    cbi(TWSR, TWPS1);
    TWBR = ((CPU_FREQ / TWI_FREQ) - 16) / 2;

    /* twi bit rate formula from atmega128 manual pg 204
       SCL Frequency = CPU Clock Frequency / (16 + (2 * TWBR))
       note: TWBR should be 10 or higher for master mode
       It is 72 for a 16mhz Wiring board with 100kHz TWI */

    // enable twi module, acks, and twi interrupt
	TWCR = _BV(TWEN) | _BV(TWIE) | _BV(TWEA);
	
}

/* 
 * Function twi_slaveInit
 * Desc     sets slave address and enables interrupt
 * Input    none
 * Output   none
 */
void twi_setAddress(uint8_t address)
{
    // set twi slave address (skip over TWGCE bit)
    TWAR = address << 1;
}

/* 
 * Function twi_readFrom
 * Desc     attempts to become twi bus master and read a
 *          series of bytes from a device on the bus
 * Input    address: 7bit i2c device address
 *          data: pointer to byte array
 *          length: number of bytes to read into array
 * Output   byte: 0 ok, 1 length too long for buffer
 */
uint8_t twi_readFrom(uint8_t address, uint8_t* data, uint8_t length)
{
    uint8_t i;

    // ensure data will fit into buffer
    if(TWI_BUFFER_LENGTH < length){
        return 1;
    }

    // wait until twi is ready, become master receiver
    while(TWI_READY != twi_state){
        continue;
    }
    twi_state = TWI_MRX;

    // initialize buffer iteration vars
    twi_masterBufferIndex = 0;
    twi_masterBufferLength = length;

    // build sla+w, slave device address + w bit
    twi_slarw = TW_READ;
	twi_slarw |= address << 1;

    // send start condition
	TWCR = _BV(TWEN) | _BV(TWIE) | _BV(TWEA) | _BV(TWINT) | _BV(TWSTA);

	// wait for read operation to complete
	while(TWI_MRX == twi_state){
        continue;
	}

    // copy twi buffer to data
    for(i = 0; i < length; ++i){
        data[i] = twi_masterBuffer[i];
    }
	
	return 0;
}

/* 
 * Function twi_writeTo
 * Desc     attempts to become twi bus master and write a
 *          series of bytes to a device on the bus
 * Input    address: 7bit i2c device address
 *          data: pointer to byte array
 *          length: number of bytes in array
 *          wait: boolean indicating to wait for write or not
 * Output   byte: 0 ok, 1 length too long for buffer
 */
uint8_t twi_writeTo(uint8_t address, uint8_t* data, uint8_t length, uint8_t wait)
{
    uint8_t i;

    // ensure data will fit into buffer
    if(TWI_BUFFER_LENGTH < length){
        return 1;
    }

    // wait until twi is ready, become master transmitter
    while(TWI_READY != twi_state){
        continue;
    }
    twi_state = TWI_MTX;

    // initialize buffer iteration vars
    twi_masterBufferIndex = 0;
    twi_masterBufferLength = length;
  
    // copy data to twi buffer
    for(i = 0; i < length; ++i){
        twi_masterBuffer[i] = data[i];
    }
  
    // build sla+w, slave device address + w bit
    twi_slarw = TW_WRITE;
	twi_slarw |= address << 1;
  
    // send start condition
	TWCR = _BV(TWEN) | _BV(TWIE) | _BV(TWEA) | _BV(TWINT) | _BV(TWSTA);

	// wait for write operation to complete
	while(wait && (TWI_MTX == twi_state)){
        continue;
	}
	
	return 0;
}


/* 
 * Function twi_reply
 * Desc     sends byte or readys receive line
 * Input    ack: byte indicating to ack or to nack
 * Output   none
 */
void twi_reply(uint8_t ack)
{
	// transmit master read ready signal, with or without ack
	if(ack){
        TWCR = _BV(TWEN) | _BV(TWIE) | _BV(TWINT) | _BV(TWEA);
    }else{
        TWCR = _BV(TWEN) | _BV(TWIE) | _BV(TWINT);
    }
}

/* 
 * Function twi_stop
 * Desc     relinquishes bus master status
 * Input    none
 * Output   none
 */
void twi_stop(void)
{
    // send stop condition
    TWCR = _BV(TWEN) | _BV(TWIE) | _BV(TWEA) | _BV(TWINT) | _BV(TWSTO);

    // wait for stop condition to be exectued on bus
    // TWINT is not set after a stop condition!
    while(TWCR & _BV(TWSTO)){
        continue;
    }

    // update twi state
    twi_state = TWI_READY;
}

/* 
 * Function twi_releaseBus
 * Desc     releases bus control
 * Input    none
 * Output   none
 */
void twi_releaseBus(void)
{
    // release bus
    TWCR = _BV(TWEN) | _BV(TWIE) | _BV(TWEA) | _BV(TWINT);

    // update twi state
    twi_state = TWI_READY;
}


SIGNAL(SIG_2WIRE_SERIAL)
{
    switch(TW_STATUS){
        // All Master
    case TW_START:     // sent start condition
    case TW_REP_START: // sent repeated start condition
        // copy device address and r/w bit to output register and ack
        TWDR = twi_slarw;
        twi_reply(1);
        break;

        // Master Transmitter
    case TW_MT_SLA_ACK:  // slave receiver acked address
    case TW_MT_DATA_ACK: // slave receiver acked data
        // if there is data to send, send it, otherwise stop 
        if(twi_masterBufferIndex < twi_masterBufferLength){
            // copy data to output register and ack
            TWDR = twi_masterBuffer[twi_masterBufferIndex++];
            twi_reply(1);
        }else{
            twi_stop();
        }
        break;
    case TW_MT_SLA_NACK:  // address sent, nack received
    case TW_MT_DATA_NACK: // data sent, nack received
        twi_stop();
        break;
    case TW_MT_ARB_LOST: // lost bus arbitration
        twi_releaseBus();
        break;

        // Master Receiver
    case TW_MR_DATA_ACK: // data received, ack sent
        // put byte into buffer
        twi_masterBuffer[twi_masterBufferIndex++] = TWDR;
    case TW_MR_SLA_ACK:  // address sent, ack received
        // ack if more bytes are expected, otherwise nack
        if(twi_masterBufferIndex < twi_masterBufferLength){
            twi_reply(1);
        }else{
            twi_reply(0);
        }
        break;
    case TW_MR_DATA_NACK: // data received, nack sent
        // put final byte into buffer
        twi_masterBuffer[twi_masterBufferIndex++] = TWDR;
    case TW_MR_SLA_NACK: // address sent, nack received
        twi_stop();
        break;
        // TW_MR_ARB_LOST handled by TW_MT_ARB_LOST case
    }
}

#endif
