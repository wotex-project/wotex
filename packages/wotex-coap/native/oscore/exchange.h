/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_EXCHANGE_H
#define WOTEX_COAP_OSCORE_EXCHANGE_H

#include "identity.h"
#include "store.h"
#include <stddef.h>
#include <stdint.h>

#define WCO_EXCHANGE_OPTIONS_MAX 64u

struct wco_exchange;

struct wco_exchange_option {
    uint16_t number;
    const uint8_t *value;
    size_t length;
};

enum wco_exchange_delivery {
    WCO_EXCHANGE_UNARY = 0,
    WCO_EXCHANGE_OBSERVE_INITIAL,
    WCO_EXCHANGE_OBSERVE_REPORT,
    WCO_EXCHANGE_OBSERVE_INTERVENING,
    WCO_EXCHANGE_CANCELLED
};

struct wco_exchange_message {
    enum wco_exchange_delivery delivery;
    uint8_t type, code;
    uint16_t message_id;
    const uint8_t *token, *payload;
    size_t token_length, payload_length, option_count;
    struct wco_exchange_option options[WCO_EXCHANGE_OPTIONS_MAX];
};

typedef int (*wco_exchange_response_fn)(void *argument,
                                        const struct wco_exchange_message *message);
typedef void (*wco_exchange_failure_fn)(void *argument, const char *code);

struct wco_exchange_callbacks {
    wco_exchange_response_fn response;
    wco_exchange_failure_fn failure;
    void *argument;
};

/* The production implementation is compiled with WCO_WITH_LIBCOAP and pinned
 * public libcoap 4.3.5 headers. Open copies all configuration synchronously;
 * callers can erase credential input immediately after return. The returned
 * error string is finite and contains no peer or credential material. */
const char *wco_exchange_open(const char *host, uint16_t port,
                              const struct wco_oscore_material *material,
                              struct wco_store *store,
                              const struct wco_exchange_callbacks *callbacks,
                              struct wco_exchange **result);

/* Exactly one request may be active. Path is the validated relative-reference
 * form from the command boundary. A present zero-length body remains distinct
 * at admission even though RFC 7252 has no zero-length payload marker. */
const char *wco_exchange_request(struct wco_exchange *exchange,
                                 const char *method, const char *path,
                                 int confirmable, int accept_present,
                                 uint16_t accept, int format_present,
                                 uint16_t format, int body_present,
                                 const uint8_t *body, size_t body_length);
const char *wco_exchange_observe(struct wco_exchange *exchange,
                                 const char *path, int confirmable,
                                 int accept_present, uint16_t accept);
const char *wco_exchange_cancel(struct wco_exchange *exchange);
int wco_exchange_io(struct wco_exchange *exchange);
int wco_exchange_active(const struct wco_exchange *exchange);
void wco_exchange_close(struct wco_exchange *exchange);

#endif
