// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <uart.h>

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
const char connect[]        = CONNECT;  //Defined in esp_console.h
const char get_ip[]         = "AT+CIFSR"; //get IP address
const char enable_conns[]   = "AT+CIPMUX=1";  //Enable multiple connections
const char run_tcp_serv[]   = "AT+CIPSERVER=1,80"; //run a TCP server on port 80
const char conn_client[]    = "AT+CIPSTART=0,\"TCP\",\"192.168.1.4\",6123"; //Connect as client
const char cmd_send_packet[]= "AT+CIPSEND=0,10"; //Send packet
const char conn_thingspeak[]= "AT+CIPSTART=0,\"TCP\",\"api.thingspeak.com\",80"; //Connect to thingspeak
const char conn_close[]     = "AT+CIPCLOSE=0";
const char send_varlen[]= "AT+CIPSEND=0,%d";
const char update_thingspeak[] = "POST /update HTTP/1.1\nHost: api.thingspeak.com\nConnection: close\nX-THINGSPEAKAPIKEY: " THINGSPEAKKEYSTR "\nContent-Type: application/x-www-form-urlencoded\nContent-Length: %d\n";
const char a_message[]      = "Power=100W";
const char msg_unformatted[]="field1=%d&field2=%d&field3=%d&field4=%.2f&field5=%.2f&field6=%.1f";


static void fail(esp_event_t outcome, char * response){
    char outcome_msg[32];
    event_to_text(outcome, outcome_msg);
    printf("Outcome: %s, Response: %s\n", outcome_msg, response);
    //_Exit(-1);
}

static void do_esp_cmd(client i_esp_console i_esp, const char * cmd){
    esp_event_t outcome;
    char response[RX_BUFFER_SIZE];
    outcome = send_cmd_ack(i_esp, cmd, response, 10);
    printf("Response: %s", response);
    if (outcome != ESP_OK) fail(outcome, response);
}

static void send_tcp(client i_esp_console i_esp, const char * pkt){
    esp_event_t outcome;
    char response[RX_BUFFER_SIZE];
    char sendcmd[512];
    sprintf(sendcmd, send_varlen, strlen(pkt) + 2);
    outcome = send_cmd_ack(i_esp, sendcmd, response, 1);
    printf("Response: %s", response);
    if (outcome != ESP_OK) fail(outcome, response);
    outcome = send_cmd_ack(i_esp, pkt, response, 1);
    printf("Response: %s", response);
    if (outcome != ESP_OK) fail(outcome, response);
}

void app(client i_esp_console i_esp){
    char response[RX_BUFFER_SIZE] = {0};
    char msg[256] = {0};

    unsigned power = 0;
    unsigned peak_power = 0;
    unsigned yield = 0;

    float v_batt = 0;
    float i_batt = 0;
    float efficiency = 0;

    power = 85;
    peak_power = 120;

    v_batt = 13.6124;
    i_batt = 0.42765;
    efficiency = 92.2142;

    do_esp_cmd(i_esp, get_ip);
    do_esp_cmd(i_esp, enable_conns);

    char sendstr[512];
    sprintf(msg, msg_unformatted, power, peak_power, yield, i_batt, v_batt, efficiency); //Create the payload
    sprintf(sendstr, update_thingspeak, strlen(msg)); //Format the update message with msg length

    do_esp_cmd(i_esp, conn_thingspeak); //Open TCP

    send_tcp(i_esp, sendstr);   //start sending
    send_tcp(i_esp, msg);       //payload

    do_esp_cmd(i_esp, conn_close);  //Close TCP
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

    on tile[0]: app(i_esp);
    on tile[0]: esp_console_task(i_esp, i_tx, i_rx);
  }
  return 0;
}
