/* SPDX-License-Identifier: Apache-2.0
 * Process fixture: the production native owner, output queue and IPC parser
 * behind an explicitly injected service. It has no OPC UA socket or Session.
 * Behavior is selected only by the request node identity; the fixture never
 * receives an expected result. Counters are written to owner-fixture.json in
 * the working directory when the process exits.
 */
#define _POSIX_C_SOURCE 200809L
#include "../../priv/native/owner.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef enum { MODE_SUCCESS, MODE_HOLD, MODE_DELAY, MODE_BAD, MODE_LOSE } Mode;

typedef struct {
    bool used;
    uint64_t serial;
    unsigned remaining;
    bool fail_after;
    unsigned sent;
} FakeSubscription;

typedef struct {
    FakeSubscription subscriptions[32];
    uint64_t serial;
    unsigned subscribes, unsubscribes, reports;
    Mode mode[WOP_OWNER_OPERATIONS];
    double value[WOP_OWNER_OPERATIONS];
    int64_t ready_at[WOP_OWNER_OPERATIONS];
    bool pending[WOP_OWNER_OPERATIONS];
    bool lose;
    bool slow_open;
    int64_t opened_at;
    unsigned requests, cancels, closes, retired;
} Fixture;

static Fixture fixture;

static int64_t monotonic_ms(void) {
    struct timespec now;
    if(clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int64_t fixture_clock(void *context) {
    (void)context;
    return monotonic_ms();
}

static bool fixture_open(void *context, yyjson_val *parameters, int64_t deadline_ms,
                         WopFailure *failure) {
    (void)context; (void)deadline_ms; (void)failure;
    const char *endpoint = yyjson_get_str(yyjson_obj_get(parameters, "endpoint"));
    fixture.slow_open = endpoint && strstr(endpoint, "slow-open");
    fixture.opened_at = monotonic_ms() + (fixture.slow_open ? 400 : 0);
    return true;
}

static WopCompletion fixture_opened(void *context, yyjson_mut_doc *document,
                                    yyjson_mut_val *result, WopFailure *failure) {
    (void)context; (void)failure;
    if(monotonic_ms() < fixture.opened_at) return WOP_COMPLETION_PENDING;
    yyjson_mut_val *namespaces = yyjson_mut_arr(document);
    return namespaces &&
           yyjson_mut_arr_add_str(document, namespaces, "http://opcfoundation.org/UA/") &&
           yyjson_mut_arr_add_str(document, namespaces, "urn:fixture") &&
           yyjson_mut_obj_add_real(document, result, "session_timeout_ms", 60000.0) &&
           yyjson_mut_obj_add_val(document, result, "namespace_array", namespaces)
               ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
}

static bool fixture_prepare(void *context, const WopOperation *operation,
                            yyjson_val *parameters, WopFailure *failure) {
    (void)context; (void)failure;
    size_t slot = operation->index;
    if(operation->kind == WOP_OPERATION_UNSUBSCRIBE) {
        const char *token = yyjson_get_str(yyjson_obj_get(parameters, "subscription"));
        uint64_t serial = token && token[0] == 's' ? strtoull(token + 1, NULL, 10) : 0;
        for(size_t i = 0; i < 32; i++) {
            if(fixture.subscriptions[i].used && fixture.subscriptions[i].serial == serial) {
                fixture.value[slot] = (double)i;
                fixture.mode[slot] = MODE_SUCCESS;
                return true;
            }
        }
        return false;
    }
    const char *node = yyjson_get_str(yyjson_obj_get(parameters, "node_id"));
    if(!node) node = yyjson_get_str(yyjson_obj_get(parameters, "object_id"));
    if(operation->kind == WOP_OPERATION_SUBSCRIBE && node) {
        const char *name = strncmp(node, "ns=1;s=", 7) == 0 ? node + 7 : "";
        bool stream = strncmp(name, "stream-", 7) == 0, error = strncmp(name, "error-", 6) == 0;
        if(!stream && !error) return false;
        fixture.mode[slot] = MODE_SUCCESS;
        fixture.value[slot] = (double)atoll(name + (stream ? 7 : 6));
        fixture.ready_at[slot] = error;
        return true;
    }
    if(!node || strncmp(node, "ns=1;s=", 7) != 0) return false;
    const char *name = node + 7;
    fixture.value[slot] = 0;
    fixture.ready_at[slot] = 0;
    if(strncmp(name, "hold", 4) == 0) {
        fixture.mode[slot] = MODE_HOLD;
    } else if(strncmp(name, "delay-", 6) == 0) {
        fixture.mode[slot] = MODE_DELAY;
        fixture.ready_at[slot] = atoll(name + 6);
    } else if(strcmp(name, "bad") == 0) {
        fixture.mode[slot] = MODE_BAD;
    } else if(strcmp(name, "lose") == 0) {
        fixture.mode[slot] = MODE_LOSE;
    } else if(strncmp(name, "value-", 6) == 0) {
        fixture.mode[slot] = MODE_SUCCESS;
        fixture.value[slot] = (double)atoll(name + 6);
    } else {
        return false;
    }
    return true;
}

static bool fixture_dispatch(void *context, const WopOperation *operation, uint32_t timeout_ms,
                             WopFailure *failure) {
    (void)context; (void)timeout_ms; (void)failure;
    size_t slot = operation->index;
    fixture.requests++;
    fixture.pending[slot] = true;
    if(fixture.mode[slot] == MODE_DELAY) fixture.ready_at[slot] += monotonic_ms();
    if(fixture.mode[slot] == MODE_LOSE) fixture.lose = true;
    return true;
}

static WopCompletion fixture_complete(void *context, const WopOperation *operation,
                                      yyjson_mut_doc *document, yyjson_mut_val **result,
                                      WopFailure *failure) {
    (void)context;
    size_t slot = operation->index;
    switch(fixture.mode[slot]) {
    case MODE_HOLD:
    case MODE_LOSE:
        return WOP_COMPLETION_PENDING;
    case MODE_DELAY:
        if(monotonic_ms() < fixture.ready_at[slot]) return WOP_COMPLETION_PENDING;
        break;
    case MODE_BAD:
        fixture.pending[slot] = false;
        failure->code = "remote_error";
        failure->phase = "exchange";
        failure->has_status = true;
        failure->status = 0x803B0000U;
        return WOP_COMPLETION_FAILURE;
    case MODE_SUCCESS:
        break;
    }
    fixture.pending[slot] = false;
    if(operation->kind == WOP_OPERATION_UNSUBSCRIBE) {
        fixture.subscriptions[(size_t)fixture.value[slot]].used = false;
        fixture.unsubscribes++;
        *result = yyjson_mut_null(document);
        return *result ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
    }
    *result = yyjson_mut_obj(document);
    if(!*result) return WOP_COMPLETION_TERMINAL;
    bool built;
    if(operation->kind == WOP_OPERATION_SUBSCRIBE) {
        size_t index = 0;
        while(index < 32 && fixture.subscriptions[index].used) index++;
        if(index == 32) return WOP_COMPLETION_TERMINAL;
        FakeSubscription *subscription = &fixture.subscriptions[index];
        memset(subscription, 0, sizeof(*subscription));
        subscription->used = true;
        subscription->serial = ++fixture.serial;
        subscription->remaining = (unsigned)fixture.value[slot];
        subscription->fail_after = fixture.ready_at[slot] != 0;
        fixture.subscribes++;
        char token[24];
        (void)snprintf(token, sizeof(token), "s%llu", (unsigned long long)subscription->serial);
        built = yyjson_mut_obj_add_strcpy(document, *result, "subscription", token) &&
                yyjson_mut_obj_add_uint(document, *result, "subscription_id", 100 + subscription->serial) &&
                yyjson_mut_obj_add_uint(document, *result, "monitored_item_id", 200 + subscription->serial) &&
                yyjson_mut_obj_add_uint(document, *result, "client_handle", subscription->serial) &&
                yyjson_mut_obj_add_real(document, *result, "publishing_interval_ms", 500.5) &&
                yyjson_mut_obj_add_real(document, *result, "sampling_interval_ms", 250.25) &&
                yyjson_mut_obj_add_uint(document, *result, "queue_size", 10) &&
                yyjson_mut_obj_add_uint(document, *result, "lifetime_count", 30) &&
                yyjson_mut_obj_add_uint(document, *result, "keepalive_count", 10) &&
                yyjson_mut_obj_add_uint(document, *result, "item_status", 0);
    } else if(operation->kind == WOP_OPERATION_WRITE) {
        built = yyjson_mut_obj_add_uint(document, *result, "status", 0);
    } else if(operation->kind == WOP_OPERATION_CALL) {
        built = yyjson_mut_obj_add_uint(document, *result, "status", 0) &&
                yyjson_mut_obj_add_val(document, *result, "input_argument_statuses",
                                       yyjson_mut_arr(document)) &&
                yyjson_mut_obj_add_val(document, *result, "outputs", yyjson_mut_arr(document));
    } else {
        yyjson_mut_val *variant = yyjson_mut_obj(document);
        built = variant && yyjson_mut_obj_add_str(document, variant, "type", "Double") &&
                yyjson_mut_obj_add_bool(document, variant, "array", false) &&
                yyjson_mut_obj_add_real(document, variant, "value", fixture.value[slot]) &&
                yyjson_mut_obj_add_bool(document, *result, "has_value", true) &&
                yyjson_mut_obj_add_val(document, *result, "value", variant) &&
                yyjson_mut_obj_add_uint(document, *result, "status", 0);
    }
    return built ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
}

/* Emits queued fake reports: data values 1..N, then one error when requested. */
static bool fixture_report(void *context, yyjson_mut_doc *document, yyjson_mut_val *envelope,
                           bool *produced, WopFailure *failure) {
    (void)context; (void)failure;
    *produced = false;
    for(size_t i = 0; i < 32; i++) {
        FakeSubscription *subscription = &fixture.subscriptions[i];
        if(!subscription->used || (!subscription->remaining && !subscription->fail_after)) continue;
        char token[24];
        (void)snprintf(token, sizeof(token), "s%llu", (unsigned long long)subscription->serial);
        yyjson_mut_val *value = yyjson_mut_obj(document);
        yyjson_mut_val *metadata = yyjson_mut_obj(document);
        if(!value || !metadata || !yyjson_mut_obj_add_strcpy(document, envelope, "subscription_id", token))
            return false;
        if(subscription->remaining) {
            subscription->remaining--;
            subscription->sent++;
            yyjson_mut_val *variant = yyjson_mut_obj(document);
            if(!variant || !yyjson_mut_obj_add_str(document, variant, "type", "Double") ||
               !yyjson_mut_obj_add_bool(document, variant, "array", false) ||
               !yyjson_mut_obj_add_real(document, variant, "value", (double)subscription->sent) ||
               !yyjson_mut_obj_add_bool(document, value, "has_value", true) ||
               !yyjson_mut_obj_add_val(document, value, "value", variant) ||
               !yyjson_mut_obj_add_uint(document, value, "status", 0) ||
               !yyjson_mut_obj_add_uint(document, metadata, "sequence", subscription->sent) ||
               !yyjson_mut_obj_add_sint(document, metadata, "publish_time", 1000 + subscription->sent) ||
               !yyjson_mut_obj_add_uint(document, metadata, "client_handle", subscription->serial) ||
               !yyjson_mut_obj_add_bool(document, metadata, "overflow", false) ||
               !yyjson_mut_obj_add_uint(document, metadata, "datetime_resolution_ns", 100) ||
               !yyjson_mut_obj_add_bool(document, metadata, "raw_datetime_ticks_available", true) ||
               !yyjson_mut_obj_add_str(document, envelope, "event", "data"))
                return false;
        } else {
            subscription->used = false;
            if(!yyjson_mut_obj_add_str(document, value, "code", "sequence_gap") ||
               !yyjson_mut_obj_add_str(document, value, "phase", "exchange") ||
               !yyjson_mut_obj_add_str(document, value, "effect", "none") ||
               !yyjson_mut_obj_add_str(document, envelope, "event", "error"))
                return false;
        }
        fixture.reports++;
        *produced = yyjson_mut_obj_add_val(document, envelope, "value", value) &&
                    yyjson_mut_obj_add_val(document, envelope, "metadata", metadata);
        return *produced;
    }
    return true;
}

static void fixture_cancel(void *context, const WopOperation *operation) {
    (void)context;
    fixture.cancels++;
    /* The fixture's protocol cancellation completes the callback. */
    fixture.pending[operation->index] = false;
}

static void fixture_retire(void *context, const WopOperation *operation) {
    (void)context; (void)operation;
    fixture.retired++;
}

static bool fixture_released(void *context, const WopOperation *operation) {
    (void)context;
    return !fixture.pending[operation->index];
}

static bool fixture_step(void *context, int slice_ms, WopFailure *failure) {
    (void)context; (void)slice_ms; (void)failure;
    return !fixture.lose;
}

static bool fixture_close(void *context) {
    (void)context;
    fixture.closes++;
    memset(fixture.pending, 0, sizeof(fixture.pending));
    return true;
}

static void write_counters(const WopOwner *owner) {
    FILE *file = fopen("owner-fixture.json.tmp", "w");
    if(!file) return;
    fprintf(file,
            "{\"requests\":%u,\"cancels\":%u,\"closes\":%u,\"retired\":%u,"
            "\"occupied\":%zu,\"emitted_messages\":%" PRIu64 ",\"status\":%d,"
            "\"subscribes\":%u,\"unsubscribes\":%u,\"reports\":%u}\n",
            fixture.requests, fixture.cancels, fixture.closes, fixture.retired,
            owner->occupied, owner->output.emitted_messages, owner->status,
            fixture.subscribes, fixture.unsubscribes, fixture.reports);
    if(fclose(file) == 0) (void)rename("owner-fixture.json.tmp", "owner-fixture.json");
}

int main(void) {
    FILE *identity = fopen("host.pid", "wx");
    if(!identity) return 41;
    fprintf(identity, "%ld %ld\n", (long)getpid(), (long)getppid());
    if(fclose(identity)) return 42;
    int flags = fcntl(STDOUT_FILENO, F_GETFL);
    if(flags < 0 || fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK) < 0) return 70;
    WopService service = {
        NULL, fixture_open, fixture_opened, fixture_prepare, fixture_dispatch,
        fixture_complete, fixture_cancel, fixture_retire, fixture_released, fixture_step,
        fixture_close, fixture_report, NULL
    };
    static WopOwner owner;
    if(!wop_owner_init(&owner, &service, fixture_clock, NULL) ||
       !wop_owner_ready(&owner, "d1173ccc31560ffc60c29e24ce8adb19f8c3c686", monotonic_ms()) ||
       wop_output_flush(&owner.output, STDOUT_FILENO) != WOP_OUTPUT_OK)
        return 70;
    owner.output_descriptor = STDOUT_FILENO;
    int status = 70;
    for(;;) {
        wop_owner_tick(&owner, 0);
        if(wop_output_flush(&owner.output, STDOUT_FILENO) != WOP_OUTPUT_OK) goto done;
        if(owner.finished) break;
        struct pollfd descriptors[2] = {
            {STDIN_FILENO, POLLIN, 0},
            {STDOUT_FILENO, wop_output_writable(&owner.output) ? POLLOUT : 0, 0}
        };
        int polled = poll(descriptors, 2, 1);
        if(polled < 0 && errno == EINTR) continue;
        if(polled < 0) goto done;
        if(!(descriptors[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL))) continue;
        char buffer[4096];
        ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
        if(count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if(count < 0) goto done;
        if(count == 0) wop_owner_eof(&owner);
        else wop_owner_input(&owner, buffer, (size_t)count);
        if(wop_output_flush(&owner.output, STDOUT_FILENO) != WOP_OUTPUT_OK) goto done;
    }
    status = owner.status;
done:
    for(int i = 0; i < 100 && !wop_output_drained(&owner.output) &&
                   wop_output_writable(&owner.output); i++) {
        struct pollfd descriptor = {STDOUT_FILENO, POLLOUT, 0};
        if(poll(&descriptor, 1, 1) > 0 &&
           wop_output_flush(&owner.output, STDOUT_FILENO) != WOP_OUTPUT_OK)
            break;
    }
    wop_owner_shutdown(&owner);
    write_counters(&owner);
    wop_owner_clear(&owner);
    return status;
}
