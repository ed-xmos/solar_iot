#include "solar.h"

#define PRINT_SOLAR_DECODE  0

// Update the value if key value found, else leave as is
static unsigned process_line(const char * field, const char * line, unsigned current){
    unsigned ret = current;
    char * outcome = strstr(line, field);
    if (outcome && (outcome == line)) {
        ret = atoi(outcome + strlen(field));
#if PRINT_SOLAR_DECODE
        printf("field: %s val: %d\n", field, ret);
#endif
    }
    return ret;
}


extern unsigned power;
extern unsigned peak_power;
extern unsigned yield;
extern unsigned v_solar_mv;
extern unsigned v_batt_mv;
extern int i_batt_ma;
extern unsigned efficiency_2dp;
extern unsigned i_load_ma;

unsafe{
    volatile unsigned * unsafe power_ptr = &power;
    volatile unsigned * unsafe peak_power_ptr = &peak_power;
    volatile unsigned * unsafe yield_ptr = &yield;
    volatile unsigned * unsafe v_solar_mv_ptr = &v_solar_mv;
    volatile unsigned * unsafe v_batt_mv_ptr = &v_batt_mv;
    volatile int * unsafe i_batt_ma_ptr = &i_batt_ma;
    volatile unsigned * unsafe efficiency_2dp_ptr = &efficiency_2dp;
    volatile unsigned * unsafe i_load_ma_ptr = &i_load_ma;
}

#define INTERVAL_S  10 //MPPT emulator tx interval

void solar_sim(client uart_tx_if i_uart_tx){
    random_generator_t my_rand = random_create_generator_from_hw_seed();
    unsigned watt_seconds = 0;
    unsigned speak_power = 0;
    while(1){
        unsigned spower = 100 + (random_get_random_number(my_rand) % 30);
        speak_power = (speak_power > spower) ? speak_power : spower;
        watt_seconds += spower * INTERVAL_S;
        unsigned syield = watt_seconds / (60 * 60);
        unsigned sv_batt_mv = 13000 + (random_get_random_number(my_rand) % 100);
        unsigned si_batt_ma = 1000 + (random_get_random_number(my_rand) % 1000);
        unsigned si_load_ma = 2000 + (random_get_random_number(my_rand) % 1000);
        unsigned sv_solar_mv = 29000 + (random_get_random_number(my_rand) % 3000);

        char tx_str[64];
        tx_str[0] = 0;


        sprintf(tx_str, "IL\t%d\r\n", si_load_ma);
        for (int i = 0; i < strlen(tx_str); ++i) i_uart_tx.write(tx_str[i]);

        sprintf(tx_str, "PPV\t%d\r\n", spower);
        for (int i = 0; i < strlen(tx_str); ++i) i_uart_tx.write(tx_str[i]);

        sprintf(tx_str, "I\t%d\r\n", si_batt_ma);
        for (int i = 0; i < strlen(tx_str); ++i) i_uart_tx.write(tx_str[i]);

        sprintf(tx_str, "V\t%d\r\n", sv_batt_mv);
        for (int i = 0; i < strlen(tx_str); ++i) i_uart_tx.write(tx_str[i]);

        sprintf(tx_str, "VPV\t%d\r\n", sv_solar_mv);
        for (int i = 0; i < strlen(tx_str); ++i) i_uart_tx.write(tx_str[i]);

        sprintf(tx_str, "H20\t%d\r\n", syield);
        for (int i = 0; i < strlen(tx_str); ++i) i_uart_tx.write(tx_str[i]);

        sprintf(tx_str, "H21\t%d\r\n", speak_power);
        for (int i = 0; i < strlen(tx_str); ++i) i_uart_tx.write(tx_str[i]);

        delay_seconds(INTERVAL_S);
    }
}

typedef enum {
        PPV = 0,
        IL,
        I,
        V,
        H20,
        H21
} led_disp_t;

unsafe void solar_decoder(client uart_rx_if i_uart_rx, client interface spi_master_if i_spi) {
    match_t newline;
    init_match(&newline, "\r\n");
    char line[SOLAR_RX_BUFFER_SIZE];
    unsigned line_idx = 0;

    timer t;
    int disp_time;
    t :> disp_time;

    char led_str[8];
    init_led(i_spi);
    led_disp_t led_disp = PPV;

    while(1){
        select{
            case i_uart_rx.data_ready(void):
                char rx = i_uart_rx.read();
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
                    *power_ptr          = process_line("PPV\t", line, *power_ptr);
                    *peak_power_ptr     = process_line("H21\t", line, *peak_power_ptr);
                    *yield_ptr          = process_line("H20\t", line, *yield_ptr);
                    *v_batt_mv_ptr      = process_line("V\t", line, *v_batt_mv_ptr);
                    *i_batt_ma_ptr      = process_line("I\t", line, *i_batt_ma_ptr);
                    *v_solar_mv_ptr     = process_line("VPV\t", line, *v_solar_mv_ptr);
                    *i_load_ma_ptr      = process_line("IL\t", line, *i_load_ma_ptr);
                    unsigned power_out = (((*i_load_ma_ptr + *i_batt_ma_ptr) * *v_batt_mv_ptr) / 100);
                    if (*power_ptr) *efficiency_2dp_ptr = power_out / *power_ptr; //Avoid divide by zero
                    else *efficiency_2dp_ptr = 0;

                }
                break;

            case t when timerafter(disp_time) :> disp_time:
                unsigned dp = 0;
                switch(led_disp){
                    case PPV:
                        sprintf(led_str, "PSOL%4d", *power_ptr);
                        dp = 0;
                        led_disp = I;
                        break;
                    case I:
                        sprintf(led_str, "IBT%5d", *i_batt_ma_ptr);
                        dp = 3;
                        led_disp = H20;
                        break;
                    case H20:
                        sprintf(led_str, "YLD%5d", *yield_ptr);
                        dp = 2;
                        led_disp = PPV;
                        break;
                }
                led_print_str(i_spi, led_str, dp);
                disp_time += (DISPLAY_UPDATE_S * SECOND_TICKS);

                break;
        }
    }
}
