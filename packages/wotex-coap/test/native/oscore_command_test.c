/* SPDX-License-Identifier: Apache-2.0
 * Actual C07 decoder tests. No SDK, socket or store is involved in admission.
 */
#include "command.h"
#include "body.h"
#include <assert.h>
#include <openssl/evp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned cases;
static const char security[] =
    "{\"mode\":\"oscore\",\"master_secret\":{\"type\":\"bytes\",\"base64\":\"AAECAwQFBgcICQoLDA0ODw==\"},"
    "\"master_salt\":{\"type\":\"bytes\",\"base64\":\"\"},"
    "\"sender_id\":{\"type\":\"bytes\",\"base64\":\"\"},"
    "\"recipient_id\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},"
    "\"id_context\":null,\"context_store\":\"/fixture/not-opened\"}";
static struct wco_json *json;

static void line(const char *input, int valid, enum wco_operation operation) {
    struct wco_command command;
    memset(&command, 0xa5, sizeof(command));
    enum wco_json_status status = wco_json_parse(json, input, strlen(input));
    int decoded = wco_command_decode(json, &command);
    assert(decoded == valid);
    if (valid) {
        assert(status == WCO_JSON_OK && command.operation == operation);
        assert(command.timeout_ms >= 1 && command.timeout_ms <= 60000 && command.parameters);
        char retained[65];
        int written = snprintf(retained, sizeof(retained), "%s",
                               yyjson_get_str(yyjson_obj_get(wco_json_root(json), "id")));
        assert(written >= 0 && (size_t)written < sizeof(retained));
        wco_json_reset(json);
        assert(strcmp(command.id, retained) == 0); /* Identity owns its bytes. */
    } else {
        const unsigned char *bytes = (const unsigned char *)&command;
        for (size_t index = 0; index < sizeof(command); ++index) assert(bytes[index] == 0);
    }
    wco_command_clear(&command); cases++;
}
static void parameters(const char *operation, const char *values, int valid, enum wco_operation kind) {
    char *input = malloc(WCO_JSON_FRAME_MAX); assert(input);
    int size = snprintf(input, WCO_JSON_FRAME_MAX,
        "{\"version\":1,\"id\":\"42\",\"operation\":\"%s\",\"parameters\":%s,\"timeout_ms\":60000}\n",
        operation, values);
    assert(size > 0 && size < (int)WCO_JSON_FRAME_MAX); line(input, valid, kind); free(input);
}
static void open_case(const char *host, const char *port, const char *generation,
                      const char *credentials, int valid) {
    char input[8192];
    int size = snprintf(input, sizeof(input), "{\"host\":\"%s\",\"port\":%s,\"generation\":%s,\"security\":%s}",
        host, port, generation, credentials);
    assert(size > 0 && size < (int)sizeof(input)); parameters("open", input, valid, WCO_OPEN);
}
static void changed_security(const char *before, const char *after) {
    char changed[8192]; const char *at = strstr(security, before); assert(at);
    int size = snprintf(changed, sizeof(changed), "%.*s%s%s", (int)(at-security), security,
                        after, at+strlen(before));
    assert(size > 0 && size < (int)sizeof(changed)); open_case("127.0.0.1", "5683", "1", changed, 0);
}
static void request_path(const char *value, int valid) {
    char values[8192];
    int size = snprintf(values, sizeof(values), "{\"method\":\"GET\",\"path\":\"%s\",\"confirmable\":true}", value);
    assert(size > 0 && size < (int)sizeof(values)); parameters("request", values, valid, WCO_REQUEST);
}
static void envelope(void) {
    const char *invalid[] = {
        "{}\n", "null\n", "[]\n",
        "{\"version\":2,\"id\":\"a\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1}\n",
        "{\"version\":true,\"id\":\"a\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1}\n",
        "{\"version\":1,\"id\":\"\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1}\n",
        "{\"version\":1,\"id\":\"a\\u0000b\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1}\n",
        "{\"version\":1,\"id\":\"a\\nb\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1}\n",
        "{\"version\":1,\"id\":\"a\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":0}\n",
        "{\"version\":1,\"id\":\"a\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":60001}\n",
        "{\"version\":1,\"id\":\"a\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1e0}\n",
        "{\"version\":1,\"id\":\"a\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1,\"extra\":0}\n",
        "{\"version\":1,\"version\":1,\"id\":\"a\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1}\n"
    };
    for (size_t index = 0; index < sizeof(invalid)/sizeof(invalid[0]); ++index)
        line(invalid[index], 0, WCO_CLOSE);
    parameters("close", "{}", 1, WCO_CLOSE);
    parameters("close", "{\"x\":0}", 0, WCO_CLOSE);
    parameters("close", "null", 0, WCO_CLOSE);
    parameters("unknown", "{}", 0, WCO_CLOSE);
    char id[66], input[256]; memset(id, 'a', sizeof(id));
    for (size_t length = 64; length <= 65; ++length) {
        id[length] = 0;
        snprintf(input, sizeof(input), "{\"version\":1,\"id\":\"%s\",\"operation\":\"close\",\"parameters\":{},\"timeout_ms\":1}\n", id);
        line(input, length == 64, WCO_CLOSE); id[length] = 'a';
    }
    struct wco_command command; memset(&command, 0xa5, sizeof(command));
    assert(!wco_command_decode(NULL, &command)); assert(command.parameters == NULL);
    assert(!wco_command_decode(json, NULL)); wco_command_clear(NULL);
}
static void opens(void) {
    open_case("127.0.0.1", "1", "1", security, 1);
    open_case("::1", "65535", "18446744073709551615", security, 1);
    open_case("localhost", "5683", "1", security, 0);
    open_case("127.0.0.1", "0", "1", security, 0);
    open_case("127.0.0.1", "65536", "1", security, 0);
    open_case("127.0.0.1", "true", "1", security, 0);
    open_case("127.0.0.1", "5683", "0", security, 0);
    open_case("127.0.0.1", "5683", "18446744073709551616", security, 0);
    changed_security("\"oscore\"", "\"dtls_psk\"");
    changed_security("AAECAwQFBgcICQoLDA0ODw==", "AA==");
    changed_security("AAECAwQFBgcICQoLDA0ODw==", "AAECAwQFBgcICQoLDA0ODx==");
    changed_security("\"AQ==\"", "\"\"");
    changed_security("\"/fixture/not-opened\"", "\"relative\"");
    changed_security("\"id_context\":null", "\"id_context\":false");
    changed_security("\"id_context\":null,", "");
    changed_security("\"id_context\":null", "\"id_context\":null,\"algorithm\":10");
}
static void requests(void) {
    const char *valid[] = {"", "/", "value", "/a//b/", "/a%2Fb?q=a+b&&q=%2B", "/%252e", "?empty=", "/a:b"};
    const char *invalid[] = {".", "..", "/a/../b", "/%2e", "/%2E%2e?x", "/a/./", "coap://127.0.0.1/x", "//peer/x", "/x#fragment", "/a b", "/%", "/%2z", "foo:bar"};
    for (size_t index = 0; index < sizeof(valid)/sizeof(valid[0]); ++index) request_path(valid[index], 1);
    for (size_t index = 0; index < sizeof(invalid)/sizeof(invalid[0]); ++index) request_path(invalid[index], 0);
    parameters("request", "{\"method\":\"POST\",\"path\":\"/value\",\"confirmable\":false,\"accept\":0,\"content_format\":65535,\"body_id\":\"b1\"}", 1, WCO_REQUEST);
    parameters("request", "{\"method\":\"PUT\",\"path\":\"/value\",\"confirmable\":true,\"body_id\":\"b2\"}", 1, WCO_REQUEST);
    parameters("request", "{\"method\":\"DELETE\",\"path\":\"/value\",\"confirmable\":true}", 1, WCO_REQUEST);
    parameters("request", "{\"method\":\"PATCH\",\"path\":\"/value\",\"confirmable\":true}", 0, WCO_REQUEST);
    parameters("request", "{\"method\":\"PUT\",\"path\":\"/value\",\"confirmable\":1}", 0, WCO_REQUEST);
    parameters("request", "{\"method\":\"GET\",\"path\":\"/value\",\"confirmable\":true,\"accept\":null}", 0, WCO_REQUEST);
    parameters("request", "{\"method\":\"GET\",\"path\":\"/value\",\"confirmable\":true,\"payload\":\"unexpected\"}", 0, WCO_REQUEST);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"property\",\"renew\":false}", 1, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":false,\"observation_kind\":\"event\",\"renew\":true,\"accept\":65535}", 1, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"property\"}", 0, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"property\",\"renew\":null}", 0, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"property\",\"renew\":0}", 0, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"property\",\"renew\":\"true\"}", 0, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"property\",\"renew\":{}}", 0, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true}", 0, WCO_OBSERVE);
    parameters("observe", "{\"path\":\"/value\",\"confirmable\":true,\"observation_kind\":\"event\",\"renew\":false,\"method\":\"GET\"}", 0, WCO_OBSERVE);
}
static void bodies_and_control(void) {
    parameters("body_begin", "{\"body_id\":\"b1\",\"length\":1048576,\"sha256\":\"b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78\"}", 1, WCO_BODY_BEGIN);
    parameters("body_begin", "{\"body_id\":\"b1\",\"length\":0,\"sha256\":\"INVALID\"}", 0, WCO_BODY_BEGIN);
    parameters("body_end", "{\"body_id\":\"b1\"}", 1, WCO_BODY_END);
    parameters("body_end", "{\"body_id\":\"b1\",\"length\":0}", 0, WCO_BODY_END);
    parameters("body_chunk", "{\"body_id\":\"b1\",\"offset\":0,\"data\":{\"type\":\"bytes\",\"base64\":\"QUJD\"}}", 1, WCO_BODY_CHUNK);
    parameters("body_chunk", "{\"body_id\":\"b1\",\"offset\":1048577,\"data\":{\"type\":\"bytes\",\"base64\":\"\"}}", 0, WCO_BODY_CHUNK);
    for (size_t length = 32768; length <= 32769; ++length) {
        unsigned char *raw = malloc(length), *encoded = malloc(4*((length+2)/3)+1); char *input = malloc(65536);
        assert(raw && encoded && input); memset(raw, 'x', length);
        assert(EVP_EncodeBlock(encoded, raw, (int)length) > 0);
        snprintf(input, 65536, "{\"body_id\":\"b1\",\"offset\":0,\"data\":{\"type\":\"bytes\",\"base64\":\"%s\"}}", encoded);
        parameters("body_chunk", input, length == 32768, WCO_BODY_CHUNK); free(raw); free(encoded); free(input);
    }
    parameters("credit", "{\"generation\":18446744073709551615,\"ack_seq\":18446744073709551615}", 1, WCO_CREDIT);
    parameters("credit", "{\"generation\":1,\"ack_seq\":-0}", 1, WCO_CREDIT);
    parameters("credit", "{\"generation\":1,\"ack_seq\":18446744073709551616}", 0, WCO_CREDIT);
    parameters("credit", "{\"generation\":1,\"ack_seq\":1.0}", 0, WCO_CREDIT);
    parameters("cancel", "{\"subscription_id\":\"s1\",\"generation\":1}", 1, WCO_CANCEL);
    parameters("cancel", "{\"subscription_id\":\"s1\",\"generation\":0}", 0, WCO_CANCEL);
}
int main(void) {
    json = wco_json_new(); assert(json);
    envelope(); opens(); requests(); bodies_and_control();
    wco_json_free(json);
    printf("WCO-C07 WCO-N03: %u exact operation, malformed, credential, path and integer-bound cases passed\n", cases);
    return 0;
}
