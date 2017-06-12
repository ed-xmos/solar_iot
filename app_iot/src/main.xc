// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <uart.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

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
  ESP_ERROR = -1,
  ESP_TIMEOUT = -2
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

//Character based string search
#define SEARCH_STR_MAX_LEN  64
typedef struct match_t {
    char search_str[SEARCH_STR_MAX_LEN];
    unsigned chars_found;
    unsigned len;
    unsigned valid;
} match_t;

typedef enum search_result_t {
    SEARCH_NOT_FOUND,
    SEARCH_FOUND,
} search_result_t;

void init_match(match_t *match, char search_str[]){
    strcpy(match->search_str, search_str);
    match->len = strlen(match->search_str);
    match->chars_found = 0;
    if (match->len > 0) match->valid = 1;
}

search_result_t match_str(match_t *match, char chr[]){
    if (chr == match->search_str[match->chars_found]){
        match->chars_found++;
    }
    else match->chars_found = 0;
    if (match->chars_found == match->len){
        match->chars_found = 0;
        return SEARCH_FOUND;
    }
    return SEARCH_NOT_FOUND;
}

//FIFO stuff
#define FIFO_SIZE   128

typedef enum fifo_ret_t {
  FIFO_SUCCESS = 0,
  FIFO_FULL,
  FIFO_EMPTY
} fifo_ret_t;

typedef unsigned char fifo_buff_t;
typedef fifo_buff_t * unsafe fifo_ptr_t;

typedef struct fifo_t{
    fifo_buff_t fifo_buff[FIFO_SIZE];
    fifo_ptr_t wr;
    fifo_ptr_t rd;
} fifo_t;

void fifo_init(fifo_t *fifo) {
  unsafe {
    memset(fifo->fifo_buff, 0, FIFO_SIZE);
    fifo->wr = &fifo->fifo_buff[0];
    fifo->rd = &fifo->fifo_buff[0];
    }
}

fifo_ret_t fifo_push(fifo_t *fifo, unsigned char data){
  unsafe {
    fifo_ptr_t wr_next = fifo->wr + 1;
    if (wr_next > &fifo->fifo_buff[FIFO_SIZE-1]) wr_next = &fifo->fifo_buff[0]; //Check for wrap
    if (wr_next == fifo->rd) return FIFO_FULL;
    *(fifo->wr) = data;
    fifo->wr = wr_next;
    return FIFO_SUCCESS;
  }
}

fifo_ret_t fifo_pop(fifo_t *fifo, unsigned char *data){
  unsafe{
    if (fifo->wr == fifo->rd) return FIFO_EMPTY;
    *data = *(fifo->rd);
    fifo->rd++;
    if (fifo->rd > &fifo->fifo_buff[FIFO_SIZE-1]) fifo->rd = fifo->fifo_buff; //Check for wrap
    return FIFO_SUCCESS;
  }
}

//String reverser helper function
unsafe {
    static char * unsafe revStr (char *str)  {
        char tmp, *src, *dst;
        size_t len;
        if (str != NULL)
        {
            len = strlen (str);
            if (len > 1) {
                src = str;
                dst = src + len - 1;
                while (src < dst) {
                    tmp = *src;
                    //*src++ = *dst;
                    *src = *dst;
                    src++;
                    //*dst-- = tmp;
                    *dst = tmp;
                    dst--;
                }
            }
        }
        return str;
    }
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

void app_input(client uart_tx_if uart_tx)
{
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
    char rx_history[RX_BUFFER_SIZE];
    unsigned rx_hist_wr_idx;

    match_t error;
    init_match(&error, "error");

    match_t ok;
    init_match(&ok, "OK\n\r");

    match_t custom;
    init_match(&custom, "");

    fifo_t fifo;
    fifo_init(&fifo);

    while(1){
        select{
            case i_esp.send_cmd_ack(esp_commands_t command, unsigned timeout_s):
                //i_esp.esp_event();
                break;
            case i_esp.send_cmd_search_ack(esp_commands_t command, char * search_term, unsigned timeout_s):
                //i_esp.esp_event();
                break;
            case i_esp.check_event(void) -> esp_event_t event:
                event = last_event;
                break;

            case i_uart_rx.data_ready(void):
                char rx = i_uart_rx.read();

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
                        BAUD_RATE, UART_PARITY_NONE, 8, 1,
                        i_gpio_tx[0]);
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
