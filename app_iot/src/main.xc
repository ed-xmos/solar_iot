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
port p_ch_pd   = on tile[0] : XS1_PORT_1I; //24 pull down output only
port p_uart_solar_rx = on tile[0] : XS1_PORT_1J;//25

const char fw_info[]        = "AT+GMR"; //Firmware info
const char reset[]          = "AT+RST"; //Restart ends with "ready"
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
const char msg_unformatted[]="field1=%d&field2=%d&field3=%d&field4=%d&field5=%d&field6=%d";

char mppt[] = "\r\nPID\t0xA043\r\nFW\t116\r\nSER#\tHQ1517557PE\r\nV\t13470\r\nI\t140\r\nVPV\t32100\r\nPPV\t20\r\nCS\t0\r\nERR\t0\r\nLOAD\tON\r\nIL\t2320\r\nH19\t0\r\nH20\t30\r\nH21\t222\r\nH22\t0\r\nH23\t0\r\nHSDS\t0\r\nChecksum\t'184'\r\n";

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
    printf("Cmd: %s Response: %s", cmd, response);
    if (outcome != ESP_OK) fail(outcome, response);
}

static void send_tcp(client i_esp_console i_esp, const char * pkt){
    esp_event_t outcome;
    char response[RX_BUFFER_SIZE];
    char sendcmd[TX_BUFFER_SIZE];
    sprintf(sendcmd, send_varlen, strlen(pkt) + 2);
    outcome = send_cmd_ack(i_esp, sendcmd, response, 1);
    printf("Response: %s", response);
    if (outcome != ESP_OK) fail(outcome, response);
    outcome = send_cmd_ack(i_esp, pkt, response, 1);
    printf("Response: %s", response);
    if (outcome != ESP_OK) fail(outcome, response);
}

// Update the value if
unsigned process_line(const char * field, const char * line, unsigned current){
    unsigned ret = current;
    char * outcome = strstr(line, field);
    if (outcome && (outcome == line)) {
        ret = atoi(outcome + strlen(field));
        printf("field: %s val: %d\n", field, ret);
    }
    return ret;
}


unsigned power = 0;
unsigned peak_power = 0;
unsigned yield = 0;
unsigned v_batt_mv = 0;
unsigned i_batt_ma = 0;
unsigned efficiency_2dp = 0;
unsigned i_load_ma = 0;

unsafe{
    volatile unsigned * unsafe power_ptr = &power;
    volatile unsigned * unsafe peak_power_ptr = &peak_power;
    volatile unsigned * unsafe yield_ptr = &yield;
    volatile unsigned * unsafe v_batt_mv_ptr = &v_batt_mv;
    volatile unsigned * unsafe i_batt_ma_ptr = &i_batt_ma;
    volatile unsigned * unsafe efficiency_2dp_ptr = &efficiency_2dp;
    volatile unsigned * unsafe i_load_ma_ptr = &i_load_ma;
}

void solar_decoder(client uart_rx_if i_uart_rx){
    match_t newline;
    init_match(&newline, "\r\n");
    char line[SOLAR_RX_BUFFER_SIZE];
    unsigned line_idx = 0;

    char * str = mppt;

    while(1){
        select{
            //case i_uart_rx.data_ready(void):
            default:
                delay_milliseconds(1000);
                //char rx = i_uart_rx.read();
                char rx = *str; ++str; if (str == (mppt + strlen(mppt))) str = mppt;
                //printchar(rx);
                line[line_idx] = rx;
                ++line_idx;
                if(line_idx == SOLAR_RX_BUFFER_SIZE){
                    printf("Solar line overflow: %s\n", line);
                    line_idx = 0;
                }
                int is_newline = match_str(&newline, rx);
                if (is_newline){
                    line[line_idx] = 0;
                    line_idx = 0;
                    unsafe{
                        *power_ptr          = process_line("PPV\t", line, *power_ptr);
                        *peak_power_ptr     = process_line("H21\t", line, *peak_power_ptr);
                        *yield_ptr          = process_line("H20\t", line, *yield_ptr);
                        *v_batt_mv_ptr      = process_line("V\t", line, *v_batt_mv_ptr);
                        *i_batt_ma_ptr      = process_line("I\t", line, *i_batt_ma_ptr);
                        *i_load_ma_ptr      = process_line("IL\t", line, *i_load_ma_ptr);
                        unsigned tmp = (((*i_load_ma_ptr + *i_batt_ma_ptr) * *v_batt_mv_ptr) / 10000);
                        if (tmp) *efficiency_2dp_ptr = *power_ptr / tmp; //Avoid divide by zero
                        else *efficiency_2dp_ptr = 0;
                    }
                }
                break;
        }
    }
}

void app(client i_esp_console i_esp){
    char response[RX_BUFFER_SIZE] = {0};
    char msg[TX_BUFFER_SIZE] = {0};

    printf("**Test started**\n");

    power = 85;
    peak_power = 120;

    v_batt_mv = 13640;
    i_batt_ma = 423;
    efficiency_2dp = 9221;

    for (int i = 0; i < 10; ++i){
        char event_type[32];

        esp_event_t event = ESP_NO_EVENT;
        while (event != ESP_OK){
            i_esp.send_cmd_search_noack(reset, "ready", 10);
            event = esp_wait_for_event(i_esp, response);
            event_to_text(event, event_type);
            printf("RST EVENT: %s\n", event_type);
        }
        event = esp_wait_for_event_timeout(i_esp, response,5);
        event_to_text(event, event_type);
        printf("RST EVENT: %s\n", event_type);
        if (event == ESP_SEARCH_FOUND) break;
        delay_seconds(5);
    }

    do_esp_cmd(i_esp, get_ip);
    do_esp_cmd(i_esp, enable_conns);

    char sendstr[TX_BUFFER_SIZE];
    sprintf(msg, msg_unformatted, power, peak_power, yield, i_batt_ma, v_batt_mv, efficiency_2dp); //Create the payload
    sprintf(sendstr, update_thingspeak, strlen(msg)); //Format the update message with msg length

    printf("sendstr.len=%d", strlen(sendstr));

    do_esp_cmd(i_esp, conn_thingspeak); //Open TCP

    send_tcp(i_esp, sendstr);       //start sending
    send_tcp(i_esp, msg);           //payload

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

  interface uart_rx_if i_solar_rx;
  input_gpio_if i_gpio_solar_rx;

  i_esp_console i_esp;
  par {
    on tile[0]: output_gpio(i_gpio_tx, 1, p_uart_tx, null);
    on tile[0]: uart_tx(i_tx, null,
                        BAUD_RATE, UART_PARITY_NONE, 8, 1, i_gpio_tx[0]);
    on tile[0].core[0] : input_gpio_1bit_with_events(i_gpio_rx, p_uart_rx);
    on tile[0].core[0] : uart_rx(i_rx, null, RX_BUFFER_SIZE,
                                 BAUD_RATE, UART_PARITY_NONE, 8, 1,
                                 i_gpio_rx);

    on tile[0].core[0] : input_gpio_1bit_with_events(i_gpio_solar_rx, p_uart_solar_rx);
    on tile[0].core[0] : uart_rx(i_solar_rx, null, SOLAR_RX_BUFFER_SIZE,
                                 SOLAR_BAUD_RATE, UART_PARITY_NONE, 8, 1,
                                 i_gpio_solar_rx);

    on tile[0]: app(i_esp);
    on tile[0]: esp_console_task(i_esp, i_tx, i_rx);

    on tile[0]: solar_decoder(i_solar_rx);
  }
  return 0;
}
