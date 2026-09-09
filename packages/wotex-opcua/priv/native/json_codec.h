#ifndef WOTEX_OPCUA_JSON_CODEC_H
#define WOTEX_OPCUA_JSON_CODEC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "vendor/yyjson/yyjson.h"

/* Internal, explicit-pool JSON syntax boundary. No operation or SDK admission. */
#define WOP_JSON_POOL_BYTES 2097152U
#define WOP_JSON_FRAME_BYTES 131072U

typedef enum {
    WOP_JSON_OK = 0,
    WOP_JSON_INVALID = 1,
    WOP_JSON_LIMIT = 2
} WopJsonStatus;

typedef struct {
    yyjson_alc allocator;
    yyjson_doc *document;
    size_t nodes;
} WopJson;

/* Caller owns the bounded pool until clear. Failed reads retain no document. */
WopJsonStatus wop_json_read(const char *frame, size_t length, void *pool,
                            size_t pool_bytes, WopJson *result);
void wop_json_clear(WopJson *value);
bool wop_json_int64(yyjson_val *value, int64_t *result);
bool wop_json_uint64(yyjson_val *value, uint64_t *result);
bool wop_json_double(yyjson_val *value, double *result);
bool wop_json_float(yyjson_val *value, float *result);

#endif
