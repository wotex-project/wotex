/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include "peer.h"
#include "property_peer.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include "bacnet/bacaddr.h"
#include "bacnet/cov.h"
#include "bacnet/npdu.h"
#include "bacnet/basic/npdu/h_npdu.h"
#include "bacnet/basic/object/ao.h"
#include "bacnet/basic/object/device.h"
#include "bacnet/basic/services.h"
#include "bacnet/basic/tsm/tsm.h"
#include "bacnet/datalink/bip.h"
#include "bacnet/datalink/datalink.h"

static struct peer_counters Counters;
static uint32_t Faults[PEER_FAULT_COUNT];
static enum peer_fault Current_Request;
static bool Control_Ack_Generated;
static volatile sig_atomic_t Stopping;

void peer_control_begin(enum peer_fault kind)
{
    Current_Request = kind;
    Control_Ack_Generated = false;
}

void peer_control_end(bool matching)
{
    if (Control_Ack_Generated) {
        if (Current_Request == PEER_FAULT_REGISTER_ACK) {
            peer_increment(&Counters.registrations);
        } else if (Current_Request == PEER_FAULT_RENEW_ACK) {
            peer_increment(&Counters.renewals);
        } else if (Current_Request == PEER_FAULT_CANCEL_ACK && matching) {
            peer_increment(&Counters.cancellations);
        }
    }
    Current_Request = PEER_FAULT_NONE;
}

bool peer_drop_cancel(void)
{
    if (Faults[PEER_FAULT_CANCEL_REQUEST]) {
        --Faults[PEER_FAULT_CANCEL_REQUEST];
        peer_increment(&Counters.dropped_requests);
        return true;
    }
    return false;
}

static uint64_t monotonic_ms(void)
{
    struct timespec time;
    if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) {
        exit(70);
    }
    return (uint64_t)time.tv_sec * 1000 + (uint64_t)time.tv_nsec / 1000000;
}

static void stop_signal(int signal_number)
{
    (void)signal_number;
    Stopping = 1;
}

/* Decode the stack's actual Active_COV_Subscriptions representation. */
static int subscriptions(const BACNET_ADDRESS *source, const BACNET_SUBSCRIBE_COV_DATA *request,
    bool *matching)
{
    uint8_t data[16384];
    int size = handler_cov_encode_subscriptions(data, (int)sizeof(data));
    int offset = 0;
    int count = 0;
    if (size < 0 || size > (int)sizeof(data)) {
        return -1;
    }
    while (offset < size) {
        BACNET_COV_SUBSCRIPTION subscription = {0};
        int used = bacnet_cov_subscription_decode(data + offset, (size_t)(size - offset), &subscription);
        if (used <= 0 || used > size - offset || ++count > 16) {
            return -1;
        }
        if (source && request && matching &&
            subscription.recipient.recipient.tag == BACNET_RECIPIENT_TAG_ADDRESS &&
            bacnet_address_same(source, &subscription.recipient.recipient.type.address) &&
            subscription.recipient.process_identifier == request->subscriberProcessIdentifier &&
            subscription.monitored_property_reference.object_identifier.type == request->monitoredObjectIdentifier.type &&
            subscription.monitored_property_reference.object_identifier.instance == request->monitoredObjectIdentifier.instance) {
            *matching = true;
        }
        offset += used;
    }
    return count;
}

static void read_property(uint8_t *request, uint16_t length, BACNET_ADDRESS *source,
    BACNET_CONFIRMED_SERVICE_DATA *service)
{
    peer_increment(&Counters.reads);
    handler_read_property(request, length, source, service);
}

static void write_property(uint8_t *request, uint16_t length, BACNET_ADDRESS *source,
    BACNET_CONFIRMED_SERVICE_DATA *service)
{
    peer_increment(&Counters.writes);
    handler_write_property(request, length, source, service);
}

static void who_is(uint8_t *request, uint16_t length, BACNET_ADDRESS *source)
{
    peer_increment(&Counters.who_is);
    handler_who_is_unicast(request, length, source);
}

static void subscribe_cov(uint8_t *request, uint16_t length, BACNET_ADDRESS *source,
    BACNET_CONFIRMED_SERVICE_DATA *service)
{
    BACNET_SUBSCRIBE_COV_DATA decoded = {0};
    bool matching = false;
    int decoded_length = cov_subscribe_decode_service_request(request, length, &decoded);
    Current_Request = PEER_FAULT_NONE;
    Control_Ack_Generated = false;
    if (!service->segmented_message && decoded_length > 0 && decoded_length == length) {
        if (subscriptions(source, &decoded, &matching) < 0) {
            exit(71);
        }
        Current_Request = decoded.cancellationRequest ? PEER_FAULT_CANCEL_ACK :
            (matching ? PEER_FAULT_RENEW_ACK : PEER_FAULT_REGISTER_ACK);
        if (decoded.cancellationRequest && peer_drop_cancel()) {
            Current_Request = PEER_FAULT_NONE;
            return;
        }
    }
    handler_cov_subscribe(request, length, source, service);
    peer_control_end(matching);
}

static void notification_ack(BACNET_ADDRESS *source, uint8_t invoke_id)
{
    BACNET_ADDRESS destination = {0};
    BACNET_NPDU_DATA npdu = {0};
    uint8_t apdu[MAX_PDU];
    uint16_t length = 0;
    if (tsm_get_transaction_pdu(invoke_id, &destination, &npdu, apdu, &length) &&
        bacnet_address_same(source, &destination)) {
        peer_increment(&Counters.notification_acks);
        property_peer_ack(source, invoke_id);
    }
}

int __real_bip_send_pdu(BACNET_ADDRESS *, BACNET_NPDU_DATA *, uint8_t *, unsigned);

/* The linker wrapper observes the C stack's encoded output before the UDP send. */
int __wrap_bip_send_pdu(BACNET_ADDRESS *destination, BACNET_NPDU_DATA *npdu,
    uint8_t *pdu, unsigned length)
{
    BACNET_ADDRESS decoded_destination = {0}, source = {0};
    BACNET_NPDU_DATA decoded_npdu = {0};
    int offset = length <= UINT16_MAX ?
        bacnet_npdu_decode(pdu, (uint16_t)length, &decoded_destination, &source, &decoded_npdu) : -1;
    bool notification = false;
    bool control_ack = false;
    if (offset > 0 && (unsigned)offset < length && !decoded_npdu.network_layer_message) {
        uint8_t *apdu = pdu + offset;
        unsigned remaining = length - (unsigned)offset;
        control_ack = remaining == 3 && apdu[0] == PDU_TYPE_SIMPLE_ACK &&
            (apdu[2] == SERVICE_CONFIRMED_SUBSCRIBE_COV ||
             apdu[2] == SERVICE_CONFIRMED_SUBSCRIBE_COV_PROPERTY) &&
            Current_Request != PEER_FAULT_NONE;
        notification = (remaining >= 4 && (apdu[0] & 0xF0) == PDU_TYPE_CONFIRMED_SERVICE_REQUEST &&
            apdu[3] == SERVICE_CONFIRMED_COV_NOTIFICATION) ||
            (remaining >= 2 && apdu[0] == PDU_TYPE_UNCONFIRMED_SERVICE_REQUEST &&
            apdu[1] == SERVICE_UNCONFIRMED_COV_NOTIFICATION);
    }
    if (control_ack) {
        Control_Ack_Generated = true;
        if (Faults[Current_Request]) {
            --Faults[Current_Request];
            peer_increment(&Counters.dropped_acks);
            return (int)length;
        }
    }
    int sent = __real_bip_send_pdu(destination, npdu, pdu, length);
    if (sent > 0) {
        if (notification) {
            peer_increment(&Counters.notifications);
        }
        if (control_ack) {
            peer_increment(&Counters.control_acks);
        }
    } else {
        peer_increment(&Counters.failed_sends);
    }
    return sent;
}

static int snapshot(char *output, size_t capacity, uint32_t nonce)
{
    struct rusage usage;
    int object_count = subscriptions(NULL, NULL, NULL);
    unsigned property_count = property_peer_count();
    if (object_count < 0 || getrusage(RUSAGE_SELF, &usage) != 0) {
        return -1;
    }
    return snprintf(output, capacity,
        "{\"version\":1,\"nonce\":%" PRIu32 ",\"pid\":%ld,\"active_subscribers\":%u,"
        "\"object_subscribers\":%d,\"property_subscribers\":%u,"
        "\"active_invoke_ids\":%u,\"present_value\":%.9g,\"priority\":%u,\"max_rss_kib\":%ld,"
        "\"reads\":%" PRIu64 ",\"writes\":%" PRIu64 ",\"who_is\":%" PRIu64 ","
        "\"registrations\":%" PRIu64 ",\"renewals\":%" PRIu64 ",\"cancellations\":%" PRIu64 ","
        "\"control_acks\":%" PRIu64 ",\"notification_acks\":%" PRIu64 ",\"notifications\":%" PRIu64 ","
        "\"datagrams\":%" PRIu64 ",\"dropped_acks\":%" PRIu64 ",\"dropped_requests\":%" PRIu64 ","
        "\"failed_sends\":%" PRIu64 "}\n",
        nonce, (long)getpid(), (unsigned)object_count + property_count, object_count, property_count,
        (unsigned)(MAX_TSM_TRANSACTIONS - tsm_transaction_idle_count()),
        (double)Analog_Output_Present_Value(1), Analog_Output_Present_Value_Priority(1), usage.ru_maxrss,
        Counters.reads, Counters.writes, Counters.who_is, Counters.registrations, Counters.renewals,
        Counters.cancellations, Counters.control_acks, Counters.notification_acks, Counters.notifications,
        Counters.datagrams, Counters.dropped_acks, Counters.dropped_requests, Counters.failed_sends);
}

static void control_tick(int socket_fd)
{
    for (unsigned index = 0; index < 4; index++) {
        char input[129], output[2048];
        struct sockaddr_in source;
        socklen_t source_length = sizeof(source);
        ssize_t size = recvfrom(socket_fd, input, sizeof(input), MSG_TRUNC,
            (struct sockaddr *)&source, &source_length);
        if (size < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
            return;
        }
        if (size < 0) {
            exit(72);
        }
        struct peer_command command;
        if ((size_t)size > sizeof(input) || !peer_parse(input, (size_t)size, &command)) {
            static const char invalid[] = "{\"error\":\"invalid_control\"}\n";
            if (sendto(socket_fd, invalid, sizeof(invalid) - 1, 0,
                (struct sockaddr *)&source, source_length) < 0) {
                exit(73);
            }
            continue;
        }
        if (command.kind == PEER_FAULT) {
            Faults[command.fault] = command.count;
        }
        int length = snapshot(output, sizeof(output), command.nonce);
        if (length < 0 || (size_t)length >= sizeof(output) ||
            sendto(socket_fd, output, (size_t)length, 0, (struct sockaddr *)&source, source_length) != length) {
            exit(74);
        }
        if (command.kind == PEER_QUIT) {
            Stopping = 1;
            return;
        }
    }
}

static int control_open(uint16_t port)
{
    int socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(port);
    if (socket_fd < 0 || fcntl(socket_fd, F_SETFL, O_NONBLOCK) < 0 ||
        fcntl(socket_fd, F_SETFD, FD_CLOEXEC) < 0 ||
        bind(socket_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        if (socket_fd >= 0) {
            close(socket_fd);
        }
        return -1;
    }
    return socket_fd;
}

int main(int argc, char **argv)
{
    uint32_t protocol_port, control_port, duration;
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        return peer_parser_test();
    }
    if (argc == 2 && strcmp(argv[1], "--property-self-test") == 0) {
        return property_peer_test();
    }
    if (argc != 5 || !argv[1][0] || strlen(argv[1]) > 15 ||
        !peer_uint(argv[2], 1, 65535, &protocol_port) ||
        !peer_uint(argv[3], 1, 65535, &control_port) || protocol_port == control_port ||
        !peer_uint(argv[4], 1000, 600000, &duration)) {
        fputs("usage: wotex-bacnet-peer INTERFACE BACNET_PORT CONTROL_PORT DURATION_MS\n", stderr);
        return 64;
    }
    struct sigaction action = {0};
    action.sa_handler = stop_signal;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL)) {
        return 65;
    }
    int control = control_open((uint16_t)control_port);
    if (control < 0) {
        return 66;
    }
    Device_Init(NULL);
    if (!Device_Set_Object_Instance_Number(123) || Analog_Output_Create(1) != 1) {
        close(control);
        return 67;
    }
    handler_cov_init();
    apdu_timeout_set(200);
    apdu_retries_set(2);
    apdu_set_unrecognized_service_handler_handler(handler_unrecognized_service);
    apdu_set_confirmed_handler(SERVICE_CONFIRMED_READ_PROPERTY, read_property);
    apdu_set_confirmed_handler(SERVICE_CONFIRMED_WRITE_PROPERTY, write_property);
    apdu_set_confirmed_handler(SERVICE_CONFIRMED_SUBSCRIBE_COV, subscribe_cov);
    apdu_set_confirmed_handler(SERVICE_CONFIRMED_SUBSCRIBE_COV_PROPERTY, property_peer_subscribe);
    apdu_set_unconfirmed_handler(SERVICE_UNCONFIRMED_WHO_IS, who_is);
    apdu_set_confirmed_simple_ack_handler(SERVICE_CONFIRMED_COV_NOTIFICATION, notification_ack);
    bip_set_port((uint16_t)protocol_port);
    if (!bip_init(argv[1])) {
        close(control);
        return 68;
    }
    uint64_t started = monotonic_ms(), last_tick = started, last_second = started;
    printf("{\"ready\":true,\"pid\":%ld,\"device_instance\":123}\n", (long)getpid());
    fflush(stdout);
    while (!Stopping && monotonic_ms() - started < duration) {
        BACNET_ADDRESS source = {0};
        uint8_t pdu[MAX_MPDU];
        control_tick(control);
        uint16_t length = bip_receive(&source, pdu, sizeof(pdu), 5);
        if (length) {
            peer_increment(&Counters.datagrams);
            npdu_handler(&source, pdu, length);
        }
        uint64_t now = monotonic_ms();
        uint64_t elapsed = now - last_tick;
        while (elapsed) {
            uint16_t step = elapsed > UINT16_MAX ? UINT16_MAX : (uint16_t)elapsed;
            tsm_timer_milliseconds(step);
            elapsed -= step;
        }
        last_tick = now;
        uint64_t seconds = (now - last_second) / 1000;
        if (seconds) {
            handler_cov_timer_seconds((uint32_t)seconds);
            last_second += seconds * 1000;
        }
        for (unsigned index = 0; index < 5; index++) {
            handler_cov_task();
        }
        property_peer_tick(now);
    }
    property_peer_close();
    handler_cov_init();
    for (unsigned index = 1; index <= UINT8_MAX; index++) {
        tsm_free_invoke_id((uint8_t)index);
    }
    bip_cleanup();
    close(control);
    Analog_Output_Cleanup();
    puts("{\"closed\":true}");
    return Stopping ? 0 : 75;
}
