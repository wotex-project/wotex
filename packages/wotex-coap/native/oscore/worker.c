/* SPDX-License-Identifier: Apache-2.0
 * Native OSCORE lifecycle worker. The libcoap exchange engine is added by the
 * next package; this file currently owns exact startup, durable context
 * admission, bounded body/credit state and shutdown without network traffic.
 */
#define _POSIX_C_SOURCE 200809L
#include "worker.h"
#include "body.h"
#include "command.h"
#include "credit.h"
#include "frame.h"
#include "identity.h"
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
#define WCO_REVISION "7cf7465b784baded4de183290c547d582becfd28"

struct output_frame {
    size_t end;
    int64_t deadline;
};

struct output {
    uint8_t bytes[WCO_OUTPUT_MAX];
    size_t used;
    struct output_frame frames[WCO_OUTPUT_FRAMES];
    size_t count;
};

struct worker {
    struct wco_frame frame;
    struct wco_json *json;
    struct wco_body body;
    struct wco_credit credit;
    struct wco_store *store;
    struct output output;
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
    output->frames[output->count++] = (struct output_frame){output->used, deadline};
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
    const char *directory;
    char path[4097];
    size_t directory_length;
    uint64_t generation;
    enum wco_store_status status = WCO_STORE_INVALID;
    yyjson_val *security = field(parameters, "security");
    memset(&identity, 0, sizeof(identity));
    if (!uint_value(parameters, "generation", UINT64_MAX, &generation) ||
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
done:
    erase_secret(&secret);
    OPENSSL_cleanse(&identity, sizeof(identity));
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

static int execute(struct worker *worker, const struct wco_command *command) {
    if (!worker->opened) {
        const char *error;
        if (command->operation != WCO_OPEN) return 0;
        error = open_store(worker, command->parameters);
        return error ? error_response(worker, command, error) : null_response(worker, command);
    }
    if (command->operation == WCO_OPEN) return 0;
    if (command->operation >= WCO_BODY_BEGIN && command->operation <= WCO_BODY_END)
        return body_command(worker, command);
    if (command->operation == WCO_CLOSE) {
        if (!null_response(worker, command)) return 0;
        worker->closing = 1;
        return 1;
    }
    /* Request, Observe and cancel gain their libcoap-owned implementation in
     * the exchange package. Until then they fail before network transmission. */
    return error_response(worker, command, "native_unavailable");
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

static int run(struct worker *worker) {
    static const char ready[] =
        "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
        "\"revision\":\"" WCO_REVISION "\"}\n";
    int64_t now = now_ms();
    if (now < 0 || !append(&worker->output, ready, sizeof(ready) - 1, now + 5000)) return 70;
    for (;;) {
        struct pollfd descriptors[2] = {
            {worker->closing ? -1 : STDIN_FILENO, POLLIN, 0},
            {worker->output.used ? STDOUT_FILENO : -1, POLLOUT, 0}
        };
        int timeout = 50;
        now = now_ms();
        if (now < 0 || (worker->output.count && now >= worker->output.frames[0].deadline))
            return 70;
        if (worker->output.count && worker->output.frames[0].deadline - now < timeout)
            timeout = (int)(worker->output.frames[0].deadline - now);
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
    wco_store_close(worker.store);
    wco_body_clear(&worker.body);
    wco_json_free(worker.json);
    OPENSSL_cleanse(&worker.credit, sizeof(worker.credit));
    OPENSSL_cleanse(&worker.output, sizeof(worker.output));
    return worker.failed ? 70 : status;
}
