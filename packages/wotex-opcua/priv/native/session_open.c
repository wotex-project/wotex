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

bool wop_session_read(WopSession *session, yyjson_val *parameters) {
    if(!session || !session->ready || session->read_pending ||
       !yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 2 ||
       !yyjson_is_null(yyjson_obj_get(parameters, "index_range"))) return false;
    yyjson_val *node_input = yyjson_obj_get(parameters, "node_id");
    _Alignas(max_align_t) unsigned char storage[8192];
    WopValueArena arena;
    UA_NodeId public_id = UA_NODEID_NULL;
    if(!wop_value_arena_init(&arena, storage, sizeof(storage)) ||
       wop_value_read_node_id(node_input, &arena, &public_id) != WOP_VALUE_OK ||
       public_id.namespaceIndex >= session->namespace_count) return false;
    UA_String identity = session->namespace_array[public_id.namespaceIndex];
    UA_UInt16 local_index = 0;
    UA_String reversed = UA_STRING_NULL;
    bool mapped = UA_Client_getNamespaceIndex(session->client, identity, &local_index) == UA_STATUSCODE_GOOD &&
                  UA_Client_getNamespaceUri(session->client, local_index, &reversed) == UA_STATUSCODE_GOOD &&
                  UA_String_equal(&identity, &reversed);
    UA_String_clear(&reversed);
    if(!mapped) return false;
    UA_NodeId sdk_id = public_id;
    sdk_id.namespaceIndex = local_index;
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

bool wop_session_read_supported(const WopSession *session) {
    if(!session || !session->read_valid) return false;
    if(!session->read_value.hasValue) return true;
    const UA_DataType *type = session->read_value.value.type;
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
    wop_security_clear(&session->security);
    memset(session, 0, sizeof(*session));
    return closed;
}
