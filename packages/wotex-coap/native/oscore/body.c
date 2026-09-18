/* SPDX-License-Identifier: Apache-2.0 */
#include "body.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <stdlib.h>
#include <string.h>

static int digit(unsigned char byte) {
    if (byte >= 'A' && byte <= 'Z') return byte - 'A';
    if (byte >= 'a' && byte <= 'z') return byte - 'a' + 26;
    if (byte >= '0' && byte <= '9') return byte - '0' + 52;
    return byte == '+' ? 62 : byte == '/' ? 63 : -1;
}

int wco_body_base64(yyjson_val *value, uint8_t *output, size_t capacity, size_t *length) {
    const char *const keys[] = {"type", "base64"};
    yyjson_val *encoded;
    const char *input;
    size_t size, decoded, padding = 0;
    if (!length) return 0;
    *length = 0;
    if (!wco_json_keys(value, keys, 2) || yyjson_obj_size(value) != 2 ||
        !wco_json_string(yyjson_obj_get(value, "type"), "bytes")) return 0;
    encoded = yyjson_obj_get(value, "base64");
    if (!yyjson_is_str(encoded)) return 0;
    size = yyjson_get_len(encoded); input = yyjson_get_str(encoded);
    if (size % 4 || size > 4 * ((WCO_BODY_CHUNK_MAX + 2) / 3)) return 0;
    if (size && input[size - 1] == '=') padding++;
    if (size > 1 && input[size - 2] == '=') padding++;
    decoded = (size / 4) * 3 - padding;
    if (decoded > capacity || decoded > WCO_BODY_CHUNK_MAX || (decoded && !output)) return 0;
    /* Validate the entire source, including padding bits, before exposing even
     * one decoded byte. The JSON decoder already rejected duplicate keys. */
    for (size_t offset = 0; offset < size; offset += 4) {
        int a = digit((unsigned char)input[offset]), b = digit((unsigned char)input[offset + 1]);
        int c = digit((unsigned char)input[offset + 2]), d = digit((unsigned char)input[offset + 3]);
        int last = offset + 4 == size;
        if (a < 0 || b < 0) return 0;
        if (last && padding == 2) {
            if (input[offset + 2] != '=' || input[offset + 3] != '=' || (b & 15)) return 0;
        } else if (last && padding == 1) {
            if (c < 0 || input[offset + 3] != '=' || (c & 3)) return 0;
        } else if (c < 0 || d < 0) return 0;
    }
    for (size_t offset = 0, written = 0; offset < size; offset += 4) {
        unsigned a = (unsigned)digit((unsigned char)input[offset]);
        unsigned b = (unsigned)digit((unsigned char)input[offset + 1]);
        unsigned c = input[offset + 2] == '=' ? 0 : (unsigned)digit((unsigned char)input[offset + 2]);
        unsigned d = input[offset + 3] == '=' ? 0 : (unsigned)digit((unsigned char)input[offset + 3]);
        /* NOLINTNEXTLINE(clang-analyzer-core.NullDereference): output is non-NULL whenever a byte decodes (checked above) */
        output[written++] = (uint8_t)((a << 2) | (b >> 4));
        if (written < decoded) output[written++] = (uint8_t)((b << 4) | (c >> 2));
        if (written < decoded) output[written++] = (uint8_t)((c << 6) | d);
    }
    *length = decoded;
    return 1;
}

int wco_body_identifier(const char *id, size_t length) {
    if (!id || !length || length > 64) return 0;
    for (size_t index = 0; index < length; index++)
        if ((unsigned char)id[index] < 0x20 || (unsigned char)id[index] > 0x7e) return 0;
    return 1;
}

void wco_body_init(struct wco_body *body) {
    if (body) memset(body, 0, sizeof(*body));
}

void wco_body_clear(struct wco_body *body) {
    int failed;
    if (!body) return;
    failed = body->failed;
    if (body->bytes) {
        OPENSSL_cleanse(body->bytes, body->length);
        free(body->bytes);
    }
    OPENSSL_cleanse(body, sizeof(*body));
    body->failed = failed;
}

void wco_body_fail(struct wco_body *body) {
    if (!body) return;
    body->failed = 1;
    wco_body_clear(body);
}

static int reject(struct wco_body *body) {
    wco_body_fail(body);
    return 0;
}

static int hex(unsigned char byte) {
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
    return -1;
}

int wco_body_begin(struct wco_body *body, const char *id, size_t id_length,
                     size_t length, const char *sha256, size_t sha256_length) {
    if (!body) return 0;
    if (body->failed || body->active || !wco_body_identifier(id, id_length) ||
        length > WCO_BODY_MAX || !sha256 || sha256_length != 64) return reject(body);
    for (size_t index = 0; index < 32; index++) {
        int high = hex((unsigned char)sha256[2 * index]);
        int low = hex((unsigned char)sha256[2 * index + 1]);
        if (high < 0 || low < 0) return reject(body);
        body->hash[index] = (uint8_t)((high << 4) | low);
    }
    body->bytes = length ? malloc(length) : NULL;
    if (length && !body->bytes) return reject(body);
    memcpy(body->id, id, id_length); body->id[id_length] = '\0';
    body->length = length; body->active = 1;
    return 1;
}

static int same(const struct wco_body *body, const char *id, size_t length) {
    return wco_body_identifier(id, length) && strlen(body->id) == length &&
           memcmp(body->id, id, length) == 0;
}

int wco_body_chunk(struct wco_body *body, const char *id, size_t id_length,
                     size_t offset, yyjson_val *data) {
    size_t decoded;
    if (!body) return 0;
    if (body->failed || !body->active || body->complete || !same(body, id, id_length) ||
        offset != body->used ||
        !wco_body_base64(data, body->bytes ? body->bytes + body->used : NULL,
                          body->length - body->used, &decoded)) return reject(body);
    body->used += decoded;
    return 1;
}

int wco_body_end(struct wco_body *body, const char *id, size_t id_length) {
    uint8_t digest[32]; unsigned length;
    int valid;
    if (!body) return 0;
    if (body->failed || !body->active || body->complete || !same(body, id, id_length) ||
        body->used != body->length) return reject(body);
    valid = EVP_Digest(body->bytes, body->length, digest, &length, EVP_sha256(), NULL) == 1 &&
              length == sizeof(digest) && CRYPTO_memcmp(body->hash, digest, sizeof(digest)) == 0;
    OPENSSL_cleanse(digest, sizeof(digest));
    if (!valid) return reject(body);
    body->complete = 1;
    return 1;
}

int wco_body_data(const struct wco_body *body, const uint8_t **bytes, size_t *length) {
    if (!bytes || !length) return 0;
    *bytes = NULL; *length = 0;
    if (!body || body->failed || !body->active || !body->complete) return 0;
    *bytes = body->bytes; *length = body->length;
    return 1;
}
