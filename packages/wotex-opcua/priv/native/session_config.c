/* SPDX-License-Identifier: Apache-2.0 */
#include "session_config.h"

#include <open62541/client_config_default.h>
#include <openssl/evp.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    UA_CertificateGroup previous;
    const WopSecurity *security;
} WopVerifier;

static UA_StatusCode reject_password_prompt(UA_ClientConfig *config, UA_ByteString *password) {
    (void)config;
    (void)password;
    return UA_STATUSCODE_BADSECURITYCHECKSFAILED;
}

static UA_StatusCode verify_peer(UA_CertificateGroup *group,
                                 const UA_ByteString *certificate) {
    WopVerifier *verifier = (WopVerifier *)group->context;
    time_t now = time(NULL);
    if(!verifier || now == (time_t)-1 ||
       !wop_security_peer(verifier->security, certificate, now))
        return UA_STATUSCODE_BADCERTIFICATEINVALID;
    return UA_STATUSCODE_GOOD;
}

static void clear_verifier(UA_CertificateGroup *group) {
    WopVerifier *verifier = (WopVerifier *)group->context;
    if(verifier) {
        if(verifier->previous.clear)
            verifier->previous.clear(&verifier->previous);
        free(verifier);
    }
    memset(group, 0, sizeof(*group));
}

static bool install_verifier(UA_ClientConfig *config, const WopSecurity *security) {
    WopVerifier *verifier = calloc(1, sizeof(*verifier));
    if(!verifier) return false;
    verifier->previous = config->certificateVerification;
    verifier->security = security;
    memset(&config->certificateVerification, 0, sizeof(config->certificateVerification));
    config->certificateVerification.context = verifier;
    config->certificateVerification.logging = config->logging;
    config->certificateVerification.verifyCertificate = verify_peer;
    config->certificateVerification.clear = clear_verifier;
    return true;
}

static bool copy_text(yyjson_val *value, UA_String *result) {
    UA_String view = {(size_t)yyjson_get_len(value), (UA_Byte *)yyjson_get_str(value)};
    return UA_String_copy(&view, result) == UA_STATUSCODE_GOOD;
}

static bool password_read(yyjson_val *authentication, UA_ByteString *password) {
    yyjson_val *encoded = yyjson_obj_get(yyjson_obj_get(authentication, "password"), "base64");
    size_t length = yyjson_get_len(encoded);
    if(!length) return UA_ByteString_allocBuffer(password, 0) == UA_STATUSCODE_GOOD;
    size_t capacity = length / 4 * 3;
    if(capacity > 4098 || UA_ByteString_allocBuffer(password, capacity) != UA_STATUSCODE_GOOD)
        return false;
    const unsigned char *text = (const unsigned char *)yyjson_get_str(encoded);
    int decoded = EVP_DecodeBlock(password->data, text, (int)length);
    if(decoded < 0 || (size_t)decoded != capacity) return false;
    password->length -= text[length - 1] == '=';
    password->length -= text[length - 2] == '=';
    return true;
}

static bool authentication(UA_ClientConfig *config, yyjson_val *parameters,
                           const WopSecurity *security) {
    yyjson_val *auth = yyjson_obj_get(parameters, "authentication");
    const char *type = yyjson_get_str(yyjson_obj_get(auth, "type"));
    if(strcmp(type, "anonymous") == 0) return true;
    if(strcmp(type, "certificate") == 0)
        return UA_ClientConfig_setAuthenticationCert(config, security->user_certificate,
                                                      security->user_private_key) == UA_STATUSCODE_GOOD;
    if(strcmp(type, "username") != 0) return false;
    UA_UserNameIdentityToken *token = UA_UserNameIdentityToken_new();
    if(!token) return false;
    bool valid = copy_text(yyjson_obj_get(auth, "username"), &token->userName) &&
                 password_read(auth, &token->password);
    if(!valid) {
        UA_UserNameIdentityToken_delete(token);
        return false;
    }
    UA_ExtensionObject_clear(&config->userIdentityToken);
    config->userIdentityToken.encoding = UA_EXTENSIONOBJECT_DECODED;
    config->userIdentityToken.content.decoded.type = &UA_TYPES[UA_TYPES_USERNAMEIDENTITYTOKEN];
    config->userIdentityToken.content.decoded.data = token;
    return true;
}

bool wop_session_configure(UA_ClientConfig *config, yyjson_val *parameters,
                           const WopSecurity *security) {
    if(!config || !security || !security->server || !wop_ipc_open(parameters)) return false;
    config->privateKeyPasswordCallback = reject_password_prompt;
    if(UA_ClientConfig_setDefaultEncryption(config, security->certificate,
            security->private_key, &security->trust_certificate, 1,
            &security->crl, 1) != UA_STATUSCODE_GOOD) return false;
    if(!install_verifier(config, security)) return false;

    config->noReconnect = true;
    config->noNewSession = true;
    config->securityMode = UA_MESSAGESECURITYMODE_SIGNANDENCRYPT;
    config->endpoint.securityMode = UA_MESSAGESECURITYMODE_SIGNANDENCRYPT;
    config->allowNonePolicyPassword = false;
    uint64_t timeout = 0;
    if(!wop_json_uint64(yyjson_obj_get(parameters, "session_timeout_ms"), &timeout))
        return false;
    config->requestedSessionTimeout = (UA_UInt32)timeout;

    UA_String_clear(&config->clientDescription.applicationUri);
    if(!copy_text(yyjson_obj_get(parameters, "client_uri"),
                  &config->clientDescription.applicationUri) ||
       !copy_text(yyjson_obj_get(parameters, "server_uri"), &config->applicationUri) ||
       !copy_text(yyjson_obj_get(parameters, "server_uri"),
                  &config->endpoint.server.applicationUri) ||
       !copy_text(yyjson_obj_get(parameters, "endpoint"), &config->endpoint.endpointUrl) ||
       !copy_text(yyjson_obj_get(parameters, "security_policy"),
                  &config->securityPolicyUri) ||
       UA_String_copy(&config->securityPolicyUri,
                      &config->endpoint.securityPolicyUri) != UA_STATUSCODE_GOOD ||
       UA_ByteString_copy(&security->server_certificate,
                          &config->endpoint.serverCertificate) != UA_STATUSCODE_GOOD ||
       !authentication(config, parameters, security)) return false;

    for(size_t i = 0; i < config->securityPoliciesSize; i++) {
        if(UA_String_equal(&config->securityPolicyUri,
                           &config->securityPolicies[i].policyUri)) return true;
    }
    return false;
}
