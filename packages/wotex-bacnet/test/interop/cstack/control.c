/* SPDX-License-Identifier: Apache-2.0 */
#include "peer.h"
#include <stdio.h>
#include <string.h>

bool peer_uint(const char *text, uint32_t minimum, uint32_t maximum, uint32_t *out)
{
    uint32_t value = 0;
    size_t length = strlen(text);
    if (!length || length > 10 || (length > 1 && text[0] == '0')) {
        return false;
    }
    for (size_t index = 0; index < length; index++) {
        unsigned char digit = (unsigned char)text[index];
        if (digit < '0' || digit > '9' || value > (UINT32_MAX - (digit - '0')) / 10) {
            return false;
        }
        value = value * 10 + (digit - '0');
    }
    if (value < minimum || value > maximum) {
        return false;
    }
    *out = value;
    return true;
}

bool peer_parse(const char *data, size_t size, struct peer_command *out)
{
    char input[129];
    char *tokens[4] = {0};
    size_t count = 1;
    if (!size || size > 128 || memchr(data, '\0', size)) {
        return false;
    }
    memcpy(input, data, size);
    if (input[size - 1] == '\n') {
        size--;
    }
    input[size] = '\0';
    tokens[0] = input;
    for (size_t index = 0; index < size; index++) {
        if (input[index] == ' ') {
            if (count == 4 || index == 0 || input[index - 1] == '\0') {
                return false;
            }
            input[index] = '\0';
            tokens[count++] = input + index + 1;
        }
    }
    struct peer_command parsed = {0};
    if (count == 2 && strcmp(tokens[0], "stats") == 0) {
        parsed.kind = PEER_STATS;
    } else if (count == 2 && strcmp(tokens[0], "quit") == 0) {
        parsed.kind = PEER_QUIT;
    } else if (count == 4 && strcmp(tokens[0], "fault") == 0) {
        const char *names[] = {"none", "register_ack", "renew_ack", "cancel_ack", "cancel_request"};
        parsed.kind = PEER_FAULT;
        for (unsigned index = 1; index < PEER_FAULT_COUNT; index++) {
            if (strcmp(tokens[1], names[index]) == 0) {
                parsed.fault = (enum peer_fault)index;
            }
        }
        if (parsed.fault == PEER_FAULT_NONE || !peer_uint(tokens[2], 0, 255, &parsed.count)) {
            return false;
        }
    } else {
        return false;
    }
    if (!peer_uint(tokens[count - 1], 0, UINT32_MAX, &parsed.nonce)) {
        return false;
    }
    *out = parsed;
    return true;
}

void peer_increment(uint64_t *value)
{
    if (*value < UINT64_MAX) {
        ++*value;
    }
}

int peer_parser_test(void)
{
    const char *valid[] = {"stats 0", "stats 4294967295\n", "quit 1", "fault register_ack 255 2",
        "fault renew_ack 0 3", "fault cancel_ack 1 4", "fault cancel_request 1 5"};
    const char *invalid[] = {"", "\n", "stats", "stats -1", "stats 01", "stats 4294967296",
        "stats 0 extra", " stats 0", "stats  0", "stats 0 ", "stats 0\n\n", "stats\t0",
        "fault none 1 0", "fault register_ack 256 0", "fault register_ack -1 0",
        "fault register_ack 1", "fault register_ack 1 0 extra"};
    struct peer_command command = {0};
    for (size_t index = 0; index < sizeof(valid) / sizeof(valid[0]); index++) {
        if (!peer_parse(valid[index], strlen(valid[index]), &command)) {
            return 1;
        }
    }
    for (size_t index = 0; index < sizeof(invalid) / sizeof(invalid[0]); index++) {
        if (peer_parse(invalid[index], strlen(invalid[index]), &command)) {
            return 2;
        }
    }
    char oversized[129];
    memset(oversized, 'x', sizeof(oversized));
    if (peer_parse(oversized, sizeof(oversized), &command) ||
        peer_parse("stats 0\0x", 9, &command)) {
        return 3;
    }
    uint64_t counter = UINT64_MAX - 1;
    peer_increment(&counter);
    peer_increment(&counter);
    if (counter != UINT64_MAX) {
        return 4;
    }
    puts("WBA-CP01 control parser and counter bounds pass");
    return 0;
}
