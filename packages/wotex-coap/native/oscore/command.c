/* SPDX-License-Identifier: Apache-2.0 */
#include "command.h"
#include "body.h"
#include <arpa/inet.h>
#include <openssl/crypto.h>
#include <string.h>

static yyjson_val *field(yyjson_val *object, const char *key) {
    return yyjson_obj_get(object, key);
}
static int string(yyjson_val *value, const char **bytes, size_t *length,
                  size_t minimum, size_t maximum) {
    if (!yyjson_is_str(value)) return 0;
    *bytes = yyjson_get_str(value); *length = yyjson_get_len(value);
    return *length >= minimum && *length <= maximum && !memchr(*bytes, 0, *length);
}
static int identifier(yyjson_val *value) {
    const char *bytes; size_t length;
    return string(value, &bytes, &length, 1, 64) && wco_body_identifier(bytes, length);
}
static int unsigned_value(yyjson_val *value, uint64_t minimum, uint64_t maximum) {
    uint64_t number;
    return wco_json_uint(value, maximum, &number) && number >= minimum;
}
static int optional_uint(yyjson_val *parameters, const char *key, uint64_t maximum) {
    yyjson_val *value = field(parameters, key);
    return !value || unsigned_value(value, 0, maximum);
}
static int bytes(yyjson_val *value, size_t minimum, size_t maximum) {
    uint8_t buffer[WCO_BODY_CHUNK_MAX]; size_t length = 0;
    int valid = wco_body_base64(value, buffer, maximum, &length) && length >= minimum;
    OPENSSL_cleanse(buffer, sizeof(buffer));
    return valid;
}
static int absolute_path(yyjson_val *value) {
    const char *data; size_t length;
    return string(value, &data, &length, 1, 4096) && data[0] == '/';
}
static int numeric_host(yyjson_val *value) {
    const char *data; size_t length; struct in6_addr address;
    return string(value, &data, &length, 1, INET6_ADDRSTRLEN - 1) &&
        (inet_pton(AF_INET, data, &address) == 1 || inet_pton(AF_INET6, data, &address) == 1);
}
static int hex(unsigned char byte) {
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' && byte <= 'F') return byte - 'A' + 10;
    return -1;
}
static int path(yyjson_val *value) {
    const char *data; size_t length, index, segment_length = 0;
    int query = 0, leading_segment = 1, all_dots = 1;
    if (!string(value, &data, &length, 0, 4096) ||
        (length >= 2 && data[0] == '/' && data[1] == '/')) return 0;
    for (index = 0; index < length; ++index) {
        unsigned char byte = (unsigned char)data[index];
        if (byte <= 32 || byte == 127 || byte == '#') return 0;
        if (!query && (byte == '/' || byte == '?')) {
            if (all_dots && segment_length >= 1 && segment_length <= 2) return 0;
            query = byte == '?'; leading_segment = 0;
            segment_length = 0; all_dots = 1; continue;
        }
        if (!query && leading_segment && byte == ':') return 0;
        if (byte == '%') {
            if (index + 2 >= length || hex((unsigned char)data[index+1]) < 0 ||
                hex((unsigned char)data[index+2]) < 0) return 0;
            byte = (unsigned char)(hex((unsigned char)data[index+1]) * 16 +
                                   hex((unsigned char)data[index+2]));
            index += 2;
        }
        if (!query) { segment_length++; if (byte != '.') all_dots = 0; }
    }
    return query || !all_dots || segment_length == 0 || segment_length > 2;
}
static int security(yyjson_val *parameters) {
    static const char *const keys[] = {"mode", "master_secret", "master_salt", "sender_id",
        "recipient_id", "id_context", "context_store"};
    uint8_t sender[7], recipient[7]; size_t sender_length = 0, recipient_length = 0;
    yyjson_val *context = field(parameters, "id_context");
    int valid = wco_json_keys(parameters, keys, 7) && yyjson_obj_size(parameters) == 7 &&
        wco_json_string(field(parameters, "mode"), "oscore") &&
        bytes(field(parameters, "master_secret"), 16, 32) &&
        bytes(field(parameters, "master_salt"), 0, 32) &&
        wco_body_base64(field(parameters, "sender_id"), sender, sizeof(sender), &sender_length) &&
        wco_body_base64(field(parameters, "recipient_id"), recipient, sizeof(recipient), &recipient_length) &&
        (sender_length != recipient_length ||
         (sender_length && memcmp(sender, recipient, sender_length))) &&
        (yyjson_is_null(context) || bytes(context, 0, 255)) &&
        absolute_path(field(parameters, "context_store"));
    OPENSSL_cleanse(sender, sizeof(sender)); OPENSSL_cleanse(recipient, sizeof(recipient));
    return valid;
}
static int open_parameters(yyjson_val *parameters) {
    static const char *const keys[] = {"host", "port", "generation", "security"};
    return wco_json_keys(parameters, keys, 4) && yyjson_obj_size(parameters) == 4 &&
        numeric_host(field(parameters, "host")) && unsigned_value(field(parameters, "port"), 1, 65535) &&
        unsigned_value(field(parameters, "generation"), 1, UINT64_MAX) &&
        security(field(parameters, "security"));
}
static int body_parameters(enum wco_operation operation, yyjson_val *parameters) {
    static const char *const begin[] = {"body_id", "length", "sha256"};
    static const char *const chunk[] = {"body_id", "offset", "data"};
    static const char *const end[] = {"body_id"};
    if (!identifier(field(parameters, "body_id"))) return 0;
    if (operation == WCO_BODY_BEGIN) {
        const char *hash; size_t length;
        if (!wco_json_keys(parameters, begin, 3) || yyjson_obj_size(parameters) != 3 ||
            !unsigned_value(field(parameters, "length"), 0, WCO_BODY_MAX) ||
            !string(field(parameters, "sha256"), &hash, &length, 64, 64)) return 0;
        for (size_t index = 0; index < length; ++index)
            if (!((hash[index] >= '0' && hash[index] <= '9') ||
                  (hash[index] >= 'a' && hash[index] <= 'f'))) return 0;
        return 1;
    }
    if (operation == WCO_BODY_CHUNK)
        return wco_json_keys(parameters, chunk, 3) && yyjson_obj_size(parameters) == 3 &&
            unsigned_value(field(parameters, "offset"), 0, WCO_BODY_MAX) &&
            bytes(field(parameters, "data"), 0, WCO_BODY_CHUNK_MAX);
    return wco_json_keys(parameters, end, 1) && yyjson_obj_size(parameters) == 1;
}
static int request_parameters(enum wco_operation operation, yyjson_val *parameters) {
    static const char *const request[] = {"method", "path", "confirmable", "accept", "content_format", "body_id"};
    static const char *const observe[] = {"path", "confirmable", "observation_kind", "accept"};
    if (!path(field(parameters, "path")) || !yyjson_is_bool(field(parameters, "confirmable")) ||
        !optional_uint(parameters, "accept", 65535)) return 0;
    if (operation == WCO_OBSERVE)
        return wco_json_keys(parameters, observe, 4) &&
            (wco_json_string(field(parameters, "observation_kind"), "property") ||
             wco_json_string(field(parameters, "observation_kind"), "event"));
    yyjson_val *method = field(parameters, "method"), *body = field(parameters, "body_id");
    return wco_json_keys(parameters, request, 6) &&
        (wco_json_string(method, "GET") || wco_json_string(method, "POST") ||
         wco_json_string(method, "PUT") || wco_json_string(method, "DELETE")) &&
        optional_uint(parameters, "content_format", 65535) && (!body || identifier(body));
}
static int control_parameters(enum wco_operation operation, yyjson_val *parameters) {
    static const char *const credit[] = {"generation", "ack_seq"};
    static const char *const cancel[] = {"subscription_id", "generation"};
    if (operation == WCO_CLOSE) return yyjson_is_obj(parameters) && yyjson_obj_size(parameters) == 0;
    if (!unsigned_value(field(parameters, "generation"), 1, UINT64_MAX)) return 0;
    if (operation == WCO_CREDIT)
        return wco_json_keys(parameters, credit, 2) && yyjson_obj_size(parameters) == 2 &&
            unsigned_value(field(parameters, "ack_seq"), 0, UINT64_MAX);
    return wco_json_keys(parameters, cancel, 2) && yyjson_obj_size(parameters) == 2 &&
        identifier(field(parameters, "subscription_id"));
}
void wco_command_clear(struct wco_command *command) {
    if (command) OPENSSL_cleanse(command, sizeof(*command));
}
int wco_command_decode(const struct wco_json *json, struct wco_command *command) {
    static const char *const keys[] = {"version", "id", "operation", "parameters", "timeout_ms"};
    static const char *const names[] = {"open", "body_begin", "body_chunk", "body_end", "request",
        "observe", "credit", "cancel", "close"};
    yyjson_val *root = wco_json_root(json), *parameters, *id;
    uint64_t timeout; size_t index; int valid;
    if (!command) return 0;
    wco_command_clear(command);
    if (!wco_json_keys(root, keys, 5) || yyjson_obj_size(root) != 5 ||
        !unsigned_value(field(root, "version"), 1, 1) || !identifier(field(root, "id")) ||
        !wco_json_uint(field(root, "timeout_ms"), 60000, &timeout) || timeout == 0) return 0;
    for (index = 0; index < sizeof(names)/sizeof(names[0]); ++index)
        if (wco_json_string(field(root, "operation"), names[index])) break;
    if (index == sizeof(names)/sizeof(names[0])) return 0;
    parameters = field(root, "parameters");
    if (!yyjson_is_obj(parameters)) return 0;
    enum wco_operation operation = (enum wco_operation)index;
    if (operation == WCO_OPEN) valid = open_parameters(parameters);
    else if (operation <= WCO_BODY_END) valid = body_parameters(operation, parameters);
    else if (operation <= WCO_OBSERVE) valid = request_parameters(operation, parameters);
    else valid = control_parameters(operation, parameters);
    if (!valid) return 0;
    id = field(root, "id");
    memcpy(command->id, yyjson_get_str(id), yyjson_get_len(id));
    command->timeout_ms = (uint32_t)timeout; command->operation = operation;
    command->parameters = parameters;
    return 1;
}
