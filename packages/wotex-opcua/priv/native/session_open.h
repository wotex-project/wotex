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
/* True only when the CloseSession/channel teardown completed cooperatively. */
bool wop_session_close(WopSession *session);

#endif
