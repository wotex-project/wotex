/* SPDX-License-Identifier: Apache-2.0 */
#include "body.h"
#include <assert.h>
#include <openssl/evp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char abc_sha[] = "b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78";
static const char empty_sha[] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

static yyjson_val *data(struct wco_json *json, const char *encoded) {
    size_t length = strlen(encoded) + 48;
    char *input = malloc(length);
    assert(input);
    int count = snprintf(input, length, "{\"data\":{\"type\":\"bytes\",\"base64\":\"%s\"}}\n", encoded);
    assert(count > 0 && (size_t)count < length);
    assert(wco_json_parse(json, input, (size_t)count) == WCO_JSON_OK);
    free(input);
    return yyjson_obj_get(wco_json_root(json), "data");
}

static void hidden(const struct wco_body *body) {
    const uint8_t *bytes = (const uint8_t *)"sentinel";
    size_t length = 123;
    assert(!wco_body_data(body, &bytes, &length));
    assert(!bytes && !length);
}

static void poisoned(struct wco_body *body) {
    assert(body->failed && !body->active && !body->bytes && !body->length && !body->used);
    hidden(body);
    assert(!wco_body_begin(body, "b1", 2, 3, abc_sha, 64));
    wco_body_clear(body);
    assert(body->failed);
}

static void base64(struct wco_json *json) {
    uint8_t bytes[256]; size_t length;
    const char *invalid[] = {"A", "AA", "AAA", "====", "A===", "A=AA", "AA=A", "AAA=AAAA", "Zh==", "Zm9=", "AA-_", "YW J", "YWJ\\n", "\\u0000AAA"};
    const char *valid[] = {"", "Zg==", "Zm8=", "Zm9v", "Zm9vYg==", "Zm9vYmE=", "Zm9vYmFy"};
    for (size_t index = 0; index < sizeof(valid) / sizeof(valid[0]); index++) {
        memset(bytes, 0xcd, sizeof(bytes));
        assert(wco_body_base64(data(json, valid[index]), bytes, sizeof(bytes), &length));
        assert(length == index && !memcmp(bytes, "foobar", length));
        assert(bytes[length] == 0xcd);
    }
    for (size_t index = 0; index < sizeof(invalid) / sizeof(invalid[0]); index++) {
        memset(bytes, 0xcd, sizeof(bytes)); length = 123;
        assert(!wco_body_base64(data(json, invalid[index]), bytes, sizeof(bytes), &length));
        assert(!length);
        for (size_t byte = 0; byte < sizeof(bytes); byte++) assert(bytes[byte] == 0xcd);
    }
    assert(!wco_body_base64(data(json, "QUJD"), bytes, 2, &length) && length == 0);
    assert(!wco_body_base64(data(json, "QUJD"), NULL, 3, &length) && length == 0);
    assert(wco_body_base64(data(json, ""), NULL, 0, &length) && length == 0);
    {
        const char *wrong[] = {"{\"data\":{\"type\":\"bytes\",\"base64\":\"\",\"extra\":0}}\n", "{\"data\":{\"type\":\"bytes\"}}\n", "{\"data\":{\"type\":\"text\",\"base64\":\"\"}}\n", "{\"data\":{\"type\":\"bytes\",\"base64\":0}}\n", "{\"data\":\"QUJD\"}\n"};
        for (size_t index = 0; index < sizeof(wrong) / sizeof(wrong[0]); index++) {
            assert(wco_json_parse(json, wrong[index], strlen(wrong[index])) == WCO_JSON_OK);
            assert(!wco_body_base64(yyjson_obj_get(wco_json_root(json), "data"), bytes, sizeof(bytes), &length));
        }
    }
    puts("WCO-C07 WCO-N03: canonical base64 rejects type/padding/alphabet/capacity failures without partial output");
}

static void assembly(struct wco_json *json) {
    struct wco_body body; const uint8_t *bytes; size_t length;
    wco_body_init(&body); hidden(&body);
    assert(wco_body_begin(&body, "b1", 2, 3, abc_sha, 64)); hidden(&body);
    assert(wco_body_chunk(&body, "b1", 2, 0, data(json, "QQ=="))); hidden(&body);
    assert(wco_body_chunk(&body, "b1", 2, 1, data(json, "QkM="))); hidden(&body);
    assert(wco_body_end(&body, "b1", 2));
    assert(wco_body_data(&body, &bytes, &length) && length == 3 && !memcmp(bytes, "ABC", 3));
    wco_body_clear(&body); hidden(&body);
    assert(wco_body_begin(&body, "empty", 5, 0, empty_sha, 64)); hidden(&body);
    assert(wco_body_end(&body, "empty", 5));
    assert(wco_body_data(&body, &bytes, &length) && !bytes && !length);
    wco_body_clear(&body); hidden(&body);
    puts("WCO-C07 WCO-N03: exact ABC and empty bodies stay hidden until SHA-256/length verification");
}

static void malformed(struct wco_json *json) {
    struct wco_body body;
    for (unsigned scenario = 0; scenario < 9; scenario++) {
        wco_body_init(&body);
        assert(wco_body_begin(&body, "b1", 2, 3, abc_sha, 64));
        switch (scenario) {
        case 0: assert(!wco_body_chunk(&body, "b1", 2, 1, data(json, "QUJD"))); break;
        case 1: assert(!wco_body_chunk(&body, "b2", 2, 0, data(json, "QUJD"))); break;
        case 2: assert(!wco_body_end(&body, "b1", 2)); break;
        case 3: assert(!wco_body_chunk(&body, "b1", 2, 0, data(json, "QUJDRA=="))); break;
        case 4: assert(!wco_body_begin(&body, "b2", 2, 3, abc_sha, 64)); break;
        case 5:
            assert(wco_body_chunk(&body, "b1", 2, 0, data(json, "QUJE")));
            assert(!wco_body_end(&body, "b1", 2)); break;
        case 6:
            assert(wco_body_chunk(&body, "b1", 2, 0, data(json, "QUJD")));
            assert(!wco_body_chunk(&body, "b1", 2, 0, data(json, ""))); break;
        case 7:
            assert(wco_body_chunk(&body, "b1", 2, 0, data(json, "QUJD")));
            assert(wco_body_end(&body, "b1", 2));
            assert(!wco_body_end(&body, "b1", 2)); break;
        case 8: wco_body_fail(&body); break;
        }
        poisoned(&body);
    }
    wco_body_init(&body); assert(!wco_body_begin(&body, "b1", 2, WCO_BODY_MAX + 1, abc_sha, 64)); poisoned(&body);
    wco_body_init(&body); assert(!wco_body_begin(&body, "b\0", 2, 3, abc_sha, 64)); poisoned(&body);
    wco_body_init(&body); assert(!wco_body_begin(&body, "b1", 2, 3, "B5", 2)); poisoned(&body);
    assert(!wco_body_identifier("", 0));
    assert(!wco_body_identifier("\x7f", 1));
    assert(!wco_body_identifier("\x80", 1));
    {
        char id[65], hash[64];
        memset(id, 'x', sizeof(id)); memset(hash, 'A', sizeof(hash));
        assert(wco_body_identifier(id, 64) && !wco_body_identifier(id, 65));
        wco_body_init(&body);
        assert(wco_body_begin(&body, id, 64, 0, empty_sha, 64));
        assert(wco_body_end(&body, id, 64));
        wco_body_clear(&body);
        wco_body_init(&body);
        assert(!wco_body_begin(&body, "b1", 2, 3, hash, 64)); poisoned(&body);
    }
    puts("WCO-C07 WCO-N03: wrong offset/id/hash, interleaving, incomplete/duplicate end and owner abort poison bounded body");
}

static void boundaries(struct wco_json *json) {
    uint8_t *chunk = malloc(WCO_BODY_CHUNK_MAX + 1), *all = malloc(WCO_BODY_MAX);
    char *encoded = malloc(4 * ((WCO_BODY_CHUNK_MAX + 3) / 3) + 1), hex[65];
    unsigned char digest[32]; unsigned digest_length;
    struct wco_body body; const uint8_t *bytes; size_t length;
    assert(chunk && all && encoded);
    for (size_t index = 0; index < WCO_BODY_CHUNK_MAX + 1; index++) chunk[index] = (uint8_t)index;
    for (size_t offset = 0; offset < WCO_BODY_MAX; offset += WCO_BODY_CHUNK_MAX)
        memcpy(all + offset, chunk, WCO_BODY_CHUNK_MAX);
    assert(EVP_Digest(all, WCO_BODY_MAX, digest, &digest_length, EVP_sha256(), NULL) && digest_length == 32);
    for (size_t index = 0; index < 32; index++) (void)sprintf(hex + 2 * index, "%02x", digest[index]);
    assert(EVP_EncodeBlock((unsigned char *)encoded, chunk, WCO_BODY_CHUNK_MAX) > 0);
    wco_body_init(&body); assert(wco_body_begin(&body, "max", 3, WCO_BODY_MAX, hex, 64));
    for (size_t offset = 0; offset < WCO_BODY_MAX; offset += WCO_BODY_CHUNK_MAX) {
        assert(wco_body_chunk(&body, "max", 3, offset, data(json, encoded)));
        hidden(&body);
    }
    assert(wco_body_end(&body, "max", 3));
    assert(wco_body_data(&body, &bytes, &length) && length == WCO_BODY_MAX && !memcmp(bytes, all, length));
    wco_body_clear(&body);
    assert(EVP_EncodeBlock((unsigned char *)encoded, chunk, WCO_BODY_CHUNK_MAX + 1) > 0);
    memset(all, 0xcd, WCO_BODY_MAX);
    assert(!wco_body_base64(data(json, encoded), all, WCO_BODY_MAX, &length) && length == 0);
    for (size_t index = 0; index < WCO_BODY_MAX; index++) assert(all[index] == 0xcd);
    free(chunk); free(all); free(encoded);
    puts("WCO-C07 WCO-N03: 32-KiB chunks assemble exact 1-MiB body; oversized chunk writes no output");
}

int main(void) {
    struct wco_json *json = wco_json_new(); assert(json);
    base64(json); assembly(json); malformed(json); boundaries(json);
    wco_json_free(json);
    return 0;
}
