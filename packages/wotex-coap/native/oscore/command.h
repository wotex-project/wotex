/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_COMMAND_H
#define WOTEX_COAP_OSCORE_COMMAND_H

#include "json.h"
#include <stdint.h>

enum wco_operation {
    WCO_OPEN, WCO_BODY_BEGIN, WCO_BODY_CHUNK, WCO_BODY_END,
    WCO_REQUEST, WCO_OBSERVE, WCO_CREDIT, WCO_CANCEL, WCO_CLOSE
};
struct wco_command {
    enum wco_operation operation;
    char id[65];
    uint32_t timeout_ms;
    yyjson_val *parameters;
};

/* Decode one already parsed C07 request. Every envelope/operation field has an
 * exact allowlist and bounded type. This function opens no file/socket and does
 * not alter body, credit or SDK state. Parameters borrow the JSON pool: consume
 * or copy them before its next parse/reset/free. The returned ID is owned.
 * Failure erases the output, including any previously decoded identity. */
int wco_command_decode(const struct wco_json *json, struct wco_command *command);
void wco_command_clear(struct wco_command *command);

#endif
