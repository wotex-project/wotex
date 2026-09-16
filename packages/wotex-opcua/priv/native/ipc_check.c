/* SPDX-License-Identifier: Apache-2.0 */
#include "ipc.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(test) do { if (!(test)) return __LINE__; } while (0)

static const char valid[] =
    "{\"version\":1,\"generation\":18446744073709551615,\"id\":\"a\","
    "\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":60000,"
    "\"deadline_ms\":9223372036854775807}\n";

static int request_case(const char *frame, bool expected) {
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    CHECK(pool);
    WopJson json = {0};
    WopIpcRequest request = {0};
    WopJsonStatus parsed = wop_json_read(frame, strlen(frame), pool, WOP_JSON_POOL_BYTES, &json);
    bool admitted = parsed == WOP_JSON_OK &&
                    wop_ipc_request(yyjson_doc_get_root(json.document), &request);
    CHECK(admitted == expected);
    if (admitted) {
        CHECK(request.generation == UINT64_MAX);
        CHECK(request.timeout_ms == 60000);
        CHECK(request.deadline_ms == INT64_MAX);
    }
    wop_json_clear(&json);
    free(pool);
    return 0;
}

static int split_lines(void) {
    size_t length = sizeof(valid) - 1;
    for (size_t split = 0; split <= length; split++) {
        WopIpcInput input = {0};
        size_t consumed = 0;
        WopIpcFrameStatus first = wop_ipc_feed(&input, valid, split, &consumed);
        CHECK(consumed == split);
        CHECK(first == (split == length ? WOP_IPC_FRAME : WOP_IPC_MORE));
        if (split < length) {
            CHECK(wop_ipc_feed(&input, valid + split, length - split, &consumed) ==
                  WOP_IPC_FRAME);
            CHECK(consumed == length - split);
        }
        CHECK(input.used == length);
        CHECK(memcmp(input.bytes, valid, length) == 0);
    }
    WopIpcInput coalesced = {0};
    char both[sizeof(valid) * 2];
    memcpy(both, valid, length);
    memcpy(both + length, valid, length);
    size_t consumed = 0;
    CHECK(wop_ipc_feed(&coalesced, both, length * 2, &consumed) == WOP_IPC_FRAME);
    CHECK(consumed == length);
    memset(&coalesced, 0, sizeof(coalesced));
    CHECK(wop_ipc_feed(&coalesced, both + consumed, length, &consumed) == WOP_IPC_FRAME);
    CHECK(consumed == length);
    return 0;
}

static int bounds(void) {
    WopIpcInput *input = calloc(1, sizeof(*input));
    char *bytes = malloc(WOP_JSON_FRAME_BYTES + 1);
    CHECK(input && bytes);
    memset(bytes, ' ', WOP_JSON_FRAME_BYTES + 1);
    bytes[WOP_JSON_FRAME_BYTES - 1] = '\n';
    size_t consumed = 0;
    CHECK(wop_ipc_feed(input, bytes, WOP_JSON_FRAME_BYTES + 1, &consumed) == WOP_IPC_FRAME);
    CHECK(consumed == WOP_JSON_FRAME_BYTES);
    memset(input, 0, sizeof(*input));
    bytes[WOP_JSON_FRAME_BYTES - 1] = ' ';
    CHECK(wop_ipc_feed(input, bytes, WOP_JSON_FRAME_BYTES, &consumed) == WOP_IPC_LIMIT);
    memset(input, 0, sizeof(*input));
    CHECK(wop_ipc_feed(input, "{}\0\n", 4, &consumed) == WOP_IPC_INVALID);
    CHECK(input->used == 2);
    free(bytes);
    free(input);
    return 0;
}

static int open_case(const char *policy, const char *mode, const char *certificate,
                     const char *authentication, const char *timeout, const char *extra,
                     bool expected) {
    char frame[4096];
    int length = snprintf(frame, sizeof(frame),
        "{\"endpoint\":\"opc.tcp://localhost:4840\",\"security_policy\":\"%s\","
        "\"security_mode\":\"%s\",\"client_uri\":\"urn:client\","
        "\"server_uri\":\"urn:server\",\"certificate\":%s,"
        "\"private_key\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
        "\"server_certificate\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
        "\"trust_certificate\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
        "\"crl\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
        "\"authentication\":%s,\"session_timeout_ms\":%s%s}\n",
        policy, mode, certificate, authentication, timeout, extra);
    CHECK(length > 0 && (size_t)length < sizeof(frame));
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    CHECK(pool);
    WopJson json = {0};
    bool valid = wop_json_read(frame, (size_t)length, pool, WOP_JSON_POOL_BYTES, &json) == WOP_JSON_OK &&
                 wop_ipc_open(yyjson_doc_get_root(json.document));
    CHECK(valid == expected);
    wop_json_clear(&json);
    free(pool);
    return 0;
}

static int open_cases(void) {
    static const char *policies[] = {
        "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
        "http://opcfoundation.org/UA/SecurityPolicy#Aes128_Sha256_RsaOaep",
        "http://opcfoundation.org/UA/SecurityPolicy#Aes256_Sha256_RsaPss"
    };
    static const char *bytes = "{\"type\":\"bytes\",\"base64\":\"AQ==\"}";
    static const char *anonymous = "{\"type\":\"anonymous\"}";
    int result;
    for (size_t i = 0; i < sizeof(policies) / sizeof(policies[0]); i++) {
        result = open_case(policies[i], "SignAndEncrypt", bytes, anonymous, "60000", "", true);
        if (result) return result;
    }
    const struct {
        const char *policy, *mode, *certificate, *auth, *timeout, *extra;
        bool valid;
    } cases[] = {
        {"None", "SignAndEncrypt", bytes, anonymous, "60000", "", false},
        {policies[0], "None", bytes, anonymous, "60000", "", false},
        {policies[0], "SignAndEncrypt", "{\"type\":\"bytes\",\"base64\":\"AR==\"}", anonymous, "60000", "", false},
        {policies[0], "SignAndEncrypt", bytes, "{\"type\":\"anonymous\",\"username\":\"x\"}", "60000", "", false},
        {policies[0], "SignAndEncrypt", bytes, "{\"type\":\"username\",\"username\":\"alice\",\"password\":{\"type\":\"bytes\",\"base64\":\"\"}}", "60000", "", true},
        {policies[0], "SignAndEncrypt", bytes, "{\"type\":\"certificate\",\"certificate\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},\"private_key\":{\"type\":\"bytes\",\"base64\":\"AQ==\"}}", "60000", "", true},
        {policies[0], "SignAndEncrypt", bytes, "{\"type\":\"username\",\"username\":\"\",\"password\":{\"type\":\"bytes\",\"base64\":\"\"}}", "60000", "", false},
        {policies[0], "SignAndEncrypt", bytes, anonymous, "999", "", false},
        {policies[0], "SignAndEncrypt", bytes, anonymous, "3600001", "", false},
        {policies[0], "SignAndEncrypt", bytes, anonymous, "1000.0", "", false},
        {policies[0], "SignAndEncrypt", bytes, anonymous, "60000", ",\"extra\":1", false}
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        result = open_case(cases[i].policy, cases[i].mode, cases[i].certificate,
                           cases[i].auth, cases[i].timeout, cases[i].extra, cases[i].valid);
        if (result) return result;
    }
    return 0;
}

int main(void) {
    static const char *invalid[] = {
        "{\"version\":1,\"generation\":1}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1,\"extra\":0}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1.0,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":0,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"eval\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1,\"id\":\"b\"}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":9223372036854775808}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":60001,\"deadline_ms\":1}\n",
        "{\"version\":true,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":18446744073709551616,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\\u0000b\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":[],\"timeout_ms\":1,\"deadline_ms\":1}\n",
        "{\"version\":1,\"generation\":1,\"id\":\"a\",\"operation\":\"read\",\"parameters\":{},\"timeout_ms\":1,\"deadline_ms\":-1}\n"
    };
    int status = split_lines();
    if (!status) status = bounds();
    if (!status) status = open_cases();
    if (!status) status = request_case(valid, true);
    for (size_t i = 0; !status && i < sizeof(invalid) / sizeof(invalid[0]); i++)
        status = request_case(invalid[i], false);
    if (status) {
        fprintf(stderr, "native IPC check failed at line %d\n", status);
        return 1;
    }
    puts("{\"status\":\"passed\"}");
    return 0;
}
