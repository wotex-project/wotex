/* SPDX-License-Identifier: Apache-2.0 */
#include "ipc.h"

#include <string.h>

WopIpcFrameStatus wop_ipc_feed(WopIpcInput *input, const char *bytes, size_t length,
                               size_t *consumed) {
    if (!input || !bytes || !consumed || input->used >= WOP_JSON_FRAME_BYTES)
        return WOP_IPC_INVALID;
    *consumed = 0;
    for (size_t i = 0; i < length; i++) {
        if (bytes[i] == '\0') return WOP_IPC_INVALID;
        if (input->used == WOP_JSON_FRAME_BYTES) return WOP_IPC_LIMIT;
        input->bytes[input->used++] = bytes[i];
        *consumed = i + 1;
        if (bytes[i] == '\n') return WOP_IPC_FRAME;
    }
    return input->used == WOP_JSON_FRAME_BYTES ? WOP_IPC_LIMIT : WOP_IPC_MORE;
}

static bool key_is(yyjson_val *key, const char *literal) {
    size_t length = strlen(literal);
    return yyjson_get_len(key) == length &&
           memcmp(yyjson_get_str(key), literal, length) == 0;
}

static bool ascii_id(yyjson_val *value) {
    if (!yyjson_is_str(value)) return false;
    size_t length = yyjson_get_len(value);
    if (length == 0 || length > 64) return false;
    const unsigned char *bytes = (const unsigned char *)yyjson_get_str(value);
    for (size_t i = 0; i < length; i++) {
        if (bytes[i] < 0x20 || bytes[i] > 0x7e) return false;
    }
    return true;
}

static bool operation(yyjson_val *value) {
    if (!yyjson_is_str(value)) return false;
    static const char *names[] = {
        "open", "read", "health", "write", "call", "browse", "browse_next",
        "browse_release", "subscribe", "unsubscribe", "cancel", "close"
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (yyjson_get_len(value) == strlen(names[i]) &&
            memcmp(yyjson_get_str(value), names[i], yyjson_get_len(value)) == 0)
            return true;
    }
    return false;
}

bool wop_ipc_request(yyjson_val *root, WopIpcRequest *request) {
    if (!request || !yyjson_is_obj(root) || yyjson_obj_size(root) != 7)
        return false;
    unsigned fields = 0;
    yyjson_obj_iter iter = yyjson_obj_iter_with(root);
    yyjson_val *key;
    WopIpcRequest parsed = {0};
    while ((key = yyjson_obj_iter_next(&iter))) {
        yyjson_val *value = yyjson_obj_iter_get_val(key);
        unsigned bit;
        if (key_is(key, "version")) {
            int64_t version;
            bit = 1U;
            if (!wop_json_int64(value, &version) || version != 1) return false;
        } else if (key_is(key, "generation")) {
            bit = 2U;
            if (!wop_json_uint64(value, &parsed.generation) || parsed.generation == 0)
                return false;
        } else if (key_is(key, "id")) {
            bit = 4U;
            if (!ascii_id(value)) return false;
        } else if (key_is(key, "operation")) {
            bit = 8U;
            if (!operation(value)) return false;
        } else if (key_is(key, "parameters")) {
            bit = 16U;
            if (!yyjson_is_obj(value)) return false;
        } else if (key_is(key, "timeout_ms")) {
            bit = 32U;
            if (!wop_json_uint64(value, &parsed.timeout_ms) ||
                parsed.timeout_ms == 0 || parsed.timeout_ms > 60000) return false;
        } else if (key_is(key, "deadline_ms")) {
            bit = 64U;
            if (!wop_json_int64(value, &parsed.deadline_ms) || parsed.deadline_ms < 0)
                return false;
        } else {
            return false;
        }
        if (fields & bit) return false;
        fields |= bit;
    }
    if (fields != 127U) return false;
    *request = parsed;
    return true;
}
