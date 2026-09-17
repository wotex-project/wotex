/* SPDX-License-Identifier: Apache-2.0 */
/* Test-only same-stack secure peer for real BrowseNext and release I/O. Each
 * 's' byte on stdin prints current and cumulative server Session and
 * SecureChannel counters, so tests can distinguish explicit Session deletion,
 * server-side Session timeout and channel release. Each 'b' byte writes five
 * consecutive Double values to the burst Variable in one server iteration and
 * prints the last value, so a small MonitoredItem queue overflows. Each 'c'
 * byte toggles such a burst on every loop iteration and prints the new state. */
#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void stop_peer(int signal_number) {
    (void)signal_number;
    running = 0;
}

static UA_ByteString load(const char *directory, const char *name) {
    UA_ByteString value = UA_BYTESTRING_NULL;
    char path[1024];
    int length = snprintf(path, sizeof(path), "%s/%s", directory, name);
    if(length <= 0 || (size_t)length >= sizeof(path)) return value;
    FILE *file = fopen(path, "rb");
    if(!file) return value;
    if(fseek(file, 0, SEEK_END) != 0) goto done;
    long size = ftell(file);
    if(size <= 0 || size > 65536 || fseek(file, 0, SEEK_SET) != 0) goto done;
    if(UA_ByteString_allocBuffer(&value, (size_t)size) != UA_STATUSCODE_GOOD) goto done;
    if(fread(value.data, 1, (size_t)size, file) != (size_t)size)
        UA_ByteString_clear(&value);
done:
    fclose(file);
    return value;
}

static UA_StatusCode add_nodes(UA_Server *server, UA_UInt16 namespace_index) {
    UA_NodeId object = UA_NODEID_STRING(namespace_index, "paged");
    UA_ObjectAttributes object_attributes = UA_ObjectAttributes_default;
    object_attributes.displayName = UA_LOCALIZEDTEXT("en", "Paged");
    UA_StatusCode status = UA_Server_addObjectNode(server, object,
        UA_NS0ID(OBJECTSFOLDER), UA_NS0ID(ORGANIZES),
        UA_QUALIFIEDNAME(namespace_index, "Paged"), UA_NS0ID(BASEOBJECTTYPE),
        object_attributes, NULL, NULL);
    for(unsigned index = 1; status == UA_STATUSCODE_GOOD && index <= 3; index++) {
        char identifier[16];
        int size = snprintf(identifier, sizeof(identifier), "child%u", index);
        if(size <= 0 || (size_t)size >= sizeof(identifier)) return UA_STATUSCODE_BADINTERNALERROR;
        UA_Int32 number = (UA_Int32)index;
        UA_VariableAttributes attributes = UA_VariableAttributes_default;
        attributes.displayName = UA_LOCALIZEDTEXT("en", "Child");
        attributes.dataType = UA_TYPES[UA_TYPES_INT32].typeId;
        UA_Variant_setScalar(&attributes.value, &number, &UA_TYPES[UA_TYPES_INT32]);
        status = UA_Server_addVariableNode(server,
            UA_NODEID_STRING(namespace_index, identifier), object,
            UA_NS0ID(HASCOMPONENT), UA_QUALIFIEDNAME(namespace_index, identifier),
            UA_NS0ID(BASEDATAVARIABLETYPE), attributes, NULL, NULL);
    }
    if(status != UA_STATUSCODE_GOOD) return status;
    UA_Double zero = 0.0;
    UA_VariableAttributes burst = UA_VariableAttributes_default;
    burst.displayName = UA_LOCALIZEDTEXT("en", "Burst");
    burst.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
    UA_Variant_setScalar(&burst.value, &zero, &UA_TYPES[UA_TYPES_DOUBLE]);
    return UA_Server_addVariableNode(server, UA_NODEID_STRING(namespace_index, "burst"),
        UA_NS0ID(OBJECTSFOLDER), UA_NS0ID(ORGANIZES), UA_QUALIFIEDNAME(namespace_index, "burst"),
        UA_NS0ID(BASEDATAVARIABLETYPE), burst, NULL, NULL);
}

/* Writes five consecutive values without running the server loop between them. */
static UA_StatusCode write_burst(UA_Server *server, UA_UInt16 namespace_index, UA_Double *value) {
    UA_StatusCode status = UA_STATUSCODE_GOOD;
    for(unsigned index = 0; status == UA_STATUSCODE_GOOD && index < 5; index++) {
        *value += 1.0;
        UA_Variant variant;
        UA_Variant_setScalar(&variant, value, &UA_TYPES[UA_TYPES_DOUBLE]);
        status = UA_Server_writeValue(server, UA_NODEID_STRING(namespace_index, "burst"), variant);
    }
    return status;
}

int main(int argc, char **argv) {
    if(argc != 3) return 2;
    char *tail = NULL;
    unsigned long selected = strtoul(argv[1], &tail, 10);
    if(!tail || *tail || selected == 0 || selected > 65535) return 2;
    UA_ByteString certificate = load(argv[2], "server.der");
    UA_ByteString private_key = load(argv[2], "server.key.der");
    UA_ByteString trust = load(argv[2], "ca.der");
    UA_ByteString crl = load(argv[2], "clean.crl");
    if(!certificate.length || !private_key.length || !trust.length || !crl.length) {
        UA_ByteString_clear(&certificate);
        UA_ByteString_clear(&private_key);
        UA_ByteString_clear(&trust);
        UA_ByteString_clear(&crl);
        return 3;
    }

    UA_Server *server = UA_Server_new();
    if(!server) {
        UA_ByteString_clear(&certificate);
        UA_ByteString_clear(&private_key);
        UA_ByteString_clear(&trust);
        UA_ByteString_clear(&crl);
        return 4;
    }
    UA_ServerConfig *config = UA_Server_getConfig(server);
    UA_StatusCode status = UA_ServerConfig_setDefaultWithSecurityPolicies(config,
        (UA_UInt16)selected, &certificate, &private_key, &trust, 1,
        &trust, 1, &crl, 1);
    UA_ByteString_clear(&certificate);
    UA_ByteString_clear(&private_key);
    UA_ByteString_clear(&trust);
    UA_ByteString_clear(&crl);
    if(status != UA_STATUSCODE_GOOD) goto done;
    config->maxReferencesPerNode = 1;
    config->samplingIntervalLimits.min = 0.0;
    UA_String_clear(&config->applicationDescription.applicationUri);
    config->applicationDescription.applicationUri = UA_STRING_ALLOC("urn:wotex:fixture:server");
    if(!config->applicationDescription.applicationUri.data) {
        status = UA_STATUSCODE_BADOUTOFMEMORY;
        goto done;
    }
    char endpoint_url[64];
    int endpoint_length = snprintf(endpoint_url, sizeof(endpoint_url),
        "opc.tcp://127.0.0.1:%lu", selected);
    if(endpoint_length <= 0 || (size_t)endpoint_length >= sizeof(endpoint_url)) {
        status = UA_STATUSCODE_BADINTERNALERROR;
        goto done;
    }
    UA_Array_delete(config->serverUrls, config->serverUrlsSize, &UA_TYPES[UA_TYPES_STRING]);
    config->serverUrls = UA_Array_new(1, &UA_TYPES[UA_TYPES_STRING]);
    if(!config->serverUrls) {
        config->serverUrlsSize = 0;
        status = UA_STATUSCODE_BADOUTOFMEMORY;
        goto done;
    }
    config->serverUrlsSize = 1;
    config->serverUrls[0] = UA_STRING_ALLOC(endpoint_url);
    if(!config->serverUrls[0].data) {
        status = UA_STATUSCODE_BADOUTOFMEMORY;
        goto done;
    }
    for(size_t index = 0; index < config->endpointsSize; index++) {
        UA_EndpointDescription *endpoint = &config->endpoints[index];
        endpoint->userIdentityTokens =
            UA_Array_new(1, &UA_TYPES[UA_TYPES_USERTOKENPOLICY]);
        if(!endpoint->userIdentityTokens) {
            status = UA_STATUSCODE_BADOUTOFMEMORY;
            goto done;
        }
        endpoint->userIdentityTokensSize = 1;
        endpoint->userIdentityTokens[0].tokenType = UA_USERTOKENTYPE_ANONYMOUS;
        const char *hash = NULL;
        for(size_t offset = 0; offset < endpoint->securityPolicyUri.length; offset++) {
            if(endpoint->securityPolicyUri.data[offset] == '#')
                hash = (const char *)endpoint->securityPolicyUri.data + offset;
        }
        if(!hash) {
            status = UA_STATUSCODE_BADINTERNALERROR;
            goto done;
        }
        char policy_id[128];
        int policy_length = snprintf(policy_id, sizeof(policy_id), "wotex-anonymous%.*s",
            (int)(endpoint->securityPolicyUri.length -
                (size_t)(hash - (const char *)endpoint->securityPolicyUri.data)), hash);
        if(policy_length <= 0 || (size_t)policy_length >= sizeof(policy_id)) {
            status = UA_STATUSCODE_BADINTERNALERROR;
            goto done;
        }
        endpoint->userIdentityTokens[0].policyId = UA_STRING_ALLOC(policy_id);
        if(!endpoint->userIdentityTokens[0].policyId.data) {
            status = UA_STATUSCODE_BADOUTOFMEMORY;
            goto done;
        }
        status = UA_String_copy(&endpoint->securityPolicyUri,
            &endpoint->userIdentityTokens[0].securityPolicyUri);
        if(status != UA_STATUSCODE_GOOD) goto done;
    }
    UA_UInt16 namespace_index = UA_Server_addNamespace(server, "urn:wotex:fixture");
    if(!namespace_index) {
        status = UA_STATUSCODE_BADINTERNALERROR;
        goto done;
    }
    status = add_nodes(server, namespace_index);
    if(status != UA_STATUSCODE_GOOD) goto done;
    status = UA_Server_run_startup(server);
    if(status != UA_STATUSCODE_GOOD) goto done;
    signal(SIGTERM, stop_peer);
    signal(SIGINT, stop_peer);
    UA_Double burst_value = 0.0;
    bool continuous = false;
    printf("READY %u\n", (unsigned)namespace_index);
    fflush(stdout);
    while(running) {
        (void)UA_Server_run_iterate(server, false);
        if(continuous && write_burst(server, namespace_index, &burst_value) != UA_STATUSCODE_GOOD)
            break;
        struct pollfd owner = {.fd = 0, .events = POLLIN};
        int ready = poll(&owner, 1, 20);
        if(ready > 0 && (owner.revents & (POLLHUP | POLLERR | POLLNVAL))) break;
        if(ready > 0 && (owner.revents & POLLIN)) {
            char input[16];
            ssize_t count = read(0, input, sizeof(input));
            if(count <= 0) break;
            for(ssize_t index = 0; index < count; index++) {
                if(input[index] == 'c') {
                    continuous = !continuous;
                    printf("CONTINUOUS %s\n", continuous ? "on" : "off");
                    fflush(stdout);
                    continue;
                }
                if(input[index] == 'b') {
                    UA_StatusCode written = write_burst(server, namespace_index, &burst_value);
                    printf("BURST %.1f %s\n", burst_value, UA_StatusCode_name(written));
                    fflush(stdout);
                    continue;
                }
                if(input[index] != 's') continue;
                UA_ServerStatistics statistics = UA_Server_getStatistics(server);
                printf("COUNTERS %zu %zu %zu %zu %zu\n",
                       statistics.ss.currentSessionCount, statistics.ss.cumulatedSessionCount,
                       statistics.ss.sessionTimeoutCount, statistics.ss.sessionAbortCount,
                       statistics.scs.currentChannelCount);
                fflush(stdout);
            }
        }
    }
    status = UA_Server_run_shutdown(server);
done:
    UA_Server_delete(server);
    return status == UA_STATUSCODE_GOOD ? 0 : 5;
}
