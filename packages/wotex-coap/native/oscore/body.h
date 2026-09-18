/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_BODY_H
#define WOTEX_COAP_OSCORE_BODY_H

#include "json.h"
#include <stddef.h>
#include <stdint.h>

#define WCO_BODY_MAX 1048576u
#define WCO_BODY_CHUNK_MAX 32768u

struct wco_body {
    uint8_t *bytes;
    size_t length, used;
    uint8_t hash[32];
    char id[65];
    int active, complete, failed;
};

/* These helpers validate the exact byte envelope and canonical padded
 * base64. Decoded length is checked before writing any output. Capacity zero
 * accepts only empty data; nonempty output requires a valid caller buffer. */
int wco_body_base64(yyjson_val *value, uint8_t *output, size_t capacity, size_t *length);
int wco_body_identifier(const char *id, size_t length);

/* One body owns at most its admitted length (<= 1 MiB). The first successful
 * end verifies exact length and SHA-256 before data can be exposed. All errors
 * erase/release the buffer and poison this generation; clear after a consumed
 * complete body preserves poison and never authorizes recovery from failure.
 * The owner supplies and enforces the originating operation's absolute deadline. */
void wco_body_init(struct wco_body *body);
int wco_body_begin(struct wco_body *body, const char *id, size_t id_length,
                     size_t length, const char *sha256, size_t sha256_length);
int wco_body_chunk(struct wco_body *body, const char *id, size_t id_length,
                     size_t offset, yyjson_val *data);
int wco_body_end(struct wco_body *body, const char *id, size_t id_length);
int wco_body_data(const struct wco_body *body, const uint8_t **bytes, size_t *length);
void wco_body_clear(struct wco_body *body);
void wco_body_fail(struct wco_body *body);

#endif
