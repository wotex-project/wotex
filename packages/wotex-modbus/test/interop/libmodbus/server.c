#include <modbus/modbus.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    modbus_t *ctx = modbus_new_tcp("0.0.0.0", 1502);
    if (!ctx || modbus_set_slave(ctx, 1) < 0) return 1;
    modbus_mapping_t *map = modbus_mapping_new(2000, 2000, 200, 200);
    if (!map) return 2;
    map->tab_registers[0] = 42;
    map->tab_input_registers[0] = 77;
    map->tab_input_bits[0] = 1;
    int listener = modbus_tcp_listen(ctx, 4);
    if (listener < 0) return 3;
    for (;;) {
        if (modbus_tcp_accept(ctx, &listener) < 0) return 4;
        uint8_t request[MODBUS_TCP_MAX_ADU_LENGTH];
        int count;
        while ((count = modbus_receive(ctx, request)) > 0) {
            if (modbus_reply(ctx, request, count, map) < 0) break;
        }
        modbus_close(ctx);
    }
}
