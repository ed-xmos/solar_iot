/*
 * app_settings.h
 *
 *  Created on: 16 Jun 2017
 *      Author: Ed
 */


#ifndef APP_SETTINGS_H_
#define APP_SETTINGS_H_

#define BAUD_RATE 					115200
#define RX_BUFFER_SIZE 				4096
#define TX_BUFFER_SIZE 				512
#define SECOND_TICKS   				100000000 //How many timer ticks in 1 second

#define SOLAR_BAUD_RATE 			19200
#define SOLAR_RX_BUFFER_SIZE 	    128

#define SPI_KHZ         			1000    // 1MHz
#define DEASSERT_TICKS  			10      // 100ns

#define THINGSPEAK_UPDATE_S 	    30
#define DISPLAY_UPDATE_S            5

#define SOLAR_SIM							0 //Task which streams simulated MPPT data

#include "credentials.h"   //File cotaining #define SSID <my-ssid> and #define PASSWORD <my-ap-passord> and #define THINGSPEAKEY  <key>

#endif /* APP_SETTINGS_H_ */
