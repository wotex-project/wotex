/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_IDENTITY_H
#define WOTEX_COAP_OSCORE_IDENTITY_H

#include <stddef.h>
#include <stdint.h>

struct wco_bytes {
    const uint8_t *data;
    size_t length;
};

/* Fixed RFC 8613 suite: AES-CCM-16-64-128 and HKDF-SHA-256.
 * Pointers must address their declared byte lengths; zero lengths permit NULL.
 * context_present distinguishes the KDF's null from an empty byte string. */
struct wco_oscore_material {
    struct wco_bytes secret, salt, sender, recipient, context;
    int context_present;
};

struct wco_oscore_keys {
    uint8_t sender[16], recipient[16], common_iv[13];
};

/* Only these hashes may be persisted. Directional hashes are role independent:
 * swapping sender/recipient cannot evade the single-generation policy. */
struct wco_oscore_identity {
    uint8_t context[32], sender_space[32], recipient_space[32];
};

/* Returns 1 on success and 0 on invalid bounds or cryptographic failure.
 * Output is zeroed on failure. Callers erase returned keys after use.
 * These derivations identify storage namespaces; libcoap owns encryption. */
int wco_oscore_keys(const struct wco_oscore_material *material,
                    struct wco_oscore_keys *result);
int wco_oscore_identity(const struct wco_oscore_material *material,
                        struct wco_oscore_identity *result);
int wco_oscore_identity_overlaps(const struct wco_oscore_identity *left,
                                 const struct wco_oscore_identity *right);

#endif
