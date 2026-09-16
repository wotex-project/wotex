/* SPDX-License-Identifier: Apache-2.0
 * Same-stack process test for the production worker/libcoap boundary.
 */
#define _POSIX_C_SOURCE 200809L
#include <coap3/coap.h>
#include "observation.h"
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <openssl/evp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int coap_remove_option(coap_pdu_t *pdu, coap_option_num_t number);

static unsigned get_count, post_count, large_count, observe_count, cancel_count;
static uint8_t large_body[32769];
static uint8_t observe_token[8];
static size_t observe_token_length;
static coap_mid_t observe_mid, renewal_mid;
static int64_t zero_max_age_at;
static int renewal_fault;
static uint64_t server_start_sequence;
static pid_t worker_child = -1;
static const char *stage = "startup";
static coap_resource_t *observed_resource;
static int notification, notification_streamed, notification_value;
static int initial_max_age_zero;
static const char server_conf[] =
    "master_secret,hex,\"0102030405060708090a0b0c0d0e0f10\"\n"
    "master_salt,hex,\"\"\n"
    "sender_id,hex,\"01\"\nrecipient_id,hex,\"00\"\n"
    "replay_window,integer,32\n"
    "aead_alg,integer,10\nhkdf_alg,integer,-10\n"
    "rfc8613_b_1_2,bool,false\nrfc8613_b_2,bool,false\n"
    "ssn_freq,integer,32\n";

static int64_t now_ms(void) {
    struct timespec value;
    assert(clock_gettime(CLOCK_MONOTONIC, &value) == 0);
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}

static int saved(uint64_t boundary, void *argument) {
    (void)boundary; (void)argument;
    return 1;
}

static void freshness_primitives(void) {
    struct wco_observation_freshness freshness, retained;
    memset(&freshness, 0, sizeof(freshness));
    assert(wco_observation_admit(&freshness, 10, 1000, 1, 0, 0) ==
           WCO_OBSERVATION_FRESH);
    retained = freshness;
    assert(wco_observation_admit(&freshness, 10, 1001, 1, 42, 0) ==
           WCO_OBSERVATION_STALE);
    assert(!memcmp(&freshness, &retained, sizeof(freshness)));
    assert(wco_observation_admit(&freshness, 9, 1002, 0, 0, 0) ==
           WCO_OBSERVATION_STALE);
    assert(!memcmp(&freshness, &retained, sizeof(freshness)));
    assert(wco_observation_admit(&freshness, 10 + 0x800000u, 1003, 1, 0, 0) ==
           WCO_OBSERVATION_STALE);
    assert(!memcmp(&freshness, &retained, sizeof(freshness)));
    assert(wco_observation_admit(&freshness, 11, 1004, 1, 0, 0) ==
           WCO_OBSERVATION_FRESH);
    retained = freshness;
    assert(wco_observation_admit(&freshness, 12, 1005, 1, 42, 0) ==
           WCO_OBSERVATION_CHANGED);
    assert(!memcmp(&freshness, &retained, sizeof(freshness)));
    assert(wco_observation_admit(&freshness, 11, 2000, 1, 0, 1) ==
           WCO_OBSERVATION_FRESH);
    retained = freshness;
    assert(wco_observation_admit(&freshness, 11, 2001, 1, 42, 1) ==
           WCO_OBSERVATION_CHANGED);
    assert(!memcmp(&freshness, &retained, sizeof(freshness)));
    assert(wco_observation_admit(&freshness, 11, 130002, 1, 0, 0) ==
           WCO_OBSERVATION_FRESH);
    memset(&freshness, 0, sizeof(freshness));
    assert(wco_observation_admit(&freshness, 0xffffffu, 1, 1, 0, 0) ==
           WCO_OBSERVATION_FRESH);
    assert(wco_observation_admit(&freshness, 0, 2, 1, 0, 0) ==
           WCO_OBSERVATION_FRESH);
    assert(wco_observation_admit(&freshness, 0x1000000u, 3, 1, 0, 0) ==
           WCO_OBSERVATION_INVALID);
}

static void resource(coap_resource_t *resource, coap_session_t *session,
                     const coap_pdu_t *request, const coap_string_t *query,
                     coap_pdu_t *response) {
    const uint8_t *data = NULL;
    size_t length = 0, offset = 0, total = 0;
    coap_pdu_code_t code = coap_pdu_get_code(request);
    uint8_t format[] = {50}, etag[] = {0xaa};
    if (code == COAP_REQUEST_CODE_GET) {
        coap_opt_iterator_t iterator;
        coap_opt_t *observe = coap_check_option(request, COAP_OPTION_OBSERVE,
                                                &iterator);
        if (observe) {
            coap_opt_iterator_t accept_iterator;
            coap_opt_t *accept = coap_check_option(request, COAP_OPTION_ACCEPT,
                                                   &accept_iterator);
            coap_bin_const_t token = coap_pdu_get_token(request);
            coap_mid_t mid = coap_pdu_get_mid(request);
            uint32_t value = coap_decode_var_bytes(coap_opt_value(observe),
                                                   coap_opt_length(observe));
            char notification_payload[16];
            const char *payload = "20";
            int fault_renewal = renewal_fault && observe_count == 1 &&
                value != COAP_OBSERVE_CANCEL;
            if (notification) {
                assert(snprintf(notification_payload, sizeof(notification_payload),
                                "%d", notification_value ? notification_value : 21) > 0);
                payload = notification_payload;
            }
            assert(query == NULL && value <= 1 && accept &&
                   coap_decode_var_bytes(coap_opt_value(accept),
                                         coap_opt_length(accept)) == 0);
            if (value == COAP_OBSERVE_CANCEL) {
                assert(token.length == observe_token_length &&
                       !memcmp(token.s, observe_token, token.length));
                if (renewal_fault == 5) {
                    assert(renewal_mid != 0 && mid != renewal_mid);
                }
                cancel_count++;
            } else {
                if (notification && observe_count == 1)
                    zero_max_age_at = now_ms();
                if (observe_count == 0) {
                    assert(token.length <= sizeof(observe_token));
                    memcpy(observe_token, token.s, token.length);
                    observe_token_length = token.length;
                    observe_mid = mid;
                } else {
                    assert(token.length == observe_token_length &&
                           !memcmp(token.s, observe_token, token.length));
                    if ((!notification && observe_count == 2) || fault_renewal) {
                        assert(mid != observe_mid);
                        if (renewal_fault == 5) renewal_mid = mid;
                        if (!renewal_fault)
                            assert(now_ms() - zero_max_age_at >= 1000);
                    }
                }
                observe_count++;
            }
            if (fault_renewal) {
                if (renewal_fault == 1) {
                    coap_pdu_set_code(response, COAP_RESPONSE_CODE_BAD_REQUEST);
                    return;
                }
                if (renewal_fault == 2) {
                    coap_resource_set_get_observable(resource, 0);
                    assert(coap_remove_option(response, COAP_OPTION_OBSERVE));
                }
                if (renewal_fault == 4 || renewal_fault == 5) {
                    coap_pdu_set_code(response, COAP_EMPTY_CODE);
                    return;
                }
            }
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
            if (notification && notification_streamed &&
                value != COAP_OBSERVE_CANCEL) {
                assert(coap_add_data_large_response(
                    resource, session, request, response, query, 0, 0, 0,
                    sizeof(large_body), large_body, NULL, NULL));
                return;
            }
            if (fault_renewal && renewal_fault == 3) {
                assert(coap_add_option(response, COAP_OPTION_CONTENT_FORMAT,
                                       1, (const uint8_t *)"*"));
            } else {
                assert(coap_add_option(response, COAP_OPTION_CONTENT_FORMAT, 0, NULL));
            }
            if (initial_max_age_zero)
                assert(coap_add_option(response, COAP_OPTION_MAXAGE, 0, NULL));
            assert(coap_add_data(response, strlen(payload),
                                 (const uint8_t *)payload));
            return;
        }
        assert(query && query->length == 3 && !memcmp(query->s, "x=1", 3));
        get_count++;
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
        assert(coap_add_option(response, COAP_OPTION_ETAG, sizeof(etag), etag));
        assert(coap_add_option(response, COAP_OPTION_CONTENT_FORMAT,
                               sizeof(format), format));
        assert(coap_add_data(response, 2, (const uint8_t *)"42"));
    } else {
        coap_opt_iterator_t iterator;
        coap_opt_t *option;
        assert(code == COAP_REQUEST_CODE_POST && query == NULL);
        option = coap_check_option(request, COAP_OPTION_CONTENT_FORMAT, &iterator);
        assert(option && coap_decode_var_bytes(coap_opt_value(option),
                                               coap_opt_length(option)) == 42);
        assert(coap_get_data_large(request, &length, &data, &offset, &total));
        assert(offset == 0 && length == 2048 && total == 2048);
        for (size_t index = 0; index < length; index++) assert(data[index] == 'A');
        post_count++;
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_CHANGED);
    }
}

static void large_resource(coap_resource_t *resource, coap_session_t *session,
                           const coap_pdu_t *request, const coap_string_t *query,
                           coap_pdu_t *response) {
    assert(coap_pdu_get_code(request) == COAP_REQUEST_CODE_GET && query == NULL);
    large_count++;
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    assert(coap_add_data_large_response(resource, session, request, response, query,
                                        50, 60, 0, sizeof(large_body), large_body,
                                        NULL, NULL));
}

static coap_context_t *server(unsigned *port) {
    coap_context_t *context = coap_new_context(NULL);
    coap_address_t bind;
    coap_endpoint_t *endpoint;
    coap_resource_t *value, *large;
    coap_oscore_conf_t *config = coap_new_oscore_conf(
        (coap_str_const_t){sizeof(server_conf) - 1,
                           (const uint8_t *)server_conf}, saved, NULL,
        server_start_sequence);
    assert(context && config && coap_context_oscore_server(context, config));
    coap_context_set_block_mode(context,
                                COAP_BLOCK_USE_LIBCOAP | COAP_BLOCK_SINGLE_BODY);
    coap_address_init(&bind);
    bind.addr.sin.sin_family = AF_INET;
    assert(inet_pton(AF_INET, "127.0.0.1", &bind.addr.sin.sin_addr) == 1);
    bind.size = sizeof(bind.addr.sin);
    endpoint = coap_new_endpoint(context, &bind, COAP_PROTO_UDP);
    assert(endpoint);
    assert(sscanf(coap_endpoint_str(endpoint), "127.0.0.1:%u UDP", port) == 1);
    assert(*port > 0 && *port <= 65535);
    value = coap_resource_init(coap_make_str_const("value"),
                               COAP_RESOURCE_FLAGS_OSCORE_ONLY);
    assert(value);
    coap_register_handler(value, COAP_REQUEST_GET, resource);
    coap_register_handler(value, COAP_REQUEST_POST, resource);
    coap_resource_set_get_observable(value, 1);
    coap_add_resource(context, value);
    observed_resource = value;
    large = coap_resource_init(coap_make_str_const("large"),
                               COAP_RESOURCE_FLAGS_OSCORE_ONLY);
    assert(large);
    coap_register_handler(large, COAP_REQUEST_GET, large_resource);
    coap_add_resource(context, large);
    return context;
}

static void write_all(int descriptor, const char *bytes) {
    size_t length = strlen(bytes), used = 0;
    while (used < length) {
        ssize_t count = write(descriptor, bytes + used, length - used);
        assert(count > 0);
        used += (size_t)count;
    }
}

static void line(coap_context_t *context, int descriptor,
                 char *output, size_t capacity) {
    static char pending[262144];
    static size_t used;
    int64_t deadline = now_ms() + 12000;
    output[0] = '\0';
    while (now_ms() < deadline) {
        char *newline = memchr(pending, '\n', used);
        ssize_t count;
        if (newline) {
            size_t length = (size_t)(newline - pending) + 1;
            assert(length < capacity);
            memcpy(output, pending, length);
            output[length] = '\0';
            used -= length;
            memmove(pending, pending + length, used);
            return;
        }
        assert(coap_io_process(context, 1) >= 0);
        assert(used < sizeof(pending));
        count = read(descriptor, pending + used, sizeof(pending) - used);
        if (count > 0) {
            used += (size_t)count;
        } else if (count == 0) {
            break;
        } else {
            assert(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR);
        }
    }
    fprintf(stderr, "worker response deadline at %s after %zu buffered bytes\n",
            stage, used);
    if (worker_child > 0) {
        int status = 0;
        pid_t waited = waitpid(worker_child, &status, WNOHANG);
        fprintf(stderr, "custody wait=%ld status=%d exited=%d code=%d\n",
                (long)waited, status, waited == worker_child && WIFEXITED(status),
                waited == worker_child && WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    }
    assert(!"worker response deadline");
}

static void exact(coap_context_t *context, int descriptor, const char *expected) {
    char output[131072];
    line(context, descriptor, output, sizeof(output));
    if (strcmp(output, expected))
        fprintf(stderr, "expected: %sactual: %s", expected, output);
    assert(!strcmp(output, expected));
}

static uint32_t report_observe(const char *line) {
    static const char prefix[] = "\"metadata\":{\"code\":69,\"observe\":";
    const char *value = strstr(line, prefix);
    char *end;
    unsigned long sequence;
    assert(value);
    errno = 0;
    sequence = strtoul(value + sizeof(prefix) - 1, &end, 10);
    assert(errno == 0 && sequence <= 0xfffffful && *end == ',');
    return (uint32_t)sequence;
}

static void assert_report_payload(const char *line, int value) {
    char plain[16], encoded[32], pattern[96];
    int length = snprintf(plain, sizeof(plain), "%d", value);
    int encoded_length;
    assert(length > 0 && (size_t)length < sizeof(plain));
    encoded_length = EVP_EncodeBlock((unsigned char *)encoded,
                                     (const unsigned char *)plain, length);
    assert(encoded_length > 0 && (size_t)encoded_length < sizeof(encoded));
    encoded[encoded_length] = '\0';
    assert(snprintf(pattern, sizeof(pattern),
                    "\"payload\":{\"type\":\"bytes\",\"base64\":\"%s\"}",
                    encoded) > 0);
    assert(strstr(line, pattern));
}

static void pending_notification(coap_context_t *context, int value,
                                 unsigned expected_count) {
    int64_t deadline = now_ms() + 3000;
    int scheduled = 0;
    notification = 1;
    notification_streamed = 0;
    notification_value = value;
    while (!scheduled && now_ms() < deadline) {
        scheduled = coap_resource_notify_observers(observed_resource, NULL);
        if (!scheduled) assert(coap_io_process(context, 1) >= 0);
    }
    if (!scheduled)
        fprintf(stderr, "notification schedule failed at %s value=%d count=%u\n",
                stage, value, observe_count);
    assert(scheduled);
    while (observe_count < expected_count && now_ms() < deadline)
        assert(coap_io_process(context, 1) >= 0);
    assert(observe_count == expected_count);
    for (unsigned attempt = 0; attempt < 50; attempt++)
        assert(coap_io_process(context, 1) >= 0);
}

static void stale_observation(const char *executable) {
    char directory[160], command[8192], output[131072];
    int input[2], result[2], status;
    pid_t child;
    unsigned port;
    coap_context_t *context;
#if defined(__APPLE__)
    assert(snprintf(directory, sizeof(directory),
                    "/private/tmp/wotex-coap-exchange-%ld-stale",
#else
    assert(snprintf(directory, sizeof(directory),
                    "/tmp/wotex-coap-exchange-%ld-stale",
#endif
                    (long)getpid()) > 0);
    assert(mkdir(directory, 0700) == 0);
    assert(pipe(input) == 0 && pipe(result) == 0);
    child = fork();
    assert(child >= 0);
    worker_child = child;
    if (child == 0) {
        assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
        assert(dup2(result[1], STDOUT_FILENO) == STDOUT_FILENO);
        close(input[0]); close(input[1]); close(result[0]); close(result[1]);
        execl(executable, executable, "--custody", directory, (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(result[1]);
    assert(fcntl(result[0], F_SETFL, O_NONBLOCK) == 0);
    get_count = post_count = large_count = observe_count = cancel_count = 0;
    observe_token_length = 0;
    zero_max_age_at = 0;
    notification = 0;
    notification_streamed = 0;
    notification_value = 0;
    initial_max_age_zero = 1;
    context = server(&port);
    stage = "stale ready";
    exact(context, result[0],
          "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
          "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
        "\"host\":\"127.0.0.1\",\"port\":%u,\"generation\":2,\"security\":{"
        "\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\","
        "\"base64\":\"AQIDBAUGBwgJCgsMDQ4PEA==\"},\"master_salt\":{"
        "\"type\":\"bytes\",\"base64\":\"\"},\"sender_id\":{\"type\":\"bytes\","
        "\"base64\":\"AA==\"},\"recipient_id\":{\"type\":\"bytes\","
        "\"base64\":\"AQ==\"},\"id_context\":null,\"context_store\":\"%s\"}},"
        "\"timeout_ms\":5000}\n", port, directory) > 0);
    write_all(input[1], command);
    stage = "stale open";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"2\",\"operation\":\"observe\",\"parameters\":{"
        "\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":"
        "\"property\",\"renew\":false,\"accept\":0},\"timeout_ms\":5000}\n");
    stage = "stale establish";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"2\",\"ok\":true,\"result\":{"
          "\"subscription_id\":\"2\",\"generation\":2}}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"3\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":2,\"ack_seq\":0},\"timeout_ms\":5000}\n");
    stage = "stale credit";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"ok\":true,\"result\":null}\n");
    stage = "stale initial report";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"report_seq\":1,\"event\":\"report\""));
    assert(strstr(output, "\"max_age\":0}"));
    stage = "stale terminal";
    exact(context, result[0],
          "{\"version\":1,\"subscription_id\":\"2\",\"generation\":2,"
          "\"event\":\"error\",\"value\":{\"code\":\"observation_stale\"},"
          "\"metadata\":{}}\n");
    for (unsigned attempt = 0; attempt < 50 && cancel_count == 0; attempt++)
        assert(coap_io_process(context, 1) >= 0);
    assert(cancel_count == 1);
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(input[1]); close(result[0]);
    coap_free_context(context);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
    initial_max_age_zero = 0;
}

static void owner_eof_observation(const char *executable) {
    char directory[192], command[8192], output[131072];
    int input[2], result[2], status = 0;
    int64_t began, deadline;
    pid_t child, waited = 0;
    unsigned port;
    coap_context_t *context;
#if defined(__APPLE__)
    assert(snprintf(directory, sizeof(directory),
                    "/private/tmp/wotex-coap-exchange-%ld-owner-eof",
#else
    assert(snprintf(directory, sizeof(directory),
                    "/tmp/wotex-coap-exchange-%ld-owner-eof",
#endif
                    (long)getpid()) > 0);
    assert(mkdir(directory, 0700) == 0);
    assert(pipe(input) == 0 && pipe(result) == 0);
    child = fork();
    assert(child >= 0);
    worker_child = child;
    if (child == 0) {
        assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
        assert(dup2(result[1], STDOUT_FILENO) == STDOUT_FILENO);
        close(input[0]); close(input[1]); close(result[0]); close(result[1]);
        execl(executable, executable, "--custody", directory, (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(result[1]);
    assert(fcntl(result[0], F_SETFL, O_NONBLOCK) == 0);
    get_count = post_count = large_count = observe_count = cancel_count = 0;
    observe_token_length = 0;
    zero_max_age_at = 0;
    notification = notification_streamed = notification_value = 0;
    initial_max_age_zero = renewal_fault = 0;
    context = server(&port);
    stage = "owner eof ready";
    exact(context, result[0],
          "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
          "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
        "\"host\":\"127.0.0.1\",\"port\":%u,\"generation\":8,\"security\":{"
        "\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\","
        "\"base64\":\"AQIDBAUGBwgJCgsMDQ4PEA==\"},\"master_salt\":{"
        "\"type\":\"bytes\",\"base64\":\"\"},\"sender_id\":{\"type\":\"bytes\","
        "\"base64\":\"AA==\"},\"recipient_id\":{\"type\":\"bytes\","
        "\"base64\":\"AQ==\"},\"id_context\":null,\"context_store\":\"%s\"}},"
        "\"timeout_ms\":5000}\n", port, directory) > 0);
    write_all(input[1], command);
    stage = "owner eof open";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"2\",\"operation\":\"observe\",\"parameters\":{"
        "\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":"
        "\"property\",\"renew\":true,\"accept\":0},\"timeout_ms\":5000}\n");
    stage = "owner eof establish";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"2\",\"ok\":true,\"result\":{"
          "\"subscription_id\":\"2\",\"generation\":8}}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"3\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":8,\"ack_seq\":0},\"timeout_ms\":5000}\n");
    stage = "owner eof credit";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"ok\":true,\"result\":null}\n");
    stage = "owner eof initial";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"report_seq\":1,\"event\":\"report\""));
    began = now_ms();
    assert(close(input[1]) == 0);
    input[1] = -1;
    deadline = began + 1000;
    while (now_ms() < deadline && (cancel_count == 0 || waited == 0)) {
        assert(coap_io_process(context, 1) >= 0);
        if (!waited) {
            waited = waitpid(child, &status, WNOHANG);
            assert(waited >= 0);
        }
    }
    assert(cancel_count == 1);
    assert(waited == child);
    assert(now_ms() - began <= 1000);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 127);
    assert(!coap_resource_notify_observers(observed_resource, NULL));
    close(result[0]);
    coap_free_context(context);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
}

static void renewal_fault_observation(const char *executable, int mode,
                                      const char *value) {
    char directory[192], command[8192], output[131072], expected[512];
    int input[2], result[2], status;
    pid_t child;
    unsigned port;
    coap_context_t *context;
#if defined(__APPLE__)
    assert(snprintf(directory, sizeof(directory),
                    "/private/tmp/wotex-coap-exchange-%ld-fault-%d",
#else
    assert(snprintf(directory, sizeof(directory),
                    "/tmp/wotex-coap-exchange-%ld-fault-%d",
#endif
                    (long)getpid(), mode) > 0);
    assert(mkdir(directory, 0700) == 0);
    assert(pipe(input) == 0 && pipe(result) == 0);
    child = fork();
    assert(child >= 0);
    worker_child = child;
    if (child == 0) {
        assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
        assert(dup2(result[1], STDOUT_FILENO) == STDOUT_FILENO);
        close(input[0]); close(input[1]); close(result[0]); close(result[1]);
        execl(executable, executable, "--custody", directory, (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(result[1]);
    assert(fcntl(result[0], F_SETFL, O_NONBLOCK) == 0);
    get_count = post_count = large_count = observe_count = cancel_count = 0;
    observe_token_length = 0;
    zero_max_age_at = 0;
    notification = 0;
    notification_streamed = 0;
    notification_value = 0;
    initial_max_age_zero = 1;
    renewal_fault = mode;
    context = server(&port);
    stage = "fault ready";
    exact(context, result[0],
          "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
          "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
        "\"host\":\"127.0.0.1\",\"port\":%u,\"generation\":3,\"security\":{"
        "\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\","
        "\"base64\":\"AQIDBAUGBwgJCgsMDQ4PEA==\"},\"master_salt\":{"
        "\"type\":\"bytes\",\"base64\":\"\"},\"sender_id\":{\"type\":\"bytes\","
        "\"base64\":\"AA==\"},\"recipient_id\":{\"type\":\"bytes\","
        "\"base64\":\"AQ==\"},\"id_context\":null,\"context_store\":\"%s\"}},"
        "\"timeout_ms\":1000}\n", port, directory) > 0);
    write_all(input[1], command);
    stage = "fault open";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"2\",\"operation\":\"observe\",\"parameters\":{"
        "\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":"
        "\"property\",\"renew\":true,\"accept\":0},\"timeout_ms\":1000}\n");
    stage = "fault establish";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"2\",\"ok\":true,\"result\":{"
          "\"subscription_id\":\"2\",\"generation\":3}}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"3\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":3,\"ack_seq\":0},\"timeout_ms\":1000}\n");
    stage = "fault credit";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"ok\":true,\"result\":null}\n");
    stage = "fault initial report";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"report_seq\":1,\"event\":\"report\""));
    assert(strstr(output, "\"max_age\":0}"));
    assert(snprintf(expected, sizeof(expected),
          "{\"version\":1,\"subscription_id\":\"2\",\"generation\":3,"
          "\"event\":\"error\",\"value\":%s,\"metadata\":{}}\n", value) > 0);
    stage = "fault terminal";
    exact(context, result[0], expected);
    for (unsigned attempt = 0; attempt < 100 && cancel_count == 0; attempt++)
        assert(coap_io_process(context, 1) >= 0);
    if (mode == 3) assert(cancel_count == 1);
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(input[1]); close(result[0]);
    coap_free_context(context);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
    initial_max_age_zero = 0;
    renewal_fault = 0;
}

static void renewal_cancel_observation(const char *executable) {
    char directory[192], command[8192], output[131072];
    int input[2], result[2], status;
    int64_t deadline;
    pid_t child;
    unsigned port;
    coap_context_t *context;
#if defined(__APPLE__)
    assert(snprintf(directory, sizeof(directory),
                    "/private/tmp/wotex-coap-exchange-%ld-renew-cancel",
#else
    assert(snprintf(directory, sizeof(directory),
                    "/tmp/wotex-coap-exchange-%ld-renew-cancel",
#endif
                    (long)getpid()) > 0);
    assert(mkdir(directory, 0700) == 0);
    assert(pipe(input) == 0 && pipe(result) == 0);
    child = fork();
    assert(child >= 0);
    worker_child = child;
    if (child == 0) {
        assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
        assert(dup2(result[1], STDOUT_FILENO) == STDOUT_FILENO);
        close(input[0]); close(input[1]); close(result[0]); close(result[1]);
        execl(executable, executable, "--custody", directory, (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(result[1]);
    assert(fcntl(result[0], F_SETFL, O_NONBLOCK) == 0);
    get_count = post_count = large_count = observe_count = cancel_count = 0;
    observe_token_length = 0;
    renewal_mid = 0;
    zero_max_age_at = 0;
    notification = notification_streamed = notification_value = 0;
    initial_max_age_zero = 1;
    renewal_fault = 5;
    context = server(&port);
    stage = "renew cancel ready";
    exact(context, result[0],
          "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
          "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
        "\"host\":\"127.0.0.1\",\"port\":%u,\"generation\":7,\"security\":{"
        "\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\","
        "\"base64\":\"AQIDBAUGBwgJCgsMDQ4PEA==\"},\"master_salt\":{"
        "\"type\":\"bytes\",\"base64\":\"\"},\"sender_id\":{\"type\":\"bytes\","
        "\"base64\":\"AA==\"},\"recipient_id\":{\"type\":\"bytes\","
        "\"base64\":\"AQ==\"},\"id_context\":null,\"context_store\":\"%s\"}},"
        "\"timeout_ms\":5000}\n", port, directory) > 0);
    write_all(input[1], command);
    stage = "renew cancel open";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"2\",\"operation\":\"observe\",\"parameters\":{"
        "\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":"
        "\"property\",\"renew\":true,\"accept\":0},\"timeout_ms\":5000}\n");
    stage = "renew cancel establish";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"2\",\"ok\":true,\"result\":{"
          "\"subscription_id\":\"2\",\"generation\":7}}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"3\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":7,\"ack_seq\":0},\"timeout_ms\":5000}\n");
    stage = "renew cancel credit";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"ok\":true,\"result\":null}\n");
    stage = "renew cancel initial";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"report_seq\":1,\"event\":\"report\""));
    assert(strstr(output, "\"max_age\":0}"));
    deadline = now_ms() + 3000;
    while (observe_count < 2 && now_ms() < deadline)
        assert(coap_io_process(context, 1) >= 0);
    assert(observe_count == 2 && renewal_mid != 0 && cancel_count == 0);
    write_all(input[1],
        "{\"version\":1,\"id\":\"4\",\"operation\":\"cancel\",\"parameters\":{"
        "\"subscription_id\":\"2\",\"generation\":7},\"timeout_ms\":1000}\n");
    stage = "renew cancel result";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"4\",\"ok\":false,\"error\":{"
          "\"code\":\"timeout\"}}\n");
    assert(cancel_count == 1);
    assert(!coap_resource_notify_observers(observed_resource, NULL));
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(input[1]); close(result[0]);
    coap_free_context(context);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
    initial_max_age_zero = 0;
    renewal_fault = 0;
    renewal_mid = 0;
}

static void overloaded_observation(const char *executable, int event_kind) {
    char directory[192], command[8192], output[131072], expected[512];
    int input[2], result[2], status;
    pid_t child;
    unsigned port, generation = event_kind ? 5 : 4;
    coap_context_t *context;
#if defined(__APPLE__)
    assert(snprintf(directory, sizeof(directory),
                    "/private/tmp/wotex-coap-exchange-%ld-%s",
#else
    assert(snprintf(directory, sizeof(directory),
                    "/tmp/wotex-coap-exchange-%ld-%s",
#endif
                    (long)getpid(), event_kind ? "event" : "property") > 0);
    assert(mkdir(directory, 0700) == 0);
    assert(pipe(input) == 0 && pipe(result) == 0);
    child = fork();
    assert(child >= 0);
    worker_child = child;
    if (child == 0) {
        assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
        assert(dup2(result[1], STDOUT_FILENO) == STDOUT_FILENO);
        close(input[0]); close(input[1]); close(result[0]); close(result[1]);
        execl(executable, executable, "--custody", directory, (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(result[1]);
    assert(fcntl(result[0], F_SETFL, O_NONBLOCK) == 0);
    get_count = post_count = large_count = observe_count = cancel_count = 0;
    observe_token_length = 0;
    zero_max_age_at = 0;
    notification = notification_streamed = notification_value = 0;
    initial_max_age_zero = renewal_fault = 0;
    context = server(&port);
    stage = "overload ready";
    exact(context, result[0],
          "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
          "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
        "\"host\":\"127.0.0.1\",\"port\":%u,\"generation\":%u,\"security\":{"
        "\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\","
        "\"base64\":\"AQIDBAUGBwgJCgsMDQ4PEA==\"},\"master_salt\":{"
        "\"type\":\"bytes\",\"base64\":\"\"},\"sender_id\":{\"type\":\"bytes\","
        "\"base64\":\"AA==\"},\"recipient_id\":{\"type\":\"bytes\","
        "\"base64\":\"AQ==\"},\"id_context\":null,\"context_store\":\"%s\"}},"
        "\"timeout_ms\":5000}\n", port, generation, directory) > 0);
    write_all(input[1], command);
    stage = "overload open";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":null}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"2\",\"operation\":\"observe\",\"parameters\":{"
        "\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"%s\","
        "\"renew\":false,\"accept\":0},\"timeout_ms\":5000}\n",
        event_kind ? "event" : "property") > 0);
    write_all(input[1], command);
    assert(snprintf(expected, sizeof(expected),
          "{\"version\":1,\"id\":\"2\",\"ok\":true,\"result\":{"
          "\"subscription_id\":\"2\",\"generation\":%u}}\n", generation) > 0);
    stage = "overload establish";
    exact(context, result[0], expected);
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"3\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":%u,\"ack_seq\":0},\"timeout_ms\":5000}\n", generation) > 0);
    write_all(input[1], command);
    stage = "overload credit";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"ok\":true,\"result\":null}\n");
    stage = "overload initial";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"report_seq\":1,\"event\":\"report\""));
    assert_report_payload(output, 20);
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"4\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":%u,\"ack_seq\":1},\"timeout_ms\":5000}\n", generation) > 0);
    write_all(input[1], command);
    stage = "overload initial acknowledgment";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"4\",\"ok\":true,\"result\":null}\n");
    for (unsigned index = 0; index < 8; index++) {
        notification = 1;
        notification_streamed = 0;
        notification_value = 21 + (int)index;
        assert(coap_resource_notify_observers(observed_resource, NULL));
        stage = "overload credited report";
        line(context, result[0], output, sizeof(output));
        assert(snprintf(expected, sizeof(expected), "\"report_seq\":%u,\"event\":\"report\"",
                        index + 2) > 0);
        assert(strstr(output, expected));
        assert_report_payload(output, notification_value);
    }
    assert(observe_count == 9);
    pending_notification(context, 29, 10);
    pending_notification(context, 30, 11);
    if (event_kind) {
        assert(snprintf(expected, sizeof(expected),
              "{\"version\":1,\"subscription_id\":\"2\",\"generation\":%u,"
              "\"event\":\"error\",\"value\":{\"code\":"
              "\"overlapping_event_report\"},\"metadata\":{}}\n", generation) > 0);
        stage = "event overload terminal";
        exact(context, result[0], expected);
        for (unsigned attempt = 0; attempt < 100 && cancel_count == 0; attempt++)
            assert(coap_io_process(context, 1) >= 0);
        assert(cancel_count == 1);
        assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    } else {
        assert(snprintf(command, sizeof(command),
            "{\"version\":1,\"id\":\"5\",\"operation\":\"credit\",\"parameters\":{"
            "\"generation\":%u,\"ack_seq\":9},\"timeout_ms\":5000}\n", generation) > 0);
        write_all(input[1], command);
        stage = "property overload acknowledgment";
        exact(context, result[0],
              "{\"version\":1,\"id\":\"5\",\"ok\":true,\"result\":null}\n");
        stage = "property coalesced report";
        line(context, result[0], output, sizeof(output));
        assert(strstr(output, "\"report_seq\":10,\"event\":\"report\""));
        assert_report_payload(output, 30);
        assert(snprintf(command, sizeof(command),
            "{\"version\":1,\"id\":\"6\",\"operation\":\"cancel\",\"parameters\":{"
            "\"subscription_id\":\"2\",\"generation\":%u},\"timeout_ms\":5000}\n",
            generation) > 0);
        write_all(input[1], command);
        stage = "property overload cancel";
        exact(context, result[0],
              "{\"version\":1,\"id\":\"6\",\"ok\":true,\"result\":null}\n");
        assert(cancel_count == 1);
        write_all(input[1],
            "{\"version\":1,\"id\":\"7\",\"operation\":\"close\",\"parameters\":{},"
            "\"timeout_ms\":5000}\n");
        stage = "property overload close";
        exact(context, result[0],
              "{\"version\":1,\"id\":\"7\",\"ok\":true,\"result\":null}\n");
        assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
    close(input[1]); close(result[0]);
    coap_free_context(context);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
    notification = notification_streamed = notification_value = 0;
}

static void wraparound_observation(const char *executable) {
    char directory[192], command[8192], output[131072];
    int input[2], result[2], status;
    pid_t child;
    unsigned port;
    coap_context_t *context;
#if defined(__APPLE__)
    assert(snprintf(directory, sizeof(directory),
                    "/private/tmp/wotex-coap-exchange-%ld-wrap",
#else
    assert(snprintf(directory, sizeof(directory),
                    "/tmp/wotex-coap-exchange-%ld-wrap",
#endif
                    (long)getpid()) > 0);
    assert(mkdir(directory, 0700) == 0);
    assert(pipe(input) == 0 && pipe(result) == 0);
    child = fork();
    assert(child >= 0);
    worker_child = child;
    if (child == 0) {
        assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
        assert(dup2(result[1], STDOUT_FILENO) == STDOUT_FILENO);
        close(input[0]); close(input[1]); close(result[0]); close(result[1]);
        execl(executable, executable, "--custody", directory, (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(result[1]);
    assert(fcntl(result[0], F_SETFL, O_NONBLOCK) == 0);
    get_count = post_count = large_count = observe_count = cancel_count = 0;
    observe_token_length = 0;
    zero_max_age_at = 0;
    notification = notification_streamed = notification_value = 0;
    initial_max_age_zero = renewal_fault = 0;
    server_start_sequence = 0xffffffu;
    context = server(&port);
    stage = "wrap ready";
    exact(context, result[0],
          "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
          "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
        "\"host\":\"127.0.0.1\",\"port\":%u,\"generation\":6,\"security\":{"
        "\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\","
        "\"base64\":\"AQIDBAUGBwgJCgsMDQ4PEA==\"},\"master_salt\":{"
        "\"type\":\"bytes\",\"base64\":\"\"},\"sender_id\":{\"type\":\"bytes\","
        "\"base64\":\"AA==\"},\"recipient_id\":{\"type\":\"bytes\","
        "\"base64\":\"AQ==\"},\"id_context\":null,\"context_store\":\"%s\"}},"
        "\"timeout_ms\":5000}\n", port, directory) > 0);
    write_all(input[1], command);
    stage = "wrap open";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"2\",\"operation\":\"observe\",\"parameters\":{"
        "\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":"
        "\"property\",\"renew\":false,\"accept\":0},\"timeout_ms\":5000}\n");
    stage = "wrap establish";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"2\",\"ok\":true,\"result\":{"
          "\"subscription_id\":\"2\",\"generation\":6}}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"3\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":6,\"ack_seq\":0},\"timeout_ms\":5000}\n");
    stage = "wrap credit";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"ok\":true,\"result\":null}\n");
    stage = "wrap initial";
    line(context, result[0], output, sizeof(output));
    assert(report_observe(output) == 0xffffffu);
    write_all(input[1],
        "{\"version\":1,\"id\":\"4\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":6,\"ack_seq\":1},\"timeout_ms\":5000}\n");
    stage = "wrap initial acknowledgment";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"4\",\"ok\":true,\"result\":null}\n");
    notification = 1;
    notification_value = 21;
    assert(coap_resource_notify_observers(observed_resource, NULL));
    stage = "wrap report";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"report_seq\":2,\"event\":\"report\""));
    assert(report_observe(output) == 0);
    assert_report_payload(output, 21);
    write_all(input[1],
        "{\"version\":1,\"id\":\"5\",\"operation\":\"cancel\",\"parameters\":{"
        "\"subscription_id\":\"2\",\"generation\":6},\"timeout_ms\":5000}\n");
    stage = "wrap cancel";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"5\",\"ok\":true,\"result\":null}\n");
    assert(cancel_count == 1);
    write_all(input[1],
        "{\"version\":1,\"id\":\"6\",\"operation\":\"close\",\"parameters\":{},"
        "\"timeout_ms\":5000}\n");
    stage = "wrap close";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"6\",\"ok\":true,\"result\":null}\n");
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(input[1]); close(result[0]);
    coap_free_context(context);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
    notification = notification_value = 0;
    server_start_sequence = 0;
}

int main(int argc, char **argv) {
    char directory[128];
    char command[131072], output[131072], encoded[2733], large_encoded[43693];
    uint8_t post_body[2048];
    int input[2], result[2], status;
    pid_t child;
    unsigned port;
    uint32_t initial_observe, streamed_observe, renewed_observe;
    coap_context_t *context;
    assert(argc == 2 && argv[1][0] == '/');
    freshness_primitives();
#if defined(__APPLE__)
    assert(snprintf(directory, sizeof(directory), "/private/tmp/wotex-coap-exchange-%ld",
#else
    assert(snprintf(directory, sizeof(directory), "/tmp/wotex-coap-exchange-%ld",
#endif
                    (long)getpid()) > 0);
    assert(mkdir(directory, 0700) == 0);
    assert(pipe(input) == 0 && pipe(result) == 0);
    child = fork();
    assert(child >= 0);
    worker_child = child;
    if (child == 0) {
        assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
        assert(dup2(result[1], STDOUT_FILENO) == STDOUT_FILENO);
        close(input[0]); close(input[1]); close(result[0]); close(result[1]);
        execl(argv[1], argv[1], "--custody", directory, (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(result[1]);
    assert(fcntl(result[0], F_SETFL, O_NONBLOCK) == 0);
    coap_startup(); coap_set_log_level(COAP_LOG_EMERG);
    observe_token_length = 0;
    zero_max_age_at = 0;
    context = server(&port);
    memset(large_body, 'B', sizeof(large_body));
    stage = "ready";
    exact(context, result[0],
          "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
          "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n");
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"1\",\"operation\":\"open\",\"parameters\":{"
        "\"host\":\"127.0.0.1\",\"port\":%u,\"generation\":1,\"security\":{"
        "\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\","
        "\"base64\":\"AQIDBAUGBwgJCgsMDQ4PEA==\"},\"master_salt\":{"
        "\"type\":\"bytes\",\"base64\":\"\"},\"sender_id\":{\"type\":\"bytes\","
        "\"base64\":\"AA==\"},\"recipient_id\":{\"type\":\"bytes\","
        "\"base64\":\"AQ==\"},\"id_context\":null,\"context_store\":\"%s\"}},"
        "\"timeout_ms\":5000}\n", port, directory) > 0);
    write_all(input[1], command);
    stage = "open";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":null}\n");

    write_all(input[1],
        "{\"version\":1,\"id\":\"2\",\"operation\":\"request\",\"parameters\":{"
        "\"method\":\"GET\",\"path\":\"/value?x=1\",\"confirmable\":true,"
        "\"accept\":50},\"timeout_ms\":5000}\n");
    stage = "get";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"id\":\"2\",\"ok\":true"));
    assert(strstr(output, "\"code\":69"));
    assert(strstr(output, "\"type\":\"con\"") ||
           strstr(output, "\"type\":\"ack\""));
    assert(strstr(output, "\"number\":4,\"value\":{\"type\":\"bytes\","
                          "\"base64\":\"qg==\"}"));
    assert(strstr(output, "\"number\":12,\"value\":{\"type\":\"bytes\","
                          "\"base64\":\"Mg==\"}"));
    assert(strstr(output, "\"payload\":{\"type\":\"bytes\",\"base64\":\"NDI=\"}"));
    assert(!strstr(output, "AQIDBAUGBwgJCgsMDQ4PEA=="));
    assert(get_count == 1);

    write_all(input[1],
        "{\"version\":1,\"id\":\"3\",\"operation\":\"request\",\"parameters\":{"
        "\"method\":\"GET\",\"path\":\"/large\",\"confirmable\":true},"
        "\"timeout_ms\":5000}\n");
    stage = "large begin";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"event\":\"body_begin\","
          "\"body_id\":\"response-body\",\"length\":32769,\"sha256\":"
          "\"de8ef28f32ff275111f82039b9660dd3fc85c8444601c6a7c61d998830942ce3\"}\n");
    assert(EVP_EncodeBlock((unsigned char *)large_encoded, large_body, 32768) == 43692);
    large_encoded[43692] = '\0';
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"3\",\"event\":\"body_chunk\","
        "\"body_id\":\"response-body\",\"offset\":0,\"data\":{\"type\":\"bytes\","
        "\"base64\":\"%s\"}}\n", large_encoded) > 0);
    stage = "large first chunk";
    exact(context, result[0], command);
    stage = "large last chunk";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"event\":\"body_chunk\","
          "\"body_id\":\"response-body\",\"offset\":32768,\"data\":{"
          "\"type\":\"bytes\",\"base64\":\"Qg==\"}}\n");
    stage = "large end";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"event\":\"body_end\","
          "\"body_id\":\"response-body\"}\n");
    stage = "large result";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"id\":\"3\",\"ok\":true"));
    assert(strstr(output, "\"code\":69"));
    assert(strstr(output, "\"body_id\":\"response-body\""));
    assert(!strstr(output, "\"payload\":"));
    assert(large_count > 0);

    write_all(input[1],
        "{\"version\":1,\"id\":\"4\",\"operation\":\"body_begin\",\"parameters\":{"
        "\"body_id\":\"body-1\",\"length\":2048,\"sha256\":"
        "\"3a34c8dc4aec1554c04e0d0e61179d08362b329029db4632f5f086c37be74caa\"},"
        "\"timeout_ms\":5000}\n");
    stage = "body_begin";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"4\",\"ok\":true,\"result\":null}\n");
    memset(post_body, 'A', sizeof(post_body));
    assert(EVP_EncodeBlock((unsigned char *)encoded, post_body,
                           sizeof(post_body)) == 2732);
    encoded[2732] = '\0';
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"5\",\"operation\":\"body_chunk\",\"parameters\":{"
        "\"body_id\":\"body-1\",\"offset\":0,\"data\":{\"type\":\"bytes\","
        "\"base64\":\"%s\"}},\"timeout_ms\":5000}\n", encoded) > 0);
    write_all(input[1], command);
    stage = "body_chunk";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"5\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"6\",\"operation\":\"body_end\",\"parameters\":{"
        "\"body_id\":\"body-1\"},\"timeout_ms\":5000}\n");
    stage = "body_end";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"6\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"7\",\"operation\":\"request\",\"parameters\":{"
        "\"method\":\"POST\",\"path\":\"/value\",\"confirmable\":true,"
        "\"content_format\":42,\"body_id\":\"body-1\"},\"timeout_ms\":5000}\n");
    stage = "post";
    line(context, result[0], output, sizeof(output));
    if (!strstr(output, "\"id\":\"7\",\"ok\":true"))
        fprintf(stderr, "unexpected post response: %s", output);
    assert(strstr(output, "\"id\":\"7\",\"ok\":true"));
    assert(strstr(output, "\"code\":68"));
    assert(strstr(output, "\"payload\":{\"type\":\"bytes\",\"base64\":\"\"}"));
    assert(post_count == 1);

    write_all(input[1],
        "{\"version\":1,\"id\":\"8\",\"operation\":\"observe\",\"parameters\":{"
        "\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":"
        "\"property\",\"renew\":true,\"accept\":0},\"timeout_ms\":5000}\n");
    stage = "observe establish";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"8\",\"ok\":true,\"result\":{"
          "\"subscription_id\":\"8\",\"generation\":1}}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"9\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":1,\"ack_seq\":0},\"timeout_ms\":5000}\n");
    stage = "observe credit";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"9\",\"ok\":true,\"result\":null}\n");
    stage = "initial report";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"subscription_id\":\"8\",\"generation\":1,"));
    assert(strstr(output, "\"report_seq\":1,\"event\":\"report\""));
    assert(strstr(output, "\"payload\":{\"type\":\"bytes\",\"base64\":\"MjA=\"}"));
    assert(strstr(output, "\"metadata\":{\"code\":69,\"observe\":"));
    assert(strstr(output, "\"etag\":null,\"content_format\":0,\"max_age\":60}"));
    initial_observe = report_observe(output);
    assert(observe_count == 1);

    write_all(input[1],
        "{\"version\":1,\"id\":\"10\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":1,\"ack_seq\":1},\"timeout_ms\":5000}\n");
    stage = "observe acknowledgment";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"10\",\"ok\":true,\"result\":null}\n");

    notification = 1;
    notification_streamed = 1;
    assert(coap_resource_notify_observers(observed_resource, NULL));
    stage = "notification begin";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"8\",\"generation\":1,\"report_seq\":2,"
          "\"event\":\"body_begin\",\"body_id\":\"report-body\","
          "\"length\":32769,\"sha256\":"
          "\"de8ef28f32ff275111f82039b9660dd3fc85c8444601c6a7c61d998830942ce3\"}\n");
    assert(EVP_EncodeBlock((unsigned char *)large_encoded, large_body, 32768) == 43692);
    large_encoded[43692] = '\0';
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"8\",\"generation\":1,\"report_seq\":3,"
        "\"event\":\"body_chunk\",\"body_id\":\"report-body\","
        "\"offset\":0,\"data\":{\"type\":\"bytes\",\"base64\":\"%s\"}}\n",
        large_encoded) > 0);
    stage = "notification first chunk";
    exact(context, result[0], command);
    stage = "notification last chunk";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"8\",\"generation\":1,\"report_seq\":4,"
          "\"event\":\"body_chunk\",\"body_id\":\"report-body\","
          "\"offset\":32768,\"data\":{\"type\":\"bytes\",\"base64\":\"Qg==\"}}\n");
    stage = "notification end";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"8\",\"generation\":1,\"report_seq\":5,"
          "\"event\":\"body_end\",\"body_id\":\"report-body\"}\n");
    stage = "notification result";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"subscription_id\":\"8\",\"generation\":1,"));
    assert(strstr(output, "\"report_seq\":6,\"event\":\"report\""));
    assert(strstr(output, "\"body_id\":\"report-body\""));
    assert(!strstr(output, "\"payload\":"));
    assert(strstr(output, "\"max_age\":0}"));
    streamed_observe = report_observe(output);
    assert(streamed_observe == ((initial_observe + 1) & 0xffffffu));
    assert(observe_count == 2);

    write_all(input[1],
        "{\"version\":1,\"id\":\"11\",\"operation\":\"credit\",\"parameters\":{"
        "\"generation\":1,\"ack_seq\":6},\"timeout_ms\":5000}\n");
    stage = "stream acknowledgment";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"11\",\"ok\":true,\"result\":null}\n");

    notification = 0;
    notification_streamed = 0;
    stage = "renewal report";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"subscription_id\":\"8\",\"generation\":1,"));
    assert(strstr(output, "\"report_seq\":7,\"event\":\"report\""));
    assert(strstr(output, "\"payload\":{\"type\":\"bytes\",\"base64\":\"MjA=\"}"));
    renewed_observe = report_observe(output);
    assert(((renewed_observe - streamed_observe) & 0xffffffu) > 0);
    assert(((renewed_observe - streamed_observe) & 0xffffffu) < 0x800000u);
    assert(observe_count == 3);

    write_all(input[1],
        "{\"version\":1,\"id\":\"12\",\"operation\":\"cancel\",\"parameters\":{"
        "\"subscription_id\":\"8\",\"generation\":1},\"timeout_ms\":5000}\n");
    stage = "cancel";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"12\",\"ok\":true,\"result\":null}\n");
    assert(cancel_count == 1);
    assert(!coap_resource_notify_observers(observed_resource, NULL));

    write_all(input[1],
        "{\"version\":1,\"id\":\"13\",\"operation\":\"close\",\"parameters\":{},"
        "\"timeout_ms\":5000}\n");
    stage = "close";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"13\",\"ok\":true,\"result\":null}\n");
    assert(waitpid(child, &status, 0) == child);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        fprintf(stderr, "custody status=%d exited=%d code=%d\n", status,
                WIFEXITED(status), WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(input[1]); close(result[0]);
    coap_free_context(context);
    assert(unlink("/tmp/wotex-coap-exchange-must-not-exist") < 0);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
    stale_observation(argv[1]);
    owner_eof_observation(argv[1]);
    renewal_fault_observation(argv[1], 1,
                              "{\"code\":\"remote_response\",\"status\":128}");
    renewal_fault_observation(argv[1], 2,
                              "{\"code\":\"invalid_observation_response\"}");
    renewal_fault_observation(argv[1], 3,
                              "{\"code\":\"representation_changed\"}");
    renewal_fault_observation(argv[1], 4, "{\"code\":\"timeout\"}");
    renewal_cancel_observation(argv[1]);
    overloaded_observation(argv[1], 0);
    overloaded_observation(argv[1], 1);
    wraparound_observation(argv[1]);
    coap_cleanup();
    puts("WCO-N02/N04: production worker completes unary, streamed and Observe exchanges");
    return 0;
}
