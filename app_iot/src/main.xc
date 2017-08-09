// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <uart.h>

#include "match.h"
#include "esp_console.h"
#include "solar.h"
#include "spi.h"

#include "app_settings.h"

// Port declarations ESP8266
port p_uart_rx = on tile[0] : XS1_PORT_1E; //12
port p_uart_tx = on tile[0] : XS1_PORT_1F; //13

// Port declarations for MPPT Solar module
port p_uart_solar_rx = on tile[0] : XS1_PORT_1G;//22
port p_uart_solar_tx = on tile[0] : XS1_PORT_1H;//23

// Port declarations LED
on tile[0] : out port p_spi_ss[1]           = {XS1_PORT_1A}; //00
on tile[0] : out buffered port:32 p_spi_clk = XS1_PORT_1B; //01
on tile[0] : out buffered port:32 p_spi_da  = XS1_PORT_1C; //10
on tile[0] : clock clk_spi                  = XS1_CLKBLK_1;

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
//const char msg_unformatted[]="field1=%d&field2=%d&field3=%d&field4=%d&field5=%d&field6=%d";
//p, pp, yld, ib, v, eff_2dp
const char msg_unformatted[]="field1=%d&field2=%d&field3=%d&field4=%d.%03d&field5=%d.%03d&field6=%d.%02d";


unsigned power = 0;
unsigned peak_power = 0;
unsigned yield = 0;
unsigned v_batt_mv = 0;
unsigned i_batt_ma = 0;
unsigned efficiency_2dp = 0;
unsigned i_load_ma = 0;


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

void app(client i_esp_console i_esp){
    char response[RX_BUFFER_SIZE] = {0};
    char msg[TX_BUFFER_SIZE] = {0};

    printf("**Solar IOT started**\n");

    //Init values
    power = 85;
    peak_power = 120;

    v_batt_mv = 13640;
    i_batt_ma = 423;
    efficiency_2dp = 9221;

    //Try 10 resets
    for (int i = 0; i < 0; ++i){
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

    //do_esp_cmd(i_esp, get_ip);

    while(0){
        delay_seconds(3);
        do_esp_cmd(i_esp, list_ap);
    }
    do_esp_cmd(i_esp, connect);
    do_esp_cmd(i_esp, enable_conns);

    while(1){
        char sendstr[TX_BUFFER_SIZE];
        //sprintf(msg, msg_unformatted, power, peak_power, yield, i_batt_ma, v_batt_mv, efficiency_2dp); //Create the payload
        sprintf(msg, msg_unformatted, power, peak_power, yield, 
            i_batt_ma / 1000, i_batt_ma % 1000, 
            v_batt_mv / 1000, v_batt_mv % 1000, 
            efficiency_2dp / 100, efficiency_2dp % 100
            ); //Create the payload
        printf("%s\n", msg);

        sprintf(sendstr, update_thingspeak, strlen(msg)); //Format the update message with msg length

        //printf("sendstr.len=%d", strlen(sendstr));

        do_esp_cmd(i_esp, conn_thingspeak); //Open TCP

        send_tcp(i_esp, sendstr);       //start sending
        send_tcp(i_esp, msg);           //payload

        do_esp_cmd(i_esp, conn_close);  //Close TCP

        delay_seconds(THINGSPEAK_UPDATE_S);
    }
}

 // Set xCORE tile standby clock to 100MHz from 500MHz System frequency
#define STANDBY_CLOCK_DIVIDER   (5-1)
#define XCORE_CTRL0_CLOCK_MASK  0x30
#define XCORE_CTRL0_ENABLE_AEC  0x30

void enableAEC(unsigned standbyClockDivider)
{
    unsigned xcore_ctrl0_data;
    // Set standby divider
    write_pswitch_reg(get_local_tile_id(),
                XS1_PSWITCH_PLL_CLK_DIVIDER_NUM,
                standbyClockDivider);
    // Modify the clock control bits
    xcore_ctrl0_data = getps(XS1_PS_XCORE_CTRL0);
    xcore_ctrl0_data &= 0xffffffff - XCORE_CTRL0_CLOCK_MASK;
    xcore_ctrl0_data +=  XCORE_CTRL0_ENABLE_AEC;
    setps(XS1_PS_XCORE_CTRL0, xcore_ctrl0_data);
}




/* "main" function that sets up two uarts, console and the application */
int main() {
  interface uart_rx_if i_rx;
  interface uart_tx_if i_tx;

  input_gpio_if i_gpio_rx;
  output_gpio_if i_gpio_tx[1];

  interface uart_rx_if i_solar_rx;
  input_gpio_if i_gpio_solar_rx;

  interface uart_tx_if i_solar_tx;
  output_gpio_if i_gpio_solar_tx[1];

  interface spi_master_if i_spi[1];

  i_esp_console i_esp;
  par {
    
    on tile[0]: output_gpio(i_gpio_tx, 1, p_uart_tx, null);
    on tile[0]: uart_tx(i_tx, null,
                        BAUD_RATE, UART_PARITY_NONE, 8, 1, i_gpio_tx[0]);
    
    on tile[0].core[0] : input_gpio_1bit_with_events(i_gpio_rx, p_uart_rx);
    on tile[0].core[0] : uart_rx(i_rx, null, RX_BUFFER_SIZE,
                                 BAUD_RATE, UART_PARITY_NONE, 8, 1,
                                 i_gpio_rx);
    
    on tile[0].core[1] : input_gpio_1bit_with_events(i_gpio_solar_rx, p_uart_solar_rx);
    on tile[0].core[1] : uart_rx(i_solar_rx, null, SOLAR_RX_BUFFER_SIZE,
                                 SOLAR_BAUD_RATE, UART_PARITY_NONE, 8, 1,
                                 i_gpio_solar_rx);
    
    on tile[0]: {
        enableAEC(STANDBY_CLOCK_DIVIDER);
        app(i_esp, i_spi[1]);
    }
    on tile[0]: esp_console_task(i_esp, i_tx, i_rx);

    on tile[0]: unsafe{ solar_decoder(i_solar_rx, i_spi[0]);}

    on tile[0]: solar_sim(i_solar_tx);
    on tile[0]: output_gpio(i_gpio_solar_tx, 1, p_uart_solar_tx, null);
    on tile[0]: uart_tx(i_solar_tx, null,
                        SOLAR_BAUD_RATE, UART_PARITY_NONE, 8, 1, i_gpio_solar_tx[0]);

    on tile[0]: spi_master(i_spi, 1, p_spi_clk, p_spi_da, null, p_spi_ss, 1, clk_spi);
  }
  return 0;
}
