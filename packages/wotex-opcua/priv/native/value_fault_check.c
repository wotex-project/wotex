/* SPDX-License-Identifier: Apache-2.0
 * Direct SDK-structure faults complement the materialized JSON input corpus.
 */
#include "value_codec.h"
#include <open62541/types_generated.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if(!(condition)) return __LINE__; } while(0)
typedef struct {
    WopValueArena arena;
    void *arena_pool;
    void *parse_pool;
    void *write_pool;
    yyjson_alc allocator;
    yyjson_mut_doc *document;
    WopJson parsed;
} Fixture;

static bool parse(Fixture *fixture, const char *text) {
    return wop_json_read(text, strlen(text), fixture->parse_pool, WOP_JSON_POOL_BYTES,
                         &fixture->parsed) == WOP_JSON_OK;
}

static bool document(Fixture *fixture, size_t size) {
    if(!yyjson_alc_pool_init(&fixture->allocator, fixture->write_pool, size)) return false;
    fixture->document = yyjson_mut_doc_new(&fixture->allocator);
    return fixture->document != NULL;
}

static bool all_zero(const void *value, size_t size) {
    const unsigned char *bytes = value;
    for(size_t index = 0; index < size; index++) if(bytes[index]) return false;
    return true;
}

static int faults(Fixture *fixture, const char *id) {
    yyjson_mut_val *result = (yyjson_mut_val*)(uintptr_t)1;
    UA_Variant variant;
    memset(&variant, 0, sizeof(variant));
    if(!strcmp(id, "WOP-NF01")) {
        WopValueArena invalid;
        CHECK(!wop_value_arena_init(NULL, fixture->arena_pool, 16));
        CHECK(!wop_value_arena_init(&invalid, NULL, 16));
        CHECK(!wop_value_arena_init(&invalid, fixture->arena_pool, 0));
        CHECK(!wop_value_arena_init(&invalid, fixture->arena_pool, WOP_VALUE_POOL_BYTES + 1));
        CHECK(!wop_value_arena_init(&invalid, (char*)fixture->arena_pool + 1, 16));
        CHECK(wop_value_read_variant(NULL, NULL, &variant) == WOP_VALUE_INVALID);
        CHECK(all_zero(&variant, sizeof(variant)));
        CHECK(wop_value_read_variant(NULL, &fixture->arena, NULL) == WOP_VALUE_INVALID);
        CHECK(wop_value_read_data_value(NULL, &fixture->arena, NULL) == WOP_VALUE_INVALID);
        fixture->arena.used = fixture->arena.capacity + 1;
        CHECK(wop_value_read_variant(NULL, &fixture->arena, &variant) == WOP_VALUE_INVALID);
        return 0;
    }
    if(!strcmp(id, "WOP-NF02")) {
        CHECK(wop_value_arena_init(&fixture->arena, fixture->arena_pool, 32));
        memset(fixture->arena_pool, 0x11, 32);
        fixture->arena.used = 16;
        CHECK(parse(fixture, "{\"type\":\"String\",\"array\":false,\"value\":\"retained\"}\n"));
        memset(&variant, 0xA5, sizeof(variant));
        CHECK(wop_value_read_variant(yyjson_doc_get_root(fixture->parsed.document),
              &fixture->arena, &variant) == WOP_VALUE_LIMIT);
        CHECK(fixture->arena.used == 16 && all_zero(&variant, sizeof(variant)));
        for(size_t index = 0; index < 16; index++) CHECK(((unsigned char*)fixture->arena_pool)[index] == 0x11);
        CHECK(all_zero((char*)fixture->arena_pool + 16, 16));
        wop_value_arena_reset(&fixture->arena);
        CHECK(fixture->arena.used == 0 && all_zero(fixture->arena_pool, 32));
        return 0;
    }
    if(!strcmp(id, "WOP-NF17")) {
        UA_String server[] = {UA_STRING("http://opcfoundation.org/UA/"), UA_STRING("urn:server"),
                              UA_STRING("urn:temperature"), UA_STRING("urn:power")};
        UA_String sdk[] = {UA_STRING("http://opcfoundation.org/UA/"), UA_STRING("urn:server"),
                           UA_STRING("urn:power"), UA_STRING("urn:temperature")};
        UA_NodeId public_id = UA_NODEID_NUMERIC(2, 42);
        UA_NodeId sdk_id = UA_NODEID_NUMERIC(9, 9);
        CHECK(wop_value_translate_node_id(server, 4, sdk, 4, &public_id, &sdk_id) == WOP_VALUE_OK);
        CHECK(sdk_id.namespaceIndex == 3 && sdk_id.identifier.numeric == 42);
        CHECK(public_id.namespaceIndex == 2 && public_id.identifier.numeric == 42);
        CHECK(wop_value_translate_node_id(NULL, 4, sdk, 4, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        CHECK(wop_value_translate_node_id(server, 0, sdk, 4, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        CHECK(wop_value_translate_node_id(server, 65537, sdk, 4, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        CHECK(wop_value_translate_node_id(server, 4, sdk, 4, NULL, &sdk_id) == WOP_VALUE_INVALID);
        CHECK(wop_value_translate_node_id(server, 4, sdk, 4, &public_id, NULL) == WOP_VALUE_INVALID);
        UA_String duplicate[] = {UA_STRING("urn:temperature"), UA_STRING("urn:temperature")};
        CHECK(wop_value_translate_node_id(server, 4, duplicate, 2, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        UA_String absent[] = {UA_STRING("urn:other")};
        CHECK(wop_value_translate_node_id(server, 4, absent, 1, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        UA_String invalid[] = {{1, NULL}};
        CHECK(wop_value_translate_node_id(server, 4, invalid, 1, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        public_id.namespaceIndex = 4;
        CHECK(wop_value_translate_node_id(server, 4, sdk, 4, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        public_id.namespaceIndex = 2;
        /* NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): a deliberately invalid identifier type for the fault case */
        public_id.identifierType = (enum UA_NodeIdType)255;
        CHECK(wop_value_translate_node_id(server, 4, sdk, 4, &public_id, &sdk_id) == WOP_VALUE_INVALID);
        return 0;
    }
    CHECK(document(fixture, !strcmp(id, "WOP-NF12") ? 1024 : WOP_JSON_POOL_BYTES));
    if(!strcmp(id, "WOP-NF03")) {
        CHECK(wop_value_write_variant(&variant, fixture->document, NULL) == WOP_VALUE_INVALID);
        CHECK(wop_value_write_variant(NULL, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        CHECK(wop_value_write_variant(&variant, NULL, &result) == WOP_VALUE_INVALID && !result);
        CHECK(wop_value_write_data_value(NULL, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        variant.type = &UA_TYPES[UA_TYPES_XMLELEMENT];
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_UNSUPPORTED && !result);
        variant.type = (const UA_DataType*)(uintptr_t)1;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_UNSUPPORTED && !result);
        return 0;
    }
    if(!strcmp(id, "WOP-NF04")) {
        variant.type = &UA_TYPES[UA_TYPES_INT32];
        variant.arrayLength = 1025;
        variant.data = (void*)(uintptr_t)1;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_LIMIT && !result);
        variant.arrayLength = 2;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        variant.data = NULL;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        variant.arrayLength = 0;
        variant.arrayDimensionsSize = 9;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_LIMIT && !result);
        return 0;
    }
    if(!strcmp(id, "WOP-NF05")) {
        UA_Int32 data[2] = {1, 2};
        UA_UInt32 axes[2] = {1, 3};
        variant.type = &UA_TYPES[UA_TYPES_INT32]; variant.data = data; variant.arrayLength = 2;
        variant.arrayDimensions = axes; variant.arrayDimensionsSize = 1;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        variant.arrayDimensionsSize = 2;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        axes[0] = 0;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        variant.arrayDimensions = NULL;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        return 0;
    }
    if(!strcmp(id, "WOP-NF06")) {
        UA_Double data = INFINITY;
        variant.type = &UA_TYPES[UA_TYPES_DOUBLE]; variant.data = &data;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        data = -INFINITY;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        data = NAN;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        UA_Float single = NAN;
        variant.type = &UA_TYPES[UA_TYPES_FLOAT]; variant.data = &single;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        return 0;
    }
    if(!strcmp(id, "WOP-NF07")) {
        UA_String data = {65537, (UA_Byte*)(uintptr_t)1};
        variant.type = &UA_TYPES[UA_TYPES_STRING]; variant.data = &data;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_LIMIT && !result);
        variant.type = &UA_TYPES[UA_TYPES_BYTESTRING];
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_LIMIT && !result);
        data.length = 1; data.data = NULL;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        return 0;
    }
    if(!strcmp(id, "WOP-NF08")) {
        UA_Byte invalid[][4] = {{0xC0, 0x80}, {0xED, 0xA0, 0x80}, {0xF4, 0x90, 0x80, 0x80},
                                {0xE0, 0x9F, 0x80}, {0xF0, 0x8F, 0xBF, 0xBF}, {0xE2, 0x82}};
        size_t lengths[] = {2, 3, 4, 3, 4, 2};
        UA_String data;
        variant.type = &UA_TYPES[UA_TYPES_STRING]; variant.data = &data;
        for(size_t index = 0; index < sizeof(lengths) / sizeof(lengths[0]); index++) {
            data.data = invalid[index]; data.length = lengths[index];
            CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        }
        return 0;
    }
    if(!strcmp(id, "WOP-NF09")) {
        UA_ExpandedNodeId data;
        memset(&data, 0, sizeof(data));
        data.nodeId = UA_NODEID_NUMERIC(1, 42);
        data.namespaceUri = UA_STRING("urn:example:nodes");
        variant.type = &UA_TYPES[UA_TYPES_EXPANDEDNODEID]; variant.data = &data;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        data.nodeId.namespaceIndex = 0; data.namespaceUri = UA_STRING("");
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        return 0;
    }
    if(!strcmp(id, "WOP-NF10")) {
        UA_ExtensionObject data;
        memset(&data, 0, sizeof(data));
        data.encoding = UA_EXTENSIONOBJECT_DECODED;
        variant.type = &UA_TYPES[UA_TYPES_EXTENSIONOBJECT]; variant.data = &data;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_UNSUPPORTED && !result);
        data.encoding = UA_EXTENSIONOBJECT_ENCODED_XML;
        UA_Byte body[] = {0xFF};
        data.content.encoded.body = (UA_ByteString){1, body};
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_INVALID && !result);
        data.content.encoded.body.length = 65537;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_LIMIT && !result);
        return 0;
    }
    if(!strcmp(id, "WOP-NF11")) {
        UA_DataValue data;
        memset(&data, 0, sizeof(data));
        data.status = 0xFFFFFFFF;
        data.hasSourcePicoseconds = true; data.sourcePicoseconds = 65535;
        data.hasServerTimestamp = true; data.serverTimestamp = INT64_MIN;
        data.hasServerPicoseconds = true; data.serverPicoseconds = 65535;
        CHECK(wop_value_write_data_value(&data, fixture->document, &result) == WOP_VALUE_OK && result);
        CHECK(yyjson_mut_get_uint(yyjson_mut_obj_get(result, "status")) == 0);
        CHECK(!yyjson_mut_obj_get(result, "source_timestamp") && !yyjson_mut_obj_get(result, "source_picoseconds"));
        CHECK(!yyjson_mut_obj_get(result, "value"));
        CHECK(yyjson_mut_get_sint(yyjson_mut_obj_get(result, "server_timestamp")) == INT64_MIN);
        CHECK(yyjson_mut_get_uint(yyjson_mut_obj_get(result, "server_picoseconds")) == 9999);
        return 0;
    }
    if(!strcmp(id, "WOP-NF12")) {
        UA_Byte bytes[4096]; memset(bytes, 'x', sizeof(bytes));
        UA_String data = {sizeof(bytes), bytes};
        variant.type = &UA_TYPES[UA_TYPES_STRING]; variant.data = &data;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_LIMIT && !result);
        for(size_t index = 0; index < sizeof(bytes); index++) CHECK(bytes[index] == 'x');
        return 0;
    }
    if(!strcmp(id, "WOP-NF13")) {
        char input[8192];
        size_t used = (size_t)snprintf(input, sizeof(input), "{\"type\":\"Byte\",\"array\":true,\"value\":[");
        for(unsigned index = 0; index < 1024; index++) {
            int size = snprintf(input + used, sizeof(input) - used, "%s%u", index ? "," : "", index % 256);
            CHECK(size > 0 && (size_t)size < sizeof(input) - used);
            used += (size_t)size;
        }
        CHECK(snprintf(input + used, sizeof(input) - used, "]}\n") == 3);
        CHECK(parse(fixture, input));
        CHECK(wop_value_read_variant(yyjson_doc_get_root(fixture->parsed.document),
              &fixture->arena, &variant) == WOP_VALUE_OK);
        CHECK(variant.arrayLength == 1024 && variant.type == &UA_TYPES[UA_TYPES_BYTE]);
        for(size_t index = 0; index < 1024; index++) CHECK(((UA_Byte*)variant.data)[index] == index % 256);
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_OK && result);
        CHECK(yyjson_mut_arr_size(yyjson_mut_obj_get(result, "value")) == 1024);
        CHECK(UA_calcSizeBinary(&variant, &UA_TYPES[UA_TYPES_VARIANT], NULL) == 1029);
        return 0;
    }
    if(!strcmp(id, "WOP-NF14")) {
        char input[65664];
        const char *prefix = "{\"type\":\"String\",\"array\":false,\"value\":\"";
        size_t length = strlen(prefix);
        memcpy(input, prefix, length); memset(input + length, 'x', 65536);
        memcpy(input + length + 65536, "\"}\n", 4);
        CHECK(parse(fixture, input));
        CHECK(wop_value_read_variant(yyjson_doc_get_root(fixture->parsed.document),
              &fixture->arena, &variant) == WOP_VALUE_OK);
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_OK && result);
        yyjson_mut_val *text = yyjson_mut_obj_get(result, "value");
        CHECK(yyjson_mut_get_len(text) == 65536);
        for(size_t index = 0; index < 65536; index++) CHECK(yyjson_mut_get_str(text)[index] == 'x');
        wop_json_clear(&fixture->parsed); wop_value_arena_reset(&fixture->arena);
        input[length + 65536] = 'x'; memcpy(input + length + 65537, "\"}\n", 4);
        CHECK(parse(fixture, input));
        CHECK(wop_value_read_variant(yyjson_doc_get_root(fixture->parsed.document),
              &fixture->arena, &variant) == WOP_VALUE_LIMIT);
        CHECK(!fixture->arena.used && all_zero(&variant, sizeof(variant)));
        return 0;
    }
    if(!strcmp(id, "WOP-NF15")) {
        UA_Byte bytes[65536];
        for(size_t index = 0; index < sizeof(bytes); index++) bytes[index] = (UA_Byte)index;
        UA_ByteString data = {sizeof(bytes), bytes};
        variant.type = &UA_TYPES[UA_TYPES_BYTESTRING]; variant.data = &data;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_OK && result);
        yyjson_mut_doc_set_root(fixture->document, result);
        size_t length;
        char *json = yyjson_mut_write_opts(fixture->document, 0, &fixture->allocator, &length, NULL);
        CHECK(json && length < WOP_JSON_FRAME_BYTES);
        /* Serialization belongs to the fixed fixture pool. Reuse its NUL as LF;
         * the strict reader receives an explicit length and retains no pointer. */
        json[length] = '\n';
        WopJsonStatus parsed = wop_json_read(json, length + 1, fixture->parse_pool,
                                            WOP_JSON_POOL_BYTES, &fixture->parsed);
        fixture->allocator.free(fixture->allocator.ctx, json);
        CHECK(parsed == WOP_JSON_OK);
        CHECK(wop_value_read_variant(yyjson_doc_get_root(fixture->parsed.document),
              &fixture->arena, &variant) == WOP_VALUE_OK);
        UA_ByteString *decoded = variant.data;
        CHECK(decoded->length == sizeof(bytes) && memcmp(decoded->data, bytes, sizeof(bytes)) == 0);
        return 0;
    }
    if(!strcmp(id, "WOP-NF16")) {
        UA_Byte bytes[65536]; memset(bytes, 'x', sizeof(bytes));
        UA_String strings[16];
        for(size_t index = 0; index < 16; index++) strings[index] = (UA_String){sizeof(bytes), bytes};
        strings[15].length = 65467; /* 5-byte array prefix + sixteen 4-byte lengths. */
        variant.type = &UA_TYPES[UA_TYPES_STRING]; variant.data = strings; variant.arrayLength = 16;
        CHECK(UA_calcSizeBinary(&variant, &UA_TYPES[UA_TYPES_VARIANT], NULL) == WOP_VALUE_WIRE_BYTES);
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_OK && result);
        yyjson_mut_doc_free(fixture->document); fixture->document = NULL;
        CHECK(document(fixture, WOP_JSON_POOL_BYTES));
        strings[15].length++;
        CHECK(wop_value_write_variant(&variant, fixture->document, &result) == WOP_VALUE_LIMIT && !result);
        CHECK(strings[15].length == 65468 && bytes[0] == 'x' && bytes[65535] == 'x');
        return 0;
    }
    return -1;
}

int main(int argc, char **argv) {
    if(argc != 2) return 2;
    Fixture fixture;
    memset(&fixture, 0, sizeof(fixture));
    fixture.arena_pool = malloc(WOP_VALUE_POOL_BYTES);
    fixture.parse_pool = malloc(WOP_JSON_POOL_BYTES);
    fixture.write_pool = malloc(WOP_JSON_POOL_BYTES);
    int result = -1;
    if(fixture.arena_pool && fixture.parse_pool && fixture.write_pool &&
       wop_value_arena_init(&fixture.arena, fixture.arena_pool, WOP_VALUE_POOL_BYTES))
        result = faults(&fixture, argv[1]);
    wop_json_clear(&fixture.parsed);
    if(fixture.document) yyjson_mut_doc_free(fixture.document);
    free(fixture.arena_pool); free(fixture.parse_pool); free(fixture.write_pool);
    if(result) { fprintf(stderr, "native value fault failed at line %d\n", result); return 1; }
    puts("{\"status\":\"passed\"}");
    return 0;
}
