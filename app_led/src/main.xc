// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <stdio.h>
#include "spi.h"

#define SPI_KHZ         1000    // 1MHz
#define DEASSERT_TICKS  10
#define DECODE          0

// Port declarations
on tile[0] : out port p_spi_ss[1]           = {XS1_PORT_1A}; //00
on tile[0] : out buffered port:32 p_spi_clk = XS1_PORT_1B; //01
on tile[0] : out buffered port:32 p_spi_da  = XS1_PORT_1C; //10
on tile[0] : clock clk_spi                  = XS1_CLKBLK_1;

//Assumes B encoding
void print_nums(client interface spi_master_if i_spi, char nums[8]){
    for (int i=0; i<8; i++){
        i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
        if (nums[i] == ' ') {
            i_spi.transfer8(8 - i); i_spi.transfer8(0xf); // off
            i_spi.end_transaction(DEASSERT_TICKS);
            continue;
        }
        i_spi.transfer8(8 - i); i_spi.transfer8(nums[i] - '0');
        i_spi.end_transaction(DEASSERT_TICKS);
    }
}

typedef struct digit_t {
    char digit;
    unsigned char bitmap;
} digit_t;

static const digit_t digit_map[] = {
         //.abcdefg.
  {'0',  0b01111110},
  {'1',  0b00110000},
  {'2',  0b01101101},
  {'3',  0b01111001},
  {'4',  0b00110011},
  {'5',  0b01011011},
  {'6',  0b01011111},
  {'7',  0b01110000},
  {'8',  0b01111111},
  {'9',  0b01111011},
  {' ',  0b00000000},
  {'P',  0b01100111},
  {'W',  0b00011110},
  {'w',  0b00111100},
  {'r',  0b00000101},
  {'E',  0b01001111},
  {'A',  0b01110111},
  {'F',  0b01000111},
  {'Y',  0b00111011},
  {'-',  0b00000001},
  {'V',  0b00111110},
  {'T',  0b00001111},
  {'D',  0b00111101},
  {'B',  0b00011111},
  {'L',  0b00001110},
  {'O',  0b01111110},
};

static void led_print_str(client interface spi_master_if i_spi, char digits[8], unsigned dec_pt){
    for (int i=0; i<8; i++){
        char digit = digits[i];
        unsigned char bitmap;
        if ((i > 0) && (i == (7 - dec_pt)))
          bitmap = 0x80; // Decimal point
        else 
          bitmap = 0x00; // Blank
        for (int d = 0; d < (sizeof(digit_map)/sizeof(digit_t)); ++d){
            if (digit_map[d].digit == digit) bitmap |= digit_map[d].bitmap;
        }

        i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
        i_spi.transfer8(8 - i); i_spi.transfer8(bitmap); // off
        i_spi.end_transaction(DEASSERT_TICKS);
    }
}

void app(client interface spi_master_if i_spi){
    for (int i=0; i<8; i++){
        i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
        i_spi.transfer8(i + 1); i_spi.transfer8(0xf); // clear digit
        i_spi.end_transaction(DEASSERT_TICKS);
    }

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
#if DECODE
    i_spi.transfer8(0x9); i_spi.transfer8(0xff); // code b decode for all digits
#else
    i_spi.transfer8(0x9); i_spi.transfer8(0x00); // bit map for all digits
#endif
    i_spi.end_transaction(DEASSERT_TICKS);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xa); i_spi.transfer8(0x0f); // max brightness
    i_spi.end_transaction(DEASSERT_TICKS);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xb); i_spi.transfer8(0x7); // all digits on
    i_spi.end_transaction(DEASSERT_TICKS);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xc); i_spi.transfer8(0x1); // out of low power mode
    i_spi.end_transaction(DEASSERT_TICKS);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xf); i_spi.transfer8(0x0); // not test mode
    i_spi.end_transaction(DEASSERT_TICKS);

    timer t;
    unsigned time_datum, time_now;

    t :> time_datum;

    while(1){
        t :> time_now;

        char str[8];
        sprintf(str, "%8d", (time_now - time_datum)/100);
        sprintf(str, "BAT 1347");
        printf("%s\n", str);
#if DECODE
        print_nums(i_spi, str);
#else
        led_print_str(i_spi, str, 2);
#endif
    }

}


/* "main" function that sets up two uarts, console and the application */
int main() {
  interface spi_master_if i_spi[1];
 
  par {
    on tile[0]: app(i_spi[0]);
    on tile[0]: spi_master(i_spi, 1, p_spi_clk, p_spi_da, null, p_spi_ss, 1, clk_spi);
  }
  return 0;
}
