/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_SESSION_OPEN_H
#define WOTEX_OPCUA_SESSION_OPEN_H

#include "session_config.h"

typedef struct {
    UA_Client *client;
    WopSecurity security;
    UA_String *namespace_array;
    size_t namespace_count;
    UA_Double revised_timeout_ms;
    bool namespace_requested, namespace_received, namespace_valid, ready;
    UA_DataValue read_value;
    UA_StatusCode read_status;
    UA_UInt32 read_request_id;
    bool read_pending, read_completed, read_valid, read_remote_error;
    UA_WriteValue write_value;
    UA_StatusCode write_status;
    UA_UInt32 write_request_id;
    bool write_pending, write_completed, write_valid, write_remote_error;
    UA_CallMethodRequest call_method;
    UA_CallMethodResult call_result;
    UA_StatusCode call_status;
    UA_UInt32 call_request_id;
    bool call_pending, call_completed, call_valid, call_remote_error;
    UA_BrowseDescription browse_description;
    UA_BrowseResult browse_result;
    UA_StatusCode browse_status;
    UA_UInt32 browse_request_id;
    UA_UInt32 browse_page_size;
    bool browse_pending, browse_completed, browse_valid, browse_remote_error, browse_limit;
    UA_ByteString browse_point;
    UA_UInt64 browse_serial;
    UA_UInt32 browse_pages, browse_references;
    size_t browse_bytes;
    bool browse_active, browse_expose, browse_releasing, browse_release_valid;
} WopSession;

/* Only call after closed open-shape and deadline admission. The caller owns
 * the stable WopSession storage through wop_session_close. */
bool wop_session_start(WopSession *session, yyjson_val *parameters, time_t now,
                       int64_t deadline_ms);
bool wop_session_step(WopSession *session, uint64_t requested_timeout_ms);
/* One bounded asynchronous Value read. The JSON owner retains the IPC ID and
 * deadline; callback storage remains in WopSession until close or completion. */
bool wop_session_read(WopSession *session, yyjson_val *parameters);
bool wop_session_read_supported(const WopSession *session);
/* Write owns copied SDK values until callback or client destruction. A
 * transmitted write may have an unknown effect on every failure path. */
bool wop_session_write(WopSession *session, yyjson_val *parameters,
                       bool *sdk_attempted);
/* One bounded asynchronous Call with copied argument storage. */
bool wop_session_call(WopSession *session, yyjson_val *parameters,
                      bool *sdk_attempted);
bool wop_session_call_supported(const WopSession *session);
/* One service-level bounded Browse page. A continuation is not exposed until
 * owner-bound pagination exists; the caller closes the Session on that path. */
bool wop_session_browse(WopSession *session, yyjson_val *parameters);
/* Only a local token matching the current native generation can select the
 * C-owned server bytes. A failed BrowseNext/release closes the Session. */
bool wop_session_browse_next(WopSession *session, yyjson_val *parameters,
                             bool release);
bool wop_session_browse_token(const WopSession *session, char token[32]);
bool wop_session_browse_capture(WopSession *session);
/* True only when the CloseSession/channel teardown completed cooperatively. */
bool wop_session_close(WopSession *session);

#endif
