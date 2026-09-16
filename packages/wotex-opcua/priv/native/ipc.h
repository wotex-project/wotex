#ifndef WOTEX_OPCUA_IPC_H
#define WOTEX_OPCUA_IPC_H

#include "json_codec.h"

/* One bounded input line. A completed line is consumed before more input. */
typedef struct {
    char bytes[WOP_JSON_FRAME_BYTES];
    size_t used;
} WopIpcInput;

typedef enum {
    WOP_IPC_MORE,
    WOP_IPC_FRAME,
    WOP_IPC_INVALID,
    WOP_IPC_LIMIT
} WopIpcFrameStatus;

/* consumed allows a caller to feed coalesced lines one at a time. */
WopIpcFrameStatus wop_ipc_feed(WopIpcInput *input, const char *bytes, size_t length,
                               size_t *consumed);

typedef struct {
    uint64_t generation;
    int64_t deadline_ms;
    uint64_t timeout_ms;
    bool open;
} WopIpcRequest;

/* Outer request shape only. Parameter admission belongs to each service. */
bool wop_ipc_request(yyjson_val *root, WopIpcRequest *request);

/* Closed open-parameter shape, before any certificate or SDK admission. */
bool wop_ipc_open(yyjson_val *parameters);

#endif
