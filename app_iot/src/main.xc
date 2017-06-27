// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <uart.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

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
const char connect[]        = CONNECT;
const char get_ip[]         = "AT+CIFSR"; //get IP address
const char enable_conns[]   = "AT+CIPMUX=1";  //Enable multiple connections
const char run_tcp_serv[]   = "AT+CIPSERVER=1,80"; //run a TCP server on port 80
const char conn_client[]    = "AT+CIPSTART=0,\"TCP\",\"192.168.1.4\",6123"; //Connect as client
const char cmd_send_packet[]= "AT+CIPSEND=0,10"; //Send packet
const char a_message[]      = "Power=100W";

static void fail(esp_event_t outcome, char * response){
    char outcome_msg[32];
    event_to_text(outcome, outcome_msg);
    printf("Response: %sOutcome: %s\n", response, outcome_msg);
    //_Exit(-1);
}

static void do_esp(client i_esp_console i_esp, const char * cmd, char * response){
    esp_event_t outcome;
    outcome = send_cmd_ack(i_esp, cmd, response, 10);
    printf("Response: %s", response);
    if (outcome != ESP_OK) fail(outcome, response);
}

void app_new(client i_esp_console i_esp){
    char response[RX_BUFFER_SIZE] = {0};
    //esp_event_t outcome;

    do_esp(i_esp, set_ap_mode, response);
    do_esp(i_esp, list_ap, response);
    do_esp(i_esp, connect, response);
    do_esp(i_esp, get_ip, response);

    do_esp(i_esp, enable_conns, response);
    do_esp(i_esp, conn_client, response);

    do_esp(i_esp, cmd_send_packet, response);
    do_esp(i_esp, a_message, response);

    do_esp(i_esp, run_tcp_serv, response);

#if 0
    i_esp.send_cmd_noack(list_ap, 10);
    if(ESP_OK != (outcome = esp_wait_for_event(i_esp, response))) fail(outcome, response);
    printf("Response: %s", response);

    outcome = send_cmd_search_ack(i_esp, get_ip, response, "APIP", 1);
    if (outcome == ESP_SEARCH_FOUND){
        printf("**FOUND**");
        if(ESP_OK != (outcome = esp_wait_for_event(i_esp, response))) fail(outcome, response);
    }
    printf("Response: %s", response);
#endif

    printf("**Finished test**\n");

    while(1){
        esp_wait_for_event(i_esp, response);
        printf("Response: %s", response);
    }
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
