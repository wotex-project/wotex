/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_SESSION_OPEN_H
#define WOTEX_OPCUA_SESSION_OPEN_H

#include "owner.h"
#include "publish_sequence.h"
#include "session_config.h"
#include "subscription_rules.h"

/* Subscription bounds for one Session. */
#define WOP_SESSION_SUBSCRIPTIONS 32U
#define WOP_SESSION_PUBLISH 4U
#define WOP_SESSION_NOTIFICATIONS 64U
#define WOP_SESSION_READY 256U
#define WOP_SESSION_HELD 4U
#define WOP_SESSION_ACKS 64U

typedef struct WopSession WopSession;

typedef struct {
    UA_NotificationMessage message;
} WopHeldMessage;

/* One established raw-service subscription with one Value MonitoredItem. */
typedef struct {
    bool used;
    bool closing;
    uint64_t serial;
    UA_UInt32 subscription_id;
    UA_UInt32 monitored_item_id;
    UA_UInt32 client_handle;
    WopSubscriptionParameters revised;
    int64_t activity_ms;
    WopSequence *sequence;
    UA_UInt32 acks[WOP_SESSION_ACKS];
    size_t ack_count;
    WopHeldMessage held[WOP_SESSION_HELD];
    size_t held_count;
    bool republish_pending;
    bool republish_delivered;
    UA_UInt32 republish_request_id;
    UA_UInt32 republish_sequence;
    UA_StatusCode republish_status;
    UA_NotificationMessage republished;
    /* A terminal subscription error awaiting its one report. */
    bool failed;
    const char *failure_code;
    bool failure_has_status;
    UA_StatusCode failure_status;
} WopSubscription;

/* One validated MonitoredItem notification awaiting report emission. */
typedef struct {
    size_t subscription;
    uint64_t serial;
    UA_UInt32 sequence;
    UA_DateTime publish_time;
    UA_UInt32 client_handle;
    UA_DataValue value;
} WopReadyReport;

#define WOP_SESSION_CONTINUATIONS 64

/* Optional SDK send hooks. Production leaves this NULL and calls the pinned SDK
 * directly; a native trace injects recording hooks with scripted responses. */
typedef struct WopSessionOperation WopSessionOperation;

typedef struct {
    void *context;
    UA_StatusCode (*browse)(void *context, WopSessionOperation *operation,
                            const UA_BrowseRequest *request);
    UA_StatusCode (*browse_next)(void *context, WopSessionOperation *operation,
                                 const UA_BrowseNextRequest *request);
    bool (*disconnect)(void *context);
    void (*cancel)(void *context, const WopSessionOperation *operation);
} WopSessionSdk;

/* One owned continuation chain. `used` covers a live continuation and any
 * unfinished operation that may create or consume one. */
typedef struct {
    UA_ByteString point;
    UA_UInt64 serial;
    UA_UInt32 page_size, pages, references;
    size_t bytes;
    bool used, active, busy;
} WopBrowseChain;

/* Per-slot SDK storage. The SDK callback userdata is this stable address and
 * every callback also matches the SDK request ID, so a late response for a
 * retired request can never attach to a later request in the same slot. */
struct WopSessionOperation {
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
    /* Index of the continuation chain a Browse, BrowseNext or release uses. */
    size_t chain;
    /* Subscribe and unsubscribe stages. */
    unsigned stage;
    WopSubscriptionParameters requested;
    WopSubscriptionParameters revised;
    UA_UInt32 created_subscription;
    UA_UInt32 monitored_item_id;
    UA_StatusCode item_status;
    size_t subscription;
    uint64_t serial;
};

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
    /* Up to 64 continuation chains, each with one live server continuation or
     * one unfinished Browse, BrowseNext or release, and its cumulative bounds. */
    WopBrowseChain browse_chains[WOP_SESSION_CONTINUATIONS];
    UA_UInt64 browse_serial;
    /* Continuation state may exist on the server without local ownership. */
    bool browse_orphaned;
    /* Injected SDK hooks for native traces; NULL in production. */
    const WopSessionSdk *sdk;
    WopSubscription subscriptions[WOP_SESSION_SUBSCRIPTIONS];
    uint64_t subscription_serial;
    WopReadyReport reports[WOP_SESSION_READY];
    size_t report_head, report_count;
    UA_PublishResponse inbox[WOP_SESSION_PUBLISH];
    size_t inbox_count;
    size_t publish_outstanding;
    size_t queued_frames;
    /* Subscription state may exist on the server without local ownership. */
    bool subscription_orphaned;
    bool publish_fault;
};

/* Binds the SDK implementation of the owner service boundary. The session
 * storage must be zero-initialized and outlive the owner. */
void wop_session_service(WopSession *session, WopService *service);

/* Browse token state primitives, exposed for native state tests. The token
 * names the live continuation of one chain. */
bool wop_session_browse_token(const WopSession *session, size_t chain, char token[32]);
/* Moves a complete page's continuation into session ownership. false means an
 * unowned continuation or cumulative limit: the Session must close. */
bool wop_session_browse_capture(WopSession *session, WopSessionOperation *operation);
/* Admits BrowseNext or release only for the exact live local token. */
bool wop_session_browse_admit(WopSession *session, WopSessionOperation *operation,
                              yyjson_val *parameters, bool release);

/* Namespace projection for SDK values. The pinned SDK maps each decoded
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
