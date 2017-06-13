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

// Port declarations
port p_uart_rx = on tile[0] : XS1_PORT_1G; //22
port p_uart_tx = on tile[0] : XS1_PORT_1H; //23
port p_ch_pd   = on tile[0] : XS1_PORT_1I; //24

#define BAUD_RATE 116200    //FOund to be more stable at this rate compared with 119200
#define RX_BUFFER_SIZE 128

typedef enum esp_commands_t {
  ESP_CONNECT
}esp_commands_t;

typedef enum esp_event_t {
  ESP_OK = 0,
  ESP_SEARCH_FOUND = 1,
  ESP_RESPONSE_READY = 2,
  ESP_ERROR = -1,
  ESP_TIMEOUT = -2,
}esp_event_t;


typedef interface i_esp_console {
  void send_cmd_ack(esp_commands_t command, unsigned timeout_s);
  void send_cmd_search_ack(esp_commands_t command, char *search, unsigned timeout_s);
  [[notification]] slave void esp_event(void);
  [[clears_notification]] esp_event_t check_event(void);
}i_esp_console;

typedef interface i_esp_event {
  [[notification]] slave void esp_event(void);
  [[clears_notification]] esp_event_t check_event(void);
}i_esp_event;

int ok_flag = 0;
int err_flag = 0;
int cmd_flag = 0;

unsafe{
  volatile int * unsafe ok_flag_ptr = &ok_flag;
  volatile int * unsafe err_flag_ptr = &err_flag;
  volatile int * unsafe cmd_flag_ptr = &cmd_flag;

}

static void fail(char * str){
    printstrln(str);
}

void app_output( client uart_rx_if uart_rx)
{
  printstrln("Output console started");
  char rx_history[6] = {0};
  while(1) {
    char rx = uart_rx.wait_for_data_and_read();
    //shift FIFO along
    rx_history[5] = rx_history[4];
    rx_history[4] = rx_history[3];
    rx_history[3] = rx_history[2];
    rx_history[2] = rx_history[1];
    rx_history[1] = rx_history[0];
    rx_history[0] = rx;        
    printchar(rx);
    if (!memcmp(rx_history, "KO\n\r", 4)) unsafe {
      unsafe {*ok_flag_ptr = 1;}
    }
    if (!memcmp(rx_history, "RORRE", 6)) unsafe {
      unsafe {*err_flag_ptr = 1;}
    }
    if (!memcmp(rx_history, "sutats", 6)) unsafe {
      unsafe {*cmd_flag_ptr = 1;}
    }
  }
}

static int send_cmd_ack(const char *send_string, client uart_tx_if uart_tx)
{
  int ret_val = -1; //error
  size_t len = strlen(send_string);
  for(size_t j = 0; j < len; j++) {
    uart_tx.write(send_string[j]);
  }
  uart_tx.write('\r');
  uart_tx.write('\n');
  unsafe {
    while(!*ok_flag_ptr && !*err_flag_ptr);
    if (*err_flag_ptr) {
      *err_flag_ptr = 0;
      ret_val = -1;
      printstr("\n**ERROR running cmd: ");
      printstrln(send_string);
    }
    if (*ok_flag_ptr) {
      *ok_flag_ptr = 0;
      ret_val = 0;
    }
  }
  return ret_val;
}

const char s0[] = "AT+GMR"; //Firmware info
const char s1[] = "AT+CWMODE=3";  //AP & client
const char s2[] = "AT+CWLAP"; //List AP
const char s3[] = "AT+CWJAP=\"Badger\",\"mouse2000\"";
const char s4[] = "AT+CIFSR"; //get IP address
const char s5[] = "AT+CIPMUX=1";  //Enable multiple connections
const char s6[] = "AT+CIPSERVER=1,80"; //run a TCP server on port 80
const char s7[] = "AT+CIPSTART=0,\"TCP\",\"192.168.1.5\",6123"; //Connect as client
const char s8[] = "AT+CIPSEND=0,10"; //Send packet
const char s9[] = "Power=100W";

void app_input(client uart_tx_if uart_tx)
{

  //send_cmd_ack(s0, uart_tx);

  send_cmd_ack(s4, uart_tx);
  //send_cmd_ack(s1, uart_tx);
  //send_cmd_ack(s2, uart_tx);
  //send_cmd_ack(s3, uart_tx);
  //send_cmd_ack(s4, uart_tx);
  send_cmd_ack(s5, uart_tx);
  send_cmd_ack(s6, uart_tx);
  //delay_seconds(1);
  send_cmd_ack(s7, uart_tx);
  while(1) unsafe {
    if (*cmd_flag_ptr) {
      printstrln("**STATUS**");
      *cmd_flag_ptr = 0;
      send_cmd_ack(s8, uart_tx);
      send_cmd_ack(s9, uart_tx);
    }
  }
}


void esp_console_task(server i_esp_console i_esp, client uart_tx_if i_uart_tx, client uart_rx_if i_uart_rx) {

    esp_event_t last_event = ESP_OK;

    char response[FIFO_SIZE] = {0};

    fifo_t rx_fifo;
    fifo_init(&rx_fifo);

    timer timeout_t;
    int timeout_trig;
    int timer_enabled = 0;

    match_t error;
    init_match(&error, "ERROR");

    match_t ok;
    init_match(&ok, "OK");

    match_t custom;
    init_match(&custom, "");

    match_t newline;
    init_match(&custom, "\n\r");

    fifo_t fifo;
    fifo_init(&fifo);

    while(1){
        select{
            case i_esp.send_cmd_ack(esp_commands_t command, unsigned timeout_s):
                for (int i = 0; i < strlen(s2); i++) i_uart_tx.write(s2[i]);
                break;
            case i_esp.send_cmd_search_ack(esp_commands_t command, char * search_term, unsigned timeout_s):
                //i_esp.esp_event();
                break;
            case i_esp.check_event(void) -> esp_event_t event:
                event = last_event;
                break;

            case i_uart_rx.data_ready(void):
                char rx = i_uart_rx.read();
                if (fifo_push(&fifo, rx) != FIFO_SUCCESS) fail("Fifo full");
                int is_newline = match_str(&newline, rx);
                int is_ok = match_str(&ok, rx);
                int is_custom = match_str(&custom, rx);
                int is_error = match_str(&error, rx);
                if (is_error) {
                    last_event = ESP_ERROR;
                    i_esp.esp_event();
                    break;
                }
                if (is_custom) {
                    last_event = ESP_SEARCH_FOUND;
                    i_esp.esp_event();
                    break;
                }
                if (is_ok) {
                    last_event = ESP_OK;
                    break;
                }
                if (is_newline) {
                    char chr;
                    for (char * response_ptr = response; FIFO_EMPTY != fifo_pop(&fifo, &chr);) {
                        *response_ptr = chr;
                        response_ptr++;
                    }
                    printstr(response);
                }
                break;


            case timer_enabled => timeout_t when timerafter(timeout_trig) :> void:
                timer_enabled = 0;
                last_event = ESP_TIMEOUT;
                i_esp.esp_event();
                break;
        }
    }
}


/* "main" function that sets up two uarts and the application */
int main() {
  interface uart_rx_if i_rx;
  interface uart_tx_if i_tx;
  input_gpio_if i_gpio_rx;
  output_gpio_if i_gpio_tx[1];
  par {
    on tile[0]: output_gpio(i_gpio_tx, 1, p_uart_tx, null);
    on tile[0]: uart_tx(i_tx, null,
                        BAUD_RATE, UART_PARITY_NONE, 8, 1, i_gpio_tx[0]);
    on tile[0].core[0] : input_gpio_1bit_with_events(i_gpio_rx, p_uart_rx);
    on tile[0].core[0] : uart_rx(i_rx, null, RX_BUFFER_SIZE,
                                 BAUD_RATE, UART_PARITY_NONE, 8, 1,
                                 i_gpio_rx);
    on tile[0]: {
      p_ch_pd <: 1;
      app_input(i_tx);
    }
    on tile[0]: app_output(i_rx);
  }
  return 0;
}
