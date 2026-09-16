/* SPDX-License-Identifier: Apache-2.0 */
/* Same-stack, loopback-only SDK patch regression. Security None is confined to
 * this test binary and does not establish secure native Session acceptance. */
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "SDK revision check line %d\n", __LINE__); exit(1); } } while (0)

static void quiet(void *context, UA_LogLevel level, UA_LogCategory category,
                  const char *format, va_list args) {
    (void)context; (void)level; (void)category; (void)format; (void)args;
}

static void logger_clear(UA_Logger *logger) { UA_free(logger); }

static UA_Logger *logger_new(void) {
    UA_Logger *logger = UA_calloc(1, sizeof(*logger));
    REQUIRE(logger);
    logger->log = quiet;
    logger->clear = logger_clear;
    return logger;
}

static int64_t milliseconds(void) {
    struct timespec now;
    REQUIRE(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static unsigned reserve_port(void) {
    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    REQUIRE(descriptor >= 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    REQUIRE(inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1);
    REQUIRE(bind(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0);
    socklen_t length = sizeof(address);
    REQUIRE(getsockname(descriptor, (struct sockaddr *)&address, &length) == 0);
    unsigned port = ntohs(address.sin_port);
    REQUIRE(close(descriptor) == 0);
    return port;
}

static UA_StatusCode revision(UA_Client *client, UA_Double *value) {
    return UA_Client_getConnectionAttribute_scalar(client,
        UA_QUALIFIEDNAME(0, "revisedSessionTimeout"), &UA_TYPES[UA_TYPES_DOUBLE], value);
}

static void exchange(UA_Double server_timeout, UA_UInt32 requested, UA_Double expected) {
    unsigned port = reserve_port();
    char endpoint[96];
    int length = snprintf(endpoint, sizeof(endpoint), "opc.tcp://127.0.0.1:%u", port);
    REQUIRE(length > 0 && (size_t)length < sizeof(endpoint));
    UA_ServerConfig server_config = {0};
    server_config.logging = logger_new();
    REQUIRE(UA_ServerConfig_setMinimal(&server_config, (UA_UInt16)port, NULL) == UA_STATUSCODE_GOOD);
    UA_Array_delete(server_config.serverUrls, server_config.serverUrlsSize, &UA_TYPES[UA_TYPES_STRING]);
    server_config.serverUrls = UA_String_new();
    REQUIRE(server_config.serverUrls);
    server_config.serverUrls[0] = UA_STRING_ALLOC(endpoint);
    REQUIRE(server_config.serverUrls[0].data);
    server_config.serverUrlsSize = 1;
    server_config.maxSessionTimeout = server_timeout;
    UA_Server *server = UA_Server_newWithConfig(&server_config);
    REQUIRE(server && UA_Server_run_startup(server) == UA_STATUSCODE_GOOD);

    UA_ClientConfig client_config = {0};
    client_config.logging = logger_new();
    REQUIRE(UA_ClientConfig_setDefault(&client_config) == UA_STATUSCODE_GOOD);
    client_config.noReconnect = true;
    client_config.noNewSession = true;
    client_config.requestedSessionTimeout = requested;
    client_config.timeout = 3000;
    client_config.securityMode = UA_MESSAGESECURITYMODE_NONE;
    UA_Client *client = UA_Client_newWithConfig(&client_config);
    REQUIRE(client);
    UA_Double value = -1;
    REQUIRE(revision(client, &value) == UA_STATUSCODE_BADNOTCONNECTED);
    REQUIRE(UA_Client_connectAsync(client, endpoint) == UA_STATUSCODE_GOOD);
    int64_t deadline = milliseconds() + 5000;
    UA_SessionState session = UA_SESSIONSTATE_CLOSED;
    UA_StatusCode connected = UA_STATUSCODE_GOOD;
    while (session != UA_SESSIONSTATE_ACTIVATED && milliseconds() < deadline) {
        UA_Server_run_iterate(server, false);
        REQUIRE(UA_Client_run_iterate(client, 1) == UA_STATUSCODE_GOOD);
        UA_Client_getState(client, NULL, &session, &connected);
        REQUIRE(connected == UA_STATUSCODE_GOOD);
    }
    REQUIRE(session == UA_SESSIONSTATE_ACTIVATED && revision(client, &value) == UA_STATUSCODE_GOOD);
    REQUIRE(value == expected);
    UA_Variant copy;
    UA_Variant_init(&copy);
    REQUIRE(UA_Client_getConnectionAttributeCopy(client,
        UA_QUALIFIEDNAME(0, "revisedSessionTimeout"), &copy) == UA_STATUSCODE_GOOD);
    REQUIRE(UA_Variant_hasScalarType(&copy, &UA_TYPES[UA_TYPES_DOUBLE]) && *(UA_Double *)copy.data == expected);
    REQUIRE(UA_Client_disconnectAsync(client) == UA_STATUSCODE_GOOD);
    deadline = milliseconds() + 1000;
    while (session != UA_SESSIONSTATE_CLOSED && milliseconds() < deadline) {
        UA_Server_run_iterate(server, false);
        (void)UA_Client_run_iterate(client, 1);
        UA_Client_getState(client, NULL, &session, NULL);
    }
    REQUIRE(session == UA_SESSIONSTATE_CLOSED && revision(client, &value) == UA_STATUSCODE_BADNOTCONNECTED);
    REQUIRE(*(UA_Double *)copy.data == expected);
    UA_Variant_clear(&copy);
    UA_Client_delete(client);
    REQUIRE(UA_Server_run_shutdown(server) == UA_STATUSCODE_GOOD);
    UA_Server_delete(server);
}

int main(void) {
    exchange(3210.5, 60000, 3210.5);
    exchange(60000, 60000, 60000);
    exchange(60000, 1000, 1000);
    puts("{\"status\":\"passed\",\"sessions\":3,\"secure_profile_acceptance\":false}");
    return 0;
}
