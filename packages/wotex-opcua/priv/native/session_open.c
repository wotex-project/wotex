/* SPDX-License-Identifier: Apache-2.0 */
#include "session_open.h"
#include "value_codec.h"

#include <open62541/client_highlevel_async.h>
#include <math.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void quiet(void *context, UA_LogLevel level, UA_LogCategory category,
                  const char *format, va_list args) {
    (void)context; (void)level; (void)category; (void)format; (void)args;
}

static void logger_clear(UA_Logger *logger) { UA_free(logger); }

static int64_t monotonic_ms(void) {
    struct timespec now;
    if(clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 ||
       (uint64_t)now.tv_sec > (uint64_t)INT64_MAX / 1000U) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static void fail_with(WopFailure *failure, const char *code, const char *phase,
                      bool unknown_effect) {
    failure->code = code;
    failure->phase = phase;
    failure->unknown_effect = unknown_effect;
    failure->has_status = false;
    failure->status = 0;
}

static void fail_status(WopFailure *failure, const char *code, const char *phase,
                        bool unknown_effect, UA_StatusCode status) {
    fail_with(failure, code, phase, unknown_effect);
    failure->has_status = true;
    failure->status = status;
}

static bool valid_utf8(const UA_String *value) {
    if(!value->data || !value->length || value->length > 4096) return false;
    for(size_t i = 0; i < value->length;) {
        unsigned char c = value->data[i++];
        if(c == 0 || c < 0x20 || c == 0x7f) return false;
        if(c < 0x80) continue;
        size_t more;
        uint32_t code;
        if(c >= 0xc2 && c <= 0xdf) { more = 1; code = c & 0x1f; }
        else if(c >= 0xe0 && c <= 0xef) { more = 2; code = c & 0x0f; }
        else if(c >= 0xf0 && c <= 0xf4) { more = 3; code = c & 0x07; }
        else return false;
        if(more > value->length - i) return false;
        for(size_t j = 0; j < more; j++) {
            unsigned char next = value->data[i++];
            if((next & 0xc0) != 0x80) return false;
            code = (code << 6) | (next & 0x3f);
        }
        if((more == 1 && code < 0x80) || (more == 2 && code < 0x800) ||
           (more == 3 && code < 0x10000) || code > 0x10ffff ||
           (code >= 0xd800 && code <= 0xdfff)) return false;
    }
    return true;
}

static void receive_namespaces(UA_Client *client, void *userdata, UA_UInt32 request_id,
                               UA_StatusCode status, UA_DataValue *value) {
    (void)client; (void)request_id;
    WopSession *session = userdata;
    session->namespace_received = true;
    if(status != UA_STATUSCODE_GOOD || !value || !value->hasValue ||
       !UA_Variant_hasArrayType(&value->value, &UA_TYPES[UA_TYPES_STRING]) ||
       value->value.arrayLength < 2 || value->value.arrayLength > 1024 ||
       !value->value.data || value->value.data == UA_EMPTY_ARRAY_SENTINEL) return;
    UA_String *uris = value->value.data;
    static const char standard[] = "http://opcfoundation.org/UA/";
    if(uris[0].length != sizeof(standard) - 1 ||
       memcmp(uris[0].data, standard, sizeof(standard) - 1) != 0) return;
    size_t total = 0;
    for(size_t i = 0; i < value->value.arrayLength; i++) {
        if(!valid_utf8(&uris[i])) return;
        total += uris[i].length;
        if(total > 131072) return;
        for(size_t j = 0; j < i; j++)
            if(UA_String_equal(&uris[i], &uris[j])) return;
    }
    if(UA_Array_copy(uris, value->value.arrayLength,
                     (void **)&session->namespace_array,
                     &UA_TYPES[UA_TYPES_STRING]) != UA_STATUSCODE_GOOD) return;
    session->namespace_count = value->value.arrayLength;
    session->namespace_valid = true;
}

static bool session_open(void *context, yyjson_val *parameters, int64_t deadline_ms,
                         WopFailure *failure) {
    WopSession *session = context;
    time_t now = time(NULL);
    uint64_t requested = 0;
    if(now == (time_t)-1 ||
       !wop_json_uint64(yyjson_obj_get(parameters, "session_timeout_ms"), &requested) ||
       !wop_security_read(parameters, now, &session->security)) {
        fail_with(failure, monotonic_ms() >= deadline_ms ? "deadline_exceeded" :
                  "certificate_invalid", "opening", false);
        return false;
    }
    session->requested_timeout_ms = requested;
    UA_ClientConfig config = {0};
    config.logging = UA_calloc(1, sizeof(*config.logging));
    if(!config.logging) goto fail;
    config.logging->log = quiet;
    config.logging->clear = logger_clear;
    if(!wop_session_configure(&config, parameters, &session->security)) goto fail;
    config.timeout = 1000;
    session->client = UA_Client_newWithConfig(&config);
    if(!session->client) goto fail;
    memset(&config, 0, sizeof(config));
    int64_t current = monotonic_ms();
    if(current < 0 || current >= deadline_ms) goto fail;
    if(UA_Client_connectAsync(session->client,
        yyjson_get_str(yyjson_obj_get(parameters, "endpoint"))) != UA_STATUSCODE_GOOD)
        goto fail;
    return true;
fail:
    UA_ClientConfig_clear(&config);
    wop_session_close(session);
    fail_with(failure, monotonic_ms() >= deadline_ms ? "deadline_exceeded" :
              "certificate_invalid", "opening", false);
    return false;
}

/* The SDK builds its client-local namespace table and binary mapping from its
 * own NamespaceArray read. Service admission waits until every server URI is
 * present there, so no request is encoded before that mapping exists. */
static bool sdk_namespaces_ready(WopSession *session) {
    for(size_t i = 0; i < session->namespace_count; i++) {
        UA_UInt16 local = 0;
        if(UA_Client_getNamespaceIndex(session->client, session->namespace_array[i],
                                       &local) != UA_STATUSCODE_GOOD)
            return false;
    }
    return true;
}

static bool session_step(void *context, int slice_ms, WopFailure *failure) {
    WopSession *session = context;
    if(!session->client) return true;
    if(session->browse_orphaned) {
        fail_with(failure, "cleanup_failed", "cleanup", false);
        return false;
    }
    UA_StatusCode status = UA_Client_run_iterate(session->client,
                                                 slice_ms < 0 ? 0 : (UA_UInt32)slice_ms);
    UA_StatusCode connection = UA_STATUSCODE_GOOD;
    UA_SessionState state = UA_SESSIONSTATE_CLOSED;
    UA_Client_getState(session->client, NULL, &state, &connection);
    if(status != UA_STATUSCODE_GOOD || connection != UA_STATUSCODE_GOOD ||
       (session->namespace_requested && state != UA_SESSIONSTATE_ACTIVATED)) {
        fail_with(failure, "connection_failed", "exchange", false);
        return false;
    }
    if(session->browse_orphaned) {
        fail_with(failure, "cleanup_failed", "cleanup", false);
        return false;
    }
    if(state != UA_SESSIONSTATE_ACTIVATED || session->ready) return true;
    if(!session->namespace_requested) {
        session->namespace_requested = true;
        if(UA_Client_readValueAttribute_async(session->client,
               UA_NS0ID(SERVER_NAMESPACEARRAY), receive_namespaces, session, NULL) !=
           UA_STATUSCODE_GOOD) {
            fail_with(failure, "invalid_response", "opening", false);
            return false;
        }
        return true;
    }
    if(!session->namespace_received) return true;
    if(!session->namespace_valid) {
        fail_with(failure, "invalid_response", "opening", false);
        return false;
    }
    if(!sdk_namespaces_ready(session)) return true;
    UA_Double value = NAN;
    if(UA_Client_getConnectionAttribute_scalar(session->client,
          UA_QUALIFIEDNAME(0, "revisedSessionTimeout"),
          &UA_TYPES[UA_TYPES_DOUBLE], &value) != UA_STATUSCODE_GOOD ||
       !isfinite(value) || value <= 0 || value > (UA_Double)session->requested_timeout_ms) {
        fail_with(failure, "invalid_response", "opening", false);
        return false;
    }
    session->revised_timeout_ms = value;
    session->ready = true;
    return true;
}

static WopCompletion session_opened(void *context, yyjson_mut_doc *document,
                                    yyjson_mut_val *result, WopFailure *failure) {
    WopSession *session = context;
    if(!session->ready) return WOP_COMPLETION_PENDING;
    yyjson_mut_val *namespaces = yyjson_mut_arr(document);
    bool valid = namespaces &&
        yyjson_mut_obj_add_real(document, result, "session_timeout_ms",
                                session->revised_timeout_ms) &&
        yyjson_mut_obj_add_val(document, result, "namespace_array", namespaces);
    for(size_t i = 0; valid && i < session->namespace_count; i++)
        valid = yyjson_mut_arr_add_strncpy(document, namespaces,
            (const char *)session->namespace_array[i].data,
            session->namespace_array[i].length);
    if(valid) return WOP_COMPLETION_SUCCESS;
    fail_with(failure, "invalid_response", "opening", false);
    return WOP_COMPLETION_TERMINAL;
}

static bool translate_node(WopSession *session, yyjson_val *node_input,
                           WopValueArena *arena, UA_NodeId *sdk_id) {
    UA_NodeId public_id = UA_NODEID_NULL;
    if(wop_value_read_node_id(node_input, arena, &public_id) != WOP_VALUE_OK ||
       public_id.namespaceIndex >= session->namespace_count) return false;
    UA_String identity = session->namespace_array[public_id.namespaceIndex];
    UA_UInt16 local_index = 0;
    UA_String reversed = UA_STRING_NULL;
    bool mapped = UA_Client_getNamespaceIndex(session->client, identity, &local_index) == UA_STATUSCODE_GOOD &&
                  UA_Client_getNamespaceUri(session->client, local_index, &reversed) == UA_STATUSCODE_GOOD &&
                  UA_String_equal(&identity, &reversed);
    UA_String_clear(&reversed);
    if(!mapped) return false;
    *sdk_id = public_id;
    sdk_id->namespaceIndex = local_index;
    return true;
}

static bool supported_value_type(const UA_DataType *type) {
    if(!type) return true;
    static const unsigned admitted[] = {
        UA_TYPES_BOOLEAN, UA_TYPES_SBYTE, UA_TYPES_BYTE, UA_TYPES_INT16,
        UA_TYPES_UINT16, UA_TYPES_INT32, UA_TYPES_UINT32, UA_TYPES_INT64,
        UA_TYPES_UINT64, UA_TYPES_FLOAT, UA_TYPES_DOUBLE, UA_TYPES_STRING,
        UA_TYPES_DATETIME, UA_TYPES_GUID, UA_TYPES_BYTESTRING,
        UA_TYPES_STATUSCODE, UA_TYPES_LOCALIZEDTEXT
    };
    for(size_t i = 0; i < sizeof(admitted) / sizeof(admitted[0]); i++)
        if(type == &UA_TYPES[admitted[i]]) return true;
    return false;
}

/* Connection-scoped service results end the whole generation. */
static bool transport_status(UA_StatusCode status) {
    return status == UA_STATUSCODE_BADSHUTDOWN || status == UA_STATUSCODE_BADCONNECTIONCLOSED ||
           status == UA_STATUSCODE_BADSERVERNOTCONNECTED ||
           status == UA_STATUSCODE_BADSECURECHANNELCLOSED ||
           status == UA_STATUSCODE_BADSECURECHANNELIDINVALID ||
           status == UA_STATUSCODE_BADSESSIONCLOSED || status == UA_STATUSCODE_BADSESSIONIDINVALID ||
           status == UA_STATUSCODE_BADCOMMUNICATIONERROR || status == UA_STATUSCODE_BADDISCONNECT;
}

static WopSessionOperation *slot(WopSession *session, const WopOperation *operation) {
    return operation->index < WOP_OWNER_OPERATIONS ? &session->operations[operation->index] : NULL;
}

/* Returns false when the callback belongs to a retired or foreign request. */
static bool accept_response(WopSessionOperation *operation, UA_UInt32 request_id,
                            const UA_ResponseHeader *header) {
    if(!operation->pending || request_id != operation->request_id) return false;
    operation->pending = false;
    if(operation->abandoned) return false;
    operation->delivered = true;
    operation->status = UA_STATUSCODE_BADUNEXPECTEDERROR;
    if(!header) return false;
    UA_StatusCode result = header->serviceResult;
    if(result == UA_STATUSCODE_GOOD) return true;
    operation->status = result;
    if(transport_status(result)) operation->transport_error = true;
    else if(result == UA_STATUSCODE_BADTIMEOUT) operation->timed_out = true;
    else operation->remote_error = true;
    return false;
}

static void receive_read(UA_Client *client, void *userdata, UA_UInt32 request_id,
                         UA_ReadResponse *response) {
    (void)client;
    WopSessionOperation *operation = userdata;
    if(!accept_response(operation, request_id, response ? &response->responseHeader : NULL))
        return;
    if(response->resultsSize != 1 || !response->results) return;
    const UA_DataValue *value = &response->results[0];
    operation->status = value->hasStatus ? value->status : UA_STATUSCODE_GOOD;
    if(UA_DataValue_copy(value, &operation->read_value) != UA_STATUSCODE_GOOD) {
        operation->status = UA_STATUSCODE_BADOUTOFMEMORY;
        return;
    }
    operation->valid = true;
}

static void receive_write(UA_Client *client, void *userdata, UA_UInt32 request_id,
                          UA_WriteResponse *response) {
    (void)client;
    WopSessionOperation *operation = userdata;
    if(!accept_response(operation, request_id, response ? &response->responseHeader : NULL))
        return;
    if(response->resultsSize != 1 || !response->results) return;
    operation->status = response->results[0];
    operation->valid = true;
}

static void receive_call(UA_Client *client, void *userdata, UA_UInt32 request_id,
                         void *raw_response) {
    (void)client;
    WopSessionOperation *operation = userdata;
    UA_CallResponse *response = raw_response;
    if(!accept_response(operation, request_id, response ? &response->responseHeader : NULL))
        return;
    if(response->resultsSize != 1 || !response->results) return;
    const UA_CallMethodResult *result = &response->results[0];
    if(result->inputArgumentResultsSize > 64 || result->outputArgumentsSize > 64 ||
       (result->inputArgumentResultsSize && !result->inputArgumentResults) ||
       (result->outputArgumentsSize && !result->outputArguments)) return;
    operation->status = result->statusCode;
    if(UA_CallMethodResult_copy(result, &operation->call_result) != UA_STATUSCODE_GOOD) {
        operation->status = UA_STATUSCODE_BADOUTOFMEMORY;
        return;
    }
    operation->valid = true;
}

static bool chain_operation(const WopSessionOperation *operation) {
    return operation->expose || operation->kind == WOP_OPERATION_BROWSE_NEXT ||
           operation->kind == WOP_OPERATION_BROWSE_RELEASE;
}

static void capture_page(WopSessionOperation *operation, const UA_BrowseResult *result) {
    WopSession *session = operation->session;
    operation->status = result->statusCode;
    size_t size = UA_calcSizeBinary(result, &UA_TYPES[UA_TYPES_BROWSERESULT], NULL);
    UA_UInt32 pages = chain_operation(operation) ? session->browse_pages : 0;
    UA_UInt32 references = chain_operation(operation) ? session->browse_references : 0;
    size_t bytes = chain_operation(operation) ? session->browse_bytes : 0;
    if(result->referencesSize > operation->page_size ||
       result->continuationPoint.length > 4096 || size > 1048576 || pages >= 64 ||
       result->referencesSize > 4096 - references || size > 1048576 - bytes) {
        operation->limit = true;
        return;
    }
    if(size == 0 || UA_BrowseResult_copy(result, &operation->browse_result) != UA_STATUSCODE_GOOD)
        return;
    if(chain_operation(operation)) {
        session->browse_pages++;
        session->browse_references += (UA_UInt32)result->referencesSize;
        session->browse_bytes += size;
    }
    operation->valid = true;
}

static void receive_browse(UA_Client *client, void *userdata, UA_UInt32 request_id,
                           UA_BrowseResponse *response) {
    (void)client;
    WopSessionOperation *operation = userdata;
    if(!accept_response(operation, request_id, response ? &response->responseHeader : NULL))
        return;
    if(response->resultsSize != 1 || !response->results || response->diagnosticInfosSize != 0)
        return;
    capture_page(operation, &response->results[0]);
}

static void receive_browse_next(UA_Client *client, void *userdata,
                                UA_UInt32 request_id, UA_BrowseNextResponse *response) {
    (void)client;
    WopSessionOperation *operation = userdata;
    if(!accept_response(operation, request_id, response ? &response->responseHeader : NULL))
        return;
    if(operation->releasing) {
        operation->release_valid = response->resultsSize == 1 &&
            response->results && response->diagnosticInfosSize == 0 &&
            response->results[0].statusCode == UA_STATUSCODE_GOOD &&
            response->results[0].referencesSize == 0 &&
            response->results[0].continuationPoint.length == 0;
        return;
    }
    if(response->resultsSize != 1 || !response->results || response->diagnosticInfosSize != 0)
        return;
    capture_page(operation, &response->results[0]);
}

static bool prepare_read(WopSession *session, WopSessionOperation *operation,
                         yyjson_val *parameters) {
    if(!yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 2 ||
       !yyjson_is_null(yyjson_obj_get(parameters, "index_range"))) return false;
    _Alignas(max_align_t) unsigned char storage[8192];
    WopValueArena arena;
    UA_NodeId sdk_id = UA_NODEID_NULL;
    bool valid = wop_value_arena_init(&arena, storage, sizeof(storage)) &&
                 translate_node(session, yyjson_obj_get(parameters, "node_id"), &arena, &sdk_id) &&
                 UA_NodeId_copy(&sdk_id, &operation->read_node) == UA_STATUSCODE_GOOD;
    wop_value_arena_reset(&arena);
    return valid;
}

static bool prepare_write(WopSession *session, WopSessionOperation *operation,
                          yyjson_val *parameters) {
    if(!yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 3 ||
       !yyjson_is_null(yyjson_obj_get(parameters, "index_range"))) return false;
    void *storage = malloc(WOP_VALUE_POOL_BYTES);
    if(!storage) return false;
    WopValueArena arena;
    UA_NodeId sdk_id = UA_NODEID_NULL;
    UA_Variant value = {0};
    bool valid = wop_value_arena_init(&arena, storage, WOP_VALUE_POOL_BYTES) &&
        translate_node(session, yyjson_obj_get(parameters, "node_id"), &arena, &sdk_id) &&
        wop_value_read_variant(yyjson_obj_get(parameters, "value"), &arena, &value) == WOP_VALUE_OK &&
        supported_value_type(value.type);
    if(valid) {
        valid = UA_NodeId_copy(&sdk_id, &operation->write_value.nodeId) == UA_STATUSCODE_GOOD &&
            UA_Variant_copy(&value, &operation->write_value.value.value) == UA_STATUSCODE_GOOD;
        operation->write_value.attributeId = UA_ATTRIBUTEID_VALUE;
        operation->write_value.value.hasValue = true;
    }
    wop_value_arena_reset(&arena);
    free(storage);
    return valid;
}

static bool prepare_call(WopSession *session, WopSessionOperation *operation,
                         yyjson_val *parameters) {
    if(!yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 3) return false;
    yyjson_val *arguments = yyjson_obj_get(parameters, "arguments");
    if(!yyjson_is_arr(arguments) || yyjson_arr_size(arguments) > 64) return false;
    void *storage = malloc(WOP_VALUE_POOL_BYTES);
    if(!storage) return false;
    WopValueArena arena;
    UA_NodeId object_id = UA_NODEID_NULL, method_id = UA_NODEID_NULL;
    bool valid = wop_value_arena_init(&arena, storage, WOP_VALUE_POOL_BYTES) &&
        translate_node(session, yyjson_obj_get(parameters, "object_id"), &arena, &object_id) &&
        translate_node(session, yyjson_obj_get(parameters, "method_id"), &arena, &method_id);
    if(valid) {
        valid = UA_NodeId_copy(&object_id, &operation->call_method.objectId) == UA_STATUSCODE_GOOD &&
                UA_NodeId_copy(&method_id, &operation->call_method.methodId) == UA_STATUSCODE_GOOD;
        size_t count = yyjson_arr_size(arguments);
        if(valid && count) {
            operation->call_method.inputArguments = UA_Array_new(count, &UA_TYPES[UA_TYPES_VARIANT]);
            valid = operation->call_method.inputArguments != NULL;
            if(valid) operation->call_method.inputArgumentsSize = count;
        }
        for(size_t i = 0; valid && i < count; i++) {
            UA_Variant input = {0};
            valid = wop_value_read_variant(yyjson_arr_get(arguments, i), &arena, &input) == WOP_VALUE_OK &&
                supported_value_type(input.type) &&
                UA_Variant_copy(&input, &operation->call_method.inputArguments[i]) == UA_STATUSCODE_GOOD;
        }
    }
    wop_value_arena_reset(&arena);
    free(storage);
    return valid;
}

static bool prepare_browse(WopSession *session, WopSessionOperation *operation,
                           yyjson_val *parameters, WopFailure *failure) {
    if(!yyjson_is_obj(parameters) ||
       (yyjson_obj_size(parameters) != 6 && yyjson_obj_size(parameters) != 7))
        return false;
    yyjson_val *expose = yyjson_obj_get(parameters, "allow_continuation");
    if((yyjson_obj_size(parameters) == 7 && (!yyjson_is_bool(expose) ||
                                            !yyjson_get_bool(expose))) ||
       (yyjson_obj_size(parameters) == 6 && expose)) return false;
    yyjson_val *direction = yyjson_obj_get(parameters, "direction");
    yyjson_val *subtypes = yyjson_obj_get(parameters, "include_subtypes");
    uint64_t mask = 0, page_size = 0;
    if(!yyjson_is_str(direction) || !yyjson_is_bool(subtypes) ||
       !wop_json_uint64(yyjson_obj_get(parameters, "node_class_mask"), &mask) ||
       !wop_json_uint64(yyjson_obj_get(parameters, "page_size"), &page_size) ||
       mask > 255 || page_size < 1 || page_size > 256) return false;
    UA_BrowseDirection sdk_direction;
    const char *name = yyjson_get_str(direction);
    if(strcmp(name, "forward") == 0) sdk_direction = UA_BROWSEDIRECTION_FORWARD;
    else if(strcmp(name, "inverse") == 0) sdk_direction = UA_BROWSEDIRECTION_INVERSE;
    else if(strcmp(name, "both") == 0) sdk_direction = UA_BROWSEDIRECTION_BOTH;
    else return false;
    if(expose && (session->browse_active || session->browse_chain_busy)) {
        fail_with(failure, "busy", "admission", false);
        return false;
    }

    _Alignas(max_align_t) unsigned char storage[16384];
    WopValueArena arena;
    UA_NodeId node = UA_NODEID_NULL, reference_type = UA_NODEID_NULL;
    if(!wop_value_arena_init(&arena, storage, sizeof(storage)) ||
       !translate_node(session, yyjson_obj_get(parameters, "node_id"), &arena, &node) ||
       !translate_node(session, yyjson_obj_get(parameters, "reference_type_id"),
                       &arena, &reference_type)) return false;
    UA_BrowseDescription *description = &operation->browse_description;
    if(UA_NodeId_copy(&node, &description->nodeId) != UA_STATUSCODE_GOOD ||
       UA_NodeId_copy(&reference_type, &description->referenceTypeId) != UA_STATUSCODE_GOOD) {
        UA_BrowseDescription_clear(description);
        return false;
    }
    description->browseDirection = sdk_direction;
    description->includeSubtypes = yyjson_get_bool(subtypes);
    description->nodeClassMask = (UA_UInt32)mask;
    description->resultMask = UA_BROWSERESULTMASK_ALL;
    operation->page_size = (UA_UInt32)page_size;
    operation->expose = expose != NULL;
    if(operation->expose) {
        session->browse_chain_busy = true;
        session->browse_page_size = operation->page_size;
        session->browse_pages = 0;
        session->browse_references = 0;
        session->browse_bytes = 0;
    }
    return true;
}

bool wop_session_browse_token(const WopSession *session, char token[32]) {
    if(!session || !session->browse_active || !token) return false;
    int length = snprintf(token, 32, "c%" PRIu64, (uint64_t)session->browse_serial);
    return length > 1 && length < 32;
}

bool wop_session_browse_capture(WopSession *session, WopSessionOperation *operation) {
    if(!session || !operation || !operation->valid) return false;
    UA_ByteString_clear(&session->browse_point);
    session->browse_active = false;
    if(!operation->browse_result.continuationPoint.length) return true;
    if(!chain_operation(operation) || session->browse_serial == UINT64_MAX ||
       session->browse_pages >= 64 || session->browse_references >= 4096 ||
       session->browse_bytes >= 1048576 ||
       operation->browse_result.continuationPoint.length > 4096 ||
       UA_ByteString_copy(&operation->browse_result.continuationPoint,
                          &session->browse_point) != UA_STATUSCODE_GOOD) return false;
    session->browse_serial++;
    session->browse_active = true;
    return true;
}

bool wop_session_browse_admit(WopSession *session, WopSessionOperation *operation,
                              yyjson_val *parameters, bool release) {
    if(!session || !operation || !session->browse_active || session->browse_chain_busy ||
       !yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 1) return false;
    yyjson_val *token_value = yyjson_obj_get(parameters, "continuation");
    char expected[32] = {0};
    if(!yyjson_is_str(token_value) || !wop_session_browse_token(session, expected) ||
       yyjson_get_len(token_value) != strlen(expected) ||
       memcmp(yyjson_get_str(token_value), expected, strlen(expected)) != 0)
        return false;
    operation->browse_point = session->browse_point;
    session->browse_point = UA_BYTESTRING_NULL;
    session->browse_active = false;
    session->browse_chain_busy = true;
    operation->kind = release ? WOP_OPERATION_BROWSE_RELEASE : WOP_OPERATION_BROWSE_NEXT;
    operation->releasing = release;
    operation->page_size = release ? 0 : session->browse_page_size;
    return true;
}

static void clear_operation(WopSessionOperation *operation) {
    WopSession *session = operation->session;
    UA_NodeId_clear(&operation->read_node);
    UA_DataValue_clear(&operation->read_value);
    UA_WriteValue_clear(&operation->write_value);
    UA_CallMethodRequest_clear(&operation->call_method);
    UA_CallMethodResult_clear(&operation->call_result);
    UA_BrowseDescription_clear(&operation->browse_description);
    UA_BrowseResult_clear(&operation->browse_result);
    UA_ByteString_clear(&operation->browse_point);
    UA_UInt32 request_id = operation->request_id;
    bool pending = operation->pending;
    bool abandoned = operation->abandoned;
    memset(operation, 0, sizeof(*operation));
    operation->session = session;
    operation->request_id = request_id;
    operation->pending = pending;
    operation->abandoned = abandoned;
}

static bool session_prepare(void *context, const WopOperation *owner_operation,
                            yyjson_val *parameters, WopFailure *failure) {
    WopSession *session = context;
    WopSessionOperation *operation = slot(session, owner_operation);
    if(!operation || !session->ready || operation->pending) {
        fail_with(failure, "invalid_request", "validation", false);
        return false;
    }
    clear_operation(operation);
    operation->abandoned = false;
    operation->kind = owner_operation->kind;
    bool prepared = false;
    switch(owner_operation->kind) {
    case WOP_OPERATION_READ:
    case WOP_OPERATION_HEALTH:
        prepared = prepare_read(session, operation, parameters);
        break;
    case WOP_OPERATION_WRITE:
        prepared = prepare_write(session, operation, parameters);
        break;
    case WOP_OPERATION_CALL:
        prepared = prepare_call(session, operation, parameters);
        break;
    case WOP_OPERATION_BROWSE:
        prepared = prepare_browse(session, operation, parameters, failure);
        break;
    case WOP_OPERATION_BROWSE_NEXT:
    case WOP_OPERATION_BROWSE_RELEASE:
        prepared = wop_session_browse_admit(session, operation, parameters,
                                            owner_operation->kind == WOP_OPERATION_BROWSE_RELEASE);
        break;
    }
    if(!prepared) clear_operation(operation);
    return prepared;
}

static bool session_dispatch(void *context, const WopOperation *owner_operation,
                             uint32_t timeout_ms, WopFailure *failure) {
    WopSession *session = context;
    WopSessionOperation *operation = slot(session, owner_operation);
    bool unknown = owner_operation->kind == WOP_OPERATION_WRITE ||
                   owner_operation->kind == WOP_OPERATION_CALL;
    fail_with(failure, "connection_failed", "admission", unknown);
    if(!operation || !session->client || timeout_ms == 0) return false;
    UA_RequestHeader header;
    UA_RequestHeader_init(&header);
    header.requestHandle = owner_operation->request_handle;
    header.timeoutHint = timeout_ms;
    operation->pending = true;
    UA_StatusCode status = UA_STATUSCODE_BADINTERNALERROR;
    switch(owner_operation->kind) {
    case WOP_OPERATION_READ:
    case WOP_OPERATION_HEALTH: {
        UA_ReadValueId target;
        UA_ReadValueId_init(&target);
        target.nodeId = operation->read_node;
        target.attributeId = UA_ATTRIBUTEID_VALUE;
        UA_ReadRequest request;
        UA_ReadRequest_init(&request);
        request.requestHeader = header;
        request.nodesToRead = &target;
        request.nodesToReadSize = 1;
        request.timestampsToReturn = UA_TIMESTAMPSTORETURN_BOTH;
        status = UA_Client_sendAsyncReadRequest(session->client, &request, receive_read,
                                                operation, &operation->request_id);
        break;
    }
    case WOP_OPERATION_WRITE: {
        UA_WriteRequest request;
        UA_WriteRequest_init(&request);
        request.requestHeader = header;
        request.nodesToWrite = &operation->write_value;
        request.nodesToWriteSize = 1;
        status = UA_Client_sendAsyncWriteRequest(session->client, &request, receive_write,
                                                 operation, &operation->request_id);
        break;
    }
    case WOP_OPERATION_CALL: {
        UA_CallRequest request;
        UA_CallRequest_init(&request);
        request.requestHeader = header;
        request.methodsToCall = &operation->call_method;
        request.methodsToCallSize = 1;
        status = __UA_Client_AsyncService(session->client, &request,
            &UA_TYPES[UA_TYPES_CALLREQUEST], receive_call, &UA_TYPES[UA_TYPES_CALLRESPONSE],
            operation, &operation->request_id);
        break;
    }
    case WOP_OPERATION_BROWSE: {
        UA_BrowseRequest request;
        UA_BrowseRequest_init(&request);
        request.requestHeader = header;
        request.nodesToBrowse = &operation->browse_description;
        request.nodesToBrowseSize = 1;
        request.requestedMaxReferencesPerNode = operation->page_size;
        status = UA_Client_sendAsyncBrowseRequest(session->client, &request, receive_browse,
                                                  operation, &operation->request_id);
        break;
    }
    case WOP_OPERATION_BROWSE_NEXT:
    case WOP_OPERATION_BROWSE_RELEASE: {
        UA_BrowseNextRequest request;
        UA_BrowseNextRequest_init(&request);
        request.requestHeader = header;
        request.releaseContinuationPoints = operation->releasing;
        request.continuationPointsSize = 1;
        request.continuationPoints = &operation->browse_point;
        status = UA_Client_sendAsyncBrowseNextRequest(session->client, &request,
            receive_browse_next, operation, &operation->request_id);
        break;
    }
    }
    if(status == UA_STATUSCODE_GOOD) return true;
    operation->pending = false;
    if(chain_operation(operation)) {
        session->browse_chain_busy = false;
        /* The server may still hold a continuation that can no longer be released. */
        if(owner_operation->kind != WOP_OPERATION_BROWSE) session->browse_orphaned = true;
    }
    return false;
}

static WopCompletion data_value_result(WopSessionOperation *operation, yyjson_mut_doc *document,
                                       yyjson_mut_val **result, WopFailure *failure) {
    if(!operation->valid) {
        fail_with(failure, "invalid_response", "decode", false);
        return WOP_COMPLETION_FAILURE;
    }
    if(operation->status & 0x80000000U) {
        fail_status(failure, "remote_error", "exchange", false, operation->status);
        return WOP_COMPLETION_FAILURE;
    }
    if(operation->read_value.hasValue && !supported_value_type(operation->read_value.value.type)) {
        fail_with(failure, "unsupported_type", "decode", false);
        return WOP_COMPLETION_FAILURE;
    }
    if(wop_value_write_data_value(&operation->read_value, document, result) != WOP_VALUE_OK ||
       !*result) {
        fail_with(failure, "response_limit", "decode", false);
        return WOP_COMPLETION_FAILURE;
    }
    return WOP_COMPLETION_SUCCESS;
}

static WopCompletion call_result(WopSessionOperation *operation, yyjson_mut_doc *document,
                                 yyjson_mut_val **result, WopFailure *failure) {
    if(!operation->valid) {
        fail_with(failure, "invalid_response", "decode", true);
        return WOP_COMPLETION_FAILURE;
    }
    if(operation->status & 0x80000000U) {
        fail_status(failure, "remote_error", "exchange", true, operation->status);
        return WOP_COMPLETION_FAILURE;
    }
    const UA_CallMethodResult *call = &operation->call_result;
    for(size_t i = 0; i < call->outputArgumentsSize; i++) {
        if(!supported_value_type(call->outputArguments[i].type)) {
            fail_with(failure, "unsupported_type", "decode", true);
            return WOP_COMPLETION_FAILURE;
        }
    }
    yyjson_mut_val *object = yyjson_mut_obj(document);
    yyjson_mut_val *statuses = yyjson_mut_arr(document);
    yyjson_mut_val *outputs = yyjson_mut_arr(document);
    bool valid = object && statuses && outputs &&
        yyjson_mut_obj_add_uint(document, object, "status", call->statusCode) &&
        yyjson_mut_obj_add_val(document, object, "input_argument_statuses", statuses) &&
        yyjson_mut_obj_add_val(document, object, "outputs", outputs);
    for(size_t i = 0; valid && i < call->inputArgumentResultsSize; i++)
        valid = yyjson_mut_arr_add_uint(document, statuses, call->inputArgumentResults[i]);
    for(size_t i = 0; valid && i < call->outputArgumentsSize; i++) {
        yyjson_mut_val *value = NULL;
        valid = wop_value_write_variant(&call->outputArguments[i], document, &value) ==
                    WOP_VALUE_OK && value && yyjson_mut_arr_append(outputs, value);
    }
    if(!valid) {
        fail_with(failure, "response_limit", "decode", true);
        return WOP_COMPLETION_FAILURE;
    }
    *result = object;
    return WOP_COMPLETION_SUCCESS;
}

static WopCompletion browse_result(WopSession *session, WopSessionOperation *operation,
                                   yyjson_mut_doc *document, yyjson_mut_val **result,
                                   WopFailure *failure) {
    bool next = operation->kind == WOP_OPERATION_BROWSE_NEXT;
    if(operation->releasing) {
        session->browse_chain_busy = false;
        if(!operation->release_valid) {
            fail_with(failure, "cleanup_failed", "cleanup", false);
            return WOP_COMPLETION_TERMINAL;
        }
        *result = yyjson_mut_null(document);
        return *result ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
    }
    if(chain_operation(operation)) session->browse_chain_busy = false;
    if(operation->limit) {
        fail_with(failure, "response_limit", "decode", false);
        return WOP_COMPLETION_TERMINAL;
    }
    if(operation->remote_error && !next) {
        fail_status(failure, "remote_error", "exchange", false, operation->status);
        return WOP_COMPLETION_FAILURE;
    }
    if(!operation->valid) {
        if(operation->remote_error)
            fail_status(failure, "remote_error", "exchange", false, operation->status);
        else
            fail_with(failure, "invalid_response", "decode", false);
        return WOP_COMPLETION_TERMINAL;
    }
    if(operation->status & 0x80000000U) {
        fail_status(failure, "remote_error", "exchange", false, operation->status);
        return next ? WOP_COMPLETION_TERMINAL : WOP_COMPLETION_FAILURE;
    }
    if(!wop_session_browse_capture(session, operation)) {
        fail_with(failure, "response_limit", "decode", false);
        return WOP_COMPLETION_TERMINAL;
    }
    char token[32] = {0};
    const char *continuation = session->browse_active ? token : NULL;
    yyjson_mut_val *object = yyjson_mut_obj(document);
    yyjson_mut_val *references = NULL;
    if(!object || (continuation && !wop_session_browse_token(session, token)) ||
       wop_value_write_references(operation->browse_result.references,
                                  operation->browse_result.referencesSize, document,
                                  &references) != WOP_VALUE_OK || !references ||
       !yyjson_mut_obj_add_uint(document, object, "status", operation->browse_result.statusCode) ||
       !yyjson_mut_obj_add_val(document, object, "references", references) ||
       !(continuation ? yyjson_mut_obj_add_strcpy(document, object, "continuation", continuation) :
                        yyjson_mut_obj_add_null(document, object, "continuation"))) {
        fail_with(failure, "response_limit", "decode", false);
        return WOP_COMPLETION_TERMINAL;
    }
    *result = object;
    return WOP_COMPLETION_SUCCESS;
}

static WopCompletion session_complete(void *context, const WopOperation *owner_operation,
                                      yyjson_mut_doc *document, yyjson_mut_val **result,
                                      WopFailure *failure) {
    WopSession *session = context;
    WopSessionOperation *operation = slot(session, owner_operation);
    if(!operation) {
        fail_with(failure, "invalid_response", "decode", false);
        return WOP_COMPLETION_TERMINAL;
    }
    if(operation->pending || !operation->delivered) return WOP_COMPLETION_PENDING;
    bool unknown = owner_operation->kind == WOP_OPERATION_WRITE ||
                   owner_operation->kind == WOP_OPERATION_CALL;
    if(operation->transport_error) {
        if(chain_operation(operation)) session->browse_chain_busy = false;
        fail_status(failure, "connection_failed", "exchange", unknown, operation->status);
        return WOP_COMPLETION_TERMINAL;
    }
    if(operation->timed_out) {
        if(chain_operation(operation)) {
            session->browse_chain_busy = false;
            session->browse_orphaned = true;
        }
        fail_with(failure, "deadline_exceeded", "exchange", unknown);
        return WOP_COMPLETION_FAILURE;
    }
    switch(owner_operation->kind) {
    case WOP_OPERATION_READ:
    case WOP_OPERATION_HEALTH:
        if(operation->remote_error) {
            fail_status(failure, "remote_error", "exchange", false, operation->status);
            return WOP_COMPLETION_FAILURE;
        }
        return data_value_result(operation, document, result, failure);
    case WOP_OPERATION_WRITE:
        if(operation->remote_error || (operation->valid && (operation->status & 0x80000000U))) {
            fail_status(failure, "remote_error", "exchange", true, operation->status);
            return WOP_COMPLETION_FAILURE;
        }
        if(!operation->valid) {
            fail_with(failure, "invalid_response", "decode", true);
            return WOP_COMPLETION_FAILURE;
        }
        *result = yyjson_mut_obj(document);
        if(!*result || !yyjson_mut_obj_add_uint(document, *result, "status", operation->status)) {
            fail_with(failure, "response_limit", "decode", true);
            return WOP_COMPLETION_FAILURE;
        }
        return WOP_COMPLETION_SUCCESS;
    case WOP_OPERATION_CALL:
        if(operation->remote_error) {
            fail_status(failure, "remote_error", "exchange", true, operation->status);
            return WOP_COMPLETION_FAILURE;
        }
        return call_result(operation, document, result, failure);
    case WOP_OPERATION_BROWSE:
    case WOP_OPERATION_BROWSE_NEXT:
    case WOP_OPERATION_BROWSE_RELEASE:
        return browse_result(session, operation, document, result, failure);
    }
    fail_with(failure, "invalid_response", "decode", unknown);
    return WOP_COMPLETION_TERMINAL;
}

static void ignore_cancel(UA_Client *client, void *userdata, UA_UInt32 request_id,
                          void *response) {
    (void)client; (void)userdata; (void)request_id; (void)response;
}

/* The SDK's cancel helpers wait synchronously; this sends the same Cancel
 * service asynchronously with a bounded hint and ignores its count. */
static void session_cancel(void *context, const WopOperation *owner_operation) {
    WopSession *session = context;
    WopSessionOperation *operation = slot(session, owner_operation);
    if(!operation || !operation->pending || !session->client) return;
    UA_CancelRequest request;
    UA_CancelRequest_init(&request);
    request.requestHeader.timeoutHint = 1000;
    request.requestHandle = owner_operation->request_handle;
    (void)__UA_Client_AsyncService(session->client, &request, &UA_TYPES[UA_TYPES_CANCELREQUEST],
                                   ignore_cancel, &UA_TYPES[UA_TYPES_CANCELRESPONSE], NULL, NULL);
}

static void session_retire(void *context, const WopOperation *owner_operation) {
    WopSession *session = context;
    WopSessionOperation *operation = slot(session, owner_operation);
    if(!operation) return;
    if(chain_operation(operation)) {
        if(owner_operation->state == WOP_SLOT_QUEUED && !session->browse_orphaned &&
           operation->browse_point.length && !session->browse_active) {
            /* A queued BrowseNext or release never reached the server; its
             * live continuation returns to the session unchanged. */
            session->browse_point = operation->browse_point;
            operation->browse_point = UA_BYTESTRING_NULL;
            session->browse_active = true;
        }
        /* Retiring sent chain work leaves possible server state unowned. */
        if(operation->pending) session->browse_orphaned = true;
        session->browse_chain_busy = false;
    }
    operation->abandoned = operation->pending;
    clear_operation(operation);
}

static bool session_released(void *context, const WopOperation *owner_operation) {
    WopSession *session = context;
    WopSessionOperation *operation = slot(session, owner_operation);
    return !operation || !operation->pending;
}

static bool session_close_service(void *context) {
    return wop_session_close(context);
}

void wop_session_service(WopSession *session, WopService *service) {
    for(size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) session->operations[i].session = session;
    service->context = session;
    service->open = session_open;
    service->opened = session_opened;
    service->prepare = session_prepare;
    service->dispatch = session_dispatch;
    service->complete = session_complete;
    service->cancel = session_cancel;
    service->retire = session_retire;
    service->released = session_released;
    service->step = session_step;
    service->close = session_close_service;
}

bool wop_session_close(WopSession *session) {
    if(!session) return false;
    bool closed = true;
    if(session->client) {
        UA_ClientConfig *config = UA_Client_getConfig(session->client);
        config->timeout = 350;
        UA_StatusCode requested = UA_Client_disconnectAsync(session->client);
        closed = requested == UA_STATUSCODE_GOOD;
        int64_t start = monotonic_ms();
        int64_t deadline = start < 0 ? -1 : start + 400;
        UA_SecureChannelState channel = UA_SECURECHANNELSTATE_CLOSED;
        UA_SessionState state = UA_SESSIONSTATE_CLOSED;
        while(deadline > 0 && monotonic_ms() < deadline) {
            UA_Client_getState(session->client, &channel, &state, NULL);
            if(channel == UA_SECURECHANNELSTATE_CLOSED && state == UA_SESSIONSTATE_CLOSED)
                break;
            (void)UA_Client_run_iterate(session->client, 1);
        }
        UA_Client_getState(session->client, &channel, &state, NULL);
        closed = closed && channel == UA_SECURECHANNELSTATE_CLOSED &&
                 state == UA_SESSIONSTATE_CLOSED;
        config->timeout = 10;
        /* Client deletion completes every outstanding callback with a shutdown
         * status before operation storage is cleared below. */
        UA_Client_delete(session->client);
        session->client = NULL;
    }
    if(session->namespace_array)
        UA_Array_delete(session->namespace_array, session->namespace_count,
                        &UA_TYPES[UA_TYPES_STRING]);
    session->namespace_array = NULL;
    session->namespace_count = 0;
    for(size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        session->operations[i].pending = false;
        session->operations[i].abandoned = false;
        session->operations[i].session = session;
        clear_operation(&session->operations[i]);
    }
    UA_ByteString_clear(&session->browse_point);
    wop_security_clear(&session->security);
    session->revised_timeout_ms = 0;
    session->requested_timeout_ms = 0;
    session->namespace_requested = session->namespace_received = false;
    session->namespace_valid = session->ready = false;
    session->browse_serial = 0;
    session->browse_page_size = session->browse_pages = session->browse_references = 0;
    session->browse_bytes = 0;
    session->browse_active = session->browse_chain_busy = session->browse_orphaned = false;
    return closed;
}
