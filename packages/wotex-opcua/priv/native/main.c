/* Wotex native process bootstrap. OPC UA service admission is separate from
 * executable readiness. This build/ownership boundary performs no network I/O.
 * The first-party source is licensed under the repository's Apache-2.0 license. */
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include "ipc.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/opensslv.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdlib.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#if UA_OPEN62541_VER_MAJOR != 1 || UA_OPEN62541_VER_MINOR != 5 || UA_OPEN62541_VER_PATCH != 7
#error "The native source requires open62541 1.5.7"
#endif
#if OPENSSL_VERSION_NUMBER != 0x30500080L
#error "The native source requires OpenSSL 3.5.8"
#endif

#define WOTEX_SDK_REVISION "d1173ccc31560ffc60c29e24ce8adb19f8c3c686"

static void silent_log(void *context, UA_LogLevel level, UA_LogCategory category,
                       const char *format, va_list arguments) {
    (void)context;
    (void)level;
    (void)category;
    (void)format;
    (void)arguments;
}

static int write_control(const char *bytes, size_t size) {
    size_t offset = 0;
    while(offset < size) {
        ssize_t count = write(STDOUT_FILENO, bytes + offset, size - offset);
        if(count > 0)
            offset += (size_t)count;
        else if(count < 0 && errno == EINTR)
            continue;
        else
            return 0;
    }
    return 1;
}

static int64_t monotonic_ms(void) {
    struct timespec now;
    if(clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 ||
       (uint64_t)now.tv_sec > (uint64_t)INT64_MAX / 1000U)
        return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int self_test(void) {
    static const unsigned char expected[32] = {
        0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,
        0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad
    };
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_size = 0;
    if(!EVP_Digest("abc", 3, digest, &digest_size, EVP_sha256(), NULL) ||
       digest_size != 32 || memcmp(digest, expected, 32) != 0)
        return 0;

    UA_DateTime ticks = 1;
    UA_DateTime decoded = 0;
    UA_ByteString bytes = UA_BYTESTRING_NULL;
    UA_StatusCode encoded = UA_encodeBinary(&ticks, &UA_TYPES[UA_TYPES_DATETIME], &bytes, NULL);
    UA_StatusCode result = encoded;
    if(encoded == UA_STATUSCODE_GOOD)
        result = UA_decodeBinary(&bytes, &decoded, &UA_TYPES[UA_TYPES_DATETIME], NULL);
    UA_ByteString_clear(&bytes);
    return result == UA_STATUSCODE_GOOD && decoded == ticks;
}

static int terminal(uint64_t generation, const char *code, const char *phase) {
    char output[256];
    int size;
    if(generation) {
        size = snprintf(output, sizeof(output),
            "{\"version\":1,\"generation\":%" PRIu64 ",\"event\":\"terminal\","
            "\"error\":{\"code\":\"%s\",\"phase\":\"%s\",\"effect\":\"none\"}}\n",
            generation, code, phase);
    } else {
        size = snprintf(output, sizeof(output),
            "{\"version\":1,\"generation\":null,\"event\":\"terminal\","
            "\"error\":{\"code\":\"%s\",\"phase\":\"%s\",\"effect\":\"none\"}}\n",
            code, phase);
    }
    return size > 0 && (size_t)size < sizeof(output) && write_control(output, (size_t)size);
}

static int bootstrap(void) {
    UA_Client *client = UA_Client_new();
    if(!client)
        return 70;
    void *json_pool = malloc(WOP_JSON_POOL_BYTES);
    if(!json_pool) {
        UA_Client_delete(client);
        return 70;
    }
    WopIpcInput input = {0};
    uint64_t admitted_generation = 0;
    UA_ClientConfig *config = UA_Client_getConfig(client);
    if(config->logging)
        config->logging->log = silent_log;
    config->noReconnect = true;
    config->noNewSession = true;

    char ready[256];
    int64_t clock_ms = monotonic_ms();
    int length = snprintf(ready, sizeof(ready),
        "{\"version\":1,\"event\":\"ready\",\"backend\":\"open62541\","
        "\"revision\":\"%s\",\"clock_ms\":%" PRId64 "}\n", WOTEX_SDK_REVISION, clock_ms);
    int status = 70;
    if(clock_ms < 0 || length < 0 || (size_t)length >= sizeof(ready) ||
       !write_control(ready, (size_t)length))
        goto done;

    for(;;) {
        struct pollfd descriptor = {STDIN_FILENO, POLLIN, 0};
        int polled = poll(&descriptor, 1, 10);
        if(polled < 0 && errno == EINTR)
            continue;
        if(polled < 0)
            break;
        if(polled == 0)
            continue;
        char buffer[4096];
        ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
        if(count == 0) {
            if(input.used)
                (void)terminal(admitted_generation, "invalid_request", "validation");
            else
                status = 0;
            break;
        }
        if(count < 0 && (errno == EINTR || errno == EAGAIN))
            continue;
        if(count < 0)
            break;
        for(size_t offset = 0; offset < (size_t)count;) {
            size_t consumed = 0;
            WopIpcFrameStatus framed = wop_ipc_feed(&input, buffer + offset,
                                                      (size_t)count - offset, &consumed);
            offset += consumed;
            if(framed == WOP_IPC_MORE)
                break;
            if(framed != WOP_IPC_FRAME) {
                (void)terminal(admitted_generation, "invalid_request", "validation");
                goto done;
            }
            WopJson parsed = {0};
            WopIpcRequest request;
            uint64_t generation = 0;
            if(wop_json_read(input.bytes, input.used, json_pool, WOP_JSON_POOL_BYTES,
                             &parsed) == WOP_JSON_OK) {
                yyjson_val *root = yyjson_doc_get_root(parsed.document);
                if(yyjson_is_obj(root))
                    (void)wop_json_uint64(yyjson_obj_get(root, "generation"), &generation);
                if(yyjson_is_obj(root) && yyjson_obj_get(root, "event")) {
                    WopIpcCredit credit;
                    if(admitted_generation || !wop_ipc_credit(root, &credit) ||
                       credit.sequence != 1) {
                        (void)terminal(admitted_generation, "invalid_request", "validation");
                    } else {
                        admitted_generation = credit.generation;
                        wop_json_clear(&parsed);
                        input.used = 0;
                        continue;
                    }
                } else if(!wop_ipc_request(root, &request) || !admitted_generation ||
                          request.generation != admitted_generation) {
                    (void)terminal(admitted_generation, "invalid_request", "validation");
                } else if(request.open &&
                          !wop_ipc_open(yyjson_obj_get(root, "parameters"))) {
                    (void)terminal(request.generation, "invalid_request", "validation");
                } else if((clock_ms = monotonic_ms()) < 0 || clock_ms >= request.deadline_ms) {
                    (void)terminal(request.generation, "deadline_exceeded", "admission");
                } else {
                    /* Framing is connected; no SDK service is admitted yet. */
                    (void)terminal(request.generation, "unsupported_protocol", "validation");
                }
                wop_json_clear(&parsed);
            } else {
                (void)terminal(admitted_generation, "invalid_request", "validation");
            }
            goto done;
        }
    }
done:
    free(json_pool);
    UA_Client_delete(client);
    return status;
}

int main(int argc, char **argv) {
    if(argc > 2 || (argc == 2 && strcmp(argv[1], "--self-test") != 0))
        return 64;
    if(!OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG, NULL) ||
       OpenSSL_version_num() != OPENSSL_VERSION_NUMBER)
        return 70;

    int status;
    if(argc == 2) {
        status = self_test() ? 0 : 70;
        if(status == 0) {
            static const char result[] =
                "{\"self_test\":\"ok\",\"sha256_known_answer\":true,"
                "\"datetime_ticks\":1,\"network_requests\":0}\n";
            if(!write_control(result, sizeof(result) - 1))
                status = 70;
        }
    } else {
        int flags = fcntl(STDOUT_FILENO, F_GETFL);
        status = flags < 0 || fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK) < 0
                     ? 70 : bootstrap();
    }
    OPENSSL_cleanup();
    return status;
}
