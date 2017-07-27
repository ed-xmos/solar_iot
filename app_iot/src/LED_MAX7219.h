#include "spi.h"
#include "app_settings.h"
void init_led(client interface spi_master_if i_spi);
/*
Print number and selected digits on to display of 8 7seg modules
param: spi interface
param: string of characters to print (if cannot be found then blank is displayed)
param: decimal point. 0=off 1=after digit 1 etc. (digit 0 is far right or LSD)*/
void led_print_str(client interface spi_master_if i_spi, char digits[8], unsigned dec_pt);