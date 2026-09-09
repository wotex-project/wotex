/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_CREDIT_H
#define WOTEX_COAP_OSCORE_CREDIT_H

#include <stdint.h>
#define WCO_REPORT_WINDOW 8u

struct wco_credit {
    uint64_t generation, assigned, written, acknowledged;
    int started, failed;
};
enum wco_credit_status { WCO_CREDIT_OK, WCO_CREDIT_WAIT, WCO_CREDIT_INVALID, WCO_CREDIT_EXHAUSTED };

/* One initialized instance belongs to one nonzero generation. Assign only after
 * reserving a bounded native queue slot; mark written only after the complete
 * wire frame has left that queue. Acknowledgments refer to cumulative report
 * sequence, independent of request IDs. Old/duplicate grants replenish nothing.
 * Invalid input or exhaustion poisons this generation; it cannot wrap/reset. */
void wco_credit_init(struct wco_credit *credit, uint64_t generation);
enum wco_credit_status wco_credit_ack(struct wco_credit *credit, uint64_t generation,
                                       uint64_t sequence);
enum wco_credit_status wco_credit_assign(struct wco_credit *credit, uint64_t *sequence);
enum wco_credit_status wco_credit_written(struct wco_credit *credit, uint64_t sequence);
unsigned wco_credit_available(const struct wco_credit *credit);

#endif
