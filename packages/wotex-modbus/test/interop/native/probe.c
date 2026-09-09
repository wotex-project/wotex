/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static void forever(void) {
    (void)signal(SIGTERM, SIG_IGN);
    for (;;) pause();
}

int main(int argc, char **argv) {
    if (argc >= 3 && !strcmp(argv[1], "--inherited")) {
        struct sigaction action;
        sigset_t mask;
        memset(&action, 0, sizeof(action));
        sigemptyset(&action.sa_mask);
        action.sa_handler = SIG_IGN;
        action.sa_flags = SA_NOCLDWAIT;
        sigfillset(&mask);
        if (sigaction(SIGCHLD, &action, NULL) || sigprocmask(SIG_SETMASK, &mask, NULL)) return 3;
        execv(argv[2], &argv[2]);
        return 3;
    }
    if (argc == 3 && !strcmp(argv[1], "--lock")) {
        struct timespec delay = {0, 50000000};
        char byte;
        if (!strcmp(argv[2], "/split")) {
            if (write(STDOUT_FILENO, "wotex_", 6) != 6) return 3;
            (void)nanosleep(&delay, NULL);
            if (write(STDOUT_FILENO, "fixture_lock\n", 13) != 13) return 3;
        } else if (!strcmp(argv[2], "/extra")) {
            if (write(STDOUT_FILENO, "wotex_fixture_lock\nextra", 24) != 24) return 3;
        } else {
            if (write(STDOUT_FILENO, "invalid", 7) != 7) return 3;
        }
        if (read(STDIN_FILENO, &byte, 1) == 1 && byte == 'R') {
            return write(STDOUT_FILENO, "wotex_fixture_unlocked\n", 23) == 23 ? 0 : 3;
        }
        return 0;
    }
    if (argc != 2) return 2;
    if (!strcmp(argv[1], "signals")) {
        struct sigaction action;
        sigset_t mask;
        if (sigaction(SIGCHLD, NULL, &action) || action.sa_handler != SIG_DFL ||
            (action.sa_flags & SA_NOCLDWAIT) || sigprocmask(SIG_SETMASK, NULL, &mask)) return 5;
        if (sigismember(&mask, SIGCHLD) || sigismember(&mask, SIGTERM) ||
            sigismember(&mask, SIGINT) || sigismember(&mask, SIGHUP) ||
            sigismember(&mask, SIGPIPE) || getpgrp() != getpid()) return 5;
        puts("signals-reset");
        return 0;
    }
    if (!strcmp(argv[1], "output")) {
        puts("stdout");
        fputs("stderr\n", stderr);
        return 0;
    }
    if (!strcmp(argv[1], "exit")) return 7;
    if (!strcmp(argv[1], "stopped")) {
        (void)raise(SIGSTOP);
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
        if (!strcmp(argv[1], "background")) return 0;
        forever();
    }
    return 4;
}
