/* SPDX-License-Identifier: Apache-2.0
 * WOP-F14/F15/F16 Browse continuation lifecycle traces through the production
 * owner, Session adapter and continuation chains with an injected SDK send
 * boundary and an injected clock. The injected boundary records the exact
 * service requests the adapter builds and returns only scripted responses; the
 * runner supplies case input and never hands an expectation to the adapter.
 * The BEAM host role (release at the original deadline, cleanup after its
 * grace) is scripted by this runner.
 */
#include "owner.h"
#include "session_internal.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <open62541/client_config_default.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(condition) do { if(!(condition)) return __LINE__; } while(0)
#define STEP(call) do { int line = (call); if(line) return line; } while(0)
#define SERVICES 8

typedef struct {
    char kind[24];
    UA_UInt32 max_references;
    bool release;
    char continuation_hex[32];
    UA_UInt32 timeout_hint;
} Recorded;

typedef struct {
    WopSession session;
    WopSessionSdk sdk;
    int64_t now;
    Recorded services[SERVICES];
    size_t recorded;
    WopSessionOperation *pending;
    UA_UInt32 pending_request;
    bool pending_next;
    bool closed;
    size_t live;
    unsigned cancels;
    int pipe_fds[2];
    char output[1 << 20];
    size_t used, consumed;
    WopOwner owner;
} Trace;

static int64_t trace_clock(void *context) { return ((Trace *)context)->now; }

static void hex(const UA_ByteString *bytes, char *out, size_t capacity) {
    out[0] = '\0';
    for(size_t i = 0; i < bytes->length && (2 * i + 3) < capacity; i++)
        (void)snprintf(out + 2 * i, capacity - 2 * i, "%02x", bytes->data[i]);
}

static Recorded *record(Trace *trace, const char *kind) {
    if(trace->recorded == SERVICES) return NULL;
    Recorded *entry = &trace->services[trace->recorded++];
    memset(entry, 0, sizeof(*entry));
    (void)snprintf(entry->kind, sizeof(entry->kind), "%s", kind);
    return entry;
}

static UA_StatusCode send_browse(void *context, WopSessionOperation *operation,
                                 const UA_BrowseRequest *request) {
    Trace *trace = context;
    Recorded *entry = record(trace, "browse");
    if(!entry || trace->pending) return UA_STATUSCODE_BADINTERNALERROR;
    entry->max_references = request->requestedMaxReferencesPerNode;
    entry->timeout_hint = request->requestHeader.timeoutHint;
    trace->pending = operation;
    trace->pending_next = false;
    ++trace->pending_request;
    operation->request_id = trace->pending_request;
    return UA_STATUSCODE_GOOD;
}

static UA_StatusCode send_browse_next(void *context, WopSessionOperation *operation,
                                      const UA_BrowseNextRequest *request) {
    Trace *trace = context;
    Recorded *entry = record(trace, "browse_next");
    if(!entry || trace->pending || request->continuationPointsSize != 1)
        return UA_STATUSCODE_BADINTERNALERROR;
    entry->release = request->releaseContinuationPoints;
    entry->timeout_hint = request->requestHeader.timeoutHint;
    hex(&request->continuationPoints[0], entry->continuation_hex, sizeof(entry->continuation_hex));
    trace->pending = operation;
    trace->pending_next = true;
    ++trace->pending_request;
    operation->request_id = trace->pending_request;
    return UA_STATUSCODE_GOOD;
}

/* The adapter's cooperative cleanup closes the Session and then its channel. */
static bool disconnect(void *context) {
    Trace *trace = context;
    trace->closed = true;
    return record(trace, "close_session") && record(trace, "close_channel");
}

/* The trace never reaches a SecureChannel, so protocol Cancel is recorded only. */
static void cancel(void *context, const WopSessionOperation *operation) {
    (void)operation;
    ((Trace *)context)->cancels++;
}

static bool trace_open(void *context, yyjson_val *parameters, int64_t deadline_ms,
                       WopFailure *failure) {
    (void)parameters; (void)deadline_ms; (void)failure; (void)context;
    return true;
}

static WopCompletion trace_opened(void *context, yyjson_mut_doc *document,
                                  yyjson_mut_val *result, WopFailure *failure) {
    WopSession *session = context;
    session->revised_timeout_ms = 60000.0;
    session->ready = wop_session_sample_namespaces(session);
    if(!session->ready) {
        wop_fail(failure, "invalid_response", "opening", false);
        return WOP_COMPLETION_TERMINAL;
    }
    yyjson_mut_val *namespaces = yyjson_mut_arr(document);
    bool valid = namespaces &&
        yyjson_mut_obj_add_real(document, result, "session_timeout_ms", 60000.0) &&
        yyjson_mut_obj_add_val(document, result, "namespace_array", namespaces);
    for(size_t i = 0; valid && i < session->namespace_count; i++)
        valid = yyjson_mut_arr_add_strncpy(document, namespaces,
            (const char *)session->namespace_array[i].data, session->namespace_array[i].length);
    return valid ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
}

static void pump(Trace *trace) {
    (void)wop_output_flush(&trace->owner.output, trace->pipe_fds[1]);
    for(;;) {
        if(trace->used == sizeof(trace->output)) return;
        ssize_t count = read(trace->pipe_fds[0], trace->output + trace->used,
                             sizeof(trace->output) - trace->used);
        if(count > 0) trace->used += (size_t)count;
        else if(count < 0 && errno == EINTR) continue;
        else return;
    }
}

static void feed(Trace *trace, const char *text) {
    wop_owner_input(&trace->owner, text, strlen(text));
    pump(trace);
}

static void tick(Trace *trace) {
    wop_owner_tick(&trace->owner, 0);
    pump(trace);
}

static yyjson_doc *next_line(Trace *trace) {
    const char *start = trace->output + trace->consumed;
    const char *end = memchr(start, '\n', trace->used - trace->consumed);
    if(!end) return NULL;
    size_t length = (size_t)(end - start);
    trace->consumed += length + 1;
    return yyjson_read(start, length, 0);
}

static bool text_is(yyjson_val *value, const char *literal) {
    return yyjson_is_str(value) && strcmp(yyjson_get_str(value), literal) == 0;
}

static char *request_line(const char *id, const char *operation, const char *parameters,
                          uint64_t timeout_ms, int64_t deadline_ms) {
    static char line[4096];
    int size = snprintf(line, sizeof(line),
        "{\"version\":1,\"generation\":1,\"id\":\"%s\",\"operation\":\"%s\","
        "\"parameters\":%s,\"timeout_ms\":%" PRIu64 ",\"deadline_ms\":%" PRId64 "}\n",
        id, operation, parameters, timeout_ms, deadline_ms);
    return size > 0 && (size_t)size < sizeof(line) ? line : NULL;
}

static bool trace_start(Trace *trace, const char *const *uris, size_t uri_count) {
    memset(trace, 0, sizeof(*trace));
    if(pipe(trace->pipe_fds) != 0) return false;
    for(int i = 0; i < 2; i++) {
        int flags = fcntl(trace->pipe_fds[i], F_GETFL);
        if(flags < 0 || fcntl(trace->pipe_fds[i], F_SETFL, flags | O_NONBLOCK) != 0) return false;
    }
    trace->session.client = UA_Client_new();
    trace->session.namespace_array = (UA_String *)UA_Array_new(uri_count, &UA_TYPES[UA_TYPES_STRING]);
    if(!trace->session.client || !trace->session.namespace_array) return false;
    for(size_t i = 0; i < uri_count; i++) {
        trace->session.namespace_array[i] = UA_STRING_ALLOC(uris[i]);
        UA_UInt16 index = 0;
        if(i > 0 && UA_Client_addNamespace(trace->session.client, UA_STRING((char *)(uintptr_t)uris[i]),
                                           &index) != UA_STATUSCODE_GOOD)
            return false;
    }
    trace->session.namespace_count = uri_count;
    trace->sdk.context = trace;
    trace->sdk.browse = send_browse;
    trace->sdk.browse_next = send_browse_next;
    trace->sdk.disconnect = disconnect;
    trace->sdk.cancel = cancel;
    trace->session.sdk = &trace->sdk;
    WopService service;
    wop_session_service(&trace->session, &service);
    service.open = trace_open;
    service.opened = trace_opened;
    if(!wop_owner_init(&trace->owner, &service, trace_clock, trace)) return false;
    trace->owner.output_descriptor = trace->pipe_fds[1];
    return wop_owner_ready(&trace->owner, "trace-revision", trace->now);
}

static void trace_stop(Trace *trace) {
    wop_owner_clear(&trace->owner);
    close(trace->pipe_fds[0]);
    close(trace->pipe_fds[1]);
}

/* Builds the one scripted reference every case declares. */
static bool reference(yyjson_val *declared, UA_ReferenceDescription *description) {
    UA_ReferenceDescription_init(description);
    yyjson_val *node = yyjson_obj_get(declared, "node_id");
    yyjson_val *name = yyjson_obj_get(declared, "browse_name");
    yyjson_val *display = yyjson_obj_get(declared, "display_name");
    yyjson_val *type = yyjson_obj_get(declared, "type_definition");
    const char *reference_type = yyjson_get_str(yyjson_obj_get(declared, "reference_type_id"));
    if(!reference_type || strcmp(reference_type, "ns=0;i=47") != 0) return false;
    description->referenceTypeId = UA_NODEID_NUMERIC(0, 47);
    description->isForward = yyjson_get_bool(yyjson_obj_get(declared, "is_forward"));
    if(!text_is(yyjson_obj_get(node, "node_id"), "ns=2;i=1")) return false;
    description->nodeId.nodeId = UA_NODEID_NUMERIC(2, 1);
    description->browseName.namespaceIndex =
        (UA_UInt16)yyjson_get_uint(yyjson_obj_get(name, "namespace"));
    description->browseName.name = UA_STRING_ALLOC(yyjson_get_str(yyjson_obj_get(name, "name")));
    description->displayName.text = UA_STRING_ALLOC(yyjson_get_str(yyjson_obj_get(display, "text")));
    description->nodeClass = (UA_NodeClass)yyjson_get_uint(yyjson_obj_get(declared, "node_class"));
    if(!text_is(yyjson_obj_get(type, "node_id"), "ns=0;i=63")) return false;
    description->typeDefinition.nodeId = UA_NODEID_NUMERIC(0, 63);
    return true;
}

static bool page_response(Trace *trace, yyjson_val *event) {
    UA_BrowseResult result;
    UA_BrowseResult_init(&result);
    result.statusCode = (UA_StatusCode)yyjson_get_uint(yyjson_obj_get(event, "status"));
    yyjson_val *references = yyjson_obj_get(event, "references");
    size_t count = yyjson_arr_size(references);
    UA_ReferenceDescription *descriptions =
        count ? (UA_ReferenceDescription *)UA_Array_new(count, &UA_TYPES[UA_TYPES_REFERENCEDESCRIPTION])
              : NULL;
    if(count && !descriptions) return false;
    size_t index, total;
    yyjson_val *declared;
    yyjson_arr_foreach(references, index, total, declared) {
        if(!reference(declared, &descriptions[index])) return false;
    }
    result.references = descriptions;
    result.referencesSize = count;
    const char *point = yyjson_get_str(yyjson_obj_get(event, "continuation_hex"));
    if(point) {
        size_t bytes = strlen(point) / 2;
        result.continuationPoint.data = (UA_Byte *)UA_malloc(bytes);
        if(!result.continuationPoint.data) return false;
        result.continuationPoint.length = bytes;
        for(size_t i = 0; i < bytes; i++) {
            unsigned value = 0;
            /* NOLINTNEXTLINE(clang-analyzer-unix.Malloc,bugprone-unchecked-string-to-number-conversion,cert-err34-c): two hex digits cannot overflow; a failed parse fails the check, which exits */
            if(sscanf(point + 2 * i, "%2x", &value) != 1) return false;
            result.continuationPoint.data[i] = (UA_Byte)value;
        }
    }
    WopSessionOperation *operation = trace->pending;
    UA_UInt32 request_id = trace->pending_request;
    bool next = trace->pending_next;
    trace->pending = NULL;
    if(next) {
        UA_BrowseNextResponse response;
        UA_BrowseNextResponse_init(&response);
        response.results = &result;
        response.resultsSize = 1;
        wop_session_browse_next_receive(operation, request_id, &response);
    } else {
        UA_BrowseResponse response;
        UA_BrowseResponse_init(&response);
        response.results = &result;
        response.resultsSize = 1;
        wop_session_browse_receive(operation, request_id, &response);
    }
    UA_BrowseResult_clear(&result);
    return true;
}

static size_t active_continuations(const Trace *trace) {
    size_t active = 0;
    for(size_t i = 0; i < WOP_SESSION_CONTINUATIONS; i++)
        if(trace->session.browse_chains[i].active) active++;
    return active;
}

static bool services_match(const Trace *trace, yyjson_val *expected) {
    size_t index, count;
    yyjson_val *declared;
    if(yyjson_arr_size(expected) != trace->recorded) return false;
    yyjson_arr_foreach(expected, index, count, declared) {
        const Recorded *entry = &trace->services[index];
        if(yyjson_is_str(declared)) {
            /* The shorthand list names a releasing BrowseNext "browse_release". */
            const char *shorthand = strcmp(entry->kind, "browse_next") == 0 && entry->release
                                        ? "browse_release" : entry->kind;
            if(!text_is(declared, shorthand)) return false;
            continue;
        }
        if(!text_is(yyjson_obj_get(declared, "service"), entry->kind)) return false;
        yyjson_val *maximum = yyjson_obj_get(declared, "requested_max_references_per_node");
        yyjson_val *release = yyjson_obj_get(declared, "release_continuation_points");
        yyjson_val *point = yyjson_obj_get(declared, "continuation_hex");
        if(maximum && yyjson_get_uint(maximum) != entry->max_references) return false;
        if(release && yyjson_get_bool(release) != entry->release) return false;
        if(point && strcmp(yyjson_get_str(point), entry->continuation_hex) != 0) return false;
    }
    return true;
}

static const char open_parameters[] =
    "{\"endpoint\":\"opc.tcp://127.0.0.1:4840\","
    "\"security_policy\":\"http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256\","
    "\"security_mode\":\"SignAndEncrypt\",\"client_uri\":\"urn:client\","
    "\"server_uri\":\"urn:server\",\"certificate\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
    "\"private_key\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
    "\"server_certificate\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
    "\"trust_certificate\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
    "\"crl\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
    "\"authentication\":{\"type\":\"anonymous\"},\"session_timeout_ms\":60000}";

static const char browse_parameters[] =
    "{\"node_id\":\"ns=0;i=85\",\"reference_type_id\":\"ns=0;i=33\","
    "\"direction\":\"forward\",\"include_subtypes\":true,\"node_class_mask\":0,"
    "\"page_size\":%" PRIu64 ",\"allow_continuation\":true}";

static int open_trace(Trace *trace) {
    static const char *const uris[] = {"http://opcfoundation.org/UA/", "urn:fixture", "urn:values"};
    CHECK(trace_start(trace, uris, 3));
    pump(trace);
    yyjson_doc_free(next_line(trace));
    feed(trace, "{\"version\":1,\"generation\":1,\"event\":\"credit\",\"sequence\":1,"
                "\"messages\":16,\"bytes\":262144}\n");
    feed(trace, request_line("open-1", "open", open_parameters, 60000, INT64_MAX));
    tick(trace);
    yyjson_doc *document = next_line(trace);
    CHECK(document && yyjson_get_bool(yyjson_obj_get(yyjson_doc_get_root(document), "ok")));
    yyjson_doc_free(document);
    return 0;
}

/* Sends the case's Browse and delivers its scripted first page. */
static int first_page(Trace *trace, yyjson_val *input, char token[32]) {
    yyjson_val *options = yyjson_obj_get(input, "options");
    char parameters[512];
    (void)snprintf(parameters, sizeof(parameters), browse_parameters,
                   yyjson_get_uint(yyjson_obj_get(options, "page_size")));
    uint64_t timeout = yyjson_get_uint(yyjson_obj_get(options, "timeout_ms"));
    feed(trace, request_line("browse-1", "browse", parameters, timeout,
                             trace->now + (int64_t)timeout));
    tick(trace);
    yyjson_val *events = yyjson_obj_get(input, "events");
    yyjson_val *event = yyjson_arr_get(events, 0);
    trace->now = (int64_t)yyjson_get_uint(yyjson_obj_get(event, "at_ms"));
    CHECK(text_is(yyjson_obj_get(event, "event"), "browse_result"));
    CHECK(trace->pending && page_response(trace, event));
    tick(trace);
    yyjson_doc *document = next_line(trace);
    CHECK(document);
    yyjson_val *root = yyjson_doc_get_root(document);
    yyjson_val *result = yyjson_obj_get(root, "result");
    const char *continuation = yyjson_get_str(yyjson_obj_get(result, "continuation"));
    bool valid = yyjson_get_bool(yyjson_obj_get(root, "ok")) && continuation &&
                 yyjson_arr_size(yyjson_obj_get(result, "references")) ==
                     yyjson_arr_size(yyjson_obj_get(event, "references")) &&
                 yyjson_get_uint(yyjson_obj_get(result, "status")) ==
                     yyjson_get_uint(yyjson_obj_get(event, "status"));
    if(valid) (void)snprintf(token, 32, "%s", continuation);
    yyjson_doc_free(document);
    CHECK(valid);
    return 0;
}

/* `live` is sampled before any cleanup, which clears every chain. */
static int check_common(Trace *trace, yyjson_val *expected, bool session_open) {
    CHECK(services_match(trace, yyjson_obj_get(expected, "sent_services")));
    CHECK(trace->live == yyjson_get_uint(yyjson_obj_get(expected, "active_continuations")));
    CHECK(active_continuations(trace) == 0);
    yyjson_val *tasks = yyjson_obj_get(expected, "active_owned_native_tasks");
    if(tasks) CHECK(trace->owner.occupied == yyjson_get_uint(tasks));
    CHECK(yyjson_get_bool(yyjson_obj_get(expected, "session_open")) == session_open);
    yyjson_val *renewals = yyjson_obj_get(expected, "deadline_renewals");
    if(renewals) {
        /* Paging must never widen the original browse budget. The release
         * cleanup carries its own separate grace and is excluded. */
        UA_UInt32 budget = 0;
        size_t widened = 0;
        for(size_t i = 0; i < trace->recorded; i++) {
            const Recorded *entry = &trace->services[i];
            if(entry->release || !entry->timeout_hint) continue;
            if(budget && entry->timeout_hint > budget) widened++;
            budget = entry->timeout_hint;
        }
        CHECK(yyjson_get_uint(renewals) == widened);
    }
    return 0;
}

/* WOP-F14: an explicit release consumes the live continuation and keeps the Session. */
static int release_after_page(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace);
    yyjson_val *input = yyjson_obj_get(fixture, "input");
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    STEP(open_trace(trace));
    trace->recorded = 0;
    char token[32] = {0};
    STEP(first_page(trace, input, token));
    yyjson_val *events = yyjson_obj_get(input, "events");
    yyjson_val *release = yyjson_arr_get(events, 1);
    CHECK(text_is(yyjson_obj_get(release, "event"), "caller_release"));
    trace->now = (int64_t)yyjson_get_uint(yyjson_obj_get(release, "at_ms"));
    char parameters[64];
    (void)snprintf(parameters, sizeof(parameters), "{\"continuation\":\"%s\"}", token);
    feed(trace, request_line("release-1", "browse_release", parameters, 1000, trace->now + 1000));
    tick(trace);
    yyjson_val *response = yyjson_arr_get(events, 2);
    CHECK(text_is(yyjson_obj_get(response, "event"), "release_response"));
    trace->now = (int64_t)yyjson_get_uint(yyjson_obj_get(response, "at_ms"));
    CHECK(trace->pending && page_response(trace, response));
    tick(trace);
    yyjson_doc *document = next_line(trace);
    CHECK(document);
    yyjson_val *root = yyjson_doc_get_root(document);
    bool released = yyjson_get_bool(yyjson_obj_get(root, "ok")) &&
                    yyjson_is_null(yyjson_obj_get(root, "result"));
    yyjson_doc_free(document);
    trace->live = active_continuations(trace);
    CHECK(released && text_is(yyjson_obj_get(expected, "release"), "ok"));
    yyjson_val *page = yyjson_obj_get(expected, "page");
    CHECK(text_is(yyjson_obj_get(page, "continuation"), "h1") && token[0] == 'c');
    STEP(check_common(trace, expected, !trace->closed));
    trace_stop(trace);
    (void)wop_session_close(&trace->session);
    free(trace);
    return 0;
}

/* WOP-F15: the original deadline releases the continuation; a lost release closes. */
static int deadline_release(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace);
    yyjson_val *input = yyjson_obj_get(fixture, "input");
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    STEP(open_trace(trace));
    trace->recorded = 0;
    char token[32] = {0};
    STEP(first_page(trace, input, token));
    yyjson_val *events = yyjson_obj_get(input, "events");
    /* The host releases an unconsumed continuation when its browse deadline passes. */
    trace->now = (int64_t)yyjson_get_uint(yyjson_obj_get(yyjson_arr_get(events, 1), "at_ms"));
    char parameters[64];
    (void)snprintf(parameters, sizeof(parameters), "{\"continuation\":\"%s\"}", token);
    feed(trace, request_line("release-1", "browse_release", parameters, 1000, trace->now + 1000));
    tick(trace);
    CHECK(trace->pending);
    /* No release response arrives; the host's cleanup grace expires. */
    trace->now = (int64_t)yyjson_get_uint(yyjson_obj_get(yyjson_arr_get(events, 2), "at_ms"));
    tick(trace);
    trace->live = active_continuations(trace);
    CHECK(wop_session_close(&trace->session));
    /* Cleanup releases every abandoned slot on the next owner ticks. */
    for(int i = 0; i < 4; i++) tick(trace);
    STEP(check_common(trace, expected, !trace->closed));
    CHECK(trace->session.client == NULL);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-F16: a lost BrowseNext response fails its caller and closes the Session. */
static int lost_next(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace);
    yyjson_val *input = yyjson_obj_get(fixture, "input");
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    STEP(open_trace(trace));
    trace->recorded = 0;
    char token[32] = {0};
    STEP(first_page(trace, input, token));
    yyjson_val *events = yyjson_obj_get(input, "events");
    yyjson_val *caller = yyjson_arr_get(events, 1);
    CHECK(text_is(yyjson_obj_get(caller, "event"), "caller_next"));
    trace->now = (int64_t)yyjson_get_uint(yyjson_obj_get(caller, "at_ms"));
    uint64_t timeout = yyjson_get_uint(yyjson_obj_get(yyjson_obj_get(input, "options"), "timeout_ms"));
    char parameters[64];
    (void)snprintf(parameters, sizeof(parameters), "{\"continuation\":\"%s\"}", token);
    feed(trace, request_line("next-1", "browse_next", parameters, timeout,
                             (int64_t)timeout));
    tick(trace);
    CHECK(trace->pending);
    trace->now = (int64_t)yyjson_get_uint(yyjson_obj_get(yyjson_arr_get(events, 2), "at_ms"));
    tick(trace);
    yyjson_doc *document = next_line(trace);
    CHECK(document);
    yyjson_val *root = yyjson_doc_get_root(document);
    yyjson_val *error = yyjson_obj_get(root, "error");
    yyjson_val *declared = yyjson_obj_get(yyjson_obj_get(expected, "next_result"), "error");
    bool failed = yyjson_get_bool(yyjson_obj_get(root, "ok")) == false &&
                  text_is(yyjson_obj_get(error, "code"),
                          yyjson_get_str(yyjson_obj_get(declared, "code"))) &&
                  text_is(yyjson_obj_get(error, "effect"),
                          yyjson_get_str(yyjson_obj_get(declared, "effect")));
    yyjson_doc_free(document);
    CHECK(failed);
    trace->live = active_continuations(trace);
    CHECK(wop_session_close(&trace->session));
    for(int i = 0; i < 4; i++) tick(trace);
    STEP(check_common(trace, expected, !trace->closed));
    trace_stop(trace);
    free(trace);
    return 0;
}

static int run_case(yyjson_val *fixture) {
    yyjson_val *id = yyjson_obj_get(fixture, "id");
    if(text_is(id, "WOP-F14")) return release_after_page(fixture);
    if(text_is(id, "WOP-F15")) return deadline_release(fixture);
    if(text_is(id, "WOP-F16")) return lost_next(fixture);
    return __LINE__;
}

int main(int argc, char **argv) {
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
    int line = selected ? run_case(selected) : -1;
    printf("{\"status\":\"%s\",\"case\":\"%s\",\"line\":%d}\n",
           line == 0 ? "passed" : "failed", argv[2], line);
    yyjson_doc_free(document);
    return line == 0 ? 0 : 1;
}
