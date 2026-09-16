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
} WopSession;

/* Only call after closed open-shape and deadline admission. The caller owns
 * the stable WopSession storage through wop_session_close. */
bool wop_session_start(WopSession *session, yyjson_val *parameters, time_t now,
                       int64_t deadline_ms);
bool wop_session_step(WopSession *session, uint64_t requested_timeout_ms);
/* True only when the CloseSession/channel teardown completed cooperatively. */
bool wop_session_close(WopSession *session);

#endif
