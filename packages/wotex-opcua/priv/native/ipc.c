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
            parsed.open = key_is(value, "open");
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

static bool closed(yyjson_val *object, const char *const *keys, size_t count) {
    if (!yyjson_is_obj(object) || yyjson_obj_size(object) != count) return false;
    for (size_t i = 0; i < count; i++) {
        if (!yyjson_obj_get(object, keys[i])) return false;
    }
    return true;
}

bool wop_ipc_credit(yyjson_val *root, WopIpcCredit *credit) {
    static const char *const fields[] = {
        "version", "generation", "event", "sequence", "messages", "bytes"
    };
    if (!credit || !closed(root, fields, 6)) return false;
    int64_t version;
    WopIpcCredit parsed = {0};
    yyjson_val *event = yyjson_obj_get(root, "event");
    if (!wop_json_int64(yyjson_obj_get(root, "version"), &version) || version != 1 ||
        !yyjson_is_str(event) || !key_is(event, "credit") ||
        !wop_json_uint64(yyjson_obj_get(root, "generation"), &parsed.generation) ||
        parsed.generation == 0 ||
        !wop_json_uint64(yyjson_obj_get(root, "sequence"), &parsed.sequence) ||
        parsed.sequence == 0 ||
        !wop_json_uint64(yyjson_obj_get(root, "messages"), &parsed.messages) ||
        parsed.messages == 0 || parsed.messages > 16 ||
        !wop_json_uint64(yyjson_obj_get(root, "bytes"), &parsed.bytes) ||
        parsed.bytes == 0 || parsed.bytes > 262144) return false;
    *credit = parsed;
    return true;
}

static bool bounded_text(yyjson_val *value, size_t maximum) {
    return yyjson_is_str(value) && yyjson_get_len(value) > 0 &&
           yyjson_get_len(value) <= maximum &&
           !memchr(yyjson_get_str(value), '\0', yyjson_get_len(value));
}

static int sextet(unsigned char value) {
    if (value >= 'A' && value <= 'Z') return value - 'A';
    if (value >= 'a' && value <= 'z') return value - 'a' + 26;
    if (value >= '0' && value <= '9') return value - '0' + 52;
    if (value == '+') return 62;
    if (value == '/') return 63;
    return -1;
}

static bool bytes_envelope(yyjson_val *value, size_t maximum, bool allow_empty) {
    static const char *const fields[] = {"type", "base64"};
    if (!closed(value, fields, 2)) return false;
    yyjson_val *type = yyjson_obj_get(value, "type");
    yyjson_val *encoded = yyjson_obj_get(value, "base64");
    if (!yyjson_is_str(type) || !key_is(type, "bytes") || !yyjson_is_str(encoded))
        return false;
    const unsigned char *text = (const unsigned char *)yyjson_get_str(encoded);
    size_t length = yyjson_get_len(encoded);
    if (length % 4 != 0 || length > (maximum / 3 + 2) * 4)
        return false;
    size_t padding = length && text[length - 1] == '=' ? 1U : 0U;
    if (length >= 2 && text[length - 2] == '=') padding++;
    size_t decoded = length / 4 * 3 - padding;
    if (decoded > maximum || (!allow_empty && decoded == 0)) return false;
    for (size_t i = 0; i < length - padding; i++) {
        if (sextet(text[i]) < 0) return false;
    }
    for (size_t i = length - padding; i < length; i++) {
        if (text[i] != '=') return false;
    }
    if (padding == 1 && (sextet(text[length - 2]) & 3) != 0) return false;
    if (padding == 2 && (sextet(text[length - 3]) & 15) != 0) return false;
    return true;
}

static bool authentication(yyjson_val *value) {
    if (!yyjson_is_obj(value)) return false;
    yyjson_val *type = yyjson_obj_get(value, "type");
    if (!yyjson_is_str(type)) return false;
    if (key_is(type, "anonymous")) {
        static const char *const fields[] = {"type"};
        return closed(value, fields, 1);
    }
    if (key_is(type, "username")) {
        static const char *const fields[] = {"type", "username", "password"};
        return closed(value, fields, 3) &&
               bounded_text(yyjson_obj_get(value, "username"), 1024) &&
               bytes_envelope(yyjson_obj_get(value, "password"), 4096, true);
    }
    if (key_is(type, "certificate")) {
        static const char *const fields[] = {"type", "certificate", "private_key"};
        return closed(value, fields, 3) &&
               bytes_envelope(yyjson_obj_get(value, "certificate"), 65536, false) &&
               bytes_envelope(yyjson_obj_get(value, "private_key"), 65536, false);
    }
    return false;
}

bool wop_ipc_open(yyjson_val *parameters) {
    static const char *const fields[] = {
        "endpoint", "security_policy", "security_mode", "client_uri", "server_uri",
        "certificate", "private_key", "server_certificate", "trust_certificate",
        "crl", "authentication", "session_timeout_ms"
    };
    static const char *const policies[] = {
        "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
        "http://opcfoundation.org/UA/SecurityPolicy#Aes128_Sha256_RsaOaep",
        "http://opcfoundation.org/UA/SecurityPolicy#Aes256_Sha256_RsaPss"
    };
    if (!closed(parameters, fields, sizeof(fields) / sizeof(fields[0]))) return false;
    if (!bounded_text(yyjson_obj_get(parameters, "endpoint"), 4096) ||
        !bounded_text(yyjson_obj_get(parameters, "client_uri"), 4096) ||
        !bounded_text(yyjson_obj_get(parameters, "server_uri"), 4096)) return false;
    yyjson_val *mode = yyjson_obj_get(parameters, "security_mode");
    yyjson_val *policy = yyjson_obj_get(parameters, "security_policy");
    if (!yyjson_is_str(mode) || !key_is(mode, "SignAndEncrypt") || !yyjson_is_str(policy))
        return false;
    bool allowed = false;
    for (size_t i = 0; i < sizeof(policies) / sizeof(policies[0]); i++) {
        if (key_is(policy, policies[i])) allowed = true;
    }
    if (!allowed) return false;
    for (size_t i = 5; i <= 9; i++) {
        if (!bytes_envelope(yyjson_obj_get(parameters, fields[i]), 65536, false))
            return false;
    }
    uint64_t session_timeout;
    return authentication(yyjson_obj_get(parameters, "authentication")) &&
           wop_json_uint64(yyjson_obj_get(parameters, "session_timeout_ms"), &session_timeout) &&
           session_timeout >= 1000 && session_timeout <= 3600000;
}
