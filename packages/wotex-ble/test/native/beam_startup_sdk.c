/* SPDX-License-Identifier: Apache-2.0
 * Deterministic process fixture for the BEAM-owned native startup boundary.
 */
#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_line(char *line, size_t capacity) {
    size_t length;
    if (!fgets(line, (int)capacity, stdin)) return 0;
    length = strlen(line);
    return length > 0 && line[length - 1] == '\n';
}

static int string_field(const char *line, const char *name, char *output, size_t capacity) {
    char prefix[128];
    const char *value;
    const char *end;
    int length = snprintf(prefix, sizeof(prefix), "\"%s\":\"", name);
    if (length < 0 || (size_t)length >= sizeof(prefix)) return 0;
    value = strstr(line, prefix);
    if (!value) return 0;
    value += strlen(prefix);
    end = strchr(value, '"');
    if (!end || (size_t)(end - value) + 1 > capacity) return 0;
    memcpy(output, value, (size_t)(end - value));
    output[end - value] = '\0';
    return 1;
}

static int generation(const char *line, char output[33]) {
    if (!string_field(line, "session_generation", output, 33) || strlen(output) != 32) return 0;
    for (size_t index = 0; index < 32; ++index)
        if (!isdigit((unsigned char)output[index]) &&
            !(output[index] >= 'a' && output[index] <= 'f')) return 0;
    return 1;
}

static int unsigned_field(const char *line, const char *name, size_t expected) {
    char field[128];
    int length = snprintf(field, sizeof(field), "\"%s\":%zu", name, expected);
    return length > 0 && (size_t)length < sizeof(field) && strstr(line, field);
}

static int write_line(const char *line) {
    return puts(line) >= 0 && fflush(stdout) == 0;
}

static int mark_started(const char *executable) {
    char path[PATH_MAX];
    FILE *marker;
    int length = snprintf(path, sizeof(path), "%s.started", executable);
    if (length < 0 || (size_t)length >= sizeof(path)) return 0;
    marker = fopen(path, "wb");
    if (!marker) return 0;
    if (fputs("started\n", marker) < 0 || fclose(marker) != 0) return 0;
    return 1;
}

int main(int argc, char **argv) {
    char line[8192];
    char session[33];
    if (argc != 1 || !mark_started(argv[0])) return 20;
    if (!write_line("{\"version\":1,\"event\":\"ready\",\"backend\":\"bluez-native\",\"revision\":\"2123ab772fbe97d1369fc9e179ea87c3469cf98f\"}")) return 21;

    if (!read_line(line, sizeof(line)) || !strstr(line, "\"event\":\"flow_open\"") ||
        !generation(line, session)) return 22;
    if (!read_line(line, sizeof(line)) || !strstr(line, "\"id\":\"open\"") ||
        !strstr(line, "\"operation\":\"open\"")) return 23;

    if (!write_line("{\"version\":1,\"id\":\"open\",\"ok\":true,\"result\":{\"generation\":1,\"device_path\":\"/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF\",\"link_owned\":false,\"sender\":\":1.1\"}}")) return 24;

    if (!read_line(line, sizeof(line))) return 25;
    if (strstr(line, "\"id\":\"close\"") && strstr(line, "\"operation\":\"close\"")) {
        if (!write_line("{\"version\":1,\"id\":\"close\",\"ok\":true,\"result\":null}")) return 26;
        return 0;
    }

    if (!strstr(line, "\"id\":\"1\"") || !strstr(line, "\"operation\":\"subscribe\"") ||
        !strstr(line, "\"queue_limit\":2")) return 27;

    if (!write_line("{\"version\":1,\"id\":\"1\",\"ok\":true,\"result\":{\"subscription_id\":\"1\",\"generation\":1,\"characteristic\":{\"service_uuid\":\"0000180f-0000-1000-8000-00805f9b34fb\",\"characteristic_uuid\":\"00002a19-0000-1000-8000-00805f9b34fb\",\"service_path\":\"/service\",\"object_path\":\"/characteristic\",\"handle\":1,\"generation\":1,\"flags\":[\"notify\"]},\"requested_mode\":\"auto\",\"effective_mode\":\"notify\"}}")) return 28;

    {
        char first[2048];
        char second[2048];
        char unsubscribe_id[65] = {0};
        size_t first_bytes;
        size_t total_bytes;
        int first_ack = 0;
        int second_ack = 0;
        int unsubscribe = 0;
        char acknowledged_session[33];
        int length = snprintf(first, sizeof(first),
            "{\"version\":1,\"session_generation\":\"%s\",\"report_sequence\":1,\"subscription_id\":\"1\",\"generation\":1,\"event\":\"value\",\"value\":{\"type\":\"bytes\",\"base64\":\"AQ==\"},\"metadata\":{\"source\":\"bluez_value_change\",\"characteristic\":{\"service_uuid\":\"0000180f-0000-1000-8000-00805f9b34fb\",\"characteristic_uuid\":\"00002a19-0000-1000-8000-00805f9b34fb\",\"service_path\":\"/service\",\"object_path\":\"/characteristic\",\"handle\":1,\"generation\":1,\"flags\":[\"notify\"]},\"requested_mode\":\"auto\",\"effective_mode\":\"notify\"}}",
            session);
        if (length < 0 || (size_t)length >= sizeof(first)) return 29;
        length = snprintf(second, sizeof(second),
            "{\"version\":1,\"session_generation\":\"%s\",\"report_sequence\":2,\"subscription_id\":\"1\",\"generation\":1,\"event\":\"value\",\"value\":{\"type\":\"bytes\",\"base64\":\"Ag==\"},\"metadata\":{\"source\":\"bluez_value_change\",\"characteristic\":{\"service_uuid\":\"0000180f-0000-1000-8000-00805f9b34fb\",\"characteristic_uuid\":\"00002a19-0000-1000-8000-00805f9b34fb\",\"service_path\":\"/service\",\"object_path\":\"/characteristic\",\"handle\":1,\"generation\":1,\"flags\":[\"notify\"]},\"requested_mode\":\"auto\",\"effective_mode\":\"notify\"}}",
            session);
        if (length < 0 || (size_t)length >= sizeof(second)) return 30;
        first_bytes = strlen(first) + 1;
        total_bytes = first_bytes + strlen(second) + 1;
        if (!write_line(first) || !write_line(second)) return 31;

        while (!first_ack || !second_ack || !unsubscribe) {
            if (!read_line(line, sizeof(line))) return 32;
            if (strstr(line, "\"event\":\"report_ack\"")) {
                if (!generation(line, acknowledged_session) ||
                    strcmp(acknowledged_session, session) != 0) return 33;
                if (unsigned_field(line, "report_sequence", 1) &&
                    unsigned_field(line, "acknowledged_bytes", first_bytes) && !first_ack) {
                    first_ack = 1;
                } else if (unsigned_field(line, "report_sequence", 2) &&
                           unsigned_field(line, "acknowledged_bytes", total_bytes) &&
                           first_ack && !second_ack) {
                    second_ack = 1;
                } else {
                    return 34;
                }
            } else if (strstr(line, "\"operation\":\"unsubscribe\"") &&
                       strstr(line, "\"subscription_id\":\"1\"") &&
                       string_field(line, "id", unsubscribe_id, sizeof(unsubscribe_id))) {
                if (unsubscribe) return 35;
                unsubscribe = 1;
            } else {
                return 36;
            }
        }

        length = snprintf(line, sizeof(line),
            "{\"version\":1,\"event\":\"stream_retired\",\"session_generation\":\"%s\",\"subscription_id\":\"1\",\"generation\":1,\"last_report_sequence\":2}",
            session);
        if (length < 0 || (size_t)length >= sizeof(line) || !write_line(line)) return 37;
        length = snprintf(line, sizeof(line),
            "{\"version\":1,\"id\":\"%s\",\"ok\":true,\"result\":null}", unsubscribe_id);
        if (length < 0 || (size_t)length >= sizeof(line) || !write_line(line)) return 38;
    }

    if (!read_line(line, sizeof(line)) || !strstr(line, "\"id\":\"close\"") ||
        !strstr(line, "\"operation\":\"close\"")) return 39;
    if (!write_line("{\"version\":1,\"id\":\"close\",\"ok\":true,\"result\":null}")) return 40;
    return 0;
}
