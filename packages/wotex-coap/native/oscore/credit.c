/* SPDX-License-Identifier: Apache-2.0 */
#include "credit.h"
#include <string.h>

void wco_credit_init(struct wco_credit *credit, uint64_t generation) {
    if (!credit) return;
    memset(credit, 0, sizeof(*credit));
    credit->generation = generation;
    credit->failed = generation == 0;
}

static enum wco_credit_status reject(struct wco_credit *credit, enum wco_credit_status status) {
    if (credit) credit->failed = 1;
    return status;
}

unsigned wco_credit_available(const struct wco_credit *credit) {
    if (!credit || credit->failed || !credit->started) return 0;
    return WCO_REPORT_WINDOW - (unsigned)(credit->assigned - credit->acknowledged);
}

enum wco_credit_status wco_credit_ack(struct wco_credit *credit, uint64_t generation,
                                       uint64_t sequence) {
    if (!credit || credit->failed || generation != credit->generation)
        return reject(credit, WCO_CREDIT_INVALID);
    if (!credit->started) {
        if (sequence) return reject(credit, WCO_CREDIT_INVALID);
        credit->started = 1;
        return WCO_CREDIT_OK;
    }
    if (sequence > credit->written) return reject(credit, WCO_CREDIT_INVALID);
    if (sequence > credit->acknowledged) credit->acknowledged = sequence;
    return WCO_CREDIT_OK;
}

enum wco_credit_status wco_credit_assign(struct wco_credit *credit, uint64_t *sequence) {
    if (sequence) *sequence = 0;
    if (!credit || !sequence || credit->failed) return reject(credit, WCO_CREDIT_INVALID);
    if (credit->assigned == UINT64_MAX) return reject(credit, WCO_CREDIT_EXHAUSTED);
    if (!wco_credit_available(credit)) return WCO_CREDIT_WAIT;
    *sequence = ++credit->assigned;
    return WCO_CREDIT_OK;
}

enum wco_credit_status wco_credit_written(struct wco_credit *credit, uint64_t sequence) {
    if (!credit || credit->failed || credit->written == UINT64_MAX ||
        sequence != credit->written + 1 || sequence > credit->assigned)
        return reject(credit, WCO_CREDIT_INVALID);
    credit->written = sequence;
    return WCO_CREDIT_OK;
}
