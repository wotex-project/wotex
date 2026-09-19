/* SPDX-License-Identifier: Apache-2.0 */
/* Test-only secure OPC UA peer. It owns disposable credentials, a bounded
 * address space and deterministic subscription fault controls. */
#include <open62541/plugin/accesscontrol_default.h>
#include <open62541/server.h>
#include <open62541/server_config_default.h>

#include "ua_server_internal.h"
#include "vendor/yyjson/yyjson.h"

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define PEER_URI "urn:wotex:fixture:server"
#define CLIENT_URI "urn:wotex:fixture:client"
#define USERNAME "operator"
#define PASSWORD "correct horse"
#define MAX_FILE_BYTES 65536U

typedef enum {
    VARIANT_DEFAULT,
    VARIANT_EXPIRED,
    VARIANT_WRONG_HOST,
    VARIANT_NONE_ONLY,
    VARIANT_ANONYMOUS_ONLY,
    VARIANT_ENCRYPTED_TOKENS
} PeerVariant;

typedef UA_StatusCode (*ActivateSession)(UA_Server *, UA_AccessControl *,
                                         const UA_EndpointDescription *, const UA_ByteString *,
                                         const UA_NodeId *, const UA_ExtensionObject *, void **);

typedef struct {
    UA_ByteString user_certificate;
    ActivateSession activate_session;
    char token_algorithm[128];
} PeerState;

typedef struct {
    EVP_PKEY *key;
    X509 *certificate;
} Identity;

static volatile sig_atomic_t running = 1;
static PeerState *active_state = NULL;

static void stop_peer(int signal_number) {
    (void)signal_number;
    running = 0;
}

static bool path(char *output, size_t capacity, const char *directory, const char *name) {
    int length = snprintf(output, capacity, "%s/%s", directory, name);
    return length > 0 && (size_t)length < capacity;
}

static UA_ByteString load_file(const char *directory, const char *name) {
    UA_ByteString value = UA_BYTESTRING_NULL;
    char filename[4096];
    if (!path(filename, sizeof(filename), directory, name)) return value;
    FILE *file = fopen(filename, "rb");
    if (!file) return value;
    if (fseek(file, 0, SEEK_END) != 0) goto done;
    long length = ftell(file);
    if (length <= 0 || length > (long)MAX_FILE_BYTES || fseek(file, 0, SEEK_SET) != 0) goto done;
    if (UA_ByteString_allocBuffer(&value, (size_t)length) != UA_STATUSCODE_GOOD) goto done;
    if (fread(value.data, 1, (size_t)length, file) != (size_t)length) UA_ByteString_clear(&value);
done:
    fclose(file);
    return value;
}

static bool write_certificate(const char *directory, const char *name, X509 *certificate) {
    char filename[4096];
    if (!path(filename, sizeof(filename), directory, name)) return false;
    FILE *file = fopen(filename, "wb");
    bool written = file && i2d_X509_fp(file, certificate) == 1;
    if (file && fclose(file) != 0) written = false;
    return written;
}

static bool write_key(const char *directory, const char *role, EVP_PKEY *key) {
    char name[128];
    char filename[4096];
    int length = snprintf(name, sizeof(name), "%s.pem", role);
    if (length <= 0 || (size_t)length >= sizeof(name) ||
        !path(filename, sizeof(filename), directory, name))
        return false;
    FILE *pem = fopen(filename, "wb");
    bool written = pem && PEM_write_PrivateKey(pem, key, NULL, NULL, 0, NULL, NULL) == 1;
    if (pem && fclose(pem) != 0) written = false;
    if (!written || chmod(filename, 0600) != 0) return false;

    length = snprintf(name, sizeof(name), "%s.key.der", role);
    if (length <= 0 || (size_t)length >= sizeof(name) ||
        !path(filename, sizeof(filename), directory, name))
        return false;
    FILE *der = fopen(filename, "wb");
    written = der && i2d_PKCS8PrivateKey_fp(der, key, NULL, NULL, 0, NULL, NULL) == 1;
    if (der && fclose(der) != 0) written = false;
    return written && chmod(filename, 0600) == 0;
}

static bool write_crl(const char *directory, const char *name, X509_CRL *crl) {
    char filename[4096];
    if (!path(filename, sizeof(filename), directory, name)) return false;
    FILE *file = fopen(filename, "wb");
    bool written = file && i2d_X509_CRL_fp(file, crl) == 1;
    if (file && fclose(file) != 0) written = false;
    return written;
}

static EVP_PKEY *generate_key(void) {
    EVP_PKEY_CTX *context = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    EVP_PKEY *key = NULL;
    if (!context || EVP_PKEY_keygen_init(context) <= 0 ||
        EVP_PKEY_CTX_set_rsa_keygen_bits(context, 2048) <= 0 ||
        EVP_PKEY_keygen(context, &key) <= 0) {
        EVP_PKEY_free(key);
        key = NULL;
    }
    EVP_PKEY_CTX_free(context);
    return key;
}

static bool add_extension(X509 *certificate, X509 *issuer, int nid, const char *value) {
    X509V3_CTX context;
    X509V3_set_ctx(&context, issuer, certificate, NULL, NULL, 0);
    X509_EXTENSION *extension = X509V3_EXT_conf_nid(NULL, &context, nid, value);
    bool added = extension && X509_add_ext(certificate, extension, -1) == 1;
    X509_EXTENSION_free(extension);
    return added;
}

static X509_NAME *fixture_name(const char *common_name) {
    X509_NAME *name = X509_NAME_new();
    if (!name || X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_UTF8,
                                            (const unsigned char *)common_name, -1, -1, 0) != 1) {
        X509_NAME_free(name);
        return NULL;
    }
    return name;
}

static X509 *root_certificate(EVP_PKEY *key, const char *common_name, long serial) {
    X509 *certificate = X509_new();
    X509_NAME *name = fixture_name(common_name);
    if (!certificate || !name || X509_set_version(certificate, 2) != 1 ||
        ASN1_INTEGER_set(X509_get_serialNumber(certificate), serial) != 1 ||
        X509_set_subject_name(certificate, name) != 1 ||
        X509_set_issuer_name(certificate, name) != 1 || X509_set_pubkey(certificate, key) != 1 ||
        !X509_gmtime_adj(X509_getm_notBefore(certificate), -86400) ||
        !X509_gmtime_adj(X509_getm_notAfter(certificate), 172800) ||
        !add_extension(certificate, certificate, NID_basic_constraints,
                       "critical,CA:TRUE,pathlen:0") ||
        !add_extension(certificate, certificate, NID_key_usage, "critical,keyCertSign,cRLSign") ||
        !add_extension(certificate, certificate, NID_subject_key_identifier, "hash") ||
        X509_sign(certificate, key, EVP_sha256()) <= 0) {
        X509_free(certificate);
        certificate = NULL;
    }
    X509_NAME_free(name);
    return certificate;
}

static X509 *leaf_certificate(EVP_PKEY *key, X509 *issuer, EVP_PKEY *issuer_key, const char *role,
                              long serial, bool expired, bool wrong_host, bool client) {
    X509 *certificate = X509_new();
    X509_NAME *subject = fixture_name(role);
    char san[256];
    int san_length = snprintf(san, sizeof(san), "URI:%s,DNS:localhost,IP:%s",
                              strcmp(role, "client") == 0 ? CLIENT_URI : PEER_URI,
                              wrong_host ? "127.0.0.2" : "127.0.0.1");
    if (!certificate || !subject || san_length <= 0 || (size_t)san_length >= sizeof(san) ||
        X509_set_version(certificate, 2) != 1 ||
        ASN1_INTEGER_set(X509_get_serialNumber(certificate), serial) != 1 ||
        X509_set_subject_name(certificate, subject) != 1 ||
        X509_set_issuer_name(certificate, X509_get_subject_name(issuer)) != 1 ||
        X509_set_pubkey(certificate, key) != 1 ||
        !X509_gmtime_adj(X509_getm_notBefore(certificate), -172800) ||
        !X509_gmtime_adj(X509_getm_notAfter(certificate), expired ? -86400 : 86400) ||
        !add_extension(certificate, issuer, NID_basic_constraints, "critical,CA:FALSE") ||
        !add_extension(certificate, issuer, NID_key_usage,
                       "critical,digitalSignature,keyEncipherment,dataEncipherment,keyAgreement") ||
        !add_extension(certificate, issuer, NID_ext_key_usage,
                       client ? "clientAuth" : "serverAuth") ||
        !add_extension(certificate, issuer, NID_subject_alt_name, san) ||
        !add_extension(certificate, issuer, NID_subject_key_identifier, "hash") ||
        !add_extension(certificate, issuer, NID_authority_key_identifier, "keyid") ||
        X509_sign(certificate, issuer_key, EVP_sha256()) <= 0) {
        X509_free(certificate);
        certificate = NULL;
    }
    X509_NAME_free(subject);
    return certificate;
}

static X509_CRL *fixture_crl(X509 *issuer, EVP_PKEY *key, X509 *revoked, bool stale) {
    X509_CRL *crl = X509_CRL_new();
    ASN1_TIME *last = ASN1_TIME_adj(NULL, time(NULL), stale ? -2 : 0, -3600);
    ASN1_TIME *next = ASN1_TIME_adj(NULL, time(NULL), stale ? -1 : 1, 0);
    X509V3_CTX context;
    X509V3_set_ctx(&context, issuer, NULL, NULL, crl, 0);
    X509_EXTENSION *authority = X509V3_EXT_conf_nid(NULL, &context, NID_authority_key_identifier,
                                                    "keyid");
    bool valid = crl && last && next && X509_CRL_set_version(crl, 1) == 1 &&
                 X509_CRL_set_issuer_name(crl, X509_get_subject_name(issuer)) == 1 &&
                 X509_CRL_set1_lastUpdate(crl, last) == 1 &&
                 X509_CRL_set1_nextUpdate(crl, next) == 1 && authority &&
                 X509_CRL_add_ext(crl, authority, -1) == 1;
    if (valid && revoked) {
        X509_REVOKED *entry = X509_REVOKED_new();
        ASN1_TIME *when = ASN1_TIME_adj(NULL, time(NULL), 0, -60);
        valid = entry && when &&
                X509_REVOKED_set_serialNumber(entry, X509_get_serialNumber(revoked)) == 1 &&
                X509_REVOKED_set_revocationDate(entry, when) == 1 &&
                X509_CRL_add0_revoked(crl, entry) == 1;
        if (!valid) X509_REVOKED_free(entry);
        ASN1_TIME_free(when);
    }
    if (valid) valid = X509_CRL_sort(crl) == 1 && X509_CRL_sign(crl, key, EVP_sha256()) > 0;
    X509_EXTENSION_free(authority);
    ASN1_TIME_free(last);
    ASN1_TIME_free(next);
    if (!valid) {
        X509_CRL_free(crl);
        crl = NULL;
    }
    return crl;
}

static void identity_clear(Identity *identity) {
    EVP_PKEY_free(identity->key);
    X509_free(identity->certificate);
    identity->key = NULL;
    identity->certificate = NULL;
}

static bool generate_fixtures(const char *directory) {
    if (mkdir(directory, 0700) != 0 && errno != EEXIST) return false;
    Identity ca = {generate_key(), NULL};
    ca.certificate = ca.key ? root_certificate(ca.key, "Wotex fixture CA", 1) : NULL;
    const char *roles[] = {"server", "client", "expired", "wronghost", "user", "stranger"};
    Identity identities[6] = {{0}};
    bool generated = ca.key && ca.certificate;
    for (size_t index = 0; generated && index < 6; index++) {
        identities[index].key = generate_key();
        bool client = strcmp(roles[index], "client") == 0 || strcmp(roles[index], "user") == 0 ||
                      strcmp(roles[index], "stranger") == 0;
        identities[index].certificate =
            identities[index].key
                ? leaf_certificate(identities[index].key, ca.certificate, ca.key, roles[index],
                                   (long)index + 2, strcmp(roles[index], "expired") == 0,
                                   strcmp(roles[index], "wronghost") == 0, client)
                : NULL;
        char certificate_name[128];
        int length = snprintf(certificate_name, sizeof(certificate_name), "%s.der", roles[index]);
        generated = identities[index].key && identities[index].certificate && length > 0 &&
                    (size_t)length < sizeof(certificate_name) &&
                    write_certificate(directory, certificate_name, identities[index].certificate) &&
                    write_key(directory, roles[index], identities[index].key);
    }
    X509_CRL *clean = generated ? fixture_crl(ca.certificate, ca.key, NULL, false) : NULL;
    X509_CRL *revoked = generated
                            ? fixture_crl(ca.certificate, ca.key, identities[0].certificate, false)
                            : NULL;
    X509_CRL *expired = generated ? fixture_crl(ca.certificate, ca.key, NULL, true) : NULL;
    generated = generated && write_certificate(directory, "ca.der", ca.certificate) && clean &&
                revoked && expired && write_crl(directory, "clean.crl", clean) &&
                write_crl(directory, "revoked.crl", revoked) &&
                write_crl(directory, "expired.crl", expired);

    Identity other = {generate_key(), NULL};
    other.certificate = other.key ? root_certificate(other.key, "Untrusted fixture CA", 100) : NULL;
    generated = generated && other.key && other.certificate &&
                write_certificate(directory, "other-ca.der", other.certificate) &&
                write_key(directory, "other", other.key);

    X509_CRL_free(clean);
    X509_CRL_free(revoked);
    X509_CRL_free(expired);
    identity_clear(&other);
    for (size_t index = 0; index < 6; index++) identity_clear(&identities[index]);
    identity_clear(&ca);
    return generated;
}

static int available_port(void) {
    int socket_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (socket_fd < 0) return -1;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    if (inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) != 1) {
        close(socket_fd);
        return -1;
    }
    address.sin_port = 0;
    socklen_t size = sizeof(address);
    int port = -1;
    if (bind(socket_fd, (struct sockaddr *)&address, sizeof(address)) == 0 &&
        getsockname(socket_fd, (struct sockaddr *)&address, &size) == 0)
        port = (int)ntohs(address.sin_port);
    close(socket_fd);
    return port;
}

static UA_StatusCode peer_activate_session(UA_Server *server, UA_AccessControl *access,
                                           const UA_EndpointDescription *endpoint,
                                           const UA_ByteString *remote_certificate,
                                           const UA_NodeId *session_id,
                                           const UA_ExtensionObject *token,
                                           void **session_context) {
    PeerState *state = active_state;
    if (!state || !state->activate_session) return UA_STATUSCODE_BADINTERNALERROR;
    if (token && token->encoding >= UA_EXTENSIONOBJECT_DECODED &&
        token->content.decoded.type == &UA_TYPES[UA_TYPES_X509IDENTITYTOKEN]) {
        const UA_X509IdentityToken *identity = (const UA_X509IdentityToken *)
                                                   token->content.decoded.data;
        if (!UA_ByteString_equal(&identity->certificateData, &state->user_certificate))
            return UA_STATUSCODE_BADUSERACCESSDENIED;
    }
    if (token && token->encoding >= UA_EXTENSIONOBJECT_DECODED &&
        token->content.decoded.type == &UA_TYPES[UA_TYPES_USERNAMEIDENTITYTOKEN]) {
        const UA_UserNameIdentityToken *identity = (const UA_UserNameIdentityToken *)
                                                       token->content.decoded.data;
        size_t length = identity->encryptionAlgorithm.length;
        if (length >= sizeof(state->token_algorithm)) length = sizeof(state->token_algorithm) - 1;
        if (length > 0) memcpy(state->token_algorithm, identity->encryptionAlgorithm.data, length);
        state->token_algorithm[length] = '\0';
    }
    return state->activate_session(server, access, endpoint, remote_certificate, session_id, token,
                                   session_context);
}

static void argument(UA_Argument *value, const char *name, const UA_DataType *type) {
    UA_Argument_init(value);
    value->name = UA_STRING_ALLOC(name);
    value->description = UA_LOCALIZEDTEXT_ALLOC("en", name);
    value->dataType = type->typeId;
    value->valueRank = UA_VALUERANK_SCALAR;
}

static UA_StatusCode add_method(UA_Server *server, UA_UInt16 namespace_index,
                                const char *identifier, const char *name,
                                UA_MethodCallback callback, size_t input_size, UA_Argument *inputs,
                                size_t output_size, UA_Argument *outputs, void *context) {
    UA_MethodAttributes attributes = UA_MethodAttributes_default;
    attributes.displayName = UA_LOCALIZEDTEXT("en", (char *)(uintptr_t)name);
    attributes.executable = true;
    attributes.userExecutable = true;
    return UA_Server_addMethodNode(server,
                                   UA_NODEID_STRING(namespace_index, (char *)(uintptr_t)identifier),
                                   UA_NS0ID(OBJECTSFOLDER), UA_NS0ID(HASCOMPONENT),
                                   UA_QUALIFIEDNAME(namespace_index, (char *)(uintptr_t)name),
                                   attributes, callback, input_size, inputs, output_size, outputs,
                                   context, NULL);
}

static UA_StatusCode add_callback(UA_Server *server, const UA_NodeId *session_id,
                                  void *session_context, const UA_NodeId *method_id,
                                  void *method_context, const UA_NodeId *object_id,
                                  void *object_context, size_t input_size, const UA_Variant *input,
                                  size_t output_size, UA_Variant *output) {
    (void)server;
    (void)session_id;
    (void)session_context;
    (void)method_id;
    (void)method_context;
    (void)object_id;
    (void)object_context;
    if (input_size != 2 || output_size != 1 ||
        !UA_Variant_hasScalarType(&input[0], &UA_TYPES[UA_TYPES_DOUBLE]) ||
        !UA_Variant_hasScalarType(&input[1], &UA_TYPES[UA_TYPES_DOUBLE]))
        return UA_STATUSCODE_BADINVALIDARGUMENT;
    UA_Double result = *(UA_Double *)input[0].data + *(UA_Double *)input[1].data;
    return UA_Variant_setScalarCopy(&output[0], &result, &UA_TYPES[UA_TYPES_DOUBLE]);
}

static UA_StatusCode slow_callback(UA_Server *server, const UA_NodeId *session_id,
                                   void *session_context, const UA_NodeId *method_id,
                                   void *method_context, const UA_NodeId *object_id,
                                   void *object_context, size_t input_size, const UA_Variant *input,
                                   size_t output_size, UA_Variant *output) {
    (void)server;
    (void)session_id;
    (void)session_context;
    (void)method_id;
    (void)method_context;
    (void)object_id;
    (void)object_context;
    if (input_size != 1 || output_size != 1 ||
        !UA_Variant_hasScalarType(&input[0], &UA_TYPES[UA_TYPES_UINT32]))
        return UA_STATUSCODE_BADINVALIDARGUMENT;
    UA_UInt32 milliseconds = *(UA_UInt32 *)input[0].data;
    struct timespec duration = {(time_t)(milliseconds / 1000U),
                                (long)(milliseconds % 1000U) * 1000000L};
    while (nanosleep(&duration, &duration) != 0 && errno == EINTR) {}
    return UA_Variant_setScalarCopy(&output[0], &milliseconds, &UA_TYPES[UA_TYPES_UINT32]);
}

static UA_StatusCode resources_callback(UA_Server *server, const UA_NodeId *session_id,
                                        void *session_context, const UA_NodeId *method_id,
                                        void *method_context, const UA_NodeId *object_id,
                                        void *object_context, size_t input_size,
                                        const UA_Variant *input, size_t output_size,
                                        UA_Variant *output) {
    (void)session_id;
    (void)session_context;
    (void)method_id;
    (void)method_context;
    (void)object_id;
    (void)object_context;
    (void)input;
    (void)input_size;
    if (output_size != 2) return UA_STATUSCODE_BADINVALIDARGUMENT;
    UA_UInt32 subscriptions = (UA_UInt32)server->subscriptionsSize;
    UA_UInt32 monitored = (UA_UInt32)server->monitoredItemsSize;
    UA_StatusCode status = UA_Variant_setScalarCopy(&output[0], &subscriptions,
                                                    &UA_TYPES[UA_TYPES_UINT32]);
    if (status == UA_STATUSCODE_GOOD)
        status = UA_Variant_setScalarCopy(&output[1], &monitored, &UA_TYPES[UA_TYPES_UINT32]);
    return status;
}

static UA_StatusCode publish_faults_callback(UA_Server *server, const UA_NodeId *session_id,
                                             void *session_context, const UA_NodeId *method_id,
                                             void *method_context, const UA_NodeId *object_id,
                                             void *object_context, size_t input_size,
                                             const UA_Variant *input, size_t output_size,
                                             UA_Variant *output) {
    (void)session_id;
    (void)session_context;
    (void)method_id;
    (void)method_context;
    (void)object_id;
    (void)object_context;
    if (input_size != 2 || output_size != 2 ||
        !UA_Variant_hasScalarType(&input[0], &UA_TYPES[UA_TYPES_UINT32]) ||
        !UA_Variant_hasScalarType(&input[1], &UA_TYPES[UA_TYPES_BOOLEAN]))
        return UA_STATUSCODE_BADINVALIDARGUMENT;
    UA_UInt32 requested = *(UA_UInt32 *)input[0].data;
    if (requested > 0) {
        server->wotexPeerWithhold = requested;
        server->wotexPeerDiscard = *(UA_Boolean *)input[1].data;
    }
    UA_StatusCode status = UA_Variant_setScalarCopy(&output[0], &server->wotexPeerWithheld,
                                                    &UA_TYPES[UA_TYPES_UINT32]);
    if (status == UA_STATUSCODE_GOOD)
        status = UA_Variant_setScalarCopy(&output[1], &server->wotexPeerRepublished,
                                          &UA_TYPES[UA_TYPES_UINT32]);
    return status;
}

static UA_StatusCode lose_subscriptions_callback(UA_Server *server, const UA_NodeId *session_id,
                                                 void *session_context, const UA_NodeId *method_id,
                                                 void *method_context, const UA_NodeId *object_id,
                                                 void *object_context, size_t input_size,
                                                 const UA_Variant *input, size_t output_size,
                                                 UA_Variant *output) {
    (void)session_id;
    (void)session_context;
    (void)method_id;
    (void)method_context;
    (void)object_id;
    (void)object_context;
    (void)input;
    (void)input_size;
    if (output_size != 1) return UA_STATUSCODE_BADINVALIDARGUMENT;
    UA_UInt32 count = 0;
    UA_Subscription *subscription;
    LIST_FOREACH(subscription, &server->subscriptions, serverListEntry) {
        subscription->statusChange = UA_STATUSCODE_BADTIMEOUT;
        count++;
    }
    return UA_Variant_setScalarCopy(&output[0], &count, &UA_TYPES[UA_TYPES_UINT32]);
}

static UA_StatusCode counter_callback(UA_Server *server, const UA_NodeId *session_id,
                                      void *session_context, const UA_NodeId *method_id,
                                      void *method_context, const UA_NodeId *object_id,
                                      void *object_context, size_t input_size,
                                      const UA_Variant *input, size_t output_size,
                                      UA_Variant *output) {
    (void)session_id;
    (void)session_context;
    (void)method_id;
    (void)object_id;
    (void)object_context;
    if (input_size != 1 || output_size != 1 ||
        !UA_Variant_hasScalarType(&input[0], &UA_TYPES[UA_TYPES_UINT32]))
        return UA_STATUSCODE_BADINVALIDARGUMENT;
    UA_UInt32 *counter = method_context == (void *)(uintptr_t)1 ? &server->wotexPeerFailDeletes
                                                                : &server->wotexPeerFailAcks;
    *counter = *(UA_UInt32 *)input[0].data;
    return UA_Variant_setScalarCopy(&output[0], counter, &UA_TYPES[UA_TYPES_UINT32]);
}

static UA_StatusCode token_callback(UA_Server *server, const UA_NodeId *session_id,
                                    void *session_context, const UA_NodeId *method_id,
                                    void *method_context, const UA_NodeId *object_id,
                                    void *object_context, size_t input_size,
                                    const UA_Variant *input, size_t output_size,
                                    UA_Variant *output) {
    (void)server;
    (void)session_id;
    (void)session_context;
    (void)method_id;
    (void)object_id;
    (void)object_context;
    (void)input;
    (void)input_size;
    if (output_size != 1) return UA_STATUSCODE_BADINVALIDARGUMENT;
    PeerState *state = (PeerState *)method_context;
    UA_String value = UA_STRING(state->token_algorithm);
    return UA_Variant_setScalarCopy(&output[0], &value, &UA_TYPES[UA_TYPES_STRING]);
}

static UA_StatusCode add_variable(UA_Server *server, UA_UInt16 namespace_index,
                                  const char *identifier, const char *name, const UA_DataType *type,
                                  const void *values, size_t count, bool array) {
    UA_VariableAttributes attributes = UA_VariableAttributes_default;
    attributes.displayName = UA_LOCALIZEDTEXT_ALLOC("en", name);
    attributes.dataType = type->typeId;
    attributes.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;
    attributes.userAccessLevel = attributes.accessLevel;
    UA_StatusCode status = array ? UA_Variant_setArrayCopy(&attributes.value, values, count, type)
                                 : UA_Variant_setScalarCopy(&attributes.value, values, type);
    if (status == UA_STATUSCODE_GOOD)
        status = UA_Server_addVariableNode(
            server, UA_NODEID_STRING(namespace_index, (char *)(uintptr_t)identifier),
            UA_NS0ID(OBJECTSFOLDER), UA_NS0ID(ORGANIZES),
            UA_QUALIFIEDNAME(namespace_index, (char *)(uintptr_t)name),
            UA_NS0ID(BASEDATAVARIABLETYPE), attributes, NULL, NULL);
    UA_VariableAttributes_clear(&attributes);
    return status;
}

static UA_StatusCode add_nodes(UA_Server *server, UA_UInt16 namespace_index, PeerState *state) {
    UA_Double value = 21.5;
    UA_ByteString bytes[2] = {UA_BYTESTRING("a"), UA_BYTESTRING("b")};
    UA_ByteString byte = UA_BYTESTRING("seed");
    UA_Int32 integers[3] = {INT32_MIN, 0, 7};
    UA_Double doubles[2] = {1.5, -0.0};
    UA_NodeId node = UA_NODEID_STRING(namespace_index, "value");
    UA_QualifiedName name = UA_QUALIFIEDNAME(namespace_index, "Name");
    UA_Variant variants[2];
    UA_Variant_init(&variants[0]);
    UA_Variant_init(&variants[1]);
    UA_Int32 one = 1;
    UA_String text = UA_STRING("x");
    UA_Variant_setScalar(&variants[0], &one, &UA_TYPES[UA_TYPES_INT32]);
    UA_Variant_setScalar(&variants[1], &text, &UA_TYPES[UA_TYPES_STRING]);
    UA_StatusCode status = add_variable(server, namespace_index, "value", "Value",
                                        &UA_TYPES[UA_TYPES_DOUBLE], &value, 1, false);
    if (status == UA_STATUSCODE_GOOD)
        status = add_variable(server, namespace_index, "byte_values", "ByteValues",
                              &UA_TYPES[UA_TYPES_BYTESTRING], bytes, 2, true);
    if (status == UA_STATUSCODE_GOOD)
        status = add_variable(server, namespace_index, "byte_value", "ByteValue",
                              &UA_TYPES[UA_TYPES_BYTESTRING], &byte, 1, false);
    if (status == UA_STATUSCODE_GOOD)
        status = add_variable(server, namespace_index, "int_values", "IntValues",
                              &UA_TYPES[UA_TYPES_INT32], integers, 3, true);
    if (status == UA_STATUSCODE_GOOD)
        status = add_variable(server, namespace_index, "double_values", "DoubleValues",
                              &UA_TYPES[UA_TYPES_DOUBLE], doubles, 2, true);
    if (status == UA_STATUSCODE_GOOD)
        status = add_variable(server, namespace_index, "node_value", "NodeValue",
                              &UA_TYPES[UA_TYPES_NODEID], &node, 1, false);
    if (status == UA_STATUSCODE_GOOD)
        status = add_variable(server, namespace_index, "name_value", "NameValue",
                              &UA_TYPES[UA_TYPES_QUALIFIEDNAME], &name, 1, false);
    if (status == UA_STATUSCODE_GOOD)
        status = add_variable(server, namespace_index, "variants", "Variants",
                              &UA_TYPES[UA_TYPES_VARIANT], variants, 2, true);
    if (status != UA_STATUSCODE_GOOD) return status;

    UA_Argument two_doubles[2];
    UA_Argument double_output;
    argument(&two_doubles[0], "left", &UA_TYPES[UA_TYPES_DOUBLE]);
    argument(&two_doubles[1], "right", &UA_TYPES[UA_TYPES_DOUBLE]);
    argument(&double_output, "sum", &UA_TYPES[UA_TYPES_DOUBLE]);
    status = add_method(server, namespace_index, "add", "Add", add_callback, 2, two_doubles, 1,
                        &double_output, state);
    UA_Argument_clear(&two_doubles[0]);
    UA_Argument_clear(&two_doubles[1]);
    UA_Argument_clear(&double_output);

    UA_Argument uint_input;
    UA_Argument uint_output;
    argument(&uint_input, "value", &UA_TYPES[UA_TYPES_UINT32]);
    argument(&uint_output, "value", &UA_TYPES[UA_TYPES_UINT32]);
    if (status == UA_STATUSCODE_GOOD)
        status = add_method(server, namespace_index, "slow", "Slow", slow_callback, 1, &uint_input,
                            1, &uint_output, state);
    if (status == UA_STATUSCODE_GOOD)
        status = add_method(server, namespace_index, "fail_deletes", "FailDeletes",
                            counter_callback, 1, &uint_input, 1, &uint_output,
                            (void *)(uintptr_t)1);
    if (status == UA_STATUSCODE_GOOD)
        status = add_method(server, namespace_index, "fail_acks", "FailAcks", counter_callback, 1,
                            &uint_input, 1, &uint_output, (void *)(uintptr_t)2);
    UA_Argument_clear(&uint_input);
    UA_Argument_clear(&uint_output);

    UA_Argument resource_outputs[2];
    argument(&resource_outputs[0], "subscriptions", &UA_TYPES[UA_TYPES_UINT32]);
    argument(&resource_outputs[1], "monitored_items", &UA_TYPES[UA_TYPES_UINT32]);
    if (status == UA_STATUSCODE_GOOD)
        status = add_method(server, namespace_index, "resources", "Resources", resources_callback,
                            0, NULL, 2, resource_outputs, state);
    UA_Argument_clear(&resource_outputs[0]);
    UA_Argument_clear(&resource_outputs[1]);

    UA_Argument fault_inputs[2];
    UA_Argument fault_outputs[2];
    argument(&fault_inputs[0], "withhold", &UA_TYPES[UA_TYPES_UINT32]);
    argument(&fault_inputs[1], "discard", &UA_TYPES[UA_TYPES_BOOLEAN]);
    argument(&fault_outputs[0], "withheld", &UA_TYPES[UA_TYPES_UINT32]);
    argument(&fault_outputs[1], "republished", &UA_TYPES[UA_TYPES_UINT32]);
    if (status == UA_STATUSCODE_GOOD)
        status = add_method(server, namespace_index, "publish_faults", "PublishFaults",
                            publish_faults_callback, 2, fault_inputs, 2, fault_outputs, state);
    UA_Argument_clear(&fault_inputs[0]);
    UA_Argument_clear(&fault_inputs[1]);
    UA_Argument_clear(&fault_outputs[0]);
    UA_Argument_clear(&fault_outputs[1]);

    UA_Argument count_output;
    argument(&count_output, "count", &UA_TYPES[UA_TYPES_UINT32]);
    if (status == UA_STATUSCODE_GOOD)
        status = add_method(server, namespace_index, "lose_subscriptions", "LoseSubscriptions",
                            lose_subscriptions_callback, 0, NULL, 1, &count_output, state);
    UA_Argument_clear(&count_output);

    UA_Argument algorithm_output;
    argument(&algorithm_output, "algorithm", &UA_TYPES[UA_TYPES_STRING]);
    if (status == UA_STATUSCODE_GOOD)
        status = add_method(server, namespace_index, "token_algorithm", "TokenAlgorithm",
                            token_callback, 0, NULL, 1, &algorithm_output, state);
    UA_Argument_clear(&algorithm_output);
    return status;
}

static bool clear_endpoints(UA_ServerConfig *config) {
    UA_Array_delete(config->endpoints, config->endpointsSize,
                    &UA_TYPES[UA_TYPES_ENDPOINTDESCRIPTION]);
    config->endpoints = NULL;
    config->endpointsSize = 0;
    return UA_ServerConfig_addAllEndpoints(config) == UA_STATUSCODE_GOOD;
}

static bool append_policy_postfix(UA_UserTokenPolicy *policy, const UA_String *uri) {
    size_t postfix_start = 0;
    for (size_t offset = 0; offset < uri->length; offset++)
        if (uri->data[offset] == '#') postfix_start = offset;
    size_t postfix_length = uri->length - postfix_start;
    UA_Byte *extended = UA_realloc(policy->policyId.data, policy->policyId.length + postfix_length);
    if (!extended) return false;
    memcpy(extended + policy->policyId.length, uri->data + postfix_start, postfix_length);
    policy->policyId.data = extended;
    policy->policyId.length += postfix_length;
    return true;
}

static bool pin_endpoint_tokens(UA_ServerConfig *config) {
    for (size_t index = 0; index < config->endpointsSize; index++) {
        UA_EndpointDescription *endpoint = &config->endpoints[index];
        UA_Array_delete(endpoint->userIdentityTokens, endpoint->userIdentityTokensSize,
                        &UA_TYPES[UA_TYPES_USERTOKENPOLICY]);
        endpoint->userIdentityTokens = NULL;
        endpoint->userIdentityTokensSize = 0;
        if (UA_Array_copy(config->accessControl.userTokenPolicies,
                          config->accessControl.userTokenPoliciesSize,
                          (void **)&endpoint->userIdentityTokens,
                          &UA_TYPES[UA_TYPES_USERTOKENPOLICY]) != UA_STATUSCODE_GOOD)
            return false;
        endpoint->userIdentityTokensSize = config->accessControl.userTokenPoliciesSize;
        for (size_t policy_index = 0; policy_index < endpoint->userIdentityTokensSize;
             policy_index++) {
            UA_UserTokenPolicy *policy = &endpoint->userIdentityTokens[policy_index];
            const UA_String *uri = &policy->securityPolicyUri;
            if (policy->tokenType != UA_USERTOKENTYPE_USERNAME) {
                UA_String_clear(&policy->securityPolicyUri);
                uri = &endpoint->securityPolicyUri;
            }
            if (!append_policy_postfix(policy, uri)) return false;
        }
    }
    return true;
}

static bool pin_encrypted_endpoint_tokens(UA_ServerConfig *config) {
    bool available[4] = {false, false, false, false};
    size_t count = 0;
    for (size_t index = 0; index < config->accessControl.userTokenPoliciesSize; index++) {
        UA_UserTokenType type = config->accessControl.userTokenPolicies[index].tokenType;
        if ((unsigned)type < 4 && !available[type]) {
            available[type] = true;
            count++;
        }
    }
    for (size_t index = 0; index < config->endpointsSize; index++) {
        UA_EndpointDescription *endpoint = &config->endpoints[index];
        UA_Array_delete(endpoint->userIdentityTokens, endpoint->userIdentityTokensSize,
                        &UA_TYPES[UA_TYPES_USERTOKENPOLICY]);
        endpoint->userIdentityTokens = UA_Array_new(count, &UA_TYPES[UA_TYPES_USERTOKENPOLICY]);
        endpoint->userIdentityTokensSize = 0;
        if (!endpoint->userIdentityTokens) return false;
        bool copied[4] = {false, false, false, false};
        for (size_t policy_index = 0; policy_index < config->accessControl.userTokenPoliciesSize;
             policy_index++) {
            const UA_UserTokenPolicy *source =
                &config->accessControl.userTokenPolicies[policy_index];
            unsigned type = (unsigned)source->tokenType;
            if (type >= 4 || copied[type]) continue;
            UA_UserTokenPolicy *policy =
                &endpoint->userIdentityTokens[endpoint->userIdentityTokensSize];
            if (UA_UserTokenPolicy_copy(source, policy) != UA_STATUSCODE_GOOD) return false;
            UA_String_clear(&policy->securityPolicyUri);
            if (UA_String_copy(&endpoint->securityPolicyUri, &policy->securityPolicyUri) !=
                    UA_STATUSCODE_GOOD ||
                !append_policy_postfix(policy, &endpoint->securityPolicyUri))
                return false;
            copied[type] = true;
            endpoint->userIdentityTokensSize++;
        }
    }
    return true;
}

static bool anonymous_only(UA_ServerConfig *config) {
    UA_UserTokenPolicy selected;
    UA_UserTokenPolicy_init(&selected);
    bool found = false;
    for (size_t index = 0; index < config->accessControl.userTokenPoliciesSize; index++) {
        UA_UserTokenPolicy *policy = &config->accessControl.userTokenPolicies[index];
        if (policy->tokenType == UA_USERTOKENTYPE_ANONYMOUS) {
            found = UA_UserTokenPolicy_copy(policy, &selected) == UA_STATUSCODE_GOOD;
            break;
        }
    }
    UA_Array_delete(config->accessControl.userTokenPolicies,
                    config->accessControl.userTokenPoliciesSize,
                    &UA_TYPES[UA_TYPES_USERTOKENPOLICY]);
    config->accessControl.userTokenPolicies = NULL;
    config->accessControl.userTokenPoliciesSize = 0;
    if (!found) return false;
    config->accessControl.userTokenPolicies = UA_Array_new(1, &UA_TYPES[UA_TYPES_USERTOKENPOLICY]);
    if (!config->accessControl.userTokenPolicies) {
        UA_UserTokenPolicy_clear(&selected);
        return false;
    }
    config->accessControl.userTokenPolicies[0] = selected;
    config->accessControl.userTokenPoliciesSize = 1;
    return clear_endpoints(config);
}

static bool configure_server(UA_Server *server, PeerVariant variant, int port,
                             const char *directory, PeerState *state) {
    const char *leaf = variant == VARIANT_EXPIRED      ? "expired.der"
                       : variant == VARIANT_WRONG_HOST ? "wronghost.der"
                                                       : "server.der";
    const char *key = variant == VARIANT_EXPIRED      ? "expired.key.der"
                      : variant == VARIANT_WRONG_HOST ? "wronghost.key.der"
                                                      : "server.key.der";
    UA_ByteString certificate = load_file(directory, leaf);
    UA_ByteString private_key = load_file(directory, key);
    UA_ByteString trust = load_file(directory, "ca.der");
    UA_ByteString crl = load_file(directory, "clean.crl");
    if (!certificate.length || !private_key.length || !trust.length || !crl.length) goto failed;
    UA_ServerConfig *config = UA_Server_getConfig(server);
    UA_StatusCode status;
    if (variant == VARIANT_NONE_ONLY)
        status = UA_ServerConfig_setMinimal(config, (UA_UInt16)port, &certificate);
    else
        status = UA_ServerConfig_setDefaultWithSecurityPolicies(config, (UA_UInt16)port,
                                                                &certificate, &private_key, &trust,
                                                                1, &trust, 1, &crl, 1);
    if (status != UA_STATUSCODE_GOOD) goto failed;
    UA_String_clear(&config->applicationDescription.applicationUri);
    config->applicationDescription.applicationUri = UA_STRING_ALLOC(PEER_URI);
    config->samplingIntervalLimits.min = 0.0;
    config->publishingIntervalLimits.min = 5.0;
    config->maxReferencesPerNode = 0;

    UA_UsernamePasswordLogin login = {UA_STRING(USERNAME), UA_BYTESTRING(PASSWORD)};
    const UA_String none = UA_STRING_STATIC("http://opcfoundation.org/UA/SecurityPolicy#None");
    const UA_String *policy = variant == VARIANT_ENCRYPTED_TOKENS ? NULL : &none;
    size_t logins = variant == VARIANT_ANONYMOUS_ONLY || variant == VARIANT_NONE_ONLY ? 0 : 1;
    if (UA_AccessControl_default(config, true, policy, logins, logins ? &login : NULL) !=
        UA_STATUSCODE_GOOD)
        goto failed;
    if ((variant == VARIANT_ANONYMOUS_ONLY || variant == VARIANT_NONE_ONLY)
            ? !anonymous_only(config)
            : !clear_endpoints(config))
        goto failed;
    if (variant == VARIANT_ENCRYPTED_TOKENS ? !pin_encrypted_endpoint_tokens(config)
                                            : !pin_endpoint_tokens(config))
        goto failed;
    state->activate_session = config->accessControl.activateSession;
    config->accessControl.activateSession = peer_activate_session;
    UA_ByteString_clear(&certificate);
    UA_ByteString_clear(&private_key);
    UA_ByteString_clear(&trust);
    UA_ByteString_clear(&crl);
    return config->applicationDescription.applicationUri.data != NULL;
failed:
    UA_ByteString_clear(&certificate);
    UA_ByteString_clear(&private_key);
    UA_ByteString_clear(&trust);
    UA_ByteString_clear(&crl);
    return false;
}

static const char *variant_name(PeerVariant variant) {
    switch (variant) {
    case VARIANT_EXPIRED:
        return "expired_leaf";
    case VARIANT_WRONG_HOST:
        return "wrong_host";
    case VARIANT_NONE_ONLY:
        return "none_only";
    case VARIANT_ANONYMOUS_ONLY:
        return "anonymous_only";
    case VARIANT_ENCRYPTED_TOKENS:
        return "encrypted_tokens";
    default:
        return "default";
    }
}

static bool parse_variant(const char *name, PeerVariant *variant) {
    if (!name || strcmp(name, "default") == 0) *variant = VARIANT_DEFAULT;
    else if (strcmp(name, "expired_leaf") == 0) *variant = VARIANT_EXPIRED;
    else if (strcmp(name, "wrong_host") == 0) *variant = VARIANT_WRONG_HOST;
    else if (strcmp(name, "none_only") == 0) *variant = VARIANT_NONE_ONLY;
    else if (strcmp(name, "anonymous_only") == 0) *variant = VARIANT_ANONYMOUS_ONLY;
    else if (strcmp(name, "encrypted_tokens") == 0) *variant = VARIANT_ENCRYPTED_TOKENS;
    else return false;
    return true;
}

static bool add_json_string(yyjson_mut_doc *document, yyjson_mut_val *object, const char *key,
                            const char *value) {
    return yyjson_mut_obj_add_strcpy(document, object, key, value);
}

static bool join_path(char *output, size_t capacity, const char *directory, const char *name) {
    return path(output, capacity, directory, name);
}

static yyjson_mut_val *bytes_envelope(yyjson_mut_doc *document, const char *directory,
                                      const char *name) {
    UA_ByteString bytes = load_file(directory, name);
    if (!bytes.length) return NULL;
    size_t capacity = 4 * ((bytes.length + 2) / 3) + 1;
    unsigned char *encoded = malloc(capacity);
    yyjson_mut_val *object = yyjson_mut_obj(document);
    int length = encoded ? EVP_EncodeBlock(encoded, bytes.data, (int)bytes.length) : -1;
    bool built = object && length >= 0 &&
                 yyjson_mut_obj_add_str(document, object, "type", "bytes") &&
                 yyjson_mut_obj_add_strncpy(document, object, "base64", (char *)encoded,
                                            (size_t)length);
    free(encoded);
    UA_ByteString_clear(&bytes);
    return built ? object : NULL;
}

static bool write_json(yyjson_mut_doc *document, const char *filename) {
    size_t length = 0;
    char *json = yyjson_mut_write(document, 0, &length);
    if (!json) return false;
    FILE *file = fopen(filename, "wb");
    bool written = file && fwrite(json, 1, length, file) == length && fputc('\n', file) == '\n';
    if (file && fclose(file) != 0) written = false;
    free(json);
    return written;
}

static bool write_config(const char *directory, const char *executable, int port,
                         UA_UInt16 namespace_index, PeerVariant variant) {
    char filename[4096];
    char endpoint[128];
    char node[128];
    char certificate[4096];
    char private_key[4096];
    char crl[4096];
    const char *suffix = variant_name(variant);
    int length = variant == VARIANT_DEFAULT
                     ? snprintf(filename, sizeof(filename), "%s/config.json", directory)
                     : snprintf(filename, sizeof(filename), "%s/config-%s.json", directory, suffix);
    if (length <= 0 || (size_t)length >= sizeof(filename) ||
        snprintf(endpoint, sizeof(endpoint), "opc.tcp://127.0.0.1:%d", port) <= 0 ||
        !join_path(certificate, sizeof(certificate), directory, "client.der") ||
        !join_path(private_key, sizeof(private_key), directory, "client.pem") ||
        !join_path(crl, sizeof(crl), directory, "clean.crl"))
        return false;
    yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *root = yyjson_mut_obj(document);
    yyjson_mut_doc_set_root(document, root);
#define ADD_NODE(KEY, ID) \
    do { \
        int node_length = snprintf(node, sizeof(node), "ns=%u;s=%s", (unsigned)namespace_index, \
                                   ID); \
        if (node_length <= 0 || (size_t)node_length >= sizeof(node) || \
            !add_json_string(document, root, KEY, node)) \
            goto failed; \
    } while (0)
    if (!root || !add_json_string(document, root, "executable", executable) ||
        !add_json_string(document, root, "endpoint", endpoint) ||
        !add_json_string(document, root, "certificate", certificate) ||
        !add_json_string(document, root, "private_key", private_key) ||
        !add_json_string(document, root, "client_uri", CLIENT_URI) ||
        !add_json_string(document, root, "server_uri", PEER_URI) ||
        !join_path(node, sizeof(node), directory, "server.der") ||
        !add_json_string(document, root, "server_certificate", node) ||
        !join_path(node, sizeof(node), directory, "ca.der") ||
        !add_json_string(document, root, "issuer_certificate", node))
        goto failed;
    yyjson_mut_val *trust = yyjson_mut_arr(document);
    if (!trust || !join_path(node, sizeof(node), directory, "ca.der") ||
        !yyjson_mut_arr_add_strcpy(document, trust, node) ||
        !yyjson_mut_obj_add_val(document, root, "trust_certificates", trust) ||
        !add_json_string(document, root, "crl", crl))
        goto failed;
    ADD_NODE("node_id", "value");
    ADD_NODE("byte_array_node_id", "byte_values");
    ADD_NODE("byte_node_id", "byte_value");
    ADD_NODE("int_array_node_id", "int_values");
    ADD_NODE("double_array_node_id", "double_values");
    ADD_NODE("node_value_id", "node_value");
    ADD_NODE("name_value_id", "name_value");
    if (!add_json_string(document, root, "object_id", "ns=0;i=85")) goto failed;
    ADD_NODE("method_id", "add");
    ADD_NODE("resources_method_id", "resources");
    ADD_NODE("faults_method_id", "publish_faults");
    ADD_NODE("loss_method_id", "lose_subscriptions");
    ADD_NODE("delete_method_id", "fail_deletes");
    ADD_NODE("acks_method_id", "fail_acks");
    ADD_NODE("variants_node_id", "variants");
    ADD_NODE("slow_method_id", "slow");
    ADD_NODE("token_method_id", "token_algorithm");
    if (!add_json_string(document, root, "username", USERNAME) ||
        !add_json_string(document, root, "password", PASSWORD) ||
        !add_json_string(document, root, "variant", suffix) || !write_json(document, filename))
        goto failed;
    yyjson_mut_doc_free(document);
#undef ADD_NODE
    if (variant != VARIANT_DEFAULT) return true;

    if (!path(filename, sizeof(filename), directory, "native-open.json")) return false;
    document = yyjson_mut_doc_new(NULL);
    root = yyjson_mut_obj(document);
    yyjson_mut_doc_set_root(document, root);
    yyjson_mut_val *authentication = yyjson_mut_obj(document);
    bool built = root && authentication && add_json_string(document, root, "endpoint", endpoint) &&
                 add_json_string(document, root, "security_policy",
                                 "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256") &&
                 add_json_string(document, root, "security_mode", "SignAndEncrypt") &&
                 add_json_string(document, root, "client_uri", CLIENT_URI) &&
                 add_json_string(document, root, "server_uri", PEER_URI) &&
                 yyjson_mut_obj_add_val(document, root, "certificate",
                                        bytes_envelope(document, directory, "client.der")) &&
                 yyjson_mut_obj_add_val(document, root, "private_key",
                                        bytes_envelope(document, directory, "client.key.der")) &&
                 yyjson_mut_obj_add_val(document, root, "server_certificate",
                                        bytes_envelope(document, directory, "server.der")) &&
                 yyjson_mut_obj_add_val(document, root, "trust_certificate",
                                        bytes_envelope(document, directory, "ca.der")) &&
                 yyjson_mut_obj_add_val(document, root, "crl",
                                        bytes_envelope(document, directory, "clean.crl")) &&
                 add_json_string(document, authentication, "type", "anonymous") &&
                 yyjson_mut_obj_add_val(document, root, "authentication", authentication) &&
                 yyjson_mut_obj_add_uint(document, root, "session_timeout_ms", 60000) &&
                 write_json(document, filename);
    yyjson_mut_doc_free(document);
    return built;
failed:
    yyjson_mut_doc_free(document);
#undef ADD_NODE
    return false;
}

static char *absolute_executable(const char *argument) {
    if (argument[0] == '/') return strdup(argument);
    char *resolved = realpath(argument, NULL);
    if (resolved) return resolved;
    char working[4096];
    if (!getcwd(working, sizeof(working))) return NULL;
    size_t size = strlen(working) + strlen(argument) + 2;
    char *joined = malloc(size);
    if (joined) snprintf(joined, size, "%s/%s", working, argument);
    return joined;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        puts("wotex-opcua-secure-peer 1");
        return 0;
    }
    if (argc < 2 || argc > 3) return 2;
    PeerVariant variant;
    if (!parse_variant(argc == 3 ? argv[2] : NULL, &variant)) return 2;
    if (variant == VARIANT_DEFAULT && !generate_fixtures(argv[1])) return 3;
    int port = available_port();
    if (port <= 0 || port > 65535) return 4;
    PeerState state;
    memset(&state, 0, sizeof(state));
    state.user_certificate = load_file(argv[1], "user.der");
    if (!state.user_certificate.length) return 5;
    active_state = &state;
    UA_Server *server = UA_Server_new();
    if (!server || !configure_server(server, variant, port, argv[1], &state)) {
        UA_Server_delete(server);
        UA_ByteString_clear(&state.user_certificate);
        active_state = NULL;
        return 6;
    }
    UA_UInt16 namespace_index = UA_Server_addNamespace(server, "urn:wotex:fixture");
    UA_StatusCode status = namespace_index ? add_nodes(server, namespace_index, &state)
                                           : UA_STATUSCODE_BADINTERNALERROR;
    if (status == UA_STATUSCODE_GOOD) status = UA_Server_run_startup(server);
    char *executable = absolute_executable(argv[0]);
    if (status != UA_STATUSCODE_GOOD || !executable ||
        !write_config(argv[1], executable, port, namespace_index, variant)) {
        free(executable);
        UA_Server_delete(server);
        UA_ByteString_clear(&state.user_certificate);
        active_state = NULL;
        return 7;
    }
    free(executable);
    signal(SIGTERM, stop_peer);
    signal(SIGINT, stop_peer);
    puts("secure peer ready");
    fflush(stdout);
    while (running) {
        (void)UA_Server_run_iterate(server, false);
        struct pollfd owner = {.fd = STDIN_FILENO, .events = POLLIN};
        int ready = poll(&owner, 1, 10);
        if (ready > 0 && (owner.revents & (POLLHUP | POLLERR | POLLNVAL))) break;
        if (ready > 0 && (owner.revents & POLLIN)) {
            char input[16];
            if (read(STDIN_FILENO, input, sizeof(input)) <= 0) break;
        }
    }
    if (status == UA_STATUSCODE_GOOD) status = UA_Server_run_shutdown(server);
    UA_Server_delete(server);
    UA_ByteString_clear(&state.user_certificate);
    active_state = NULL;
    return status == UA_STATUSCODE_GOOD ? 0 : 8;
}
