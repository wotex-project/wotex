/* SPDX-License-Identifier: Apache-2.0
 * Narrow libcoap 4.3.5 OSCORE adapter. libcoap owns retransmission, token
 * allocation and Block1/Block2. This layer owns exact SDK configuration,
 * durable sender-sequence callbacks and bounded response projection.
 */
#define _POSIX_C_SOURCE 200809L
#include "exchange.h"
#include "body.h"

#ifdef WCO_WITH_LIBCOAP
#include <coap3/coap.h>
#include <arpa/inet.h>
#include <errno.h>
#include <openssl/crypto.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>

#define WCO_LIBCOAP_VERSION "libcoap 4.3.5"
#define WCO_MESSAGE_WIRE_MAX 1152u

struct upload {
    uint8_t *bytes;
    size_t length;
};

enum pending_operation {
    WCO_PENDING_NONE = 0,
    WCO_PENDING_REQUEST,
    WCO_PENDING_OBSERVE,
    WCO_PENDING_RENEW,
    WCO_PENDING_CANCEL
};

struct wco_exchange {
    coap_context_t *context;
    coap_session_t *session;
    struct wco_store *store;
    struct wco_exchange_callbacks callbacks;
    enum wco_store_status store_status;
    uint8_t token[8];
    size_t token_length;
    enum pending_operation pending;
    coap_pdu_type_t observe_type;
    int active, observing, failed;
};

static void silent_log(coap_log_t level, const char *message) {
    (void)level;
    (void)message;
}

static struct wco_exchange *from_session(coap_session_t *session) {
    coap_context_t *context = coap_session_get_context(session);
    return context ? coap_context_get_app_data(context) : NULL;
}

static void fail(struct wco_exchange *exchange, const char *code) {
    if (!exchange || exchange->failed) return;
    exchange->failed = 1;
    exchange->active = 0;
    exchange->observing = 0;
    exchange->pending = WCO_PENDING_NONE;
    exchange->callbacks.failure(exchange->callbacks.argument, code);
}

static int save_sequence(uint64_t boundary, void *argument) {
    struct wco_exchange *exchange = argument;
    exchange->store_status = wco_store_reserve(exchange->store, boundary);
    return exchange->store_status == WCO_STORE_OK;
}

static int hex_line(char *output, size_t capacity, size_t *used,
                    const char *name, const struct wco_bytes *value) {
    static const char digits[] = "0123456789abcdef";
    size_t name_length = strlen(name);
    if (name_length + 8 + value->length * 2 + 2 > capacity - *used) return 0;
    memcpy(output + *used, name, name_length); *used += name_length;
    memcpy(output + *used, ",hex,\"", 6); *used += 6;
    for (size_t index = 0; index < value->length; index++) {
        output[(*used)++] = digits[value->data[index] >> 4];
        output[(*used)++] = digits[value->data[index] & 15u];
    }
    output[(*used)++] = '"'; output[(*used)++] = '\n';
    return 1;
}

static int configuration(char *output, size_t capacity,
                         const struct wco_oscore_material *material,
                         size_t *length) {
    static const char profile[] =
        "replay_window,integer,32\n"
        "aead_alg,integer,10\n"
        "hkdf_alg,integer,-10\n"
        "rfc8613_b_1_2,bool,false\n"
        "rfc8613_b_2,bool,false\n"
        "ssn_freq,integer,32\n";
    size_t used = 0;
    if (!hex_line(output, capacity, &used, "master_secret", &material->secret) ||
        !hex_line(output, capacity, &used, "master_salt", &material->salt) ||
        (material->context_present &&
         !hex_line(output, capacity, &used, "id_context", &material->context)) ||
        !hex_line(output, capacity, &used, "sender_id", &material->sender) ||
        !hex_line(output, capacity, &used, "recipient_id", &material->recipient) ||
        sizeof(profile) - 1 > capacity - used) return 0;
    memcpy(output + used, profile, sizeof(profile) - 1);
    *length = used + sizeof(profile) - 1;
    return 1;
}

static int address(const char *host, uint16_t port, coap_address_t *peer) {
    coap_address_init(peer);
    if (inet_pton(AF_INET, host, &peer->addr.sin.sin_addr) == 1) {
        peer->addr.sin.sin_family = AF_INET;
        peer->addr.sin.sin_port = htons(port);
        peer->size = sizeof(peer->addr.sin);
        return 1;
    }
    if (inet_pton(AF_INET6, host, &peer->addr.sin6.sin6_addr) == 1) {
        peer->addr.sin6.sin6_family = AF_INET6;
        peer->addr.sin6.sin6_port = htons(port);
        peer->size = sizeof(peer->addr.sin6);
        return 1;
    }
    return 0;
}

static int known(uint16_t number) {
    static const uint16_t values[] =
        {1, 3, 4, 5, 6, 7, 8, 11, 12, 14, 15, 17, 20, 23, 27, 28, 35, 39, 60};
    for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); index++)
        if (values[index] == number) return 1;
    return 0;
}

static int single(uint16_t number) {
    static const uint16_t values[] = {3, 6, 7, 12, 14, 17, 28, 35, 39, 60};
    for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); index++)
        if (values[index] == number) return 1;
    return 0;
}

static int length_valid(uint16_t number, size_t length) {
    switch (number) {
        case 1: return length <= 8;
        case 4: return length >= 1 && length <= 8;
        case 3: case 8: case 11: case 15: case 20: case 39: return length <= 255 && (number != 3 || length);
        case 5: return length == 0;
        case 6: case 23: case 27: return length <= 3;
        case 7: case 12: case 17: return length <= 2;
        case 14: case 28: case 60: return length <= 4;
        case 35: return length >= 1 && length <= 1034;
        case 292: return length <= 8;
        default: return length <= WCO_MESSAGE_WIRE_MAX;
    }
}

static size_t extended_size(size_t value) {
    return value < 13 ? 0 : value < 269 ? 1 : 2;
}

static int project_options(const coap_pdu_t *received,
                           struct wco_exchange_message *message) {
    coap_opt_iterator_t iterator;
    coap_opt_t *option;
    uint16_t previous = 0;
    size_t wire = 4 + message->token_length;
    uint8_t singles[8] = {0};
    if (!coap_option_iterator_init(received, &iterator, COAP_OPT_ALL)) return 1;
    while ((option = coap_option_next(&iterator))) {
        uint16_t number = iterator.number;
        size_t length = coap_opt_length(option);
        /* OSCORE is consumed by the security layer. Whole-body completion
         * removes only the transfer descriptors from the public Message. */
        if (number == COAP_OPTION_OSCORE || number == COAP_OPTION_BLOCK1 ||
            number == COAP_OPTION_BLOCK2) continue;
        if (message->option_count == WCO_EXCHANGE_OPTIONS_MAX ||
            (number & 1u && !known(number)) || !length_valid(number, length) ||
            (single(number) && number < sizeof(singles) * 8 &&
             (singles[number / 8] & (1u << (number % 8))))) return 0;
        if (single(number) && number < sizeof(singles) * 8)
            singles[number / 8] |= 1u << (number % 8);
        wire += 1 + extended_size(number - previous) + extended_size(length) + length;
        if (wire > WCO_MESSAGE_WIRE_MAX) return 0;
        message->options[message->option_count++] =
            (struct wco_exchange_option){number, coap_opt_value(option), length};
        previous = number;
    }
    return 1;
}

static coap_response_t response_handler(coap_session_t *session,
                                        const coap_pdu_t *sent,
                                        const coap_pdu_t *received,
                                        coap_mid_t mid) {
    struct wco_exchange *exchange = from_session(session);
    struct wco_exchange_message message;
    coap_bin_const_t token = coap_pdu_get_token(received);
    coap_opt_iterator_t observe_iterator;
    int has_observe;
    size_t offset = 0, total = 0;
    (void)sent; (void)mid;
    if (!exchange || (!exchange->active && !exchange->observing) ||
        token.length != exchange->token_length ||
        (token.length && memcmp(token.s, exchange->token, token.length)))
        return coap_pdu_get_type(received) == COAP_MESSAGE_CON ||
               coap_pdu_get_type(received) == COAP_MESSAGE_NON ?
               COAP_RESPONSE_FAIL : COAP_RESPONSE_OK;
    memset(&message, 0, sizeof(message));
    message.type = (uint8_t)coap_pdu_get_type(received);
    message.code = (uint8_t)coap_pdu_get_code(received);
    message.message_id = (uint16_t)coap_pdu_get_mid(received);
    message.token = token.s; message.token_length = token.length;
    if (!coap_get_data_large(received, &message.payload_length, &message.payload,
                             &offset, &total)) {
        message.payload = (const uint8_t *)"";
        message.payload_length = offset = total = 0;
    }
    if (offset || message.payload_length != total || total > WCO_BODY_MAX ||
        token.length > sizeof(exchange->token) || !project_options(received, &message)) {
        fail(exchange, total > WCO_BODY_MAX ? "body_limit" : "invalid_response");
        return COAP_RESPONSE_OK;
    }
    has_observe = coap_check_option(received, COAP_OPTION_OBSERVE,
                                    &observe_iterator) != NULL;
    if (exchange->pending == WCO_PENDING_REQUEST) {
        message.delivery = WCO_EXCHANGE_UNARY;
        exchange->active = 0;
        exchange->pending = WCO_PENDING_NONE;
    } else if (exchange->pending == WCO_PENDING_OBSERVE) {
        message.delivery = WCO_EXCHANGE_OBSERVE_INITIAL;
        exchange->active = 0;
        exchange->pending = WCO_PENDING_NONE;
        exchange->observing = has_observe && message.code >= 64 && message.code <= 94;
    } else if (exchange->pending == WCO_PENDING_RENEW) {
        message.delivery = WCO_EXCHANGE_OBSERVE_RENEWED;
        exchange->active = 0;
        exchange->pending = WCO_PENDING_NONE;
        exchange->observing = has_observe && message.code >= 64 && message.code <= 94;
    } else if (exchange->pending == WCO_PENDING_CANCEL) {
        if (has_observe) {
            message.delivery = WCO_EXCHANGE_OBSERVE_INTERVENING;
        } else {
            message.delivery = WCO_EXCHANGE_CANCELLED;
            exchange->active = 0;
            exchange->observing = 0;
            exchange->pending = WCO_PENDING_NONE;
        }
    } else if (exchange->observing) {
        message.delivery = WCO_EXCHANGE_OBSERVE_REPORT;
    } else {
        return COAP_RESPONSE_OK;
    }
    if (!exchange->callbacks.response(exchange->callbacks.argument, &message))
        exchange->failed = 1;
    return COAP_RESPONSE_OK;
}

static void nack_handler(coap_session_t *session, const coap_pdu_t *sent,
                         coap_nack_reason_t reason, coap_mid_t mid) {
    struct wco_exchange *exchange = from_session(session);
    (void)sent; (void)mid;
    if (!exchange || (!exchange->active && !exchange->observing)) return;
    switch (reason) {
        case COAP_NACK_TOO_MANY_RETRIES: fail(exchange, "timeout"); break;
        case COAP_NACK_RST: case COAP_NACK_BAD_RESPONSE:
            fail(exchange, "invalid_response"); break;
        default: fail(exchange, "connection_closed"); break;
    }
}

static int event_handler(coap_session_t *session, coap_event_t event) {
    struct wco_exchange *exchange = from_session(session);
    if (!exchange || (!exchange->active && !exchange->observing)) return 0;
    switch (event) {
        case COAP_EVENT_OSCORE_DECRYPTION_FAILURE:
        case COAP_EVENT_OSCORE_NOT_ENABLED:
        case COAP_EVENT_OSCORE_NO_PROTECTED_PAYLOAD:
        case COAP_EVENT_OSCORE_NO_SECURITY:
        case COAP_EVENT_OSCORE_INTERNAL_ERROR:
        case COAP_EVENT_OSCORE_DECODE_ERROR:
            fail(exchange, "security_handshake_failed");
            break;
        case COAP_EVENT_SESSION_FAILED:
        case COAP_EVENT_SESSION_CLOSED:
        case COAP_EVENT_BAD_PACKET:
            fail(exchange, "connection_closed");
            break;
        default: break;
    }
    return 0;
}

static void release_upload(coap_session_t *session, void *argument) {
    struct upload *upload = argument;
    (void)session;
    if (!upload) return;
    if (upload->bytes) {
        OPENSSL_cleanse(upload->bytes, upload->length);
        free(upload->bytes);
    }
    OPENSSL_cleanse(upload, sizeof(*upload));
    free(upload);
}

static int option(coap_optlist_t **options, uint16_t number,
                  const uint8_t *value, size_t length) {
    coap_optlist_t *entry = coap_new_optlist(number, length, value);
    if (!entry) return 0;
    if (coap_insert_optlist(options, entry)) return 1;
    coap_delete_optlist(entry);
    return 0;
}

static int uint_option(coap_optlist_t **options, uint16_t number, uint16_t value) {
    uint8_t encoded[2];
    size_t length = coap_encode_var_safe(encoded, sizeof(encoded), value);
    return option(options, number, encoded, length);
}

static int request_options(const char *path, int accept_present, uint16_t accept,
                           int format_present, uint16_t format,
                           coap_optlist_t **options) {
    const char *query = strchr(path, '?');
    size_t path_length = query ? (size_t)(query - path) : strlen(path);
    const uint8_t *path_bytes = (const uint8_t *)path;
    if (path_length == 1 && path[0] == '/') path_length = 0;
    else if (path_length && path[0] == '/') { path_bytes++; path_length--; }
    if ((path_length && !coap_path_into_optlist(path_bytes, path_length,
                                                COAP_OPTION_URI_PATH, options)) ||
        (format_present && !uint_option(options, COAP_OPTION_CONTENT_FORMAT, format)) ||
        (query && !coap_query_into_optlist((const uint8_t *)(query + 1), strlen(query + 1),
                                           COAP_OPTION_URI_QUERY, options)) ||
        (accept_present && !uint_option(options, COAP_OPTION_ACCEPT, accept))) return 0;
    return 1;
}

const char *wco_exchange_open(const char *host, uint16_t port,
                              const struct wco_oscore_material *material,
                              struct wco_store *store,
                              const struct wco_exchange_callbacks *callbacks,
                              struct wco_exchange **result) {
    char config_bytes[1024]; size_t config_length = 0;
    coap_address_t peer; coap_oscore_conf_t *config;
    struct wco_exchange *exchange;
    if (!result || !callbacks || !callbacks->response || !callbacks->failure ||
        !material || !store || !address(host, port, &peer)) return "invalid_request";
    *result = NULL;
    coap_startup(); coap_set_log_level(COAP_LOG_EMERG); coap_set_log_handler(silent_log);
    if (!coap_oscore_is_supported() ||
        strcmp(coap_package_version(), WCO_LIBCOAP_VERSION)) {
        coap_cleanup(); return "unsupported_native_backend";
    }
    exchange = calloc(1, sizeof(*exchange));
    if (!exchange) { coap_cleanup(); return "native_unavailable"; }
    exchange->store = store; exchange->callbacks = *callbacks;
    exchange->store_status = WCO_STORE_OK;
    if (!configuration(config_bytes, sizeof(config_bytes), material, &config_length)) {
        free(exchange); coap_cleanup(); return "invalid_request";
    }
    config = coap_new_oscore_conf((coap_str_const_t){config_length,
                                  (const uint8_t *)config_bytes},
                                  save_sequence, exchange, 0);
    OPENSSL_cleanse(config_bytes, sizeof(config_bytes));
    if (!config) { free(exchange); coap_cleanup(); return "unsupported_native_backend"; }
    exchange->context = coap_new_context(NULL);
    if (!exchange->context) {
        coap_delete_oscore_conf(config); free(exchange); coap_cleanup();
        return "native_unavailable";
    }
    coap_context_set_app_data(exchange->context, exchange);
    coap_context_set_block_mode(exchange->context,
                                COAP_BLOCK_USE_LIBCOAP | COAP_BLOCK_SINGLE_BODY);
    coap_context_set_max_token_size(exchange->context, sizeof(exchange->token));
    coap_register_response_handler(exchange->context, response_handler);
    coap_register_nack_handler(exchange->context, nack_handler);
    coap_register_event_handler(exchange->context, event_handler);
    exchange->session = coap_new_client_session_oscore(exchange->context, NULL, &peer,
                                                        COAP_PROTO_UDP, config);
    if (!exchange->session) {
        coap_free_context(exchange->context); free(exchange); coap_cleanup();
        return "security_handshake_failed";
    }
    *result = exchange;
    return NULL;
}

const char *wco_exchange_request(struct wco_exchange *exchange,
                                 const char *method, const char *path,
                                 int confirmable, int accept_present,
                                 uint16_t accept, int format_present,
                                 uint16_t format, int body_present,
                                 const uint8_t *body, size_t body_length) {
    coap_pdu_code_t code; coap_pdu_t *pdu = NULL; coap_optlist_t *options = NULL;
    struct upload *upload = NULL;
    coap_mid_t mid;
    if (!exchange || exchange->failed) return "connection_closed";
    if (exchange->active) return "busy";
    if (exchange->observing) return "observation_active";
    if (!strcmp(method, "GET")) code = COAP_REQUEST_CODE_GET;
    else if (!strcmp(method, "POST")) code = COAP_REQUEST_CODE_POST;
    else if (!strcmp(method, "PUT")) code = COAP_REQUEST_CODE_PUT;
    else if (!strcmp(method, "DELETE")) code = COAP_REQUEST_CODE_DELETE;
    else return "invalid_request";
    if (!request_options(path, accept_present, accept, format_present, format, &options))
        goto invalid;
    pdu = coap_new_pdu(confirmable ? COAP_MESSAGE_CON : COAP_MESSAGE_NON, code,
                       exchange->session);
    if (!pdu) goto unavailable;
    exchange->token_length = sizeof(exchange->token);
    coap_session_new_token(exchange->session, &exchange->token_length, exchange->token);
    if (!coap_add_token(pdu, exchange->token_length, exchange->token) ||
        !coap_add_optlist_pdu(pdu, &options)) goto unavailable;
    if (body_present && body_length) {
        upload = calloc(1, sizeof(*upload));
        if (!upload || !(upload->bytes = malloc(body_length))) goto unavailable;
        memcpy(upload->bytes, body, body_length); upload->length = body_length;
        if (!coap_add_data_large_request(exchange->session, pdu, body_length,
                                         upload->bytes, release_upload, upload))
            goto unavailable;
        upload = NULL;
    }
    coap_delete_optlist(options); options = NULL;
    exchange->store_status = WCO_STORE_OK;
    mid = coap_send(exchange->session, pdu); pdu = NULL;
    if (mid == COAP_INVALID_MID) {
        const char *error = exchange->store_status == WCO_STORE_OK ?
            "connection_closed" : wco_store_code(exchange->store_status);
        exchange->failed = 1;
        return error;
    }
    exchange->active = 1;
    exchange->pending = WCO_PENDING_REQUEST;
    return NULL;
invalid:
    coap_delete_optlist(options);
    return "invalid_request";
unavailable:
    coap_delete_optlist(options);
    if (pdu) coap_delete_pdu(pdu);
    release_upload(exchange ? exchange->session : NULL, upload);
    return "native_unavailable";
}

static const char *send_observe(struct wco_exchange *exchange,
                                const char *path, int confirmable,
                                int accept_present, uint16_t accept,
                                int renewing) {
    coap_pdu_t *pdu = NULL;
    coap_optlist_t *options = NULL;
    uint8_t observe[1];
    coap_mid_t mid;
    size_t observe_length;
    if (!exchange || exchange->failed) return "connection_closed";
    if (exchange->active) return "busy";
    if (renewing ? !exchange->observing : exchange->observing)
        return renewing ? "invalid_request" : "observation_active";
    observe_length = coap_encode_var_safe(observe, sizeof(observe),
                                          COAP_OBSERVE_ESTABLISH);
    if (!request_options(path, accept_present, accept, 0, 0, &options) ||
        !option(&options, COAP_OPTION_OBSERVE, observe, observe_length))
        goto invalid;
    pdu = coap_new_pdu(confirmable ? COAP_MESSAGE_CON : COAP_MESSAGE_NON,
                       COAP_REQUEST_CODE_GET, exchange->session);
    if (!pdu) goto unavailable;
    if (!renewing) {
        exchange->token_length = sizeof(exchange->token);
        coap_session_new_token(exchange->session, &exchange->token_length,
                               exchange->token);
    }
    if (!coap_add_token(pdu, exchange->token_length, exchange->token) ||
        !coap_add_optlist_pdu(pdu, &options)) goto unavailable;
    coap_delete_optlist(options); options = NULL;
    exchange->store_status = WCO_STORE_OK;
    mid = coap_send(exchange->session, pdu); pdu = NULL;
    if (mid == COAP_INVALID_MID) {
        const char *error = exchange->store_status == WCO_STORE_OK ?
            "connection_closed" : wco_store_code(exchange->store_status);
        exchange->failed = 1;
        return error;
    }
    if (!renewing)
        exchange->observe_type = confirmable ? COAP_MESSAGE_CON : COAP_MESSAGE_NON;
    exchange->active = 1;
    exchange->pending = renewing ? WCO_PENDING_RENEW : WCO_PENDING_OBSERVE;
    return NULL;
invalid:
    coap_delete_optlist(options);
    return "invalid_request";
unavailable:
    coap_delete_optlist(options);
    if (pdu) coap_delete_pdu(pdu);
    return "native_unavailable";
}

const char *wco_exchange_observe(struct wco_exchange *exchange,
                                 const char *path, int confirmable,
                                 int accept_present, uint16_t accept) {
    return send_observe(exchange, path, confirmable, accept_present, accept, 0);
}

const char *wco_exchange_renew(struct wco_exchange *exchange,
                               const char *path, int confirmable,
                               int accept_present, uint16_t accept) {
    return send_observe(exchange, path, confirmable, accept_present, accept, 1);
}

const char *wco_exchange_cancel(struct wco_exchange *exchange,
                                const char *path, int accept_present,
                                uint16_t accept) {
    coap_binary_t *token = NULL;
    coap_pdu_t *pdu = NULL;
    coap_optlist_t *options = NULL;
    uint8_t observe[1];
    coap_mid_t mid;
    size_t observe_length;
    if (!exchange || exchange->failed) return "connection_closed";
    if (exchange->active && exchange->pending != WCO_PENDING_RENEW) return "busy";
    if (!exchange->observing) return "invalid_request";
    if (exchange->pending == WCO_PENDING_RENEW) {
        exchange->active = 0;
        exchange->pending = WCO_PENDING_NONE;
    }
    token = coap_new_binary(exchange->token_length);
    if (token && exchange->token_length)
        memcpy(token->s, exchange->token, exchange->token_length);
    exchange->store_status = WCO_STORE_OK;
    if (token && coap_cancel_observe(exchange->session, token,
                                     exchange->observe_type)) {
        coap_delete_binary(token);
        exchange->active = 1;
        exchange->pending = WCO_PENDING_CANCEL;
        return NULL;
    }
    coap_delete_binary(token);
    if (exchange->store_status != WCO_STORE_OK) {
        exchange->failed = 1;
        return wco_store_code(exchange->store_status);
    }
    observe_length = coap_encode_var_safe(observe, sizeof(observe),
                                          COAP_OBSERVE_CANCEL);
    if (!request_options(path, accept_present, accept, 0, 0, &options) ||
        !option(&options, COAP_OPTION_OBSERVE, observe, observe_length))
        goto invalid;
    pdu = coap_new_pdu(exchange->observe_type, COAP_REQUEST_CODE_GET,
                       exchange->session);
    if (!pdu ||
        !coap_add_token(pdu, exchange->token_length, exchange->token) ||
        !coap_add_optlist_pdu(pdu, &options)) goto unavailable;
    coap_delete_optlist(options); options = NULL;
    mid = coap_send(exchange->session, pdu); pdu = NULL;
    if (mid == COAP_INVALID_MID) {
        const char *error = exchange->store_status == WCO_STORE_OK ?
            "native_unavailable" : wco_store_code(exchange->store_status);
        if (exchange->store_status != WCO_STORE_OK) exchange->failed = 1;
        return error;
    }
    exchange->active = 1;
    exchange->pending = WCO_PENDING_CANCEL;
    return NULL;
invalid:
    coap_delete_optlist(options);
    return "invalid_request";
unavailable:
    coap_delete_optlist(options);
    if (pdu) coap_delete_pdu(pdu);
    return "native_unavailable";
}

int wco_exchange_io(struct wco_exchange *exchange) {
    if (!exchange || exchange->failed) return 0;
    if (coap_io_process(exchange->context, COAP_IO_NO_WAIT) < 0) {
        if (exchange->active) fail(exchange, "connection_closed");
        return 0;
    }
    return !exchange->failed;
}

int wco_exchange_wait(struct wco_exchange *exchange, int read_fd, int write_fd,
                      int timeout_ms) {
    int coap_fd;
    if (!exchange || exchange->failed || timeout_ms <= 0) return 0;
    coap_fd = coap_context_get_coap_fd(exchange->context);
    if (coap_fd >= 0) {
        /* epoll builds ignore caller descriptors in coap_io_process_with_fds. */
        struct pollfd descriptors[3] = {
            {read_fd, POLLIN, 0}, {write_fd, POLLOUT, 0}, {coap_fd, POLLIN, 0}};
        coap_tick_t now;
        unsigned int next;
        coap_ticks(&now);
        next = coap_io_prepare_epoll(exchange->context, now);
        if (next > 0 && next < (unsigned int)timeout_ms) timeout_ms = (int)next;
        if (poll(descriptors, 3, timeout_ms) < 0 && errno != EINTR) return 0;
        return 1;
    } else {
        fd_set readable, writable;
        int count = 0;
        FD_ZERO(&readable);
        FD_ZERO(&writable);
        if (read_fd >= 0) {
            FD_SET(read_fd, &readable);
            count = read_fd + 1;
        }
        if (write_fd >= 0) {
            FD_SET(write_fd, &writable);
            if (write_fd >= count) count = write_fd + 1;
        }
        if (coap_io_process_with_fds(exchange->context, (uint32_t)timeout_ms,
                                     count, &readable, &writable, NULL) < 0) {
            if (exchange->active) fail(exchange, "connection_closed");
            return 0;
        }
        return 1;
    }
}

int wco_exchange_active(const struct wco_exchange *exchange) {
    return exchange && (exchange->active || exchange->observing);
}

void wco_exchange_close(struct wco_exchange *exchange) {
    if (!exchange) return;
    if (exchange->session) coap_session_release(exchange->session);
    if (exchange->context) coap_free_context(exchange->context);
    OPENSSL_cleanse(exchange, sizeof(*exchange));
    free(exchange);
    coap_cleanup();
}

#else

const char *wco_exchange_open(const char *host, uint16_t port,
                              const struct wco_oscore_material *material,
                              struct wco_store *store,
                              const struct wco_exchange_callbacks *callbacks,
                              struct wco_exchange **result) {
    (void)host; (void)port; (void)material; (void)store; (void)callbacks;
    if (result) *result = NULL;
    return NULL;
}
const char *wco_exchange_request(struct wco_exchange *exchange,
                                 const char *method, const char *path,
                                 int confirmable, int accept_present,
                                 uint16_t accept, int format_present,
                                 uint16_t format, int body_present,
                                 const uint8_t *body, size_t body_length) {
    (void)exchange; (void)method; (void)path; (void)confirmable;
    (void)accept_present; (void)accept; (void)format_present; (void)format;
    (void)body_present; (void)body; (void)body_length;
    return "native_unavailable";
}
const char *wco_exchange_observe(struct wco_exchange *exchange,
                                 const char *path, int confirmable,
                                 int accept_present, uint16_t accept) {
    (void)exchange; (void)path; (void)confirmable; (void)accept_present; (void)accept;
    return "native_unavailable";
}
const char *wco_exchange_renew(struct wco_exchange *exchange,
                               const char *path, int confirmable,
                               int accept_present, uint16_t accept) {
    (void)exchange; (void)path; (void)confirmable; (void)accept_present; (void)accept;
    return "native_unavailable";
}
const char *wco_exchange_cancel(struct wco_exchange *exchange,
                                const char *path, int accept_present,
                                uint16_t accept) {
    (void)exchange; (void)path; (void)accept_present; (void)accept;
    return "native_unavailable";
}
int wco_exchange_io(struct wco_exchange *exchange) { (void)exchange; return 1; }
int wco_exchange_wait(struct wco_exchange *exchange, int read_fd, int write_fd,
                      int timeout_ms) {
    (void)exchange; (void)read_fd; (void)write_fd; (void)timeout_ms;
    return 0;
}
int wco_exchange_active(const struct wco_exchange *exchange) { (void)exchange; return 0; }
void wco_exchange_close(struct wco_exchange *exchange) { (void)exchange; }

#endif
