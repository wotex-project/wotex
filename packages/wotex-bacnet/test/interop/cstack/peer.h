/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_BACNET_PEER_H
#define WOTEX_BACNET_PEER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum peer_fault {
    PEER_FAULT_NONE,
    PEER_FAULT_REGISTER_ACK,
    PEER_FAULT_RENEW_ACK,
    PEER_FAULT_CANCEL_ACK,
    PEER_FAULT_CANCEL_REQUEST,
    PEER_FAULT_COUNT
};

struct peer_counters {
    uint64_t reads, writes, who_is, registrations, renewals, cancellations;
    uint64_t control_acks, notification_acks, notifications, datagrams;
    uint64_t dropped_acks, dropped_requests, failed_sends;
};

enum peer_command_kind { PEER_STATS, PEER_FAULT, PEER_QUIT };

struct peer_command {
    enum peer_command_kind kind;
    enum peer_fault fault;
    uint32_t nonce;
    uint32_t count;
};

bool peer_uint(const char *text, uint32_t minimum, uint32_t maximum, uint32_t *out);
bool peer_parse(const char *data, size_t size, struct peer_command *out);
int peer_parser_test(void);
void peer_increment(uint64_t *value);
void peer_control_begin(enum peer_fault kind);
void peer_control_end(bool matching);
bool peer_drop_cancel(void);

#endif
