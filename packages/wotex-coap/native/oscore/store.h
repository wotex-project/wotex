/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_STORE_H
#define WOTEX_COAP_OSCORE_STORE_H

#include "identity.h"
#include <stdint.h>

#define WCO_STORE_MAX_CONTEXTS 4096u
#define WCO_STORE_SEQUENCE_LIMIT (UINT64_C(1) << 40)

enum wco_store_status {
    WCO_STORE_OK,
    WCO_STORE_INVALID,
    WCO_STORE_LOCKED,
    WCO_STORE_CORRUPT,
    WCO_STORE_FULL,
    WCO_STORE_FRESH_REQUIRED,
    WCO_STORE_UNAVAILABLE,
    WCO_STORE_EXHAUSTED
};

struct wco_store;

/* The caller supplies a private, existing absolute local directory. Every path
 * component is opened without symlink traversal. The store takes a nonblocking
 * exclusive lock and durably consumes the identity before returning success.
 * Only a new lock file authorizes an absent registry; a missing old registry
 * fails closed. No raw keys enter the registry. initial_boundary is exclusive,
 * in 1..2^40. On failure *result is NULL and no descriptor remains owned. */
enum wco_store_status wco_store_open(const char *directory,
                                     const struct wco_oscore_identity *identity,
                                     uint64_t initial_boundary,
                                     struct wco_store **result);
/* Success means boundary <= the durable exclusive upper bound. Any storage
 * failure poisons this owner permanently. Boundary exhaustion also fails closed.
 * The public libcoap callback can return status == WCO_STORE_OK directly. */
enum wco_store_status wco_store_reserve(struct wco_store *store, uint64_t boundary);
uint64_t wco_store_boundary(const struct wco_store *store);
void wco_store_close(struct wco_store *store);
const char *wco_store_code(enum wco_store_status status);

#ifdef WCO_STORE_TEST
enum wco_store_step {
    WCO_STORE_TEMP_OPEN = 1, WCO_STORE_WRITE, WCO_STORE_FILE_SYNC,
    WCO_STORE_RENAME, WCO_STORE_DIRECTORY_SYNC
};
/* Fault injection is absent from production builds. A crash occurs immediately
 * after the named successful syscall; an injected failure occurs before it. */
void wco_store_test_fault(enum wco_store_step step, int crash);
#endif

#endif
