/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/*
 * Explicit fixture command guardian. stdin is an owner-liveness pipe. The child
 * receives /dev/null stdin and its own process group. stdout is a bounded,
 * nonblocking combined stdout/stderr stream. No command text is interpreted.
 *
 * Usage: command TIMEOUT_MS OUTPUT_BYTES CLEANUP_MS CWD EXECUTABLE [ARG ...]
 * Exit: child's 0..123, 124 deadline, 125 output bound, 126 setup/protocol error,
 * 127 owner EOF/signal/output consumer loss, 128 child signal, 129 cleanup failure.
 * The unreaped child pins the process-group identity until final cleanup. This
 * helper contains ordinary fixture descendants remaining in that group; it is
 * not a sandbox for a child deliberately escaping with setsid/setpgid.
 */
#define QUEUE_SIZE 65536U
#define POLL_MS 10
static volatile sig_atomic_t interrupted = 0;

struct state {
    pid_t child;
    int input;
    int exited;
    int child_code;
    int failure;
    int stopping;
    int killed;
    int owner_live;
    int input_eof;
    int64_t deadline;
    int64_t stop_deadline;
    int64_t kill_deadline;
    int64_t cleanup_ms;
    size_t limit;
    size_t total;
    size_t queued;
    unsigned char buffer[QUEUE_SIZE];
};

static void signal_owner(int number) { interrupted = number; }

static int64_t monotonic_ms(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}

static int number(const char *text, unsigned long long maximum, unsigned long long *value) {
    char *end = NULL;
    if (!text[0] || text[0] < '0' || text[0] > '9') return -1;
    errno = 0;
    *value = strtoull(text, &end, 10);
    return errno || !end || *end || !*value || *value > maximum ? -1 : 0;
}

static int nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    return flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 ? -1 : 0;
}

/* Keep fortified libc checks from treating the queue member as the whole state. */
#if defined(__GNUC__) || defined(__clang__)
__attribute__((noinline))
#endif
static ssize_t read_bytes(int fd, unsigned char *buffer, size_t capacity) {
    return read(fd, buffer, capacity);
}

static int kill_and_reap(pid_t child, int64_t cleanup_ms) {
    int64_t deadline = monotonic_ms();
    struct timespec delay = {0, 1000000};
    if (kill(child, SIGKILL) && errno != ESRCH) return -1;
    if (deadline < 0) return -1;
    deadline += cleanup_ms;
    for (;;) {
        int64_t now;
        pid_t result = waitpid(child, NULL, WNOHANG);
        if (result == child) return 0;
        if (result < 0 && errno != EINTR) return -1;
        now = monotonic_ms();
        if (now < 0 || now >= deadline) return -1;
        (void)nanosleep(&delay, NULL);
    }
}

static int release_group(int fd) {
    ssize_t result;
    do result = write(fd, "G", 1); while (result < 0 && errno == EINTR);
    return result == 1 ? 0 : -1;
}

static void stop(struct state *state, int reason, int64_t now) {
    if (reason && !state->failure) state->failure = reason;
    if (state->stopping) return;
    state->stopping = 1;
    state->stop_deadline = now + state->cleanup_ms;
    state->kill_deadline = now + state->cleanup_ms / 2;
    /* The direct child is intentionally unreaped here and reserves its PID. */
    (void)kill(-state->child, SIGTERM);
}

static int observe(struct state *state) {
    siginfo_t info;
    memset(&info, 0, sizeof(info));
    if (waitid(P_PID, (id_t)state->child, &info, WEXITED | WNOHANG | WNOWAIT) < 0) {
        return errno == EINTR ? 0 : -1;
    }
    if (info.si_pid == state->child &&
        (info.si_code == CLD_EXITED || info.si_code == CLD_KILLED || info.si_code == CLD_DUMPED)) {
        state->exited = 1;
        state->child_code = info.si_code == CLD_EXITED && (info.si_status < 124 || info.si_status == 126)
                                ? info.si_status : 128;
    }
    return 0;
}

static void receive_output(struct state *state, int64_t now) {
    ssize_t size;
    size_t available = QUEUE_SIZE - state->queued;
    if (!available) return;
    size = read_bytes(state->input, state->buffer + state->queued, available);
    if (size == 0) state->input_eof = 1;
    if (size < 0 && errno != EAGAIN && errno != EINTR) stop(state, 126, now);
    if (size <= 0) return;
    if ((size_t)size > state->limit - state->total) {
        state->queued += state->limit - state->total;
        state->total = state->limit;
        stop(state, 125, now);
    } else {
        state->total += (size_t)size;
        state->queued += (size_t)size;
    }
}

static void forward_output(struct state *state, int64_t now) {
    ssize_t size;
    if (!state->queued || !state->owner_live) return;
    size = write(STDOUT_FILENO, state->buffer, state->queued);
    if (size > 0) {
        state->queued -= (size_t)size;
        memmove(state->buffer, state->buffer + size, state->queued);
    } else if (size < 0 && errno != EAGAIN && errno != EINTR) {
        state->owner_live = 0;
        stop(state, 127, now);
    }
}

static int supervise(struct state *state) {
    for (;;) {
        int64_t now = monotonic_ms();
        struct pollfd descriptors[3] = {
            {state->owner_live ? STDIN_FILENO : -1, POLLIN | POLLHUP, 0},
            {state->input_eof ? -1 : state->input, state->queued < QUEUE_SIZE ? POLLIN | POLLHUP : 0, 0},
            {STDOUT_FILENO, state->queued ? POLLOUT : 0, 0}
        };
        if (now < 0) stop(state, 126, state->deadline);
        if (observe(state) < 0) stop(state, 126, now);
        if (interrupted) stop(state, 127, now);
        if (!state->stopping && now >= state->deadline) stop(state, 124, now);
        if (state->exited) stop(state, 0, now);
        if (state->stopping && !state->killed && now >= state->kill_deadline) {
            (void)kill(-state->child, SIGKILL);
            state->killed = 1;
        }
        /* Cleanup runs on successful exit too, so background group members die. */
        if (state->stopping && now >= state->stop_deadline) {
            if (!state->killed) (void)kill(-state->child, SIGKILL);
            if (!state->exited) return 129;
            if (!state->input_eof && state->owner_live && !state->failure) return 129;
            return state->failure ? state->failure : state->child_code;
        }
        if (state->exited && state->input_eof && state->queued == 0) {
            (void)kill(-state->child, SIGKILL);
            return state->failure ? state->failure : state->child_code;
        }
        if (poll(descriptors, 3, POLL_MS) < 0 && errno != EINTR) stop(state, 126, now);
        if (descriptors[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
            unsigned char unexpected;
            ssize_t size = read(STDIN_FILENO, &unexpected, 1);
            if (size == 0 || (size < 0 && errno != EAGAIN && errno != EINTR)) {
                state->owner_live = 0;
                state->queued = 0;
                stop(state, 127, now);
            } else if (size > 0) {
                stop(state, 126, now);
            }
        }
        if (descriptors[1].revents & (POLLIN | POLLHUP)) receive_output(state, now);
        if (descriptors[2].revents & (POLLOUT | POLLERR | POLLHUP)) forward_output(state, now);
        if (!state->owner_live) state->queued = 0;
    }
}

static int advisory_lock(const char *path) {
    int fd;
    struct stat info;
    struct flock lock;
    struct sigaction action;
    const char ready[] = "wotex_fixture_lock\n";
    if (path[0] != '/' || strlen(path) > 4096) return 126;
    fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW, 0600);
    if (fd < 0) return 126;
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size != 0 || (info.st_mode & 0077)) {
        close(fd);
        return 126;
    }
    memset(&lock, 0, sizeof(lock));
    lock.l_type = F_WRLCK;
    lock.l_whence = SEEK_SET;
    if (fcntl(fd, F_SETLK, &lock) < 0) {
        int result = errno == EACCES || errno == EAGAIN ? 130 : 126;
        close(fd);
        return result;
    }
    memset(&action, 0, sizeof(action));
    sigemptyset(&action.sa_mask);
    action.sa_handler = signal_owner;
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL) ||
        sigaction(SIGHUP, &action, NULL)) { close(fd); return 126; }
    action.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &action, NULL) || write(STDOUT_FILENO, ready, sizeof(ready) - 1) != (ssize_t)(sizeof(ready) - 1)) {
        close(fd);
        return 127;
    }
    while (!interrupted) {
        struct pollfd input = {STDIN_FILENO, POLLIN | POLLHUP, 0};
        int status = poll(&input, 1, POLL_MS);
        if (status < 0 && errno != EINTR) { close(fd); return 126; }
        if (status > 0) {
            unsigned char unexpected;
            ssize_t size = read(STDIN_FILENO, &unexpected, 1);
            close(fd);
            if (size == 1 && unexpected == 'R') {
                const char released[] = "wotex_fixture_unlocked\n";
                return write(STDOUT_FILENO, released, sizeof(released) - 1) == (ssize_t)(sizeof(released) - 1) ? 0 : 127;
            }
            return size == 0 ? 0 : 126;
        }
    }
    close(fd);
    return 127;
}

int main(int argc, char **argv) {
    unsigned long long timeout, output, cleanup;
    if (argc == 3 && !strcmp(argv[1], "--lock")) return advisory_lock(argv[2]);
    int pipes[2], group_ready[2];
    struct state state;
    struct sigaction action;
    sigset_t signal_mask;
    int result;
    if (argc < 6 || number(argv[1], 600000, &timeout) ||
        number(argv[2], 16777216, &output) || number(argv[3], 5000, &cleanup) ||
        argv[4][0] != '/' || argv[5][0] != '/') return 126;
    memset(&action, 0, sizeof(action));
    sigemptyset(&action.sa_mask);
    action.sa_handler = SIG_DFL;
    if (sigaction(SIGCHLD, &action, NULL) || sigemptyset(&signal_mask) ||
        sigprocmask(SIG_SETMASK, &signal_mask, NULL)) return 126;
    action.sa_handler = signal_owner;
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL) ||
        sigaction(SIGHUP, &action, NULL)) return 126;
    action.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &action, NULL) || pipe(pipes)) return 126;
    if (pipe(group_ready)) {
        close(pipes[0]);
        close(pipes[1]);
        return 126;
    }
    memset(&state, 0, sizeof(state));
    state.child = fork();
    if (state.child < 0) {
        close(group_ready[0]);
        close(group_ready[1]);
        close(pipes[0]);
        close(pipes[1]);
        return 126;
    }
    if (state.child == 0) {
        unsigned char ready;
        ssize_t ready_size;
        int null_input;
        close(group_ready[1]);
        action.sa_handler = SIG_DFL;
        (void)sigaction(SIGTERM, &action, NULL);
        (void)sigaction(SIGINT, &action, NULL);
        (void)sigaction(SIGHUP, &action, NULL);
        (void)sigaction(SIGPIPE, &action, NULL);
        do ready_size = read(group_ready[0], &ready, 1); while (ready_size < 0 && errno == EINTR);
        close(group_ready[0]);
        if (ready_size != 1 || ready != 'G' || getpgrp() != getpid()) _exit(126);
        if (chdir(argv[4])) _exit(126);
        null_input = open("/dev/null", O_RDONLY);
        if (null_input < 0) _exit(126);
        if (dup2(null_input, STDIN_FILENO) < 0 || dup2(pipes[1], STDOUT_FILENO) < 0 ||
            dup2(pipes[1], STDERR_FILENO) < 0) _exit(126);
        close(null_input);
        close(pipes[0]);
        close(pipes[1]);
        execv(argv[5], &argv[5]);
        _exit(126);
    }
    close(group_ready[0]);
    if ((setpgid(state.child, state.child) && getpgid(state.child) != state.child) ||
        release_group(group_ready[1])) {
        close(group_ready[1]);
        close(pipes[0]);
        close(pipes[1]);
        return kill_and_reap(state.child, (int64_t)cleanup) ? 129 : 126;
    }
    close(group_ready[1]);
    close(pipes[1]);
    state.input = pipes[0];
    state.owner_live = 1;
    state.limit = (size_t)output;
    state.cleanup_ms = (int64_t)cleanup;
    state.deadline = monotonic_ms() + (int64_t)timeout;
    /* The child cannot inspect resources or exec until the parent owns its group. */
    if (nonblocking(STDIN_FILENO) || nonblocking(STDOUT_FILENO) || nonblocking(state.input)) {
        (void)kill(-state.child, SIGKILL);
        result = 126;
    } else {
        result = supervise(&state);
    }
    (void)kill(-state.child, SIGKILL);
    close(state.input);
    /* waitid retains identity; WNOHANG keeps uninterruptible exits bounded. */
    (void)waitpid(state.child, NULL, WNOHANG);
    return result;
}
