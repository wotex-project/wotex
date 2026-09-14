/* SPDX-License-Identifier: Apache-2.0
 * Deterministic process fixture for the BEAM-owned native startup boundary.
 */
#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

static int read_line(char *line, size_t capacity) {
    size_t length;
    if (!fgets(line, (int)capacity, stdin)) return 0;
    length = strlen(line);
    return length > 0 && line[length - 1] == '\n';
}

static int generation(const char *line) {
    const char *prefix = "\"session_generation\":\"";
    const char *value = strstr(line, prefix);
    if (!value) return 0;
    value += strlen(prefix);
    for (size_t index = 0; index < 32; ++index)
        if (!isdigit((unsigned char)value[index]) &&
            !(value[index] >= 'a' && value[index] <= 'f')) return 0;
    return value[32] == '"';
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
    if (argc != 1 || !mark_started(argv[0])) return 20;
    if (puts("{\"version\":1,\"event\":\"ready\",\"backend\":\"bluez-native\",\"revision\":\"2123ab772fbe97d1369fc9e179ea87c3469cf98f\"}") < 0 ||
        fflush(stdout) != 0) return 21;

    if (!read_line(line, sizeof(line)) || !strstr(line, "\"event\":\"flow_open\"") ||
        !generation(line)) return 22;
    if (!read_line(line, sizeof(line)) || !strstr(line, "\"id\":\"open\"") ||
        !strstr(line, "\"operation\":\"open\"")) return 23;

    if (puts("{\"version\":1,\"id\":\"open\",\"ok\":true,\"result\":{\"generation\":1,\"device_path\":\"/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF\",\"link_owned\":false,\"sender\":\":1.1\"}}") < 0 ||
        fflush(stdout) != 0) return 24;

    if (!read_line(line, sizeof(line)) || !strstr(line, "\"id\":\"close\"") ||
        !strstr(line, "\"operation\":\"close\"")) return 25;
    if (puts("{\"version\":1,\"id\":\"close\",\"ok\":true,\"result\":null}") < 0 ||
        fflush(stdout) != 0) return 26;
    return 0;
}
