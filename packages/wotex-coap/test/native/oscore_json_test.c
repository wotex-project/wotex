/* SPDX-License-Identifier: Apache-2.0 */
#include "json.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void rejected(struct wco_json *json, const char *input, enum wco_json_status expected) {
    assert(wco_json_parse(json, input, strlen(input)) == expected);
    assert(!wco_json_root(json));
}

static void syntax_and_keys(struct wco_json *json) {
    const char *ready = "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\",\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n";
    const char *allowed[] = {"version", "event", "backend", "revision"};
    yyjson_val *root;
    uint64_t version;
    assert(wco_json_parse(json, ready, strlen(ready)) == WCO_JSON_OK);
    root = wco_json_root(json);
    assert(wco_json_keys(root, allowed, 4));
    assert(wco_json_uint(yyjson_obj_get(root, "version"), 1, &version) && version == 1);
    assert(wco_json_string(yyjson_obj_get(root, "event"), "ready"));
    assert(wco_json_string(yyjson_obj_get(root, "backend"), "libcoap"));
    assert(wco_json_string(yyjson_obj_get(root, "revision"), "7cf7465b784baded4de183290c547d582becfd28"));
    assert(!wco_json_keys(root, allowed, 3));
    rejected(json, "{\"version\":1,\"version\":1}\n", WCO_JSON_DUPLICATE);
    rejected(json, "{\"version\":1,\"\\u0076ersion\":1}\n", WCO_JSON_DUPLICATE);
    rejected(json, "{\"parameters\":{\"a\\u0000b\":1,\"\\u0061\\u0000b\":2}}\n", WCO_JSON_DUPLICATE);
    {
        const char *distinct = "{\"a\\u0000b\":1,\"a\":2}\n";
        assert(wco_json_parse(json, distinct, strlen(distinct)) == WCO_JSON_OK);
    }
    assert(!wco_json_keys(wco_json_root(json), (const char *const[]){"a"}, 1));
    rejected(json, "{\"value\":NaN}\n", WCO_JSON_SYNTAX);
    rejected(json, "{\"value\":Infinity}\n", WCO_JSON_SYNTAX);
    rejected(json, "{\"value\":0x10}\n", WCO_JSON_SYNTAX);
    rejected(json, "{\"value\":1,}\n", WCO_JSON_SYNTAX);
    rejected(json, "{/*comment*/}\n", WCO_JSON_SYNTAX);
    rejected(json, "{\"value\":\"\\ud800\"}\n", WCO_JSON_SYNTAX);
    rejected(json, "{\"value\":\"\xff\"}\n", WCO_JSON_SYNTAX);
    rejected(json, "{} {}\n", WCO_JSON_SYNTAX);
    rejected(json, "[]\n", WCO_JSON_SYNTAX);
    rejected(json, "{}", WCO_JSON_FRAME);
    rejected(json, "{}\n{}\n", WCO_JSON_FRAME);
    assert(wco_json_parse(json, "{\"x\":\"a\0b\"}\n", 12) == WCO_JSON_FRAME);
    puts("WCO-C07 WCO-N03: strict UTF-8, duplicate decoded keys and exact field lookup");
}

static void integer(struct wco_json *json, const char *token, int valid, uint64_t expected) {
    char input[256];
    uint64_t value = 123;
    int length = snprintf(input, sizeof(input), "{\"number\":%s}\n", token);
    assert(length > 0 && (size_t)length < sizeof(input));
    assert(wco_json_parse(json, input, (size_t)length) == WCO_JSON_OK);
    assert(wco_json_uint(yyjson_obj_get(wco_json_root(json), "number"), UINT64_MAX, &value) == valid);
    assert(value == (valid ? expected : 0));
}

static void exact_numbers(struct wco_json *json) {
    integer(json, "0", 1, 0);
    integer(json, "-0", 1, 0);
    integer(json, "18446744073709551615", 1, UINT64_MAX);
    integer(json, "18446744073709551614", 1, UINT64_MAX - 1);
    integer(json, "9007199254740993", 1, UINT64_C(9007199254740993));
    integer(json, "18446744073709551616", 0, 0);
    integer(json, "-1", 0, 0);
    integer(json, "1.0", 0, 0);
    integer(json, "1e0", 0, 0);
    integer(json, "true", 0, 0);
    integer(json, "\"1\"", 0, 0);
    integer(json, "-1e-320", 0, 0);
    rejected(json, "{\"value\":1e309}\n", WCO_JSON_LIMIT);
    rejected(json, "{\"value\":-1e309}\n", WCO_JSON_LIMIT);
    rejected(json, "{\"value\":1e-400}\n", WCO_JSON_LIMIT);
    assert(wco_json_parse(json, "{\"value\":256}\n", 14) == WCO_JSON_OK);
    {
        uint64_t value = 1;
        assert(!wco_json_uint(yyjson_obj_get(wco_json_root(json), "value"), 255, &value));
        assert(value == 0);
    }
    {
        char input[160];
        memcpy(input, "{\"number\":", 10);
        memset(input + 10, '1', 129);
        memcpy(input + 138, "}\n", 2);
        assert(wco_json_parse(json, input, 140) == WCO_JSON_OK);
        input[138] = '1'; memcpy(input + 139, "}\n", 2);
        assert(wco_json_parse(json, input, 141) == WCO_JSON_LIMIT);
    }
    puts("WCO-C07 WCO-N03: exact uint64, Boolean/type rejection and finite number bounds");
}

static size_t nested(char *output, unsigned arrays) {
    char *next = output;
    memcpy(next, "{\"x\":", 5); next += 5;
    for (unsigned index = 0; index < arrays; index++) *next++ = '[';
    *next++ = '0';
    for (unsigned index = 0; index < arrays; index++) *next++ = ']';
    *next++ = '}'; *next++ = '\n';
    return (size_t)(next - output);
}

static size_t nodes(char *output, unsigned last) {
    char *next = output;
    *next++ = '{';
    for (unsigned array = 0; array < 4; array++) {
        unsigned count = array == 3 ? last : 1024;
        if (array) *next++ = ',';
        *next++ = '"'; *next++ = (char)('a' + array); *next++ = '"';
        *next++ = ':'; *next++ = '[';
        for (unsigned index = 0; index < count; index++) {
            if (index) *next++ = ',';
            *next++ = '0';
        }
        *next++ = ']';
    }
    *next++ = '}'; *next++ = '\n';
    return (size_t)(next - output);
}

static void limits(struct wco_json *json) {
    char *input = malloc(WCO_JSON_FRAME_MAX + 1), *next;
    size_t length;
    assert(input);
    assert(yyjson_read_max_memory_usage(WCO_JSON_FRAME_MAX, YYJSON_READ_NUMBER_AS_RAW) < WCO_JSON_POOL_SIZE);
    length = nested(input, 7);
    assert(wco_json_parse(json, input, length) == WCO_JSON_OK);
    length = nested(input, 8);
    assert(wco_json_parse(json, input, length) == WCO_JSON_LIMIT);
    length = nested(input, 64000);
    assert(wco_json_parse(json, input, length) == WCO_JSON_LIMIT);
    length = nodes(input, 1019); /* root + four arrays + 4091 scalars = 4096 */
    assert(wco_json_parse(json, input, length) == WCO_JSON_OK);
    length = nodes(input, 1020);
    assert(wco_json_parse(json, input, length) == WCO_JSON_LIMIT);
    next = input; *next++ = '{';
    for (unsigned index = 0; index < 1025; index++) {
        if (index) *next++ = ',';
        next += sprintf(next, "\"k%u\":0", index);
        if (index == 1023) {
            memcpy(next, "}\n", 2);
            assert(wco_json_parse(json, input, (size_t)(next - input) + 2) == WCO_JSON_OK);
        }
    }
    memcpy(next, "}\n", 2);
    assert(wco_json_parse(json, input, (size_t)(next - input) + 2) == WCO_JSON_LIMIT);
    memcpy(input, "{\"x\":\"", 6);
    memset(input + 6, 'a', WCO_JSON_FRAME_MAX - 9);
    memcpy(input + WCO_JSON_FRAME_MAX - 3, "\"}\n", 3);
    assert(wco_json_parse(json, input, WCO_JSON_FRAME_MAX) == WCO_JSON_OK);
    assert(yyjson_get_len(yyjson_obj_get(wco_json_root(json), "x")) == WCO_JSON_FRAME_MAX - 9);
    input[WCO_JSON_FRAME_MAX] = '\n';
    assert(wco_json_parse(json, input, WCO_JSON_FRAME_MAX + 1) == WCO_JSON_FRAME);
    assert(!wco_json_root(json));
    free(input);
    puts("WCO-C07 WCO-N03: exact depth/node/container/frame boundaries and fixed pool");
}

int main(void) {
    struct wco_json *json = wco_json_new();
    assert(json);
    syntax_and_keys(json);
    exact_numbers(json);
    limits(json);
    for (unsigned iteration = 0; iteration < 1000; iteration++) {
        assert(wco_json_parse(json, "{\"version\":1}\n", 14) == WCO_JSON_OK);
        wco_json_reset(json);
        assert(!wco_json_root(json));
    }
    wco_json_free(json);
    puts("WCO-C07 WCO-N03: 1000 bounded parser resets release all document state");
    return 0;
}
