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

static unsigned get_count, post_count;
static const char *stage = "startup";
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
    (void)resource; (void)session;
    if (code == COAP_REQUEST_CODE_GET) {
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

static coap_context_t *server(unsigned *port) {
    coap_context_t *context = coap_new_context(NULL);
    coap_address_t bind;
    coap_endpoint_t *endpoint;
    coap_resource_t *value;
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
    coap_add_resource(context, value);
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
    size_t used = 0;
    int64_t deadline = now_ms() + 5000;
    output[0] = '\0';
    while (now_ms() < deadline) {
        ssize_t count;
        assert(coap_io_process(context, 1) >= 0);
        count = read(descriptor, output + used, capacity - 1 - used);
        if (count > 0) {
            char *newline;
            used += (size_t)count;
            output[used] = '\0';
            newline = strchr(output, '\n');
            if (newline) {
                assert((size_t)(newline - output) + 1 == used);
                return;
            }
        } else if (count == 0) {
            break;
        } else {
            assert(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR);
        }
    }
    fprintf(stderr, "worker response deadline at %s after %zu bytes: %s\n",
            stage, used, output);
    assert(!"worker response deadline");
}

static void exact(coap_context_t *context, int descriptor, const char *expected) {
    char output[131072];
    line(context, descriptor, output, sizeof(output));
    if (strcmp(output, expected))
        fprintf(stderr, "expected: %sactual: %s", expected, output);
    assert(!strcmp(output, expected));
}

int main(int argc, char **argv) {
    char directory[128];
    char command[8192], output[131072], encoded[2733];
    uint8_t post_body[2048];
    int input[2], result[2], status;
    pid_t child;
    unsigned port;
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
    context = server(&port);
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
        "{\"version\":1,\"id\":\"3\",\"operation\":\"body_begin\",\"parameters\":{"
        "\"body_id\":\"body-1\",\"length\":2048,\"sha256\":"
        "\"3a34c8dc4aec1554c04e0d0e61179d08362b329029db4632f5f086c37be74caa\"},"
        "\"timeout_ms\":5000}\n");
    stage = "body_begin";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"3\",\"ok\":true,\"result\":null}\n");
    memset(post_body, 'A', sizeof(post_body));
    assert(EVP_EncodeBlock((unsigned char *)encoded, post_body,
                           sizeof(post_body)) == 2732);
    encoded[2732] = '\0';
    assert(snprintf(command, sizeof(command),
        "{\"version\":1,\"id\":\"4\",\"operation\":\"body_chunk\",\"parameters\":{"
        "\"body_id\":\"body-1\",\"offset\":0,\"data\":{\"type\":\"bytes\","
        "\"base64\":\"%s\"}},\"timeout_ms\":5000}\n", encoded) > 0);
    write_all(input[1], command);
    stage = "body_chunk";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"4\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"5\",\"operation\":\"body_end\",\"parameters\":{"
        "\"body_id\":\"body-1\"},\"timeout_ms\":5000}\n");
    stage = "body_end";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"5\",\"ok\":true,\"result\":null}\n");
    write_all(input[1],
        "{\"version\":1,\"id\":\"6\",\"operation\":\"request\",\"parameters\":{"
        "\"method\":\"POST\",\"path\":\"/value\",\"confirmable\":true,"
        "\"content_format\":42,\"body_id\":\"body-1\"},\"timeout_ms\":5000}\n");
    stage = "post";
    line(context, result[0], output, sizeof(output));
    assert(strstr(output, "\"id\":\"6\",\"ok\":true"));
    assert(strstr(output, "\"code\":68"));
    assert(strstr(output, "\"payload\":{\"type\":\"bytes\",\"base64\":\"\"}"));
    assert(post_count == 1);

    write_all(input[1],
        "{\"version\":1,\"id\":\"7\",\"operation\":\"close\",\"parameters\":{},"
        "\"timeout_ms\":5000}\n");
    stage = "close";
    exact(context, result[0],
          "{\"version\":1,\"id\":\"7\",\"ok\":true,\"result\":null}\n");
    assert(waitpid(child, &status, 0) == child);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        fprintf(stderr, "custody status=%d exited=%d code=%d\n", status,
                WIFEXITED(status), WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(input[1]); close(result[0]);
    coap_free_context(context); coap_cleanup();
    assert(unlink("/tmp/wotex-coap-exchange-must-not-exist") < 0);
    snprintf(command, sizeof(command), "%s/contexts.v1", directory);
    assert(unlink(command) == 0);
    snprintf(command, sizeof(command), "%s/context.lock", directory);
    assert(unlink(command) == 0);
    assert(rmdir(directory) == 0);
    puts("WCO-N02/N04: production worker completes protected GET and Block1 POST");
    return 0;
}
