/*
 * fifo.h
 *
 *  Created on: 13 Jun 2017
 *      Author: Ed
 */

#ifndef FIFO_H_
#define FIFO_H_

//FIFO stuff
#define FIFO_SIZE   128

typedef enum fifo_ret_t {
  FIFO_SUCCESS = 0,
  FIFO_FULL,
  FIFO_EMPTY
} fifo_ret_t;

typedef char fifo_buff_t;
typedef fifo_buff_t * unsafe fifo_ptr_t;

typedef struct fifo_t{
    fifo_buff_t fifo_buff[FIFO_SIZE];
    fifo_ptr_t wr;
    fifo_ptr_t rd;
} fifo_t;

void fifo_init(fifo_t *fifo);
fifo_ret_t fifo_push(fifo_t *fifo, unsigned char data);
fifo_ret_t fifo_pop(fifo_t *fifo, unsigned char *data);

#endif
