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

#define BAUD_RATE 116200    //Found to be more stable at this rate compared with 119200
#define RX_BUFFER_SIZE 4096

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

typedef enum esp_result_t {
    ESP_BUFFER_OK = 0,
    ESP_BUFFER_LOST
} esp_result_t;

typedef interface i_esp_console {
  void send_cmd_ack(const char * command, char * response, unsigned timeout_s);
  void send_cmd_search_ack(esp_commands_t command, char *search, unsigned timeout_s);
  void send_cmd_noack(esp_commands_t command, unsigned timeout_s);
  void send_cmd_search_noack(esp_commands_t command, char *search, unsigned timeout_s);
  esp_result_t get_buffer(char * response);
  [[notification]] slave void esp_event(void);
  [[clears_notification]] esp_event_t check_event(void);
}i_esp_console;

typedef interface i_esp_rx_server {
  esp_result_t get_buffer(char * rx_buff);
  [[notification]] slave void esp_event(void);
  [[clears_notification]] esp_event_t check_event(void);
}i_esp_event;

static void fail(char * str){
    printstrln(str);
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

#define SECOND_TICKS   100000000

void esp_console_task(server i_esp_console i_esp, client uart_tx_if i_uart_tx, client uart_rx_if i_uart_rx) {

    esp_event_t last_event = ESP_OK;

    char buffer[2][RX_BUFFER_SIZE] = {{0}};
    int dbl_buff_idx = 0;
    int buff_idx = 0;
    int buffer_read = 1;

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
    init_match(&newline, "\n\r");

    fifo_t fifo;
    fifo_init(&fifo);

    while(1){
        select{
            case i_esp.send_cmd_ack(const char * command, char * response, unsigned timeout_s):
                for (int i = 0; i < strlen(command); i++) i_uart_tx.write(command[i]);
                i_uart_tx.write('\n');
                i_uart_tx.write('\r');

                int lf_found = 0;
                int timed_out = 0;
                timeout_t :> timeout_trig;
                timeout_trig += (timeout_s * SECOND_TICKS);
                while (!lf_found && !timed_out) {
                    char rx = 0;
                    static char rx_last = 0;
                    select{
                        case i_uart_rx.data_ready():
                            rx = i_uart_rx.read();
                            *response = rx;
                            ++response;
                            if (rx == '\r' && rx_last == '\n') lf_found = 1;
                            break;
                        case timeout_t when timerafter(timeout_trig) :> void:
                            timed_out = 1;
                            break;
                    }
                }
                break;

            case i_esp.send_cmd_search_ack(esp_commands_t command, char * search_term, unsigned timeout_s):
                for (int i = 0; i < strlen(s2); i++) i_uart_tx.write(s2[i]);
                i_uart_tx.write('\n');
                i_uart_tx.write('\r');
                init_match(&custom, search_term);
                int lf_found = 1;
                int timed_out = 1;
                timeout_t :> timeout_trig;
                timeout_trig += (timeout_s * SECOND_TICKS);
                while (!lf_found && !timed_out) {
                    char rx = 0;
                    static char rx_last = 0;
                    select{
                        case i_uart_rx.data_ready():
                            rx = i_uart_rx.read();
                            //response[response_idx] = rx;
                            //++response_idx;
                            if (rx == '\r' && rx_last == '\n') lf_found = 1;
                            break;
                        case timeout_t when timerafter(timeout_trig) :> void:
                            timed_out = 1;
                            break;
                    }
                }
                break;

            case i_esp.send_cmd_noack(esp_commands_t command, unsigned timeout_s):
                for (int i = 0; i < strlen(s2); i++) i_uart_tx.write(s2[i]);
                i_uart_tx.write('\n');
                i_uart_tx.write('\r');
                if (timeout_s) {
                    timeout_t :> timeout_trig;
                    timeout_trig += (timeout_s * SECOND_TICKS);
                    timer_enabled = 1;
                }
                break;

            case i_esp.send_cmd_search_noack(esp_commands_t command, char * search_term, unsigned timeout_s):
                 for (int i = 0; i < strlen(s2); i++) i_uart_tx.write(s2[i]);
                 i_uart_tx.write('\n');
                 i_uart_tx.write('\r');
                 init_match(&custom, search_term);
                 if (timeout_s) {
                     timeout_t :> timeout_trig;
                     timeout_trig += (timeout_s * SECOND_TICKS);
                     timer_enabled = 1;
                 }
                break;


            case i_esp.check_event(void) -> esp_event_t event:
                event = last_event;
                break;

            case i_uart_rx.data_ready(void):
                char rx = i_uart_rx.read();
                buffer[dbl_buff_idx][buff_idx] = rx;
                ++buff_idx;
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
                    i_esp.esp_event();
                    break;
                }
                if (is_newline) {
                    buffer[dbl_buff_idx][buff_idx] = 0; //string terminator
                    printstr( buffer[dbl_buff_idx]);
                    dbl_buff_idx ^= 1;
                    buff_idx = 0;
                    buffer_read = 0;
                    timer_enabled = 0;
                }
                break;


            case i_esp.get_buffer(char * rx_buff) -> esp_result_t buffer_lost:
                strcpy(rx_buff, buffer[dbl_buff_idx ^ 1]);
                buffer_lost = ESP_BUFFER_OK;
                break;

            case timer_enabled => timeout_t when timerafter(timeout_trig) :> void:
                timer_enabled = 0;
                last_event = ESP_TIMEOUT;
                i_esp.esp_event();
                break;
        }
    }
}


void app_new(client i_esp_console i_esp){
    char response[RX_BUFFER_SIZE];
    i_esp.send_cmd_ack(s2, response, 10);
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
