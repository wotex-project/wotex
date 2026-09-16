/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static const char ready[] =
    "{\"version\":1,\"event\":\"ready\",\"backend\":\"libcoap\","
    "\"revision\":\"7cf7465b784baded4de183290c547d582becfd28\"}\n";

static int read_exact(int descriptor, char *bytes, size_t length) {
    size_t used = 0;
    while (used < length) {
        ssize_t count = read(descriptor, bytes + used, length - used);
        if (count > 0) used += (size_t)count;
        else if (count < 0 && errno == EINTR) continue;
        else return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    int input[2], output[2], status;
    pid_t child;
    char bytes[sizeof(ready) - 1], extra;
    if (argc != 2 || argv[1][0] != '/' || pipe(input) || pipe(output)) return 64;
    child = fork();
    if (child < 0) return 65;
    if (child == 0) {
        char *arguments[] = {argv[1], "--worker", NULL};
        close(input[1]); close(output[0]);
        if (dup2(input[0], STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0 ||
            dup2(output[1], STDERR_FILENO) < 0) _exit(66);
        close(input[0]); close(output[1]);
        execv(argv[1], arguments);
        _exit(67);
    }
    close(input[0]); close(output[1]); close(input[1]);
    if (!read_exact(output[0], bytes, sizeof(bytes)) || memcmp(bytes, ready, sizeof(bytes)) ||
        read(output[0], &extra, 1) != 0) return 68;
    close(output[0]);
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return 69;
    return fwrite(ready, 1, sizeof(ready) - 1, stdout) == sizeof(ready) - 1 ? 0 : 71;
}
