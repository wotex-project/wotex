/* SPDX-License-Identifier: Apache-2.0
 * Public OSCORE session admission against raw UDP response faults and a real
 * same-stack protected peer. The direct SDK fixture has no production store.
 */
#define _POSIX_C_SOURCE 200809L
#include <coap3/coap.h>
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static unsigned deliveries, failures, server_requests, resets;
static const char client_conf[] =
    "master_secret,hex,0102030405060708090a0b0c0d0e0f10\n"
    "sender_id,hex,00\nrecipient_id,hex,01\n"
    "rfc8613_b_1_2,bool,false\nrfc8613_b_2,bool,false\n";
static const char server_conf[] =
    "master_secret,hex,0102030405060708090a0b0c0d0e0f10\n"
    "sender_id,hex,01\nrecipient_id,hex,00\n"
    "rfc8613_b_1_2,bool,false\nrfc8613_b_2,bool,false\n";

static int64_t now_ms(void) {
    struct timespec value; assert(clock_gettime(CLOCK_MONOTONIC, &value) == 0);
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}

static int saved(uint64_t sequence, void *argument) { (void)sequence; (void)argument; return 1; }

static coap_response_t received(coap_session_t *session, const coap_pdu_t *sent,
                                 const coap_pdu_t *reply, coap_mid_t mid) {
    const uint8_t *bytes; size_t length;
    (void)session; (void)sent; (void)mid;
    assert(coap_get_data(reply, &length, &bytes));
    assert((length == 6 && !memcmp(bytes, "forged", 6)) ||
           (length == 9 && !memcmp(bytes, "protected", 9)));
    deliveries++;
    return COAP_RESPONSE_OK;
}

static int event(coap_session_t *session, coap_event_t kind) {
    (void)session;
    if (kind == COAP_EVENT_OSCORE_NO_PROTECTED_PAYLOAD) failures++;
    return 0;
}

static void nack(coap_session_t *session, const coap_pdu_t *sent,
                 coap_nack_reason_t reason, coap_mid_t mid) {
    (void)session; (void)sent; (void)mid;
    assert(reason == COAP_NACK_RST);
    resets++;
}

static coap_session_t *client(coap_context_t **context, const struct sockaddr_in *address, int secure) {
    coap_address_t peer; coap_session_t *session;
    deliveries = failures = resets = 0;
    *context = coap_new_context(NULL); assert(*context);
    coap_context_set_block_mode(*context, COAP_BLOCK_USE_LIBCOAP | COAP_BLOCK_SINGLE_BODY);
    coap_context_set_max_token_size(*context, 8);
    coap_register_response_handler(*context, received); coap_register_event_handler(*context, event);
    coap_register_nack_handler(*context, nack);
    coap_address_init(&peer); peer.addr.sin = *address; peer.size = sizeof(*address);
    if (secure) {
        coap_oscore_conf_t *config = coap_new_oscore_conf(
            (coap_str_const_t){sizeof(client_conf) - 1, (const uint8_t *)client_conf}, saved, NULL, 0);
        assert(config);
        session = coap_new_client_session_oscore(*context, NULL, &peer, COAP_PROTO_UDP, config);
    } else session = coap_new_client_session(*context, NULL, &peer, COAP_PROTO_UDP);
    assert(session); return session;
}

static void send_request(coap_session_t *session, coap_pdu_code_t method) {
    uint8_t token[8]; size_t length = sizeof(token);
    coap_pdu_t *pdu = coap_pdu_init(COAP_MESSAGE_CON, method, coap_new_message_id(session), 1152);
    coap_session_new_token(session, &length, token);
    assert(pdu && coap_add_token(pdu, length, token));
    assert(coap_add_option(pdu, COAP_OPTION_URI_PATH, 5, (const uint8_t *)"value"));
    assert(coap_send(session, pdu) != COAP_INVALID_MID);
}

static void plain_fault(unsigned variant, coap_pdu_code_t method, int secure) {
    struct sockaddr_in address = {.sin_family = AF_INET}; socklen_t address_length = sizeof(address);
    struct sockaddr_storage source; socklen_t source_length = sizeof(source);
    int peer = socket(AF_INET, SOCK_DGRAM, 0); coap_context_t *context; coap_session_t *session;
    uint8_t request[1152], reply[32]; ssize_t count = -1; size_t token, size; int64_t deadline;
    assert(peer >= 0 && inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1);
    assert(bind(peer, (struct sockaddr *)&address, sizeof(address)) == 0);
    assert(getsockname(peer, (struct sockaddr *)&address, &address_length) == 0);
    assert(fcntl(peer, F_SETFL, O_NONBLOCK) == 0);
    session = client(&context, &address, secure); send_request(session, method);
    deadline = now_ms() + 1000;
    while (count < 0 && now_ms() < deadline) {
        assert(coap_io_process(context, 1) >= 0);
        count = recvfrom(peer, request, sizeof(request), 0, (struct sockaddr *)&source, &source_length);
        if (count < 0) assert(errno == EAGAIN || errno == EWOULDBLOCK);
    }
    assert(count >= 4); token = request[0] & 15u; assert(token <= 8 && (size_t)count >= 4 + token);
    if (variant == 5) {
        uint8_t reset[] = {0x70, 0, request[2], request[3]};
        assert(sendto(peer, reset, sizeof(reset), 0, (struct sockaddr *)&source, source_length) == 4);
        deadline = now_ms() + 1000;
        while (!resets && now_ms() < deadline) assert(coap_io_process(context, 1) >= 0);
        assert(resets == 1 && deliveries == 0 && failures == 0);
        coap_session_release(session); coap_free_context(context); assert(close(peer) == 0);
        return;
    }
    if (variant == 4) {
        uint8_t ack[] = {0x60, 0, request[2], request[3]};
        assert(sendto(peer, ack, sizeof(ack), 0, (struct sockaddr *)&source, source_length) == 4);
        assert(coap_io_process(context, 10) >= 0);
        assert(deliveries == 0 && failures == 0); /* Empty ACK is only transport progress. */
    }
    reply[0] = (uint8_t)((variant == 1 || variant == 4 ? 0x50 : variant == 2 || variant == 6 ? 0x40 : 0x60) | token);
    reply[1] = variant == 3 ? 129 : 69;
    reply[2] = variant == 0 || variant == 3 ? request[2] : 0x71;
    reply[3] = variant == 0 || variant == 3 ? request[3] : 0x27;
    memcpy(reply + 4, request + 4, token); size = 4 + token;
    if (variant == 6) reply[4] ^= 0xff; /* A token no pending request used. */
    reply[size++] = 0xff; memcpy(reply + size, "forged", 6); size += 6;
    assert(sendto(peer, reply, size, 0, (struct sockaddr *)&source, source_length) == (ssize_t)size);
    deadline = now_ms() + 1000;
    while (!deliveries && !failures && now_ms() < deadline) assert(coap_io_process(context, 1) >= 0);
    if (variant == 6) assert(deliveries == 0 && failures == 0);
    else if (secure) assert(deliveries == 0 && failures == 1);
    else assert(deliveries == 1 && failures == 0);
    coap_session_release(session); coap_free_context(context); assert(close(peer) == 0);
}

static void protected_resource(coap_resource_t *resource, coap_session_t *session,
                                 const coap_pdu_t *request, const coap_string_t *query,
                                 coap_pdu_t *reply) {
    (void)resource; (void)session; (void)request; (void)query;
    server_requests++; coap_pdu_set_code(reply, COAP_RESPONSE_CODE_CONTENT);
    assert(coap_add_data(reply, 9, (const uint8_t *)"protected"));
}

static void protected_peer(void) {
    coap_context_t *server = coap_new_context(NULL), *context; coap_address_t bind;
    coap_endpoint_t *endpoint; coap_session_t *session; coap_resource_t *resource;
    struct sockaddr_in address = {.sin_family = AF_INET}; unsigned port; int64_t deadline;
    coap_oscore_conf_t *config = coap_new_oscore_conf(
        (coap_str_const_t){sizeof(server_conf) - 1, (const uint8_t *)server_conf}, saved, NULL, 0);
    assert(server && config && coap_context_oscore_server(server, config));
    coap_address_init(&bind); bind.addr.sin.sin_family = AF_INET;
    assert(inet_pton(AF_INET, "127.0.0.1", &bind.addr.sin.sin_addr) == 1);
    bind.size = sizeof(bind.addr.sin);
    endpoint = coap_new_endpoint(server, &bind, COAP_PROTO_UDP); assert(endpoint);
    /* The pinned public formatter reports the kernel-selected bound port. */
    assert(sscanf(coap_endpoint_str(endpoint), "127.0.0.1:%u UDP", &port) == 1 && port && port <= 65535);
    address.sin_port = htons((uint16_t)port); address.sin_addr = bind.addr.sin.sin_addr;
    resource = coap_resource_init(coap_make_str_const("value"), COAP_RESOURCE_FLAGS_OSCORE_ONLY); assert(resource);
    coap_register_handler(resource, COAP_REQUEST_GET, protected_resource); coap_add_resource(server, resource);
    server_requests = 0; session = client(&context, &address, 1); send_request(session, COAP_REQUEST_CODE_GET);
    deadline = now_ms() + 1000;
    while (!deliveries && now_ms() < deadline) {
        assert(coap_io_process(server, 1) >= 0); assert(coap_io_process(context, 1) >= 0);
    }
    assert(server_requests == 1 && deliveries == 1 && failures == 0);
    coap_session_release(session); coap_free_context(context); coap_free_context(server);
}

int main(int argc, char **argv) {
    assert(argc == 1 || (argc == 2 && !strcmp(argv[1], "--positive-only")));
    coap_startup(); coap_set_log_level(COAP_LOG_EMERG);
    if (argc == 1) {
        for (unsigned variant = 0; variant < 5; variant++) {
            plain_fault(variant, COAP_REQUEST_CODE_GET, 1);
            plain_fault(variant, COAP_REQUEST_CODE_POST, 1);
            plain_fault(variant, COAP_REQUEST_CODE_PUT, 1);
        }
        puts("WCO-S06 WCO-N02: 15 plaintext ACK/NON/CON/error/separate responses yield no OSCORE application value");
    }
    plain_fault(0, COAP_REQUEST_CODE_GET, 0);
    plain_fault(5, COAP_REQUEST_CODE_GET, 1);
    plain_fault(6, COAP_REQUEST_CODE_GET, 1);
    protected_peer();
    puts("WCO-S06 WCO-N02: a plaintext response with an unused token raises no protection failure");
    puts("WCO-S06 WCO-N02: plain UDP, empty RST and actual protected OSCORE same-stack controls succeed");
    coap_cleanup(); return 0;
}
