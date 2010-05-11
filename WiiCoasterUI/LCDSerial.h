

#ifndef _LCDSERIAL_H_
#define _LCDSERIAL_H_

#include <stdint.h>

// stolen from HardwareSerial.h
#define DEC 10
#define HEX 16
#define OCT 8
#define BIN 2
#define BYTE 0

class LCDSerial
{
  private:
    long _baudRate;
    uint8_t _transmitPin;
    void printNumber(unsigned long, uint8_t);

  public:
    LCDSerial(uint8_t lcdPin);
    void begin(long speed);
    void clearScreen(void);
    void gotoLine(uint8_t line);
    void gotoPos(uint8_t line, uint8_t pos);
    void backlightOn(void);
    void backlightOff(void);
    void print(char);
    void print(const char[]);
    void print(uint8_t);
    void print(int);
    void print(unsigned int);
    void print(long);
    void print(unsigned long);
    void print(long, int);
 };

#endif
