#include <modbus/modbus.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;

static void stop_requested(int signal_number) {
    (void)signal_number;
    stopping = 1;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        puts(LIBMODBUS_VERSION_STRING);
        return 0;
    }
    if (argc != 1) return 64;

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_requested;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL)) return 1;
    signal(SIGPIPE, SIG_IGN);

    int result = 1;
    int listener = -1;
    int connected = 0;
    unsigned long connections = 0;
    unsigned long requests = 0;
    modbus_mapping_t *map = NULL;
    modbus_t *ctx = modbus_new_tcp("0.0.0.0", 1502);
    if (!ctx) goto cleanup;
    if (modbus_set_slave(ctx, 1) < 0 ||
        modbus_set_indication_timeout(ctx, 0, 500000) < 0 ||
        modbus_set_byte_timeout(ctx, 0, 100000) < 0) goto cleanup;
    map = modbus_mapping_new(2000, 2000, 200, 200);
    if (!map) goto cleanup;
    map->tab_registers[0] = 42;
    map->tab_input_registers[0] = 77;
    map->tab_input_bits[0] = 1;
    listener = modbus_tcp_listen(ctx, 64);
    if (listener < 0) goto cleanup;
    puts("{\"event\":\"ready\",\"port\":1502}");
    fflush(stdout);

    while (!stopping) {
        struct pollfd ready = {.fd = listener, .events = POLLIN, .revents = 0};
        int available = poll(&ready, 1, 100);
        if (available < 0 && errno == EINTR) continue;
        if (available < 0) goto cleanup;
        if (available == 0) continue;
        if (modbus_tcp_accept(ctx, &listener) < 0) {
            if (errno == EINTR) continue;
            goto cleanup;
        }
        connected = 1;
        connections++;
        uint8_t request[MODBUS_TCP_MAX_ADU_LENGTH];
        while (!stopping) {
            int count = modbus_receive(ctx, request);
            if (count <= 0) break;
            if (count < 8) goto cleanup;
            requests++;
            printf("{\"event\":\"request\",\"function\":%u,\"unit\":%u,\"transaction\":%u}\n",
                   (unsigned)request[7], (unsigned)request[6],
                   (unsigned)(((uint16_t)request[0] << 8) | request[1]));
            fflush(stdout);
            if (modbus_reply(ctx, request, count, map) < 0) break;
        }
        modbus_close(ctx);
        connected = 0;
    }
    result = 0;

cleanup:
    if (connected) modbus_close(ctx);
    connected = 0;
    if (listener >= 0 && close(listener) != 0) result = 1;
    listener = -1;
    if (map) modbus_mapping_free(map);
    map = NULL;
    if (ctx) modbus_free(ctx);
    ctx = NULL;
    printf("{\"event\":\"cleanup\",\"open_sockets\":%d,\"contexts\":%d,\"mappings\":%d,"
           "\"connections\":%lu,\"requests\":%lu,\"result\":%d}\n",
           connected + (listener >= 0), ctx != NULL, map != NULL, connections, requests, result);
    fflush(stdout);
    return result;
}
