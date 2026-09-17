/* SPDX-License-Identifier: Apache-2.0
 * WOP-X03/X04 native owner traces through the production admission, dispatch,
 * cancellation and output code with an explicitly injected service boundary.
 * The fake service records protocol requests; it never receives expectations.
 */
#include "owner.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(condition) do { if(!(condition)) return __LINE__; } while(0)

typedef enum { FAKE_PENDING, FAKE_SUCCESS, FAKE_REMOTE_BAD } FakeOutcome;

typedef struct {
    int64_t now;
    bool ready;
    uint64_t report_bytes;
    uint64_t reports_left;
    uint64_t reports_produced;
    bool unsubscribe_fails;
    bool step_fails;
    bool close_ok;
    unsigned opens, closes, network_requests, write_requests, cancels;
    bool prepared[WOP_OWNER_OPERATIONS];
    bool sdk_pending[WOP_OWNER_OPERATIONS];
    FakeOutcome outcome[WOP_OWNER_OPERATIONS];
    uint32_t handles[WOP_OWNER_OPERATIONS];
    char dispatch_order[128][65];
    size_t dispatched;
} Fake;

static int64_t fake_clock(void *context) { return ((Fake *)context)->now; }

static bool fake_open(void *context, yyjson_val *parameters, int64_t deadline_ms,
                      WopFailure *failure) {
    (void)parameters; (void)deadline_ms; (void)failure;
    ((Fake *)context)->opens++;
    return true;
}

static WopCompletion fake_opened(void *context, yyjson_mut_doc *document, yyjson_mut_val *result,
                                 WopFailure *failure) {
    (void)failure;
    if(!((Fake *)context)->ready) return WOP_COMPLETION_PENDING;
    yyjson_mut_val *namespaces = yyjson_mut_arr(document);
    return namespaces &&
           yyjson_mut_arr_add_str(document, namespaces, "http://opcfoundation.org/UA/") &&
           yyjson_mut_arr_add_str(document, namespaces, "urn:fixture") &&
           yyjson_mut_obj_add_real(document, result, "session_timeout_ms", 60000.0) &&
           yyjson_mut_obj_add_val(document, result, "namespace_array", namespaces)
               ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
}

static bool fake_prepare(void *context, const WopOperation *operation, yyjson_val *parameters,
                         WopFailure *failure) {
    (void)failure;
    Fake *fake = context;
    if(!yyjson_is_obj(parameters) || yyjson_obj_get(parameters, "invalid")) return false;
    fake->prepared[operation->index] = true;
    fake->outcome[operation->index] = FAKE_PENDING;
    return true;
}

static bool fake_dispatch(void *context, const WopOperation *operation, uint32_t timeout_ms,
                          WopFailure *failure) {
    (void)failure;
    Fake *fake = context;
    if(timeout_ms == 0) return false;
    fake->network_requests++;
    if(operation->kind == WOP_OPERATION_WRITE) fake->write_requests++;
    fake->sdk_pending[operation->index] = true;
    fake->handles[operation->index] = operation->request_handle;
    if(fake->dispatched < 128)
        memcpy(fake->dispatch_order[fake->dispatched++], operation->id, 65);
    return true;
}

static WopCompletion fake_complete(void *context, const WopOperation *operation,
                                   yyjson_mut_doc *document, yyjson_mut_val **result,
                                   WopFailure *failure) {
    Fake *fake = context;
    if(operation->kind == WOP_OPERATION_UNSUBSCRIBE && fake->unsubscribe_fails &&
       fake->outcome[operation->index] != FAKE_PENDING) {
        fake->sdk_pending[operation->index] = false;
        failure->code = "cleanup_failed";
        failure->phase = "cleanup";
        return WOP_COMPLETION_TERMINAL;
    }
    switch(fake->outcome[operation->index]) {
    case FAKE_PENDING:
        return WOP_COMPLETION_PENDING;
    case FAKE_REMOTE_BAD:
        fake->sdk_pending[operation->index] = false;
        failure->code = "remote_error";
        failure->phase = "exchange";
        failure->has_status = true;
        failure->status = 0x80340000U;
        return WOP_COMPLETION_FAILURE;
    case FAKE_SUCCESS:
        fake->sdk_pending[operation->index] = false;
        *result = yyjson_mut_obj(document);
        return *result && yyjson_mut_obj_add_uint(document, *result, "status", 0)
                   ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
    }
    return WOP_COMPLETION_TERMINAL;
}

/* Produces fixed-size reports while any remain; each line is exactly
 * report_bytes long including its newline. */
static bool fake_report(void *context, yyjson_mut_doc *document, yyjson_mut_val *envelope,
                        bool *produced, WopFailure *failure) {
    (void)failure;
    Fake *fake = context;
    *produced = false;
    if(!fake->reports_left) return true;
    yyjson_mut_val *metadata = yyjson_mut_obj(document);
    yyjson_mut_val *value = yyjson_mut_strcpy(document, "");
    if(!metadata || !value || !yyjson_mut_obj_add_str(document, envelope, "subscription_id", "s1") ||
       !yyjson_mut_obj_add_str(document, envelope, "event", "data") ||
       !yyjson_mut_obj_add_val(document, envelope, "value", value) ||
       !yyjson_mut_obj_add_val(document, envelope, "metadata", metadata))
        return false;
    size_t length = 0;
    char *encoded = yyjson_mut_write(document, 0, &length);
    free(encoded);
    if(!encoded || length + 1 > fake->report_bytes) return false;
    size_t padding = fake->report_bytes - 1 - length;
    char *text = malloc(padding + 1);
    if(!text) return false;
    memset(text, 'x', padding);
    text[padding] = '\0';
    yyjson_mut_val *padded = yyjson_mut_strncpy(document, text, padding);
    free(text);
    if(!padded || !yyjson_mut_obj_put(envelope, yyjson_mut_str(document, "value"), padded))
        return false;
    fake->reports_left--;
    fake->reports_produced++;
    *produced = true;
    return true;
}

static void fake_cancel(void *context, const WopOperation *operation) {
    (void)operation;
    ((Fake *)context)->cancels++;
}

static void fake_retire(void *context, const WopOperation *operation) {
    Fake *fake = context;
    fake->prepared[operation->index] = false;
    fake->outcome[operation->index] = FAKE_PENDING;
}

static bool fake_released(void *context, const WopOperation *operation) {
    return !((Fake *)context)->sdk_pending[operation->index];
}

static bool fake_step(void *context, int slice_ms, WopFailure *failure) {
    (void)slice_ms; (void)failure;
    return !((Fake *)context)->step_fails;
}

static bool fake_close(void *context) {
    Fake *fake = context;
    fake->closes++;
    /* Client deletion completes every outstanding SDK callback. */
    memset(fake->sdk_pending, 0, sizeof(fake->sdk_pending));
    return fake->close_ok;
}

typedef struct {
    Fake fake;
    WopOwner owner;
    int pipe_fds[2];
    char output[1 << 20];
    size_t used;
    size_t consumed;
} Trace;

static bool trace_start(Trace *trace) {
    memset(trace, 0, sizeof(*trace));
    trace->fake.close_ok = true;
    WopService service = {
        &trace->fake, fake_open, fake_opened, fake_prepare, fake_dispatch, fake_complete,
        fake_cancel, fake_retire, fake_released, fake_step, fake_close, fake_report, NULL
    };
    if(pipe(trace->pipe_fds) != 0) return false;
    for(int i = 0; i < 2; i++) {
        int flags = fcntl(trace->pipe_fds[i], F_GETFL);
        if(flags < 0 || fcntl(trace->pipe_fds[i], F_SETFL, flags | O_NONBLOCK) != 0) return false;
    }
    if(!wop_owner_init(&trace->owner, &service, fake_clock, &trace->fake)) return false;
    trace->owner.output_descriptor = trace->pipe_fds[1];
    return true;
}

static void trace_stop(Trace *trace) {
    wop_owner_clear(&trace->owner);
    close(trace->pipe_fds[0]);
    close(trace->pipe_fds[1]);
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

/* Returns the next complete output line as a parsed document. */
static yyjson_doc *next_line(Trace *trace) {
    const char *start = trace->output + trace->consumed;
    const char *end = memchr(start, '\n', trace->used - trace->consumed);
    if(!end) return NULL;
    size_t length = (size_t)(end - start);
    trace->consumed += length + 1;
    return yyjson_read(start, length, 0);
}

static size_t remaining_lines(const Trace *trace) {
    size_t lines = 0;
    for(size_t i = trace->consumed; i < trace->used; i++)
        if(trace->output[i] == '\n') lines++;
    return lines;
}

static bool text_is(yyjson_val *value, const char *literal) {
    return yyjson_is_str(value) && strcmp(yyjson_get_str(value), literal) == 0;
}

/* Matches one failure envelope or terminal control exactly. */
static bool error_line(yyjson_doc *document, const char *id, const char *code,
                       const char *phase, const char *effect) {
    yyjson_val *root = yyjson_doc_get_root(document);
    yyjson_val *error = yyjson_obj_get(root, "error");
    bool identity = id ? text_is(yyjson_obj_get(root, "id"), id) &&
                             yyjson_get_bool(yyjson_obj_get(root, "ok")) == false &&
                             yyjson_obj_size(root) == 5
                       : text_is(yyjson_obj_get(root, "event"), "terminal") &&
                             yyjson_obj_size(root) == 4;
    bool matched = document && identity && text_is(yyjson_obj_get(error, "code"), code) &&
                   text_is(yyjson_obj_get(error, "phase"), phase) &&
                   text_is(yyjson_obj_get(error, "effect"), effect);
    yyjson_doc_free(document);
    return matched;
}

static bool success_line(yyjson_doc *document, const char *id, yyjson_val **result_out,
                         yyjson_doc **keep) {
    yyjson_val *root = yyjson_doc_get_root(document);
    bool matched = document && text_is(yyjson_obj_get(root, "id"), id) &&
                   yyjson_get_bool(yyjson_obj_get(root, "ok")) &&
                   yyjson_get_uint(yyjson_obj_get(root, "generation")) == 1 &&
                   yyjson_obj_size(root) == 5;
    if(matched && result_out && keep) {
        *result_out = yyjson_obj_get(root, "result");
        *keep = document;
    } else {
        yyjson_doc_free(document);
    }
    return matched;
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

static char *request(const char *id, const char *operation, const char *parameters,
                     uint64_t timeout_ms, int64_t deadline_ms) {
    static char line[8192];
    int size = snprintf(line, sizeof(line),
        "{\"version\":1,\"generation\":1,\"id\":\"%s\",\"operation\":\"%s\","
        "\"parameters\":%s,\"timeout_ms\":%" PRIu64 ",\"deadline_ms\":%" PRId64 "}\n",
        id, operation, parameters, timeout_ms, deadline_ms);
    return size > 0 && (size_t)size < sizeof(line) ? line : NULL;
}

static const char full_credit[] =
    "{\"version\":1,\"generation\":1,\"event\":\"credit\",\"sequence\":1,"
    "\"messages\":16,\"bytes\":262144}\n";

static const char read_parameters[] = "{\"node_id\":\"ns=1;s=value\",\"index_range\":null}";

/* Credit, ready and a successful open; the open reply is consumed. */
static int open_session(Trace *trace) {
    CHECK(wop_owner_ready(&trace->owner, "fixture-revision", trace->fake.now));
    pump(trace);
    yyjson_doc *ready = next_line(trace);
    CHECK(ready && text_is(yyjson_obj_get(yyjson_doc_get_root(ready), "event"), "ready"));
    yyjson_doc_free(ready);
    feed(trace, full_credit);
    feed(trace, request("open-1", "open", open_parameters, 60000, INT64_MAX));
    CHECK(trace->fake.opens == 1 && remaining_lines(trace) == 0);
    tick(trace);
    CHECK(remaining_lines(trace) == 0);
    trace->fake.ready = true;
    tick(trace);
    yyjson_val *result = NULL;
    yyjson_doc *keep = NULL;
    CHECK(success_line(next_line(trace), "open-1", &result, &keep));
    CHECK(yyjson_get_uint(yyjson_obj_get(result, "session_generation")) == 1);
    yyjson_doc_free(keep);
    CHECK(trace->owner.session == WOP_OWNER_OPEN);
    return 0;
}

static yyjson_val *fixture_input(yyjson_val *fixture, const char *name) {
    return yyjson_obj_get(yyjson_obj_get(fixture, "input"), name);
}

static yyjson_val *fixture_expect(yyjson_val *fixture, const char *name) {
    return yyjson_obj_get(yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value"), name);
}

/* WOP-X-F17: the translated native deadline equals the dispatch clock and fails. */
static int native_deadline(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    /* Same arithmetic as Native.Frame.admission/5; ExUnit binds that owner side. */
    int64_t native_deadline = yyjson_get_sint(fixture_input(fixture, "ready_native_ms")) +
                              yyjson_get_sint(fixture_input(fixture, "owner_deadline_ms")) -
                              yyjson_get_sint(fixture_input(fixture, "ready_received_owner_ms"));
    CHECK(native_deadline == yyjson_get_sint(fixture_expect(fixture, "native_deadline_ms")));
    trace->fake.now = yyjson_get_sint(fixture_input(fixture, "dispatch_native_ms"));
    feed(trace, request("read-1", "read", read_parameters, 1000, native_deadline));
    tick(trace);
    CHECK(error_line(next_line(trace), "read-1",
                     yyjson_get_str(fixture_expect(fixture, "error")), "admission", "none"));
    CHECK(trace->fake.network_requests ==
          yyjson_get_uint(fixture_expect(fixture, "network_requests")));
    CHECK(trace->owner.occupied == 0);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-X-F18: a queued write canceled before its dispatch tick sends nothing. */
static int cancel_queued(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    const char *id = yyjson_get_str(fixture_input(fixture, "request_id"));
    CHECK(text_is(fixture_input(fixture, "operation"), "write"));
    char line[512];
    (void)snprintf(line, sizeof(line), "%s", request(id, "write",
        "{\"node_id\":\"ns=1;s=value\",\"index_range\":null,\"value\":{}}", 5000, INT64_MAX));
    feed(trace, line);
    char cancel[128];
    (void)snprintf(cancel, sizeof(cancel), "{\"target_id\":\"%s\"}", id);
    feed(trace, request("cancel-1", "cancel", cancel, 1000, INT64_MAX));
    tick(trace);
    CHECK(error_line(next_line(trace), id, "canceled", "admission",
                     yyjson_get_str(fixture_expect(fixture, "effect"))));
    yyjson_val *result = NULL;
    yyjson_doc *keep = NULL;
    CHECK(success_line(next_line(trace), "cancel-1", &result, &keep));
    CHECK(text_is(yyjson_obj_get(result, "target_id"), id) &&
          yyjson_get_bool(yyjson_obj_get(result, "canceled")) && yyjson_obj_size(result) == 2);
    yyjson_doc_free(keep);
    for(int i = 0; i < 4; i++) tick(trace);
    CHECK(trace->fake.network_requests ==
          yyjson_get_uint(fixture_expect(fixture, "network_requests")));
    CHECK(remaining_lines(trace) == yyjson_get_uint(fixture_expect(fixture, "late_results")));
    CHECK(trace->owner.occupied == 0 && trace->fake.cancels == 0);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-X-F19: a transmitted write keeps unknown effect and suppresses late success. */
static int cancel_transmitted(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    const char *id = yyjson_get_str(fixture_input(fixture, "request_id"));
    feed(trace, request(id, "write",
        "{\"node_id\":\"ns=1;s=value\",\"index_range\":null,\"value\":{}}", 5000, INT64_MAX));
    tick(trace);
    CHECK(trace->fake.write_requests == 1 && remaining_lines(trace) == 0);
    char cancel[128];
    (void)snprintf(cancel, sizeof(cancel), "{\"target_id\":\"%s\"}", id);
    feed(trace, request("cancel-1", "cancel", cancel, 1000, INT64_MAX));
    CHECK(error_line(next_line(trace), id, "canceled", "exchange",
                     yyjson_get_str(fixture_expect(fixture, "effect"))));
    yyjson_val *result = NULL;
    yyjson_doc *keep = NULL;
    CHECK(success_line(next_line(trace), "cancel-1", &result, &keep));
    CHECK(yyjson_get_bool(yyjson_obj_get(result, "canceled")));
    yyjson_doc_free(keep);
    CHECK(trace->fake.cancels == 1);
    size_t slot = 0;
    while(slot < WOP_OWNER_OPERATIONS && trace->fake.handles[slot] == 0) slot++;
    CHECK(slot < WOP_OWNER_OPERATIONS);
    CHECK(trace->owner.operations[slot].state == WOP_SLOT_ABANDONED && trace->owner.occupied == 1);
    /* The late SDK success arrives after local retirement. */
    trace->fake.outcome[slot] = FAKE_SUCCESS;
    trace->fake.sdk_pending[slot] = false;
    for(int i = 0; i < 4; i++) tick(trace);
    CHECK(remaining_lines(trace) == yyjson_get_uint(fixture_expect(fixture, "late_results")));
    CHECK(trace->fake.write_requests == yyjson_get_uint(fixture_expect(fixture, "write_requests")));
    CHECK(trace->owner.occupied == 0);
    feed(trace, request("cancel-2", "cancel", cancel, 1000, INT64_MAX));
    CHECK(success_line(next_line(trace), "cancel-2", &result, &keep));
    CHECK(!yyjson_get_bool(yyjson_obj_get(result, "canceled")));
    yyjson_doc_free(keep);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-X-F20: 64 unfinished operations fill admission; close uses the reserve. */
static int admission(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    uint64_t requests = yyjson_get_uint(fixture_input(fixture, "requests"));
    CHECK(yyjson_get_uint(fixture_input(fixture, "capacity")) == WOP_OWNER_OPERATIONS);
    uint64_t busy = 0;
    for(uint64_t i = 0; i < requests; i++) {
        char id[32];
        (void)snprintf(id, sizeof(id), "read-%" PRIu64, i);
        feed(trace, request(id, "read", read_parameters, 60000, INT64_MAX));
        if(i + 1 == WOP_OWNER_OPERATIONS) tick(trace);
        yyjson_doc *line = next_line(trace);
        if(line) {
            CHECK(error_line(line, id, "busy", "admission", "none"));
            busy++;
        }
    }
    CHECK(trace->owner.occupied == yyjson_get_uint(fixture_expect(fixture, "admitted")));
    CHECK(busy == yyjson_get_uint(fixture_expect(fixture, "busy")));
    CHECK(trace->fake.network_requests == WOP_OWNER_OPERATIONS);
    CHECK(yyjson_get_bool(fixture_input(fixture, "close_requested")));
    feed(trace, request("close-1", "close", "{}", 1000, INT64_MAX));
    CHECK(success_line(next_line(trace), "close-1", NULL, NULL) ==
          yyjson_get_bool(fixture_expect(fixture, "close_admitted")));
    CHECK(trace->owner.occupied == yyjson_get_uint(fixture_expect(fixture, "remaining_requests")));
    CHECK(trace->owner.finished && trace->owner.status == 0 && trace->fake.closes == 1);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-X-F49/F50: invalid credit replay or overflow ends the generation. */
static int credit_trace(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(wop_owner_ready(&trace->owner, "fixture-revision", 0));
    pump(trace);
    yyjson_doc_free(next_line(trace));
    uint64_t generation = yyjson_get_uint(fixture_input(fixture, "generation"));
    yyjson_val *events = fixture_input(fixture, "events");
    size_t index, count;
    yyjson_val *event;
    uint64_t accepted = 0;
    yyjson_arr_foreach(events, index, count, event) {
        char line[256];
        (void)snprintf(line, sizeof(line),
            "{\"version\":1,\"generation\":%" PRIu64 ",\"event\":\"credit\","
            "\"sequence\":%" PRIu64 ",\"messages\":%" PRIu64 ",\"bytes\":%" PRIu64 "}\n",
            generation, yyjson_get_uint(yyjson_obj_get(event, "sequence")),
            yyjson_get_uint(yyjson_obj_get(event, "messages")),
            yyjson_get_uint(yyjson_obj_get(event, "bytes")));
        bool finished = trace->owner.finished;
        feed(trace, line);
        if(!finished && !trace->owner.finished) accepted++;
    }
    CHECK(accepted == yyjson_get_uint(fixture_expect(fixture, "grants_accepted")));
    CHECK(error_line(next_line(trace), NULL,
                     yyjson_get_str(fixture_expect(fixture, "terminal_error")), "validation", "none"));
    feed(trace, request("read-1", "read", read_parameters, 1000, INT64_MAX));
    tick(trace);
    CHECK(remaining_lines(trace) == 0 && trace->owner.output.emitted_messages == 0);
    wop_owner_shutdown(&trace->owner);
    CHECK(trace->owner.occupied == yyjson_get_uint(fixture_expect(fixture, "owned_resources_after_grace")));
    CHECK(trace->owner.output.count == 0 && trace->fake.network_requests == 0);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-X-F52..F55: a missing or invalid native deadline fails before admission. */
static int invalid_deadline(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    size_t length = 0;
    char *envelope = yyjson_val_write(fixture_input(fixture, "envelope"), 0, &length);
    CHECK(envelope);
    char *line = malloc(length + 2);
    CHECK(line);
    memcpy(line, envelope, length);
    line[length] = '\n';
    line[length + 1] = '\0';
    feed(trace, line);
    free(line);
    free(envelope);
    tick(trace);
    yyjson_val *error = fixture_expect(fixture, "error");
    CHECK(error_line(next_line(trace), NULL, yyjson_get_str(yyjson_obj_get(error, "code")),
                     yyjson_get_str(yyjson_obj_get(error, "phase")),
                     yyjson_get_str(yyjson_obj_get(error, "effect"))));
    CHECK(trace->fake.network_requests ==
          yyjson_get_uint(fixture_expect(fixture, "native_requests")));
    CHECK(trace->owner.finished && trace->owner.status == 70 && trace->owner.occupied == 0);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* Additional WOP-X03/X04 matrix cases outside the fixed corpus. */
static int matrix_splits_and_order(void) {
    const char *first = request("read-a", "read", read_parameters, 60000, INT64_MAX);
    char both[16384];
    size_t first_length = strlen(first);
    memcpy(both, first, first_length);
    const char *second = request("read-b", "read", read_parameters, 60000, INT64_MAX);
    size_t second_length = strlen(second);
    memcpy(both + first_length, second, second_length);
    size_t total = first_length + second_length;
    for(size_t split = 0; split <= total; split++) {
        Trace *trace = calloc(1, sizeof(*trace));
        CHECK(trace && trace_start(trace));
        CHECK(open_session(trace) == 0);
        wop_owner_input(&trace->owner, both, split);
        CHECK(!trace->owner.finished);
        wop_owner_input(&trace->owner, both + split, total - split);
        tick(trace);
        CHECK(!trace->owner.finished && trace->fake.dispatched == 2);
        CHECK(strcmp(trace->fake.dispatch_order[0], "read-a") == 0);
        CHECK(strcmp(trace->fake.dispatch_order[1], "read-b") == 0);
        CHECK(trace->fake.handles[0] != 0 && trace->fake.handles[1] != 0 &&
              trace->fake.handles[0] != trace->fake.handles[1]);
        for(size_t slot = 0; slot < 2; slot++) trace->fake.outcome[slot] = FAKE_SUCCESS;
        tick(trace);
        CHECK(success_line(next_line(trace), "read-a", NULL, NULL));
        CHECK(success_line(next_line(trace), "read-b", NULL, NULL));
        CHECK(trace->owner.occupied == 0);
        trace_stop(trace);
        free(trace);
    }
    return 0;
}

static int matrix_request_failures(void) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(wop_owner_ready(&trace->owner, "fixture-revision", 0));
    pump(trace);
    yyjson_doc_free(next_line(trace));
    feed(trace, full_credit);
    /* Before open, service requests fail without ending the generation. */
    feed(trace, request("early", "read", read_parameters, 1000, INT64_MAX));
    CHECK(error_line(next_line(trace), "early", "invalid_request", "validation", "none"));
    CHECK(!trace->owner.finished);
    trace_stop(trace);
    free(trace);

    trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    feed(trace, request("sub", "subscribe", "{\"invalid\":true}", 1000, INT64_MAX));
    CHECK(error_line(next_line(trace), "sub", "invalid_value", "validation", "none"));
    feed(trace, request("bad", "read", "{\"invalid\":true}", 1000, INT64_MAX));
    CHECK(error_line(next_line(trace), "bad", "invalid_value", "validation", "none"));
    /* A remote Bad status is request-scoped and keeps the Session usable. */
    feed(trace, request("w-bad", "write", "{\"value\":{}}", 5000, INT64_MAX));
    tick(trace);
    trace->fake.outcome[0] = FAKE_REMOTE_BAD;
    tick(trace);
    yyjson_doc *line = next_line(trace);
    yyjson_val *error = yyjson_obj_get(yyjson_doc_get_root(line), "error");
    CHECK(yyjson_get_uint(yyjson_obj_get(error, "status")) == 0x80340000U);
    CHECK(error_line(line, "w-bad", "remote_error", "exchange", "unknown"));
    CHECK(!trace->owner.finished && trace->owner.occupied == 0);
    /* Dispatched deadline expiry cancels, reports unknown for a mutation and
     * keeps the slot until the SDK releases its callback storage. */
    trace->fake.now = 10;
    feed(trace, request("w-late", "write", "{\"value\":{}}", 5, INT64_MAX));
    tick(trace);
    trace->fake.now = 15;
    tick(trace);
    CHECK(error_line(next_line(trace), "w-late", "deadline_exceeded", "exchange", "unknown"));
    CHECK(trace->fake.cancels == 1 && trace->owner.occupied == 1);
    trace->fake.sdk_pending[0] = false;
    tick(trace);
    CHECK(trace->owner.occupied == 0);
    /* Queued work whose deadline passed before dispatch sends nothing. */
    feed(trace, request("r-expired", "read", read_parameters, 1, INT64_MAX));
    trace->fake.now = 16;
    unsigned before = trace->fake.network_requests;
    tick(trace);
    CHECK(error_line(next_line(trace), "r-expired", "deadline_exceeded", "admission", "none"));
    CHECK(trace->fake.network_requests == before);
    /* A duplicate outstanding identity is a protocol failure. */
    feed(trace, request("dup", "read", read_parameters, 60000, INT64_MAX));
    feed(trace, request("dup", "read", read_parameters, 60000, INT64_MAX));
    CHECK(error_line(next_line(trace), NULL, "invalid_request", "validation", "none"));
    CHECK(trace->owner.finished && trace->owner.status == 70);
    trace_stop(trace);
    free(trace);
    return 0;
}

static int matrix_terminal_paths(void) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    feed(trace, request("w-live", "write", "{\"value\":{}}", 5000, INT64_MAX));
    tick(trace);
    trace->fake.step_fails = true;
    tick(trace);
    CHECK(error_line(next_line(trace), NULL, "connection_failed", "exchange", "unknown"));
    CHECK(trace->owner.finished && trace->owner.status == 70);
    wop_owner_shutdown(&trace->owner);
    CHECK(trace->fake.closes == 1);
    trace_stop(trace);
    free(trace);

    /* A clean owner EOF finishes without output; a truncated line fails. */
    trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    wop_owner_eof(&trace->owner);
    CHECK(trace->owner.finished && trace->owner.status == 0 && remaining_lines(trace) == 0);
    trace_stop(trace);
    free(trace);

    trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    wop_owner_input(&trace->owner, "{\"version\"", 10);
    wop_owner_eof(&trace->owner);
    pump(trace);
    CHECK(error_line(next_line(trace), NULL, "invalid_request", "validation", "none"));
    trace_stop(trace);
    free(trace);

    /* Malformed JSON and a line beyond 131072 bytes end the generation. */
    trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    feed(trace, "{\"version\":1,\"version\":1}\n");
    CHECK(error_line(next_line(trace), NULL, "invalid_request", "validation", "none"));
    trace_stop(trace);
    free(trace);

    trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(open_session(trace) == 0);
    char *oversized = malloc(WOP_JSON_FRAME_BYTES + 1);
    CHECK(oversized);
    memset(oversized, ' ', WOP_JSON_FRAME_BYTES);
    oversized[WOP_JSON_FRAME_BYTES] = '\n';
    wop_owner_input(&trace->owner, oversized, WOP_JSON_FRAME_BYTES + 1);
    free(oversized);
    pump(trace);
    CHECK(error_line(next_line(trace), NULL, "response_limit", "validation", "none"));
    trace_stop(trace);
    free(trace);
    return 0;
}

/* Replies wait behind credit; the 65th unwritten envelope overflows. */
static int matrix_receiver_overflow(void) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(wop_owner_ready(&trace->owner, "fixture-revision", 0));
    pump(trace);
    yyjson_doc_free(next_line(trace));
    feed(trace, "{\"version\":1,\"generation\":1,\"event\":\"credit\",\"sequence\":1,"
                "\"messages\":1,\"bytes\":1}\n");
    for(int i = 0; i < 64; i++) {
        char id[16];
        (void)snprintf(id, sizeof(id), "early-%d", i);
        feed(trace, request(id, "read", read_parameters, 1000, INT64_MAX));
        CHECK(!trace->owner.finished);
    }
    CHECK(trace->owner.output.count == 64 && remaining_lines(trace) == 0);
    feed(trace, request("early-64", "read", read_parameters, 1000, INT64_MAX));
    CHECK(trace->owner.finished);
    CHECK(error_line(next_line(trace), NULL, "receiver_overflow", "exchange", "none"));
    CHECK(trace->owner.output.emitted_messages == 0 && remaining_lines(trace) == 0);
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-X-F21: a suspended owner stops granting credit while reports continue. */
static int credit_overflow(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    yyjson_val *credits = fixture_input(fixture, "credits");
    CHECK(yyjson_get_bool(fixture_input(fixture, "owner_suspended")));
    CHECK(yyjson_get_uint(fixture_input(fixture, "native_buffer_messages")) == WOP_OUTPUT_FRAMES);
    CHECK(yyjson_get_uint(fixture_input(fixture, "native_buffer_bytes")) == WOP_OUTPUT_BYTES);
    CHECK(wop_owner_ready(&trace->owner, "fixture-revision", 0));
    pump(trace);
    yyjson_doc_free(next_line(trace));
    char line[256];
    (void)snprintf(line, sizeof(line),
        "{\"version\":1,\"generation\":1,\"event\":\"credit\",\"sequence\":1,"
        "\"messages\":%" PRIu64 ",\"bytes\":%" PRIu64 "}\n",
        yyjson_get_uint(yyjson_obj_get(credits, "messages")),
        yyjson_get_uint(yyjson_obj_get(credits, "bytes")));
    feed(trace, line);
    feed(trace, request("open-1", "open", open_parameters, 60000, INT64_MAX));
    trace->fake.ready = true;
    tick(trace);
    yyjson_val *result = NULL;
    yyjson_doc *keep = NULL;
    CHECK(success_line(next_line(trace), "open-1", &result, &keep));
    yyjson_doc_free(keep);
    /* Return the open reply's credit so the report stream starts at the full grant. */
    (void)snprintf(line, sizeof(line),
        "{\"version\":1,\"generation\":1,\"event\":\"credit\",\"sequence\":2,"
        "\"messages\":%" PRIu64 ",\"bytes\":%" PRIu64 "}\n",
        trace->owner.output.used_messages, trace->owner.output.used_bytes);
    feed(trace, line);
    CHECK(!trace->owner.finished && trace->owner.output.credit_messages ==
          yyjson_get_uint(yyjson_obj_get(credits, "messages")));
    trace->fake.report_bytes = yyjson_get_uint(fixture_input(fixture, "report_bytes"));
    trace->fake.reports_left = yyjson_get_uint(fixture_input(fixture, "reports"));
    uint64_t emitted_before = trace->owner.output.emitted_messages;
    uint64_t bytes_before = trace->owner.output.emitted_bytes;
    for(int i = 0; i < 1000 && !trace->owner.finished; i++) tick(trace);
    size_t max_buffered = trace->owner.output.peak_count;

    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    CHECK(trace->owner.output.emitted_messages - emitted_before ==
          yyjson_get_uint(yyjson_obj_get(expected, "normal_messages_emitted")));
    CHECK(trace->owner.output.emitted_bytes - bytes_before ==
          yyjson_get_uint(yyjson_obj_get(expected, "normal_bytes_emitted")));
    CHECK(max_buffered == yyjson_get_uint(yyjson_obj_get(expected, "max_buffered_messages")));
    size_t reports = 0;
    yyjson_doc *document;
    while((document = next_line(trace))) {
        yyjson_val *root = yyjson_doc_get_root(document);
        if(yyjson_obj_get(root, "event") && text_is(yyjson_obj_get(root, "event"), "data")) {
            reports++;
            yyjson_doc_free(document);
        } else {
            CHECK(error_line(document, NULL,
                             yyjson_get_str(yyjson_obj_get(expected, "terminal")), "exchange", "none"));
        }
    }
    CHECK(reports == 16 && trace->owner.finished && trace->owner.status == 70);
    wop_owner_shutdown(&trace->owner);
    CHECK(trace->owner.occupied ==
          yyjson_get_uint(yyjson_obj_get(expected, "active_native_resources_after_grace")));
    trace_stop(trace);
    free(trace);
    return 0;
}

/* WOP-X-F29: failed server deletion ends the generation and releases local state. */
static int subscription_delete(yyjson_val *fixture) {
    Trace *trace = calloc(1, sizeof(*trace));
    CHECK(trace && trace_start(trace));
    CHECK(!yyjson_get_bool(fixture_input(fixture, "delete_ack")));
    CHECK(!yyjson_get_bool(fixture_input(fixture, "session_close_ack")));
    CHECK(open_session(trace) == 0);
    trace->fake.unsubscribe_fails = true;
    trace->fake.close_ok = false;
    feed(trace, request("u1", "unsubscribe", "{\"subscription\":\"s1\"}", 1000, INT64_MAX));
    tick(trace);
    trace->fake.outcome[0] = FAKE_SUCCESS;
    tick(trace);
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    CHECK(error_line(next_line(trace), NULL, yyjson_get_str(yyjson_obj_get(expected, "error")),
                     "cleanup", yyjson_get_str(yyjson_obj_get(expected, "effect"))));
    CHECK(trace->owner.finished && trace->owner.status == 70);
    wop_owner_shutdown(&trace->owner);
    CHECK(trace->fake.closes == 1);
    CHECK(trace->owner.occupied ==
          yyjson_get_uint(yyjson_obj_get(expected, "local_resources_after_grace")));
    CHECK(text_is(yyjson_obj_get(expected, "remote_deletion"), "requires_session_expiry_evidence"));
    trace_stop(trace);
    free(trace);
    return 0;
}

static int run_case(yyjson_val *fixture) {
    yyjson_val *operation = yyjson_obj_get(fixture, "operation");
    if(text_is(operation, "native_deadline")) return native_deadline(fixture);
    if(text_is(operation, "cancel_queued")) return cancel_queued(fixture);
    if(text_is(operation, "cancel_transmitted")) return cancel_transmitted(fixture);
    if(text_is(operation, "admission")) return admission(fixture);
    if(text_is(operation, "credit_sequence") || text_is(operation, "credit_capacity"))
        return credit_trace(fixture);
    if(text_is(operation, "invalid_deadline")) return invalid_deadline(fixture);
    if(text_is(operation, "credit_trace")) return credit_overflow(fixture);
    if(text_is(operation, "subscription_delete")) return subscription_delete(fixture);
    return -1;
}

int main(int argc, char **argv) {
    if(argc == 2 && strcmp(argv[1], "--matrix") == 0) {
        int (*cases[])(void) = {matrix_splits_and_order, matrix_request_failures,
                                matrix_terminal_paths, matrix_receiver_overflow};
        for(size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
            int line = cases[i]();
            if(line) {
                printf("{\"status\":\"failed\",\"case\":%zu,\"line\":%d}\n", i, line);
                return 1;
            }
        }
        printf("{\"status\":\"passed\",\"cases\":%zu}\n", sizeof(cases) / sizeof(cases[0]));
        return 0;
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
    int line = selected ? run_case(selected) : -1;
    printf("{\"status\":\"%s\",\"case\":\"%s\",\"line\":%d}\n",
           line == 0 ? "passed" : "failed", argv[2], line);
    yyjson_doc_free(document);
    return line == 0 ? 0 : 1;
}
