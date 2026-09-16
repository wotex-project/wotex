/* SPDX-License-Identifier: Apache-2.0 */
#include "security.h"
#include <openssl/pkcs12.h>
#include <openssl/x509v3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Fixed caller time, ephemeral in-memory keys, no files or Python generator. */
static const time_t now = 1800000000;
#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "security check line %d\n", __LINE__); exit(1); } } while (0)

typedef enum {
    VALID, USER_CERT, USER_PASSWORD, DNS_HOST, IPV6_HOST, POLICY_AES128, POLICY_AES256,
    WRONG_HOST, WRONG_URI, WRONG_CLIENT_URI, WILDCARD_HOST, CN_ONLY,
    EXPIRED, FUTURE, EXPIRES_NOW, STARTS_NOW, ROOT_EXPIRED, CLIENT_EXPIRED,
    REVOKED, STALE_CRL, FUTURE_CRL, CRL_EXPIRES_NOW, CRL_STARTS_NOW,
    BAD_CRL_SIGNATURE, BAD_CRL_ISSUER, BAD_SERVER_SIGNATURE, BAD_ROOT_SIGNATURE,
    WRONG_KEY, WEAK_KEY, WEAK_ROOT, WEAK_SIGNATURE, WEAK_CRL_SIGNATURE,
    BAD_SERVER_USAGE, BAD_CLIENT_USAGE, BAD_SERVER_EKU, BAD_CLIENT_EKU,
    UNKNOWN_CRITICAL, UNKNOWN_NONCRITICAL, DUPLICATE_EXTENSION, SERVER_CA, ROOT_NOT_CA,
    USER_WRONG_KEY, USER_EXPIRED, USER_BAD_USAGE, TRAILING_CERT, TRAILING_KEY,
    TRAILING_CRL, PEM_KEY, PKCS1_KEY, ENCRYPTED_KEY, INTERMEDIATE,
    CRL_CRITICAL, DELTA_CRL, ENDPOINT_USERINFO, ENDPOINT_PORT,
    BAD_SCHEME, WRONG_IP, TWO_URIS, PSS_SIGNATURE, PSS_CRL, LAST_CASE
} Case;

typedef struct {
    EVP_PKEY *root_key, *server_key, *client_key, *weak_key;
    X509 *root, *server, *client, *user;
    X509_CRL *crl;
} Fixture;

static void sign_pss(X509 *certificate, X509_CRL *crl, EVP_PKEY *key) {
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    EVP_PKEY_CTX *signer = NULL;
    REQUIRE(context && EVP_DigestSignInit(context, &signer, EVP_sha256(), NULL, key) == 1 &&
            EVP_PKEY_CTX_set_rsa_padding(signer, RSA_PKCS1_PSS_PADDING) == 1 &&
            EVP_PKEY_CTX_set_rsa_pss_saltlen(signer, RSA_PSS_SALTLEN_DIGEST) == 1);
    REQUIRE(certificate ? X509_sign_ctx(certificate, context) > 0 : X509_CRL_sign_ctx(crl, context) > 0);
    EVP_MD_CTX_free(context);
}

static void extension(X509 *cert, X509 *issuer, int nid, const char *text) {
    X509V3_CTX context;
    X509V3_set_ctx(&context, issuer, cert, NULL, NULL, 0);
    X509_EXTENSION *value = X509V3_EXT_conf_nid(NULL, &context, nid, text);
    REQUIRE(value && X509_add_ext(cert, value, -1) == 1);
    X509_EXTENSION_free(value);
}

static void unknown_extension(X509 *cert, bool critical) {
    ASN1_OBJECT *oid = OBJ_txt2obj("1.3.6.1.4.1.55555.1", 1);
    ASN1_OCTET_STRING *data = ASN1_OCTET_STRING_new();
    const unsigned char null_der[] = {5, 0};
    REQUIRE(oid && data && ASN1_OCTET_STRING_set(data, null_der, sizeof(null_der)) == 1);
    X509_EXTENSION *value = X509_EXTENSION_create_by_OBJ(NULL, oid, critical, data);
    REQUIRE(value && X509_add_ext(cert, value, -1) == 1);
    X509_EXTENSION_free(value);
    ASN1_OBJECT_free(oid);
    ASN1_OCTET_STRING_free(data);
}

static X509 *certificate(EVP_PKEY *key, X509 *issuer, EVP_PKEY *signer, int role, Case mode) {
    X509 *cert = X509_new();
    REQUIRE(cert && X509_set_version(cert, 2) == 1 &&
            ASN1_INTEGER_set(X509_get_serialNumber(cert), role + 1) == 1 && X509_set_pubkey(cert, key) == 1);
    X509_NAME *subject = X509_get_subject_name(cert);
    const char *name = role == 0 ? "Fixture root" : role == 1 ? "localhost" : "Fixture client";
    REQUIRE(X509_NAME_add_entry_by_NID(subject, NID_commonName, MBSTRING_ASC,
                                     (const unsigned char *)name, -1, -1, 0) == 1 &&
            X509_set_issuer_name(cert, issuer ? X509_get_subject_name(issuer) : subject) == 1);
    time_t begins = now - 3600, ends = now + 3600;
    if ((role == 1 && mode == EXPIRED) || (role == 0 && mode == ROOT_EXPIRED) ||
        (role == 2 && mode == CLIENT_EXPIRED) || (role == 3 && mode == USER_EXPIRED)) ends = now - 1;
    if (role == 1 && mode == FUTURE) begins = now + 1;
    if (role == 1 && mode == EXPIRES_NOW) ends = now;
    if (role == 1 && mode == STARTS_NOW) begins = now;
    REQUIRE(ASN1_TIME_set(X509_getm_notBefore(cert), begins) && ASN1_TIME_set(X509_getm_notAfter(cert), ends));
    bool ca = (role == 0 && mode != ROOT_NOT_CA) || (role == 1 && mode == SERVER_CA);
    extension(cert, issuer, NID_basic_constraints, ca ? "critical,CA:TRUE,pathlen:0" : "critical,CA:FALSE");
    const char *usage = ca ? "critical,keyCertSign,cRLSign" :
                            "critical,digitalSignature,keyEncipherment,dataEncipherment";
    if ((role == 1 && mode == BAD_SERVER_USAGE) || (role == 2 && mode == BAD_CLIENT_USAGE) ||
        (role == 3 && mode == USER_BAD_USAGE)) usage = "critical,keyEncipherment";
    extension(cert, issuer, NID_key_usage, usage);
    if (role) {
        const char *eku = role == 1 ? "serverAuth" : "clientAuth";
        if (role == 1 && mode == BAD_SERVER_EKU) eku = "clientAuth";
        if (role == 2 && mode == BAD_CLIENT_EKU) eku = "serverAuth";
        extension(cert, issuer, NID_ext_key_usage, eku);
        const char *san = role == 1 ? "URI:urn:fixture:server,DNS:localhost,IP:127.0.0.1,IP:::1" :
                                     "URI:urn:fixture:client";
        if (role == 1 && mode == WILDCARD_HOST) san = "URI:urn:fixture:server,DNS:*.example.com";
        if (role == 1 && mode == CN_ONLY) san = "URI:urn:fixture:server";
        if (role == 1 && mode == TWO_URIS) san = "URI:urn:fixture:other,URI:urn:fixture:server,IP:127.0.0.1";
        extension(cert, issuer, NID_subject_alt_name, san);
        if (role == 1 && (mode == UNKNOWN_CRITICAL || mode == UNKNOWN_NONCRITICAL))
            unknown_extension(cert, mode == UNKNOWN_CRITICAL);
        if (role == 1 && mode == DUPLICATE_EXTENSION) extension(cert, issuer, NID_key_usage, usage);
    }
    extension(cert, issuer, NID_subject_key_identifier, "hash");
    if (issuer) extension(cert, issuer, NID_authority_key_identifier, "keyid:always");
    REQUIRE(X509_sign(cert, signer, role == 1 && mode == WEAK_SIGNATURE ? EVP_sha1() : EVP_sha256()) > 0);
    if (mode == PSS_SIGNATURE) sign_pss(cert, NULL, signer);
    return cert;
}

static X509_CRL *revocations(Fixture *fixture, Case mode) {
    X509_CRL *crl = X509_CRL_new();
    ASN1_TIME *start = ASN1_TIME_new(), *end = ASN1_TIME_new();
    REQUIRE(crl && start && end && X509_CRL_set_version(crl, 1) == 1);
    X509 *issuer = mode == BAD_CRL_ISSUER ? fixture->client : fixture->root;
    REQUIRE(X509_CRL_set_issuer_name(crl, X509_get_subject_name(issuer)) == 1);
    time_t begins = mode == FUTURE_CRL ? now + 1 : mode == CRL_STARTS_NOW ? now : now - 60;
    time_t ends = mode == STALE_CRL ? now - 1 : mode == CRL_EXPIRES_NOW ? now : now + 60;
    REQUIRE(ASN1_TIME_set(start, begins) && ASN1_TIME_set(end, ends) &&
            X509_CRL_set1_lastUpdate(crl, start) == 1 && X509_CRL_set1_nextUpdate(crl, end) == 1);
    if (mode == REVOKED) {
        X509_REVOKED *entry = X509_REVOKED_new();
        REQUIRE(entry && X509_REVOKED_set_serialNumber(entry, X509_get_serialNumber(fixture->server)) == 1 &&
                X509_REVOKED_set_revocationDate(entry, start) == 1 && X509_CRL_add0_revoked(crl, entry) == 1);
    }
    if (mode == CRL_CRITICAL || mode == DELTA_CRL) {
        ASN1_INTEGER *number = ASN1_INTEGER_new();
        REQUIRE(number && ASN1_INTEGER_set(number, 1) == 1 &&
                X509_CRL_add1_ext_i2d(crl, mode == DELTA_CRL ? NID_delta_crl : NID_crl_number,
                                     number, mode == CRL_CRITICAL, X509V3_ADD_DEFAULT) == 1);
        ASN1_INTEGER_free(number);
    }
    REQUIRE(X509_CRL_sign(crl, mode == BAD_CRL_SIGNATURE ? fixture->client_key : fixture->root_key,
                          mode == WEAK_CRL_SIGNATURE ? EVP_sha1() : EVP_sha256()) > 0);
    if (mode == PSS_CRL) sign_pss(NULL, crl, fixture->root_key);
    ASN1_TIME_free(start);
    ASN1_TIME_free(end);
    return crl;
}

static yyjson_mut_val *bytes(yyjson_mut_doc *doc, const unsigned char *data, int size, bool trailing) {
    REQUIRE(data && size > 0 && size < 65536);
    size_t count = (size_t)size + (trailing ? 1 : 0), capacity = (count / 3 + 1) * 4 + 1;
    unsigned char *copy = malloc(count), *encoded = malloc(capacity);
    REQUIRE(copy && encoded);
    memcpy(copy, data, (size_t)size);
    if (trailing) copy[size] = 0;
    int length = EVP_EncodeBlock(encoded, copy, (int)count);
    yyjson_mut_val *object = yyjson_mut_obj(doc);
    REQUIRE(object && length > 0 && yyjson_mut_obj_add_str(doc, object, "type", "bytes") &&
            yyjson_mut_obj_add_strncpy(doc, object, "base64", (char *)encoded, (size_t)length));
    OPENSSL_clear_free(copy, count);
    OPENSSL_clear_free(encoded, capacity);
    return object;
}

static void add_certificate(yyjson_mut_doc *doc, yyjson_mut_val *object,
                            const char *name, X509 *cert, bool trailing) {
    unsigned char *encoded = NULL;
    int size = i2d_X509(cert, &encoded);
    REQUIRE(yyjson_mut_obj_add_val(doc, object, name, bytes(doc, encoded, size, trailing)));
    OPENSSL_free(encoded);
}

static void add_key(yyjson_mut_doc *doc, yyjson_mut_val *object,
                   const char *name, EVP_PKEY *key, Case mode) {
    unsigned char *encoded = NULL;
    PKCS8_PRIV_KEY_INFO *info = EVP_PKEY2PKCS8(key);
    REQUIRE(info);
    int size = i2d_PKCS8_PRIV_KEY_INFO(info, &encoded);
    if (mode == PKCS1_KEY || mode == ENCRYPTED_KEY) {
        OPENSSL_clear_free(encoded, (size_t)size);
        encoded = NULL;
        if (mode == PKCS1_KEY) size = i2d_PrivateKey(key, &encoded);
        else {
            X509_SIG *encrypted = PKCS8_encrypt(-1, EVP_aes_256_cbc(), "fixture", 7, NULL, 0, 1000, info);
            REQUIRE(encrypted);
            size = i2d_X509_SIG(encrypted, &encoded);
            X509_SIG_free(encrypted);
        }
    } else if (mode == PEM_KEY) {
        REQUIRE(size > 30);
        memcpy(encoded, "-----BEGIN PRIVATE KEY-----\n", 28);
    }
    REQUIRE(yyjson_mut_obj_add_val(doc, object, name, bytes(doc, encoded, size, mode == TRAILING_KEY)));
    OPENSSL_clear_free(encoded, (size_t)size);
    PKCS8_PRIV_KEY_INFO_free(info);
}

static char *parameters(Fixture *fixture, Case mode, size_t *length) {
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    REQUIRE(doc);
    yyjson_mut_val *root = yyjson_mut_obj(doc);
    yyjson_mut_doc_set_root(doc, root);
    const char *endpoint = "opc.tcp://127.0.0.1:4840/fixture";
    if (mode == DNS_HOST || mode == CN_ONLY) endpoint = "opc.tcp://localhost";
    if (mode == IPV6_HOST) endpoint = "opc.tcp://[::1]:4840/fixture";
    if (mode == WRONG_HOST) endpoint = "opc.tcp://different.example:4840";
    if (mode == WRONG_IP) endpoint = "opc.tcp://127.0.0.2:4840";
    if (mode == WILDCARD_HOST) endpoint = "opc.tcp://host.example.com:4840";
    if (mode == ENDPOINT_USERINFO) endpoint = "opc.tcp://user@localhost:4840";
    if (mode == ENDPOINT_PORT) endpoint = "opc.tcp://localhost:65536";
    if (mode == BAD_SCHEME) endpoint = "https://localhost:4840";
    const char *policy = "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256";
    if (mode == POLICY_AES128) policy = "http://opcfoundation.org/UA/SecurityPolicy#Aes128_Sha256_RsaOaep";
    if (mode == POLICY_AES256) policy = "http://opcfoundation.org/UA/SecurityPolicy#Aes256_Sha256_RsaPss";
    REQUIRE(yyjson_mut_obj_add_str(doc, root, "endpoint", endpoint) &&
            yyjson_mut_obj_add_str(doc, root, "security_policy", policy) &&
            yyjson_mut_obj_add_str(doc, root, "security_mode", "SignAndEncrypt") &&
            yyjson_mut_obj_add_str(doc, root, "server_uri", mode == WRONG_URI ? "urn:wrong" : "urn:fixture:server") &&
            yyjson_mut_obj_add_str(doc, root, "client_uri", mode == WRONG_CLIENT_URI ? "urn:wrong" : "urn:fixture:client") &&
            yyjson_mut_obj_add_uint(doc, root, "session_timeout_ms", 60000));
    add_certificate(doc, root, "certificate", fixture->client, false);
    add_certificate(doc, root, "server_certificate", fixture->server, mode == TRAILING_CERT);
    add_certificate(doc, root, "trust_certificate", fixture->root, false);
    add_key(doc, root, "private_key", mode == WRONG_KEY ? fixture->server_key : fixture->client_key, mode);
    unsigned char *encoded = NULL;
    int size = i2d_X509_CRL(fixture->crl, &encoded);
    REQUIRE(yyjson_mut_obj_add_val(doc, root, "crl", bytes(doc, encoded, size, mode == TRAILING_CRL)));
    OPENSSL_free(encoded);
    yyjson_mut_val *auth = yyjson_mut_obj(doc);
    REQUIRE(yyjson_mut_obj_add_val(doc, root, "authentication", auth));
    bool user = mode == USER_CERT || mode == USER_WRONG_KEY || mode == USER_EXPIRED || mode == USER_BAD_USAGE;
    REQUIRE(yyjson_mut_obj_add_str(doc, auth, "type", user ? "certificate" : mode == USER_PASSWORD ? "username" : "anonymous"));
    if (user) {
        add_certificate(doc, auth, "certificate", fixture->user, false);
        add_key(doc, auth, "private_key", mode == USER_WRONG_KEY ? fixture->server_key : fixture->client_key, VALID);
    } else if (mode == USER_PASSWORD) {
        const unsigned char password[] = {'a', 0, 'b'};
        REQUIRE(yyjson_mut_obj_add_str(doc, auth, "username", "fixture") &&
                yyjson_mut_obj_add_val(doc, auth, "password", bytes(doc, password, 3, false)));
    }
    char *json = yyjson_mut_write(doc, 0, length);
    REQUIRE(json && *length < WOP_JSON_FRAME_BYTES);
    json[(*length)++] = '\n';
    yyjson_mut_doc_free(doc);
    return json;
}

static bool accepted(Case mode) {
    return mode <= POLICY_AES256 || mode == STARTS_NOW || mode == CRL_STARTS_NOW ||
           mode == UNKNOWN_NONCRITICAL || mode == PSS_SIGNATURE || mode == PSS_CRL;
}

int main(void) {
    REQUIRE(OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG, NULL));
    Fixture f = {0};
    f.root_key = EVP_PKEY_Q_keygen(NULL, NULL, "RSA", (size_t)2048);
    f.server_key = EVP_PKEY_Q_keygen(NULL, NULL, "RSA", (size_t)2048);
    f.client_key = EVP_PKEY_Q_keygen(NULL, NULL, "RSA", (size_t)2048);
    f.weak_key = EVP_PKEY_Q_keygen(NULL, NULL, "RSA", (size_t)1024);
    REQUIRE(f.root_key && f.server_key && f.client_key && f.weak_key);
    void *pool = malloc(WOP_JSON_POOL_BYTES);
    REQUIRE(pool);
    unsigned assertions = 0;
    for (Case mode = VALID; mode < LAST_CASE; mode++) {
        EVP_PKEY *root_key = mode == WEAK_ROOT ? f.weak_key : f.root_key;
        f.root = certificate(root_key, NULL, mode == BAD_ROOT_SIGNATURE ? f.client_key : root_key, 0, mode);
        X509 *issuer = f.root;
        EVP_PKEY *signer = root_key;
        if (mode == INTERMEDIATE) { issuer = certificate(f.client_key, f.root, root_key, 0, VALID); signer = f.client_key; }
        f.server = certificate(mode == WEAK_KEY ? f.weak_key : f.server_key,
            issuer, mode == BAD_SERVER_SIGNATURE ? f.client_key : signer, 1, mode);
        if (mode == INTERMEDIATE) X509_free(issuer);
        f.client = certificate(f.client_key, f.root, root_key, 2, mode);
        f.user = certificate(f.client_key, f.root, root_key, 3, mode);
        f.crl = revocations(&f, mode);
        size_t length = 0;
        char *json = parameters(&f, mode, &length);
        WopJson parsed = {0};
        REQUIRE(wop_json_read(json, length, pool, WOP_JSON_POOL_BYTES, &parsed) == WOP_JSON_OK);
        WopSecurity security = {0};
        bool actual = wop_security_read(yyjson_doc_get_root(parsed.document), now, &security);
        if (actual != accepted(mode)) fprintf(stderr, "case %d expectation mismatch\n", mode);
        REQUIRE(actual == accepted(mode));
        assertions++;
        if (actual) {
            REQUIRE(wop_security_peer(&security, &security.server_certificate, now));
            REQUIRE(!wop_security_peer(&security, &security.certificate, now));
            REQUIRE(!wop_security_peer(&security, &security.server_certificate, now + 60));
            assertions += 3;
        } else { WopSecurity empty = {0}; REQUIRE(memcmp(&security, &empty, sizeof(empty)) == 0); }
        wop_security_clear(&security);
        wop_security_clear(&security);
        wop_json_clear(&parsed);
        OPENSSL_cleanse(pool, WOP_JSON_POOL_BYTES);
        OPENSSL_clear_free(json, length);
        X509_free(f.root); X509_free(f.server); X509_free(f.client); X509_free(f.user); X509_CRL_free(f.crl);
    }
    free(pool);
    EVP_PKEY_free(f.root_key); EVP_PKEY_free(f.server_key); EVP_PKEY_free(f.client_key); EVP_PKEY_free(f.weak_key);
    OPENSSL_cleanup();
    printf("{\"status\":\"passed\",\"cases\":%d,\"assertions\":%u,\"network_requests\":0}\n", LAST_CASE, assertions);
    return 0;
}
