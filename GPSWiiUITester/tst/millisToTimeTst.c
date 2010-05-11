
#include <stdio.h>
#include <inttypes.h>

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

int main(void)
{
    char buf[8];
    unsigned long i;
    uint8_t j = 255;

    for( i=1000; ;i+=1000 ) {
        millisToTime(buf, i);
        printf( "%d:%s:%d\n", i, buf,j);
        j+=127;
    }


}
