/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    struct sigaction action;
    sigset_t blocked;
    if (argc < 2 || getpgrp() != getpid() || sigaction(SIGCHLD, NULL, &action) ||
        action.sa_handler != SIG_DFL || sigprocmask(SIG_SETMASK, NULL, &blocked) ||
        sigismember(&blocked, SIGTERM) || sigismember(&blocked, SIGCHLD)) return 1;
    if (!strcmp(argv[1], "exit")) return 7;
    if (!strcmp(argv[1], "output")) {
        if (write(STDOUT_FILENO, "stdout\n", 7) != 7 || write(STDERR_FILENO, "stderr\n", 7) != 7) return 1;
        return 0;
    }
    if (argc == 3 && !strcmp(argv[1], "marker")) {
        int descriptor = open(argv[2], O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (descriptor < 0) return 1;
        close(descriptor);
        return 0;
    }
    return 2;
}
