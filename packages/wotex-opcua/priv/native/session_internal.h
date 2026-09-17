/* SPDX-License-Identifier: Apache-2.0
 * Internal helpers shared by the Session service translation units. */
#ifndef WOTEX_OPCUA_SESSION_INTERNAL_H
#define WOTEX_OPCUA_SESSION_INTERNAL_H

#include "session_open.h"
#include "value_codec.h"

void wop_fail(WopFailure *failure, const char *code, const char *phase, bool unknown_effect);
void wop_fail_status(WopFailure *failure, const char *code, const char *phase,
                     bool unknown_effect, UA_StatusCode status);
bool wop_session_translate(WopSession *session, yyjson_val *node_input, WopValueArena *arena,
                           UA_NodeId *sdk_id);
bool wop_session_supported(const UA_DataType *type);
bool wop_session_accept(WopSessionOperation *operation, UA_UInt32 request_id,
                        const UA_ResponseHeader *header);
int64_t wop_session_clock(void);
/* Delivers one scripted SDK response to the production receive path. */
void wop_session_browse_receive(WopSessionOperation *operation, UA_UInt32 request_id,
                                UA_BrowseResponse *response);
void wop_session_browse_next_receive(WopSessionOperation *operation, UA_UInt32 request_id,
                                     UA_BrowseNextResponse *response);

/* Subscription service, implemented in session_subscription.c. */
bool wop_subscription_prepare(WopSession *session, WopSessionOperation *operation,
                              yyjson_val *parameters, WopFailure *failure);
bool wop_subscription_dispatch(WopSession *session, WopSessionOperation *operation,
                               const UA_RequestHeader *header);
WopCompletion wop_subscription_complete(WopSession *session, WopSessionOperation *operation,
                                        yyjson_mut_doc *document, yyjson_mut_val **result,
                                        WopFailure *failure);
void wop_subscription_retire(WopSession *session, WopSessionOperation *operation);
bool wop_subscription_step(WopSession *session, WopFailure *failure);
bool wop_subscription_report(WopSession *session, yyjson_mut_doc *document,
                             yyjson_mut_val *envelope, bool *produced, WopFailure *failure);
void wop_subscription_clear(WopSession *session);

#endif
