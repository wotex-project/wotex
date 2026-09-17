/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_OWNER_H
#define WOTEX_OPCUA_OWNER_H

#include "output.h"

/* WOP-X04 native process owner. It admits framed requests, keeps at most 64
 * application operations, dispatches queued work in admission order on a
 * later tick and emits exactly one success or failure per admitted request.
 * The OPC UA SDK is reached only through WopService, so deterministic traces
 * can replace network behavior without changing admission or output rules. */
#define WOP_OWNER_OPERATIONS 64U

typedef enum {
    WOP_OPERATION_READ = 0,
    WOP_OPERATION_HEALTH,
    WOP_OPERATION_WRITE,
    WOP_OPERATION_CALL,
    WOP_OPERATION_BROWSE,
    WOP_OPERATION_BROWSE_NEXT,
    WOP_OPERATION_BROWSE_RELEASE
} WopOperationKind;

typedef enum {
    WOP_SLOT_FREE = 0,
    /* Admitted and validated; no protocol request has been sent. */
    WOP_SLOT_QUEUED,
    /* A protocol request may have been sent; its reply is still owed. */
    WOP_SLOT_DISPATCHED,
    /* Answered locally; the SDK may still reference this slot until release. */
    WOP_SLOT_ABANDONED
} WopSlotState;

/* Finite failure projection. Code and phase point to static strings. */
typedef struct {
    const char *code;
    const char *phase;
    bool unknown_effect;
    bool has_status;
    uint32_t status;
} WopFailure;

typedef enum {
    WOP_COMPLETION_PENDING = 0,
    WOP_COMPLETION_SUCCESS,
    /* Request-scoped failure; the Session remains usable. */
    WOP_COMPLETION_FAILURE,
    /* Session-scoped failure; the generation ends. */
    WOP_COMPLETION_TERMINAL
} WopCompletion;

typedef struct {
    WopSlotState state;
    WopOperationKind kind;
    size_t index;
    uint64_t sequence;
    char id[65];
    int64_t deadline_ms;
    /* Nonzero request handle unique within this process. */
    uint32_t request_handle;
} WopOperation;

typedef struct {
    void *context;
    /* Validates credentials and starts Session establishment. false is terminal. */
    bool (*open)(void *context, yyjson_val *parameters, int64_t deadline_ms,
                 WopFailure *failure);
    /* Adds session_timeout_ms and namespace_array to result when complete. */
    WopCompletion (*opened)(void *context, yyjson_mut_doc *document, yyjson_mut_val *result,
                            WopFailure *failure);
    /* Validates and copies parameters without protocol I/O. */
    bool (*prepare)(void *context, const WopOperation *operation, yyjson_val *parameters,
                    WopFailure *failure);
    /* Sends prepared work with a finite SDK timeout hint. */
    bool (*dispatch)(void *context, const WopOperation *operation, uint32_t timeout_ms,
                     WopFailure *failure);
    WopCompletion (*complete)(void *context, const WopOperation *operation,
                              yyjson_mut_doc *document, yyjson_mut_val **result,
                              WopFailure *failure);
    /* Issues bounded nonblocking protocol cancellation for dispatched work. */
    void (*cancel)(void *context, const WopOperation *operation);
    /* Drops prepared storage or local delivery; never blocks. */
    void (*retire)(void *context, const WopOperation *operation);
    /* True when abandoned work no longer references its slot. */
    bool (*released)(void *context, const WopOperation *operation);
    /* Advances network work for at most slice_ms. false is terminal. */
    bool (*step)(void *context, int slice_ms, WopFailure *failure);
    /* Cooperative Session cleanup; true only when it completed. */
    bool (*close)(void *context);
} WopService;

typedef enum {
    WOP_OWNER_IDLE = 0,
    WOP_OWNER_OPENING,
    WOP_OWNER_OPEN,
    WOP_OWNER_CLOSED
} WopOwnerSession;

typedef struct {
    WopOutput output;
    WopIpcInput input;
    void *json_pool;
    WopService service;
    int64_t (*clock)(void *context);
    void *clock_context;
    WopOperation operations[WOP_OWNER_OPERATIONS];
    size_t occupied;
    uint64_t next_sequence;
    uint32_t next_handle;
    WopOwnerSession session;
    char open_id[65];
    int64_t open_deadline_ms;
    bool finished;
    int status;
} WopOwner;

bool wop_owner_init(WopOwner *owner, const WopService *service,
                    int64_t (*clock)(void *context), void *clock_context);
/* Stages the exact ready control. */
bool wop_owner_ready(WopOwner *owner, const char *revision, int64_t clock_ms);
/* Accepts arbitrary input splits and coalesced lines. */
void wop_owner_input(WopOwner *owner, const char *bytes, size_t length);
/* Owner EOF: a partial line is a protocol failure; otherwise finish cleanly. */
void wop_owner_eof(WopOwner *owner);
/* Dispatches queued work, advances the service and emits completed replies. */
void wop_owner_tick(WopOwner *owner, int slice_ms);
/* Retires all work without further replies and closes the service Session. */
void wop_owner_shutdown(WopOwner *owner);
void wop_owner_clear(WopOwner *owner);

#endif
