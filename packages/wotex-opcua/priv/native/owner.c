/* SPDX-License-Identifier: Apache-2.0 */
#include "owner.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* SDK request handles above 100,000 are generated automatically. */
#define WOP_OWNER_MAXIMUM_HANDLE 99999U

static const char *const operation_names[] = {
    "read", "health", "write", "call", "browse", "browse_next", "browse_release"
};

static void secure_zero(void *bytes, size_t length) {
    volatile unsigned char *cursor = bytes;
    while (length--) *cursor++ = 0;
}

static bool text_is(yyjson_val *value, const char *literal) {
    return yyjson_is_str(value) && yyjson_get_len(value) == strlen(literal) &&
           memcmp(yyjson_get_str(value), literal, yyjson_get_len(value)) == 0;
}

static bool mutation(WopOperationKind kind) {
    return kind == WOP_OPERATION_WRITE || kind == WOP_OPERATION_CALL;
}

bool wop_owner_init(WopOwner *owner, const WopService *service,
                    int64_t (*clock)(void *context), void *clock_context) {
    if (!owner || !service || !clock) return false;
    memset(owner, 0, sizeof(*owner));
    owner->json_pool = malloc(WOP_JSON_POOL_BYTES);
    if (!owner->json_pool) return false;
    wop_output_init(&owner->output);
    owner->service = *service;
    owner->clock = clock;
    owner->clock_context = clock_context;
    owner->next_handle = 1;
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) owner->operations[i].index = i;
    return true;
}

bool wop_owner_ready(WopOwner *owner, const char *revision, int64_t clock_ms) {
    char line[256];
    int size = snprintf(line, sizeof(line),
        "{\"version\":1,\"event\":\"ready\",\"backend\":\"open62541\","
        "\"revision\":\"%s\",\"clock_ms\":%" PRId64 "}\n", revision, clock_ms);
    return owner && clock_ms >= 0 && size > 0 && (size_t)size < sizeof(line) &&
           wop_output_control(&owner->output, line, (size_t)size, false) == WOP_OUTPUT_OK;
}

/* A possibly transmitted mutation makes the whole-generation terminal
 * conservative; the BEAM owner still assigns each unfinished request its own
 * effect and never infers rollback from this field. */
static bool mutation_outstanding(const WopOwner *owner) {
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        const WopOperation *operation = &owner->operations[i];
        if ((operation->state == WOP_SLOT_DISPATCHED ||
             operation->state == WOP_SLOT_ABANDONED) && mutation(operation->kind))
            return true;
    }
    return false;
}

static void terminal(WopOwner *owner, const WopFailure *failure) {
    if (owner->finished) return;
    char line[320];
    char generation[32];
    char status[32] = "";
    if (owner->output.generation)
        (void)snprintf(generation, sizeof(generation), "%" PRIu64, owner->output.generation);
    else
        memcpy(generation, "null", 5);
    if (failure->has_status)
        (void)snprintf(status, sizeof(status), ",\"status\":%" PRIu32, failure->status);
    int size = snprintf(line, sizeof(line),
        "{\"version\":1,\"generation\":%s,\"event\":\"terminal\",\"error\":"
        "{\"code\":\"%s\",\"phase\":\"%s\",\"effect\":\"%s\"%s}}\n",
        generation, failure->code, failure->phase,
        mutation_outstanding(owner) || failure->unknown_effect ? "unknown" : "none", status);
    if (size > 0 && (size_t)size < sizeof(line))
        (void)wop_output_control(&owner->output, line, (size_t)size, true);
    owner->finished = true;
    owner->status = 70;
}

static void terminal_code(WopOwner *owner, const char *code, const char *phase) {
    WopFailure failure = {code, phase, false, false, 0};
    terminal(owner, &failure);
}

typedef enum { EMIT_OK, EMIT_LIMIT, EMIT_FAILED } EmitStatus;

static EmitStatus emit(WopOwner *owner, yyjson_mut_doc *document) {
    size_t size = 0;
    char *encoded = yyjson_mut_write(document, 0, &size);
    if (!encoded) return EMIT_FAILED;
    if (size >= WOP_JSON_FRAME_BYTES) {
        free(encoded);
        return EMIT_LIMIT;
    }
    char *line = realloc(encoded, size + 1);
    if (!line) {
        free(encoded);
        return EMIT_FAILED;
    }
    line[size] = '\n';
    WopOutputStatus status = wop_output_normal(&owner->output, line, size + 1);
    free(line);
    return status == WOP_OUTPUT_OK ? EMIT_OK : EMIT_FAILED;
}

static yyjson_mut_val *envelope(WopOwner *owner, yyjson_mut_doc *document, const char *id,
                                bool ok) {
    yyjson_mut_val *root = yyjson_mut_obj(document);
    if (!root || !yyjson_mut_obj_add_uint(document, root, "version", 1) ||
        !yyjson_mut_obj_add_uint(document, root, "generation", owner->output.generation) ||
        !yyjson_mut_obj_add_strcpy(document, root, "id", id) ||
        !yyjson_mut_obj_add_bool(document, root, "ok", ok))
        return NULL;
    yyjson_mut_doc_set_root(document, root);
    return root;
}

static void reply_failure(WopOwner *owner, const char *id, const WopFailure *failure) {
    yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *root = document ? envelope(owner, document, id, false) : NULL;
    yyjson_mut_val *error = root ? yyjson_mut_obj(document) : NULL;
    bool built = error &&
        yyjson_mut_obj_add_str(document, error, "code", failure->code) &&
        yyjson_mut_obj_add_str(document, error, "phase", failure->phase) &&
        yyjson_mut_obj_add_str(document, error, "effect",
                               failure->unknown_effect ? "unknown" : "none") &&
        (!failure->has_status ||
         yyjson_mut_obj_add_uint(document, error, "status", failure->status)) &&
        yyjson_mut_obj_add_val(document, root, "error", error);
    EmitStatus status = built ? emit(owner, document) : EMIT_FAILED;
    yyjson_mut_doc_free(document);
    if (status != EMIT_OK) terminal_code(owner, "receiver_overflow", "exchange");
}

/* The result must belong to document. An oversized success becomes one
 * response_limit failure with the operation's own effect. */
static void reply_success(WopOwner *owner, const char *id, yyjson_mut_doc *document,
                          yyjson_mut_val *result, bool unknown_effect) {
    yyjson_mut_val *root = envelope(owner, document, id, true);
    EmitStatus status = root && result && yyjson_mut_obj_add_val(document, root, "result", result)
                            ? emit(owner, document) : EMIT_FAILED;
    if (status == EMIT_LIMIT) {
        WopFailure failure = {"response_limit", "decode", unknown_effect, false, 0};
        reply_failure(owner, id, &failure);
    } else if (status != EMIT_OK) {
        terminal_code(owner, "receiver_overflow", "exchange");
    }
}

static WopOperation *outstanding(WopOwner *owner, const char *id) {
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        WopOperation *operation = &owner->operations[i];
        if ((operation->state == WOP_SLOT_QUEUED || operation->state == WOP_SLOT_DISPATCHED) &&
            strcmp(operation->id, id) == 0)
            return operation;
    }
    return NULL;
}

static void release_slot(WopOwner *owner, WopOperation *operation) {
    operation->state = WOP_SLOT_FREE;
    operation->id[0] = '\0';
    owner->occupied--;
}

/* Retire local delivery. Dispatched SDK work keeps its slot until release. */
static void retire(WopOwner *owner, WopOperation *operation, bool cancel_protocol) {
    bool dispatched = operation->state == WOP_SLOT_DISPATCHED;
    if (dispatched && cancel_protocol) owner->service.cancel(owner->service.context, operation);
    owner->service.retire(owner->service.context, operation);
    if (dispatched && !owner->service.released(owner->service.context, operation)) {
        operation->state = WOP_SLOT_ABANDONED;
        operation->id[0] = '\0';
    } else {
        release_slot(owner, operation);
    }
}

static uint32_t next_handle(WopOwner *owner) {
    for (;;) {
        uint32_t handle = owner->next_handle;
        owner->next_handle = handle == WOP_OWNER_MAXIMUM_HANDLE ? 1 : handle + 1;
        bool used = false;
        for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
            if (owner->operations[i].state != WOP_SLOT_FREE &&
                owner->operations[i].request_handle == handle)
                used = true;
        }
        if (!used) return handle;
    }
}

static int64_t deadline(const WopIpcRequest *request, int64_t now) {
    return (uint64_t)(request->deadline_ms - now) > request->timeout_ms
               ? now + (int64_t)request->timeout_ms : request->deadline_ms;
}

static void handle_open(WopOwner *owner, const WopIpcRequest *request,
                        yyjson_val *parameters, int64_t now) {
    if (owner->session != WOP_OWNER_IDLE || !wop_ipc_open(parameters)) {
        terminal_code(owner, "invalid_request", "validation");
        return;
    }
    if (now >= request->deadline_ms) {
        terminal_code(owner, "deadline_exceeded", "admission");
        return;
    }
    int64_t limit = deadline(request, now);
    WopFailure failure = {"certificate_invalid", "opening", false, false, 0};
    if (!owner->service.open(owner->service.context, parameters, limit, &failure)) {
        terminal(owner, &failure);
        return;
    }
    memcpy(owner->open_id, request->id, sizeof(owner->open_id));
    owner->open_deadline_ms = limit;
    owner->session = WOP_OWNER_OPENING;
}

static void handle_close(WopOwner *owner, const WopIpcRequest *request,
                         yyjson_val *parameters, int64_t now) {
    if (!yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 0) {
        terminal_code(owner, "invalid_request", "validation");
        return;
    }
    if (now >= request->deadline_ms) {
        terminal_code(owner, "deadline_exceeded", "admission");
        return;
    }
    /* Closing ends this generation; unfinished requests are failed by the BEAM
     * owner with their own effects instead of per-request native replies. */
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        WopOperation *operation = &owner->operations[i];
        if (operation->state == WOP_SLOT_QUEUED || operation->state == WOP_SLOT_DISPATCHED)
            retire(owner, operation, false);
    }
    bool released = true;
    if (owner->session == WOP_OWNER_OPENING || owner->session == WOP_OWNER_OPEN)
        released = owner->service.close(owner->service.context);
    owner->session = WOP_OWNER_CLOSED;
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        WopOperation *operation = &owner->operations[i];
        if (operation->state == WOP_SLOT_ABANDONED &&
            owner->service.released(owner->service.context, operation))
            release_slot(owner, operation);
    }
    if (!released) {
        terminal_code(owner, "cleanup_failed", "cleanup");
        return;
    }
    yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *result = document ? yyjson_mut_null(document) : NULL;
    if (result) reply_success(owner, request->id, document, result, false);
    else terminal_code(owner, "receiver_overflow", "exchange");
    yyjson_mut_doc_free(document);
    if (!owner->finished) {
        owner->finished = true;
        owner->status = 0;
    }
}

static bool ascii_id(yyjson_val *value) {
    if (!yyjson_is_str(value) || yyjson_get_len(value) == 0 || yyjson_get_len(value) > 64)
        return false;
    const unsigned char *bytes = (const unsigned char *)yyjson_get_str(value);
    for (size_t i = 0; i < yyjson_get_len(value); i++)
        if (bytes[i] < 0x20 || bytes[i] > 0x7e) return false;
    return true;
}

static void handle_cancel(WopOwner *owner, const WopIpcRequest *request,
                          yyjson_val *parameters, int64_t now) {
    yyjson_val *target = yyjson_obj_get(parameters, "target_id");
    if (!yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 1 || !ascii_id(target)) {
        terminal_code(owner, "invalid_request", "validation");
        return;
    }
    if (now >= request->deadline_ms) {
        WopFailure failure = {"deadline_exceeded", "admission", false, false, 0};
        reply_failure(owner, request->id, &failure);
        return;
    }
    char target_id[65] = {0};
    memcpy(target_id, yyjson_get_str(target), yyjson_get_len(target));
    WopOperation *operation = outstanding(owner, target_id);
    if (operation) {
        bool dispatched = operation->state == WOP_SLOT_DISPATCHED;
        WopFailure canceled = {"canceled", dispatched ? "exchange" : "admission",
                               dispatched && mutation(operation->kind), false, 0};
        retire(owner, operation, true);
        reply_failure(owner, target_id, &canceled);
        if (owner->finished) return;
    }
    yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *result = document ? yyjson_mut_obj(document) : NULL;
    if (result && yyjson_mut_obj_add_strcpy(document, result, "target_id", target_id) &&
        yyjson_mut_obj_add_bool(document, result, "canceled", operation != NULL))
        reply_success(owner, request->id, document, result, false);
    else
        terminal_code(owner, "receiver_overflow", "exchange");
    yyjson_mut_doc_free(document);
}

static void handle_operation(WopOwner *owner, WopOperationKind kind,
                             const WopIpcRequest *request, yyjson_val *parameters,
                             int64_t now) {
    if (owner->session != WOP_OWNER_OPEN) {
        WopFailure failure = {"invalid_request", "validation", false, false, 0};
        reply_failure(owner, request->id, &failure);
        return;
    }
    if (now >= request->deadline_ms) {
        WopFailure failure = {"deadline_exceeded", "admission", false, false, 0};
        reply_failure(owner, request->id, &failure);
        return;
    }
    if (owner->occupied == WOP_OWNER_OPERATIONS) {
        WopFailure failure = {"busy", "admission", false, false, 0};
        reply_failure(owner, request->id, &failure);
        return;
    }
    WopOperation *operation = NULL;
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS && !operation; i++)
        if (owner->operations[i].state == WOP_SLOT_FREE) operation = &owner->operations[i];
    operation->kind = kind;
    memcpy(operation->id, request->id, sizeof(operation->id));
    operation->deadline_ms = deadline(request, now);
    operation->request_handle = next_handle(owner);
    WopFailure failure = {"invalid_value", "validation", false, false, 0};
    if (!owner->service.prepare(owner->service.context, operation, parameters, &failure)) {
        operation->id[0] = '\0';
        reply_failure(owner, request->id, &failure);
        return;
    }
    operation->sequence = ++owner->next_sequence;
    operation->state = WOP_SLOT_QUEUED;
    owner->occupied++;
}

static void handle_line(WopOwner *owner, const char *line, size_t length) {
    WopJson parsed = {0};
    if (wop_json_read(line, length, owner->json_pool, WOP_JSON_POOL_BYTES, &parsed) !=
        WOP_JSON_OK) {
        terminal_code(owner, "invalid_request", "validation");
        return;
    }
    yyjson_val *root = yyjson_doc_get_root(parsed.document);
    WopIpcRequest request;
    if (yyjson_is_obj(root) && yyjson_obj_get(root, "event")) {
        WopIpcCredit credit;
        if (!wop_ipc_credit(root, &credit) ||
            wop_output_credit(&owner->output, &credit) != WOP_OUTPUT_OK)
            terminal_code(owner, "invalid_request", "validation");
    } else if (!wop_ipc_request(root, &request) || owner->output.generation == 0 ||
               request.generation != owner->output.generation ||
               outstanding(owner, request.id) ||
               (owner->session == WOP_OWNER_OPENING && strcmp(owner->open_id, request.id) == 0)) {
        terminal_code(owner, "invalid_request", "validation");
    } else {
        yyjson_val *name = yyjson_obj_get(root, "operation");
        yyjson_val *parameters = yyjson_obj_get(root, "parameters");
        int64_t now = owner->clock(owner->clock_context);
        if (now < 0) {
            terminal_code(owner, "deadline_exceeded", "admission");
        } else if (text_is(name, "open")) {
            handle_open(owner, &request, parameters, now);
        } else if (text_is(name, "close")) {
            handle_close(owner, &request, parameters, now);
        } else if (text_is(name, "cancel")) {
            handle_cancel(owner, &request, parameters, now);
        } else {
            bool admitted = false;
            for (size_t i = 0; i < sizeof(operation_names) / sizeof(operation_names[0]); i++) {
                if (text_is(name, operation_names[i])) {
                    handle_operation(owner, (WopOperationKind)i, &request, parameters, now);
                    admitted = true;
                }
            }
            if (!admitted) {
                WopFailure failure = {"unsupported_protocol", "validation", false, false, 0};
                reply_failure(owner, request.id, &failure);
            }
        }
    }
    wop_json_clear(&parsed);
    /* Parsed open requests carry credential bytes; erase the borrowed pool. */
    secure_zero(owner->json_pool, WOP_JSON_POOL_BYTES);
}

void wop_owner_input(WopOwner *owner, const char *bytes, size_t length) {
    if (!owner || (!bytes && length)) return;
    size_t offset = 0;
    while (offset < length && !owner->finished) {
        size_t consumed = 0;
        WopIpcFrameStatus framed = wop_ipc_feed(&owner->input, bytes + offset,
                                                length - offset, &consumed);
        offset += consumed;
        if (framed == WOP_IPC_MORE) break;
        if (framed != WOP_IPC_FRAME) {
            terminal_code(owner, framed == WOP_IPC_LIMIT ? "response_limit" : "invalid_request",
                          "validation");
            break;
        }
        handle_line(owner, owner->input.bytes, owner->input.used);
        secure_zero(owner->input.bytes, owner->input.used);
        owner->input.used = 0;
    }
}

void wop_owner_eof(WopOwner *owner) {
    if (!owner || owner->finished) return;
    if (owner->input.used) {
        terminal_code(owner, "invalid_request", "validation");
        return;
    }
    owner->finished = true;
    owner->status = 0;
}

static WopOperation *oldest_queued(WopOwner *owner) {
    WopOperation *selected = NULL;
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        WopOperation *operation = &owner->operations[i];
        if (operation->state == WOP_SLOT_QUEUED &&
            (!selected || operation->sequence < selected->sequence))
            selected = operation;
    }
    return selected;
}

static void open_tick(WopOwner *owner, int slice_ms, int64_t now) {
    if (now >= owner->open_deadline_ms) {
        terminal_code(owner, "deadline_exceeded", "opening");
        return;
    }
    WopFailure failure = {"invalid_response", "opening", false, false, 0};
    if (!owner->service.step(owner->service.context, slice_ms, &failure)) {
        WopFailure opening = {"invalid_response", "opening", false, false, 0};
        terminal(owner, &opening);
        return;
    }
    yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *result = document ? yyjson_mut_obj(document) : NULL;
    if (!result) {
        yyjson_mut_doc_free(document);
        terminal_code(owner, "invalid_response", "opening");
        return;
    }
    WopCompletion completion = owner->service.opened(owner->service.context, document, result,
                                                     &failure);
    if (completion == WOP_COMPLETION_SUCCESS) {
        if (yyjson_mut_obj_add_uint(document, result, "session_generation",
                                    owner->output.generation)) {
            owner->session = WOP_OWNER_OPEN;
            reply_success(owner, owner->open_id, document, result, false);
        } else {
            terminal_code(owner, "invalid_response", "opening");
        }
    } else if (completion != WOP_COMPLETION_PENDING) {
        terminal(owner, &failure);
    }
    yyjson_mut_doc_free(document);
}

static void dispatch_queued(WopOwner *owner, int64_t now) {
    WopOperation *operation;
    while (!owner->finished && (operation = oldest_queued(owner))) {
        if (now >= operation->deadline_ms) {
            WopFailure failure = {"deadline_exceeded", "admission", false, false, 0};
            char id[65];
            memcpy(id, operation->id, sizeof(id));
            retire(owner, operation, false);
            reply_failure(owner, id, &failure);
            continue;
        }
        uint64_t remaining = (uint64_t)(operation->deadline_ms - now);
        WopFailure failure = {"connection_failed", "admission", mutation(operation->kind),
                              false, 0};
        if (owner->service.dispatch(owner->service.context, operation,
                                    remaining > UINT32_MAX ? UINT32_MAX : (uint32_t)remaining,
                                    &failure)) {
            operation->state = WOP_SLOT_DISPATCHED;
        } else {
            char id[65];
            memcpy(id, operation->id, sizeof(id));
            retire(owner, operation, false);
            reply_failure(owner, id, &failure);
        }
    }
}

static void complete_dispatched(WopOwner *owner, int64_t now) {
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS && !owner->finished; i++) {
        WopOperation *operation = &owner->operations[i];
        if (operation->state == WOP_SLOT_ABANDONED) {
            if (owner->service.released(owner->service.context, operation))
                release_slot(owner, operation);
            continue;
        }
        if (operation->state != WOP_SLOT_DISPATCHED) continue;
        yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
        if (!document) {
            terminal_code(owner, "receiver_overflow", "exchange");
            return;
        }
        yyjson_mut_val *result = NULL;
        WopFailure failure = {"invalid_response", "decode", mutation(operation->kind), false, 0};
        WopCompletion completion = owner->service.complete(owner->service.context, operation,
                                                           document, &result, &failure);
        char id[65];
        memcpy(id, operation->id, sizeof(id));
        if (completion == WOP_COMPLETION_SUCCESS) {
            reply_success(owner, id, document, result, mutation(operation->kind));
            retire(owner, operation, false);
        } else if (completion == WOP_COMPLETION_FAILURE) {
            reply_failure(owner, id, &failure);
            retire(owner, operation, false);
        } else if (completion == WOP_COMPLETION_TERMINAL) {
            terminal(owner, &failure);
        } else if (now >= operation->deadline_ms) {
            WopFailure expired = {"deadline_exceeded", "exchange", mutation(operation->kind),
                                  false, 0};
            retire(owner, operation, true);
            reply_failure(owner, id, &expired);
        }
        yyjson_mut_doc_free(document);
    }
}

void wop_owner_tick(WopOwner *owner, int slice_ms) {
    if (!owner || owner->finished) return;
    int64_t now = owner->clock(owner->clock_context);
    if (now < 0) {
        terminal_code(owner, "deadline_exceeded", "exchange");
        return;
    }
    if (owner->session == WOP_OWNER_OPENING) {
        open_tick(owner, slice_ms, now);
        return;
    }
    if (owner->session != WOP_OWNER_OPEN) return;
    dispatch_queued(owner, now);
    if (owner->finished) return;
    WopFailure failure = {"connection_failed", "exchange", false, false, 0};
    if (!owner->service.step(owner->service.context, slice_ms, &failure)) {
        terminal(owner, &failure);
        return;
    }
    now = owner->clock(owner->clock_context);
    if (now < 0) {
        terminal_code(owner, "deadline_exceeded", "exchange");
        return;
    }
    complete_dispatched(owner, now);
}

void wop_owner_shutdown(WopOwner *owner) {
    if (!owner) return;
    for (size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        WopOperation *operation = &owner->operations[i];
        if (operation->state == WOP_SLOT_QUEUED || operation->state == WOP_SLOT_DISPATCHED)
            retire(owner, operation, false);
    }
    if (owner->session == WOP_OWNER_OPENING || owner->session == WOP_OWNER_OPEN)
        (void)owner->service.close(owner->service.context);
    owner->session = WOP_OWNER_CLOSED;
}

void wop_owner_clear(WopOwner *owner) {
    if (!owner) return;
    wop_output_clear(&owner->output);
    secure_zero(owner->input.bytes, sizeof(owner->input.bytes));
    if (owner->json_pool) {
        secure_zero(owner->json_pool, WOP_JSON_POOL_BYTES);
        free(owner->json_pool);
    }
    owner->json_pool = NULL;
}
