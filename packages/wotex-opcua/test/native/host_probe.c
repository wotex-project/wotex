/* SPDX-License-Identifier: Apache-2.0
 * Native bootstrap peer. Filename selects the fault; test-owned cwd holds the
 * PID/control files. It has no OPC UA socket or Session implementation.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int write_all(int fd, const char *bytes, size_t count) {
    while (count) {
        ssize_t size = write(fd, bytes, count);
        if (size < 0 && errno == EINTR) continue;
        if (size <= 0) return -1;
        bytes += size; count -= (size_t)size;
    }
    return 0;
}
static void sleep_ms(long milliseconds) {
    struct timespec duration = {0, milliseconds * 1000000L};
    while (nanosleep(&duration, &duration) < 0 && errno == EINTR) {}
}

static int read_line(char *output, size_t capacity) {
    size_t used = 0;
    while(used + 1 < capacity) {
        ssize_t count = read(STDIN_FILENO, output + used, 1);
        if(count < 0 && errno == EINTR) continue;
        if(count != 1) return -1;
        if(output[used++] == '\n') {
            output[used] = '\0';
            return 0;
        }
    }
    return -1;
}

static int session_reply(void) {
    char frame[4096], id[65];
    unsigned long long generation = 0;
    if(read_line(frame, sizeof(frame)) || !strstr(frame, "\"event\":\"credit\"") ||
       !strstr(frame, "\"sequence\":1")) return 50;
    if(read_line(frame, sizeof(frame)) || !strstr(frame, "\"operation\":\"open\"") ||
       !strstr(frame, "\"session_timeout_ms\":60000")) return 51;
    char *key = strstr(frame, "\"generation\":");
    char *request_id = strstr(frame, "\"id\":\"");
    if(!key || !request_id || sscanf(key, "\"generation\":%llu", &generation) != 1 ||
       sscanf(request_id, "\"id\":\"%64[0-9]\"", id) != 1) return 52;
    int count = snprintf(frame, sizeof(frame),
        "{\"version\":1,\"generation\":%llu,\"id\":\"%s\",\"ok\":true,"
        "\"result\":{\"session_timeout_ms\":60000.0,\"session_generation\":%llu,"
        "\"namespace_array\":[\"http://opcfoundation.org/UA/\",\"urn:fixture\"]}}\n",
        generation, id, generation);
    if(count <= 0 || (size_t)count >= sizeof(frame) ||
       write_all(STDOUT_FILENO, frame, (size_t)count)) return 53;
    if(read_line(frame, sizeof(frame)) || !strstr(frame, "\"event\":\"credit\"") ||
       !strstr(frame, "\"sequence\":2")) return 54;
    if(read_line(frame, sizeof(frame)) || !strstr(frame, "\"operation\":\"close\"")) return 55;
    request_id = strstr(frame, "\"id\":\"");
    if(!request_id || sscanf(request_id, "\"id\":\"%64[0-9]\"", id) != 1) return 56;
    count = snprintf(frame, sizeof(frame),
        "{\"version\":1,\"generation\":%llu,\"id\":\"%s\",\"ok\":true,\"result\":null}\n",
        generation, id);
    if(count <= 0 || (size_t)count >= sizeof(frame) ||
       write_all(STDOUT_FILENO, frame, (size_t)count)) return 57;
    return 0;
}

static int session_services(int remote_browse) {
    char frame[4096], id[65];
    unsigned long long generation = 0;
    for(unsigned sequence = 1; sequence <= 16; sequence++) {
        if(read_line(frame, sizeof(frame)) || !strstr(frame, "\"event\":\"credit\"")) return 58;
        if(read_line(frame, sizeof(frame))) return 59;
        char *key = strstr(frame, "\"generation\":");
        char *request_id = strstr(frame, "\"id\":\"");
        if(!key || !request_id || sscanf(key, "\"generation\":%llu", &generation) != 1 ||
           sscanf(request_id, "\"id\":\"%64[0-9]\"", id) != 1) return 60;
        const char *result;
        if(strstr(frame, "\"operation\":\"open\""))
            result = "{\"session_timeout_ms\":60000.0,\"session_generation\":%llu,"
                     "\"namespace_array\":[\"http://opcfoundation.org/UA/\",\"urn:fixture\"]}";
        else if(strstr(frame, "\"operation\":\"read\""))
            result = remote_browse == 5 ?
                "{\"has_value\":true,\"value\":{\"type\":\"ByteString\","
                "\"array\":true,\"value\":[{\"type\":\"bytes\",\"base64\":\"AP8=\"},"
                "{\"type\":\"bytes\",\"base64\":\"AQ==\"}]},\"status\":0}" :
                remote_browse == 6 ? "{\"has_value\":false,\"status\":0}" :
                remote_browse == 7 ?
                "{\"has_value\":true,\"value\":{\"type\":\"LocalizedText\","
                "\"array\":false,\"value\":{\"locale\":\"en\",\"text\":\"Value\"}},\"status\":0}" :
                remote_browse == 8 ?
                "{\"has_value\":true,\"value\":{\"type\":\"LocalizedText\","
                "\"array\":true,\"value\":[{\"locale\":\"en\",\"text\":\"Value\"}]},\"status\":0}" :
                "{\"has_value\":true,\"value\":{\"type\":\"Double\","
                     "\"array\":false,\"value\":21.5},\"status\":0}";
        else if(strstr(frame, "\"operation\":\"write\""))
            result = remote_browse == 11 && !strstr(frame, "\"base64\":\"AP8=\"") ?
                NULL : remote_browse == 12 &&
                (!strstr(frame, "\"array\":true") ||
                 !strstr(frame, "\"base64\":\"AP8=\"") ||
                 !strstr(frame, "\"base64\":\"\"")) ?
                NULL : "{\"status\":0}";
        else if(strstr(frame, "\"operation\":\"call\""))
            result = remote_browse == 3 ?
                "{\"status\":0,\"input_argument_statuses\":[],\"outputs\":[]}" :
                remote_browse == 4 ?
                "{\"status\":0,\"input_argument_statuses\":[],"
                "\"outputs\":[{\"type\":\"Double\",\"array\":false,\"value\":4.5},"
                "{\"type\":\"Boolean\",\"array\":false,\"value\":true}]}" :
                remote_browse == 9 ?
                "{\"status\":0,\"input_argument_statuses\":[],"
                "\"outputs\":[{\"type\":\"LocalizedText\",\"array\":false,"
                "\"value\":{\"locale\":\"en\",\"text\":\"Value\"}}]}" :
                remote_browse == 10 ?
                "{\"status\":0,\"input_argument_statuses\":[],"
                "\"outputs\":[{\"type\":\"Double\",\"array\":true,"
                "\"value\":[1.0,2.0],\"dimensions\":[1,2]}]}" :
                "{\"status\":0,\"input_argument_statuses\":[],"
                     "\"outputs\":[{\"type\":\"Double\",\"array\":false,\"value\":4.5}]}";
        else if(strstr(frame, "\"operation\":\"browse\""))
            result = remote_browse == 13 ?
                "{\"status\":0,\"continuation\":null,\"references\":[{"
                "\"reference_type_id\":\"ns=0;i=35\",\"is_forward\":true,"
                "\"node_id\":{\"node_id\":\"ns=1;s=value\",\"namespace_uri\":null,\"server_index\":0},"
                "\"browse_name\":{\"namespace\":1,\"name\":\"Value\"},"
                "\"display_name\":{\"locale\":null,\"text\":\"Value\"},\"node_class\":2,"
                "\"type_definition\":{\"node_id\":\"ns=0;i=0\",\"namespace_uri\":null,\"server_index\":0}},{"
                "\"reference_type_id\":\"ns=0;i=35\",\"is_forward\":true,"
                "\"node_id\":{\"node_id\":\"ns=1;s=value\",\"namespace_uri\":null,\"server_index\":0},"
                "\"browse_name\":{\"namespace\":1,\"name\":\"Value\"},"
                "\"display_name\":{\"locale\":null,\"text\":\"Value\"},\"node_class\":2,"
                "\"type_definition\":{\"node_id\":\"ns=0;i=0\",\"namespace_uri\":null,\"server_index\":0}}]}" :
                remote_browse == 1 ?
                "{\"status\":0,\"continuation\":null,\"references\":[{"
                "\"reference_type_id\":\"ns=0;i=35\",\"is_forward\":true,"
                "\"node_id\":{\"node_id\":\"ns=1;s=value\",\"namespace_uri\":null,\"server_index\":1},"
                "\"browse_name\":{\"namespace\":1,\"name\":\"Value\"},"
                "\"display_name\":{\"locale\":null,\"text\":\"Value\"},\"node_class\":2,"
                "\"type_definition\":{\"node_id\":\"ns=0;i=0\",\"namespace_uri\":null,\"server_index\":0}}]}" :
                remote_browse == 2 ?
                "{\"status\":0,\"continuation\":null,\"references\":[{"
                "\"reference_type_id\":\"ns=0;i=35\",\"is_forward\":true,"
                "\"node_id\":{\"node_id\":\"ns=2;s=value\",\"namespace_uri\":null,\"server_index\":0},"
                "\"browse_name\":{\"namespace\":1,\"name\":\"Value\"},"
                "\"display_name\":{\"locale\":null,\"text\":\"Value\"},\"node_class\":2,"
                "\"type_definition\":{\"node_id\":\"ns=0;i=0\",\"namespace_uri\":null,\"server_index\":0}}]}" :
                "{\"status\":0,\"continuation\":null,\"references\":[{"
                "\"reference_type_id\":\"ns=0;i=35\",\"is_forward\":true,"
                "\"node_id\":{\"node_id\":\"ns=1;s=value\",\"namespace_uri\":null,\"server_index\":0},"
                "\"browse_name\":{\"namespace\":1,\"name\":\"Value\"},"
                "\"display_name\":{\"locale\":null,\"text\":\"Value\"},\"node_class\":2,"
                "\"type_definition\":{\"node_id\":\"ns=0;i=0\",\"namespace_uri\":null,\"server_index\":0}}]}";
        else if(strstr(frame, "\"operation\":\"close\""))
            result = "null";
        else return 61;
        if(!result) return 65;
        char body[1024];
        int size;
        if(strstr(frame, "\"operation\":\"open\""))
            size = snprintf(body, sizeof(body), result, generation);
        else
            size = snprintf(body, sizeof(body), "%s", result);
        if(size <= 0 || (size_t)size >= sizeof(body)) return 62;
        int count = snprintf(frame, sizeof(frame),
            "{\"version\":1,\"generation\":%llu,\"id\":\"%s\",\"ok\":true,\"result\":%s}\n",
            generation, id, body);
        if(count <= 0 || (size_t)count >= sizeof(frame) ||
           write_all(STDOUT_FILENO, frame, (size_t)count)) return 63;
        if(!strcmp(body, "null")) return 0;
    }
    return 64;
}
int main(int argc, char **argv) {
    if (argc != 1) return 40;
    const char *mode = strrchr(argv[0], '/');
    mode = mode ? mode + 1 : argv[0];
    FILE *file = fopen("host.pid", "wx");
    if (!file) return 41;
    fprintf(file, "%ld %ld\n", (long)getpid(), (long)getppid());
    if (fclose(file)) return 42;
    file = fopen("environment", "wx");
    if (!file) return 43;
    fprintf(file, "private=%d\nlocale=%s\n", getenv("WOTEX_PRIVATE_SENTINEL") != NULL,
            getenv("LC_ALL") ? getenv("LC_ALL") : "absent");
    if (fclose(file)) return 44;
    signal(SIGTERM, SIG_IGN);
    if (!strcmp(mode, "stopped")) { raise(SIGSTOP); for (;;) pause(); }
    if (!strcmp(mode, "hang")) for (;;) pause();
    if (!strcmp(mode, "exit")) return 17;
    if (!strcmp(mode, "stderr")) {
        write_all(STDERR_FILENO, "private SDK diagnostic", 22);
        for (;;) pause();
    }
    struct timespec clock;
    if (clock_gettime(CLOCK_MONOTONIC, &clock)) return 45;
    char ready[256];
    int count = snprintf(ready, sizeof(ready),
        "{\"version\":1,\"event\":\"ready\",\"backend\":\"open62541\","
        "\"revision\":\"d1173ccc31560ffc60c29e24ce8adb19f8c3c686\",\"clock_ms\":%lld}\n",
        (long long)clock.tv_sec * 1000 + clock.tv_nsec / 1000000);
    if (count <= 0 || (size_t)count >= sizeof(ready)) return 46;
    if (!strcmp(mode, "invalid")) {
        if (write_all(STDOUT_FILENO, "{bad}\n", 6)) return 47;
    } else if (!strcmp(mode, "overlong")) {
        char bytes[4097]; memset(bytes, 'x', sizeof(bytes));
        if (write_all(STDOUT_FILENO, bytes, sizeof(bytes))) return 47;
    } else if (!strcmp(mode, "duplicate")) {
        char bytes[512]; memcpy(bytes, ready, (size_t)count); memcpy(bytes+count, ready, (size_t)count);
        if (write_all(STDOUT_FILENO, bytes, (size_t)count*2)) return 47;
    } else if (!strcmp(mode, "fragmented")) {
        for (int index = 0; index < count; ++index) {
            if (write_all(STDOUT_FILENO, ready+index, 1)) return 47;
            sleep_ms(1);
        }
    } else if (write_all(STDOUT_FILENO, ready, (size_t)count)) return 47;
    if (!strcmp(mode, "session_reply")) return session_reply();
    if (!strcmp(mode, "session_services")) return session_services(0);
    if (!strcmp(mode, "session_remote_browse")) return session_services(1);
    if (!strcmp(mode, "session_unknown_browse")) return session_services(2);
    if (!strcmp(mode, "session_empty_call")) return session_services(3);
    if (!strcmp(mode, "session_many_call")) return session_services(4);
    if (!strcmp(mode, "session_bytes_read")) return session_services(5);
    if (!strcmp(mode, "session_empty_read")) return session_services(6);
    if (!strcmp(mode, "session_localized_read")) return session_services(7);
    if (!strcmp(mode, "session_localized_array_read")) return session_services(8);
    if (!strcmp(mode, "session_localized_call")) return session_services(9);
    if (!strcmp(mode, "session_matrix_call")) return session_services(10);
    if (!strcmp(mode, "session_runtime_bytes")) return session_services(11);
    if (!strcmp(mode, "session_runtime_byte_array")) return session_services(12);
    if (!strcmp(mode, "session_two_browse")) return session_services(13);
    for (;;) {
        struct pollfd input = {STDIN_FILENO, POLLIN, 0};
        int polled = poll(&input, 1, 10);
        if (polled < 0 && errno == EINTR) continue;
        if (polled < 0) return 48;
        if (input.revents & (POLLIN | POLLHUP)) {
            char byte; ssize_t size = read(STDIN_FILENO, &byte, 1);
            if (!size) return 0;
            if (size > 0 && strcmp(mode, "stall_request"))
                return 49; /* unsolicited bootstrap input is rejected */
        }
        if (access("trigger", F_OK) == 0) {
            if (!strcmp(mode, "late")) {
                if (write_all(STDOUT_FILENO, ready, (size_t)count)) return 47;
                unlink("trigger");
            } else if (!strcmp(mode, "late_exit")) return 0;
        }
    }
}
