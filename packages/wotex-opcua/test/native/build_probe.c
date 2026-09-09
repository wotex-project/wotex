/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static void forever(void) {
    (void)signal(SIGTERM, SIG_IGN);
    for (;;) pause();
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    if (!strcmp(argv[1], "environment")) {
        printf("canary=%s\n", getenv("WOTEX_NATIVE_TEST_CANARY") ? "present" : "absent");
        printf("locale=%s\n", getenv("LC_ALL") ? getenv("LC_ALL") : "absent");
        return 0;
    }
    if (!strcmp(argv[1], "output")) {
        puts("stdout");
        fputs("stderr\n", stderr);
        return 0;
    }
    if (!strcmp(argv[1], "exit")) return 7;
    if (!strcmp(argv[1], "stopped")) {
        printf("%ld\n", (long)getpid());
        fflush(stdout);
        raise(SIGSTOP);
        forever();
    }
    if (!strcmp(argv[1], "flood")) {
        char data[4096];
        memset(data, 'x', sizeof(data));
        while (write(STDOUT_FILENO, data, sizeof(data)) > 0) {}
        return 0;
    }
    if (!strcmp(argv[1], "background") || !strcmp(argv[1], "hang")) {
        pid_t child = fork();
        if (child < 0) return 3;
        if (child == 0) forever();
        printf("%ld %ld\n", (long)getpid(), (long)child);
        fflush(stdout);
        const char *pidfile = getenv("WOTEX_NATIVE_TEST_PIDFILE");
        if (pidfile) {
            FILE *file = fopen(pidfile, "w");
            if (!file) return 5;
            fprintf(file, "%ld %ld\n", (long)getpid(), (long)child);
            fclose(file);
        }
        if (!strcmp(argv[1], "background")) return 0;
        forever();
    }
    return 4;
}
