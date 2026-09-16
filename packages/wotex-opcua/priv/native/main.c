/* Wotex native process owner. Readiness precedes explicit secure Session and
 * service admission; no network I/O occurs before a validated open request.
 * The first-party source is licensed under the repository's Apache-2.0 license. */
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include "ipc.h"
#include "session_open.h"
#include "value_codec.h"
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

static int terminal_status(uint64_t generation, const char *code,
                           const char *phase, UA_StatusCode status) {
    char output[288];
    int size = snprintf(output, sizeof(output),
        "{\"version\":1,\"generation\":%" PRIu64 ",\"event\":\"terminal\","
        "\"error\":{\"code\":\"%s\",\"phase\":\"%s\",\"effect\":\"none\","
        "\"status\":%" PRIu32 "}}\n", generation, code, phase, status);
    return size > 0 && (size_t)size < sizeof(output) && write_control(output, (size_t)size);
}

static int terminal_write(uint64_t generation, const char *code,
                          const char *phase, UA_StatusCode status, bool with_status) {
    char output[288];
    int size;
    if(with_status)
        size = snprintf(output, sizeof(output),
            "{\"version\":1,\"generation\":%" PRIu64 ",\"event\":\"terminal\","
            "\"error\":{\"code\":\"%s\",\"phase\":\"%s\",\"effect\":\"unknown\","
            "\"status\":%" PRIu32 "}}\n", generation, code, phase, status);
    else
        size = snprintf(output, sizeof(output),
            "{\"version\":1,\"generation\":%" PRIu64 ",\"event\":\"terminal\","
            "\"error\":{\"code\":\"%s\",\"phase\":\"%s\",\"effect\":\"unknown\"}}\n",
            generation, code, phase);
    return size > 0 && (size_t)size < sizeof(output) && write_control(output, (size_t)size);
}

static int terminal_active(bool writing, uint64_t generation,
                           const char *code, const char *phase) {
    return writing ? terminal_write(generation, code, phase, 0, false) :
                     terminal(generation, code, phase);
}

static bool result_frame(const WopIpcRequest *request, const WopSession *session,
                         const UA_DataValue *read_value,
                         const UA_StatusCode *write_status,
                         uint64_t *messages, uint64_t *bytes) {
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    if(!doc) return false;
    yyjson_mut_val *root = yyjson_mut_obj(doc);
    yyjson_mut_doc_set_root(doc, root);
    yyjson_mut_val *result = session || write_status ? yyjson_mut_obj(doc) : yyjson_mut_null(doc);
    if(read_value && wop_value_write_data_value(read_value, doc, &result) != WOP_VALUE_OK)
        result = NULL;
    if(write_status && (!result || !yyjson_mut_obj_add_uint(doc, result, "status", *write_status)))
        result = NULL;
    bool valid = root && result &&
        yyjson_mut_obj_add_uint(doc, root, "version", 1) &&
        yyjson_mut_obj_add_uint(doc, root, "generation", request->generation) &&
        yyjson_mut_obj_add_str(doc, root, "id", request->id) &&
        yyjson_mut_obj_add_bool(doc, root, "ok", true) &&
        yyjson_mut_obj_add_val(doc, root, "result", result);
    if(valid && session) {
        yyjson_mut_val *namespaces = yyjson_mut_arr(doc);
        valid = namespaces &&
            yyjson_mut_obj_add_real(doc, result, "session_timeout_ms",
                                    session->revised_timeout_ms) &&
            yyjson_mut_obj_add_uint(doc, result, "session_generation", request->generation) &&
            yyjson_mut_obj_add_val(doc, result, "namespace_array", namespaces);
        for(size_t i = 0; valid && i < session->namespace_count; i++)
            valid = yyjson_mut_arr_add_strncpy(doc, namespaces,
                (const char *)session->namespace_array[i].data,
                session->namespace_array[i].length);
    }
    size_t size = 0;
    char *encoded = valid ? yyjson_mut_write(doc, 0, &size) : NULL;
    bool sent = encoded && size < WOP_JSON_FRAME_BYTES && *messages > 0 &&
                size + 1 <= *bytes && write_control(encoded, size) &&
                write_control("\n", 1);
    if(sent) { (*messages)--; *bytes -= size + 1; }
    free(encoded);
    yyjson_mut_doc_free(doc);
    return sent;
}

static int bootstrap(void) {
    void *json_pool = malloc(WOP_JSON_POOL_BYTES);
    if(!json_pool) return 70;
    WopIpcInput input = {0};
    uint64_t admitted_generation = 0;
    uint64_t credit_sequence = 0, credit_messages = 0, credit_bytes = 0;
    uint64_t used_messages = 0, used_bytes = 0;
    WopSession session = {0};
    WopIpcRequest open_request = {0};
    WopIpcRequest read_request = {0};
    WopIpcRequest write_request = {0};
    uint64_t requested_session_timeout = 0;
    int64_t open_deadline = 0, read_deadline = 0, write_deadline = 0;
    bool opening = false, opened = false, reading = false, writing = false;

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
        if(opening || opened) {
            int64_t now = monotonic_ms();
            if(now < 0 || (opening && now >= open_deadline) ||
               (reading && now >= read_deadline) ||
               (writing && now >= write_deadline)) {
                if(writing)
                    (void)terminal_write(admitted_generation, "deadline_exceeded",
                                         "exchange", 0, false);
                else
                    (void)terminal(admitted_generation, "deadline_exceeded",
                                   opening ? "opening" : "exchange");
                break;
            }
            if(!wop_session_step(&session, requested_session_timeout)) {
                if(writing)
                    (void)terminal_write(admitted_generation, "connection_failed",
                                         "exchange", 0, false);
                else
                    (void)terminal(admitted_generation,
                                   opening ? "invalid_response" : "connection_failed",
                                   opening ? "opening" : "exchange");
                break;
            }
            if(opening && session.ready) {
                uint64_t before = credit_bytes;
                if(!result_frame(&open_request, &session, NULL, NULL,
                                 &credit_messages, &credit_bytes))
                    break;
                used_messages++;
                used_bytes += before - credit_bytes;
                opening = false;
                opened = true;
            }
            if(reading && session.read_completed) {
                if(!session.read_valid && !session.read_remote_error) {
                    (void)terminal(admitted_generation, "invalid_response", "decode");
                    break;
                }
                if(session.read_status & 0x80000000U) {
                    (void)terminal_status(admitted_generation, "remote_error",
                                          "exchange", session.read_status);
                    break;
                }
                if(!wop_session_read_supported(&session)) {
                    (void)terminal(admitted_generation,
                                   session.read_valid ? "unsupported_type" : "invalid_response",
                                   "decode");
                    break;
                }
                uint64_t before = credit_bytes;
                if(!result_frame(&read_request, NULL, &session.read_value, NULL,
                                 &credit_messages, &credit_bytes)) {
                    (void)terminal(admitted_generation, "response_limit", "decode");
                    break;
                }
                used_messages++;
                used_bytes += before - credit_bytes;
                UA_DataValue_clear(&session.read_value);
                reading = false;
            }
            if(writing && session.write_completed) {
                if(!session.write_valid && !session.write_remote_error) {
                    (void)terminal_write(admitted_generation, "invalid_response",
                                         "decode", 0, false);
                    break;
                }
                if(session.write_status & 0x80000000U) {
                    (void)terminal_write(admitted_generation, "remote_error",
                                         "exchange", session.write_status, true);
                    break;
                }
                uint64_t before = credit_bytes;
                if(!result_frame(&write_request, NULL, NULL, &session.write_status,
                                 &credit_messages, &credit_bytes)) {
                    (void)terminal_write(admitted_generation, "response_limit",
                                         "decode", 0, false);
                    break;
                }
                used_messages++;
                used_bytes += before - credit_bytes;
                UA_WriteValue_clear(&session.write_value);
                writing = false;
            }
        }
        struct pollfd descriptor = {STDIN_FILENO, POLLIN, 0};
        int polled = poll(&descriptor, 1, opening || opened ? 1 : 10);
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
                (void)terminal_active(writing, admitted_generation,
                                      "invalid_request", "validation");
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
                (void)terminal_active(writing, admitted_generation,
                                      "invalid_request", "validation");
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
                    if(!wop_ipc_credit(root, &credit) ||
                       (!admitted_generation && credit.sequence != 1) ||
                       (admitted_generation &&
                        (credit.generation != admitted_generation ||
                         credit.sequence != credit_sequence + 1 ||
                         credit.messages > used_messages || credit.bytes > used_bytes ||
                         credit_messages + credit.messages > 16 ||
                         credit_bytes + credit.bytes > 262144))) {
                        (void)terminal_active(writing, admitted_generation,
                                              "invalid_request", "validation");
                    } else {
                        admitted_generation = credit.generation;
                        credit_sequence = credit.sequence;
                        credit_messages += credit.messages;
                        credit_bytes += credit.bytes;
                        if(credit.sequence != 1) {
                            used_messages -= credit.messages;
                            used_bytes -= credit.bytes;
                        }
                        wop_json_clear(&parsed);
                        input.used = 0;
                        continue;
                    }
                } else if(!wop_ipc_request(root, &request) || !admitted_generation ||
                          request.generation != admitted_generation) {
                    (void)terminal_active(writing, admitted_generation,
                                          "invalid_request", "validation");
                } else if(request.open &&
                          !wop_ipc_open(yyjson_obj_get(root, "parameters"))) {
                    (void)terminal_active(writing, request.generation,
                                          "invalid_request", "validation");
                } else if((clock_ms = monotonic_ms()) < 0 || clock_ms >= request.deadline_ms) {
                    (void)terminal_active(writing, request.generation,
                                          "deadline_exceeded", "admission");
                } else if(request.open) {
                    if(opening || opened) {
                        (void)terminal_active(writing, request.generation,
                                              "invalid_request", "validation");
                    } else {
                        time_t now = time(NULL);
                        open_deadline = request.deadline_ms;
                        if((uint64_t)(request.deadline_ms - clock_ms) > request.timeout_ms)
                            open_deadline = clock_ms + (int64_t)request.timeout_ms;
                        bool admitted = now != (time_t)-1 &&
                            wop_session_start(&session, yyjson_obj_get(root, "parameters"),
                                              now, open_deadline);
                        if(!admitted)
                            (void)terminal_active(writing, request.generation,
                                monotonic_ms() >= open_deadline ? "deadline_exceeded" : "certificate_invalid",
                                "opening");
                        else {
                            open_request = request;
                            (void)wop_json_uint64(yyjson_obj_get(
                                yyjson_obj_get(root, "parameters"), "session_timeout_ms"),
                                &requested_session_timeout);
                            opening = true;
                            wop_json_clear(&parsed);
                            input.used = 0;
                            continue;
                        }
                    }
                } else if(opened && !reading && !writing &&
                          strcmp(yyjson_get_str(yyjson_obj_get(root, "operation")), "read") == 0) {
                    if(!wop_session_read(&session, yyjson_obj_get(root, "parameters"))) {
                        (void)terminal_active(writing, request.generation,
                                              "invalid_value", "validation");
                    } else {
                        read_request = request;
                        read_deadline = request.deadline_ms;
                        if((uint64_t)(request.deadline_ms - clock_ms) > request.timeout_ms)
                            read_deadline = clock_ms + (int64_t)request.timeout_ms;
                        reading = true;
                        wop_json_clear(&parsed);
                        input.used = 0;
                        continue;
                    }
                } else if(opened && !reading && !writing &&
                          strcmp(yyjson_get_str(yyjson_obj_get(root, "operation")), "write") == 0) {
                    bool attempted = false;
                    if(!wop_session_write(&session, yyjson_obj_get(root, "parameters"),
                                          &attempted)) {
                        if(attempted)
                            (void)terminal_write(request.generation, "connection_failed",
                                                 "admission", 0, false);
                        else
                            (void)terminal_active(writing, request.generation,
                                                  "invalid_value", "validation");
                    } else {
                        write_request = request;
                        write_deadline = request.deadline_ms;
                        if((uint64_t)(request.deadline_ms - clock_ms) > request.timeout_ms)
                            write_deadline = clock_ms + (int64_t)request.timeout_ms;
                        writing = true;
                        wop_json_clear(&parsed);
                        input.used = 0;
                        continue;
                    }
                } else if(opened && !reading && !writing &&
                          strcmp(yyjson_get_str(yyjson_obj_get(root, "operation")), "close") == 0 &&
                          yyjson_obj_size(yyjson_obj_get(root, "parameters")) == 0) {
                    bool released = wop_session_close(&session);
                    if(released && result_frame(&request, NULL, NULL,
                                                NULL,
                                                &credit_messages, &credit_bytes))
                        status = 0;
                    else if(!released)
                        (void)terminal_active(writing, request.generation,
                                              "cleanup_failed", "cleanup");
                    wop_json_clear(&parsed);
                    goto done;
                } else {
                    /* The other service operations are not admitted yet. */
                    (void)terminal_active(writing, request.generation,
                                          writing ? "busy" : "unsupported_protocol",
                                          writing ? "admission" : "validation");
                }
                wop_json_clear(&parsed);
            } else {
                (void)terminal_active(writing, admitted_generation,
                                      "invalid_request", "validation");
            }
            goto done;
        }
    }
done:
    wop_session_close(&session);
    OPENSSL_cleanse(input.bytes, sizeof(input.bytes));
    OPENSSL_cleanse(json_pool, WOP_JSON_POOL_BYTES);
    free(json_pool);
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
