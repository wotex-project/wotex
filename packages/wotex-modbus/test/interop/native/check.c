/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

/* Standalone sanitizer lane for the real guardian and fault producer. */
static void check(const char *guardian, const char *probe, const char *mode,
                  const char *timeout, const char *limit, int owner_eof,
                  int expected, size_t expected_length) {
    int owner[2], output[2], status = 0;
    size_t length = 0;
    char bytes[8192];
    pid_t child;
    assert(pipe(owner) == 0 && pipe(output) == 0);
    child = fork();
    assert(child >= 0);
    if (child == 0) {
        assert(dup2(owner[0], STDIN_FILENO) >= 0);
        assert(dup2(output[1], STDOUT_FILENO) >= 0);
        close(owner[0]); close(owner[1]); close(output[0]); close(output[1]);
        execl(guardian, guardian, timeout, limit, "400", "/tmp", probe, mode, (char *)NULL);
        _exit(126);
    }
    close(owner[0]); close(output[1]);
    if (owner_eof) { close(owner[1]); owner[1] = -1; }
    for (;;) {
        struct pollfd descriptor = {output[0], POLLIN | POLLHUP, 0};
        ssize_t count;
        assert(poll(&descriptor, 1, 5000) > 0);
        count = read(output[0], bytes, sizeof(bytes));
        if (count < 0 && errno == EINTR) continue;
        assert(count >= 0);
        if (!count) break;
        length += (size_t)count;
    }
    if (owner[1] >= 0) close(owner[1]);
    close(output[0]);
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status));
    if (WEXITSTATUS(status) != expected) {
        fprintf(stderr, "%s: expected %d, got %d\n", mode, expected, WEXITSTATUS(status));
        abort();
    }
    if (expected_length) assert(length == expected_length);
}

static pid_t lock_child(const char *guardian, const char *path, int *owner_fd, int *output_fd) {
    int owner[2], output[2];
    pid_t child;
    assert(pipe(owner) == 0 && pipe(output) == 0);
    child = fork();
    assert(child >= 0);
    if (child == 0) {
        assert(dup2(owner[0], STDIN_FILENO) >= 0 && dup2(output[1], STDOUT_FILENO) >= 0);
        close(owner[0]); close(owner[1]); close(output[0]); close(output[1]);
        execl(guardian, guardian, "--lock", path, (char *)NULL);
        _exit(126);
    }
    close(owner[0]); close(output[1]);
    *owner_fd = owner[1]; *output_fd = output[0];
    return child;
}

static void locks(const char *guardian) {
    char path[128], output[128];
    int owner, reader, other_owner, other_reader, status;
    pid_t first, second;
    snprintf(path, sizeof(path), "/tmp/wotex-command-lock-%ld", (long)getpid());
    first = lock_child(guardian, path, &owner, &reader);
    assert(read(reader, output, sizeof(output)) == 19);
    second = lock_child(guardian, path, &other_owner, &other_reader);
    assert(waitpid(second, &status, 0) == second && WIFEXITED(status) && WEXITSTATUS(status) == 130);
    close(other_owner); close(other_reader);
    close(owner); close(reader);
    assert(waitpid(first, &status, 0) == first && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    first = lock_child(guardian, path, &owner, &reader);
    assert(read(reader, output, sizeof(output)) == 19);
    assert(write(owner, "R", 1) == 1);
    assert(read(reader, output, sizeof(output)) == 23);
    assert(waitpid(first, &status, 0) == first && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(owner); close(reader);
    assert(unlink(path) == 0);
}

int main(int argc, char **argv) {
    assert(argc == 3);
    check(argv[1], argv[2], "output", "1000", "65536", 0, 0, 14);
    check(argv[1], argv[2], "exit", "1000", "65536", 0, 7, 0);
    check(argv[1], argv[2], "hang", "80", "65536", 0, 124, 0);
    check(argv[1], argv[2], "stopped", "100", "65536", 0, 124, 0);
    check(argv[1], argv[2], "background", "1000", "65536", 0, 0, 0);
    check(argv[1], argv[2], "flood", "1000", "4097", 0, 125, 4097);
    check(argv[1], argv[2], "hang", "1000", "65536", 1, 127, 0);
    locks(argv[1]);
    puts("WMB-N01 WMB-N02 WMB-N03 native guardian: 8 cases passed");
    return 0;
}
