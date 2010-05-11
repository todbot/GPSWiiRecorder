//
// wiichuck_funcs.h -- wii nunchuck functions using tiny twi_funcs
//
// 2008, Tod E. Kurt, http://todbot.com/blog/
//
// Based on code originally written by Chad Philips
//  http://www.windmeadow.com/node/42
//
//
//  Not compatible with the Wire library!
//
//

#ifndef WIICHUCK_FUNCS_H
#define WIICHUCK_FUNCS_H

//#include "wiring.h"

#define TWI_BUFFER_LENGTH 6   // don't need much
#include "twi_funcs.h"


#define wiichuck_addr 0x52

uint8_t tx_buf[2];
uint8_t wiichuck_buf[6];


// returns zbutton state: 1=pressed, 0=notpressed
#define wiichuck_zbutton() (((wiichuck_buf[5] >> 0) & 1) ? 0 : 1)  // voodoo

// returns zbutton state: 1=pressed, 0=notpressed
#define wiichuck_cbutton() (((wiichuck_buf[5] >> 1) & 1) ? 0 : 1)

// returns value of x-axis joystick
#define wiichuck_joyx() (wiichuck_buf[0])

// returns value of y-axis joystick
#define wiichuck_joyy() (wiichuck_buf[1])

// returns value of x-axis accelerometer
// FIXME: this leaves out 2-bits of the data
#define wiichuck_accelx() (wiichuck_buf[2])

// returns value of y-axis accelerometer
// FIXME: this leaves out 2-bits of the data
#define wiichuck_accely() (wiichuck_buf[3])

// returns value of x-axis accelerometer
// FIXME: this leaves out 2-bits of the data
#define wiichuck_accelz() (wiichuck_buf[4])

#define wiichuck_accelbuf ((uint8_t*)(wiichuck_buf+2))

// Uses port C (analog in) pins as power & ground for Nunchuck
static void wiichuck_setpowerpins()
{
#define pwrpin PC3
#define gndpin PC2
    DDRC |= _BV(pwrpin) | _BV(gndpin);
    PORTC &=~ _BV(gndpin);
    PORTC |=  _BV(pwrpin);
}

static void wiichuck_begin(void)
{
    twi_init();
    tx_buf[0] = 0x40;
    tx_buf[1] = 0x00;
    twi_writeTo( wiichuck_addr, tx_buf, 2, 1);  // blocking write
}

static void wiichuck_send_request()
{
    tx_buf[0] = 0x00;
    twi_writeTo( wiichuck_addr, tx_buf, 1, 1);  // blocking write
}

// Encode data to format that most wiimote drivers except
// only needed if you use one of the regular wiimote drivers
static char wiichuck_decode_byte (char x)
{
    x = (x ^ 0x17) + 0x17;
    return x;
}

// Receive data back from the nunchuck, 
// returns 0 on successful read. returns 1 on failure
static int wiichuck_get_data()
{
    twi_readFrom( wiichuck_addr, wiichuck_buf, 6);// request data from nunchuck

    for( uint8_t i=0; i<6; i++ )
        wiichuck_buf[i] = wiichuck_decode_byte(wiichuck_buf[i]);

    wiichuck_send_request();  // send request for next data payload
    
    return 0; // success, and look, no error checking above since we are studly
}

static void wiichuck_print_data()
{ 
    static int i=0;
    int joy_x_axis   = wiichuck_buf[0];
    int joy_y_axis   = wiichuck_buf[1];
    int accel_x_axis = wiichuck_buf[2] << 2; 
    int accel_y_axis = wiichuck_buf[3] << 2;
    int accel_z_axis = wiichuck_buf[4] << 2;

    int z_button = 0;
    int c_button = 0;

    // byte wiichuck_buf[5] contains bits for z and c buttons
    // it also contains the least significant bits for the accelerometer data
    // so we have to check each bit of byte outbuf[5]
    if ((wiichuck_buf[5] >> 0) & 1) 
        z_button = 1;
    if ((wiichuck_buf[5] >> 1) & 1)
        c_button = 1;

    if ((wiichuck_buf[5] >> 2) & 1)  // lower 2 bits of accel Z
        accel_x_axis += 2;
    if ((wiichuck_buf[5] >> 3) & 1)
        accel_x_axis += 1;

    if ((wiichuck_buf[5] >> 4) & 1)  // lower 2 bits of accel Y
        accel_y_axis += 2;
    if ((wiichuck_buf[5] >> 5) & 1)
        accel_y_axis += 1;

    if ((wiichuck_buf[5] >> 6) & 1)  // lower 2 bits of accel Z
        accel_z_axis += 2;
    if ((wiichuck_buf[5] >> 7) & 1)
        accel_z_axis += 1;

    Serial.print(i,HEX);
    Serial.print('\t');
    Serial.print("joy:");
    Serial.print(joy_x_axis,HEX);
    Serial.print(',');
    Serial.print(joy_y_axis,HEX);
    Serial.print("\tacc:");
    Serial.print(accel_x_axis,HEX);
    Serial.print(',');
    Serial.print(accel_y_axis,HEX);
    Serial.print(',');
    Serial.print(accel_z_axis,HEX);
    Serial.print("\tbut:");
    Serial.print(z_button,HEX);
    Serial.print(c_button,HEX);
    Serial.println();

    i++;
}



#endif
