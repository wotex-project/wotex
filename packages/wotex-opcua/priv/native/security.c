/* SPDX-License-Identifier: Apache-2.0 */
#include "security.h"

#include <arpa/inet.h>
#include <openssl/err.h>
#include <openssl/rsa.h>
#include <openssl/x509v3.h>
#include <string.h>

static void secret_clear(UA_ByteString *bytes) {
    if (bytes->data) OPENSSL_cleanse(bytes->data, bytes->length);
    UA_ByteString_clear(bytes);
}

void wop_security_clear(WopSecurity *value) {
    if (!value) return;
    secret_clear(&value->private_key);
    secret_clear(&value->user_private_key);
    UA_ByteString_clear(&value->certificate);
    UA_ByteString_clear(&value->server_certificate);
    UA_ByteString_clear(&value->trust_certificate);
    UA_ByteString_clear(&value->crl);
    UA_ByteString_clear(&value->user_certificate);
    X509_free(value->server);
    X509_free(value->root);
    X509_CRL_free(value->revocations);
    memset(value, 0, sizeof(*value));
    ERR_clear_error();
}

/* Called only after canonical base64/size admission by wop_ipc_open. EVP writes
 * the padded length; reserve those last two bytes even though they are not DER. */
static bool bytes_read(yyjson_val *parameters, const char *name, UA_ByteString *result) {
    yyjson_val *encoded = yyjson_obj_get(yyjson_obj_get(parameters, name), "base64");
    size_t length = yyjson_get_len(encoded);
    size_t capacity = length / 4 * 3;
    const unsigned char *text = (const unsigned char *)yyjson_get_str(encoded);
    if (!length || capacity > 65538 ||
        UA_ByteString_allocBuffer(result, capacity) != UA_STATUSCODE_GOOD) return false;
    int decoded = EVP_DecodeBlock(result->data, text, (int)length);
    if (decoded < 0 || (size_t)decoded != capacity) return false;
    result->length -= text[length - 1] == '=';
    result->length -= text[length - 2] == '=';
    return true;
}

static X509 *certificate_read(const UA_ByteString *bytes) {
    const unsigned char *cursor = bytes->data;
    X509 *certificate = d2i_X509(NULL, &cursor, (long)bytes->length);
    if (!certificate || cursor != bytes->data + bytes->length) {
        X509_free(certificate);
        return NULL;
    }
    /* Drop the cached signed body before comparing the complete DER encoding. */
    unsigned char *encoded = NULL;
    int size = i2d_re_X509_tbs(certificate, &encoded);
    OPENSSL_free(encoded);
    encoded = NULL;
    if (size > 0) size = i2d_X509(certificate, &encoded);
    bool exact = size > 0 && (size_t)size == bytes->length &&
                 memcmp(encoded, bytes->data, bytes->length) == 0;
    OPENSSL_free(encoded);
    if (!exact) { X509_free(certificate); return NULL; }
    return certificate;
}

static X509_CRL *crl_read(const UA_ByteString *bytes) {
    const unsigned char *cursor = bytes->data;
    X509_CRL *crl = d2i_X509_CRL(NULL, &cursor, (long)bytes->length);
    if (!crl || cursor != bytes->data + bytes->length) {
        X509_CRL_free(crl);
        return NULL;
    }
    unsigned char *encoded = NULL;
    int size = i2d_re_X509_CRL_tbs(crl, &encoded);
    OPENSSL_free(encoded);
    encoded = NULL;
    if (size > 0) size = i2d_X509_CRL(crl, &encoded);
    bool exact = size > 0 && (size_t)size == bytes->length &&
                 memcmp(encoded, bytes->data, bytes->length) == 0;
    OPENSSL_free(encoded);
    if (!exact) { X509_CRL_free(crl); return NULL; }
    return crl;
}

static bool rsa_key(EVP_PKEY *key) {
    return key && EVP_PKEY_is_a(key, "RSA") && EVP_PKEY_get_bits(key) >= 2048;
}

static bool matching_key(const UA_ByteString *bytes, X509 *certificate) {
    const unsigned char *cursor = bytes->data;
    PKCS8_PRIV_KEY_INFO *info = d2i_PKCS8_PRIV_KEY_INFO(NULL, &cursor, (long)bytes->length);
    EVP_PKEY *key = NULL;
    EVP_PKEY_CTX *context = NULL;
    unsigned char *encoded = NULL;
    int size = 0;
    bool valid = false;
    if (!info || cursor != bytes->data + bytes->length) goto done;
    size = i2d_PKCS8_PRIV_KEY_INFO(info, &encoded);
    if (size <= 0 || (size_t)size != bytes->length ||
        memcmp(encoded, bytes->data, bytes->length)) goto done;
    key = EVP_PKCS82PKEY(info);
    if (!rsa_key(key) || X509_check_private_key(certificate, key) != 1) goto done;
    context = EVP_PKEY_CTX_new_from_pkey(NULL, key, NULL);
    valid = context && EVP_PKEY_pairwise_check(context) == 1;
done:
    if (encoded) OPENSSL_clear_free(encoded, size > 0 ? (size_t)size : 0);
    EVP_PKEY_CTX_free(context);
    EVP_PKEY_free(key);
    PKCS8_PRIV_KEY_INFO_free(info);
    return valid;
}

static bool strong_digest(int nid) {
    return nid == NID_sha256 || nid == NID_sha384 || nid == NID_sha512 ||
           nid == NID_sha3_256 || nid == NID_sha3_384 || nid == NID_sha3_512;
}

static bool crl_signature_digest(X509_CRL *crl) {
    int digest = NID_undef, signature = NID_undef;
    if (OBJ_find_sigid_algs(X509_CRL_get_signature_nid(crl), &digest, &signature) != 1)
        return false;
    if (signature != NID_rsassaPss) return strong_digest(digest);
    const X509_ALGOR *algorithm = NULL;
    X509_CRL_get0_signature(crl, NULL, &algorithm);
    const void *parameters = NULL;
    int type = V_ASN1_UNDEF;
    X509_ALGOR_get0(NULL, &type, &parameters, algorithm);
    if (type != V_ASN1_SEQUENCE || !parameters) return false;
    const ASN1_STRING *sequence = parameters;
    const unsigned char *begin = ASN1_STRING_get0_data(sequence), *cursor = begin;
    int length = ASN1_STRING_length(sequence);
    RSA_PSS_PARAMS *pss = d2i_RSA_PSS_PARAMS(NULL, &cursor, length);
    /* An omitted hash is SHA-1, hence outside the admitted signature profile. */
    bool valid = pss && cursor == begin + length && pss->hashAlgorithm &&
                 strong_digest(OBJ_obj2nid(pss->hashAlgorithm->algorithm));
    RSA_PSS_PARAMS_free(pss);
    return valid;
}

static bool current(const ASN1_TIME *start, const ASN1_TIME *end, time_t now) {
    if (!start || !end) return false;
    int begins = ASN1_TIME_cmp_time_t(start, now);
    int ends = ASN1_TIME_cmp_time_t(end, now);
    return begins >= -1 && begins <= 0 && ends == 1;
}

static bool extensions(X509 *certificate) {
    int count = X509_get_ext_count(certificate);
    for (int i = 0; i < count; i++) {
        X509_EXTENSION *extension = X509_get_ext(certificate, i);
        ASN1_OBJECT *oid = X509_EXTENSION_get_object(extension);
        if (X509_EXTENSION_get_critical(extension) && !X509_supported_extension(extension))
            return false;
        for (int j = 0; j < i; j++) {
            if (OBJ_cmp(oid, X509_EXTENSION_get_object(X509_get_ext(certificate, j))) == 0)
                return false;
        }
    }
    return true;
}

static bool certificate_common(X509 *certificate, time_t now, bool ca) {
    int digest = NID_undef, signature = NID_undef, bits = 0;
    uint32_t flags = 0;
    if (!certificate || X509_get_version(certificate) != 2 ||
        !extensions(certificate) || !rsa_key(X509_get0_pubkey(certificate)) ||
        !current(X509_get0_notBefore(certificate), X509_get0_notAfter(certificate), now) ||
        X509_get_signature_info(certificate, &digest, &signature, &bits, &flags) != 1 ||
        !strong_digest(digest) || bits < 128) return false;
    int critical = -1;
    BASIC_CONSTRAINTS *constraints = X509_get_ext_d2i(certificate, NID_basic_constraints,
                                                    &critical, NULL);
    bool correct_ca = constraints && ((constraints->ca != 0) == ca);
    BASIC_CONSTRAINTS_free(constraints);
    uint32_t usage = X509_get_key_usage(certificate);
    uint32_t required = ca ? KU_KEY_CERT_SIGN | KU_CRL_SIGN : KU_DIGITAL_SIGNATURE;
    return correct_ca && usage != UINT32_MAX && (usage & required) == required &&
           (ca || (usage & (KU_KEY_CERT_SIGN | KU_CRL_SIGN)) == 0);
}

static bool purpose(X509 *certificate, int nid, bool application) {
    EXTENDED_KEY_USAGE *usage = X509_get_ext_d2i(certificate, NID_ext_key_usage, NULL, NULL);
    bool found = false;
    if (usage) {
        for (int i = 0; i < sk_ASN1_OBJECT_num(usage); i++)
            if (OBJ_obj2nid(sk_ASN1_OBJECT_value(usage, i)) == nid) found = true;
    }
    EXTENDED_KEY_USAGE_free(usage);
    uint32_t bits = X509_get_key_usage(certificate);
    uint32_t required = KU_DIGITAL_SIGNATURE | KU_KEY_ENCIPHERMENT | KU_DATA_ENCIPHERMENT;
    return found && (!application || (bits & required) == required);
}

static bool application_uri(X509 *certificate, const char *uri) {
    GENERAL_NAMES *names = X509_get_ext_d2i(certificate, NID_subject_alt_name, NULL, NULL);
    bool matched = false;
    size_t count = 0, length = strlen(uri);
    if (names) {
        for (int i = 0; i < sk_GENERAL_NAME_num(names); i++) {
            GENERAL_NAME *name = sk_GENERAL_NAME_value(names, i);
            if (name->type != GEN_URI) continue;
            count++;
            ASN1_IA5STRING *value = name->d.uniformResourceIdentifier;
            matched = (size_t)ASN1_STRING_length(value) == length &&
                      memcmp(ASN1_STRING_get0_data(value), uri, length) == 0;
        }
    }
    GENERAL_NAMES_free(names);
    return matched && count == 1;
}

/* Never resolve DNS. Parse only the authority, then compare SANs without CN
 * fallback, wildcard matching, IDNA rewriting or alternate host discovery. */
static bool endpoint_host(X509 *server, const char *endpoint) {
    if (strncmp(endpoint, "opc.tcp://", 10) != 0) return false;
    const char *begin = endpoint + 10;
    const char *end = begin + strcspn(begin, "/");
    const char *port = NULL, *host_end = end;
    bool bracketed = *begin == '[';
    if (bracketed) {
        begin++;
        host_end = memchr(begin, ']', (size_t)(end - begin));
        if (!host_end) return false;
        if (host_end + 1 < end) {
            if (host_end[1] != ':') return false;
            port = host_end + 2;
        }
    } else {
        port = memchr(begin, ':', (size_t)(end - begin));
        if (port) { host_end = port; port++; }
    }
    if (port) {
        unsigned value = 0;
        if (port == end || end - port > 5) return false;
        for (const char *p = port; p < end; p++) {
            if (*p < '0' || *p > '9') return false;
            value = value * 10 + (unsigned)(*p - '0');
        }
        if (value == 0 || value > 65535) return false;
    }
    size_t length = (size_t)(host_end - begin);
    if (length == 0 || length > 253 || strpbrk(endpoint, "?#@\\") != NULL) return false;
    char host[254];
    memcpy(host, begin, length);
    host[length] = 0;
    unsigned char address[16];
    if (bracketed) {
        return inet_pton(AF_INET6, host, address) == 1 &&
               X509_check_ip(server, address, 16, 0) == 1;
    }
    if (inet_pton(AF_INET, host, address) == 1)
        return X509_check_ip(server, address, 4, 0) == 1;
    for (size_t i = 0; i < length; i++) {
        unsigned char c = (unsigned char)host[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '.')) return false;
    }
    return X509_check_host(server, host, length,
                          X509_CHECK_FLAG_NEVER_CHECK_SUBJECT | X509_CHECK_FLAG_NO_WILDCARDS,
                          NULL) == 1;
}

static bool crl_extensions(X509_CRL *crl) {
    int count = X509_CRL_get_ext_count(crl);
    for (int i = 0; i < count; i++) {
        X509_EXTENSION *extension = X509_CRL_get_ext(crl, i);
        ASN1_OBJECT *oid = X509_EXTENSION_get_object(extension);
        int nid = OBJ_obj2nid(oid);
        if (X509_EXTENSION_get_critical(extension) || nid == NID_delta_crl ||
            nid == NID_issuing_distribution_point) return false;
        for (int j = 0; j < i; j++) {
            if (OBJ_cmp(oid, X509_EXTENSION_get_object(X509_CRL_get_ext(crl, j))) == 0)
                return false;
        }
    }
    STACK_OF(X509_REVOKED) *entries = X509_CRL_get_REVOKED(crl);
    for (int i = 0; i < sk_X509_REVOKED_num(entries); i++) {
        X509_REVOKED *entry = sk_X509_REVOKED_value(entries, i);
        for (int j = 0; j < X509_REVOKED_get_ext_count(entry); j++) {
            X509_EXTENSION *extension = X509_REVOKED_get_ext(entry, j);
            if (X509_EXTENSION_get_critical(extension) ||
                OBJ_obj2nid(X509_EXTENSION_get_object(extension)) == NID_certificate_issuer)
                return false;
        }
    }
    return true;
}

static bool chain(const WopSecurity *value, time_t now) {
    X509 *root = value->root, *server = value->server;
    X509_CRL *crl = value->revocations;
    if (!certificate_common(root, now, true) || !certificate_common(server, now, false) ||
        X509_check_issued(root, root) != X509_V_OK ||
        X509_verify(root, X509_get0_pubkey(root)) != 1 ||
        X509_check_issued(root, server) != X509_V_OK ||
        X509_verify(server, X509_get0_pubkey(root)) != 1 ||
        !crl || !crl_extensions(crl) ||
        !current(X509_CRL_get0_lastUpdate(crl), X509_CRL_get0_nextUpdate(crl), now) ||
        X509_NAME_cmp(X509_CRL_get_issuer(crl), X509_get_subject_name(root)) != 0 ||
        !crl_signature_digest(crl) || X509_CRL_verify(crl, X509_get0_pubkey(root)) != 1)
        return false;
    X509_REVOKED *revoked = NULL;
    if (X509_CRL_get0_by_cert(crl, &revoked, server) != 0) return false;
    X509_STORE *store = X509_STORE_new();
    X509_STORE_CTX *context = X509_STORE_CTX_new();
    bool valid = false;
    if (!store || !context || X509_STORE_add_cert(store, root) != 1 ||
        X509_STORE_add_crl(store, crl) != 1 ||
        X509_STORE_set_flags(store, X509_V_FLAG_CRL_CHECK | X509_V_FLAG_CHECK_SS_SIGNATURE) != 1 ||
        X509_STORE_CTX_init(context, store, server, NULL) != 1) goto done;
    X509_STORE_CTX_set_time(context, 0, now);
    X509_VERIFY_PARAM_set_depth(X509_STORE_CTX_get0_param(context), 1);
    if (X509_verify_cert(context) != 1) goto done;
    STACK_OF(X509) *certificates = X509_STORE_CTX_get0_chain(context);
    valid = sk_X509_num(certificates) == 2 &&
            X509_cmp(sk_X509_value(certificates, 1), root) == 0;
done:
    X509_STORE_CTX_free(context);
    X509_STORE_free(store);
    return valid;
}

bool wop_security_peer(const WopSecurity *value, const UA_ByteString *peer, time_t now) {
    bool valid = value && peer && peer->data && value->server && value->root &&
                 peer->length == value->server_certificate.length &&
                 CRYPTO_memcmp(peer->data, value->server_certificate.data, peer->length) == 0 &&
                 chain(value, now);
    ERR_clear_error();
    return valid;
}

bool wop_security_read(yyjson_val *parameters, time_t now, WopSecurity *result) {
    if (!result) return false;
    X509 *client = NULL, *user = NULL;
    bool valid = false;
    if (!wop_ipc_open(parameters) ||
        !bytes_read(parameters, "certificate", &result->certificate) ||
        !bytes_read(parameters, "private_key", &result->private_key) ||
        !bytes_read(parameters, "server_certificate", &result->server_certificate) ||
        !bytes_read(parameters, "trust_certificate", &result->trust_certificate) ||
        !bytes_read(parameters, "crl", &result->crl)) goto done;
    client = certificate_read(&result->certificate);
    result->server = certificate_read(&result->server_certificate);
    result->root = certificate_read(&result->trust_certificate);
    result->revocations = crl_read(&result->crl);
    if (!certificate_common(client, now, false) ||
        !purpose(client, NID_client_auth, true) ||
        !application_uri(client, yyjson_get_str(yyjson_obj_get(parameters, "client_uri"))) ||
        !matching_key(&result->private_key, client) || !chain(result, now) ||
        !purpose(result->server, NID_server_auth, true) ||
        !application_uri(result->server, yyjson_get_str(yyjson_obj_get(parameters, "server_uri"))) ||
        !endpoint_host(result->server, yyjson_get_str(yyjson_obj_get(parameters, "endpoint"))))
        goto done;
    yyjson_val *authentication = yyjson_obj_get(parameters, "authentication");
    if (strcmp(yyjson_get_str(yyjson_obj_get(authentication, "type")), "certificate") == 0) {
        if (!bytes_read(authentication, "certificate", &result->user_certificate) ||
            !bytes_read(authentication, "private_key", &result->user_private_key)) goto done;
        user = certificate_read(&result->user_certificate);
        if (!certificate_common(user, now, false) || !purpose(user, NID_client_auth, false) ||
            !matching_key(&result->user_private_key, user)) goto done;
    }
    valid = true;
done:
    X509_free(client);
    X509_free(user);
    if (!valid) wop_security_clear(result);
    ERR_clear_error();
    return valid;
}
