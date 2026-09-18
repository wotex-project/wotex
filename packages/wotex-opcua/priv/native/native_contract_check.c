/* SPDX-License-Identifier: Apache-2.0
 * Driver for the exact native-contract-v1 value/parser/namespace cells.
 */
#include "value_codec.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if(!(condition)) return __LINE__; } while(0)

static bool text_is(yyjson_val *value, const char *text) {
    return yyjson_is_str(value) && yyjson_get_len(value) == strlen(text) &&
           !memcmp(yyjson_get_str(value), text, yyjson_get_len(value));
}

static yyjson_val *selected_case(const WopJson *corpus, const char *id) {
    yyjson_val *cases = yyjson_obj_get(yyjson_doc_get_root(corpus->document), "cases");
    yyjson_val *selected = NULL, *candidate;
    size_t index, count;
    yyjson_arr_foreach(cases, index, count, candidate) {
        if(text_is(yyjson_obj_get(candidate, "id"), id)) {
            if(selected)
                return NULL;
            selected = candidate;
        }
    }
    return selected;
}

static bool production_input(yyjson_val *fixture, void *pool, WopJson *parsed) {
    yyjson_val *input = yyjson_obj_get(fixture, "input");
    size_t length = 0;
    char *serialized = yyjson_val_write(input, 0, &length);
    if(!serialized || length >= WOP_JSON_FRAME_BYTES) {
        free(serialized);
        return false;
    }
    char *frame = malloc(length + 1);
    if(!frame) {
        free(serialized);
        return false;
    }
    memcpy(frame, serialized, length);
    frame[length] = '\n';
    free(serialized);
    bool accepted = wop_json_read(frame, length + 1, pool, WOP_JSON_POOL_BYTES, parsed) == WOP_JSON_OK;
    free(frame);
    return accepted;
}

static int typed_roundtrip(yyjson_val *fixture) {
    int outcome = __LINE__;
    void *arena_pool = malloc(WOP_VALUE_POOL_BYTES);
    void *write_pool = malloc(WOP_JSON_POOL_BYTES);
    void *projection_pool = malloc(WOP_JSON_POOL_BYTES);
    void *input_pool = malloc(WOP_JSON_POOL_BYTES);
    WopValueArena arena = {0};
    yyjson_alc allocator = {0};
    yyjson_mut_doc *document = NULL;
    char *serialized = NULL;
    WopJson projection = {0};
    WopJson parsed_input = {0};
    yyjson_val *expected = yyjson_obj_get(
        yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value"), "variant");
    UA_Variant variant;
    memset(&variant, 0, sizeof(variant));
    if(!arena_pool || !write_pool || !projection_pool || !input_pool || !expected ||
       !production_input(fixture, input_pool, &parsed_input) ||
       !wop_value_arena_init(&arena, arena_pool, WOP_VALUE_POOL_BYTES) ||
       wop_value_read_variant(yyjson_obj_get(yyjson_doc_get_root(parsed_input.document), "variant"),
                              &arena, &variant) != WOP_VALUE_OK ||
       !yyjson_alc_pool_init(&allocator, write_pool, WOP_JSON_POOL_BYTES))
        goto done;
    document = yyjson_mut_doc_new(&allocator);
    yyjson_mut_val *result = NULL;
    if(!document || wop_value_write_variant(&variant, document, &result) != WOP_VALUE_OK || !result)
        goto done;
    yyjson_mut_doc_set_root(document, result);
    size_t length = 0;
    serialized = yyjson_mut_write_opts(document, 0, &allocator, &length, NULL);
    if(!serialized)
        goto done;
    serialized[length] = '\n';
    if(wop_json_read(serialized, length + 1, projection_pool, WOP_JSON_POOL_BYTES,
                     &projection) != WOP_JSON_OK ||
       !yyjson_equals(yyjson_doc_get_root(projection.document), expected))
        goto done;
    outcome = 0;
done:
    wop_json_clear(&parsed_input);
    wop_json_clear(&projection);
    wop_value_arena_reset(&arena);
    if(serialized) allocator.free(allocator.ctx, serialized);
    if(document) yyjson_mut_doc_free(document);
    free(arena_pool); free(write_pool); free(projection_pool); free(input_pool);
    return outcome;
}

static int hex64(yyjson_val *value, uint64_t *output) {
    if(!yyjson_is_str(value) || yyjson_get_len(value) != 16)
        return 0;
    uint64_t bits = 0;
    const unsigned char *text = (const unsigned char*)yyjson_get_str(value);
    for(size_t index = 0; index < 16; index++) {
        unsigned digit;
        if(text[index] >= '0' && text[index] <= '9') digit = text[index] - '0';
        else if(text[index] >= 'a' && text[index] <= 'f') digit = text[index] - 'a' + 10;
        else return 0;
        bits = (bits << 4) | digit;
    }
    *output = bits;
    return 1;
}

static int typed_float_roundtrip(yyjson_val *fixture) {
    int outcome = __LINE__;
    void *input_pool = malloc(WOP_JSON_POOL_BYTES);
    WopJson parsed_input = {0};
    if(!input_pool || !production_input(fixture, input_pool, &parsed_input)) {
        free(input_pool);
        return __LINE__;
    }
    yyjson_val *input = yyjson_doc_get_root(parsed_input.document);
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    uint64_t input_bits = 0, expected_bits = 0;
    CHECK(text_is(yyjson_obj_get(input, "type"), "Double"));
    CHECK(text_is(yyjson_obj_get(expected, "type"), "Double"));
    CHECK(hex64(yyjson_obj_get(input, "ieee754_hex"), &input_bits));
    CHECK(hex64(yyjson_obj_get(expected, "ieee754_hex"), &expected_bits));

    void *write_pool = malloc(WOP_JSON_POOL_BYTES);
    void *parse_pool = malloc(WOP_JSON_POOL_BYTES);
    void *arena_pool = malloc(WOP_VALUE_POOL_BYTES);
    yyjson_alc allocator = {0};
    yyjson_mut_doc *document = NULL;
    char *serialized = NULL;
    WopJson parsed = {0};
    WopValueArena arena = {0};
    UA_Double number;
    memcpy(&number, &input_bits, sizeof(number));
    UA_Variant variant;
    memset(&variant, 0, sizeof(variant));
    variant.type = &UA_TYPES[UA_TYPES_DOUBLE];
    variant.data = &number;
    if(!write_pool || !parse_pool || !arena_pool ||
       !yyjson_alc_pool_init(&allocator, write_pool, WOP_JSON_POOL_BYTES) ||
       !wop_value_arena_init(&arena, arena_pool, WOP_VALUE_POOL_BYTES))
        goto done;
    document = yyjson_mut_doc_new(&allocator);
    yyjson_mut_val *result = NULL;
    if(!document || wop_value_write_variant(&variant, document, &result) != WOP_VALUE_OK || !result)
        goto done;
    yyjson_mut_doc_set_root(document, result);
    size_t length = 0;
    serialized = yyjson_mut_write_opts(document, 0, &allocator, &length, NULL);
    if(!serialized)
        goto done;
    serialized[length] = '\n';
    if(wop_json_read(serialized, length + 1, parse_pool, WOP_JSON_POOL_BYTES, &parsed) != WOP_JSON_OK)
        goto done;
    UA_Variant decoded;
    memset(&decoded, 0, sizeof(decoded));
    if(wop_value_read_variant(yyjson_doc_get_root(parsed.document), &arena, &decoded) != WOP_VALUE_OK ||
       decoded.type != &UA_TYPES[UA_TYPES_DOUBLE] || !UA_Variant_isScalar(&decoded))
        goto done;
    uint64_t output_bits = 0;
    memcpy(&output_bits, decoded.data, sizeof(output_bits));
    if(input_bits != expected_bits || output_bits != expected_bits)
        goto done;
    outcome = 0;
done:
    wop_json_clear(&parsed);
    wop_value_arena_reset(&arena);
    if(serialized) allocator.free(allocator.ctx, serialized);
    if(document) yyjson_mut_doc_free(document);
    free(write_pool); free(parse_pool); free(arena_pool);
    wop_json_clear(&parsed_input);
    free(input_pool);
    return outcome;
}

static int parser_contract(yyjson_val *fixture) {
    yyjson_val *input = yyjson_obj_get(fixture, "input");
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    char *frame = NULL;
    size_t length = 0;
    yyjson_val *utf8 = yyjson_obj_get(input, "utf8");
    if(yyjson_is_str(utf8)) {
        length = yyjson_get_len(utf8);
        frame = malloc(length ? length : 1);
        if(!frame) return __LINE__;
        memcpy(frame, yyjson_get_str(utf8), length);
    } else {
        uint64_t fill = 0, bytes = 0, last = 0;
        if(!wop_json_uint64(yyjson_obj_get(input, "fill_byte"), &fill) || fill > 255 ||
           !wop_json_uint64(yyjson_obj_get(input, "line_bytes"), &bytes) || !bytes ||
           bytes > WOP_JSON_FRAME_BYTES + 1U ||
           !wop_json_uint64(yyjson_obj_get(input, "last_byte"), &last) || last > 255)
            return __LINE__;
        length = (size_t)bytes;
        frame = malloc(length);
        if(!frame) return __LINE__;
        memset(frame, (int)fill, length);
        frame[length - 1] = (char)last;
    }
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    if(!pool) { free(frame); return __LINE__; }
    WopJson parsed = {0};
    WopJsonStatus status = wop_json_read(frame, length, pool, WOP_JSON_POOL_BYTES, &parsed);
    const char *error = status == WOP_JSON_LIMIT ? "response_limit" : "invalid_request";
    uint64_t requests = 1;
    int result = !text_is(yyjson_obj_get(expected, "error"), error) ||
                 !wop_json_uint64(yyjson_obj_get(expected, "network_requests"), &requests) || requests ||
                 status == WOP_JSON_OK;
    wop_json_clear(&parsed);
    free(pool); free(frame);
    return result ? __LINE__ : 0;
}

static bool namespace_array(yyjson_val *input, UA_String **output, size_t *count) {
    if(!yyjson_is_arr(input) || !yyjson_arr_size(input) || yyjson_arr_size(input) > 65536)
        return false;
    *count = yyjson_arr_size(input);
    /* NOLINTNEXTLINE(clang-analyzer-optin.portability.UnixAPI): count is at least 1, the array size was checked above */
    *output = calloc(*count, sizeof(**output));
    if(!*output)
        return false;
    yyjson_val *value;
    size_t index, maximum;
    yyjson_arr_foreach(input, index, maximum, value) {
        if(!yyjson_is_str(value) || !yyjson_get_len(value) || yyjson_get_len(value) > 65536)
            return false;
        (*output)[index] = (UA_String){yyjson_get_len(value),
            (UA_Byte*)(uintptr_t)yyjson_get_str(value)};
    }
    return true;
}

static int namespace_contract(yyjson_val *fixture) {
    int outcome = __LINE__;
    void *input_pool = malloc(WOP_JSON_POOL_BYTES);
    WopJson parsed_input = {0};
    yyjson_val *input = NULL;
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    UA_String *server = NULL, *sdk = NULL;
    size_t server_count = 0, sdk_count = 0;
    void *arena_pool = malloc(WOP_VALUE_POOL_BYTES);
    void *write_pool = malloc(WOP_JSON_POOL_BYTES);
    WopValueArena arena = {0};
    yyjson_alc allocator = {0};
    yyjson_mut_doc *document = NULL;
    if(!arena_pool || !write_pool || !input_pool ||
       !production_input(fixture, input_pool, &parsed_input) ||
       !(input = yyjson_doc_get_root(parsed_input.document)) ||
       !namespace_array(yyjson_obj_get(input, "server"), &server, &server_count) ||
       !namespace_array(yyjson_obj_get(input, "sdk"), &sdk, &sdk_count) ||
       !wop_value_arena_init(&arena, arena_pool, WOP_VALUE_POOL_BYTES) ||
       !yyjson_alc_pool_init(&allocator, write_pool, WOP_JSON_POOL_BYTES))
        goto done;
    UA_NodeId public_id, sdk_id;
    memset(&public_id, 0, sizeof(public_id));
    memset(&sdk_id, 0, sizeof(sdk_id));
    if(wop_value_read_node_id(yyjson_obj_get(input, "node_id"), &arena, &public_id) != WOP_VALUE_OK)
        goto done;
    WopValueStatus status = wop_value_translate_node_id(server, server_count, sdk, sdk_count,
                                                        &public_id, &sdk_id);
    yyjson_val *expected_error = yyjson_obj_get(expected, "error");
    if(expected_error) {
        uint64_t requests = 1;
        if(status != WOP_VALUE_INVALID || !text_is(expected_error, "invalid_response") ||
           !wop_json_uint64(yyjson_obj_get(expected, "application_requests"), &requests) || requests)
            goto done;
        outcome = 0;
        goto done;
    }
    if(status != WOP_VALUE_OK)
        goto done;
    document = yyjson_mut_doc_new(&allocator);
    yyjson_mut_val *public_text = NULL, *sdk_text = NULL;
    if(!document ||
       wop_value_write_node_id(&public_id, document, &public_text) != WOP_VALUE_OK ||
       wop_value_write_node_id(&sdk_id, document, &sdk_text) != WOP_VALUE_OK ||
       !text_is(yyjson_obj_get(expected, "public_node_id"), yyjson_mut_get_str(public_text)) ||
       !text_is(yyjson_obj_get(expected, "sdk_node_id"), yyjson_mut_get_str(sdk_text)))
        goto done;
    outcome = 0;
done:
    if(document) yyjson_mut_doc_free(document);
    wop_value_arena_reset(&arena);
    wop_json_clear(&parsed_input);
    free(server); free(sdk); free(arena_pool); free(write_pool); free(input_pool);
    return outcome;
}

static int run_case(yyjson_val *fixture) {
    if(!text_is(yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "operator"), "exact"))
        return __LINE__;
    yyjson_val *operation = yyjson_obj_get(fixture, "operation");
    if(text_is(operation, "typed_roundtrip")) return typed_roundtrip(fixture);
    if(text_is(operation, "typed_float_roundtrip")) return typed_float_roundtrip(fixture);
    if(text_is(operation, "ipc_parse") || text_is(operation, "ipc_parse_generated"))
        return parser_contract(fixture);
    if(text_is(operation, "namespace_translation")) return namespace_contract(fixture);
    return __LINE__;
}

int main(int argc, char **argv) {
    if(argc != 3) return 2;
    FILE *file = fopen(argv[1], "rb");
    if(!file) return 2;
    char *bytes = malloc(WOP_JSON_FRAME_BYTES + 1U);
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    if(!bytes || !pool) { fclose(file); free(bytes); free(pool); return 2; }
    size_t length = fread(bytes, 1, WOP_JSON_FRAME_BYTES + 1U, file);
    int failed = ferror(file) || length > WOP_JSON_FRAME_BYTES;
    fclose(file);
    WopJson corpus = {0};
    if(!failed && yyjson_alc_pool_init(&corpus.allocator, pool, WOP_JSON_POOL_BYTES))
        corpus.document = yyjson_read_opts(bytes, length, YYJSON_READ_NUMBER_AS_RAW,
                                           &corpus.allocator, NULL);
    yyjson_val *fixture = corpus.document ? selected_case(&corpus, argv[2]) : NULL;
    int result = fixture ? run_case(fixture) : __LINE__;
    wop_json_clear(&corpus);
    free(bytes); free(pool);
    if(result) {
        fprintf(stderr, "native contract case failed at line %d: %s\n", result, argv[2]);
        return 1;
    }
    puts("{\"status\":\"passed\"}");
    return 0;
}
