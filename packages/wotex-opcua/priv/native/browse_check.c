/* SPDX-License-Identifier: Apache-2.0 */
#include "session_open.h"
#include <stdio.h>
#include <string.h>

static int fail(const char *message) {
    fprintf(stderr, "browse state: %s\n", message);
    return 1;
}

int main(void) {
    WopSession session = {0};
    char token[32] = {0};
    UA_ByteString secret = UA_BYTESTRING("server-private-bytes");
    if(UA_ByteString_copy(&secret, &session.browse_result.continuationPoint) != UA_STATUSCODE_GOOD)
        return fail("allocation");
    session.browse_valid = true;
    session.browse_expose = true;
    if(!wop_session_browse_capture(&session) ||
       !wop_session_browse_token(&session, token) || strcmp(token, "c1") != 0 ||
       !UA_ByteString_equal(&session.browse_point, &secret))
        return fail("first local token");

    /* A peer may reuse identical opaque bytes. The consumed public token must
     * still change while the bytes remain only in native-owned storage. */
    if(!wop_session_browse_capture(&session) ||
       !wop_session_browse_token(&session, token) || strcmp(token, "c2") != 0 ||
       !UA_ByteString_equal(&session.browse_point, &secret))
        return fail("fresh token for reused bytes");

    session.ready = true;
    yyjson_doc *foreign = yyjson_read("{\"continuation\":\"c1\"}", 21, 0);
    if(!foreign || wop_session_browse_next(&session, yyjson_doc_get_root(foreign), false) ||
       wop_session_browse_next(&session, yyjson_doc_get_root(foreign), true) ||
       !session.browse_active) return fail("foreign token admission");
    yyjson_doc_free(foreign);

    session.browse_pages = 64;
    if(wop_session_browse_capture(&session) || session.browse_active)
        return fail("page ceiling with live server point");
    session.browse_pages = 0;

    session.browse_expose = false;
    if(wop_session_browse_capture(&session) || session.browse_active ||
       session.browse_point.length != 0)
        return fail("unhandled continuation closes instead of exposing bytes");

    UA_BrowseResult_clear(&session.browse_result);
    UA_ByteString_clear(&session.browse_point);
    return 0;
}
