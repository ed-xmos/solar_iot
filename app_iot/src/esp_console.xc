/*
 * esp_console.xc
 *
 *  Created on: 16 Jun 2017
 *      Author: Ed
 */
#include <string.h>
#include <print.h>

#include "esp_console.h"
#include "match.h"

void esp_console_task(server i_esp_console i_esp, client uart_tx_if i_uart_tx, client uart_rx_if i_uart_rx) {

    esp_event_t last_event = ESP_OK;

    char buffer[2][RX_BUFFER_SIZE] = {{0}};
    int dbl_buff_idx = 0;
    int buff_idx = 0;
    int buffer_read = 1;    //Has the last received buffer been read OK
    int buffer_lost = 0;    //Have we overwritten an old buffer?

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

            case i_esp.send_cmd_search_ack(const char * command,  char * response,
                    char * search_term, unsigned timeout_s):
                for (int i = 0; i < strlen(command); i++) i_uart_tx.write(command[i]);
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

            case i_esp.send_cmd_noack(const char * command, unsigned timeout_s):
                for (int i = 0; i < strlen(command); i++) i_uart_tx.write(command[i]);
                i_uart_tx.write('\n');
                i_uart_tx.write('\r');
                if (timeout_s) {
                    timeout_t :> timeout_trig;
                    timeout_trig += (timeout_s * SECOND_TICKS);
                    timer_enabled = 1;
                }
                break;

            case i_esp.send_cmd_search_noack(const char * command, char * search_term, unsigned timeout_s):
                 for (int i = 0; i < strlen(command); i++) i_uart_tx.write(command[i]);
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
                    buffer_lost = (buffer_read == 0) ? 1 : 0;
                    buffer_read = 0;
                    timer_enabled = 0;
                }
                break;


            case i_esp.get_buffer(char * rx_buff) -> esp_result_t is_buffer_lost:
                strcpy(rx_buff, buffer[dbl_buff_idx ^ 1]);
                is_buffer_lost = buffer_lost ? ESP_BUFFER_LOST : ESP_BUFFER_OK;
                buffer_read = 1;
                break;

            case timer_enabled => timeout_t when timerafter(timeout_trig) :> void:
                timer_enabled = 0;
                last_event = ESP_TIMEOUT;
                i_esp.esp_event();
                break;
        }
    }
}


esp_event_t esp_wait_for_event(client i_esp_console i_esp, char * response){
    esp_event_t event;
    select{
        case i_esp.esp_event():
            event = i_esp.check_event();
            i_esp.get_buffer(response);
            break;
    }
    return event;
}


void event_to_text(esp_event_t event, char * string){
    switch (event){
        case ESP_OK:
            strcpy(string, "ESP_OK");
            break;
        case ESP_SEARCH_FOUND:
            strcpy(string, "ESP_SEARCH_FOUND");
            break;
        case ESP_RESPONSE_READY:
            strcpy(string, "ESP_RESPONSE_READY");
            break;
        case ESP_ERROR:
            strcpy(string, "ESP_ERROR");
            break;
        case ESP_TIMEOUT:
            strcpy(string, "ESP_TIMEOUT");
            break;
        default:
            strcpy(string, "ERROR - Unknown event");
            break;
    }
}
