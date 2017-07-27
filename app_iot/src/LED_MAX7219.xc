#include "LED_MAX7219.h"

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
  {'R',  0b00000101},
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
  {'I',  0b00110000},
};

void init_led(client interface spi_master_if i_spi){
    for (int i=0; i<8; i++){
        i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
        i_spi.transfer8(i + 1); i_spi.transfer8(0xf); // clear digit RAM
        i_spi.end_transaction(DEASSERT_TICKS);
    }

    i_spi.begin_transaction(0, SPI_KHZ, SPI_MODE_3);
    i_spi.transfer8(0x9); i_spi.transfer8(0x00); // bit map for all digits
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
  }


void led_print_str(client interface spi_master_if i_spi, char digits[8], unsigned dec_pt){
    for (int i=0; i<8; i++){
        char digit = digits[i];
        unsigned char bitmap;
        if ((dec_pt > 0) && (i == (7 - dec_pt)))
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
