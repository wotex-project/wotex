/* SPDX-License-Identifier: Apache-2.0
 * Same-stack process test for the production worker/libcoap boundary.
 */
#define _POSIX_C_SOURCE 200809L
#include <coap3/coap.h>
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

static unsigned get_count, post_count, large_count, observe_count, cancel_count;
static uint8_t large_body[32769];
static uint8_t observe_token[8];
static size_t observe_token_length;
static coap_mid_t observe_mid;
static int64_t zero_max_age_at;
static pid_t worker_child = -1;
static const char *stage = "startup";
static coap_resource_t *observed_resource;
static int notification, initial_max_age_zero;
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
            const char *payload = notification ? "21" : "20";
            assert(query == NULL && value <= 1 && accept &&
                   coap_decode_var_bytes(coap_opt_value(accept),
                                         coap_opt_length(accept)) == 0);
            if (value == COAP_OBSERVE_CANCEL) {
                assert(token.length == observe_token_length &&
                       !memcmp(token.s, observe_token, token.length));
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
                    if (observe_count == 2) {
                        assert(mid != observe_mid);
                        assert(now_ms() - zero_max_age_at >= 1000);
                    }
                }
                observe_count++;
            }
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
            if (notification && value != COAP_OBSERVE_CANCEL) {
                assert(coap_add_data_large_response(
                    resource, session, request, response, query, 0, 0, 0,
                    sizeof(large_body), large_body, NULL, NULL));
                return;
            }
            assert(coap_add_option(response, COAP_OPTION_CONTENT_FORMAT, 0, NULL));
            if (initial_max_age_zero)
                assert(coap_add_option(response, COAP_OPTION_MAXAGE, 0, NULL));
            assert(coap_add_data(response, 2, (const uint8_t *)payload));
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
                           (const uint8_t *)server_conf}, saved, NULL, 0);
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
    int64_t deadline = now_ms() + 7000;
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
    coap_cleanup();
    puts("WCO-N02/N04: production worker completes unary, streamed and Observe exchanges");
    return 0;
}
