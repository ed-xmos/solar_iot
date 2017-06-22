/*
 * match.xc
 *
 *  Created on: 13 Jun 2017
 *      Author: Ed
 */

#include <string.h>
#include <print.h>
#include "match.h"

void init_match(match_t *match, char search_str[]){
    strcpy(match->search_str, search_str);
    match->len = strlen(match->search_str);
    //printstrln(match->search_str); printintln(match->len);
    match->chars_found = 0;
    if (match->len > 0) match->valid = 1;
    else match->valid = 0;
}

search_result_t match_str(match_t *match, char chr){
    //see if the character matches current posn of search string
    if (chr == match->search_str[match->chars_found]){
        match->chars_found++;
    }

    //if not reset
    else match->chars_found = 0;

    //but...a second bite at the cherry because could be repeated first char
    if (chr == match->search_str[match->chars_found]){
        match->chars_found++;
    }

    //When we have got all characters, return a positive
    if (match->chars_found == match->len){
        match->chars_found = 0;
        if (match->valid) return SEARCH_FOUND;
    }
    return SEARCH_NOT_FOUND;
}
