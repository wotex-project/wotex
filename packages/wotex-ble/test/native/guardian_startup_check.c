/* SPDX-License-Identifier: Apache-2.0
 * Actual exec inheritance and repeated short-child startup checks. The input
 * pipe stays open until the guardian exits; command input carries no bytes.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int64_t now(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value)) return -1;
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}

static int probe(void) {
    struct sigaction action;
    sigset_t mask;
    if (sigaction(SIGCHLD, NULL, &action) || action.sa_handler != SIG_DFL ||
        sigprocmask(SIG_SETMASK, NULL, &mask) || getpgrp() != getpid()) return 20;
    for (int signal_number = 1; signal_number < 32; ++signal_number)
        if (sigismember(&mask, signal_number) == 1) return 21;
    return write(STDOUT_FILENO, "ready\n", 6) == 6 ? 0 : 22;
}

static int one(const char *self, const char *guardian, const char *kind,
               const char *inherit, const char *cwd, int expected) {
    int input[2], output[2], status = -1, eof = 0, observed = 0;
    unsigned char bytes[64];
    size_t used = 0;
    if (pipe(input) || pipe(output)) return 30;
    pid_t child = fork();
    if (child < 0) return 31;
    if (!child) {
        if (dup2(input[0], STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0)
            _exit(32);
        close(input[0]); close(input[1]); close(output[0]); close(output[1]);
        if (!strcmp(inherit, "inherit")) {
            struct sigaction action;
            sigset_t mask;
            memset(&action, 0, sizeof(action));
            action.sa_handler = SIG_IGN;
            if (sigemptyset(&action.sa_mask) || sigaction(SIGCHLD, &action, NULL) ||
                sigfillset(&mask) || sigprocmask(SIG_SETMASK, &mask, NULL)) _exit(33);
        }
        char *args[] = {(char *)guardian, "500", "4096", "4096", (char *)cwd,
                        (char *)self, "--probe", NULL};
        if (!strcmp(kind, "command")) {
            args[1] = "2000";
            args[3] = "500";
        }
        execv(guardian, args);
        _exit(34);
    }
    close(input[0]); close(output[1]);
    int flags = fcntl(output[0], F_GETFL);
    if (flags < 0 || fcntl(output[0], F_SETFL, flags | O_NONBLOCK) < 0) goto fail;
    int64_t deadline = now() + 5000;
    while (now() < deadline) {
        struct pollfd descriptor = {output[0], POLLIN, 0};
        if (poll(&descriptor, 1, 2) < 0 && errno != EINTR) goto fail;
        if (!eof) {
            ssize_t size = read(output[0], bytes + used, sizeof(bytes) - used);
            if (size > 0) used += (size_t)size;
            if (size == 0) eof = 1;
            if (size < 0 && errno != EAGAIN && errno != EINTR) goto fail;
            if (used == sizeof(bytes)) goto fail;
        }
        if (!observed) {
            pid_t result = waitpid(child, &status, WNOHANG);
            if (result == child) observed = 1;
            else if (result < 0 && errno != EINTR) goto fail;
        }
        if (observed && eof) {
            close(input[1]); close(output[0]);
            int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
            if (code != expected) {
                fprintf(stderr, "guardian startup: expected=%d actual=%d bytes=%zu\n",
                        expected, code, used);
                return 35;
            }
            if ((!expected && (used != 6 || memcmp(bytes, "ready\n", 6))) ||
                (expected && used)) return 36;
            return 0;
        }
    }
fail:
    close(input[1]); close(output[0]);
    if (!observed) {
        (void)kill(child, SIGKILL);
        while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    }
    return 37;
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--probe")) return probe();
    if (argc != 7 || argv[1][0] != '/' || argv[5][0] != '/' ||
        (strcmp(argv[2], "command") && strcmp(argv[2], "custody")) ||
        (strcmp(argv[4], "inherit") && strcmp(argv[4], "plain"))) return 40;
    char *tail;
    unsigned long count = strtoul(argv[3], &tail, 10);
    if (*tail || !count || count > 1000) return 41;
    long expected = strtol(argv[6], &tail, 10);
    if (*tail || (expected != 0 && expected != 126)) return 42;
    for (unsigned long index = 0; index < count; ++index) {
        int result = one(argv[0], argv[1], argv[2], argv[4], argv[5], (int)expected);
        if (result) return result;
    }
    printf("{\"launches\":%lu,\"status\":\"passed\"}\n", count);
    return 0;
}
