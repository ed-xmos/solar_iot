/*
 * fifo.xc
 *
 *  Created on: 13 Jun 2017
 *      Author: Ed
 */
#include <string.h>
#include "fifo.h"

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
