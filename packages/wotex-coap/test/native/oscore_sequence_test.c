/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <coap3/coap.h>

/* WCO-N04/WCO-S06: persistence failure cannot encrypt or transmit a PDU.
 * Only public libcoap APIs are used. This exercises the actual native send path,
 * not a model of its sequence callback. Key material is an RFC8613 test value. */
struct reservation {
    int permit;
    unsigned calls;
    uint64_t saved;
};

static int reserve(uint64_t boundary, void *argument) {
    struct reservation *state = argument;
    state->calls++;
    if (!state->permit) return 0;
    assert(boundary > state->saved);
    state->saved = boundary;
    return 1;
}

static void run(int permit) {
    static const char config[] =
        "master_secret,hex,0102030405060708090a0b0c0d0e0f10\n"
        "master_salt,hex,9e7ca92223786340\n"
        "sender_id,hex,00\nrecipient_id,hex,01\n"
        "aead_alg,integer,10\nhkdf_alg,integer,-10\n"
        "ssn_freq,integer,32\nrfc8613_b_1_2,bool,false\n"
        "rfc8613_b_2,bool,false\n";
    struct reservation reservation = {permit, 0, 0};
    struct sockaddr_in endpoint;
    socklen_t length = sizeof(endpoint);
    coap_address_t address;
    coap_context_t *context;
    coap_oscore_conf_t *security;
    coap_session_t *session;
    int peer = socket(AF_INET, SOCK_DGRAM, 0);
    assert(peer >= 0);
    memset(&endpoint, 0, sizeof(endpoint));
    endpoint.sin_family = AF_INET;
    assert(inet_pton(AF_INET, "127.0.0.1", &endpoint.sin_addr) == 1);
    assert(bind(peer, (struct sockaddr *)&endpoint, sizeof(endpoint)) == 0);
    assert(getsockname(peer, (struct sockaddr *)&endpoint, &length) == 0);
    assert(fcntl(peer, F_SETFL, O_NONBLOCK) == 0);
    coap_address_init(&address);
    address.addr.sin = endpoint;
    address.size = sizeof(endpoint);
    context = coap_new_context(NULL);
    assert(context);
    security = coap_new_oscore_conf((coap_str_const_t){sizeof(config) - 1, (const uint8_t *)config},
                                   reserve, &reservation, 0);
    assert(security);
    session = coap_new_client_session_oscore(context, NULL, &address, COAP_PROTO_UDP, security);
    assert(session);
    for (unsigned attempt = 0; attempt < 3; attempt++) {
        coap_pdu_t *pdu = coap_pdu_init(COAP_MESSAGE_NON, COAP_REQUEST_CODE_GET,
                                      coap_new_message_id(session), 1152);
        uint8_t token = (uint8_t)attempt;
        uint8_t bytes[1152];
        ssize_t received;
        coap_mid_t sent;
        assert(pdu);
        assert(coap_add_token(pdu, 1, &token));
        assert(coap_add_option(pdu, COAP_OPTION_URI_PATH, 5, (const uint8_t *)"value"));
        sent = coap_send(session, pdu);
        (void)coap_io_process(context, 5);
        received = recv(peer, bytes, sizeof(bytes), 0);
        if (permit) {
            coap_opt_iterator_t options;
            assert(sent != COAP_INVALID_MID);
            assert(received > 0);
            pdu = coap_pdu_init(COAP_MESSAGE_NON, COAP_EMPTY_CODE, 0, 1152);
            assert(pdu && coap_pdu_parse(COAP_PROTO_UDP, bytes, (size_t)received, pdu));
            assert(coap_check_option(pdu, COAP_OPTION_OSCORE, &options));
            coap_delete_pdu(pdu);
            assert(reservation.saved >= attempt + 1);
        } else {
            assert(sent == COAP_INVALID_MID);
            assert(received == -1 && (errno == EAGAIN || errno == EWOULDBLOCK));
            assert(reservation.calls == attempt + 1);
            assert(reservation.saved == 0);
        }
    }
    if (permit) assert(reservation.calls == 1 && reservation.saved == 32);
    coap_session_release(session);
    coap_free_context(context);
    assert(close(peer) == 0);
}

int main(void) {
    coap_startup();
    coap_set_log_level(COAP_LOG_EMERG);
    assert(coap_oscore_is_supported());
    run(0);
    run(1);
    coap_cleanup();
    puts("WCO-N04 WCO-S06: rejected reservations send zero PDUs; durable allowance bounds three sends");
    return 0;
}
