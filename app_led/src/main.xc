// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <stdio.h>
#include "spi.h"

#define SPI_KHZ 1000

// Port declarations
on tile[0] : out port p_spi_ss[1]           = {XS1_PORT_1A}; //00
on tile[0] : out buffered port:32 p_spi_clk = XS1_PORT_1B; //01
on tile[0] : out buffered port:32 p_spi_da  = XS1_PORT_1C; //10
on tile[0] : clock clk_spi                  = XS1_CLKBLK_1;

void print_nums(client interface spi_master_if i_spi, char nums[8]){
    for (int i=0; i<8; i++){
        i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
        if (nums[i] == ' ') {
            i_spi.transfer8(8 - i); i_spi.transfer8(0xf); // off
            i_spi.end_transaction(100);
            continue;
        }
        i_spi.transfer8(8 - i); i_spi.transfer8(nums[i] - '0');
        i_spi.end_transaction(100);
    }

}

void app(client interface spi_master_if i_spi){
    for (int i=0; i<8; i++){
        i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
        i_spi.transfer8(i + 1); i_spi.transfer8(0xf); // clear digit
        i_spi.end_transaction(100);
    }

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0x9); i_spi.transfer8(0xff); // code b decode for all digits
    i_spi.end_transaction(100);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xa); i_spi.transfer8(0x0f); // max brightness
    i_spi.end_transaction(100);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xb); i_spi.transfer8(0x7); // all digits on
    i_spi.end_transaction(100);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xc); i_spi.transfer8(0x1); // out of low power mode
    i_spi.end_transaction(100);

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0xf); i_spi.transfer8(0x0); // not test mode
    i_spi.end_transaction(100);

    timer t;
    unsigned count = 0;

    while(1){
        char str[8];
        sprintf(str, "%8d", count);
        print_nums(i_spi, str);
        ++count;
        delay_milliseconds(1);
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
