/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_JSON_H
#define WOTEX_COAP_OSCORE_JSON_H

#include "vendor/yyjson/yyjson.h"
#include <stddef.h>
#include <stdint.h>

#define WCO_JSON_FRAME_MAX 131072u
#define WCO_JSON_POOL_SIZE 2097152u

enum wco_json_status {
    WCO_JSON_OK, WCO_JSON_FRAME, WCO_JSON_SYNTAX, WCO_JSON_LIMIT, WCO_JSON_DUPLICATE
};
struct wco_json;

/* One decoder owns one fixed parser pool and one C numeric locale. yyjson has
 * no allocator fallback. Values borrow this pool until the next
 * parse/reset/free. Reset erases the complete pool, including credentials. */
struct wco_json *wco_json_new(void);
void wco_json_reset(struct wco_json *json);
void wco_json_free(struct wco_json *json);
enum wco_json_status wco_json_parse(struct wco_json *json, const char *line, size_t length);
yyjson_val *wco_json_root(const struct wco_json *json);

/* Scalar readers require exact types. Unsigned integers retain all 64 bits;
 * fractional/exponent tokens and negative nonzero values are rejected. */
int wco_json_uint(yyjson_val *value, uint64_t maximum, uint64_t *output);
int wco_json_string(yyjson_val *value, const char *expected);
int wco_json_keys(yyjson_val *object, const char *const *allowed, size_t count);

#endif
