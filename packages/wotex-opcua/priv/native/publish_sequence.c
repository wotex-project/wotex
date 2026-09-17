/* SPDX-License-Identifier: Apache-2.0 */
#include "publish_sequence.h"

#include <string.h>

/* Sequence values 1..UINT32_MAX map to ring positions 0..UINT32_MAX-1. */
#define RING ((uint64_t)UINT32_MAX)

void wop_sequence_init(WopSequence *state, uint32_t last) {
    if(!state) return;
    memset(state, 0, sizeof(*state));
    state->last = last;
}

uint32_t wop_sequence_next(uint32_t sequence) {
    return sequence == UINT32_MAX ? 1U : sequence + 1U;
}

static const WopSequenceEntry *cached(const WopSequence *state, uint32_t sequence) {
    for(size_t i = 0; i < state->count; i++) {
        const WopSequenceEntry *entry =
            &state->cache[(state->head + WOP_SEQUENCE_CACHE - 1U - i) % WOP_SEQUENCE_CACHE];
        if(entry->sequence == sequence) return entry;
    }
    return NULL;
}

WopSequenceVerdict wop_sequence_classify(const WopSequence *state, uint32_t sequence,
                                         const unsigned char digest[WOP_SEQUENCE_DIGEST],
                                         uint32_t *missing_first, uint32_t *missing_count) {
    if(!state || !digest || !missing_first || !missing_count || sequence == 0)
        return WOP_SEQUENCE_INVALID;
    *missing_first = 0;
    *missing_count = 0;
    const WopSequenceEntry *entry = cached(state, sequence);
    if(entry)
        return memcmp(entry->digest, digest, WOP_SEQUENCE_DIGEST) == 0 ?
               WOP_SEQUENCE_DUPLICATE : WOP_SEQUENCE_CONFLICT;
    uint32_t expected = state->last ? wop_sequence_next(state->last) : 1U;
    uint64_t distance = ((uint64_t)sequence - 1U + RING - ((uint64_t)expected - 1U)) % RING;
    if(distance == 0) return WOP_SEQUENCE_DELIVER;
    if(distance >= RING / 2U) return WOP_SEQUENCE_STALE;
    if(distance > WOP_SEQUENCE_REPUBLISH) return WOP_SEQUENCE_TOO_LARGE;
    *missing_first = expected;
    *missing_count = (uint32_t)distance;
    return WOP_SEQUENCE_GAP;
}

bool wop_sequence_record(WopSequence *state, uint32_t sequence,
                         const unsigned char digest[WOP_SEQUENCE_DIGEST]) {
    if(!state || !digest || sequence == 0) return false;
    uint32_t expected = state->last ? wop_sequence_next(state->last) : 1U;
    if(sequence != expected) return false;
    WopSequenceEntry *entry = &state->cache[state->head];
    entry->sequence = sequence;
    memcpy(entry->digest, digest, WOP_SEQUENCE_DIGEST);
    state->head = (state->head + 1U) % WOP_SEQUENCE_CACHE;
    if(state->count < WOP_SEQUENCE_CACHE) state->count++;
    state->last = sequence;
    return true;
}

bool wop_sequence_begin(WopSequence *state, uint32_t target,
                        const unsigned char digest[WOP_SEQUENCE_DIGEST],
                        uint32_t missing_first, uint32_t missing_count) {
    if(!state || !digest || state->recovering || missing_count == 0 ||
       missing_count > WOP_SEQUENCE_REPUBLISH) return false;
    uint32_t expected = state->last ? wop_sequence_next(state->last) : 1U;
    if(missing_first != expected) return false;
    state->recovering = true;
    state->recover_next = missing_first;
    state->recover_left = missing_count;
    state->target = target;
    memcpy(state->target_digest, digest, WOP_SEQUENCE_DIGEST);
    return true;
}

bool wop_sequence_pending(const WopSequence *state, uint32_t *sequence) {
    if(!state || !sequence || !state->recovering || state->recover_left == 0) return false;
    *sequence = state->recover_next;
    return true;
}

WopRecovery wop_sequence_republished(WopSequence *state, uint32_t requested, bool available,
                                     uint32_t sequence,
                                     const unsigned char digest[WOP_SEQUENCE_DIGEST]) {
    if(!state || !state->recovering || requested != state->recover_next || !available ||
       sequence != requested || !digest || !wop_sequence_record(state, sequence, digest)) {
        if(state) state->recovering = false;
        return WOP_RECOVERY_FAILED;
    }
    state->recover_next = wop_sequence_next(sequence);
    if(--state->recover_left) return WOP_RECOVERY_CONTINUE;
    state->recovering = false;
    return WOP_RECOVERY_COMPLETE;
}
