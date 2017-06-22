// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <uart.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "match.h"
#include "fifo.h"
#include "esp_console.h"

#include "app_settings.h"

// Port declarations
port p_uart_rx = on tile[0] : XS1_PORT_1G; //22
port p_uart_tx = on tile[0] : XS1_PORT_1H; //23
port p_ch_pd   = on tile[0] : XS1_PORT_1I; //24

const char fw_info[]        = "AT+GMR"; //Firmware info
const char set_ap_mode[]    = "AT+CWMODE=3";  //AP & client
const char list_ap[]        = "AT+CWLAP"; //List AP
const char connect[]        = "AT+CWJAP=\"Badger\",\"Mouse2000\"";
const char get_ip[]         = "AT+CIFSR"; //get IP address
const char enable_conns[]   = "AT+CIPMUX=1";  //Enable multiple connections
const char run_tcp_serv[]   = "AT+CIPSERVER=1,80"; //run a TCP server on port 80
const char conn_client[]    = "AT+CIPSTART=0,\"TCP\",\"192.168.1.5\",6123"; //Connect as client
const char cnd_send_packet[]= "AT+CIPSEND=0,10"; //Send packet
const char a_message[]      = "Power=100W";

void app_new(client i_esp_console i_esp){
    char response[RX_BUFFER_SIZE] = {0};
    char outcome_msg[32] = {0};
    esp_event_t outcome;

    memset(response, 0, RX_BUFFER_SIZE);
    outcome = i_esp.send_cmd_ack(fw_info, response, 10);
    event_to_text(outcome, outcome_msg);
    printf("Response: %s, outcome: %s\n", response, outcome_msg);

    i_esp.send_cmd_noack(get_ip, 1);
    memset(response, 0, RX_BUFFER_SIZE);
    outcome = esp_wait_for_event(i_esp, response);
    event_to_text(outcome, outcome_msg);
    printf("Response: %s, outcome: %s\n", response, outcome_msg);

}

/* "main" function that sets up two uarts, console and the application */
int main() {
  interface uart_rx_if i_rx;
  interface uart_tx_if i_tx;
  input_gpio_if i_gpio_rx;
  output_gpio_if i_gpio_tx[1];

  i_esp_console i_esp;
  par {
    on tile[0]: output_gpio(i_gpio_tx, 1, p_uart_tx, null);
    on tile[0]: uart_tx(i_tx, null,
                        BAUD_RATE, UART_PARITY_NONE, 8, 1, i_gpio_tx[0]);
    on tile[0].core[0] : input_gpio_1bit_with_events(i_gpio_rx, p_uart_rx);
    on tile[0].core[0] : uart_rx(i_rx, null, RX_BUFFER_SIZE,
                                 BAUD_RATE, UART_PARITY_NONE, 8, 1,
                                 i_gpio_rx);

    on tile[0]: app_new(i_esp);
    on tile[0]: esp_console_task(i_esp, i_tx, i_rx);
  }
  return 0;
}
