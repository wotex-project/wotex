/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_VALUE_CODEC_H
#define WOTEX_OPCUA_VALUE_CODEC_H

#include "json_codec.h"
#include <open62541/types.h>

/* Internal typed-value boundary. The caller owns both parser and value pools.
 * Successful SDK values borrow the value arena until the operation retires.
 * They must never outlive its reset; no UA_clear is applied to arena members.
 * Variant storage uses UA_VARIANT_DATA_NODELETE, including borrowed dimensions.
 * These functions admit values only, never endpoints or service operations. */
#define WOP_VALUE_POOL_BYTES 2097152U
#define WOP_VALUE_WIRE_BYTES 1048576U
#define WOP_VALUE_ELEMENTS 1024U
#define WOP_VALUE_STRING_BYTES 65536U

typedef enum {
    WOP_VALUE_OK = 0,
    WOP_VALUE_INVALID = 1,
    WOP_VALUE_LIMIT = 2,
    WOP_VALUE_UNSUPPORTED = 3
} WopValueStatus;

typedef struct {
    unsigned char *bytes;
    size_t capacity;
    size_t used;
} WopValueArena;

/* The arena begins at max_align_t alignment and never falls back to malloc.
 * Reset invalidates all borrowed SDK pointers and clears the used byte range. */
bool wop_value_arena_init(WopValueArena *arena, void *bytes, size_t capacity);
void wop_value_arena_reset(WopValueArena *arena);

/* Syntax must first pass wop_json_read. The typed boundary checks exact object
 * keys and selected widths before allocating SDK storage. Failure zeros the
 * output value and rolls back only the allocations made by this call. */
WopValueStatus wop_value_read_variant(yyjson_val *input, WopValueArena *arena,
                                    UA_Variant *output);
WopValueStatus wop_value_read_data_value(yyjson_val *input, WopValueArena *arena,
                                       UA_DataValue *output);
WopValueStatus wop_value_read_node_id(yyjson_val *input, WopValueArena *arena,
                                    UA_NodeId *output);

/* These writers borrow an SDK value for the duration of the call and copy all
 * retained strings into the caller's bounded yyjson mutable-document pool.
 * Failure returns no result value; the caller discards the partial document.
 * Exact framed serialization and its 128 KiB limit belong to the JSON owner. */
WopValueStatus wop_value_write_variant(const UA_Variant *input, yyjson_mut_doc *document,
                                     yyjson_mut_val **output);
WopValueStatus wop_value_write_data_value(const UA_DataValue *input, yyjson_mut_doc *document,
                                        yyjson_mut_val **output);
WopValueStatus wop_value_write_node_id(const UA_NodeId *input, yyjson_mut_doc *document,
                                     yyjson_mut_val **output);

/* Translate a concrete public NodeId between two views of one Session's
 * NamespaceArray. The identifier storage remains borrowed from public_id.
 * Missing or duplicate URI identities fail without producing an output. */
WopValueStatus wop_value_translate_node_id(const UA_String *server_namespaces,
                                         size_t server_count,
                                         const UA_String *sdk_namespaces,
                                         size_t sdk_count,
                                         const UA_NodeId *public_id,
                                         UA_NodeId *sdk_id);

#endif
