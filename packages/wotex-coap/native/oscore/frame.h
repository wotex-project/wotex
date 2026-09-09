/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_FRAME_H
#define WOTEX_COAP_OSCORE_FRAME_H

#include "json.h"
#include <stddef.h>
#include <stdint.h>

struct wco_frame {
    uint8_t bytes[WCO_JSON_FRAME_MAX];
    size_t used, peak;
    int failed;
};
typedef int (*wco_frame_callback)(const char *line, size_t length, void *argument);

/* Initialize once per native generation. Feed accepts arbitrary byte splits and
 * coalesced lines; a callback must consume/copy its borrowed line synchronously.
 * Invalid input, a failed callback or truncated EOF permanently rejects later
 * bytes. The buffer is erased after delivery or failure, without a heap resize. */
void wco_frame_init(struct wco_frame *frame);
int wco_frame_feed(struct wco_frame *frame, const void *bytes, size_t length,
                    wco_frame_callback callback, void *argument);
int wco_frame_eof(struct wco_frame *frame);

#endif
