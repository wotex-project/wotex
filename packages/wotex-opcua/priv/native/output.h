/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_OUTPUT_H
#define WOTEX_OPCUA_OUTPUT_H

#include "ipc.h"

/* WOP-X04 output bounds. Normal envelopes wait in one bounded queue and spend
 * owner-granted message/byte credit only when their first byte is written.
 * Ready and one terminal control share a separate aggregate allowance. */
#define WOP_OUTPUT_FRAMES 64U
#define WOP_OUTPUT_BYTES 1048576U
#define WOP_CREDIT_MESSAGES 16U
#define WOP_CREDIT_BYTES 262144U
#define WOP_CONTROL_BYTES 4096U

typedef enum {
    WOP_OUTPUT_OK = 0,
    /* Admitting the envelope would exceed the 64-frame or 1 MiB queue. */
    WOP_OUTPUT_OVERFLOW = 1,
    /* Credit, control or envelope shape violates the version-1 protocol. */
    WOP_OUTPUT_INVALID = 2,
    /* The descriptor failed for a reason other than temporary backpressure. */
    WOP_OUTPUT_CLOSED = 3
} WopOutputStatus;

typedef struct {
    char *bytes;
    size_t size;
} WopOutputFrame;

typedef struct {
    WopOutputFrame queue[WOP_OUTPUT_FRAMES];
    size_t head;
    size_t count;
    /* Includes the active partially written frame until its newline is sent. */
    size_t pending_bytes;
    WopOutputFrame active;
    size_t active_sent;
    char control[WOP_CONTROL_BYTES];
    size_t control_size;
    size_t control_sent;
    bool terminal;
    uint64_t generation;
    uint64_t sequence;
    uint64_t credit_messages;
    uint64_t credit_bytes;
    uint64_t used_messages;
    uint64_t used_bytes;
    uint64_t emitted_messages;
    uint64_t emitted_bytes;
    /* Largest number of unstarted normal envelopes ever queued. */
    size_t peak_count;
} WopOutput;

void wop_output_init(WopOutput *output);
/* Frees queued frames without writing them. */
void wop_output_clear(WopOutput *output);

/* Stages ready or the single terminal control after any active normal frame.
 * A terminal discards normal frames whose first byte was not yet written. */
WopOutputStatus wop_output_control(WopOutput *output, const char *bytes, size_t size,
                                   bool terminal);

/* Applies an already shape-validated credit control. The first grant fixes
 * the generation; later grants replenish only consumed, unreturned credit. */
WopOutputStatus wop_output_credit(WopOutput *output, const WopIpcCredit *credit);

/* Copies one complete LF-terminated normal envelope into the bounded queue. */
WopOutputStatus wop_output_normal(WopOutput *output, const char *bytes, size_t size);

/* Writes as much as the nonblocking descriptor and available credit permit.
 * Temporary backpressure returns WOP_OUTPUT_OK with retained partial state. */
WopOutputStatus wop_output_flush(WopOutput *output, int descriptor);

/* True when a write can make progress without new credit. */
bool wop_output_writable(const WopOutput *output);
/* True when no control or normal byte awaits delivery. */
bool wop_output_drained(const WopOutput *output);

#endif
