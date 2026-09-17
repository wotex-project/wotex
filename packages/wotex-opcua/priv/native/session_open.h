/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_SESSION_OPEN_H
#define WOTEX_OPCUA_SESSION_OPEN_H

#include "owner.h"
#include "session_config.h"

typedef struct WopSession WopSession;

/* Per-slot SDK storage. The SDK callback userdata is this stable address and
 * every callback also matches the SDK request ID, so a late response for a
 * retired request can never attach to a later request in the same slot. */
typedef struct {
    WopSession *session;
    WopOperationKind kind;
    UA_UInt32 request_id;
    bool pending;
    bool delivered;
    bool abandoned;
    bool valid;
    bool remote_error;
    bool transport_error;
    bool timed_out;
    bool limit;
    UA_StatusCode status;
    UA_NodeId read_node;
    UA_DataValue read_value;
    UA_WriteValue write_value;
    UA_CallMethodRequest call_method;
    UA_CallMethodResult call_result;
    UA_BrowseDescription browse_description;
    UA_BrowseResult browse_result;
    UA_UInt32 page_size;
    bool expose;
    bool releasing;
    bool release_valid;
    UA_ByteString browse_point;
} WopSessionOperation;

struct WopSession {
    UA_Client *client;
    WopSecurity security;
    UA_String *namespace_array;
    size_t namespace_count;
    /* Client-local SDK namespace table size, sampled when the Session is ready. */
    size_t sdk_namespace_count;
    UA_Double revised_timeout_ms;
    uint64_t requested_timeout_ms;
    bool namespace_requested, namespace_received, namespace_valid, ready;
    WopSessionOperation operations[WOP_OWNER_OPERATIONS];
    /* One live server continuation and its cumulative chain bounds. */
    UA_ByteString browse_point;
    UA_UInt64 browse_serial;
    UA_UInt32 browse_page_size, browse_pages, browse_references;
    size_t browse_bytes;
    bool browse_active;
    /* A continuation-owning Browse, BrowseNext or release is unfinished. */
    bool browse_chain_busy;
    /* Continuation state may exist on the server without local ownership. */
    bool browse_orphaned;
};

/* Binds the SDK implementation of the owner service boundary. The session
 * storage must be zero-initialized and outlive the owner. */
void wop_session_service(WopSession *session, WopService *service);

/* Browse token state primitives, exposed for native state tests. */
bool wop_session_browse_token(const WopSession *session, char token[32]);
/* Moves a complete page's continuation into session ownership. false means an
 * unowned continuation or cumulative limit: the Session must close. */
bool wop_session_browse_capture(WopSession *session, WopSessionOperation *operation);
/* Admits BrowseNext or release only for the exact live local token. */
bool wop_session_browse_admit(WopSession *session, WopSessionOperation *operation,
                              yyjson_val *parameters, bool release);

/* WOP-X04 namespace projection for SDK values. The pinned SDK maps each decoded
 * NodeId namespace index, including ExpandedNodeId and encoded ExtensionObject
 * type identities, from the server table into its client-local table and back
 * on encode; QualifiedName indexes are not mapped. `publish` converts a
 * decoded value to server indexes and `localize` converts a public value to
 * SDK-local indexes. Indexes outside the server NamespaceArray use the SDK's
 * reversible out-of-table encoding and fail when it would collide with a
 * local table entry. Only NodeId, ExpandedNodeId, ExtensionObject, Variant,
 * DataValue, CallMethodResult and ReferenceDescription values are admitted.
 * The SDK namespace count must be sampled first. false leaves a partially
 * translated value that the caller must discard. */
bool wop_session_sample_namespaces(WopSession *session);
bool wop_session_publish(WopSession *session, const UA_DataType *type, void *data,
                         size_t count);
bool wop_session_localize(WopSession *session, const UA_DataType *type, void *data,
                          size_t count);

/* True only when the CloseSession/channel teardown completed cooperatively. */
bool wop_session_close(WopSession *session);

#endif
