/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_PUBLISH_SEQUENCE_H
#define WOTEX_OPCUA_PUBLISH_SEQUENCE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* WOP-S04/X05 per-subscription notification sequence state. Sequence numbers
 * range over 1..2^32-1 and wrap to 1; keepalives never enter this state. The
 * cache retains at most 1024 accepted sequence/digest pairs. A gap of at most
 * 100 missing messages is recovered by Republish in order; any larger gap,
 * conflicting duplicate or unverifiable older sequence is terminal. */
#define WOP_SEQUENCE_CACHE 1024U
#define WOP_SEQUENCE_REPUBLISH 100U
#define WOP_SEQUENCE_DIGEST 32U

typedef struct {
    uint32_t sequence;
    unsigned char digest[WOP_SEQUENCE_DIGEST];
} WopSequenceEntry;

typedef struct {
    /* Last delivered sequence; zero before the first notification. */
    uint32_t last;
    WopSequenceEntry cache[WOP_SEQUENCE_CACHE];
    size_t head;
    size_t count;
    /* Ordered Republish recovery for one held notification. */
    bool recovering;
    uint32_t recover_next;
    uint32_t recover_left;
    uint32_t target;
    unsigned char target_digest[WOP_SEQUENCE_DIGEST];
} WopSequence;

typedef enum {
    WOP_RECOVERY_CONTINUE = 0,
    /* Every missing message was delivered; deliver and record the target. */
    WOP_RECOVERY_COMPLETE,
    WOP_RECOVERY_FAILED
} WopRecovery;

typedef enum {
    WOP_SEQUENCE_DELIVER = 0,
    /* Already accepted with the same digest: acknowledge without delivery. */
    WOP_SEQUENCE_DUPLICATE,
    /* Missing messages must be republished before this one is delivered. */
    WOP_SEQUENCE_GAP,
    /* Terminal outcomes. */
    WOP_SEQUENCE_CONFLICT,
    WOP_SEQUENCE_TOO_LARGE,
    WOP_SEQUENCE_STALE,
    WOP_SEQUENCE_INVALID
} WopSequenceVerdict;

void wop_sequence_init(WopSequence *state, uint32_t last);
uint32_t wop_sequence_next(uint32_t sequence);
/* For GAP, missing_first and missing_count identify the ordered missing run. */
WopSequenceVerdict wop_sequence_classify(const WopSequence *state, uint32_t sequence,
                                         const unsigned char digest[WOP_SEQUENCE_DIGEST],
                                         uint32_t *missing_first, uint32_t *missing_count);
/* Records a delivered sequence. It must be the expected next sequence. */
bool wop_sequence_record(WopSequence *state, uint32_t sequence,
                         const unsigned char digest[WOP_SEQUENCE_DIGEST]);

/* Starts recovery for a GAP verdict. The caller retains the target payload. */
bool wop_sequence_begin(WopSequence *state, uint32_t target,
                        const unsigned char digest[WOP_SEQUENCE_DIGEST],
                        uint32_t missing_first, uint32_t missing_count);
/* The next sequence to request with Republish while recovering. */
bool wop_sequence_pending(const WopSequence *state, uint32_t *sequence);
/* Applies one Republish outcome. An unavailable or mismatched message fails. */
WopRecovery wop_sequence_republished(WopSequence *state, uint32_t requested, bool available,
                                     uint32_t sequence,
                                     const unsigned char digest[WOP_SEQUENCE_DIGEST]);

#endif
