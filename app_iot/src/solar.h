#include "app_settings.h"
#include "spi.h"
#include "uart.h"
#include "random.h"
#include "match.h"
#include "LED_MAX7219.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>


void solar_sim(client uart_tx_if i_uart_tx);
unsafe void solar_decoder(client uart_rx_if i_uart_rx, client interface spi_master_if i_spi);
