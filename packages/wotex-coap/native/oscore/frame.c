/* SPDX-License-Identifier: Apache-2.0 */
#include "frame.h"
#include <openssl/crypto.h>
#include <string.h>

void wco_frame_init(struct wco_frame *frame) {
    if (frame) memset(frame, 0, sizeof(*frame));
}

static int fail(struct wco_frame *frame) {
    OPENSSL_cleanse(frame->bytes, sizeof(frame->bytes));
    frame->used = 0;
    frame->failed = 1;
    return 0;
}

int wco_frame_feed(struct wco_frame *frame, const void *bytes, size_t length,
                    wco_frame_callback callback, void *argument) {
    const uint8_t *input = bytes;
    if (!frame) return 0;
    if (frame->failed) return 0;
    if ((!bytes && length) || !callback) return fail(frame);
    while (length) {
        const uint8_t *newline = memchr(input, '\n', length);
        size_t count = newline ? (size_t)(newline - input) + 1 : length;
        size_t capacity = WCO_JSON_FRAME_MAX - frame->used;
        if (count > capacity) {
            /* Account for the admitted prefix, but never store the extra byte. */
            if (capacity) memcpy(frame->bytes + frame->used, input, capacity);
            frame->peak = WCO_JSON_FRAME_MAX;
            return fail(frame);
        }
        memcpy(frame->bytes + frame->used, input, count);
        frame->used += count;
        if (frame->used > frame->peak) frame->peak = frame->used;
        input += count;
        length -= count;
        if (newline) {
            if (!callback((const char *)frame->bytes, frame->used, argument)) return fail(frame);
            OPENSSL_cleanse(frame->bytes, frame->used);
            frame->used = 0;
        }
    }
    return 1;
}

int wco_frame_eof(struct wco_frame *frame) {
    if (!frame || frame->failed) return 0;
    if (frame->used) return fail(frame);
    /* Even a clean EOF closes this generation's input permanently. */
    frame->failed = 1;
    return 1;
}
