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

//Set of defines to build login string from user defined login/password
#define xstr(s) str(s)
#define str(s) #s
#define CN0         "AT+CWJAP=\""
#define CN1         "\",\""
#define CN2         "\""
#define CONNECT     CN0 xstr(SSID) CN1 xstr(PASSWORD) CN2
#define THINGSPEAKKEYSTR xstr(THINGSPEAKKEY)

typedef enum esp_event_t {
  ESP_OK = 0,
  ESP_SEARCH_FOUND = 1,
  ESP_RESPONSE_READY = 2,
  ESP_BUSY = -1,
  ESP_ERROR = -2,
  ESP_TIMEOUT = -3,
  ESP_NO_EVENT = -4
}esp_event_t;

typedef enum esp_result_t {
    ESP_BUFFER_OK = 0,
    ESP_BUFFER_LOST
} esp_result_t;

typedef interface i_esp_console {
  /** Send command string and return straight away
  *
  * Immediately transmits the whole string and sets up a timeout timer
  *
  * \param command  The data to write. Null terminated string.
  * \param timeout  Timeout in seconds
  *
  */
  void send_cmd_noack(const char * command, unsigned timeout_s);

  /** Send command string with search and return straight away
  *
  * Immediately transmits the whole string and sets up a timeout timer
  * Additionally registers a search term which will be sought by the rx case
  *
  * \param command  The data to write. Null terminated string
  * \param search   Search term. Null terminated string
  * \param timeout  Timeout in seconds
  *
  */
  void send_cmd_search_noack(const char * command, char *search, unsigned timeout_s);

  /** Read the last rx buffer
  *
  * Read the contents of the last buffer
  *
  * \param response Pointer to string to be written to with buffer
  *
  * \returns        Whether or not any buffers were overwritten (lost)
  */
  esp_result_t get_buffer(char * response);

  /** Callback indicating an event has occurred during the rx process
  *
  */
  [[notification]] slave void esp_event(void);

  /** Reads source of last event
  *
  * Find out what triggered the last event. Clears event notification at same time
  *
  * \returns        Event code
  */
  [[clears_notification]] esp_event_t check_event(void);
}i_esp_console;

[[combinable]]
/** ESP8266 Console task
*
*  Handles the UART tx and rx and looks for special messages from ESP8266
*  which are turned into events for the client.
*
*    \param i_esp           interface to app
*    \param i_uart_tx       interface enabling console to send data on UART
*    \param i_uart_rx       interface enabling console to receice data from UART
*    \param buffer_size     the size of the transmit buffer in bytes
*/
void esp_console_task(server i_esp_console i_esp, client uart_tx_if i_uart_tx, client uart_rx_if i_uart_rx);

/** Wait until we get an event from ESP8266
*
* Selects on response from ESP8266. Receives last UART rx buffer. Client side function.
*
* \param i_esp              client connection to console
* \param response           Pointer to string to be written to with buffer
*/
esp_event_t esp_wait_for_event(client i_esp_console i_esp, char * response);

/** Wait until we get an event from ESP8266 (or timeout)
*
* Selects on response from ESP8266. Receives last UART rx buffer. Client side function.
*
* \param i_esp              client connection to console
* \param response           Pointer to string to be written to with buffer
*/
esp_event_t esp_wait_for_event_timeout(client i_esp_console i_esp, char * response, unsigned timeout_s);

/** Turns the esp_event_t enum into a string for printing
*
* \param event              event code
* \param string             Pointer to string to be written to with human readable event description
*/
void event_to_text(esp_event_t event, char * string);

/** Send a string and wait until we get an event from ESP8266 (or timeout)
*
* First sends the transmit data. Then Selects on response from ESP8266.
* Receives last UART rx buffer. Client side function.
*
* \param i_esp              client connection to console
* \param command            Pointer to string to be sent to UART
* \param response           Pointer to string to be written to with buffer
* \param timeout_s          Timeout in seconds
*
* \returns                  Last ESP8266 event
*/
esp_event_t send_cmd_ack(client i_esp_console i_esp, const char * command, char * response, unsigned timeout_s);

/** Send a string and wait until we get an event from ESP8266 (or timeout)
*
* First sends the transmit data. Then Selects on response from ESP8266.
* Receives last UART rx buffer. Client side function.
*
* \param i_esp              client connection to console
* \param command            Pointer to string to be sent to UART
* \param response           Pointer to string to be written to with buffer
* \param search             Sets up a search string which can trigger an event
* \param timeout_s          Timeout in seconds
*
* \returns                  Last ESP8266 event
*/
esp_event_t send_cmd_search_ack(client i_esp_console i_esp, const char * command, char * response, char * search, unsigned timeout_s);


#endif /* ESP_CONSOLE_H_ */
