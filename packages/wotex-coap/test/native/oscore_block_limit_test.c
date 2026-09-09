/* SPDX-License-Identifier: Apache-2.0
 * Public libcoap client APIs with a raw UDP fault peer. This is a block engine
 * regression, not independent OSCORE interoperability. Linux --wrap probes
 * record requested public binary allocation sizes without changing SDK source.
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

#define BODY_LIMIT 1048576u
struct probe { unsigned complete, rejected, requests, restarts; size_t length, maximum_allocation; };
static struct probe *current;

#ifdef WCO_ALLOCATION_WRAP
coap_binary_t *__real_coap_new_binary(size_t size);
coap_binary_t *__real_coap_resize_binary(coap_binary_t *value, size_t size);
coap_binary_t *__wrap_coap_new_binary(size_t size) {
    if (current && size > current->maximum_allocation) current->maximum_allocation = size;
    return __real_coap_new_binary(size);
}
coap_binary_t *__wrap_coap_resize_binary(coap_binary_t *value, size_t size) {
    if (current && size > current->maximum_allocation) current->maximum_allocation = size;
    return __real_coap_resize_binary(value, size);
}
#endif

static int64_t now_ms(void) {
    struct timespec value; assert(clock_gettime(CLOCK_MONOTONIC, &value) == 0);
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}

static coap_response_t response(coap_session_t *session, const coap_pdu_t *sent,
                                 const coap_pdu_t *received, coap_mid_t mid) {
    const uint8_t *bytes; size_t length, offset, total; coap_block_b_t block;
    (void)sent; (void)mid;
    assert(coap_get_data_large(received, &length, &bytes, &offset, &total));
    if (offset || length != total || total > BODY_LIMIT ||
        (coap_get_block_b(session, received, COAP_OPTION_BLOCK2, &block) && (block.num || block.m))) {
        current->rejected++;
        return COAP_RESPONSE_FAIL;
    }
    for (size_t index = 0; index < length; index++) assert(bytes[index] == (uint8_t)(index % 251));
    current->complete++; current->length = length;
    return COAP_RESPONSE_OK;
}

static size_t uint_bytes(uint32_t value, uint8_t *result) {
    uint8_t bytes[4]; size_t length = 0;
    while (value) { bytes[length++] = (uint8_t)value; value >>= 8; }
    for (size_t index = 0; index < length; index++) result[index] = bytes[length - index - 1];
    return length;
}

static void reply(int peer, const struct sockaddr *destination, socklen_t destination_length,
                    const uint8_t *request, size_t request_length, unsigned block_number,
                    int more, unsigned szx, uint32_t estimate, int size_present, int etag) {
    uint8_t bytes[1200], encoded[4]; size_t token = request[0] & 15u, used, length;
    assert(token <= 8 && request_length >= 4 + token);
    bytes[0] = (uint8_t)(0x60 | token); bytes[1] = 69;
    bytes[2] = request[2]; bytes[3] = request[3]; memcpy(bytes + 4, request + 4, token);
    used = 4 + token;
    bytes[used++] = 0x41; bytes[used++] = (uint8_t)etag;
    length = uint_bytes((block_number << 4) | (more ? 8u : 0u) | szx, encoded);
    bytes[used++] = (uint8_t)(0xd0 | length); bytes[used++] = 6; /* ETag 4 -> Block2 23 */
    memcpy(bytes + used, encoded, length); used += length;
    if (size_present) {
        length = uint_bytes(estimate, encoded); bytes[used++] = (uint8_t)(0x50 | length);
        memcpy(bytes + used, encoded, length); used += length;
    }
    bytes[used++] = 0xff;
    length = (size_t)1 << (szx + 4);
    for (size_t index = 0; index < length; index++)
        bytes[used++] = (uint8_t)((block_number * length + index) % 251);
    assert(sendto(peer, bytes, used, 0, destination, destination_length) == (ssize_t)used);
}

static void run(unsigned scenario, coap_pdu_code_t method) {
    struct sockaddr_in address = {.sin_family = AF_INET}; socklen_t address_length = sizeof(address);
    int peer = socket(AF_INET, SOCK_DGRAM, 0); coap_address_t destination;
    coap_context_t *context; coap_session_t *session; coap_pdu_t *pdu;
    uint8_t token[8]; size_t token_length = sizeof(token); int64_t deadline;
    struct probe probe = {0}; current = &probe;
    assert(peer >= 0 && inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1);
    assert(bind(peer, (struct sockaddr *)&address, sizeof(address)) == 0);
    assert(getsockname(peer, (struct sockaddr *)&address, &address_length) == 0);
    assert(fcntl(peer, F_SETFL, O_NONBLOCK) == 0);
    coap_address_init(&destination); destination.addr.sin = address; destination.size = sizeof(address);
    context = coap_new_context(NULL); assert(context);
    coap_context_set_block_mode(context, COAP_BLOCK_USE_LIBCOAP | COAP_BLOCK_SINGLE_BODY);
    coap_context_set_max_token_size(context, 8);
    coap_register_response_handler(context, response);
    session = coap_new_client_session(context, NULL, &destination, COAP_PROTO_UDP); assert(session);
    coap_session_new_token(session, &token_length, token);
    pdu = coap_pdu_init(COAP_MESSAGE_CON, method, coap_new_message_id(session), 1152);
    assert(pdu && coap_add_token(pdu, token_length, token));
    assert(coap_add_option(pdu, COAP_OPTION_URI_PATH, 7, (const uint8_t *)"counter"));
    if (method != COAP_REQUEST_CODE_GET) assert(coap_add_data(pdu, 8, (const uint8_t *)"mutation"));
    assert(coap_send(session, pdu) != COAP_INVALID_MID);
    deadline = now_ms() + 10000;
    while (now_ms() < deadline && !probe.complete && !probe.rejected && !probe.restarts) {
        uint8_t received[1200]; struct sockaddr_storage source; socklen_t source_length = sizeof(source);
        ssize_t count;
        assert(coap_io_process(context, 1) >= 0);
        count = recvfrom(peer, received, sizeof(received), 0, (struct sockaddr *)&source, &source_length);
        if (count < 0) { assert(errno == EAGAIN || errno == EWOULDBLOCK); continue; }
        if (count < 4 || (received[1] == 0)) continue; /* ACK/RST are not application requests. */
        pdu = coap_pdu_init(COAP_MESSAGE_CON, COAP_EMPTY_CODE, 0, 1152); assert(pdu);
        assert(coap_pdu_parse(COAP_PROTO_UDP, received, (size_t)count, pdu));
        coap_block_b_t block; unsigned number = 0;
        if (coap_get_block_b(session, pdu, COAP_OPTION_BLOCK2, &block)) number = block.num;
        assert(coap_pdu_get_code(pdu) == method);
        if (probe.requests && number == 0) probe.restarts++;
        probe.requests++;
        if (scenario == 1) assert(probe.requests == 1);
        coap_delete_pdu(pdu);
        if (probe.restarts) break;
        if (scenario == 1) reply(peer, (struct sockaddr *)&source, source_length, received, (size_t)count, 0, 1, 0, BODY_LIMIT + 1, 1, 1);
        else if (scenario == 4) reply(peer, (struct sockaddr *)&source, source_length, received, (size_t)count, number, 1, 0, number ? BODY_LIMIT + 1 : 32, 1, 1);
        else if (scenario == 6) reply(peer, (struct sockaddr *)&source, source_length, received, (size_t)count, number, 1, 0, 64, 1, number ? 2 : 1);
        else {
            unsigned last = scenario == 0 || scenario == 5 ? 1023 : 1024;
            uint32_t estimate = scenario == 3 || scenario == 5 ? 16 : BODY_LIMIT;
            reply(peer, (struct sockaddr *)&source, source_length, received, (size_t)count, number,
                  number < last, 6, estimate, scenario != 2, 1);
        }
    }
    assert(probe.restarts == 0);
    if (scenario == 0 || scenario == 5) assert(probe.complete == 1 && probe.length == BODY_LIMIT && probe.rejected == 0);
    else assert(probe.complete == 0 && probe.rejected == 1);
    if (scenario == 1) assert(probe.requests == 1);
    if (scenario == 4 || scenario == 6) assert(probe.requests == 2);
#ifdef WCO_ALLOCATION_WRAP
    assert(probe.maximum_allocation <= BODY_LIMIT);
#endif
    coap_session_release(session); coap_free_context(context); assert(close(peer) == 0);
    current = NULL;
}

int main(int argc, char **argv) {
    assert(argc == 1 || (argc == 2 && (!strcmp(argv[1], "--size-only") || !strcmp(argv[1], "--representation-only"))));
    coap_startup(); coap_set_log_level(COAP_LOG_EMERG);
    if (argc == 2) {
        if (!strcmp(argv[1], "--size-only")) run(1, COAP_REQUEST_CODE_GET);
        else run(6, COAP_REQUEST_CODE_POST);
        coap_cleanup();
        return 0;
    }
    for (unsigned scenario = 0; scenario <= 5; scenario++) run(scenario, COAP_REQUEST_CODE_GET);
    puts("WCO-N03 WCO-S02: exact 1-MiB, oversized/absent/understated/changed Size2 and cumulative body bounds");
    run(6, COAP_REQUEST_CODE_GET); run(6, COAP_REQUEST_CODE_POST); run(6, COAP_REQUEST_CODE_PUT);
    puts("WCO-N03 WCO-S02: changed ETag never restarts GET, dispatched POST or dispatched PUT");
#ifdef WCO_ALLOCATION_WRAP
    puts("WCO-N03: actual public binary allocation requests never exceed 1 MiB");
#endif
    coap_cleanup();
    return 0;
}
