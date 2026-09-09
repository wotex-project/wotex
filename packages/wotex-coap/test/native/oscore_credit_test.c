/* SPDX-License-Identifier: Apache-2.0 */
#include "credit.h"
#include <assert.h>
#include <stdio.h>

static void sent(struct wco_credit *credit, uint64_t expected) {
    uint64_t sequence = 0;
    assert(wco_credit_assign(credit, &sequence) == WCO_CREDIT_OK && sequence == expected);
    assert(wco_credit_written(credit, sequence) == WCO_CREDIT_OK);
    assert(credit->assigned - credit->acknowledged <= WCO_REPORT_WINDOW);
}

static void replay(void) {
    struct wco_credit credit; uint64_t sequence;
    wco_credit_init(&credit, 17);
    assert(!wco_credit_available(&credit));
    assert(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_WAIT && sequence == 0);
    assert(wco_credit_ack(&credit, 17, 0) == WCO_CREDIT_OK);
    assert(wco_credit_available(&credit) == 8);
    for (uint64_t number = 1; number <= 8; number++) sent(&credit, number);
    assert(!wco_credit_available(&credit));
    assert(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_WAIT);
    assert(wco_credit_ack(&credit, 17, 4) == WCO_CREDIT_OK);
    assert(wco_credit_available(&credit) == 4);
    for (uint64_t number = 9; number <= 12; number++) sent(&credit, number);
    assert(wco_credit_ack(&credit, 17, 4) == WCO_CREDIT_OK);
    assert(wco_credit_ack(&credit, 17, 2) == WCO_CREDIT_OK);
    assert(wco_credit_ack(&credit, 17, 0) == WCO_CREDIT_OK);
    for (unsigned index = 0; index < 1000; index++)
        assert(wco_credit_ack(&credit, 17, index % 5) == WCO_CREDIT_OK);
    assert(!wco_credit_available(&credit));
    assert(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_WAIT && sequence == 0);
    assert(credit.assigned == 12 && credit.written == 12 && credit.acknowledged == 4);
    assert(wco_credit_ack(&credit, 17, 12) == WCO_CREDIT_OK);
    assert(wco_credit_available(&credit) == 8);
    puts("WCO-N03: cumulative replay trace retains exactly eight outstanding frames after 1000 stale grants");
}

static void invalid(void) {
    struct wco_credit credit; uint64_t sequence;
    for (unsigned scenario = 0; scenario < 5; scenario++) {
        wco_credit_init(&credit, 17);
        switch (scenario) {
        case 0: assert(wco_credit_ack(&credit, 18, 0) == WCO_CREDIT_INVALID); break;
        case 1: assert(wco_credit_ack(&credit, 17, 1) == WCO_CREDIT_INVALID); break;
        case 2:
            assert(wco_credit_ack(&credit, 17, 0) == WCO_CREDIT_OK);
            assert(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_OK);
            assert(wco_credit_ack(&credit, 17, 1) == WCO_CREDIT_INVALID); break;
        case 3: assert(wco_credit_written(&credit, 1) == WCO_CREDIT_INVALID); break;
        case 4:
            assert(wco_credit_ack(&credit, 17, 0) == WCO_CREDIT_OK);
            sent(&credit, 1);
            assert(wco_credit_written(&credit, 1) == WCO_CREDIT_INVALID); break;
        }
        assert(credit.failed && !wco_credit_available(&credit));
        assert(wco_credit_ack(&credit, 17, 0) == WCO_CREDIT_INVALID);
        assert(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_INVALID && sequence == 0);
    }
    wco_credit_init(&credit, 0);
    assert(credit.failed);
    puts("WCO-N03: wrong generation, future/unwritten acknowledgment and unordered writes close credit generation");
}

static void exhaustion(void) {
    struct wco_credit credit; uint64_t sequence;
    wco_credit_init(&credit, UINT64_MAX);
    assert(wco_credit_ack(&credit, UINT64_MAX, 0) == WCO_CREDIT_OK);
    /* Establish the reachable boundary directly; no impractical 2^64-frame loop. */
    credit.assigned = credit.written = credit.acknowledged = UINT64_MAX - 1;
    sent(&credit, UINT64_MAX);
    assert(wco_credit_ack(&credit, UINT64_MAX, UINT64_MAX) == WCO_CREDIT_OK);
    assert(wco_credit_assign(&credit, &sequence) == WCO_CREDIT_EXHAUSTED && sequence == 0);
    assert(credit.failed && credit.assigned == UINT64_MAX && !wco_credit_available(&credit));
    puts("WCO-N03: final uint64 report sequence is exact; exhaustion poisons without wrap");
}

int main(void) { replay(); invalid(); exhaustion(); return 0; }
