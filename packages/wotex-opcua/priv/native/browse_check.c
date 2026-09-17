/* SPDX-License-Identifier: Apache-2.0 */
#include "session_open.h"
#include "json_codec.h"
#include <open62541/client_config_default.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fail(const char *message) {
    fprintf(stderr, "browse state: %s\n", message);
    return 1;
}

static bool token_is(const WopSession *session, size_t chain, const char *expected) {
    char token[32] = {0};
    return wop_session_browse_token(session, chain, token) && strcmp(token, expected) == 0;
}

static yyjson_doc *continuation(const char *token) {
    char text[64];
    int length = snprintf(text, sizeof(text), "{\"continuation\":\"%s\"}", token);
    return length > 0 ? yyjson_read(text, (size_t)length, 0) : NULL;
}

static bool admit(WopSession *session, WopSessionOperation *operation, const char *token,
                  bool release) {
    yyjson_doc *document = continuation(token);
    bool admitted = document &&
        wop_session_browse_admit(session, operation, yyjson_doc_get_root(document), release);
    yyjson_doc_free(document);
    return admitted;
}

/* Reserves a chain as an exposed Browse admission does, then captures a page. */
static bool capture(WopSession *session, size_t slot, size_t chain, const UA_ByteString *point) {
    WopSessionOperation *operation = &session->operations[slot];
    operation->session = session;
    operation->kind = WOP_OPERATION_BROWSE;
    operation->expose = true;
    operation->chain = chain;
    operation->valid = true;
    session->browse_chains[chain].used = true;
    UA_ByteString_clear(&operation->browse_result.continuationPoint);
    return UA_ByteString_copy(point, &operation->browse_result.continuationPoint) ==
               UA_STATUSCODE_GOOD &&
           wop_session_browse_capture(session, operation);
}

int main(void) {
    static WopSession session;
    WopService service;
    wop_session_service(&session, &service);
    UA_ByteString secret = UA_BYTESTRING("server-private-bytes");
    UA_ByteString other = UA_BYTESTRING("second-chain-bytes");
    if(!capture(&session, 0, 0, &secret) || !token_is(&session, 0, "c1") ||
       !UA_ByteString_equal(&session.browse_chains[0].point, &secret))
        return fail("first local token");

    /* A peer may reuse identical opaque bytes. The consumed public token must
     * still change while the bytes remain only in native-owned storage. */
    if(!capture(&session, 0, 0, &secret) || !token_is(&session, 0, "c2") ||
       !UA_ByteString_equal(&session.browse_chains[0].point, &secret))
        return fail("fresh token for reused bytes");

    /* A second chain is live at the same time with its own token and bytes. */
    if(!capture(&session, 4, 1, &other) || !token_is(&session, 1, "c3") ||
       !token_is(&session, 0, "c2"))
        return fail("second live chain");

    session.ready = true;
    WopSessionOperation *next = &session.operations[1];
    WopSessionOperation *second = &session.operations[5];
    next->session = second->session = &session;
    if(admit(&session, next, "c1", false) || admit(&session, next, "c1", true) ||
       admit(&session, next, "c02", false) || !session.browse_chains[0].active ||
       session.browse_chains[0].busy)
        return fail("foreign token admission");

    /* Each exact live token moves its server bytes into one operation and makes
     * only that chain busy; a second admission for the same token is rejected. */
    if(!admit(&session, next, "c2", false) || next->chain != 0 ||
       session.browse_chains[0].active || !session.browse_chains[0].busy ||
       !UA_ByteString_equal(&next->browse_point, &secret) ||
       admit(&session, &session.operations[2], "c2", true) ||
       !admit(&session, second, "c3", true) || second->chain != 1 ||
       !UA_ByteString_equal(&second->browse_point, &other) || !session.browse_chains[1].busy)
        return fail("live token consumption");

    /* Retiring queued BrowseNext before dispatch restores the unchanged
     * continuation instead of losing server state. */
    WopOperation queued = {0};
    queued.state = WOP_SLOT_QUEUED;
    queued.kind = WOP_OPERATION_BROWSE_NEXT;
    queued.index = 1;
    service.retire(service.context, &queued);
    if(!session.browse_chains[0].active || session.browse_chains[0].busy ||
       !session.browse_chains[0].used || session.browse_orphaned ||
       !UA_ByteString_equal(&session.browse_chains[0].point, &secret) ||
       !token_is(&session, 0, "c2"))
        return fail("queued retirement restores continuation");

    /* A completed release frees its chain for a later Browse. */
    WopOperation released = {0};
    released.state = WOP_SLOT_DISPATCHED;
    released.kind = WOP_OPERATION_BROWSE_RELEASE;
    released.index = 5;
    service.retire(service.context, &released);
    if(session.browse_chains[1].used || session.browse_chains[1].busy ||
       session.browse_orphaned || wop_session_browse_token(&session, 1, (char[32]){0}))
        return fail("release frees chain");

    WopSessionOperation *operation = &session.operations[0];
    session.browse_chains[0].pages = 64;
    if(wop_session_browse_capture(&session, operation) || session.browse_chains[0].active)
        return fail("page ceiling with live server point");
    session.browse_chains[0].pages = 0;

    operation->expose = false;
    operation->kind = WOP_OPERATION_READ;
    if(wop_session_browse_capture(&session, operation) || session.browse_chains[0].active ||
       session.browse_chains[0].point.length != 0)
        return fail("unhandled continuation closes instead of exposing bytes");

    /* Every one of 64 chains may be reserved; the next exposed Browse is busy
     * before any SDK request is built. */
    session.client = UA_Client_new();
    session.namespace_array = (UA_String *)UA_Array_new(1, &UA_TYPES[UA_TYPES_STRING]);
    if(!session.client || !session.namespace_array) return fail("client allocation");
    session.namespace_array[0] = UA_STRING_ALLOC("http://opcfoundation.org/UA/");
    session.namespace_count = 1;
    const char *browse = "{\"node_id\":\"ns=0;i=85\",\"reference_type_id\":\"ns=0;i=33\","
        "\"direction\":\"forward\",\"include_subtypes\":true,\"node_class_mask\":0,"
        "\"page_size\":1,\"allow_continuation\":true}";
    size_t length = strlen(browse);
    char *frame = malloc(length + 1);
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    WopJson parameters = {0};
    if(!frame || !pool) return fail("parameter allocation");
    memcpy(frame, browse, length);
    frame[length] = '\n';
    if(wop_json_read(frame, length + 1, pool, WOP_JSON_POOL_BYTES, &parameters) != WOP_JSON_OK)
        return fail("browse parameters");
    for(size_t i = 0; i < WOP_SESSION_CONTINUATIONS; i++) session.browse_chains[i].used = false;
    for(size_t i = 0; i <= WOP_SESSION_CONTINUATIONS; i++) {
        WopOperation admitted = {0};
        admitted.kind = WOP_OPERATION_BROWSE;
        admitted.index = i % WOP_OWNER_OPERATIONS;
        WopFailure failure = {0};
        bool prepared = service.prepare(service.context, &admitted,
                                        yyjson_doc_get_root(parameters.document), &failure);
        if(i < WOP_SESSION_CONTINUATIONS &&
           (!prepared || session.operations[admitted.index].chain != i ||
            !session.browse_chains[i].used || !session.browse_chains[i].busy))
            return fail("chain reservation");
        if(i == WOP_SESSION_CONTINUATIONS &&
           (prepared || !failure.code || strcmp(failure.code, "busy") != 0))
            return fail("65th chain admission");
    }
    wop_json_clear(&parameters);
    free(frame);
    free(pool);

    /* Retiring dispatched chain work leaves possible server state unowned. */
    WopOperation sent = {0};
    sent.state = WOP_SLOT_DISPATCHED;
    sent.kind = WOP_OPERATION_BROWSE_NEXT;
    sent.index = 3;
    session.operations[3].kind = WOP_OPERATION_BROWSE_NEXT;
    session.operations[3].chain = 3;
    session.operations[3].pending = true;
    service.retire(service.context, &sent);
    if(!session.browse_orphaned || service.released(service.context, &sent))
        return fail("dispatched retirement orphans continuation");

    session.operations[3].pending = false;
    (void)wop_session_close(&session);
    for(size_t i = 0; i < WOP_SESSION_CONTINUATIONS; i++)
        if(session.browse_chains[i].used) return fail("close clears chains");
    printf("{\"status\":\"passed\"}\n");
    return 0;
}
