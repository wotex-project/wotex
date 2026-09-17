/* SPDX-License-Identifier: Apache-2.0
 * Native OSCORE lifecycle worker. The production build binds the narrow
 * exchange adapter to pinned libcoap; primitive builds omit that dependency
 * and preserve finite pre-network native_unavailable behavior.
 */
#define _POSIX_C_SOURCE 200809L
#include "worker.h"
#include "body.h"
#include "command.h"
#include "credit.h"
#include "exchange.h"
#include "frame.h"
#include "identity.h"
#include "observation.h"
#include "store.h"
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define WCO_OUTPUT_MAX 524288u
#define WCO_CONTROL_MAX 4096u
#define WCO_OUTPUT_FRAMES 128u
#define WCO_INITIAL_BOUNDARY 32u
#define WCO_EXIT_CANCEL_MS 20
#define WCO_REVISION "7cf7465b784baded4de183290c547d582becfd28"
#define WCO_RESPONSE_BODY_ID "response-body"
#define WCO_REPORT_BODY_ID "report-body"

struct output_frame {
    size_t end;
    int64_t deadline;
    uint64_t report_sequence;
    int completes_report;
};

struct output {
    uint8_t bytes[WCO_OUTPUT_MAX];
    size_t used;
    struct output_frame frames[WCO_OUTPUT_FRAMES];
    size_t count;
};

enum stream_phase {
    WCO_STREAM_NONE = 0,
    WCO_STREAM_BEGIN,
    WCO_STREAM_CHUNK,
    WCO_STREAM_END,
    WCO_STREAM_RESULT
};

struct response_stream {
    uint8_t *body;
    size_t length, offset, result_length;
    char sha256[65];
    char result[WCO_JSON_FRAME_MAX];
    enum stream_phase phase;
};

enum report_phase {
    WCO_REPORT_INLINE = 0,
    WCO_REPORT_BEGIN,
    WCO_REPORT_CHUNK,
    WCO_REPORT_END,
    WCO_REPORT_RESULT
};

struct pending_report {
    char value[WCO_JSON_FRAME_MAX];
    size_t value_length;
    uint8_t *body;
    size_t body_length, offset;
    char sha256[65];
    uint32_t observe, max_age;
    uint16_t content_format;
    uint8_t etag[8];
    size_t etag_length;
    uint8_t code;
    enum report_phase phase;
    int content_format_present, etag_present, pending, started;
};

struct observation {
    char id[65];
    char path[4097];
    struct pending_report report, next;
    struct wco_observation_freshness freshness;
    int64_t refresh_at, renewal_deadline;
    uint32_t timeout_ms;
    uint16_t accept;
    int confirmable, accept_present;
    int renew, renewing, initial_written;
    int established, cancelling, event_kind, used;
};

struct worker {
    struct wco_frame frame;
    struct wco_json *json;
    struct wco_body body;
    struct wco_credit credit;
    struct wco_store *store;
    struct wco_exchange *exchange;
    struct output output;
    struct response_stream stream;
    struct observation observation;
    struct {
        char id[65];
        int64_t deadline;
        int active;
    } request;
    uint64_t generation;
    int opened;
    int closing;
    int failed;
};

struct secret {
    uint8_t master[32], salt[32], sender[7], recipient[7], context[255];
    size_t master_length, salt_length, sender_length, recipient_length, context_length;
    int context_present;
};

static yyjson_val *field(yyjson_val *object, const char *name) {
    return yyjson_obj_get(object, name);
}

static int64_t now_ms(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 ||
        (uint64_t)now.tv_sec > (uint64_t)INT64_MAX / 1000u) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int nonblocking(int descriptor) {
    int flags = fcntl(descriptor, F_GETFL);
    return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0;
}

static int append(struct output *output, const char *bytes, size_t length, int64_t deadline) {
    if (!output || !bytes || !length || length > WCO_OUTPUT_MAX - output->used ||
        output->count == WCO_OUTPUT_FRAMES) return 0;
    memcpy(output->bytes + output->used, bytes, length);
    output->used += length;
    output->frames[output->count++] =
        (struct output_frame){output->used, deadline, 0, 0};
    return 1;
}

static int raw(char *line, size_t capacity, size_t *used, const char *bytes) {
    size_t length = strlen(bytes);
    if (length > capacity - *used) return 0;
    memcpy(line + *used, bytes, length);
    *used += length;
    return 1;
}

static int quoted(char *line, size_t capacity, size_t *used, const char *bytes) {
    size_t length = strlen(bytes);
    if (!raw(line, capacity, used, "\"")) return 0;
    for (size_t index = 0; index < length; index++) {
        if (bytes[index] == '"' || bytes[index] == '\\') {
            if (*used > capacity - 2) return 0;
            line[(*used)++] = '\\';
        } else if (*used == capacity) return 0;
        line[(*used)++] = bytes[index];
    }
    return raw(line, capacity, used, "\"");
}

static int response(struct worker *worker, const char *id, const char *result,
                    const char *error, uint32_t timeout_ms) {
    char line[WCO_CONTROL_MAX];
    size_t used = 0;
    int64_t now = now_ms();
    if (now < 0 || !raw(line, sizeof(line), &used, "{\"version\":1,\"id\":" ) ||
        !quoted(line, sizeof(line), &used, id)) return 0;
    if (error) {
        if (!raw(line, sizeof(line), &used, ",\"ok\":false,\"error\":{\"code\":" ) ||
            !quoted(line, sizeof(line), &used, error) ||
            !raw(line, sizeof(line), &used, "}}\n")) return 0;
    } else if (!raw(line, sizeof(line), &used, ",\"ok\":true,\"result\":" ) ||
               !raw(line, sizeof(line), &used, result) ||
               !raw(line, sizeof(line), &used, "}\n")) return 0;
    return append(&worker->output, line, used, now + timeout_ms);
}

static int null_response(struct worker *worker, const struct wco_command *command) {
    return response(worker, command->id, "null", NULL, command->timeout_ms);
}

static int error_response(struct worker *worker, const struct wco_command *command,
                          const char *code) {
    return response(worker, command->id, NULL, code, command->timeout_ms);
}

static int error_deadline_response(struct worker *worker, const char *id,
                                   const char *code, int64_t deadline) {
    char line[WCO_CONTROL_MAX];
    size_t used = 0;
    if (!raw(line, sizeof(line), &used, "{\"version\":1,\"id\":" ) ||
        !quoted(line, sizeof(line), &used, id) ||
        !raw(line, sizeof(line), &used, ",\"ok\":false,\"error\":{\"code\":" ) ||
        !quoted(line, sizeof(line), &used, code) ||
        !raw(line, sizeof(line), &used, "}}\n")) return 0;
    return append(&worker->output, line, used, deadline);
}

static int error_status_response(struct worker *worker, const char *id,
                                 const char *code, uint64_t status,
                                 int64_t deadline) {
    char line[WCO_CONTROL_MAX], number[32];
    size_t used = 0;
    int length = snprintf(number, sizeof(number), "%" PRIu64, status);
    if (length <= 0 || (size_t)length >= sizeof(number) ||
        !raw(line, sizeof(line), &used, "{\"version\":1,\"id\":" ) ||
        !quoted(line, sizeof(line), &used, id) ||
        !raw(line, sizeof(line), &used, ",\"ok\":false,\"error\":{\"code\":" ) ||
        !quoted(line, sizeof(line), &used, code) ||
        !raw(line, sizeof(line), &used, ",\"status\":" ) ||
        (size_t)length > sizeof(line) - used) return 0;
    memcpy(line + used, number, (size_t)length); used += (size_t)length;
    if (!raw(line, sizeof(line), &used, "}}\n")) return 0;
    return append(&worker->output, line, used, deadline);
}

static int result_deadline_response(struct worker *worker, const char *id,
                                    const char *result, int64_t deadline) {
    char line[WCO_CONTROL_MAX];
    size_t used = 0;
    if (!raw(line, sizeof(line), &used, "{\"version\":1,\"id\":" ) ||
        !quoted(line, sizeof(line), &used, id) ||
        !raw(line, sizeof(line), &used, ",\"ok\":true,\"result\":" ) ||
        !raw(line, sizeof(line), &used, result) ||
        !raw(line, sizeof(line), &used, "}\n")) return 0;
    return append(&worker->output, line, used, deadline);
}

static int encoded_bytes(char *line, size_t capacity, size_t *used,
                         const uint8_t *bytes, size_t length) {
    size_t encoded = 4 * ((length + 2) / 3);
    int result;
    if (!raw(line, capacity, used, "{\"type\":\"bytes\",\"base64\":\"") ||
        encoded > capacity - *used || length > INT_MAX) return 0;
    result = EVP_EncodeBlock((unsigned char *)line + *used,
                             length ? bytes : (const uint8_t *)"",
                             (int)length);
    if (result < 0 || (size_t)result != encoded) return 0;
    *used += encoded;
    return raw(line, capacity, used, "\"}");
}

static int message_value(const struct wco_exchange_message *message,
                         const char *body_id, char *line, size_t capacity,
                         size_t *used) {
    char number[64];
    static const char *const types[] = {"con", "non", "ack", "rst"};
    int length;
    if (!raw(line, capacity, used, "{\"type\":" ) ||
        !quoted(line, capacity, used, types[message->type])) return 0;
    length = snprintf(number, sizeof(number),
                      ",\"code\":%u,\"message_id\":%u,\"token\":" ,
                      message->code, message->message_id);
    if (length <= 0 || (size_t)length >= sizeof(number) ||
        (size_t)length > capacity - *used) return 0;
    memcpy(line + *used, number, (size_t)length); *used += (size_t)length;
    if (!encoded_bytes(line, capacity, used, message->token,
                       message->token_length) ||
        !raw(line, capacity, used, ",\"options\":[")) return 0;
    for (size_t index = 0; index < message->option_count; index++) {
        length = snprintf(number, sizeof(number), "%s{\"number\":%u,\"value\":" ,
                          index ? "," : "", message->options[index].number);
        if (length <= 0 || (size_t)length >= sizeof(number) ||
            (size_t)length > capacity - *used) return 0;
        memcpy(line + *used, number, (size_t)length); *used += (size_t)length;
        if (!encoded_bytes(line, capacity, used,
                           message->options[index].value,
                           message->options[index].length) ||
            !raw(line, capacity, used, "}")) return 0;
    }
    if (!raw(line, capacity, used,
             body_id ? "],\"body_id\":" : "],\"payload\":")) return 0;
    if (body_id) {
        if (!quoted(line, capacity, used, body_id)) return 0;
    } else if (!encoded_bytes(line, capacity, used, message->payload,
                              message->payload_length)) return 0;
    return raw(line, capacity, used, "}");
}

static int message_line(struct worker *worker,
                        const struct wco_exchange_message *message,
                        const char *body_id, char *line, size_t *result_length) {
    size_t used = 0;
    if (!raw(line, WCO_JSON_FRAME_MAX, &used, "{\"version\":1,\"id\":" ) ||
        !quoted(line, WCO_JSON_FRAME_MAX, &used, worker->request.id) ||
        !raw(line, WCO_JSON_FRAME_MAX, &used, ",\"ok\":true,\"result\":" ) ||
        !message_value(message, body_id, line, WCO_JSON_FRAME_MAX, &used) ||
        !raw(line, WCO_JSON_FRAME_MAX, &used, "}\n")) return 0;
    *result_length = used;
    return 1;
}

static int message_error(struct worker *worker,
                         const struct wco_exchange_message *message) {
    int valid;
    if (message->type <= 2 && message->code >= 64 && message->code <= 94) return -1;
    if (message->type > 3 || message->type == 3 || message->code < 64 ||
        message->code > 191 || (message->code > 94 && message->code < 128))
        valid = error_deadline_response(worker, worker->request.id,
                                        "invalid_response", worker->request.deadline);
    else
        valid = error_status_response(worker, worker->request.id, "remote_response",
                                      message->code, worker->request.deadline);
    worker->request.active = 0;
    return valid;
}

static int message_response(struct worker *worker,
                            const struct wco_exchange_message *message) {
    char line[WCO_JSON_FRAME_MAX];
    size_t used;
    int status;
    if (!worker->request.active || message->payload_length > WCO_BODY_CHUNK_MAX)
        return 0;
    status = message_error(worker, message);
    if (status >= 0) return status;
    if (!message_line(worker, message, NULL, line, &used)) return 0;
    worker->request.active = 0;
    return append(&worker->output, line, used, worker->request.deadline);
}

static uint32_t option_uint(const uint8_t *bytes, size_t length) {
    uint32_t value = 0;
    for (size_t index = 0; index < length; index++) value = value << 8 | bytes[index];
    return value;
}

static void clear_report(struct pending_report *report) {
    if (report->body) {
        OPENSSL_cleanse(report->body, report->body_length);
        free(report->body);
    }
    OPENSSL_cleanse(report, sizeof(*report));
}

static int sha256_hex(const uint8_t *bytes, size_t length, char output[65]) {
    static const char digits[] = "0123456789abcdef";
    uint8_t digest[EVP_MAX_MD_SIZE];
    unsigned digest_length = 0;
    if (!EVP_Digest(bytes, length, digest, &digest_length, EVP_sha256(), NULL) ||
        digest_length != 32) {
        OPENSSL_cleanse(digest, sizeof(digest));
        return 0;
    }
    for (size_t index = 0; index < digest_length; index++) {
        output[index * 2] = digits[digest[index] >> 4];
        output[index * 2 + 1] = digits[digest[index] & 15u];
    }
    output[64] = '\0';
    OPENSSL_cleanse(digest, sizeof(digest));
    return 1;
}

static int prepare_report(const struct wco_exchange_message *message,
                          struct pending_report *report) {
    size_t used = 0;
    unsigned observe_count = 0, etag_count = 0, format_count = 0, age_count = 0;
    if (message->type > 2 || message->code < 64 || message->code > 94 ||
        message->payload_length > WCO_BODY_MAX) return 0;
    clear_report(report);
    for (size_t index = 0; index < message->option_count; index++) {
        const struct wco_exchange_option *option = &message->options[index];
        switch (option->number) {
            case 4:
                if (++etag_count != 1 || option->length < 1 || option->length > 8)
                    return 0;
                memcpy(report->etag, option->value, option->length);
                report->etag_length = option->length;
                report->etag_present = 1;
                break;
            case 6:
                if (++observe_count != 1 || option->length > 3) return 0;
                report->observe = option_uint(option->value, option->length);
                break;
            case 12:
                if (++format_count != 1 || option->length > 2) return 0;
                report->content_format = (uint16_t)option_uint(option->value,
                                                              option->length);
                report->content_format_present = 1;
                break;
            case 14:
                if (++age_count != 1 || option->length > 4) return 0;
                report->max_age = option_uint(option->value, option->length);
                break;
            default:
                break;
        }
    }
    if (observe_count != 1) return 0;
    report->code = message->code;
    if (!age_count) report->max_age = 60;
    if (message->payload_length > WCO_BODY_CHUNK_MAX) {
        report->body = malloc(message->payload_length);
        if (!report->body) return 0;
        memcpy(report->body, message->payload, message->payload_length);
        report->body_length = message->payload_length;
        report->phase = WCO_REPORT_BEGIN;
        if (!sha256_hex(report->body, report->body_length, report->sha256) ||
            !message_value(message, WCO_REPORT_BODY_ID, report->value,
                           sizeof(report->value), &used)) {
            clear_report(report);
            return 0;
        }
    } else if (!message_value(message, NULL, report->value,
                              sizeof(report->value), &used)) {
        clear_report(report);
        return 0;
    } else {
        report->phase = WCO_REPORT_RESULT;
    }
    report->value_length = used;
    report->pending = 1;
    return 1;
}

static int admit_report(struct observation *observation,
                        const struct pending_report *report, int64_t received_at,
                        int renewal) {
    return wco_observation_admit(&observation->freshness, report->observe,
                                 received_at, report->content_format_present,
                                 report->content_format, renewal);
}

static int arm_observation(struct observation *observation,
                           const struct pending_report *report,
                           int64_t received_at) {
    uint64_t delay = (uint64_t)report->max_age * 1000u;
    if (observation->renew && delay < 1000u) delay = 1000u;
    if (received_at < 0 || delay > (uint64_t)(INT64_MAX - received_at)) return 0;
    observation->refresh_at = received_at + (int64_t)delay;
    return 1;
}

static int observation_open_response(struct worker *worker) {
    char result[256], escaped[256];
    size_t used = 0;
    int length;
    if (!raw(escaped, sizeof(escaped), &used, "{\"subscription_id\":" ) ||
        !quoted(escaped, sizeof(escaped), &used, worker->request.id)) return 0;
    length = snprintf(result, sizeof(result), ",\"generation\":%" PRIu64 "}",
                      worker->generation);
    if (length <= 0 || (size_t)length >= sizeof(result) ||
        (size_t)length > sizeof(escaped) - used) return 0;
    memcpy(escaped + used, result, (size_t)length); used += (size_t)length;
    escaped[used] = '\0';
    return result_deadline_response(worker, worker->request.id, escaped,
                                    worker->request.deadline);
}

static int report_line(struct worker *worker, uint64_t sequence,
                       char *line, size_t *result_length) {
    struct pending_report *report = &worker->observation.report;
    char number[192];
    size_t used = 0;
    int length;
    if (!raw(line, WCO_JSON_FRAME_MAX, &used,
             "{\"version\":1,\"subscription_id\":" ) ||
        !quoted(line, WCO_JSON_FRAME_MAX, &used, worker->observation.id)) return 0;
    length = snprintf(number, sizeof(number),
                      ",\"generation\":%" PRIu64 ",\"report_seq\":%" PRIu64
                      ",\"event\":\"report\",\"value\":" ,
                      worker->generation, sequence);
    if (length <= 0 || (size_t)length >= sizeof(number) ||
        (size_t)length > WCO_JSON_FRAME_MAX - used) return 0;
    memcpy(line + used, number, (size_t)length); used += (size_t)length;
    if (report->value_length > WCO_JSON_FRAME_MAX - used) return 0;
    memcpy(line + used, report->value, report->value_length);
    used += report->value_length;
    length = snprintf(number, sizeof(number),
                      ",\"metadata\":{\"code\":%u,\"observe\":%u,\"etag\":" ,
                      report->code, report->observe);
    if (length <= 0 || (size_t)length >= sizeof(number) ||
        (size_t)length > WCO_JSON_FRAME_MAX - used) return 0;
    memcpy(line + used, number, (size_t)length); used += (size_t)length;
    if (report->etag_present) {
        if (!encoded_bytes(line, WCO_JSON_FRAME_MAX, &used, report->etag,
                           report->etag_length)) return 0;
    } else if (!raw(line, WCO_JSON_FRAME_MAX, &used, "null")) return 0;
    if (!raw(line, WCO_JSON_FRAME_MAX, &used, ",\"content_format\":")) return 0;
    if (report->content_format_present) {
        length = snprintf(number, sizeof(number), "%u", report->content_format);
        if (length <= 0 || (size_t)length >= sizeof(number) ||
            (size_t)length > WCO_JSON_FRAME_MAX - used) return 0;
        memcpy(line + used, number, (size_t)length); used += (size_t)length;
    } else if (!raw(line, WCO_JSON_FRAME_MAX, &used, "null")) return 0;
    length = snprintf(number, sizeof(number), ",\"max_age\":%u}}\n",
                      report->max_age);
    if (length <= 0 || (size_t)length >= sizeof(number) ||
        (size_t)length > WCO_JSON_FRAME_MAX - used) return 0;
    memcpy(line + used, number, (size_t)length); used += (size_t)length;
    *result_length = used;
    return 1;
}

static void move_report(struct pending_report *target,
                        struct pending_report *source) {
    clear_report(target);
    memcpy(target, source, sizeof(*target));
    OPENSSL_cleanse(source, sizeof(*source));
}

static int report_stream_line(struct worker *worker, uint64_t sequence,
                              char *line, size_t *result_length,
                              size_t *chunk_length) {
    struct pending_report *report = &worker->observation.report;
    char number[96];
    size_t used = 0;
    int length;
    *chunk_length = 0;
    if (!raw(line, WCO_JSON_FRAME_MAX, &used, "{\"version\":1,\"id\":" ) ||
        !quoted(line, WCO_JSON_FRAME_MAX, &used, worker->observation.id)) return 0;
    length = snprintf(number, sizeof(number),
                      ",\"generation\":%" PRIu64 ",\"report_seq\":%" PRIu64,
                      worker->generation, sequence);
    if (length <= 0 || (size_t)length >= sizeof(number) ||
        (size_t)length > WCO_JSON_FRAME_MAX - used) return 0;
    memcpy(line + used, number, (size_t)length); used += (size_t)length;
    switch (report->phase) {
        case WCO_REPORT_BEGIN:
            if (!raw(line, WCO_JSON_FRAME_MAX, &used,
                     ",\"event\":\"body_begin\",\"body_id\":" ) ||
                !quoted(line, WCO_JSON_FRAME_MAX, &used, WCO_REPORT_BODY_ID)) return 0;
            length = snprintf(number, sizeof(number), ",\"length\":%zu,\"sha256\":",
                              report->body_length);
            if (length <= 0 || (size_t)length >= sizeof(number) ||
                (size_t)length > WCO_JSON_FRAME_MAX - used) return 0;
            memcpy(line + used, number, (size_t)length); used += (size_t)length;
            if (!quoted(line, WCO_JSON_FRAME_MAX, &used, report->sha256) ||
                !raw(line, WCO_JSON_FRAME_MAX, &used, "}\n")) return 0;
            break;
        case WCO_REPORT_CHUNK:
            *chunk_length = report->body_length - report->offset;
            if (*chunk_length > WCO_BODY_CHUNK_MAX) *chunk_length = WCO_BODY_CHUNK_MAX;
            if (!raw(line, WCO_JSON_FRAME_MAX, &used,
                     ",\"event\":\"body_chunk\",\"body_id\":" ) ||
                !quoted(line, WCO_JSON_FRAME_MAX, &used, WCO_REPORT_BODY_ID)) return 0;
            length = snprintf(number, sizeof(number), ",\"offset\":%zu,\"data\":",
                              report->offset);
            if (length <= 0 || (size_t)length >= sizeof(number) ||
                (size_t)length > WCO_JSON_FRAME_MAX - used) return 0;
            memcpy(line + used, number, (size_t)length); used += (size_t)length;
            if (!encoded_bytes(line, WCO_JSON_FRAME_MAX, &used,
                               report->body + report->offset, *chunk_length) ||
                !raw(line, WCO_JSON_FRAME_MAX, &used, "}\n")) return 0;
            break;
        case WCO_REPORT_END:
            if (!raw(line, WCO_JSON_FRAME_MAX, &used,
                     ",\"event\":\"body_end\",\"body_id\":" ) ||
                !quoted(line, WCO_JSON_FRAME_MAX, &used, WCO_REPORT_BODY_ID) ||
                !raw(line, WCO_JSON_FRAME_MAX, &used, "}\n")) return 0;
            break;
        default:
            return 0;
    }
    *result_length = used;
    return 1;
}

static int pump_report(struct worker *worker) {
    char line[WCO_JSON_FRAME_MAX];
    struct pending_report *report = &worker->observation.report;
    uint64_t expected, sequence;
    size_t chunk_length = 0, used;
    int64_t now;
    if (!report->pending || !wco_credit_available(&worker->credit)) return 1;
    if (worker->credit.assigned == UINT64_MAX) return 0;
    expected = worker->credit.assigned + 1;
    if (report->phase == WCO_REPORT_RESULT) {
        if (!report_line(worker, expected, line, &used)) return 0;
    } else if (!report_stream_line(worker, expected, line, &used, &chunk_length)) {
        return 0;
    }
    if (used > WCO_OUTPUT_MAX - worker->output.used ||
        worker->output.count == WCO_OUTPUT_FRAMES) return 1;
    if ((now = now_ms()) < 0 ||
        wco_credit_assign(&worker->credit, &sequence) != WCO_CREDIT_OK ||
        sequence != expected ||
        !append(&worker->output, line, used, now + 5000)) return 0;
    worker->output.frames[worker->output.count - 1].report_sequence = sequence;
    worker->output.frames[worker->output.count - 1].completes_report =
        report->phase == WCO_REPORT_RESULT;
    report->started = 1;
    switch (report->phase) {
        case WCO_REPORT_BEGIN:
            report->phase = WCO_REPORT_CHUNK;
            break;
        case WCO_REPORT_CHUNK:
            report->offset += chunk_length;
            if (report->offset == report->body_length) report->phase = WCO_REPORT_END;
            break;
        case WCO_REPORT_END:
            report->phase = WCO_REPORT_RESULT;
            break;
        case WCO_REPORT_RESULT:
            clear_report(report);
            if (worker->observation.next.pending)
                move_report(report, &worker->observation.next);
            break;
        default:
            return 0;
    }
    return 1;
}

static void clear_stream(struct response_stream *stream) {
    if (stream->body) {
        OPENSSL_cleanse(stream->body, stream->length);
        free(stream->body);
    }
    OPENSSL_cleanse(stream, sizeof(*stream));
}

static int start_stream(struct worker *worker,
                        const struct wco_exchange_message *message) {
    static const char digits[] = "0123456789abcdef";
    uint8_t digest[EVP_MAX_MD_SIZE];
    unsigned digest_length = 0;
    struct response_stream *stream = &worker->stream;
    if (stream->phase != WCO_STREAM_NONE || !message->payload_length) return 0;
    stream->body = malloc(message->payload_length);
    if (!stream->body) return 0;
    memcpy(stream->body, message->payload, message->payload_length);
    stream->length = message->payload_length;
    if (!EVP_Digest(stream->body, stream->length, digest, &digest_length,
                    EVP_sha256(), NULL) || digest_length != 32 ||
        !message_line(worker, message, WCO_RESPONSE_BODY_ID, stream->result,
                      &stream->result_length)) {
        OPENSSL_cleanse(digest, sizeof(digest));
        clear_stream(stream);
        return 0;
    }
    for (size_t index = 0; index < digest_length; index++) {
        stream->sha256[index * 2] = digits[digest[index] >> 4];
        stream->sha256[index * 2 + 1] = digits[digest[index] & 15u];
    }
    stream->sha256[64] = '\0';
    stream->phase = WCO_STREAM_BEGIN;
    OPENSSL_cleanse(digest, sizeof(digest));
    return 1;
}

static int terminal_observation_status(struct worker *worker, const char *code,
                                       int status_present, uint64_t status) {
    char line[WCO_CONTROL_MAX];
    size_t used = 0;
    int64_t now = now_ms();
    if (now < 0 || !raw(line, sizeof(line), &used,
                        "{\"version\":1,\"subscription_id\":" ) ||
        !quoted(line, sizeof(line), &used, worker->observation.id) ||
        !raw(line, sizeof(line), &used, ",\"generation\":")) return 0;
    char number[32];
    int length = snprintf(number, sizeof(number), "%" PRIu64, worker->generation);
    if (length <= 0 || (size_t)length >= sizeof(number) ||
        (size_t)length > sizeof(line) - used) return 0;
    memcpy(line + used, number, (size_t)length); used += (size_t)length;
    if (!raw(line, sizeof(line), &used,
             ",\"event\":\"error\",\"value\":{\"code\":" ) ||
        !quoted(line, sizeof(line), &used, code)) return 0;
    if (status_present) {
        length = snprintf(number, sizeof(number), ",\"status\":%" PRIu64, status);
        if (length <= 0 || (size_t)length >= sizeof(number) ||
            (size_t)length > sizeof(line) - used) return 0;
        memcpy(line + used, number, (size_t)length); used += (size_t)length;
    }
    if (!raw(line, sizeof(line), &used, "},\"metadata\":{}}\n")) return 0;
    (void)wco_exchange_cancel(worker->exchange, worker->observation.path,
                              worker->observation.accept_present,
                              worker->observation.accept);
    clear_report(&worker->observation.report);
    clear_report(&worker->observation.next);
    worker->observation.established = 0;
    worker->observation.cancelling = 0;
    worker->observation.renewing = 0;
    worker->closing = 1;
    return append(&worker->output, line, used, now + 5000);
}

static int terminal_observation(struct worker *worker, const char *code) {
    return terminal_observation_status(worker, code, 0, 0);
}

static int observation_response(struct worker *worker,
                                const struct wco_exchange_message *message) {
    struct pending_report pending;
    int64_t received_at;
    int admission, status;
    memset(&pending, 0, sizeof(pending));
    if (message->delivery == WCO_EXCHANGE_OBSERVE_INITIAL) {
        if (!worker->request.active) return 0;
        status = message_error(worker, message);
        if (status >= 0) {
            worker->closing = 1;
            return status;
        }
        if (!prepare_report(message, &worker->observation.report)) {
            int valid = error_deadline_response(worker, worker->request.id,
                                                "invalid_observation_response",
                                                worker->request.deadline);
            worker->request.active = 0;
            worker->closing = 1;
            return valid;
        }
        received_at = now_ms();
        admission = admit_report(&worker->observation,
                                 &worker->observation.report, received_at, 0);
        if (admission != 1 ||
            !arm_observation(&worker->observation,
                             &worker->observation.report, received_at)) return 0;
        if (!observation_open_response(worker)) return 0;
        memcpy(worker->observation.id, worker->request.id,
               strlen(worker->request.id) + 1);
        worker->observation.established = 1;
        worker->observation.used = 1;
        worker->request.active = 0;
        return 1;
    }
    if (message->delivery == WCO_EXCHANGE_OBSERVE_REPORT ||
        message->delivery == WCO_EXCHANGE_OBSERVE_RENEWED) {
        int renewal = message->delivery == WCO_EXCHANGE_OBSERVE_RENEWED;
        if (!worker->observation.established || worker->observation.cancelling ||
            (renewal && !worker->observation.renewing))
            return 0;
        if (renewal && (message->code < 64 || message->code > 94))
            return terminal_observation_status(worker, "remote_response", 1,
                                               message->code);
        if (!prepare_report(message, &pending)) {
            clear_report(&pending);
            return terminal_observation(worker,
                                        renewal ? "invalid_observation_response" :
                                        "observation_failed");
        }
        received_at = now_ms();
        admission = admit_report(&worker->observation, &pending, received_at,
                                 renewal);
        if (admission == 0) {
            clear_report(&pending);
            return 1;
        }
        if (admission == -2) {
            clear_report(&pending);
            return terminal_observation(worker, "representation_changed");
        }
        if (admission < 0) {
            clear_report(&pending);
            return 0;
        }
        if (!arm_observation(&worker->observation, &pending, received_at)) {
            clear_report(&pending);
            return 0;
        }
        if (renewal) worker->observation.renewing = 0;
        if (worker->observation.report.pending) {
            if (worker->observation.event_kind) {
                clear_report(&pending);
                return terminal_observation(worker, "overlapping_event_report");
            }
            if (worker->observation.report.started) {
                move_report(&worker->observation.next, &pending);
                return 1;
            }
        }
        move_report(&worker->observation.report, &pending);
        return 1;
    }
    if (message->delivery == WCO_EXCHANGE_OBSERVE_INTERVENING) {
        int valid = worker->observation.established && worker->observation.cancelling &&
            prepare_report(message, &pending);
        clear_report(&pending);
        return valid;
    }
    if (message->delivery == WCO_EXCHANGE_CANCELLED) {
        int valid;
        if (!worker->request.active || !worker->observation.established ||
            !worker->observation.cancelling) return 0;
        status = message_error(worker, message);
        if (status >= 0) {
            worker->closing = 1;
            return status;
        }
        valid = result_deadline_response(worker, worker->request.id, "null",
                                         worker->request.deadline);
        worker->request.active = 0;
        clear_report(&worker->observation.report);
        clear_report(&worker->observation.next);
        OPENSSL_cleanse(worker->observation.id, sizeof(worker->observation.id));
        worker->observation.established = 0;
        worker->observation.cancelling = 0;
        worker->observation.renewing = 0;
        worker->observation.event_kind = 0;
        return valid;
    }
    return 0;
}

static int exchange_response(void *argument,
                             const struct wco_exchange_message *message) {
    struct worker *worker = argument;
    int valid, status;
    if (message->delivery != WCO_EXCHANGE_UNARY)
        valid = observation_response(worker, message);
    else if (!worker->request.active) valid = 0;
    else if (message->payload_length <= WCO_BODY_CHUNK_MAX)
        valid = message_response(worker, message);
    else if ((status = message_error(worker, message)) >= 0) valid = status;
    else if (start_stream(worker, message)) valid = 1;
    else {
        valid = error_deadline_response(worker, worker->request.id,
                                        "native_unavailable",
                                        worker->request.deadline);
        worker->request.active = 0;
    }
    if (!valid) worker->failed = 1;
    return valid;
}

static void exchange_failure(void *argument, const char *code) {
    struct worker *worker = argument;
    if (worker->observation.established && !worker->request.active) {
        if (!terminal_observation(worker, "observation_failed")) worker->failed = 1;
        return;
    }
    if (!worker->request.active) {
        worker->failed = 1;
        return;
    }
    if (!error_deadline_response(worker, worker->request.id, code,
                                 worker->request.deadline))
        worker->failed = 1;
    worker->request.active = 0;
    clear_report(&worker->observation.report);
    clear_report(&worker->observation.next);
    worker->observation.established = 0;
    worker->observation.cancelling = 0;
    worker->observation.renewing = 0;
    worker->closing = 1;
}

static int stream_line(struct worker *worker, char *line, size_t *used,
                       size_t *chunk_length) {
    struct response_stream *stream = &worker->stream;
    char number[32];
    int length;
    *used = 0;
    *chunk_length = 0;
    if (!raw(line, WCO_JSON_FRAME_MAX, used, "{\"version\":1,\"id\":" ) ||
        !quoted(line, WCO_JSON_FRAME_MAX, used, worker->request.id)) return 0;
    switch (stream->phase) {
        case WCO_STREAM_BEGIN:
            if (!raw(line, WCO_JSON_FRAME_MAX, used,
                     ",\"event\":\"body_begin\",\"body_id\":") ||
                !quoted(line, WCO_JSON_FRAME_MAX, used, WCO_RESPONSE_BODY_ID)) return 0;
            length = snprintf(number, sizeof(number), ",\"length\":%zu,\"sha256\":",
                              stream->length);
            if (length <= 0 || (size_t)length >= sizeof(number) ||
                (size_t)length > WCO_JSON_FRAME_MAX - *used) return 0;
            memcpy(line + *used, number, (size_t)length); *used += (size_t)length;
            return quoted(line, WCO_JSON_FRAME_MAX, used, stream->sha256) &&
                raw(line, WCO_JSON_FRAME_MAX, used, "}\n");
        case WCO_STREAM_CHUNK:
            if (!raw(line, WCO_JSON_FRAME_MAX, used,
                     ",\"event\":\"body_chunk\",\"body_id\":") ||
                !quoted(line, WCO_JSON_FRAME_MAX, used, WCO_RESPONSE_BODY_ID)) return 0;
            length = snprintf(number, sizeof(number), ",\"offset\":%zu,\"data\":",
                              stream->offset);
            if (length <= 0 || (size_t)length >= sizeof(number) ||
                (size_t)length > WCO_JSON_FRAME_MAX - *used) return 0;
            memcpy(line + *used, number, (size_t)length); *used += (size_t)length;
            *chunk_length = stream->length - stream->offset;
            if (*chunk_length > WCO_BODY_CHUNK_MAX) *chunk_length = WCO_BODY_CHUNK_MAX;
            return encoded_bytes(line, WCO_JSON_FRAME_MAX, used,
                                 stream->body + stream->offset, *chunk_length) &&
                raw(line, WCO_JSON_FRAME_MAX, used, "}\n");
        case WCO_STREAM_END:
            return raw(line, WCO_JSON_FRAME_MAX, used,
                       ",\"event\":\"body_end\",\"body_id\":") &&
                quoted(line, WCO_JSON_FRAME_MAX, used, WCO_RESPONSE_BODY_ID) &&
                raw(line, WCO_JSON_FRAME_MAX, used, "}\n");
        default:
            return 0;
    }
}

static int pump_stream(struct worker *worker) {
    char line[WCO_JSON_FRAME_MAX];
    struct response_stream *stream = &worker->stream;
    while (stream->phase != WCO_STREAM_NONE) {
        const char *bytes = line;
        size_t used = 0, chunk_length = 0;
        if (stream->phase == WCO_STREAM_RESULT) {
            bytes = stream->result;
            used = stream->result_length;
        } else if (!stream_line(worker, line, &used, &chunk_length)) return 0;
        if (used > WCO_OUTPUT_MAX - worker->output.used ||
            worker->output.count == WCO_OUTPUT_FRAMES) return 1;
        if (!append(&worker->output, bytes, used, worker->request.deadline)) return 0;
        switch (stream->phase) {
            case WCO_STREAM_BEGIN:
                stream->phase = WCO_STREAM_CHUNK;
                break;
            case WCO_STREAM_CHUNK:
                stream->offset += chunk_length;
                if (stream->offset == stream->length) stream->phase = WCO_STREAM_END;
                break;
            case WCO_STREAM_END:
                stream->phase = WCO_STREAM_RESULT;
                break;
            case WCO_STREAM_RESULT:
                clear_stream(stream);
                worker->request.active = 0;
                break;
            default:
                return 0;
        }
    }
    return 1;
}

static int uint_value(yyjson_val *object, const char *name, uint64_t maximum,
                      uint64_t *result) {
    return wco_json_uint(field(object, name), maximum, result);
}

static int string_value(yyjson_val *object, const char *name,
                        const char **bytes, size_t *length) {
    yyjson_val *value = field(object, name);
    if (!yyjson_is_str(value)) return 0;
    *bytes = yyjson_get_str(value);
    *length = yyjson_get_len(value);
    return !memchr(*bytes, 0, *length);
}

static void erase_secret(struct secret *secret) {
    OPENSSL_cleanse(secret, sizeof(*secret));
}

static int decode_secret(yyjson_val *security, struct secret *secret) {
    yyjson_val *context = field(security, "id_context");
    memset(secret, 0, sizeof(*secret));
    if (!wco_body_base64(field(security, "master_secret"), secret->master,
                         sizeof(secret->master), &secret->master_length) ||
        !wco_body_base64(field(security, "master_salt"), secret->salt,
                         sizeof(secret->salt), &secret->salt_length) ||
        !wco_body_base64(field(security, "sender_id"), secret->sender,
                         sizeof(secret->sender), &secret->sender_length) ||
        !wco_body_base64(field(security, "recipient_id"), secret->recipient,
                         sizeof(secret->recipient), &secret->recipient_length)) return 0;
    if (yyjson_is_null(context)) return 1;
    secret->context_present = 1;
    return wco_body_base64(context, secret->context, sizeof(secret->context),
                           &secret->context_length);
}

static const char *open_store(struct worker *worker, yyjson_val *parameters) {
    struct secret secret;
    struct wco_oscore_identity identity;
    const char *directory, *host, *exchange_error = NULL;
    char path[4097];
    size_t directory_length, host_length;
    uint64_t generation, port;
    enum wco_store_status status = WCO_STORE_INVALID;
    yyjson_val *security = field(parameters, "security");
    memset(&identity, 0, sizeof(identity));
    if (!uint_value(parameters, "generation", UINT64_MAX, &generation) ||
        !uint_value(parameters, "port", UINT16_MAX, &port) ||
        !string_value(parameters, "host", &host, &host_length) ||
        !string_value(security, "context_store", &directory, &directory_length) ||
        directory_length >= sizeof(path) || !getcwd(path, sizeof(path)) ||
        strlen(path) != directory_length || memcmp(path, directory, directory_length) ||
        !decode_secret(security, &secret)) goto done;
    struct wco_oscore_material material = {
        .secret = {secret.master, secret.master_length},
        .salt = {secret.salt, secret.salt_length},
        .sender = {secret.sender, secret.sender_length},
        .recipient = {secret.recipient, secret.recipient_length},
        .context = {secret.context, secret.context_length},
        .context_present = secret.context_present
    };
    if (wco_oscore_identity(&material, &identity))
        status = wco_store_open(path, &identity, WCO_INITIAL_BOUNDARY, &worker->store);
    if (status == WCO_STORE_OK) {
        struct wco_exchange_callbacks callbacks = {
            exchange_response, exchange_failure, worker
        };
        exchange_error = wco_exchange_open(host, (uint16_t)port, &material,
                                           worker->store, &callbacks,
                                           &worker->exchange);
        if (exchange_error) {
            wco_store_close(worker->store);
            worker->store = NULL;
        }
    }
done:
    erase_secret(&secret);
    OPENSSL_cleanse(&identity, sizeof(identity));
    if (exchange_error) return exchange_error;
    if (status == WCO_STORE_OK) {
        worker->generation = generation;
        wco_credit_init(&worker->credit, generation);
        worker->opened = 1;
        return NULL;
    }
    return wco_store_code(status);
}

static int body_command(struct worker *worker, const struct wco_command *command) {
    yyjson_val *parameters = command->parameters;
    const char *id, *hash;
    size_t id_length, hash_length;
    uint64_t value;
    if (!string_value(parameters, "body_id", &id, &id_length)) return 0;
    if (command->operation == WCO_BODY_BEGIN) {
        return uint_value(parameters, "length", WCO_BODY_MAX, &value) &&
            string_value(parameters, "sha256", &hash, &hash_length) &&
            wco_body_begin(&worker->body, id, id_length, (size_t)value, hash, hash_length) &&
            null_response(worker, command);
    }
    if (command->operation == WCO_BODY_CHUNK) {
        return uint_value(parameters, "offset", WCO_BODY_MAX, &value) &&
            wco_body_chunk(&worker->body, id, id_length, (size_t)value,
                           field(parameters, "data")) && null_response(worker, command);
    }
    return wco_body_end(&worker->body, id, id_length) && null_response(worker, command);
}

static int request_command(struct worker *worker,
                           const struct wco_command *command) {
    yyjson_val *parameters = command->parameters;
    yyjson_val *body_value = field(parameters, "body_id");
    yyjson_val *accept_value = field(parameters, "accept");
    yyjson_val *format_value = field(parameters, "content_format");
    const char *method, *path, *body_id = NULL;
    const uint8_t *body = NULL;
    size_t method_length, path_length, body_id_length = 0, body_length = 0;
    uint64_t accept = 0, format = 0;
    const char *error;
    int body_present = body_value != NULL;
    int64_t now = now_ms();
    if (worker->request.active) return error_response(worker, command, "busy");
    if (now < 0 || !string_value(parameters, "method", &method, &method_length) ||
        !string_value(parameters, "path", &path, &path_length) ||
        (accept_value && !uint_value(parameters, "accept", UINT16_MAX, &accept)) ||
        (format_value &&
         !uint_value(parameters, "content_format", UINT16_MAX, &format)))
        return 0;
    if (body_present) {
        if (!string_value(parameters, "body_id", &body_id, &body_id_length) ||
            !worker->body.complete || strlen(worker->body.id) != body_id_length ||
            memcmp(worker->body.id, body_id, body_id_length) ||
            !wco_body_data(&worker->body, &body, &body_length))
            return error_response(worker, command, "invalid_request");
    } else if (worker->body.active || worker->body.complete) {
        return error_response(worker, command, "invalid_request");
    }
    memcpy(worker->request.id, command->id, strlen(command->id) + 1);
    worker->request.deadline = now + command->timeout_ms;
    worker->request.active = 1;
    error = wco_exchange_request(worker->exchange, method, path,
                                 yyjson_get_bool(field(parameters, "confirmable")),
                                 accept_value != NULL, (uint16_t)accept,
                                 format_value != NULL, (uint16_t)format,
                                 body_present, body, body_length);
    if (body_present) wco_body_clear(&worker->body);
    if (!error) return 1;
    worker->request.active = 0;
    int valid = error_response(worker, command, error);
    if (!strcmp(error, "connection_closed") ||
        !strcmp(error, "context_store_corrupt") ||
        !strcmp(error, "context_store_full") ||
        !strcmp(error, "context_store_unavailable") ||
        !strcmp(error, "fresh_context_required") ||
        !strcmp(error, "sequence_exhausted"))
        worker->closing = 1;
    return valid;
}

static int observe_command(struct worker *worker,
                           const struct wco_command *command) {
    yyjson_val *parameters = command->parameters;
    yyjson_val *accept_value = field(parameters, "accept");
    const char *path, *kind;
    size_t path_length, kind_length;
    uint64_t accept = 0;
    const char *error;
    int64_t now = now_ms();
    if (worker->observation.used)
        return error_response(worker, command, "invalid_request");
    if (worker->body.active || worker->body.complete)
        return error_response(worker, command, "invalid_request");
    if (now < 0 || !string_value(parameters, "path", &path, &path_length) ||
        !string_value(parameters, "observation_kind", &kind, &kind_length) ||
        (accept_value && !uint_value(parameters, "accept", UINT16_MAX, &accept)))
        return 0;
    memcpy(worker->request.id, command->id, strlen(command->id) + 1);
    worker->request.deadline = now + command->timeout_ms;
    worker->request.active = 1;
    memcpy(worker->observation.path, path, path_length);
    worker->observation.path[path_length] = '\0';
    worker->observation.confirmable =
        yyjson_get_bool(field(parameters, "confirmable"));
    worker->observation.accept_present = accept_value != NULL;
    worker->observation.accept = (uint16_t)accept;
    worker->observation.renew = yyjson_get_bool(field(parameters, "renew"));
    worker->observation.timeout_ms = command->timeout_ms;
    worker->observation.event_kind = kind_length == 5 && !memcmp(kind, "event", 5);
    error = wco_exchange_observe(worker->exchange, worker->observation.path,
                                 worker->observation.confirmable,
                                 accept_value != NULL, (uint16_t)accept);
    if (!error) return 1;
    worker->request.active = 0;
    worker->observation.event_kind = 0;
    int valid = error_response(worker, command, error);
    if (!strcmp(error, "connection_closed") ||
        !strcmp(error, "context_store_corrupt") ||
        !strcmp(error, "context_store_full") ||
        !strcmp(error, "context_store_unavailable") ||
        !strcmp(error, "fresh_context_required") ||
        !strcmp(error, "sequence_exhausted"))
        worker->closing = 1;
    return valid;
}

static int credit_command(struct worker *worker,
                          const struct wco_command *command) {
    uint64_t generation, sequence;
    if (!worker->observation.established || worker->observation.cancelling)
        return error_response(worker, command, "invalid_request");
    if (!uint_value(command->parameters, "generation", UINT64_MAX, &generation) ||
        !uint_value(command->parameters, "ack_seq", UINT64_MAX, &sequence) ||
        wco_credit_ack(&worker->credit, generation, sequence) != WCO_CREDIT_OK)
        return 0;
    return null_response(worker, command);
}

static int cancel_command(struct worker *worker,
                          const struct wco_command *command) {
    const char *subscription_id, *error;
    size_t subscription_length;
    uint64_t generation;
    int64_t now = now_ms();
    if (!worker->observation.established || worker->observation.cancelling ||
        now < 0 ||
        !string_value(command->parameters, "subscription_id", &subscription_id,
                      &subscription_length) ||
        !uint_value(command->parameters, "generation", UINT64_MAX, &generation) ||
        generation != worker->generation ||
        strlen(worker->observation.id) != subscription_length ||
        memcmp(worker->observation.id, subscription_id, subscription_length))
        return error_response(worker, command, "invalid_request");
    memcpy(worker->request.id, command->id, strlen(command->id) + 1);
    worker->request.deadline = now + command->timeout_ms;
    worker->request.active = 1;
    worker->observation.cancelling = 1;
    worker->observation.renewing = 0;
    clear_report(&worker->observation.report);
    clear_report(&worker->observation.next);
    error = wco_exchange_cancel(worker->exchange, worker->observation.path,
                                worker->observation.accept_present,
                                worker->observation.accept);
    if (!error) return 1;
    worker->request.active = 0;
    worker->observation.cancelling = 0;
    worker->closing = 1;
    return error_response(worker, command, error);
}

static int execute(struct worker *worker, const struct wco_command *command) {
    if (!worker->opened) {
        const char *error;
        if (command->operation != WCO_OPEN) return 0;
        error = open_store(worker, command->parameters);
        return error ? error_response(worker, command, error) : null_response(worker, command);
    }
    if (command->operation == WCO_OPEN) return 0;
    if (worker->request.active) return error_response(worker, command, "busy");
    if (worker->observation.established) {
        if (command->operation == WCO_CREDIT) return credit_command(worker, command);
        if (command->operation == WCO_CANCEL) return cancel_command(worker, command);
        if (command->operation != WCO_CLOSE)
            return error_response(worker, command, "observation_active");
    }
    if (command->operation >= WCO_BODY_BEGIN && command->operation <= WCO_BODY_END)
        return body_command(worker, command);
    if (command->operation == WCO_CLOSE) {
        clear_report(&worker->observation.report);
        clear_report(&worker->observation.next);
        if (!null_response(worker, command)) return 0;
        worker->closing = 1;
        return 1;
    }
    if (command->operation == WCO_REQUEST) return request_command(worker, command);
    if (command->operation == WCO_OBSERVE) return observe_command(worker, command);
    return error_response(worker, command, "invalid_request");
}

static int consume(const char *line, size_t length, void *argument) {
    struct worker *worker = argument;
    struct wco_command command;
    int valid = wco_json_parse(worker->json, line, length) == WCO_JSON_OK &&
        wco_command_decode(worker->json, &command) && execute(worker, &command);
    wco_command_clear(&command);
    wco_json_reset(worker->json);
    if (!valid) worker->failed = 1;
    return valid;
}

static int flush_output(struct worker *worker) {
    ssize_t written;
    if (!worker->output.used) return 1;
    written = write(STDOUT_FILENO, worker->output.bytes, worker->output.used);
    if (written > 0) {
        size_t consumed = 0;
        while (consumed < worker->output.count &&
               worker->output.frames[consumed].end <= (size_t)written) consumed++;
        for (size_t index = 0; index < consumed; index++) {
            uint64_t sequence = worker->output.frames[index].report_sequence;
            if (sequence && wco_credit_written(&worker->credit, sequence) != WCO_CREDIT_OK)
                return 0;
            if (worker->output.frames[index].completes_report)
                worker->observation.initial_written = 1;
        }
        for (size_t index = consumed; index < worker->output.count; index++) {
            worker->output.frames[index - consumed] = worker->output.frames[index];
            worker->output.frames[index - consumed].end -= (size_t)written;
        }
        worker->output.count -= consumed;
        worker->output.used -= (size_t)written;
        memmove(worker->output.bytes, worker->output.bytes + written, worker->output.used);
        return 1;
    }
    return written < 0 && (errno == EAGAIN || errno == EINTR);
}

static int maintain_observation(struct worker *worker, int64_t now) {
    struct observation *observation = &worker->observation;
    const char *error;
    if (!observation->established || observation->cancelling ||
        !observation->initial_written) return 1;
    if (observation->renewing) {
        if (now < observation->renewal_deadline) return 1;
        return terminal_observation(worker, "timeout");
    }
    if (now < observation->refresh_at) return 1;
    if (!observation->renew) {
        return terminal_observation(worker, "observation_stale");
    }
    error = wco_exchange_renew(worker->exchange, observation->path,
                               observation->confirmable,
                               observation->accept_present,
                               observation->accept);
    if (error) return terminal_observation(worker, error);
    observation->renewing = 1;
    observation->renewal_deadline = now + observation->timeout_ms;
    return 1;
}

static int run(struct worker *worker) {
    static const char ready[] =
        "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
        "\"revision\":\"" WCO_REVISION "\"}\n";
    int64_t now = now_ms();
    if (now < 0 || !append(&worker->output, ready, sizeof(ready) - 1, now + 5000)) return 70;
    for (;;) {
        struct pollfd descriptors[2];
        int timeout = 50;
        now = now_ms();
        if (now < 0 || (worker->output.count && now >= worker->output.frames[0].deadline))
            return 70;
        if (worker->request.active && now >= worker->request.deadline) {
            if (worker->stream.phase != WCO_STREAM_NONE) {
                clear_stream(&worker->stream);
                worker->failed = 1;
                return 70;
            }
            if (!response(worker, worker->request.id, NULL, "timeout", 500)) return 70;
            worker->request.active = 0;
            worker->closing = 1;
        }
        if (!maintain_observation(worker, now)) return 70;
        if (!pump_stream(worker)) return 70;
        if (!pump_report(worker)) return 70;
        descriptors[0] = (struct pollfd){worker->closing ? -1 : STDIN_FILENO,
                                         POLLIN, 0};
        descriptors[1] = (struct pollfd){worker->output.used ? STDOUT_FILENO : -1,
                                         POLLOUT, 0};
        if (worker->output.count && worker->output.frames[0].deadline - now < timeout)
            timeout = (int)(worker->output.frames[0].deadline - now);
        if (worker->request.active && worker->request.deadline - now < timeout)
            timeout = (int)(worker->request.deadline - now);
        if (!worker->closing && worker->exchange &&
            wco_exchange_wait(worker->exchange, descriptors[0].fd,
                              descriptors[1].fd, timeout))
            timeout = 0;
        if (poll(descriptors, 2, timeout) < 0) {
            if (errno == EINTR) continue;
            return 70;
        }
        if (descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) return 70;
        if ((descriptors[1].revents & POLLOUT) && !flush_output(worker)) return 70;
        if (worker->closing && !worker->output.used) return 0;
        if (descriptors[0].revents & (POLLERR | POLLNVAL)) return 70;
        if (descriptors[0].revents & (POLLIN | POLLHUP)) {
            uint8_t input[32768];
            ssize_t length = read(STDIN_FILENO, input, sizeof(input));
            if (length > 0) {
                if (!wco_frame_feed(&worker->frame, input, (size_t)length, consume, worker))
                    return 70;
            } else if (length == 0) {
                return wco_frame_eof(&worker->frame) ? 0 : 70;
            } else if (errno != EAGAIN && errno != EINTR) return 70;
        }
        if (!worker->closing && worker->exchange)
            (void)wco_exchange_io(worker->exchange);
        if (worker->failed) return 70;
    }
}

static void cancel_observation_on_exit(struct worker *worker) {
    const char *error;
    int64_t deadline;
    if (!worker->exchange || !worker->observation.path[0]) return;
    error = wco_exchange_cancel(worker->exchange, worker->observation.path,
                                worker->observation.accept_present,
                                worker->observation.accept);
    if (error) return;
    (void)wco_exchange_io(worker->exchange);
    /* A peer may answer with an empty ACK and a separate CON response. Keep
     * servicing the exchange until that response is processed and ACKed, so
     * the peer does not retransmit it toward a later client that reuses this
     * UDP endpoint. Custody signals the worker 25 ms after teardown begins. */
    deadline = now_ms() + WCO_EXIT_CANCEL_MS;
    while (wco_exchange_active(worker->exchange)) {
        int64_t now = now_ms();
        if (now < 0 || now >= deadline ||
            !wco_exchange_wait(worker->exchange, -1, -1, (int)(deadline - now)) ||
            !wco_exchange_io(worker->exchange)) break;
    }
}

int wco_worker_main(void) {
    struct worker worker;
    int status = 70;
    memset(&worker, 0, sizeof(worker));
    wco_frame_init(&worker.frame);
    wco_body_init(&worker.body);
    worker.json = wco_json_new();
    if (worker.json && nonblocking(STDIN_FILENO) && nonblocking(STDOUT_FILENO) &&
        OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG, NULL)) status = run(&worker);
    cancel_observation_on_exit(&worker);
    wco_exchange_close(worker.exchange);
    wco_store_close(worker.store);
    clear_stream(&worker.stream);
    clear_report(&worker.observation.report);
    clear_report(&worker.observation.next);
    wco_body_clear(&worker.body);
    wco_json_free(worker.json);
    OPENSSL_cleanse(&worker.credit, sizeof(worker.credit));
    OPENSSL_cleanse(&worker.output, sizeof(worker.output));
    return worker.failed ? 70 : status;
}
