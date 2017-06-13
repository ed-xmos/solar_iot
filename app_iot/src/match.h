/*
 * match.h
 *
 * Character based string search
 *
 *
 *  Created on: 13 Jun 2017
 *      Author: Ed
 */
#ifndef MATCH_H_
#define MATCH_H_

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

void init_match(match_t *match, char search_str[]);
search_result_t match_str(match_t *match, char chr);


#endif /* MATCH_H_ */
