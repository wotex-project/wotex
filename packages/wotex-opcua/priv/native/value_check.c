/* SPDX-License-Identifier: Apache-2.0
 * SDK-backed typed-value fixture driver. Every retained source allocation is
 * overwritten before response serialization to test the two ownership copies.
 */
#include "value_codec.h"
#include <open62541/types_generated.h>
#include <stdalign.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *status_name(WopValueStatus status) {
    switch(status) {
    case WOP_VALUE_OK: return "ok";
    case WOP_VALUE_INVALID: return "invalid";
    case WOP_VALUE_LIMIT: return "limit";
    case WOP_VALUE_UNSUPPORTED: return "unsupported";
    }
    return "invalid";
}

static int process(const char *mode, FILE *input, size_t capacity, FILE *report) {
    int outcome = 3;
    WopJson parsed = {0};
    WopValueArena arena = {0};
    yyjson_mut_doc *document = NULL;
    char *output = NULL;
    yyjson_alc allocator = {0};
    char *frame = malloc(WOP_JSON_FRAME_BYTES + 1);
    void *parse_pool = malloc(WOP_JSON_POOL_BYTES);
    void *value_pool = malloc(capacity);
    void *write_pool = malloc(WOP_JSON_POOL_BYTES);
    UA_Byte *binary = malloc(WOP_VALUE_WIRE_BYTES);
    if(!frame || !parse_pool || !value_pool || !write_pool || !binary)
        goto done;
    size_t length = fread(frame, 1, WOP_JSON_FRAME_BYTES + 1, input);
    int failed = ferror(input);
    if(fclose(input)) failed = 1;
    input = NULL;
    if(failed)
        goto done;
    UA_Variant variant;
    UA_DataValue data_value;
    memset(&variant, 0, sizeof(variant));
    memset(&data_value, 0, sizeof(data_value));
    if(!wop_value_arena_init(&arena, value_pool, capacity))
        goto done;
    WopJsonStatus syntax = wop_json_read(frame, length, parse_pool, WOP_JSON_POOL_BYTES, &parsed);
    bool is_variant = !strcmp(mode, "variant");
    WopValueStatus status;
    if(syntax != WOP_JSON_OK) {
        status = syntax == WOP_JSON_LIMIT ? WOP_VALUE_LIMIT : WOP_VALUE_INVALID;
    } else {
        yyjson_val *root = yyjson_doc_get_root(parsed.document);
        status = is_variant ? wop_value_read_variant(root, &arena, &variant) :
                              wop_value_read_data_value(root, &arena, &data_value);
    }
    wop_json_clear(&parsed);
    memset(parse_pool, 0xA5, WOP_JSON_POOL_BYTES);
    memset(frame, 0xA5, WOP_JSON_FRAME_BYTES + 1);
    if(!yyjson_alc_pool_init(&allocator, write_pool, WOP_JSON_POOL_BYTES))
        goto done;
    document = yyjson_mut_doc_new(&allocator);
    yyjson_mut_val *result = yyjson_mut_obj(document);
    if(!result)
        goto done;
    outcome = 4;
    yyjson_mut_doc_set_root(document, result);
    if(status == WOP_VALUE_OK) {
        UA_ByteString wire = {WOP_VALUE_WIRE_BYTES, binary};
        const UA_DataType *type = &UA_TYPES[is_variant ? UA_TYPES_VARIANT : UA_TYPES_DATAVALUE];
        const void *value = is_variant ? (const void*)&variant : (const void*)&data_value;
        UA_StatusCode encoded = UA_encodeBinary(value, type, &wire, NULL);
        if(encoded != UA_STATUSCODE_GOOD)
            goto done;
        yyjson_mut_val *projection = NULL;
        status = is_variant ? wop_value_write_variant(&variant, document, &projection) :
                              wop_value_write_data_value(&data_value, document, &projection);
        if(status == WOP_VALUE_OK) {
            if(!yyjson_mut_obj_add_val(document, result, "value", projection) ||
               !yyjson_mut_obj_add_uint(document, result, "wire_bytes", wire.length))
                goto done;
            if(wire.length <= 256) {
                char hex[512];
                static const char digits[] = "0123456789abcdef";
                for(size_t index = 0; index < wire.length; index++) {
                    hex[index * 2] = digits[binary[index] >> 4];
                    hex[index * 2 + 1] = digits[binary[index] & 15];
                }
                if(!yyjson_mut_obj_add_strncpy(document, result, "wire_hex", hex, wire.length * 2))
                    goto done;
            }
        }
    }
    if(!yyjson_mut_obj_add_str(document, result, "status", status_name(status)) ||
       !yyjson_mut_obj_add_uint(document, result, "arena_used", arena.used))
        goto done;
    wop_value_arena_reset(&arena);
    memset(&variant, 0, sizeof(variant));
    memset(&data_value, 0, sizeof(data_value));
    size_t size = 0;
    output = yyjson_mut_write_opts(document, 0, &allocator, &size, NULL);
    if(!output)
        goto done;
    outcome = 5;
    if(fwrite(output, 1, size, report) != size || fputc('\n', report) == EOF || fflush(report))
        goto done;
    outcome = 0;
done:
    if(input) fclose(input);
    wop_json_clear(&parsed);
    wop_value_arena_reset(&arena);
    if(output) allocator.free(allocator.ctx, output);
    if(document) yyjson_mut_doc_free(document);
    free(frame); free(parse_pool); free(value_pool); free(write_pool); free(binary);
    return outcome;
}

static bool equal_text(yyjson_val *value, const char *text) {
    return yyjson_is_str(value) && yyjson_get_len(value) == strlen(text) &&
           memcmp(yyjson_get_str(value), text, yyjson_get_len(value)) == 0;
}

static int check_case(const char *path, const char *id) {
    int outcome = 2;
    FILE *file = fopen(path, "rb");
    char *frame = malloc(WOP_JSON_FRAME_BYTES + 1);
    char *response = malloc(WOP_JSON_FRAME_BYTES + 1);
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    void *response_pool = malloc(WOP_JSON_POOL_BYTES);
    void *expected_pool = malloc(WOP_JSON_POOL_BYTES);
    WopJson corpus = {0}, result = {0}, expected = {0};
    FILE *input = NULL, *report = NULL;
    if(!file || !frame || !response || !pool || !response_pool || !expected_pool)
        goto done;
    size_t length = fread(frame, 1, WOP_JSON_FRAME_BYTES + 1, file);
    if(ferror(file) || length > WOP_JSON_FRAME_BYTES ||
       !yyjson_alc_pool_init(&corpus.allocator, pool, WOP_JSON_POOL_BYTES)) goto done;
    /* The checked-in fixture is a JSON document; each input_json is separately
     * admitted through the strict one-frame production reader. */
    corpus.document = yyjson_read_opts(frame, length, YYJSON_READ_NUMBER_AS_RAW,
                                       &corpus.allocator, NULL);
    if(!corpus.document) goto done;
    yyjson_val *cases = yyjson_obj_get(yyjson_doc_get_root(corpus.document), "cases");
    yyjson_val *selected = NULL, *candidate;
    size_t index, count;
    yyjson_arr_foreach(cases, index, count, candidate) {
        if(equal_text(yyjson_obj_get(candidate, "id"), id)) {
            if(selected) goto done;
            selected = candidate;
        }
    }
    if(!selected) goto done;
    yyjson_val *operation = yyjson_obj_get(selected, "operation");
    const char *mode = equal_text(operation, "variant") ? "variant" :
                        equal_text(operation, "data_value") ? "data_value" : NULL;
    yyjson_val *json = yyjson_obj_get(selected, "input_json");
    uint64_t capacity;
    if(!mode || !yyjson_is_str(json) ||
       !wop_json_uint64(yyjson_obj_get(selected, "pool_bytes"), &capacity) ||
       !capacity || capacity > WOP_VALUE_POOL_BYTES) goto done;
    input = tmpfile(); report = tmpfile();
    if(!input || !report || fwrite(yyjson_get_str(json), 1, yyjson_get_len(json), input) != yyjson_get_len(json))
        goto done;
    rewind(input);
    FILE *owned_input = input;
    input = NULL; /* process consumes and closes the input stream. */
    if(process(mode, owned_input, (size_t)capacity, report)) goto done;
    rewind(report);
    length = fread(response, 1, WOP_JSON_FRAME_BYTES + 1, report);
    if(ferror(report) || wop_json_read(response, length, response_pool, WOP_JSON_POOL_BYTES, &result) != WOP_JSON_OK)
        goto done;
    yyjson_val *root = yyjson_doc_get_root(result.document);
    if(!yyjson_equals(yyjson_obj_get(root, "status"), yyjson_obj_get(selected, "expected_status")))
        goto done;
    uint64_t used;
    if(!wop_json_uint64(yyjson_obj_get(root, "arena_used"), &used) || used > capacity)
        goto done;
    if(equal_text(yyjson_obj_get(root, "status"), "ok")) {
        if(!yyjson_equals(yyjson_obj_get(root, "wire_hex"), yyjson_obj_get(selected, "expected_hex")) ||
           wop_json_read(yyjson_get_str(json), yyjson_get_len(json), expected_pool,
                         WOP_JSON_POOL_BYTES, &expected) != WOP_JSON_OK ||
           !yyjson_equals(yyjson_obj_get(root, "value"), yyjson_doc_get_root(expected.document)))
            goto done;
    } else if(used || yyjson_obj_get(root, "value") || yyjson_obj_get(root, "wire_hex")) {
        goto done;
    }
    puts("{\"status\":\"passed\"}");
    outcome = 0;
done:
    if(outcome) fprintf(stderr, "native value case failed: %s\n", id);
    if(input) fclose(input);
    if(report) fclose(report);
    if(file) fclose(file);
    wop_json_clear(&corpus); wop_json_clear(&result); wop_json_clear(&expected);
    free(frame); free(response); free(pool); free(response_pool); free(expected_pool);
    return outcome;
}

int main(int argc, char **argv) {
    if(argc == 4 && !strcmp(argv[1], "--case"))
        return check_case(argv[2], argv[3]);
    if(argc < 3 || argc > 4 || (strcmp(argv[1], "--variant") && strcmp(argv[1], "--data-value")))
        return 2;
    size_t capacity = WOP_VALUE_POOL_BYTES;
    if(argc == 4) {
        char *tail;
        unsigned long size = strtoul(argv[3], &tail, 10);
        if(*tail || !size || size > WOP_VALUE_POOL_BYTES) return 2;
        capacity = size;
    }
    FILE *input = fopen(argv[2], "rb");
    if(!input) return 2;
    return process(!strcmp(argv[1], "--variant") ? "variant" : "data_value", input, capacity, stdout);
}
