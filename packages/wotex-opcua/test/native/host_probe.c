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
    for (;;) {
        struct pollfd input = {STDIN_FILENO, POLLIN, 0};
        int polled = poll(&input, 1, 10);
        if (polled < 0 && errno == EINTR) continue;
        if (polled < 0) return 48;
        if (input.revents & (POLLIN | POLLHUP)) {
            char byte; ssize_t size = read(STDIN_FILENO, &byte, 1);
            if (!size) return 0;
            if (size > 0) return 49; /* bootstrap must not send service bytes */
        }
        if (access("trigger", F_OK) == 0) {
            if (!strcmp(mode, "late")) {
                if (write_all(STDOUT_FILENO, ready, (size_t)count)) return 47;
                unlink("trigger");
            } else if (!strcmp(mode, "late_exit")) return 0;
        }
    }
}
