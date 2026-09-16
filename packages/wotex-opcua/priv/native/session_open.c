/* SPDX-License-Identifier: Apache-2.0 */
#include "session_open.h"
#include "value_codec.h"

#include <open62541/client_highlevel_async.h>
#include <math.h>
#include <stddef.h>
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

bool wop_session_start(WopSession *session, yyjson_val *parameters, time_t now,
                       int64_t deadline_ms) {
    if(!session || !wop_security_read(parameters, now, &session->security)) return false;
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
    return false;
}

bool wop_session_step(WopSession *session, uint64_t requested_timeout_ms) {
    if(!session || !session->client) return false;
    UA_StatusCode status = UA_Client_run_iterate(session->client, 1);
    UA_StatusCode connection = UA_STATUSCODE_GOOD;
    UA_SessionState state = UA_SESSIONSTATE_CLOSED;
    UA_Client_getState(session->client, NULL, &state, &connection);
    if(status != UA_STATUSCODE_GOOD || connection != UA_STATUSCODE_GOOD ||
       (session->namespace_requested && state != UA_SESSIONSTATE_ACTIVATED)) return false;
    if(state != UA_SESSIONSTATE_ACTIVATED) return true;
    if(!session->namespace_requested) {
        session->namespace_requested = true;
        return UA_Client_readValueAttribute_async(session->client,
            UA_NS0ID(SERVER_NAMESPACEARRAY), receive_namespaces, session, NULL) == UA_STATUSCODE_GOOD;
    }
    if(!session->namespace_received) return true;
    if(!session->namespace_valid) return false;
    if(!session->ready) {
        UA_Double value = NAN;
        if(UA_Client_getConnectionAttribute_scalar(session->client,
              UA_QUALIFIEDNAME(0, "revisedSessionTimeout"),
              &UA_TYPES[UA_TYPES_DOUBLE], &value) != UA_STATUSCODE_GOOD ||
           !isfinite(value) || value <= 0 || value > (UA_Double)requested_timeout_ms)
            return false;
        session->revised_timeout_ms = value;
        session->ready = true;
    }
    return true;
}

static void receive_read(UA_Client *client, void *userdata, UA_UInt32 request_id,
                         UA_ReadResponse *response) {
    (void)client;
    WopSession *session = userdata;
    if(!session->read_pending) return;
    session->read_pending = false;
    session->read_completed = true;
    session->read_status = UA_STATUSCODE_BADUNEXPECTEDERROR;
    if(!response || request_id != session->read_request_id) return;
    if(response->responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        session->read_status = response->responseHeader.serviceResult;
        session->read_remote_error = true;
        return;
    }
    if(response->resultsSize != 1 || !response->results) return;
    const UA_DataValue *value = &response->results[0];
    session->read_status = value->hasStatus ? value->status : UA_STATUSCODE_GOOD;
    if(UA_DataValue_copy(value, &session->read_value) != UA_STATUSCODE_GOOD) {
        session->read_status = UA_STATUSCODE_BADOUTOFMEMORY;
        return;
    }
    session->read_valid = true;
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

bool wop_session_read(WopSession *session, yyjson_val *parameters) {
    if(!session || !session->ready || session->read_pending ||
       !yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 2 ||
       !yyjson_is_null(yyjson_obj_get(parameters, "index_range"))) return false;
    _Alignas(max_align_t) unsigned char storage[8192];
    WopValueArena arena;
    UA_NodeId sdk_id = UA_NODEID_NULL;
    if(!wop_value_arena_init(&arena, storage, sizeof(storage)) ||
       !translate_node(session, yyjson_obj_get(parameters, "node_id"),
                       &arena, &sdk_id)) return false;
    UA_ReadValueId target = {0};
    target.nodeId = sdk_id;
    target.attributeId = UA_ATTRIBUTEID_VALUE;
    UA_ReadRequest request = {0};
    request.nodesToRead = &target;
    request.nodesToReadSize = 1;
    request.timestampsToReturn = UA_TIMESTAMPSTORETURN_BOTH;
    UA_DataValue_clear(&session->read_value);
    session->read_completed = false;
    session->read_valid = false;
    session->read_remote_error = false;
    session->read_pending = true;
    UA_StatusCode status = UA_Client_sendAsyncReadRequest(session->client, &request,
                                                           receive_read, session,
                                                           &session->read_request_id);
    if(status != UA_STATUSCODE_GOOD) session->read_pending = false;
    return status == UA_STATUSCODE_GOOD;
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

bool wop_session_read_supported(const WopSession *session) {
    if(!session || !session->read_valid) return false;
    if(!session->read_value.hasValue) return true;
    return supported_value_type(session->read_value.value.type);
}

static void receive_write(UA_Client *client, void *userdata, UA_UInt32 request_id,
                          UA_WriteResponse *response) {
    (void)client;
    WopSession *session = userdata;
    if(!session->write_pending) return;
    session->write_pending = false;
    session->write_completed = true;
    session->write_status = UA_STATUSCODE_BADUNEXPECTEDERROR;
    if(!response || request_id != session->write_request_id) return;
    if(response->responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        session->write_status = response->responseHeader.serviceResult;
        session->write_remote_error = true;
        return;
    }
    if(response->resultsSize != 1 || !response->results) return;
    session->write_status = response->results[0];
    session->write_valid = true;
}

bool wop_session_write(WopSession *session, yyjson_val *parameters,
                       bool *sdk_attempted) {
    if(!sdk_attempted) return false;
    *sdk_attempted = false;
    if(!session || !session->ready || session->write_pending ||
       !yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 3 ||
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
    UA_WriteValue_clear(&session->write_value);
    if(valid) {
        valid = UA_NodeId_copy(&sdk_id, &session->write_value.nodeId) == UA_STATUSCODE_GOOD &&
            UA_Variant_copy(&value, &session->write_value.value.value) == UA_STATUSCODE_GOOD;
        session->write_value.attributeId = UA_ATTRIBUTEID_VALUE;
        session->write_value.value.hasValue = true;
    }
    wop_value_arena_reset(&arena);
    free(storage);
    if(!valid) {
        UA_WriteValue_clear(&session->write_value);
        return false;
    }
    UA_WriteRequest request = {0};
    request.nodesToWrite = &session->write_value;
    request.nodesToWriteSize = 1;
    session->write_pending = true;
    session->write_completed = false;
    session->write_valid = false;
    session->write_remote_error = false;
    *sdk_attempted = true;
    UA_StatusCode status = UA_Client_sendAsyncWriteRequest(session->client, &request,
        receive_write, session, &session->write_request_id);
    if(status != UA_STATUSCODE_GOOD) {
        session->write_pending = false;
        UA_WriteValue_clear(&session->write_value);
    }
    return status == UA_STATUSCODE_GOOD;
}

static void receive_call(UA_Client *client, void *userdata, UA_UInt32 request_id,
                         UA_CallResponse *response) {
    (void)client;
    WopSession *session = userdata;
    if(!session->call_pending) return;
    session->call_pending = false;
    session->call_completed = true;
    session->call_status = UA_STATUSCODE_BADUNEXPECTEDERROR;
    if(!response || request_id != session->call_request_id) return;
    if(response->responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        session->call_status = response->responseHeader.serviceResult;
        session->call_remote_error = true;
        return;
    }
    if(response->resultsSize != 1 || !response->results) return;
    const UA_CallMethodResult *result = &response->results[0];
    if(result->inputArgumentResultsSize > 64 || result->outputArgumentsSize > 64 ||
       (result->inputArgumentResultsSize && !result->inputArgumentResults) ||
       (result->outputArgumentsSize && !result->outputArguments)) return;
    session->call_status = result->statusCode;
    if(UA_CallMethodResult_copy(result, &session->call_result) != UA_STATUSCODE_GOOD) {
        session->call_status = UA_STATUSCODE_BADOUTOFMEMORY;
        return;
    }
    session->call_valid = true;
}

bool wop_session_call(WopSession *session, yyjson_val *parameters,
                      bool *sdk_attempted) {
    if(!sdk_attempted) return false;
    *sdk_attempted = false;
    if(!session || !session->ready || session->call_pending ||
       !yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 3) return false;
    yyjson_val *arguments = yyjson_obj_get(parameters, "arguments");
    if(!yyjson_is_arr(arguments) || yyjson_arr_size(arguments) > 64) return false;
    void *storage = malloc(WOP_VALUE_POOL_BYTES);
    if(!storage) return false;
    WopValueArena arena;
    UA_NodeId object_id = UA_NODEID_NULL, method_id = UA_NODEID_NULL;
    bool valid = wop_value_arena_init(&arena, storage, WOP_VALUE_POOL_BYTES) &&
        translate_node(session, yyjson_obj_get(parameters, "object_id"), &arena, &object_id) &&
        translate_node(session, yyjson_obj_get(parameters, "method_id"), &arena, &method_id);
    UA_CallMethodRequest_clear(&session->call_method);
    UA_CallMethodResult_clear(&session->call_result);
    if(valid) {
        valid = UA_NodeId_copy(&object_id, &session->call_method.objectId) == UA_STATUSCODE_GOOD &&
                UA_NodeId_copy(&method_id, &session->call_method.methodId) == UA_STATUSCODE_GOOD;
        size_t count = yyjson_arr_size(arguments);
        if(valid && count) {
            session->call_method.inputArguments = UA_Array_new(count, &UA_TYPES[UA_TYPES_VARIANT]);
            valid = session->call_method.inputArguments != NULL;
            if(valid) session->call_method.inputArgumentsSize = count;
        }
        for(size_t i = 0; valid && i < count; i++) {
            UA_Variant input = {0};
            valid = wop_value_read_variant(yyjson_arr_get(arguments, i), &arena, &input) == WOP_VALUE_OK &&
                supported_value_type(input.type) &&
                UA_Variant_copy(&input, &session->call_method.inputArguments[i]) == UA_STATUSCODE_GOOD;
        }
    }
    wop_value_arena_reset(&arena);
    free(storage);
    if(!valid) {
        UA_CallMethodRequest_clear(&session->call_method);
        return false;
    }
    session->call_pending = true;
    session->call_completed = false;
    session->call_valid = false;
    session->call_remote_error = false;
    *sdk_attempted = true;
    UA_StatusCode status = UA_Client_call_async(session->client,
        session->call_method.objectId, session->call_method.methodId,
        session->call_method.inputArgumentsSize, session->call_method.inputArguments,
        receive_call, session, &session->call_request_id);
    if(status != UA_STATUSCODE_GOOD) {
        session->call_pending = false;
        UA_CallMethodRequest_clear(&session->call_method);
    }
    return status == UA_STATUSCODE_GOOD;
}

bool wop_session_call_supported(const WopSession *session) {
    if(!session || !session->call_valid) return false;
    for(size_t i = 0; i < session->call_result.outputArgumentsSize; i++)
        if(!supported_value_type(session->call_result.outputArguments[i].type))
            return false;
    return true;
}

static void receive_browse(UA_Client *client, void *userdata, UA_UInt32 request_id,
                           UA_BrowseResponse *response) {
    (void)client;
    WopSession *session = userdata;
    if(!session->browse_pending) return;
    session->browse_pending = false;
    session->browse_completed = true;
    session->browse_status = UA_STATUSCODE_BADUNEXPECTEDERROR;
    if(!response || request_id != session->browse_request_id) return;
    if(response->responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        session->browse_status = response->responseHeader.serviceResult;
        session->browse_remote_error = true;
        return;
    }
    if(response->resultsSize != 1 || !response->results ||
       response->diagnosticInfosSize != 0) return;
    const UA_BrowseResult *result = &response->results[0];
    session->browse_status = result->statusCode;
    size_t size = UA_calcSizeBinary(result, &UA_TYPES[UA_TYPES_BROWSERESULT], NULL);
    if(result->referencesSize > session->browse_page_size ||
       result->continuationPoint.length > 4096 || size > 1048576) {
        session->browse_limit = true;
        return;
    }
    if(size == 0) return;
    if(UA_BrowseResult_copy(result, &session->browse_result) != UA_STATUSCODE_GOOD)
        return;
    session->browse_valid = true;
}

bool wop_session_browse(WopSession *session, yyjson_val *parameters) {
    if(!session || !session->ready || session->browse_pending ||
       !yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 6)
        return false;
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

    _Alignas(max_align_t) unsigned char storage[16384];
    WopValueArena arena;
    UA_NodeId node = UA_NODEID_NULL, reference_type = UA_NODEID_NULL;
    if(!wop_value_arena_init(&arena, storage, sizeof(storage)) ||
       !translate_node(session, yyjson_obj_get(parameters, "node_id"), &arena, &node) ||
       !translate_node(session, yyjson_obj_get(parameters, "reference_type_id"),
                       &arena, &reference_type)) return false;

    UA_BrowseDescription_clear(&session->browse_description);
    UA_BrowseResult_clear(&session->browse_result);
    UA_BrowseDescription *description = &session->browse_description;
    if(UA_NodeId_copy(&node, &description->nodeId) != UA_STATUSCODE_GOOD ||
       UA_NodeId_copy(&reference_type, &description->referenceTypeId) != UA_STATUSCODE_GOOD) {
        UA_BrowseDescription_clear(description);
        return false;
    }
    description->browseDirection = sdk_direction;
    description->includeSubtypes = yyjson_get_bool(subtypes);
    description->nodeClassMask = (UA_UInt32)mask;
    description->resultMask = UA_BROWSERESULTMASK_ALL;
    UA_BrowseRequest request = {0};
    request.nodesToBrowse = description;
    request.nodesToBrowseSize = 1;
    request.requestedMaxReferencesPerNode = (UA_UInt32)page_size;
    session->browse_page_size = (UA_UInt32)page_size;
    session->browse_pending = true;
    session->browse_completed = false;
    session->browse_valid = false;
    session->browse_remote_error = false;
    session->browse_limit = false;
    UA_StatusCode status = UA_Client_sendAsyncBrowseRequest(session->client, &request,
        receive_browse, session, &session->browse_request_id);
    if(status != UA_STATUSCODE_GOOD) {
        session->browse_pending = false;
        UA_BrowseDescription_clear(description);
    }
    return status == UA_STATUSCODE_GOOD;
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
        UA_Client_delete(session->client);
    }
    if(session->namespace_array)
        UA_Array_delete(session->namespace_array, session->namespace_count,
                        &UA_TYPES[UA_TYPES_STRING]);
    UA_DataValue_clear(&session->read_value);
    UA_WriteValue_clear(&session->write_value);
    UA_CallMethodRequest_clear(&session->call_method);
    UA_CallMethodResult_clear(&session->call_result);
    UA_BrowseDescription_clear(&session->browse_description);
    UA_BrowseResult_clear(&session->browse_result);
    wop_security_clear(&session->security);
    memset(session, 0, sizeof(*session));
    return closed;
}
