/*
 * esp_console.h
 *
 *  Created on: 16 Jun 2017
 *      Author: Ed
 */

#ifndef ESP_CONSOLE_H_
#define ESP_CONSOLE_H_

#include "app_settings.h"
#include "uart.h"

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
  void send_cmd_search_ack(const char * command, char * response, char *search, unsigned timeout_s);
  void send_cmd_noack(const char * command, unsigned timeout_s);
  void send_cmd_search_noack(const char * command, char *search, unsigned timeout_s);
  esp_result_t get_buffer(char * response);
  [[notification]] slave void esp_event(void);
  [[clears_notification]] esp_event_t check_event(void);
}i_esp_console;

typedef interface i_esp_rx_server {
  esp_result_t get_buffer(char * rx_buff);
  [[notification]] slave void esp_event(void);
  [[clears_notification]] esp_event_t check_event(void);
}i_esp_event;

void esp_console_task(server i_esp_console i_esp, client uart_tx_if i_uart_tx, client uart_rx_if i_uart_rx);
esp_event_t esp_wait_for_event(client i_esp_console i_esp, char * response);
void event_to_text(esp_event_t event, char * string);


#endif /* ESP_CONSOLE_H_ */