/*
 * match.xc
 *
 *  Created on: 13 Jun 2017
 *      Author: Ed
 */

#include <string.h>
#include "match.h"

void init_match(match_t *match, char search_str[]){
    strcpy(match->search_str, search_str);
    match->len = strlen(match->search_str);
    match->chars_found = 0;
    if (match->len > 0) match->valid = 1;
}

search_result_t match_str(match_t *match, char chr){
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
