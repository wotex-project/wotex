/* SPDX-License-Identifier: Apache-2.0
 * WOP-S04/X05 Session subscription processing with an unconnected SDK client.
 * Publish responses are placed in the Session inbox exactly as the SDK callback
 * would; production validation, sequencing and report projection run on them.
 */
#include "session_internal.h"
#include "subscription_rules.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if(!(condition)) return __LINE__; } while(0)

static bool text_is(yyjson_val *value, const char *literal) {
    return yyjson_is_str(value) && strcmp(yyjson_get_str(value), literal) == 0;
}

static void *pool;

/* Parses one frame through the production strict reader with raw numbers. */
static bool strict(const char *text, size_t length, WopJson *output) {
    char *frame = malloc(length + 1);
    if(!frame) return false;
    memcpy(frame, text, length);
    frame[length] = '\n';
    bool parsed = wop_json_read(frame, length + 1, pool, WOP_JSON_POOL_BYTES, output) == WOP_JSON_OK;
    free(frame);
    return parsed;
}

static WopSession *session_new(void) {
    WopSession *session = calloc(1, sizeof(*session));
    if(!session) return NULL;
    WopService service;
    wop_session_service(session, &service);
    session->client = UA_Client_new();
    session->namespace_array = (UA_String *)UA_Array_new(2, &UA_TYPES[UA_TYPES_STRING]);
    if(!session->client || !session->namespace_array) return NULL;
    session->namespace_array[0] = UA_STRING_ALLOC("http://opcfoundation.org/UA/");
    session->namespace_count = 2;
    session->ready = true;
    /* Output is occupied, so the step never sends Publish on this client. */
    session->queued_frames = 1;
    if(!wop_session_sample_namespaces(session)) return NULL;
    WopSubscription *subscription = &session->subscriptions[0];
    subscription->used = true;
    subscription->serial = 1;
    subscription->subscription_id = 77;
    subscription->monitored_item_id = 5;
    subscription->client_handle = 1;
    subscription->revised = (WopSubscriptionParameters){100.0, 50.0, 10, true, 10, 30};
    subscription->activity_ms = wop_session_clock();
    subscription->sequence = malloc(sizeof(WopSequence));
    if(!subscription->sequence) return NULL;
    wop_sequence_init(subscription->sequence, 0);
    session->subscription_serial = 1;
    return session;
}

static void session_free(WopSession *session) {
    if(!session) return;
    (void)wop_session_close(session);
    free(session);
}

static bool deliver(WopSession *session, UA_UInt32 sequence, UA_UInt32 handle,
                    const UA_DataValue *value, UA_StatusCode *ack_statuses, size_t acks) {
    UA_PublishResponse *response = &session->inbox[session->inbox_count];
    UA_PublishResponse_init(response);
    response->subscriptionId = 77;
    response->notificationMessage.sequenceNumber = sequence;
    response->notificationMessage.publishTime = 1234;
    if(acks) {
        response->results = UA_Array_new(acks, &UA_TYPES[UA_TYPES_STATUSCODE]);
        if(!response->results) return false;
        memcpy(response->results, ack_statuses, acks * sizeof(UA_StatusCode));
        response->resultsSize = acks;
    }
    if(value) {
        UA_DataChangeNotification *change = UA_DataChangeNotification_new();
        if(!change) return false;
        change->monitoredItems = UA_Array_new(1, &UA_TYPES[UA_TYPES_MONITOREDITEMNOTIFICATION]);
        if(!change->monitoredItems) return false;
        change->monitoredItemsSize = 1;
        change->monitoredItems[0].clientHandle = handle;
        if(UA_DataValue_copy(value, &change->monitoredItems[0].value) != UA_STATUSCODE_GOOD)
            return false;
        response->notificationMessage.notificationData =
            UA_Array_new(1, &UA_TYPES[UA_TYPES_EXTENSIONOBJECT]);
        if(!response->notificationMessage.notificationData) return false;
        response->notificationMessage.notificationDataSize = 1;
        UA_ExtensionObject_setValue(&response->notificationMessage.notificationData[0], change,
                                    &UA_TYPES[UA_TYPES_DATACHANGENOTIFICATION]);
    }
    session->inbox_count++;
    return true;
}

/* Collects every emitted envelope as serialized JSON documents. */
static size_t reports(WopSession *session, yyjson_doc **output, size_t capacity, bool *valid) {
    size_t count = 0;
    *valid = true;
    for(;;) {
        yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
        yyjson_mut_val *root = yyjson_mut_obj(document);
        yyjson_mut_doc_set_root(document, root);
        bool produced = false;
        WopFailure failure = {0};
        if(!wop_subscription_report(session, document, root, &produced, &failure)) *valid = false;
        if(produced && count < capacity) {
            size_t length = 0;
            char *encoded = yyjson_mut_write(document, 0, &length);
            output[count++] = yyjson_read(encoded, length, 0);
            free(encoded);
        }
        yyjson_mut_doc_free(document);
        if(!produced || !*valid) return count;
    }
}

static UA_DataValue boolean_value(bool value) {
    UA_DataValue data;
    UA_DataValue_init(&data);
    UA_Variant_setScalarCopy(&data.value, &value, &UA_TYPES[UA_TYPES_BOOLEAN]);
    data.hasValue = true;
    return data;
}

/* WOP-X-F27: complete DataValue metadata survives report projection. */
static int data_value_projection(yyjson_val *fixture) {
    WopSession *session = session_new();
    CHECK(session);
    size_t input_length = 0;
    char *serialized = yyjson_val_write(yyjson_obj_get(fixture, "input"), 0, &input_length);
    WopJson parsed = {0};
    CHECK(serialized && strict(serialized, input_length, &parsed));
    free(serialized);
    yyjson_val *input = yyjson_doc_get_root(parsed.document);
    static unsigned char arena_bytes[65536];
    WopValueArena arena;
    UA_DataValue value;
    CHECK(wop_value_arena_init(&arena, arena_bytes, sizeof(arena_bytes)) &&
          wop_value_read_data_value(input, &arena, &value) == WOP_VALUE_OK);
    UA_DataValue copy;
    CHECK(UA_DataValue_copy(&value, &copy) == UA_STATUSCODE_GOOD);
    wop_value_arena_reset(&arena);
    wop_json_clear(&parsed);
    CHECK(deliver(session, 1, 1, &copy, NULL, 0));
    UA_DataValue_clear(&copy);
    WopFailure failure = {0};
    CHECK(wop_subscription_step(session, &failure));
    yyjson_doc *documents[4];
    bool valid = false;
    CHECK(reports(session, documents, 4, &valid) == 1 && valid);
    yyjson_val *root = yyjson_doc_get_root(documents[0]);
    CHECK(text_is(yyjson_obj_get(root, "subscription_id"), "s1") &&
          text_is(yyjson_obj_get(root, "event"), "data"));
    yyjson_val *projected = yyjson_obj_get(root, "value");
    yyjson_val *metadata = yyjson_obj_get(root, "metadata");
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    CHECK(yyjson_is_obj(expected));
    size_t index, count;
    yyjson_val *key, *expected_value;
    size_t value_keys = 0;
    yyjson_obj_foreach(expected, index, count, key, expected_value) {
        const char *name = yyjson_get_str(key);
        yyjson_val *actual = yyjson_obj_get(projected, name);
        if(!actual) actual = yyjson_obj_get(metadata, name);
        else value_keys++;
        CHECK(actual && yyjson_equals(actual, expected_value));
    }
    CHECK(value_keys == yyjson_obj_size(projected));
    CHECK(yyjson_get_uint(yyjson_obj_get(metadata, "sequence")) == 1 &&
          yyjson_get_uint(yyjson_obj_get(metadata, "client_handle")) == 1 &&
          yyjson_get_bool(yyjson_obj_get(metadata, "overflow")) == false);
    CHECK(session->subscriptions[0].ack_count == 1 && session->subscriptions[0].acks[0] == 1);
    yyjson_doc_free(documents[0]);
    session_free(session);
    return 0;
}

/* WOP-X-F28: server revisions are preserved when every value is admissible. */
static int subscription_revision(yyjson_val *fixture) {
    yyjson_val *input = yyjson_obj_get(fixture, "input");
    yyjson_val *revised = yyjson_obj_get(input, "revised");
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    WopSubscriptionParameters value = {
        yyjson_get_num(yyjson_obj_get(revised, "publishing_interval_ms")),
        yyjson_get_num(yyjson_obj_get(revised, "sampling_interval_ms")),
        (uint32_t)yyjson_get_uint(yyjson_obj_get(revised, "queue_size")), true,
        (uint32_t)yyjson_get_uint(yyjson_obj_get(revised, "keepalive_count")),
        (uint32_t)yyjson_get_uint(yyjson_obj_get(revised, "lifetime_count"))
    };
    CHECK(yyjson_get_uint(yyjson_obj_get(input, "status")) == 0);
    CHECK(wop_subscription_revision_valid(&value) ==
          yyjson_get_bool(yyjson_obj_get(expected, "accepted")));
    CHECK(value.publishing_interval_ms == yyjson_get_num(yyjson_obj_get(expected, "publishing_interval_ms")) &&
          value.sampling_interval_ms == yyjson_get_num(yyjson_obj_get(expected, "sampling_interval_ms")) &&
          value.queue_size == yyjson_get_uint(yyjson_obj_get(expected, "queue_size")) &&
          value.lifetime_count == yyjson_get_uint(yyjson_obj_get(expected, "lifetime_count")) &&
          value.keepalive_count == yyjson_get_uint(yyjson_obj_get(expected, "keepalive_count")));
    return 0;
}

static int matrix(void) {
    /* Parameter admission bounds and revision rejection. */
    static const char valid_request[] =
        "{\"node_id\":\"ns=0;i=1\",\"publishing_interval_ms\":10.5,\"sampling_interval_ms\":0,"
        "\"queue_size\":1000,\"discard_oldest\":false,\"keepalive_count\":1000,\"lifetime_count\":3000}";
    WopSubscriptionParameters parameters;
    WopJson parsed = {0};
    CHECK(strict(valid_request, sizeof(valid_request) - 1, &parsed) &&
          wop_subscription_read(yyjson_doc_get_root(parsed.document), &parameters) &&
          parameters.publishing_interval_ms == 10.5 && parameters.queue_size == 1000);
    wop_json_clear(&parsed);
    static const char short_lifetime[] =
        "{\"node_id\":\"ns=0;i=1\",\"publishing_interval_ms\":10,\"sampling_interval_ms\":0,"
        "\"queue_size\":1,\"discard_oldest\":true,\"keepalive_count\":10,\"lifetime_count\":29}";
    CHECK(strict(short_lifetime, sizeof(short_lifetime) - 1, &parsed) &&
          !wop_subscription_read(yyjson_doc_get_root(parsed.document), &parameters));
    wop_json_clear(&parsed);
    WopSubscriptionParameters revision = {9.99, 0, 1, true, 1, 3};
    CHECK(!wop_subscription_revision_valid(&revision));
    revision.publishing_interval_ms = 10;
    revision.sampling_interval_ms = -1;
    CHECK(!wop_subscription_revision_valid(&revision));

    /* Identical duplicates acknowledge once; a conflicting duplicate is terminal. */
    WopSession *session = session_new();
    CHECK(session);
    UA_DataValue first = boolean_value(true);
    UA_DataValue changed = boolean_value(false);
    CHECK(deliver(session, 1, 1, &first, NULL, 0) && deliver(session, 1, 1, &first, NULL, 0));
    WopFailure failure = {0};
    CHECK(wop_subscription_step(session, &failure));
    yyjson_doc *documents[8];
    bool valid = false;
    CHECK(reports(session, documents, 8, &valid) == 1 && valid);
    yyjson_doc_free(documents[0]);
    CHECK(deliver(session, 1, 1, &changed, NULL, 0) && wop_subscription_step(session, &failure));
    CHECK(reports(session, documents, 8, &valid) == 1 && valid);
    yyjson_val *error = yyjson_doc_get_root(documents[0]);
    CHECK(text_is(yyjson_obj_get(error, "event"), "error") &&
          text_is(yyjson_obj_get(yyjson_obj_get(error, "value"), "code"), "sequence_gap"));
    yyjson_doc_free(documents[0]);
    CHECK(!session->subscriptions[0].used && session->report_count == 0);
    session_free(session);

    /* A foreign client handle, status change and missing activity end the subscription. */
    for(int variant = 0; variant < 3; variant++) {
        session = session_new();
        CHECK(session);
        if(variant == 0) {
            CHECK(deliver(session, 1, 9, &first, NULL, 0));
        } else if(variant == 1) {
            CHECK(deliver(session, 1, 1, NULL, NULL, 0));
            UA_PublishResponse *response = &session->inbox[0];
            UA_StatusChangeNotification *change = UA_StatusChangeNotification_new();
            CHECK(change);
            change->status = UA_STATUSCODE_BADTIMEOUT;
            response->notificationMessage.notificationData =
                UA_Array_new(1, &UA_TYPES[UA_TYPES_EXTENSIONOBJECT]);
            CHECK(response->notificationMessage.notificationData);
            response->notificationMessage.notificationDataSize = 1;
            UA_ExtensionObject_setValue(&response->notificationMessage.notificationData[0], change,
                                        &UA_TYPES[UA_TYPES_STATUSCHANGENOTIFICATION]);
        } else {
            session->subscriptions[0].activity_ms -= 3001;
        }
        CHECK(wop_subscription_step(session, &failure));
        CHECK(reports(session, documents, 8, &valid) == 1 && valid);
        yyjson_val *value = yyjson_obj_get(yyjson_doc_get_root(documents[0]), "value");
        const char *expected = variant == 0 ? "invalid_response" : "subscription_lost";
        CHECK(text_is(yyjson_obj_get(value, "code"), expected));
        CHECK(variant != 1 || yyjson_get_uint(yyjson_obj_get(value, "status")) == UA_STATUSCODE_BADTIMEOUT);
        yyjson_doc_free(documents[0]);
        session_free(session);
    }

    /* A keepalive refreshes activity without a report; a Bad acknowledgement is Session-wide. */
    session = session_new();
    CHECK(session);
    session->subscriptions[0].activity_ms -= 2000;
    CHECK(deliver(session, 1, 1, NULL, NULL, 0) && wop_subscription_step(session, &failure));
    CHECK(reports(session, documents, 8, &valid) == 0 && valid);
    CHECK(wop_session_clock() - session->subscriptions[0].activity_ms < 1000);
    UA_StatusCode bad_ack = UA_STATUSCODE_BADINTERNALERROR;
    CHECK(deliver(session, 1, 1, NULL, &bad_ack, 1));
    CHECK(!wop_subscription_step(session, &failure));
    CHECK(strcmp(failure.code, "invalid_response") == 0 && failure.status == UA_STATUSCODE_BADINTERNALERROR);
    session_free(session);

    /* A gap starts Republish; without a connected channel the subscription fails. */
    session = session_new();
    CHECK(session);
    CHECK(deliver(session, 2, 1, &first, NULL, 0) && wop_subscription_step(session, &failure));
    CHECK(reports(session, documents, 8, &valid) == 1 && valid);
    CHECK(text_is(yyjson_obj_get(yyjson_obj_get(yyjson_doc_get_root(documents[0]), "value"), "code"),
                  "connection_failed"));
    yyjson_doc_free(documents[0]);
    session_free(session);
    UA_DataValue_clear(&first);
    UA_DataValue_clear(&changed);
    return 0;
}

int main(int argc, char **argv) {
    pool = malloc(WOP_JSON_POOL_BYTES);
    if(!pool) return 70;
    if(argc == 2 && strcmp(argv[1], "--matrix") == 0) {
        int line = matrix();
        printf("{\"status\":\"%s\",\"line\":%d}\n", line ? "failed" : "passed", line);
        return line ? 1 : 0;
    }
    if(argc != 3) return 64;
    FILE *file = fopen(argv[1], "rb");
    if(!file) return 66;
    static char corpus[1 << 20];
    size_t length = fread(corpus, 1, sizeof(corpus), file);
    fclose(file);
    yyjson_doc *document = yyjson_read(corpus, length, 0);
    yyjson_val *cases = yyjson_obj_get(yyjson_doc_get_root(document), "cases");
    yyjson_val *selected = NULL, *candidate;
    size_t index, count;
    yyjson_arr_foreach(cases, index, count, candidate) {
        if(text_is(yyjson_obj_get(candidate, "id"), argv[2])) selected = candidate;
    }
    int line = -1;
    if(selected && text_is(yyjson_obj_get(selected, "operation"), "data_value_projection"))
        line = data_value_projection(selected);
    else if(selected && text_is(yyjson_obj_get(selected, "operation"), "subscription_revision"))
        line = subscription_revision(selected);
    printf("{\"status\":\"%s\",\"case\":\"%s\",\"line\":%d}\n",
           line == 0 ? "passed" : "failed", argv[2], line);
    yyjson_doc_free(document);
    return line == 0 ? 0 : 1;
}
