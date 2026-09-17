/* SPDX-License-Identifier: Apache-2.0 */
#include "session_open.h"
#include <stdio.h>
#include <string.h>

static int fail(const char *message) {
    fprintf(stderr, "browse state: %s\n", message);
    return 1;
}

int main(void) {
    static WopSession session;
    WopService service;
    wop_session_service(&session, &service);
    WopSessionOperation *operation = &session.operations[0];
    char token[32] = {0};
    UA_ByteString secret = UA_BYTESTRING("server-private-bytes");
    if(UA_ByteString_copy(&secret, &operation->browse_result.continuationPoint) != UA_STATUSCODE_GOOD)
        return fail("allocation");
    operation->valid = true;
    operation->expose = true;
    if(!wop_session_browse_capture(&session, operation) ||
       !wop_session_browse_token(&session, token) || strcmp(token, "c1") != 0 ||
       !UA_ByteString_equal(&session.browse_point, &secret))
        return fail("first local token");

    /* A peer may reuse identical opaque bytes. The consumed public token must
     * still change while the bytes remain only in native-owned storage. */
    if(!wop_session_browse_capture(&session, operation) ||
       !wop_session_browse_token(&session, token) || strcmp(token, "c2") != 0 ||
       !UA_ByteString_equal(&session.browse_point, &secret))
        return fail("fresh token for reused bytes");

    session.ready = true;
    WopSessionOperation *next = &session.operations[1];
    yyjson_doc *foreign = yyjson_read("{\"continuation\":\"c1\"}", 21, 0);
    if(!foreign || wop_session_browse_admit(&session, next, yyjson_doc_get_root(foreign), false) ||
       wop_session_browse_admit(&session, next, yyjson_doc_get_root(foreign), true) ||
       !session.browse_active || session.browse_chain_busy) return fail("foreign token admission");
    yyjson_doc_free(foreign);

    /* The exact live token moves the server bytes into one operation and makes
     * the chain busy; a second admission for the same token is rejected. */
    yyjson_doc *current = yyjson_read("{\"continuation\":\"c2\"}", 21, 0);
    if(!current || !wop_session_browse_admit(&session, next, yyjson_doc_get_root(current), false) ||
       session.browse_active || !session.browse_chain_busy ||
       !UA_ByteString_equal(&next->browse_point, &secret) ||
       wop_session_browse_admit(&session, &session.operations[2],
                                yyjson_doc_get_root(current), true))
        return fail("live token consumption");
    yyjson_doc_free(current);

    /* Retiring queued BrowseNext before dispatch restores the unchanged
     * continuation instead of losing server state. */
    WopOperation queued = {0};
    queued.state = WOP_SLOT_QUEUED;
    queued.kind = WOP_OPERATION_BROWSE_NEXT;
    queued.index = 1;
    service.retire(service.context, &queued);
    if(!session.browse_active || session.browse_chain_busy || session.browse_orphaned ||
       !UA_ByteString_equal(&session.browse_point, &secret) || !wop_session_browse_token(&session, token) ||
       strcmp(token, "c2") != 0)
        return fail("queued retirement restores continuation");

    session.browse_pages = 64;
    if(wop_session_browse_capture(&session, operation) || session.browse_active)
        return fail("page ceiling with live server point");
    session.browse_pages = 0;

    operation->expose = false;
    if(wop_session_browse_capture(&session, operation) || session.browse_active ||
       session.browse_point.length != 0)
        return fail("unhandled continuation closes instead of exposing bytes");

    /* Retiring dispatched chain work leaves possible server state unowned. */
    WopOperation sent = {0};
    sent.state = WOP_SLOT_DISPATCHED;
    sent.kind = WOP_OPERATION_BROWSE_NEXT;
    sent.index = 3;
    session.operations[3].kind = WOP_OPERATION_BROWSE_NEXT;
    session.operations[3].pending = true;
    service.retire(service.context, &sent);
    if(!session.browse_orphaned || service.released(service.context, &sent))
        return fail("dispatched retirement orphans continuation");

    UA_BrowseResult_clear(&operation->browse_result);
    session.operations[3].pending = false;
    (void)wop_session_close(&session);
    printf("{\"status\":\"passed\"}\n");
    return 0;
}
