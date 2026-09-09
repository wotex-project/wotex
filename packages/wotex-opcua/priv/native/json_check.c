#include "json_codec.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int self_test(void) {
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    if (!pool) return 1;
    const char *valid[] = {"{}\n", "{\"a\\u0000b\":1,\"a\":2}\n", "-0.0\n",
        "18446744073709551615\n", "-9223372036854775808\n", "[[[[[[[[0]]]]]]]]\n"};
    const char *invalid[] = {"{\"a\":1,\"a\":2}\n", "{\"a\":1,\"\\u0061\":2}\n",
        "[1,]\n", "NaN\n", "{}{}\n", "{}\n{}\n", "{a:1}\n", "[/*x*/1]\n",
        "'string'\n", "\xef\xbb\xbf{}\n", "0x01\n", "01\n", "+1\n"};
    WopJson json;
    for (size_t i = 0; i < sizeof(valid) / sizeof(*valid); i++) {
        if (wop_json_read(valid[i], strlen(valid[i]), pool, WOP_JSON_POOL_BYTES, &json) != WOP_JSON_OK)
            goto fail;
        wop_json_clear(&json);
    }
    for (size_t i = 0; i < sizeof(invalid) / sizeof(*invalid); i++) {
        if (wop_json_read(invalid[i], strlen(invalid[i]), pool, WOP_JSON_POOL_BYTES, &json) != WOP_JSON_INVALID)
            goto fail;
        if (json.document) goto fail;
    }
    if (wop_json_read("{}\n", 3, pool, 1, &json) != WOP_JSON_LIMIT) goto fail;
    if (wop_json_read("[[[[[[[[[]]]]]]]]]\n", 19, pool, WOP_JSON_POOL_BYTES, &json) != WOP_JSON_LIMIT)
        goto fail;
    const char *minimum = "-9223372036854775808\n";
    if (wop_json_read(minimum, strlen(minimum), pool, WOP_JSON_POOL_BYTES, &json) != WOP_JSON_OK)
        goto fail;
    int64_t signed_value = 0;
    uint64_t unsigned_value = 0;
    if (!wop_json_int64(yyjson_doc_get_root(json.document), &signed_value) || signed_value != INT64_MIN ||
        wop_json_uint64(yyjson_doc_get_root(json.document), &unsigned_value)) goto fail;
    wop_json_clear(&json);
    free(pool);
    puts("{\"status\":\"passed\"}");
    return 0;
fail:
    wop_json_clear(&json);
    free(pool);
    return 1;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return self_test();
    if (argc < 3 || argc > 4 || strcmp(argv[1], "--parse") != 0) return 2;
    size_t pool_bytes = WOP_JSON_POOL_BYTES;
    if (argc == 4) {
        char *end;
        unsigned long count = strtoul(argv[3], &end, 10);
        if (*end || count == 0 || count > WOP_JSON_POOL_BYTES) return 2;
        pool_bytes = count;
    }
    FILE *input = fopen(argv[2], "rb");
    if (!input) return 2;
    char *frame = malloc(WOP_JSON_FRAME_BYTES + 1U);
    void *pool = malloc(pool_bytes);
    if (!frame || !pool) { fclose(input); free(frame); free(pool); return 2; }
    size_t length = fread(frame, 1, WOP_JSON_FRAME_BYTES + 1U, input);
    int input_error = ferror(input);
    fclose(input);
    if (input_error) { free(frame); free(pool); return 2; }
    WopJson json;
    WopJsonStatus status = wop_json_read(frame, length, pool, pool_bytes, &json);
    if (status != WOP_JSON_OK) {
        printf("{\"status\":\"%s\",\"live_document\":%s}\n",
            status == WOP_JSON_LIMIT ? "limit" : "invalid", json.document ? "true" : "false");
    } else {
        yyjson_val *root = yyjson_doc_get_root(json.document);
        printf("{\"status\":\"ok\",\"nodes\":%zu", json.nodes);
        int64_t signed_value;
        uint64_t unsigned_value;
        double double_value;
        float float_value;
        if (wop_json_int64(root, &signed_value)) printf(",\"int64\":%" PRId64, signed_value);
        if (wop_json_uint64(root, &unsigned_value)) printf(",\"uint64\":%" PRIu64, unsigned_value);
        if (wop_json_double(root, &double_value)) {
            uint64_t bits;
            memcpy(&bits, &double_value, sizeof(bits));
            printf(",\"double_bits\":\"%016" PRIx64 "\"", bits);
        }
        if (wop_json_float(root, &float_value)) {
            uint32_t bits;
            memcpy(&bits, &float_value, sizeof(bits));
            printf(",\"float_bits\":\"%08" PRIx32 "\"", bits);
        }
        if (yyjson_is_str(root) && yyjson_get_len(root) <= 64) {
            const unsigned char *bytes = (const unsigned char *)yyjson_get_str(root);
            printf(",\"string_hex\":\"");
            for (size_t i = 0; i < yyjson_get_len(root); i++) printf("%02x", bytes[i]);
            printf("\"");
        }
        puts("}");
    }
    wop_json_clear(&json);
    free(pool);
    free(frame);
    return 0;
}
