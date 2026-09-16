/* SPDX-License-Identifier: Apache-2.0 */
#include "value_codec.h"
#include <limits.h>
#include <math.h>
#include <stdalign.h>
#include <stdint.h>
#include <string.h>

bool wop_value_arena_init(WopValueArena *arena, void *bytes, size_t capacity) {
    if(!arena)
        return false;
    memset(arena, 0, sizeof(*arena));
    if(!bytes || !capacity || capacity > WOP_VALUE_POOL_BYTES ||
       (uintptr_t)bytes % alignof(max_align_t) != 0)
        return false;
    arena->bytes = bytes;
    arena->capacity = capacity;
    return true;
}

void wop_value_arena_reset(WopValueArena *arena) {
    if(!arena || !arena->bytes || arena->used > arena->capacity)
        return;
    memset(arena->bytes, 0, arena->used);
    arena->used = 0;
}

static void *value_alloc(WopValueArena *arena, size_t size) {
    if(!arena || !arena->bytes || arena->capacity > WOP_VALUE_POOL_BYTES ||
       arena->used > arena->capacity || !size)
        return NULL;
    size_t padding = (alignof(max_align_t) - arena->used % alignof(max_align_t)) %
                     alignof(max_align_t);
    if(padding > arena->capacity - arena->used ||
       size > arena->capacity - arena->used - padding)
        return NULL;
    void *output = arena->bytes + arena->used + padding;
    arena->used += padding + size;
    memset(output, 0, size);
    return output;
}

static bool text_is(yyjson_val *value, const char *expected) {
    size_t length = strlen(expected); /* Only first-party literal keys/enums. */
    return yyjson_is_str(value) && yyjson_get_len(value) == length &&
           memcmp(yyjson_get_str(value), expected, length) == 0;
}

/* The syntax reader rejects duplicate decoded keys before this fixed schema
 * check. Each bit in required identifies a mandatory entry in keys. */
static bool object_keys(yyjson_val *value, const char *const *keys, size_t count,
                        unsigned required) {
    if(!yyjson_is_obj(value) || count > 16 || yyjson_obj_size(value) > count)
        return false;
    unsigned seen = 0;
    size_t index, maximum;
    yyjson_val *key, *field;
    yyjson_obj_foreach(value, index, maximum, key, field) {
        (void)field;
        size_t selected = 0;
        while(selected < count && !text_is(key, keys[selected]))
            selected++;
        if(selected == count || (seen & (1U << selected)))
            return false;
        seen |= 1U << selected;
    }
    return (seen & required) == required;
}

static WopValueStatus copy_bytes(WopValueArena *arena, const char *bytes, size_t length,
                                 size_t maximum, UA_String *output) {
    if(length > maximum)
        return WOP_VALUE_LIMIT;
    output->length = length;
    output->data = length ? value_alloc(arena, length) : UA_EMPTY_ARRAY_SENTINEL;
    if(!output->data)
        return WOP_VALUE_LIMIT;
    if(length)
        memcpy(output->data, bytes, length);
    return WOP_VALUE_OK;
}

static WopValueStatus read_string(yyjson_val *value, WopValueArena *arena,
                                  size_t maximum, UA_String *output) {
    if(yyjson_is_null(value)) {
        *output = UA_STRING_NULL;
        return WOP_VALUE_OK;
    }
    if(!yyjson_is_str(value))
        return WOP_VALUE_INVALID;
    return copy_bytes(arena, yyjson_get_str(value), yyjson_get_len(value), maximum, output);
}

static int base64_digit(unsigned char value) {
    if(value >= 'A' && value <= 'Z') return value - 'A';
    if(value >= 'a' && value <= 'z') return value - 'a' + 26;
    if(value >= '0' && value <= '9') return value - '0' + 52;
    if(value == '+') return 62;
    if(value == '/') return 63;
    return -1;
}

static WopValueStatus decode_base64(const char *text, size_t length, size_t maximum,
                                    WopValueArena *arena, UA_ByteString *output) {
    if(length % 4 != 0)
        return WOP_VALUE_INVALID;
    if(length / 4 > (maximum + 2) / 3)
        return WOP_VALUE_LIMIT;
    size_t padding = length && text[length - 1] == '=' ? 1 : 0;
    if(length > 1 && text[length - 2] == '=')
        padding++;
    size_t size = length / 4 * 3 - padding;
    if(size > maximum)
        return WOP_VALUE_LIMIT;
    unsigned char *decoded = size ? value_alloc(arena, size) : UA_EMPTY_ARRAY_SENTINEL;
    if(!decoded)
        return WOP_VALUE_LIMIT;
    size_t written = 0;
    for(size_t offset = 0; offset < length; offset += 4) {
        bool final = offset + 4 == length;
        int a = base64_digit((unsigned char)text[offset]);
        int b = base64_digit((unsigned char)text[offset + 1]);
        int c = text[offset + 2] == '=' && final ? 0 : base64_digit((unsigned char)text[offset + 2]);
        int d = text[offset + 3] == '=' && final ? 0 : base64_digit((unsigned char)text[offset + 3]);
        if(a < 0 || b < 0 || c < 0 || d < 0 ||
           (final && text[offset + 2] == '=' && text[offset + 3] != '=') ||
           (final && padding == 2 && ((b & 15) != 0 || text[offset + 3] != '=')) ||
           (final && padding == 1 && (c & 3) != 0))
            return WOP_VALUE_INVALID;
        if(written < size) decoded[written++] = (unsigned char)((a << 2) | (b >> 4));
        if(written < size) decoded[written++] = (unsigned char)((b << 4) | (c >> 2));
        if(written < size) decoded[written++] = (unsigned char)((c << 6) | d);
    }
    output->length = size;
    output->data = decoded;
    return WOP_VALUE_OK;
}

static WopValueStatus read_bytes(yyjson_val *value, WopValueArena *arena,
                                 size_t maximum, UA_ByteString *output) {
    static const char *const keys[] = {"type", "base64"};
    if(yyjson_is_null(value)) {
        *output = UA_BYTESTRING_NULL;
        return WOP_VALUE_OK;
    }
    yyjson_val *base64 = yyjson_obj_get(value, "base64");
    if(!object_keys(value, keys, 2, 3) || !text_is(yyjson_obj_get(value, "type"), "bytes") ||
       !yyjson_is_str(base64))
        return WOP_VALUE_INVALID;
    return decode_base64(yyjson_get_str(base64), yyjson_get_len(base64), maximum, arena, output);
}

static bool decimal_u32(const char *text, size_t length, uint32_t maximum, uint32_t *output) {
    if(!length || length > 10 || (length > 1 && text[0] == '0'))
        return false;
    uint32_t value = 0;
    for(size_t index = 0; index < length; index++) {
        unsigned char digit = (unsigned char)text[index];
        if(digit < '0' || digit > '9' || value > (maximum - (digit - '0')) / 10)
            return false;
        value = value * 10 + digit - '0';
    }
    *output = value;
    return true;
}

static WopValueStatus read_guid(const char *text, size_t length, UA_Guid *output) {
    if(length != 36)
        return WOP_VALUE_INVALID;
    for(size_t index = 0; index < length; index++) {
        bool separator = index == 8 || index == 13 || index == 18 || index == 23;
        char value = text[index];
        if(separator ? value != '-' : !((value >= '0' && value <= '9') ||
                                         (value >= 'a' && value <= 'f')))
            return WOP_VALUE_INVALID;
    }
    UA_String input = {length, (UA_Byte*)(uintptr_t)text};
    return UA_Guid_parse(output, input) == UA_STATUSCODE_GOOD ? WOP_VALUE_OK : WOP_VALUE_INVALID;
}

static WopValueStatus read_node(yyjson_val *value, WopValueArena *arena, UA_NodeId *output) {
    if(!yyjson_is_str(value) || yyjson_get_len(value) > 8192)
        return WOP_VALUE_INVALID;
    const char *text = yyjson_get_str(value);
    size_t length = yyjson_get_len(value);
    if(length < 7 || memcmp(text, "ns=", 3) != 0)
        return WOP_VALUE_INVALID;
    size_t separator = 3;
    while(separator < length && text[separator] != ';')
        separator++;
    uint32_t ns;
    if(!decimal_u32(text + 3, separator - 3, UINT16_MAX, &ns) ||
       length - separator < 3 || text[separator + 2] != '=')
        return WOP_VALUE_INVALID;
    output->namespaceIndex = (UA_UInt16)ns;
    char kind = text[separator + 1];
    const char *body = text + separator + 3;
    size_t body_length = length - separator - 3;
    switch(kind) {
    case 'i':
        output->identifierType = UA_NODEIDTYPE_NUMERIC;
        return decimal_u32(body, body_length, UINT32_MAX, &output->identifier.numeric)
                   ? WOP_VALUE_OK : WOP_VALUE_INVALID;
    case 's':
        output->identifierType = UA_NODEIDTYPE_STRING;
        return copy_bytes(arena, body, body_length, 4096, &output->identifier.string);
    case 'g':
        output->identifierType = UA_NODEIDTYPE_GUID;
        return read_guid(body, body_length, &output->identifier.guid);
    case 'b':
        output->identifierType = UA_NODEIDTYPE_BYTESTRING;
        return decode_base64(body, body_length, 4096, arena, &output->identifier.byteString);
    default:
        return WOP_VALUE_INVALID;
    }
}

static WopValueStatus read_expanded(yyjson_val *value, WopValueArena *arena,
                                    UA_ExpandedNodeId *output) {
    static const char *const keys[] = {"node_id", "namespace_uri", "server_index"};
    if(!object_keys(value, keys, 3, 7))
        return WOP_VALUE_INVALID;
    WopValueStatus status = read_node(yyjson_obj_get(value, "node_id"), arena, &output->nodeId);
    if(status != WOP_VALUE_OK)
        return status;
    yyjson_val *uri = yyjson_obj_get(value, "namespace_uri");
    if(!yyjson_is_null(uri) && (output->nodeId.namespaceIndex != 0 || !yyjson_is_str(uri) ||
                               yyjson_get_len(uri) == 0))
        return WOP_VALUE_INVALID;
    status = read_string(uri, arena, 4096, &output->namespaceUri);
    uint64_t server;
    if(status == WOP_VALUE_OK && (!wop_json_uint64(yyjson_obj_get(value, "server_index"), &server) ||
                                  server > UINT32_MAX))
        return WOP_VALUE_INVALID;
    if(status == WOP_VALUE_OK)
        output->serverIndex = (UA_UInt32)server;
    return status;
}

static WopValueStatus read_qualified(yyjson_val *value, WopValueArena *arena,
                                     UA_QualifiedName *output) {
    static const char *const keys[] = {"namespace", "name"};
    uint64_t ns;
    if(!object_keys(value, keys, 2, 3) || !wop_json_uint64(yyjson_obj_get(value, "namespace"), &ns) ||
       ns > UINT16_MAX)
        return WOP_VALUE_INVALID;
    output->namespaceIndex = (UA_UInt16)ns;
    return read_string(yyjson_obj_get(value, "name"), arena, WOP_VALUE_STRING_BYTES, &output->name);
}

static WopValueStatus read_localized(yyjson_val *value, WopValueArena *arena,
                                     UA_LocalizedText *output) {
    static const char *const keys[] = {"locale", "text"};
    if(!object_keys(value, keys, 2, 3))
        return WOP_VALUE_INVALID;
    WopValueStatus status = read_string(yyjson_obj_get(value, "locale"), arena,
                                        WOP_VALUE_STRING_BYTES, &output->locale);
    return status == WOP_VALUE_OK ? read_string(yyjson_obj_get(value, "text"), arena,
                                               WOP_VALUE_STRING_BYTES, &output->text) : status;
}

/* RFC 3629 scalar-value encodings. XML content remains opaque; only its declared
 * UTF-8 representation is checked. Embedded U+0000 remains length-bearing. */
static bool valid_utf8(const UA_String *value) {
    size_t index = 0;
    while(index < value->length) {
        unsigned char first = value->data[index++];
        if(first <= 0x7F)
            continue;
        size_t remaining;
        unsigned char low = 0x80, high = 0xBF;
        if(first >= 0xC2 && first <= 0xDF) {
            remaining = 1;
        } else if(first >= 0xE0 && first <= 0xEF) {
            remaining = 2;
            if(first == 0xE0) low = 0xA0;
            if(first == 0xED) high = 0x9F;
        } else if(first >= 0xF0 && first <= 0xF4) {
            remaining = 3;
            if(first == 0xF0) low = 0x90;
            if(first == 0xF4) high = 0x8F;
        } else {
            return false;
        }
        if(remaining > value->length - index || value->data[index] < low || value->data[index] > high)
            return false;
        index++;
        while(--remaining) {
            if(value->data[index] < 0x80 || value->data[index] > 0xBF)
                return false;
            index++;
        }
    }
    return true;
}

static WopValueStatus read_extension(yyjson_val *value, WopValueArena *arena,
                                     UA_ExtensionObject *output) {
    static const char *const keys[] = {"encoding_id", "encoding", "body"};
    if(!object_keys(value, keys, 3, 7))
        return WOP_VALUE_INVALID;
    WopValueStatus status = read_node(yyjson_obj_get(value, "encoding_id"), arena,
                                      &output->content.encoded.typeId);
    if(status != WOP_VALUE_OK)
        return status;
    yyjson_val *encoding = yyjson_obj_get(value, "encoding");
    yyjson_val *body = yyjson_obj_get(value, "body");
    if(text_is(encoding, "none")) {
        output->encoding = UA_EXTENSIONOBJECT_ENCODED_NOBODY;
        return yyjson_is_null(body) ? WOP_VALUE_OK : WOP_VALUE_INVALID;
    }
    if(!text_is(encoding, "binary") && !text_is(encoding, "xml"))
        return WOP_VALUE_INVALID;
    output->encoding = text_is(encoding, "binary") ? UA_EXTENSIONOBJECT_ENCODED_BYTESTRING
                                                  : UA_EXTENSIONOBJECT_ENCODED_XML;
    status = read_bytes(body, arena, WOP_VALUE_STRING_BYTES, &output->content.encoded.body);
    if(status == WOP_VALUE_OK && output->encoding == UA_EXTENSIONOBJECT_ENCODED_XML &&
       !valid_utf8(&output->content.encoded.body))
        return WOP_VALUE_INVALID;
    return status;
}

typedef struct {
    unsigned id;
    const char *name;
    const UA_DataType *sdk;
} ValueType;

static const ValueType value_types[] = {
    {0, "Null", NULL},
    {1, "Boolean", &UA_TYPES[UA_TYPES_BOOLEAN]},
    {2, "SByte", &UA_TYPES[UA_TYPES_SBYTE]},
    {3, "Byte", &UA_TYPES[UA_TYPES_BYTE]},
    {4, "Int16", &UA_TYPES[UA_TYPES_INT16]},
    {5, "UInt16", &UA_TYPES[UA_TYPES_UINT16]},
    {6, "Int32", &UA_TYPES[UA_TYPES_INT32]},
    {7, "UInt32", &UA_TYPES[UA_TYPES_UINT32]},
    {8, "Int64", &UA_TYPES[UA_TYPES_INT64]},
    {9, "UInt64", &UA_TYPES[UA_TYPES_UINT64]},
    {10, "Float", &UA_TYPES[UA_TYPES_FLOAT]},
    {11, "Double", &UA_TYPES[UA_TYPES_DOUBLE]},
    {12, "String", &UA_TYPES[UA_TYPES_STRING]},
    {13, "DateTime", &UA_TYPES[UA_TYPES_DATETIME]},
    {14, "Guid", &UA_TYPES[UA_TYPES_GUID]},
    {15, "ByteString", &UA_TYPES[UA_TYPES_BYTESTRING]},
    {17, "NodeId", &UA_TYPES[UA_TYPES_NODEID]},
    {18, "ExpandedNodeId", &UA_TYPES[UA_TYPES_EXPANDEDNODEID]},
    {19, "StatusCode", &UA_TYPES[UA_TYPES_STATUSCODE]},
    {20, "QualifiedName", &UA_TYPES[UA_TYPES_QUALIFIEDNAME]},
    {21, "LocalizedText", &UA_TYPES[UA_TYPES_LOCALIZEDTEXT]},
    {22, "ExtensionObject", &UA_TYPES[UA_TYPES_EXTENSIONOBJECT]}
};

static const ValueType *type_by_name(yyjson_val *name) {
    for(size_t index = 0; index < sizeof(value_types) / sizeof(value_types[0]); index++) {
        if(text_is(name, value_types[index].name))
            return &value_types[index];
    }
    return NULL;
}

static WopValueStatus read_element(unsigned id, yyjson_val *input, WopValueArena *arena,
                                   void *output) {
    int64_t signed_value;
    uint64_t unsigned_value;
    switch(id) {
    case 1:
        if(!yyjson_is_bool(input)) return WOP_VALUE_INVALID;
        *(UA_Boolean*)output = yyjson_get_bool(input);
        return WOP_VALUE_OK;
#define READ_SIGNED(ID, TYPE, MINIMUM, MAXIMUM) \
    case ID: \
        if(!wop_json_int64(input, &signed_value) || signed_value < (MINIMUM) || \
           signed_value > (MAXIMUM)) return WOP_VALUE_INVALID; \
        *(TYPE*)output = (TYPE)signed_value; \
        return WOP_VALUE_OK
#define READ_UNSIGNED(ID, TYPE, MAXIMUM) \
    case ID: \
        if(!wop_json_uint64(input, &unsigned_value) || unsigned_value > (MAXIMUM)) \
            return WOP_VALUE_INVALID; \
        *(TYPE*)output = (TYPE)unsigned_value; \
        return WOP_VALUE_OK
    READ_SIGNED(2, UA_SByte, INT8_MIN, INT8_MAX);
    READ_UNSIGNED(3, UA_Byte, UINT8_MAX);
    READ_SIGNED(4, UA_Int16, INT16_MIN, INT16_MAX);
    READ_UNSIGNED(5, UA_UInt16, UINT16_MAX);
    READ_SIGNED(6, UA_Int32, INT32_MIN, INT32_MAX);
    READ_UNSIGNED(7, UA_UInt32, UINT32_MAX);
    READ_SIGNED(8, UA_Int64, INT64_MIN, INT64_MAX);
    READ_UNSIGNED(9, UA_UInt64, UINT64_MAX);
    READ_SIGNED(13, UA_DateTime, INT64_MIN, INT64_MAX);
    READ_UNSIGNED(19, UA_StatusCode, UINT32_MAX);
#undef READ_SIGNED
#undef READ_UNSIGNED
    case 10:
        return wop_json_float(input, output) ? WOP_VALUE_OK : WOP_VALUE_INVALID;
    case 11:
        return wop_json_double(input, output) ? WOP_VALUE_OK : WOP_VALUE_INVALID;
    case 12:
        return read_string(input, arena, WOP_VALUE_STRING_BYTES, output);
    case 14:
        return yyjson_is_str(input) ? read_guid(yyjson_get_str(input), yyjson_get_len(input), output)
                                    : WOP_VALUE_INVALID;
    case 15:
        return read_bytes(input, arena, WOP_VALUE_STRING_BYTES, output);
    case 17:
        return read_node(input, arena, output);
    case 18:
        return read_expanded(input, arena, output);
    case 20:
        return read_qualified(input, arena, output);
    case 21:
        return read_localized(input, arena, output);
    case 22:
        return read_extension(input, arena, output);
    default:
        return WOP_VALUE_UNSUPPORTED;
    }
}

static WopValueStatus read_dimensions(yyjson_val *input, size_t elements,
                                      WopValueArena *arena, UA_Variant *output) {
    if(!input)
        return WOP_VALUE_OK;
    if(!elements || !yyjson_is_arr(input) || yyjson_arr_size(input) < 2 || yyjson_arr_size(input) > 8)
        return WOP_VALUE_INVALID;
    UA_UInt32 axes[8];
    size_t product = 1, index, count;
    yyjson_val *axis;
    yyjson_arr_foreach(input, index, count, axis) {
        uint64_t length;
        if(!wop_json_uint64(axis, &length) || length < 1 || length > WOP_VALUE_ELEMENTS ||
           product > elements / length)
            return WOP_VALUE_INVALID;
        product *= (size_t)length;
        axes[index] = (UA_UInt32)length;
    }
    if(product != elements)
        return WOP_VALUE_INVALID;
    output->arrayDimensions = value_alloc(arena, count * sizeof(UA_UInt32));
    if(!output->arrayDimensions)
        return WOP_VALUE_LIMIT;
    output->arrayDimensionsSize = count;
    memcpy(output->arrayDimensions, axes, count * sizeof(UA_UInt32));
    return WOP_VALUE_OK;
}

static WopValueStatus read_variant(yyjson_val *input, WopValueArena *arena, UA_Variant *output) {
    static const char *const keys[] = {"type", "array", "value", "dimensions"};
    if(!object_keys(input, keys, 4, 7) || !yyjson_is_bool(yyjson_obj_get(input, "array")))
        return WOP_VALUE_INVALID;
    const ValueType *type = type_by_name(yyjson_obj_get(input, "type"));
    if(!type)
        return WOP_VALUE_UNSUPPORTED;
    bool array = yyjson_get_bool(yyjson_obj_get(input, "array"));
    yyjson_val *payload = yyjson_obj_get(input, "value");
    yyjson_val *dimensions = yyjson_obj_get(input, "dimensions");
    output->storageType = UA_VARIANT_DATA_NODELETE;
    if(type->id == 0)
        return !array && !dimensions && yyjson_is_null(payload) ? WOP_VALUE_OK : WOP_VALUE_INVALID;
    output->type = type->sdk;
    if(!array) {
        if(dimensions)
            return WOP_VALUE_INVALID;
        output->data = value_alloc(arena, type->sdk->memSize);
        return output->data ? read_element(type->id, payload, arena, output->data) : WOP_VALUE_LIMIT;
    }
    if(yyjson_is_null(payload))
        return dimensions ? WOP_VALUE_INVALID : WOP_VALUE_OK;
    if(!yyjson_is_arr(payload))
        return WOP_VALUE_INVALID;
    size_t count = yyjson_arr_size(payload);
    if(count > WOP_VALUE_ELEMENTS)
        return WOP_VALUE_LIMIT;
    if(count > SIZE_MAX / type->sdk->memSize)
        return WOP_VALUE_LIMIT;
    output->arrayLength = count;
    output->data = count ? value_alloc(arena, count * type->sdk->memSize) : UA_EMPTY_ARRAY_SENTINEL;
    if(!output->data)
        return WOP_VALUE_LIMIT;
    WopValueStatus status = read_dimensions(dimensions, count, arena, output);
    if(status != WOP_VALUE_OK)
        return status;
    size_t index, maximum;
    yyjson_val *element;
    yyjson_arr_foreach(payload, index, maximum, element) {
        status = read_element(type->id, element, arena,
                              (unsigned char*)output->data + index * type->sdk->memSize);
        if(status != WOP_VALUE_OK)
            return status;
    }
    return WOP_VALUE_OK;
}

static bool valid_arena(const WopValueArena *arena) {
    return arena && arena->bytes && arena->capacity && arena->capacity <= WOP_VALUE_POOL_BYTES &&
           arena->used <= arena->capacity && (uintptr_t)arena->bytes % alignof(max_align_t) == 0;
}

static void rollback(WopValueArena *arena, size_t checkpoint) {
    memset(arena->bytes + checkpoint, 0, arena->used - checkpoint);
    arena->used = checkpoint;
}

WopValueStatus wop_value_read_node_id(yyjson_val *input, WopValueArena *arena,
                                    UA_NodeId *output) {
    if(!output)
        return WOP_VALUE_INVALID;
    memset(output, 0, sizeof(*output));
    if(!valid_arena(arena))
        return WOP_VALUE_INVALID;
    size_t checkpoint = arena->used;
    WopValueStatus status = read_node(input, arena, output);
    if(status != WOP_VALUE_OK) {
        rollback(arena, checkpoint);
        memset(output, 0, sizeof(*output));
    }
    return status;
}

WopValueStatus wop_value_read_variant(yyjson_val *input, WopValueArena *arena, UA_Variant *output) {
    if(!output)
        return WOP_VALUE_INVALID;
    memset(output, 0, sizeof(*output));
    if(!valid_arena(arena))
        return WOP_VALUE_INVALID;
    size_t checkpoint = arena->used;
    WopValueStatus status = read_variant(input, arena, output);
    if(status == WOP_VALUE_OK) {
        size_t bytes = UA_calcSizeBinary(output, &UA_TYPES[UA_TYPES_VARIANT], NULL);
        if(!bytes || bytes > WOP_VALUE_WIRE_BYTES)
            status = WOP_VALUE_LIMIT;
    }
    if(status != WOP_VALUE_OK) {
        rollback(arena, checkpoint);
        memset(output, 0, sizeof(*output));
    }
    return status;
}

static WopValueStatus read_metadata(yyjson_val *input, UA_DataValue *output) {
    static const char *const timestamps[] = {"source_timestamp", "server_timestamp"};
    static const char *const fractions[] = {"source_picoseconds", "server_picoseconds"};
    for(size_t index = 0; index < 2; index++) {
        yyjson_val *timestamp = yyjson_obj_get(input, timestamps[index]);
        yyjson_val *fraction = yyjson_obj_get(input, fractions[index]);
        int64_t ticks = 0;
        uint64_t picoseconds = 0;
        if(timestamp && !wop_json_int64(timestamp, &ticks))
            return WOP_VALUE_INVALID;
        if(fraction && (!timestamp || !wop_json_uint64(fraction, &picoseconds) || picoseconds > 9999))
            return WOP_VALUE_INVALID;
        if(index == 0) {
            output->hasSourceTimestamp = timestamp != NULL;
            output->hasSourcePicoseconds = fraction != NULL;
            output->sourceTimestamp = (UA_DateTime)ticks;
            output->sourcePicoseconds = (UA_UInt16)picoseconds;
        } else {
            output->hasServerTimestamp = timestamp != NULL;
            output->hasServerPicoseconds = fraction != NULL;
            output->serverTimestamp = (UA_DateTime)ticks;
            output->serverPicoseconds = (UA_UInt16)picoseconds;
        }
    }
    return WOP_VALUE_OK;
}

static WopValueStatus read_data_value(yyjson_val *input, WopValueArena *arena, UA_DataValue *output) {
    static const char *const keys[] = {"has_value", "value", "status", "source_timestamp",
                                      "server_timestamp", "source_picoseconds", "server_picoseconds"};
    if(!object_keys(input, keys, 7, 5) || !yyjson_is_bool(yyjson_obj_get(input, "has_value")))
        return WOP_VALUE_INVALID;
    uint64_t status_code;
    if(!wop_json_uint64(yyjson_obj_get(input, "status"), &status_code) || status_code > UINT32_MAX)
        return WOP_VALUE_INVALID;
    output->hasStatus = status_code != 0;
    output->status = (UA_StatusCode)status_code;
    output->hasValue = yyjson_get_bool(yyjson_obj_get(input, "has_value"));
    yyjson_val *value = yyjson_obj_get(input, "value");
    if(output->hasValue != (value != NULL))
        return WOP_VALUE_INVALID;
    WopValueStatus status = read_metadata(input, output);
    if(status == WOP_VALUE_OK && output->hasValue)
        status = wop_value_read_variant(value, arena, &output->value);
    return status;
}

WopValueStatus wop_value_read_data_value(yyjson_val *input, WopValueArena *arena, UA_DataValue *output) {
    if(!output)
        return WOP_VALUE_INVALID;
    memset(output, 0, sizeof(*output));
    if(!valid_arena(arena))
        return WOP_VALUE_INVALID;
    size_t checkpoint = arena->used;
    WopValueStatus status = read_data_value(input, arena, output);
    if(status == WOP_VALUE_OK) {
        size_t bytes = UA_calcSizeBinary(output, &UA_TYPES[UA_TYPES_DATAVALUE], NULL);
        if(!bytes || bytes > WOP_VALUE_WIRE_BYTES)
            status = WOP_VALUE_LIMIT;
    }
    if(status != WOP_VALUE_OK) {
        rollback(arena, checkpoint);
        memset(output, 0, sizeof(*output));
    }
    return status;
}

/* The response projection accepts only fixed built-in SDK representations.
 * Unknown decoded ExtensionObject classes never acquire a JSON schema here. */
typedef struct {
    yyjson_mut_doc *document;
    WopValueStatus status;
} ValueWriter;

static yyjson_mut_val *writer_fail(ValueWriter *writer, WopValueStatus status) {
    if(writer->status == WOP_VALUE_OK)
        writer->status = status;
    return NULL;
}

static yyjson_mut_val *writer_checked(ValueWriter *writer, yyjson_mut_val *value) {
    return value ? value : writer_fail(writer, WOP_VALUE_LIMIT);
}

static bool writer_field(ValueWriter *writer, yyjson_mut_val *object, const char *key,
                          yyjson_mut_val *value) {
    if(!value || !yyjson_mut_obj_add(object, yyjson_mut_str(writer->document, key), value)) {
        writer_fail(writer, WOP_VALUE_LIMIT);
        return false;
    }
    return true;
}

static bool valid_string(const UA_String *value, size_t maximum) {
    return value && value->length <= maximum && (!value->length || value->data);
}

static bool namespace_string(const UA_String *value) {
    return valid_string(value, WOP_VALUE_STRING_BYTES) && value->length && valid_utf8(value);
}

static bool same_string(const UA_String *left, const UA_String *right) {
    return left->length == right->length &&
           (!left->length || !memcmp(left->data, right->data, left->length));
}

static bool valid_node_id(const UA_NodeId *value) {
    if(!value)
        return false;
    switch(value->identifierType) {
    case UA_NODEIDTYPE_NUMERIC:
    case UA_NODEIDTYPE_GUID:
        return true;
    case UA_NODEIDTYPE_STRING:
        return valid_string(&value->identifier.string, 4096) &&
               valid_utf8(&value->identifier.string);
    case UA_NODEIDTYPE_BYTESTRING:
        return valid_string(&value->identifier.byteString, 4096);
    default:
        return false;
    }
}

WopValueStatus wop_value_translate_node_id(const UA_String *server_namespaces,
                                         size_t server_count,
                                         const UA_String *sdk_namespaces,
                                         size_t sdk_count,
                                         const UA_NodeId *public_id,
                                         UA_NodeId *sdk_id) {
    if(!server_namespaces || !sdk_namespaces || !public_id || !sdk_id ||
       !server_count || server_count > (size_t)UINT16_MAX + 1U ||
       !sdk_count || sdk_count > (size_t)UINT16_MAX + 1U ||
       public_id->namespaceIndex >= server_count || !valid_node_id(public_id))
        return WOP_VALUE_INVALID;
    const UA_String *identity = &server_namespaces[public_id->namespaceIndex];
    if(!namespace_string(identity))
        return WOP_VALUE_INVALID;
    size_t server_matches = 0;
    for(size_t index = 0; index < server_count; index++) {
        if(!namespace_string(&server_namespaces[index]))
            return WOP_VALUE_INVALID;
        if(same_string(&server_namespaces[index], identity))
            server_matches++;
    }
    size_t sdk_matches = 0;
    size_t translated = 0;
    for(size_t index = 0; index < sdk_count; index++) {
        if(!namespace_string(&sdk_namespaces[index]))
            return WOP_VALUE_INVALID;
        if(same_string(&sdk_namespaces[index], identity)) {
            sdk_matches++;
            translated = index;
        }
    }
    if(server_matches != 1 || sdk_matches != 1)
        return WOP_VALUE_INVALID;
    *sdk_id = *public_id;
    sdk_id->namespaceIndex = (UA_UInt16)translated;
    return WOP_VALUE_OK;
}

static yyjson_mut_val *write_string(ValueWriter *writer, const UA_String *value, size_t maximum) {
    if(!valid_string(value, maximum))
        return writer_fail(writer, value && value->length > maximum ? WOP_VALUE_LIMIT : WOP_VALUE_INVALID);
    if(!valid_utf8(value))
        return writer_fail(writer, WOP_VALUE_INVALID);
    return writer_checked(writer, value->data ?
        yyjson_mut_strncpy(writer->document, (const char*)value->data, value->length) :
        yyjson_mut_null(writer->document));
}

static size_t encode_base64(const UA_ByteString *value, char *output) {
    static const char digits[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t used = 0;
    for(size_t index = 0; index < value->length; index += 3) {
        size_t remaining = value->length - index;
        unsigned a = value->data[index];
        unsigned b = remaining > 1 ? value->data[index + 1] : 0;
        unsigned c = remaining > 2 ? value->data[index + 2] : 0;
        output[used++] = digits[a >> 2];
        output[used++] = digits[((a & 3) << 4) | (b >> 4)];
        output[used++] = remaining > 1 ? digits[((b & 15) << 2) | (c >> 6)] : '=';
        output[used++] = remaining > 2 ? digits[c & 63] : '=';
    }
    return used;
}

static yyjson_mut_val *write_bytes(ValueWriter *writer, const UA_ByteString *value) {
    if(!valid_string(value, WOP_VALUE_STRING_BYTES))
        return writer_fail(writer, value && value->length > WOP_VALUE_STRING_BYTES ?
                            WOP_VALUE_LIMIT : WOP_VALUE_INVALID);
    if(!value->data)
        return writer_checked(writer, yyjson_mut_null(writer->document));
    char encoded[((WOP_VALUE_STRING_BYTES + 2) / 3) * 4];
    size_t size = encode_base64(value, encoded);
    yyjson_mut_val *object = writer_checked(writer, yyjson_mut_obj(writer->document));
    if(!writer_field(writer, object, "type", yyjson_mut_str(writer->document, "bytes")) ||
       !writer_field(writer, object, "base64", yyjson_mut_strncpy(writer->document, encoded, size)))
        return NULL;
    return object;
}

static size_t encode_guid(const UA_Guid *guid, char output[36]) {
    static const char digits[] = "0123456789abcdef";
    unsigned char bytes[16] = {
        (unsigned char)(guid->data1 >> 24), (unsigned char)(guid->data1 >> 16),
        (unsigned char)(guid->data1 >> 8), (unsigned char)guid->data1,
        (unsigned char)(guid->data2 >> 8), (unsigned char)guid->data2,
        (unsigned char)(guid->data3 >> 8), (unsigned char)guid->data3
    };
    memcpy(bytes + 8, guid->data4, 8);
    size_t used = 0;
    for(size_t index = 0; index < 16; index++) {
        if(index == 4 || index == 6 || index == 8 || index == 10)
            output[used++] = '-';
        output[used++] = digits[bytes[index] >> 4];
        output[used++] = digits[bytes[index] & 15];
    }
    return used;
}

static size_t encode_decimal(uint32_t number, char *output) {
    char reversed[10];
    size_t used = 0;
    do {
        reversed[used++] = (char)('0' + number % 10);
        number /= 10;
    } while(number);
    for(size_t index = 0; index < used; index++)
        output[index] = reversed[used - index - 1];
    return used;
}

static yyjson_mut_val *write_node(ValueWriter *writer, const UA_NodeId *value) {
    char text[8192];
    memcpy(text, "ns=", 3);
    size_t used = 3 + encode_decimal(value->namespaceIndex, text + 3);
    text[used++] = ';';
    switch(value->identifierType) {
    case UA_NODEIDTYPE_NUMERIC:
        text[used++] = 'i'; text[used++] = '=';
        used += encode_decimal(value->identifier.numeric, text + used);
        break;
    case UA_NODEIDTYPE_GUID:
        text[used++] = 'g'; text[used++] = '=';
        used += encode_guid(&value->identifier.guid, text + used);
        break;
    case UA_NODEIDTYPE_STRING:
    case UA_NODEIDTYPE_BYTESTRING: {
        const UA_String *body = value->identifierType == UA_NODEIDTYPE_STRING ?
            &value->identifier.string : &value->identifier.byteString;
        if(!valid_string(body, 4096) || !body->data)
            return writer_fail(writer, body->length > 4096 ? WOP_VALUE_LIMIT : WOP_VALUE_INVALID);
        if(value->identifierType == UA_NODEIDTYPE_STRING && !valid_utf8(body))
            return writer_fail(writer, WOP_VALUE_INVALID);
        text[used++] = value->identifierType == UA_NODEIDTYPE_STRING ? 's' : 'b';
        text[used++] = '=';
        if(value->identifierType == UA_NODEIDTYPE_STRING) {
            memcpy(text + used, body->data, body->length);
            used += body->length;
        } else {
            used += encode_base64(body, text + used);
        }
        break;
    }
    default:
        return writer_fail(writer, WOP_VALUE_INVALID);
    }
    return writer_checked(writer, yyjson_mut_strncpy(writer->document, text, used));
}

WopValueStatus wop_value_write_node_id(const UA_NodeId *input, yyjson_mut_doc *document,
                                     yyjson_mut_val **output) {
    if(!output)
        return WOP_VALUE_INVALID;
    *output = NULL;
    if(!input || !document)
        return WOP_VALUE_INVALID;
    ValueWriter writer = {document, WOP_VALUE_OK};
    yyjson_mut_val *result = write_node(&writer, input);
    if(writer.status == WOP_VALUE_OK)
        *output = result;
    return writer.status;
}

static yyjson_mut_val *write_expanded(ValueWriter *writer, const UA_ExpandedNodeId *value) {
    if(value->namespaceUri.data && (!value->namespaceUri.length || value->nodeId.namespaceIndex))
        return writer_fail(writer, WOP_VALUE_INVALID);
    yyjson_mut_val *object = writer_checked(writer, yyjson_mut_obj(writer->document));
    if(!writer_field(writer, object, "node_id", write_node(writer, &value->nodeId)) ||
       !writer_field(writer, object, "namespace_uri", write_string(writer, &value->namespaceUri, 4096)) ||
       !writer_field(writer, object, "server_index", yyjson_mut_uint(writer->document, value->serverIndex)))
        return NULL;
    return object;
}

static yyjson_mut_val *write_qualified(ValueWriter *writer, const UA_QualifiedName *value) {
    yyjson_mut_val *object = writer_checked(writer, yyjson_mut_obj(writer->document));
    if(!writer_field(writer, object, "namespace", yyjson_mut_uint(writer->document, value->namespaceIndex)) ||
       !writer_field(writer, object, "name", write_string(writer, &value->name, WOP_VALUE_STRING_BYTES)))
        return NULL;
    return object;
}

static yyjson_mut_val *write_localized(ValueWriter *writer, const UA_LocalizedText *value) {
    yyjson_mut_val *object = writer_checked(writer, yyjson_mut_obj(writer->document));
    if(!writer_field(writer, object, "locale", write_string(writer, &value->locale, WOP_VALUE_STRING_BYTES)) ||
       !writer_field(writer, object, "text", write_string(writer, &value->text, WOP_VALUE_STRING_BYTES)))
        return NULL;
    return object;
}

WopValueStatus wop_value_write_references(const UA_ReferenceDescription *input, size_t count,
                                       yyjson_mut_doc *document, yyjson_mut_val **output) {
    if(!output) return WOP_VALUE_INVALID;
    *output = NULL;
    if(!document || count > 256 || (count && !input)) return WOP_VALUE_INVALID;
    ValueWriter writer = {document, WOP_VALUE_OK};
    yyjson_mut_val *array = yyjson_mut_arr(document);
    if(!array) return WOP_VALUE_LIMIT;
    for(size_t i = 0; i < count; i++) {
        const UA_ReferenceDescription *reference = &input[i];
        UA_UInt32 node_class = reference->nodeClass;
        if(node_class > 128 || (node_class && (node_class & (node_class - 1))))
            return WOP_VALUE_INVALID;
        yyjson_mut_val *item = yyjson_mut_obj(document);
        if(!item ||
           !writer_field(&writer, item, "reference_type_id",
                         write_node(&writer, &reference->referenceTypeId)) ||
           !writer_field(&writer, item, "is_forward",
                         yyjson_mut_bool(document, reference->isForward)) ||
           !writer_field(&writer, item, "node_id",
                         write_expanded(&writer, &reference->nodeId)) ||
           !writer_field(&writer, item, "browse_name",
                         write_qualified(&writer, &reference->browseName)) ||
           !writer_field(&writer, item, "display_name",
                         write_localized(&writer, &reference->displayName)) ||
           !writer_field(&writer, item, "node_class",
                         yyjson_mut_uint(document, node_class)) ||
           !writer_field(&writer, item, "type_definition",
                         write_expanded(&writer, &reference->typeDefinition)) ||
           !yyjson_mut_arr_append(array, item))
            return writer.status == WOP_VALUE_OK ? WOP_VALUE_LIMIT : writer.status;
    }
    *output = array;
    return WOP_VALUE_OK;
}

static yyjson_mut_val *write_extension(ValueWriter *writer, const UA_ExtensionObject *value) {
    const char *encoding;
    switch(value->encoding) {
    case UA_EXTENSIONOBJECT_ENCODED_NOBODY: encoding = "none"; break;
    case UA_EXTENSIONOBJECT_ENCODED_BYTESTRING: encoding = "binary"; break;
    case UA_EXTENSIONOBJECT_ENCODED_XML: encoding = "xml"; break;
    default: return writer_fail(writer, WOP_VALUE_UNSUPPORTED);
    }
    const UA_ByteString *body = &value->content.encoded.body;
    if(value->encoding == UA_EXTENSIONOBJECT_ENCODED_XML &&
       (!valid_string(body, WOP_VALUE_STRING_BYTES) || !valid_utf8(body)))
        return writer_fail(writer, body->length > WOP_VALUE_STRING_BYTES ? WOP_VALUE_LIMIT : WOP_VALUE_INVALID);
    yyjson_mut_val *object = writer_checked(writer, yyjson_mut_obj(writer->document));
    if(!writer_field(writer, object, "encoding_id", write_node(writer, &value->content.encoded.typeId)) ||
       !writer_field(writer, object, "encoding", yyjson_mut_str(writer->document, encoding)) ||
       !writer_field(writer, object, "body", value->encoding == UA_EXTENSIONOBJECT_ENCODED_NOBODY ?
                     yyjson_mut_null(writer->document) : write_bytes(writer, body)))
        return NULL;
    return object;
}

static yyjson_mut_val *write_element(ValueWriter *writer, unsigned id, const void *input) {
    yyjson_mut_doc *doc = writer->document;
    yyjson_mut_val *output;
    switch(id) {
    case 1: output = yyjson_mut_bool(doc, *(const UA_Boolean*)input); break;
    case 2: output = yyjson_mut_sint(doc, *(const UA_SByte*)input); break;
    case 3: output = yyjson_mut_uint(doc, *(const UA_Byte*)input); break;
    case 4: output = yyjson_mut_sint(doc, *(const UA_Int16*)input); break;
    case 5: output = yyjson_mut_uint(doc, *(const UA_UInt16*)input); break;
    case 6: output = yyjson_mut_sint(doc, *(const UA_Int32*)input); break;
    case 7: output = yyjson_mut_uint(doc, *(const UA_UInt32*)input); break;
    case 8: case 13: output = yyjson_mut_sint(doc, *(const UA_Int64*)input); break;
    case 9: output = yyjson_mut_uint(doc, *(const UA_UInt64*)input); break;
    case 10: case 11: {
        double number = id == 10 ? *(const UA_Float*)input : *(const UA_Double*)input;
        if(!isfinite(number)) return writer_fail(writer, WOP_VALUE_INVALID);
        output = yyjson_mut_real(doc, number);
        break;
    }
    case 12: return write_string(writer, input, WOP_VALUE_STRING_BYTES);
    case 14: {
        char text[36];
        encode_guid(input, text);
        output = yyjson_mut_strncpy(doc, text, sizeof(text));
        break;
    }
    case 15: return write_bytes(writer, input);
    case 17: return write_node(writer, input);
    case 18: return write_expanded(writer, input);
    case 19: output = yyjson_mut_uint(doc, *(const UA_StatusCode*)input); break;
    case 20: return write_qualified(writer, input);
    case 21: return write_localized(writer, input);
    case 22: return write_extension(writer, input);
    default: return writer_fail(writer, WOP_VALUE_UNSUPPORTED);
    }
    return writer_checked(writer, output);
}

static yyjson_mut_val *write_variant(ValueWriter *writer, const UA_Variant *input) {
    const ValueType *type = NULL;
    for(size_t index = 0; index < sizeof(value_types) / sizeof(value_types[0]); index++) {
        if(input->type == value_types[index].sdk) {
            type = &value_types[index];
            break;
        }
    }
    if(!type)
        return writer_fail(writer, WOP_VALUE_UNSUPPORTED);
    if(input->arrayLength > WOP_VALUE_ELEMENTS || input->arrayDimensionsSize > 8)
        return writer_fail(writer, WOP_VALUE_LIMIT);
    bool array = type->id != 0 && !UA_Variant_isScalar(input);
    if((!type->id && (input->data || input->arrayLength || input->arrayDimensionsSize)) ||
       (input->arrayLength && (uintptr_t)input->data <= (uintptr_t)UA_EMPTY_ARRAY_SENTINEL))
        return writer_fail(writer, WOP_VALUE_INVALID);
    yyjson_mut_val *dimensions = NULL;
    if(input->arrayDimensionsSize) {
        if(!array || !input->arrayLength || !input->arrayDimensions || input->arrayDimensionsSize < 2)
            return writer_fail(writer, WOP_VALUE_INVALID);
        size_t product = 1;
        dimensions = writer_checked(writer, yyjson_mut_arr(writer->document));
        for(size_t index = 0; index < input->arrayDimensionsSize; index++) {
            UA_UInt32 axis = input->arrayDimensions[index];
            if(!axis || axis > WOP_VALUE_ELEMENTS || product > input->arrayLength / axis)
                return writer_fail(writer, WOP_VALUE_INVALID);
            product *= axis;
            if(!yyjson_mut_arr_add_uint(writer->document, dimensions, axis))
                return writer_fail(writer, WOP_VALUE_LIMIT);
        }
        if(product != input->arrayLength)
            return writer_fail(writer, WOP_VALUE_INVALID);
    }
    yyjson_mut_val *value;
    if(!type->id || (array && !input->data)) {
        value = writer_checked(writer, yyjson_mut_null(writer->document));
    } else if(!array) {
        value = write_element(writer, type->id, input->data);
    } else {
        value = writer_checked(writer, yyjson_mut_arr(writer->document));
        for(size_t index = 0; index < input->arrayLength; index++) {
            yyjson_mut_val *element = write_element(writer, type->id,
                (const unsigned char*)input->data + index * type->sdk->memSize);
            if(!element || !yyjson_mut_arr_append(value, element))
                return writer_fail(writer, WOP_VALUE_LIMIT);
        }
    }
    if(!value)
        return NULL;
    size_t size = UA_calcSizeBinary(input, &UA_TYPES[UA_TYPES_VARIANT], NULL);
    if(!size || size > WOP_VALUE_WIRE_BYTES)
        return writer_fail(writer, WOP_VALUE_LIMIT);
    yyjson_mut_val *object = writer_checked(writer, yyjson_mut_obj(writer->document));
    if(!writer_field(writer, object, "type", yyjson_mut_str(writer->document, type->name)) ||
       !writer_field(writer, object, "array", yyjson_mut_bool(writer->document, array)) ||
       !writer_field(writer, object, "value", value) ||
       (dimensions && !writer_field(writer, object, "dimensions", dimensions)))
        return NULL;
    return object;
}

WopValueStatus wop_value_write_variant(const UA_Variant *input, yyjson_mut_doc *document,
                                     yyjson_mut_val **output) {
    if(!output)
        return WOP_VALUE_INVALID;
    *output = NULL;
    if(!input || !document)
        return WOP_VALUE_INVALID;
    ValueWriter writer = {document, WOP_VALUE_OK};
    yyjson_mut_val *result = write_variant(&writer, input);
    if(writer.status == WOP_VALUE_OK)
        *output = result;
    return writer.status;
}

WopValueStatus wop_value_write_data_value(const UA_DataValue *input, yyjson_mut_doc *document,
                                        yyjson_mut_val **output) {
    if(!output)
        return WOP_VALUE_INVALID;
    *output = NULL;
    if(!input || !document)
        return WOP_VALUE_INVALID;
    ValueWriter writer = {document, WOP_VALUE_OK};
    yyjson_mut_val *object = writer_checked(&writer, yyjson_mut_obj(document));
    if(!writer_field(&writer, object, "has_value", yyjson_mut_bool(document, input->hasValue)) ||
       !writer_field(&writer, object, "status", yyjson_mut_uint(document, input->hasStatus ? input->status : 0)))
        return writer.status;
    if(input->hasValue && !writer_field(&writer, object, "value", write_variant(&writer, &input->value)))
        return writer.status;
    if(input->hasSourceTimestamp) {
        writer_field(&writer, object, "source_timestamp", yyjson_mut_sint(document, input->sourceTimestamp));
        if(input->hasSourcePicoseconds)
            writer_field(&writer, object, "source_picoseconds", yyjson_mut_uint(document,
                input->sourcePicoseconds < 10000 ? input->sourcePicoseconds : 9999));
    }
    if(input->hasServerTimestamp) {
        writer_field(&writer, object, "server_timestamp", yyjson_mut_sint(document, input->serverTimestamp));
        if(input->hasServerPicoseconds)
            writer_field(&writer, object, "server_picoseconds", yyjson_mut_uint(document,
                input->serverPicoseconds < 10000 ? input->serverPicoseconds : 9999));
    }
    if(writer.status == WOP_VALUE_OK) {
        size_t size = UA_calcSizeBinary(input, &UA_TYPES[UA_TYPES_DATAVALUE], NULL);
        if(!size || size > WOP_VALUE_WIRE_BYTES)
            return WOP_VALUE_LIMIT;
        *output = object;
    }
    return writer.status;
}
