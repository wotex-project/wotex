/* SPDX-License-Identifier: Apache-2.0 */
/* Test-only independent-peer secure Session probe. It is never installed. */
#include "session_config.h"
#include <open62541/client.h>
#include <open62541/client_highlevel_async.h>
#include <openssl/crypto.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void quiet(void *context, UA_LogLevel level, UA_LogCategory category,
                  const char *format, va_list args) {
    (void)context; (void)level; (void)category; (void)format; (void)args;
}

static void logger_clear(UA_Logger *logger) { UA_free(logger); }

static int64_t milliseconds(void) {
    struct timespec now;
    if(clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

typedef struct { bool done, valid; size_t count; } Namespaces;

static void namespaces_received(UA_Client *client, void *userdata, UA_UInt32 request_id,
                                UA_StatusCode status, UA_DataValue *value) {
    (void)client; (void)request_id;
    Namespaces *state = userdata;
    state->done = true;
    if(status != UA_STATUSCODE_GOOD || !value || !value->hasValue ||
       !UA_Variant_hasArrayType(&value->value, &UA_TYPES[UA_TYPES_STRING]) ||
       value->value.arrayLength < 2 || value->value.arrayLength > 1024 ||
       !value->value.data || value->value.data == UA_EMPTY_ARRAY_SENTINEL) return;
    UA_String *uris = value->value.data;
    const char *standard = "http://opcfoundation.org/UA/";
    if(uris[0].length != strlen(standard) ||
       memcmp(uris[0].data, standard, uris[0].length) != 0) return;
    size_t aggregate = 0;
    for(size_t i = 0; i < value->value.arrayLength; i++) {
        if(!uris[i].data || uris[i].length == 0 || uris[i].length > 4096 ||
           memchr(uris[i].data, '\0', uris[i].length)) return;
        aggregate += uris[i].length;
        if(aggregate > 131072) return;
        for(size_t j = 0; j < i; j++)
            if(UA_String_equal(&uris[i], &uris[j])) return;
    }
    state->count = value->value.arrayLength;
    state->valid = true;
}

static int probe(yyjson_val *parameters) {
    WopSecurity security = {0};
    UA_ClientConfig config = {0};
    UA_Client *client = NULL;
    int result = 1;
    time_t now = time(NULL);
    if(now == (time_t)-1 || !wop_security_read(parameters, now, &security)) {
        fprintf(stderr, "credential preflight failed\n");
        goto done;
    }
    config.logging = UA_calloc(1, sizeof(*config.logging));
    if(!config.logging) goto done;
    config.logging->log = quiet;
    config.logging->clear = logger_clear;
    if(!wop_session_configure(&config, parameters, &security)) {
        fprintf(stderr, "SDK configuration failed\n");
        goto done;
    }
    config.timeout = 3000;
    client = UA_Client_newWithConfig(&config);
    if(!client) goto done;
    memset(&config, 0, sizeof(config));
    UA_StatusCode status = UA_Client_connectAsync(client,
        yyjson_get_str(yyjson_obj_get(parameters, "endpoint")));
    UA_SessionState session = UA_SESSIONSTATE_CLOSED;
    int64_t deadline = milliseconds() + 5000;
    while(status == UA_STATUSCODE_GOOD && session != UA_SESSIONSTATE_ACTIVATED &&
          milliseconds() < deadline) {
        status = UA_Client_run_iterate(client, 1);
        UA_StatusCode connection = UA_STATUSCODE_GOOD;
        UA_Client_getState(client, NULL, &session, &connection);
        if(connection != UA_STATUSCODE_GOOD) status = connection;
    }
    if(status != UA_STATUSCODE_GOOD || session != UA_SESSIONSTATE_ACTIVATED) {
        fprintf(stderr, "secure session failed status=0x%08x state=%u\n",
                status, (unsigned)session);
        goto done;
    }
    UA_Double revised = NAN;
    status = UA_Client_getConnectionAttribute_scalar(client,
        UA_QUALIFIEDNAME(0, "revisedSessionTimeout"), &UA_TYPES[UA_TYPES_DOUBLE], &revised);
    if(status != UA_STATUSCODE_GOOD || !isfinite(revised) || revised <= 0 || revised > 60000) {
        fprintf(stderr, "invalid Session revision\n");
        goto done;
    }
    Namespaces namespaces = {0};
    status = UA_Client_readValueAttribute_async(client, UA_NS0ID(SERVER_NAMESPACEARRAY),
                                                 namespaces_received, &namespaces, NULL);
    while(status == UA_STATUSCODE_GOOD && !namespaces.done && milliseconds() < deadline) {
        status = UA_Client_run_iterate(client, 1);
        UA_StatusCode connection = UA_STATUSCODE_GOOD;
        UA_Client_getState(client, NULL, &session, &connection);
        if(connection != UA_STATUSCODE_GOOD || session != UA_SESSIONSTATE_ACTIVATED)
            status = UA_STATUSCODE_BADSESSIONCLOSED;
    }
    if(status != UA_STATUSCODE_GOOD || !namespaces.done || !namespaces.valid) {
        fprintf(stderr, "NamespaceArray failed\n");
        goto done;
    }
    printf("{\"status\":\"passed\",\"secure_session\":true,\"revised_ms\":%.3f,\"namespaces\":%zu}\n",
           revised, namespaces.count);
    result = 0;
done:
    if(client) UA_Client_delete(client);
    UA_ClientConfig_clear(&config);
    wop_security_clear(&security);
    return result;
}

int main(int argc, char **argv) {
    if(argc != 2) return 64;
    FILE *file = fopen(argv[1], "rb");
    if(!file) return 66;
    char *bytes = malloc(WOP_JSON_FRAME_BYTES);
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    if(!bytes || !pool) { fclose(file); free(bytes); free(pool); return 70; }
    size_t length = fread(bytes, 1, WOP_JSON_FRAME_BYTES, file);
    int extra = fgetc(file);
    fclose(file);
    WopJson parsed = {0};
    int result = 65;
    if(extra == EOF && length > 0 && length < WOP_JSON_FRAME_BYTES &&
       wop_json_read(bytes, length, pool, WOP_JSON_POOL_BYTES, &parsed) == WOP_JSON_OK)
        result = probe(yyjson_doc_get_root(parsed.document));
    wop_json_clear(&parsed);
    OPENSSL_cleanse(bytes, WOP_JSON_FRAME_BYTES);
    OPENSSL_cleanse(pool, WOP_JSON_POOL_BYTES);
    free(bytes);
    free(pool);
    return result;
}
