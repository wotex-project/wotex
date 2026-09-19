/* SPDX-License-Identifier: Apache-2.0
 * Raw-service subscriptions: CreateSubscription and one Value
 * MonitoredItem per handle, an owner-driven Publish loop with validated
 * acknowledgements, ordered Republish recovery, lifetime loss detection and
 * explicit deletion. The SDK's high-level subscription manager is never used.
 */
#include "session_internal.h"
#include "value_codec.h"

#include <open62541/client_highlevel_async.h>
#include <openssl/evp.h>
#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void ignore_response(UA_Client *client, void *userdata, UA_UInt32 request_id,
                            void *response) {
    (void)client; (void)userdata; (void)request_id; (void)response;
}

/* Best-effort server cleanup after a local failure; the Session close or
 * server lifetime remains the bound when this request cannot complete. */
static void delete_remote(WopSession *session, UA_UInt32 subscription_id) {
    if(!session->client || !subscription_id) return;
    UA_DeleteSubscriptionsRequest request;
    UA_DeleteSubscriptionsRequest_init(&request);
    request.requestHeader.timeoutHint = 1000;
    request.subscriptionIds = &subscription_id;
    request.subscriptionIdsSize = 1;
    (void)__UA_Client_AsyncService(session->client, &request,
        &UA_TYPES[UA_TYPES_DELETESUBSCRIPTIONSREQUEST], ignore_response,
        &UA_TYPES[UA_TYPES_DELETESUBSCRIPTIONSRESPONSE], NULL, NULL);
}

static WopSubscription *find_serial(WopSession *session, yyjson_val *token, size_t *index) {
    if(!yyjson_is_str(token)) return NULL;
    const char *text = yyjson_get_str(token);
    size_t length = yyjson_get_len(token);
    if(length < 2 || length > 21 || text[0] != 's' || text[1] == '0') return NULL;
    uint64_t serial = 0;
    for(size_t i = 1; i < length; i++) {
        if(text[i] < '0' || text[i] > '9' || serial > (UINT64_MAX - (uint64_t)(text[i] - '0')) / 10U)
            return NULL;
        serial = serial * 10U + (uint64_t)(text[i] - '0');
    }
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS; i++) {
        WopSubscription *subscription = &session->subscriptions[i];
        if(subscription->used && subscription->serial == serial) {
            *index = i;
            return subscription;
        }
    }
    return NULL;
}

static size_t reserved(const WopSession *session) {
    size_t count = 0;
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS; i++)
        if(session->subscriptions[i].used) count++;
    for(size_t i = 0; i < WOP_OWNER_OPERATIONS; i++) {
        const WopSessionOperation *operation = &session->operations[i];
        if(operation->kind == WOP_OPERATION_SUBSCRIBE && operation->serial) count++;
    }
    return count;
}

bool wop_subscription_prepare(WopSession *session, WopSessionOperation *operation,
                              yyjson_val *parameters, WopFailure *failure) {
    if(operation->kind == WOP_OPERATION_UNSUBSCRIBE) {
        size_t index = 0;
        WopSubscription *subscription;
        if(!yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 1 ||
           !(subscription = find_serial(session, yyjson_obj_get(parameters, "subscription"), &index)) ||
           subscription->closing || subscription->failed)
            return false;
        subscription->closing = true;
        operation->subscription = index;
        return true;
    }
    if(!wop_subscription_read(parameters, &operation->requested)) return false;
    if(reserved(session) >= WOP_SESSION_SUBSCRIPTIONS ||
       session->subscription_serial >= UINT32_MAX) {
        wop_fail(failure, "busy", "admission", false);
        return false;
    }
    _Alignas(max_align_t) unsigned char storage[8192];
    WopValueArena arena;
    UA_NodeId node = UA_NODEID_NULL;
    bool valid = wop_value_arena_init(&arena, storage, sizeof(storage)) &&
                 wop_session_translate(session, yyjson_obj_get(parameters, "node_id"), &arena, &node) &&
                 UA_NodeId_copy(&node, &operation->read_node) == UA_STATUSCODE_GOOD;
    wop_value_arena_reset(&arena);
    /* The serial is also the MonitoredItem client handle; it is never reused. */
    if(valid) operation->serial = ++session->subscription_serial;
    return valid;
}

static void receive_create_subscription(UA_Client *client, void *userdata, UA_UInt32 request_id,
                                        void *raw) {
    (void)client;
    WopSessionOperation *operation = userdata;
    UA_CreateSubscriptionResponse *response = raw;
    if(!wop_session_accept(operation, request_id, response ? &response->responseHeader : NULL))
        return;
    /* NOLINTNEXTLINE(clang-analyzer-core.NullDereference): wop_session_accept is true only for a non-NULL response */
    operation->created_subscription = response->subscriptionId;
    operation->revised.publishing_interval_ms = response->revisedPublishingInterval;
    operation->revised.lifetime_count = response->revisedLifetimeCount;
    operation->revised.keepalive_count = response->revisedMaxKeepAliveCount;
    operation->valid = response->subscriptionId != 0;
}

static void receive_create_items(UA_Client *client, void *userdata, UA_UInt32 request_id,
                                 void *raw) {
    (void)client;
    WopSessionOperation *operation = userdata;
    UA_CreateMonitoredItemsResponse *response = raw;
    if(!wop_session_accept(operation, request_id, response ? &response->responseHeader : NULL))
        return;
    /* NOLINTNEXTLINE(clang-analyzer-core.NullDereference): wop_session_accept is true only for a non-NULL response */
    if(response->resultsSize != 1 || !response->results) return;
    const UA_MonitoredItemCreateResult *result = &response->results[0];
    operation->item_status = result->statusCode;
    operation->monitored_item_id = result->monitoredItemId;
    operation->revised.sampling_interval_ms = result->revisedSamplingInterval;
    operation->revised.queue_size = result->revisedQueueSize;
    operation->valid = true;
}

static void receive_delete(UA_Client *client, void *userdata, UA_UInt32 request_id, void *raw) {
    (void)client;
    WopSessionOperation *operation = userdata;
    /* DeleteMonitoredItems and DeleteSubscriptions responses share the same
     * leading header/result shape after their service-specific types. */
    if(operation->stage == 0) {
        UA_DeleteMonitoredItemsResponse *response = raw;
        if(!wop_session_accept(operation, request_id, response ? &response->responseHeader : NULL))
            return;
        /* NOLINTNEXTLINE(clang-analyzer-core.NullDereference): wop_session_accept is true only for a non-NULL response */
        operation->valid = response->resultsSize == 1 && response->results &&
                           response->results[0] == UA_STATUSCODE_GOOD;
    } else {
        UA_DeleteSubscriptionsResponse *response = raw;
        if(!wop_session_accept(operation, request_id, response ? &response->responseHeader : NULL))
            return;
        /* NOLINTNEXTLINE(clang-analyzer-core.NullDereference): wop_session_accept is true only for a non-NULL response */
        operation->valid = response->resultsSize == 1 && response->results &&
                           response->results[0] == UA_STATUSCODE_GOOD;
    }
}

static bool send_create_items(WopSession *session, WopSessionOperation *operation) {
    UA_MonitoredItemCreateRequest item;
    UA_MonitoredItemCreateRequest_init(&item);
    item.itemToMonitor.nodeId = operation->read_node;
    item.itemToMonitor.attributeId = UA_ATTRIBUTEID_VALUE;
    item.monitoringMode = UA_MONITORINGMODE_REPORTING;
    item.requestedParameters.clientHandle = (UA_UInt32)operation->serial;
    item.requestedParameters.samplingInterval = operation->requested.sampling_interval_ms;
    item.requestedParameters.queueSize = operation->requested.queue_size;
    item.requestedParameters.discardOldest = operation->requested.discard_oldest;
    UA_CreateMonitoredItemsRequest request;
    UA_CreateMonitoredItemsRequest_init(&request);
    request.requestHeader.timeoutHint = 60000;
    request.subscriptionId = operation->created_subscription;
    request.timestampsToReturn = UA_TIMESTAMPSTORETURN_BOTH;
    request.itemsToCreate = &item;
    request.itemsToCreateSize = 1;
    operation->pending = true;
    operation->delivered = false;
    operation->valid = false;
    operation->stage = 1;
    UA_StatusCode status = __UA_Client_AsyncService(session->client, &request,
        &UA_TYPES[UA_TYPES_CREATEMONITOREDITEMSREQUEST], receive_create_items,
        &UA_TYPES[UA_TYPES_CREATEMONITOREDITEMSRESPONSE], operation, &operation->request_id);
    if(status != UA_STATUSCODE_GOOD) operation->pending = false;
    return status == UA_STATUSCODE_GOOD;
}

bool wop_subscription_dispatch(WopSession *session, WopSessionOperation *operation,
                               const UA_RequestHeader *header) {
    UA_StatusCode status;
    operation->stage = 0;
    if(operation->kind == WOP_OPERATION_SUBSCRIBE) {
        UA_CreateSubscriptionRequest request;
        UA_CreateSubscriptionRequest_init(&request);
        request.requestHeader = *header;
        request.requestedPublishingInterval = operation->requested.publishing_interval_ms;
        request.requestedLifetimeCount = operation->requested.lifetime_count;
        request.requestedMaxKeepAliveCount = operation->requested.keepalive_count;
        request.maxNotificationsPerPublish = WOP_SESSION_NOTIFICATIONS;
        request.publishingEnabled = true;
        status = __UA_Client_AsyncService(session->client, &request,
            &UA_TYPES[UA_TYPES_CREATESUBSCRIPTIONREQUEST], receive_create_subscription,
            &UA_TYPES[UA_TYPES_CREATESUBSCRIPTIONRESPONSE], operation, &operation->request_id);
    } else {
        WopSubscription *subscription = &session->subscriptions[operation->subscription];
        UA_DeleteMonitoredItemsRequest request;
        UA_DeleteMonitoredItemsRequest_init(&request);
        request.requestHeader = *header;
        request.subscriptionId = subscription->subscription_id;
        request.monitoredItemIds = &subscription->monitored_item_id;
        request.monitoredItemIdsSize = 1;
        status = __UA_Client_AsyncService(session->client, &request,
            &UA_TYPES[UA_TYPES_DELETEMONITOREDITEMSREQUEST], receive_delete,
            &UA_TYPES[UA_TYPES_DELETEMONITOREDITEMSRESPONSE], operation, &operation->request_id);
    }
    return status == UA_STATUSCODE_GOOD;
}

static void free_subscription(WopSession *session, size_t index) {
    WopSubscription *subscription = &session->subscriptions[index];
    /* Drop reports that were not emitted before this subscription ended. */
    size_t kept = 0;
    for(size_t i = 0; i < session->report_count; i++) {
        WopReadyReport *report = &session->reports[(session->report_head + i) % WOP_SESSION_READY];
        if(report->subscription == index && report->serial == subscription->serial) {
            UA_DataValue_clear(&report->value);
            continue;
        }
        WopReadyReport *target = &session->reports[(session->report_head + kept) % WOP_SESSION_READY];
        if(target != report) {
            *target = *report;
            memset(report, 0, sizeof(*report));
        }
        kept++;
    }
    session->report_count = kept;
    for(size_t i = 0; i < subscription->held_count; i++)
        UA_NotificationMessage_clear(&subscription->held[i].message);
    UA_NotificationMessage_clear(&subscription->republished);
    free(subscription->sequence);
    memset(subscription, 0, sizeof(*subscription));
}

static bool write_parameters(yyjson_mut_doc *document, yyjson_mut_val *object,
                             const WopSubscriptionParameters *value) {
    return yyjson_mut_obj_add_real(document, object, "publishing_interval_ms",
                                   value->publishing_interval_ms) &&
           yyjson_mut_obj_add_real(document, object, "sampling_interval_ms",
                                   value->sampling_interval_ms) &&
           yyjson_mut_obj_add_uint(document, object, "queue_size", value->queue_size) &&
           yyjson_mut_obj_add_uint(document, object, "lifetime_count", value->lifetime_count) &&
           yyjson_mut_obj_add_uint(document, object, "keepalive_count", value->keepalive_count);
}

static WopCompletion subscribe_complete(WopSession *session, WopSessionOperation *operation,
                                        yyjson_mut_doc *document, yyjson_mut_val **result,
                                        WopFailure *failure) {
    if(operation->stage == 0) {
        if(operation->remote_error || !operation->valid) {
            if(operation->remote_error)
                wop_fail_status(failure, "remote_error", "exchange", false, operation->status);
            else
                wop_fail(failure, "invalid_response", "decode", false);
            if(operation->created_subscription) delete_remote(session, operation->created_subscription);
            operation->created_subscription = 0;
            return WOP_COMPLETION_FAILURE;
        }
        if(!send_create_items(session, operation)) {
            delete_remote(session, operation->created_subscription);
            operation->created_subscription = 0;
            wop_fail(failure, "connection_failed", "exchange", false);
            return WOP_COMPLETION_FAILURE;
        }
        return WOP_COMPLETION_PENDING;
    }
    UA_UInt32 remote = operation->created_subscription;
    if(operation->remote_error || !operation->valid ||
       (operation->item_status & 0x80000000U) || !operation->monitored_item_id ||
       !wop_subscription_revision_valid(&operation->revised)) {
        if(operation->remote_error)
            wop_fail_status(failure, "remote_error", "exchange", false, operation->status);
        else if(operation->valid && (operation->item_status & 0x80000000U))
            wop_fail_status(failure, "remote_error", "exchange", false, operation->item_status);
        else
            wop_fail(failure, "invalid_response", "decode", false);
        delete_remote(session, remote);
        operation->created_subscription = 0;
        return WOP_COMPLETION_FAILURE;
    }
    size_t index = WOP_SESSION_SUBSCRIPTIONS;
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS && index == WOP_SESSION_SUBSCRIPTIONS; i++)
        if(!session->subscriptions[i].used) index = i;
    WopSequence *sequence = index < WOP_SESSION_SUBSCRIPTIONS ? malloc(sizeof(*sequence)) : NULL;
    if(!sequence) {
        free(sequence);
        delete_remote(session, remote);
        operation->created_subscription = 0;
        wop_fail(failure, "busy", "admission", false);
        return WOP_COMPLETION_FAILURE;
    }
    char token[24];
    uint64_t serial = operation->serial;
    (void)snprintf(token, sizeof(token), "s%" PRIu64, serial);
    yyjson_mut_val *object = yyjson_mut_obj(document);
    if(!object || !yyjson_mut_obj_add_strcpy(document, object, "subscription", token) ||
       !yyjson_mut_obj_add_uint(document, object, "subscription_id", remote) ||
       !yyjson_mut_obj_add_uint(document, object, "monitored_item_id", operation->monitored_item_id) ||
       !yyjson_mut_obj_add_uint(document, object, "client_handle", (uint64_t)serial) ||
       !write_parameters(document, object, &operation->revised) ||
       !yyjson_mut_obj_add_uint(document, object, "item_status", operation->item_status)) {
        free(sequence);
        delete_remote(session, remote);
        operation->created_subscription = 0;
        wop_fail(failure, "response_limit", "decode", false);
        return WOP_COMPLETION_FAILURE;
    }
    WopSubscription *subscription = &session->subscriptions[index];
    memset(subscription, 0, sizeof(*subscription));
    subscription->used = true;
    subscription->serial = serial;
    subscription->subscription_id = remote;
    subscription->monitored_item_id = operation->monitored_item_id;
    subscription->client_handle = (UA_UInt32)serial;
    subscription->revised = operation->revised;
    subscription->activity_ms = wop_session_clock();
    subscription->sequence = sequence;
    wop_sequence_init(sequence, 0);
    operation->created_subscription = 0;
    operation->serial = 0;
    *result = object;
    return WOP_COMPLETION_SUCCESS;
}

static WopCompletion unsubscribe_complete(WopSession *session, WopSessionOperation *operation,
                                          yyjson_mut_doc *document, yyjson_mut_val **result,
                                          WopFailure *failure) {
    WopSubscription *subscription = &session->subscriptions[operation->subscription];
    if(operation->remote_error || !operation->valid) {
        /* A failed delete leaves server state that only Session close can bound. */
        if(operation->remote_error)
            wop_fail_status(failure, "cleanup_failed", "cleanup", false, operation->status);
        else
            wop_fail(failure, "cleanup_failed", "cleanup", false);
        return WOP_COMPLETION_TERMINAL;
    }
    if(operation->stage == 0) {
        UA_DeleteSubscriptionsRequest request;
        UA_DeleteSubscriptionsRequest_init(&request);
        request.requestHeader.timeoutHint = 60000;
        request.subscriptionIds = &subscription->subscription_id;
        request.subscriptionIdsSize = 1;
        operation->stage = 1;
        operation->pending = true;
        operation->delivered = false;
        operation->valid = false;
        if(__UA_Client_AsyncService(session->client, &request,
               &UA_TYPES[UA_TYPES_DELETESUBSCRIPTIONSREQUEST], receive_delete,
               &UA_TYPES[UA_TYPES_DELETESUBSCRIPTIONSRESPONSE], operation,
               &operation->request_id) != UA_STATUSCODE_GOOD) {
            operation->pending = false;
            wop_fail(failure, "cleanup_failed", "cleanup", false);
            return WOP_COMPLETION_TERMINAL;
        }
        return WOP_COMPLETION_PENDING;
    }
    free_subscription(session, operation->subscription);
    *result = yyjson_mut_null(document);
    return *result ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
}

WopCompletion wop_subscription_complete(WopSession *session, WopSessionOperation *operation,
                                        yyjson_mut_doc *document, yyjson_mut_val **result,
                                        WopFailure *failure) {
    return operation->kind == WOP_OPERATION_SUBSCRIBE ?
           subscribe_complete(session, operation, document, result, failure) :
           unsubscribe_complete(session, operation, document, result, failure);
}

void wop_subscription_retire(WopSession *session, WopSessionOperation *operation) {
    if(operation->kind == WOP_OPERATION_SUBSCRIBE) {
        if(operation->created_subscription) delete_remote(session, operation->created_subscription);
        /* A CreateSubscription still in flight may create unowned server state. */
        if(operation->pending && operation->stage == 0) session->subscription_orphaned = true;
        operation->created_subscription = 0;
        return;
    }
    WopSubscription *subscription = &session->subscriptions[operation->subscription];
    if(!subscription->used) return;
    if(operation->pending || operation->delivered || operation->stage) {
        /* Deletion was sent without a confirmed result. */
        session->subscription_orphaned = true;
    } else {
        subscription->closing = false;
    }
}

/* SHA-256 over the ordered binary notification payload. */
static bool digest_message(const UA_NotificationMessage *message,
                           unsigned char digest[WOP_SEQUENCE_DIGEST]) {
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    bool valid = context && EVP_DigestInit_ex(context, EVP_sha256(), NULL) == 1;
    for(size_t i = 0; valid && i < message->notificationDataSize; i++) {
        UA_ByteString bytes = UA_BYTESTRING_NULL;
        valid = UA_encodeBinary(&message->notificationData[i],
                                &UA_TYPES[UA_TYPES_EXTENSIONOBJECT], &bytes, NULL) ==
                    UA_STATUSCODE_GOOD &&
                EVP_DigestUpdate(context, bytes.data, bytes.length) == 1;
        UA_ByteString_clear(&bytes);
    }
    unsigned int length = 0;
    valid = valid && EVP_DigestFinal_ex(context, digest, &length) == 1 &&
            length == WOP_SEQUENCE_DIGEST;
    EVP_MD_CTX_free(context);
    return valid;
}

static void fail_subscription(WopSubscription *subscription, const char *code,
                              bool has_status, UA_StatusCode status) {
    if(subscription->failed) return;
    subscription->failed = true;
    subscription->failure_code = code;
    subscription->failure_has_status = has_status;
    subscription->failure_status = status;
}

static void add_ack(WopSubscription *subscription, UA_UInt32 sequence) {
    for(size_t i = 0; i < subscription->ack_count; i++)
        if(subscription->acks[i] == sequence) return;
    if(subscription->ack_count < WOP_SESSION_ACKS)
        subscription->acks[subscription->ack_count++] = sequence;
}

/* Validates a complete data-change message and enqueues its notifications. */
static bool enqueue(WopSession *session, size_t index, const UA_NotificationMessage *message) {
    WopSubscription *subscription = &session->subscriptions[index];
    size_t items = 0;
    for(size_t i = 0; i < message->notificationDataSize; i++) {
        const UA_ExtensionObject *data = &message->notificationData[i];
        if(data->encoding != UA_EXTENSIONOBJECT_DECODED ||
           data->content.decoded.type == &UA_TYPES[UA_TYPES_STATUSCHANGENOTIFICATION]) {
            UA_StatusCode status = UA_STATUSCODE_BADUNEXPECTEDERROR;
            if(data->encoding == UA_EXTENSIONOBJECT_DECODED)
                status = ((UA_StatusChangeNotification *)data->content.decoded.data)->status;
            fail_subscription(subscription, "subscription_lost", true, status);
            return false;
        }
        if(data->content.decoded.type != &UA_TYPES[UA_TYPES_DATACHANGENOTIFICATION]) {
            fail_subscription(subscription, "invalid_response", false, 0);
            return false;
        }
        const UA_DataChangeNotification *change = data->content.decoded.data;
        for(size_t j = 0; j < change->monitoredItemsSize; j++) {
            if(change->monitoredItems[j].clientHandle != subscription->client_handle) {
                fail_subscription(subscription, "invalid_response", false, 0);
                return false;
            }
        }
        items += change->monitoredItemsSize;
    }
    if(items > WOP_SESSION_READY - session->report_count) {
        fail_subscription(subscription, "receiver_overflow", false, 0);
        return false;
    }
    for(size_t i = 0; i < message->notificationDataSize; i++) {
        const UA_DataChangeNotification *change = message->notificationData[i].content.decoded.data;
        for(size_t j = 0; j < change->monitoredItemsSize; j++) {
            WopReadyReport *report =
                &session->reports[(session->report_head + session->report_count) % WOP_SESSION_READY];
            memset(report, 0, sizeof(*report));
            if(UA_DataValue_copy(&change->monitoredItems[j].value, &report->value) !=
               UA_STATUSCODE_GOOD) {
                fail_subscription(subscription, "response_limit", false, 0);
                return false;
            }
            report->subscription = index;
            report->serial = subscription->serial;
            report->sequence = message->sequenceNumber;
            report->publish_time = message->publishTime;
            report->client_handle = subscription->client_handle;
            session->report_count++;
        }
    }
    return true;
}

static void process_message(WopSession *session, size_t index, const UA_NotificationMessage *message);

static void release_held(WopSession *session, size_t index) {
    WopSubscription *subscription = &session->subscriptions[index];
    size_t count = subscription->held_count;
    WopHeldMessage held[WOP_SESSION_HELD];
    memcpy(held, subscription->held, sizeof(held));
    memset(subscription->held, 0, sizeof(subscription->held));
    subscription->held_count = 0;
    for(size_t i = 0; i < count; i++) {
        if(subscription->used && !subscription->failed)
            process_message(session, index, &held[i].message);
        UA_NotificationMessage_clear(&held[i].message);
    }
}

static void process_message(WopSession *session, size_t index, const UA_NotificationMessage *message) {
    WopSubscription *subscription = &session->subscriptions[index];
    if(subscription->failed || subscription->closing) return;
    unsigned char digest[WOP_SEQUENCE_DIGEST];
    if(!digest_message(message, digest)) {
        fail_subscription(subscription, "response_limit", false, 0);
        return;
    }
    if(subscription->sequence->recovering) {
        if(subscription->held_count == WOP_SESSION_HELD ||
           UA_NotificationMessage_copy(message, &subscription->held[subscription->held_count].message) !=
               UA_STATUSCODE_GOOD) {
            fail_subscription(subscription, "sequence_gap", false, 0);
            return;
        }
        subscription->held_count++;
        return;
    }
    uint32_t first = 0, missing = 0;
    switch(wop_sequence_classify(subscription->sequence, message->sequenceNumber, digest, &first,
                                 &missing)) {
    case WOP_SEQUENCE_DELIVER:
        if(enqueue(session, index, message) &&
           wop_sequence_record(subscription->sequence, message->sequenceNumber, digest))
            add_ack(subscription, message->sequenceNumber);
        return;
    case WOP_SEQUENCE_DUPLICATE:
        add_ack(subscription, message->sequenceNumber);
        return;
    case WOP_SEQUENCE_GAP:
        if(!wop_sequence_begin(subscription->sequence, message->sequenceNumber, digest, first, missing) ||
           UA_NotificationMessage_copy(message, &subscription->held[0].message) != UA_STATUSCODE_GOOD) {
            fail_subscription(subscription, "sequence_gap", false, 0);
            return;
        }
        subscription->held_count = 1;
        return;
    default:
        fail_subscription(subscription, "sequence_gap", false, 0);
        return;
    }
}

static void receive_publish(UA_Client *client, void *userdata, UA_UInt32 request_id, void *raw) {
    (void)client; (void)request_id;
    WopSession *session = userdata;
    if(session->publish_outstanding) session->publish_outstanding--;
    UA_PublishResponse *response = raw;
    if(!response || session->inbox_count == WOP_SESSION_PUBLISH ||
       UA_PublishResponse_copy(response, &session->inbox[session->inbox_count]) != UA_STATUSCODE_GOOD) {
        session->publish_fault = true;
        return;
    }
    session->inbox_count++;
}

static WopSubscription *by_remote(WopSession *session, UA_UInt32 id, size_t *index) {
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS; i++) {
        if(session->subscriptions[i].used && session->subscriptions[i].subscription_id == id) {
            *index = i;
            return &session->subscriptions[i];
        }
    }
    return NULL;
}

/* Returns false for a Session-wide Publish fault. */
static bool process_publish(WopSession *session, UA_PublishResponse *response, WopFailure *failure) {
    UA_StatusCode result = response->responseHeader.serviceResult;
    if(result == UA_STATUSCODE_BADTIMEOUT || result == UA_STATUSCODE_BADNOSUBSCRIPTION ||
       result == UA_STATUSCODE_BADTOOMANYPUBLISHREQUESTS || result == UA_STATUSCODE_BADSHUTDOWN)
        return true;
    if(result != UA_STATUSCODE_GOOD) {
        wop_fail_status(failure, "invalid_response", "exchange", false, result);
        return false;
    }
    for(size_t i = 0; i < response->resultsSize; i++) {
        UA_StatusCode ack = response->results[i];
        if(ack != UA_STATUSCODE_GOOD && ack != UA_STATUSCODE_BADSEQUENCENUMBERUNKNOWN &&
           ack != UA_STATUSCODE_BADSUBSCRIPTIONIDINVALID) {
            wop_fail_status(failure, "invalid_response", "exchange", false, ack);
            return false;
        }
    }
    size_t index = 0;
    WopSubscription *subscription = by_remote(session, response->subscriptionId, &index);
    if(!subscription) return true;
    subscription->activity_ms = wop_session_clock();
    if(response->notificationMessage.notificationDataSize == 0) return true;
    process_message(session, index, &response->notificationMessage);
    return true;
}

static void receive_republish(UA_Client *client, void *userdata, UA_UInt32 request_id, void *raw) {
    (void)client;
    WopSubscription *subscription = userdata;
    UA_RepublishResponse *response = raw;
    if(!subscription->used || !subscription->republish_pending ||
       request_id != subscription->republish_request_id)
        return;
    subscription->republish_pending = false;
    subscription->republish_delivered = true;
    subscription->republish_status = response ? response->responseHeader.serviceResult :
                                                UA_STATUSCODE_BADUNEXPECTEDERROR;
    if(response && subscription->republish_status == UA_STATUSCODE_GOOD &&
       UA_NotificationMessage_copy(&response->notificationMessage, &subscription->republished) !=
           UA_STATUSCODE_GOOD)
        subscription->republish_status = UA_STATUSCODE_BADOUTOFMEMORY;
}

static void advance_recovery(WopSession *session, size_t index) {
    WopSubscription *subscription = &session->subscriptions[index];
    if(subscription->failed || !subscription->sequence->recovering) return;
    if(subscription->republish_delivered) {
        subscription->republish_delivered = false;
        unsigned char digest[WOP_SEQUENCE_DIGEST] = {0};
        bool available = subscription->republish_status == UA_STATUSCODE_GOOD &&
                         digest_message(&subscription->republished, digest);
        UA_UInt32 requested = subscription->republish_sequence;
        WopRecovery recovery = wop_sequence_republished(subscription->sequence, requested, available,
            subscription->republished.sequenceNumber, digest);
        bool delivered = recovery != WOP_RECOVERY_FAILED &&
                         enqueue(session, index, &subscription->republished);
        UA_NotificationMessage_clear(&subscription->republished);
        if(recovery == WOP_RECOVERY_FAILED) {
            fail_subscription(subscription, "sequence_gap",
                              subscription->republish_status != UA_STATUSCODE_GOOD,
                              subscription->republish_status);
            return;
        }
        if(!delivered) return;
        add_ack(subscription, requested);
        if(recovery == WOP_RECOVERY_COMPLETE) {
            WopHeldMessage target = subscription->held[0];
            memmove(subscription->held, subscription->held + 1,
                    (subscription->held_count - 1) * sizeof(subscription->held[0]));
            subscription->held_count--;
            memset(&subscription->held[subscription->held_count], 0, sizeof(subscription->held[0]));
            unsigned char target_digest[WOP_SEQUENCE_DIGEST];
            memcpy(target_digest, subscription->sequence->target_digest, sizeof(target_digest));
            if(enqueue(session, index, &target.message) &&
               wop_sequence_record(subscription->sequence, target.message.sequenceNumber,
                                   target_digest))
                add_ack(subscription, target.message.sequenceNumber);
            UA_NotificationMessage_clear(&target.message);
            release_held(session, index);
            return;
        }
    }
    uint32_t next = 0;
    if(subscription->republish_pending || !wop_sequence_pending(subscription->sequence, &next))
        return;
    UA_RepublishRequest request;
    UA_RepublishRequest_init(&request);
    request.requestHeader.timeoutHint = 60000;
    request.subscriptionId = subscription->subscription_id;
    request.retransmitSequenceNumber = next;
    subscription->republish_sequence = next;
    subscription->republish_pending = true;
    if(__UA_Client_AsyncService(session->client, &request, &UA_TYPES[UA_TYPES_REPUBLISHREQUEST],
           receive_republish, &UA_TYPES[UA_TYPES_REPUBLISHRESPONSE], subscription,
           &subscription->republish_request_id) != UA_STATUSCODE_GOOD) {
        subscription->republish_pending = false;
        fail_subscription(subscription, "connection_failed", false, 0);
    }
}

/* Returns the SDK status of the Publish submission, so a Session that has
 * already lost its channel ends its subscriptions with that Bad status. */
static UA_StatusCode send_publish(WopSession *session) {
    UA_SubscriptionAcknowledgement acks[WOP_SESSION_ACKS];
    size_t count = 0;
    double keepalive = 0;
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS; i++) {
        WopSubscription *subscription = &session->subscriptions[i];
        if(!subscription->used) continue;
        double period = subscription->revised.publishing_interval_ms *
                        (double)subscription->revised.keepalive_count;
        if(period > keepalive) keepalive = period;
        size_t taken = 0;
        while(taken < subscription->ack_count && count < WOP_SESSION_ACKS) {
            acks[count].subscriptionId = subscription->subscription_id;
            acks[count].sequenceNumber = subscription->acks[taken++];
            count++;
        }
        memmove(subscription->acks, subscription->acks + taken,
                (subscription->ack_count - taken) * sizeof(subscription->acks[0]));
        subscription->ack_count -= taken;
    }
    UA_PublishRequest request;
    UA_PublishRequest_init(&request);
    double hint = keepalive * 3.0 + 5000.0;
    request.requestHeader.timeoutHint = hint > 600000.0 ? 600000U : (UA_UInt32)hint;
    request.subscriptionAcknowledgements = count ? acks : NULL;
    request.subscriptionAcknowledgementsSize = count;
    UA_StatusCode status = __UA_Client_AsyncService(session->client, &request,
                                                    &UA_TYPES[UA_TYPES_PUBLISHREQUEST],
                                                    receive_publish,
                                                    &UA_TYPES[UA_TYPES_PUBLISHRESPONSE], session,
                                                    NULL);
    if (status != UA_STATUSCODE_GOOD) return status;
    session->publish_outstanding++;
    return UA_STATUSCODE_GOOD;
}

bool wop_subscription_step(WopSession *session, WopFailure *failure) {
    if(session->subscription_orphaned) {
        wop_fail(failure, "cleanup_failed", "cleanup", false);
        return false;
    }
    if(session->publish_fault) {
        wop_fail(failure, "response_limit", "exchange", false);
        return false;
    }
    size_t inbox = session->inbox_count;
    bool valid = true;
    for(size_t i = 0; i < inbox; i++) {
        if(valid) valid = process_publish(session, &session->inbox[i], failure);
        UA_PublishResponse_clear(&session->inbox[i]);
    }
    session->inbox_count = 0;
    if(!valid) return false;
    size_t active = 0;
    int64_t now = wop_session_clock();
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS; i++) {
        WopSubscription *subscription = &session->subscriptions[i];
        if(!subscription->used) continue;
        advance_recovery(session, i);
        double lifetime = subscription->revised.publishing_interval_ms *
                          (double)subscription->revised.lifetime_count;
        if(!subscription->failed && now >= 0 &&
           (double)(now - subscription->activity_ms) > lifetime)
            fail_subscription(subscription, "subscription_lost", false, 0);
        if(!subscription->closing && !subscription->failed) active++;
    }
    /* Request more notifications only when every earlier one was emitted. */
    while(active && session->report_count == 0 && session->queued_frames == 0 &&
          session->publish_outstanding < WOP_SESSION_PUBLISH &&
          session->publish_outstanding < active) {
        UA_StatusCode status = send_publish(session);
        if (status != UA_STATUSCODE_GOOD) {
            wop_fail_status(failure, "connection_failed", "exchange", false, status);
            return false;
        }
    }
    return true;
}

static bool error_report(WopSession *session, size_t index, yyjson_mut_doc *document,
                         yyjson_mut_val *envelope) {
    WopSubscription *subscription = &session->subscriptions[index];
    char token[24];
    (void)snprintf(token, sizeof(token), "s%" PRIu64, subscription->serial);
    yyjson_mut_val *value = yyjson_mut_obj(document);
    bool built = value && yyjson_mut_obj_add_strcpy(document, envelope, "subscription_id", token) &&
        yyjson_mut_obj_add_str(document, envelope, "event", "error") &&
        yyjson_mut_obj_add_str(document, value, "code", subscription->failure_code) &&
        yyjson_mut_obj_add_str(document, value, "phase", "exchange") &&
        yyjson_mut_obj_add_str(document, value, "effect", "none") &&
        (!subscription->failure_has_status ||
         yyjson_mut_obj_add_uint(document, value, "status", subscription->failure_status)) &&
        yyjson_mut_obj_add_val(document, envelope, "value", value) &&
        yyjson_mut_obj_add_val(document, envelope, "metadata", yyjson_mut_obj(document));
    delete_remote(session, subscription->subscription_id);
    free_subscription(session, index);
    return built;
}

bool wop_subscription_report(WopSession *session, yyjson_mut_doc *document,
                             yyjson_mut_val *envelope, bool *produced, WopFailure *failure) {
    *produced = false;
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS; i++) {
        WopSubscription *subscription = &session->subscriptions[i];
        if(subscription->used && subscription->failed && !subscription->closing) {
            *produced = true;
            if(error_report(session, i, document, envelope)) return true;
            wop_fail(failure, "response_limit", "exchange", false);
            return false;
        }
    }
    while(session->report_count) {
        WopReadyReport *report = &session->reports[session->report_head];
        WopReadyReport current = *report;
        memset(report, 0, sizeof(*report));
        session->report_head = (session->report_head + 1U) % WOP_SESSION_READY;
        session->report_count--;
        WopSubscription *subscription = &session->subscriptions[current.subscription];
        if(!subscription->used || subscription->serial != current.serial || subscription->closing ||
           subscription->failed) {
            UA_DataValue_clear(&current.value);
            continue;
        }
        char token[24];
        (void)snprintf(token, sizeof(token), "s%" PRIu64, current.serial);
        yyjson_mut_val *value = NULL;
        bool supported = !current.value.hasValue || wop_session_supported(current.value.value.type);
        bool translated = supported &&
            wop_session_publish(session, &UA_TYPES[UA_TYPES_DATAVALUE], &current.value, 1);
        WopValueStatus status = translated ?
            wop_value_write_data_value(&current.value, document, &value) : WOP_VALUE_UNSUPPORTED;
        UA_StatusCode code = current.value.hasStatus ? current.value.status : UA_STATUSCODE_GOOD;
        bool overflow = (code & 0x0C00U) == 0x0400U && (code & 0x0080U);
        UA_DataValue_clear(&current.value);
        if(status != WOP_VALUE_OK || !value) {
            fail_subscription(subscription, status == WOP_VALUE_UNSUPPORTED ? "unsupported_type" :
                              status == WOP_VALUE_INVALID ? "invalid_response" : "response_limit",
                              false, 0);
            return wop_subscription_report(session, document, envelope, produced, failure);
        }
        yyjson_mut_val *metadata = yyjson_mut_obj(document);
        *produced = true;
        if(metadata && yyjson_mut_obj_add_strcpy(document, envelope, "subscription_id", token) &&
           yyjson_mut_obj_add_str(document, envelope, "event", "data") &&
           yyjson_mut_obj_add_val(document, envelope, "value", value) &&
           yyjson_mut_obj_add_uint(document, metadata, "sequence", current.sequence) &&
           yyjson_mut_obj_add_sint(document, metadata, "publish_time", current.publish_time) &&
           yyjson_mut_obj_add_uint(document, metadata, "client_handle", current.client_handle) &&
           yyjson_mut_obj_add_bool(document, metadata, "overflow", overflow) &&
           yyjson_mut_obj_add_uint(document, metadata, "datetime_resolution_ns", 100) &&
           yyjson_mut_obj_add_bool(document, metadata, "raw_datetime_ticks_available", true) &&
           yyjson_mut_obj_add_val(document, envelope, "metadata", metadata))
            return true;
        wop_fail(failure, "response_limit", "exchange", false);
        return false;
    }
    return true;
}

void wop_subscription_clear(WopSession *session) {
    for(size_t i = 0; i < WOP_SESSION_SUBSCRIPTIONS; i++)
        if(session->subscriptions[i].used) free_subscription(session, i);
    for(size_t i = 0; i < session->report_count; i++)
        UA_DataValue_clear(&session->reports[(session->report_head + i) % WOP_SESSION_READY].value);
    for(size_t i = 0; i < session->inbox_count; i++) UA_PublishResponse_clear(&session->inbox[i]);
    session->report_head = session->report_count = session->inbox_count = 0;
    session->publish_outstanding = 0;
    session->queued_frames = 0;
    session->subscription_serial = 0;
    session->subscription_orphaned = session->publish_fault = false;
}
