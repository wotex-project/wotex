/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1
#define _DEFAULT_SOURCE 1
#include "store.h"
#include <coap3/coap.h>
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int save(uint64_t boundary, void *store) {
    return wco_store_reserve(store, boundary) == WCO_STORE_OK;
}

static void run(int fault) {
    static const uint8_t secret[] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
    static const uint8_t salt[] = {0x9e,0x7c,0xa9,0x22,0x23,0x78,0x63,0x40};
    static const uint8_t sender = 0, recipient = 1;
    static const char config[] =
        "master_secret,hex,0102030405060708090a0b0c0d0e0f10\n"
        "master_salt,hex,9e7ca92223786340\n"
        "sender_id,hex,00\nrecipient_id,hex,01\n"
        "aead_alg,integer,10\nhkdf_alg,integer,-10\n"
        "ssn_freq,integer,32\nrfc8613_b_1_2,bool,false\nrfc8613_b_2,bool,false\n";
    const struct wco_oscore_material material = {
        .secret = {secret, sizeof(secret)}, .salt = {salt, sizeof(salt)},
        .sender = {&sender, 1}, .recipient = {&recipient, 1}
    };
    struct wco_oscore_identity identity;
    struct wco_store *store, *reopened;
    struct sockaddr_in endpoint = {.sin_family = AF_INET};
    socklen_t length = sizeof(endpoint);
    coap_address_t address;
    coap_context_t *context;
    coap_oscore_conf_t *security;
    coap_session_t *session;
    char template[] = "/tmp/wotex-coap-store-send-XXXXXX", *dir, file[4096];
    int peer = socket(AF_INET, SOCK_DGRAM, 0);
    assert(peer >= 0 && mkdtemp(template));
    dir = realpath(template, NULL);
    assert(dir && wco_oscore_identity(&material, &identity));
    assert(wco_store_open(dir, &identity, 1, &store) == WCO_STORE_OK);
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
                                    save, store, 0);
    assert(security);
    session = coap_new_client_session_oscore(context, NULL, &address, COAP_PROTO_UDP, security);
    assert(session);
    wco_store_test_fault((enum wco_store_step)fault, 0);
    for (unsigned attempt = 0; attempt < 3; attempt++) {
        coap_pdu_t *pdu = coap_pdu_init(COAP_MESSAGE_NON, COAP_REQUEST_CODE_GET,
                                       coap_new_message_id(session), 1152);
        uint8_t token = (uint8_t)attempt, bytes[1152];
        ssize_t received;
        coap_mid_t sent;
        assert(pdu && coap_add_token(pdu, 1, &token));
        sent = coap_send(session, pdu);
        (void)coap_io_process(context, 5);
        received = recv(peer, bytes, sizeof(bytes), 0);
        if (fault) {
            assert(sent == COAP_INVALID_MID);
            assert(received == -1 && (errno == EAGAIN || errno == EWOULDBLOCK));
            assert(wco_store_boundary(store) == 1);
        } else {
            coap_opt_iterator_t options;
            assert(sent != COAP_INVALID_MID && received > 0);
            pdu = coap_pdu_init(COAP_MESSAGE_NON, COAP_EMPTY_CODE, 0, 1152);
            assert(pdu && coap_pdu_parse(COAP_PROTO_UDP, bytes, (size_t)received, pdu));
            assert(coap_check_option(pdu, COAP_OPTION_OSCORE, &options));
            coap_delete_pdu(pdu);
            assert(wco_store_boundary(store) == 32);
        }
    }
    wco_store_test_fault(0, 0);
    coap_session_release(session);
    coap_free_context(context);
    assert(close(peer) == 0);
    wco_store_close(store);
    assert(wco_store_open(dir, &identity, 1, &reopened) == WCO_STORE_FRESH_REQUIRED && !reopened);
    assert(snprintf(file, sizeof(file), "%s/contexts.v1", dir) > 0 && unlink(file) == 0);
    assert(snprintf(file, sizeof(file), "%s/context.lock", dir) > 0 && unlink(file) == 0);
    assert(rmdir(dir) == 0);
    free(dir);
}

int main(void) {
    coap_startup();
    coap_set_log_level(COAP_LOG_EMERG);
    for (int fault = 0; fault <= WCO_STORE_DIRECTORY_SYNC; fault++) run(fault);
    coap_cleanup();
    puts("WCO-N04 WCO-V14: five durable-write failures block actual libcoap sends and unsafe reopen");
    puts("WCO-N04 WCO-S06: persisted allowance permits three protected datagrams");
    return 0;
}
