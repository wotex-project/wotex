/* SPDX-License-Identifier: Apache-2.0
 * Bidirectional runtime custody. Process-group identity retention derives from
 * Wotex Modbus command.c at 018f419b0644cfecc83891551d10b5c8d771d7c6.
 * See runtime-guardian.md for the opaque-stream and process-ownership contract.
 */
#define _POSIX_C_SOURCE 200809L
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAX_QUEUE 262144U
#define POLL_MS 10

struct queue {
    unsigned char *bytes;
    size_t size;
    size_t capacity;
};

struct custody {
    pid_t child;
    int input;
    int output;
    int diagnostic;
    int owner_live;
    int output_eof;
    int exited;
    int child_status;
    int failure;
    int stopping;
    int terminated;
    int killed;
    int custody_lost;
    int64_t cleanup_ms;
    int64_t term_at;
    int64_t kill_at;
    int64_t stop_at;
    struct queue to_sdk;
    struct queue to_owner;
};

static volatile sig_atomic_t interrupted;

static void on_signal(int signal_number) { interrupted = signal_number; }

static int64_t monotonic_ms(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 ||
        (uint64_t)now.tv_sec > (uint64_t)INT64_MAX / 1000U) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int positive(const char *text, unsigned long long maximum,
                    unsigned long long *value) {
    char *end;
    if (!text || text[0] < '0' || text[0] > '9') return -1;
    errno = 0;
    *value = strtoull(text, &end, 10);
    return errno || *end || !*value || *value > maximum ? -1 : 0;
}

static int path(const char *text) {
    return text && text[0] == '/' && strnlen(text, 4097) <= 4096;
}

static int arguments(int argc, char **argv) {
    size_t total = 0;
    if (argc < 6 || argc - 6 > 256 || !path(argv[4]) || !path(argv[5])) return -1;
    for (int index = 6; index < argc; ++index) {
        size_t size = strnlen(argv[index], 8193);
        if (size > 8192 || size > 65536 - total) return -1;
        total += size;
    }
    return 0;
}

static int nonblocking(int descriptor) {
    int flags = fcntl(descriptor, F_GETFL);
    return flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0 ? -1 : 0;
}

static void close_fd(int *descriptor) {
    if (*descriptor >= 0) (void)close(*descriptor);
    *descriptor = -1;
}

static int owned_pipe(int descriptors[2]) {
    if (pipe(descriptors) < 0) return -1;
    if (fcntl(descriptors[0], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(descriptors[1], F_SETFD, FD_CLOEXEC) < 0) {
        close_fd(&descriptors[0]); close_fd(&descriptors[1]);
        return -1;
    }
    return 0;
}

static int close_inherited(void) {
    /* Inventory the actual open descriptors, including descriptors above a
     * subsequently lowered RLIMIT_NOFILE. No thread opens descriptors here. */
#if defined(__APPLE__)
    const char *directory = "/dev/fd";
#elif defined(__linux__)
    const char *directory = "/proc/self/fd";
#else
    return -1;
#endif
    DIR *inventory;
    struct dirent *entry;
    int descriptor, result = 0;
    for (descriptor = 0; descriptor < 3; ++descriptor)
        if (fcntl(descriptor, F_GETFD) < 0) return -1;
    inventory = opendir(directory);
    if (!inventory) return -1;
    descriptor = dirfd(inventory);
    if (descriptor < 0 || fcntl(descriptor, F_SETFD, FD_CLOEXEC) < 0) result = -1;
    while (!result) {
        char *end;
        long number;
        errno = 0;
        entry = readdir(inventory);
        if (!entry) { if (errno) result = -1; break; }
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
        errno = 0;
        number = strtol(entry->d_name, &end, 10);
        if (errno || *end || number < 0 || number > INT_MAX) { result = -1; break; }
        if (number < 3 || number == descriptor) continue;
        if (fcntl((int)number, F_SETFD, FD_CLOEXEC) < 0 || close((int)number) < 0)
            result = -1;
    }
    if (closedir(inventory) < 0) result = -1;
    return result;
}

static void group_signal(struct custody *state, int signal_number) {
    /* Only the unreaped direct child pins this process-group identity. */
    if (state->child > 0 && !state->custody_lost)
        (void)kill(-state->child, signal_number);
}

static void stop(struct custody *state, int reason, int64_t now) {
    if (reason && !state->failure) state->failure = reason;
    if (state->failure) {
        state->to_owner.size = 0;
        close_fd(&state->output);
        state->output_eof = 1;
    }
    if (state->stopping) return;
    state->stopping = 1;
    state->to_sdk.size = 0;
    close_fd(&state->input);
    state->stop_at = now + state->cleanup_ms;
    state->term_at = now + (state->cleanup_ms / 4 < 25 ? state->cleanup_ms / 4 : 25);
    state->kill_at = now + state->cleanup_ms / 2;
}

static int observe(struct custody *state) {
    siginfo_t status;
    if (state->exited) return 0;
    memset(&status, 0, sizeof(status));
    if (waitid(P_PID, (id_t)state->child, &status, WEXITED | WNOHANG | WNOWAIT) < 0) {
        if (errno == EINTR) return 0;
        state->custody_lost = 1;
        return -1;
    }
    /* Darwin can return CLD_STOPPED even with WEXITED. A stop/continue is not
     * process exit and must never authorize successful reap or stream closure. */
    if (status.si_pid == state->child &&
        (status.si_code == CLD_EXITED || status.si_code == CLD_KILLED ||
         status.si_code == CLD_DUMPED)) {
        state->exited = 1;
        state->child_status = status.si_code == CLD_EXITED &&
            (status.si_status < 124 || status.si_status == 126) ? status.si_status : 128;
    }
    return 0;
}

static int reap(struct custody *state, int outcome) {
    int status;
    pid_t reaped;
    group_signal(state, SIGKILL);
    if (!state->exited || state->custody_lost) return 129;
    reaped = waitpid(state->child, &status, WNOHANG);
    /* An interrupted final reap is explicitly unverified, never an unbounded
     * retry that silently extends the absolute cleanup deadline. */
    if (reaped != state->child) return 129;
    state->child = -1;
    return outcome;
}

static void read_owner(struct custody *state, short events, int64_t now) {
    size_t capacity;
    ssize_t size;
    if (!state->owner_live) return;
    /* HUP remains observable even with unread data and a completely full queue. */
    if (events & (POLLHUP | POLLERR | POLLNVAL)) {
        state->owner_live = 0;
        stop(state, 127, now);
        return;
    }
    if (state->stopping) return;
    capacity = state->to_sdk.capacity - state->to_sdk.size;
    if (!(events & POLLIN) || !capacity) return;
    size = read(STDIN_FILENO, state->to_sdk.bytes + state->to_sdk.size, capacity);
    if (size > 0) state->to_sdk.size += (size_t)size;
    else if (size == 0 || (errno != EAGAIN && errno != EINTR)) {
        state->owner_live = 0;
        stop(state, 127, now);
    }
}

static void read_sdk(struct custody *state, short events, int64_t now) {
    size_t capacity;
    ssize_t size;
    if (state->output < 0) return;
    if (events & (POLLERR | POLLNVAL)) { stop(state, 126, now); return; }
    capacity = state->to_owner.capacity - state->to_owner.size;
    if (!(events & (POLLIN | POLLHUP)) || !capacity) return;
    size = read(state->output, state->to_owner.bytes + state->to_owner.size, capacity);
    if (size > 0) state->to_owner.size += (size_t)size;
    else if (size == 0) {
        state->output_eof = 1;
        close_fd(&state->output);
    } else if (errno != EAGAIN && errno != EINTR) stop(state, 126, now);
}

static void read_diagnostic(struct custody *state, short events, int64_t now) {
    unsigned char bytes[256];
    ssize_t size;
    if (state->diagnostic < 0 || !(events & (POLLIN | POLLHUP | POLLERR | POLLNVAL))) return;
    if (events & (POLLERR | POLLNVAL)) { stop(state, 126, now); return; }
    size = read(state->diagnostic, bytes, sizeof(bytes));
    if (size > 0) stop(state, 131, now);
    if (size == 0) close_fd(&state->diagnostic);
    else if (size < 0 && errno != EAGAIN && errno != EINTR) stop(state, 126, now);
}

static void write_queue(struct custody *state, struct queue *queue, int descriptor,
                        short events, int receiver, int64_t now) {
    ssize_t size;
    if (descriptor < 0) return;
    if (events & (POLLHUP | POLLERR | POLLNVAL)) {
        if (receiver) state->owner_live = 0;
        stop(state, receiver ? 127 : 126, now);
        return;
    }
    if (!(events & POLLOUT) || !queue->size) return;
    size = write(descriptor, queue->bytes, queue->size);
    if (size > 0) {
        queue->size -= (size_t)size;
        memmove(queue->bytes, queue->bytes + size, queue->size);
    } else if (size < 0 && errno != EAGAIN && errno != EINTR) {
        if (receiver) state->owner_live = 0;
        stop(state, receiver ? 127 : 126, now);
    }
}

static int poll_wait(const struct custody *state, int64_t now) {
    int64_t remaining;
    if (!state->stopping) return POLL_MS;
    remaining = state->stop_at - now;
    if (!state->terminated && state->term_at - now < remaining) remaining = state->term_at - now;
    if (!state->killed && state->kill_at - now < remaining) remaining = state->kill_at - now;
    return remaining <= 0 ? 0 : remaining < POLL_MS ? (int)remaining : POLL_MS;
}

static void owner_liveness(struct custody *state, int64_t now) {
    struct pollfd descriptors[2] = {
        {state->owner_live ? STDIN_FILENO : -1, POLLIN, 0},
        {state->owner_live ? STDOUT_FILENO : -1, POLLOUT, 0}
    };
    /* Darwin's poll omits pipe HUP when events is zero. Probe the directions
     * without consuming data, then omit full queues from the blocking poll.
     * This observes EOF within POLL_MS without spinning on unread requests. */
    if (poll(descriptors, 2, 0) < 0) {
        if (errno != EINTR) stop(state, 126, now);
        return;
    }
    read_owner(state, descriptors[0].revents & (POLLHUP | POLLERR | POLLNVAL), now);
    write_queue(state, &state->to_owner, STDOUT_FILENO,
                descriptors[1].revents & (POLLHUP | POLLERR | POLLNVAL), 1, now);
}

static int supervise(struct custody *state) {
    for (;;) {
        int64_t now = monotonic_ms();
        struct pollfd descriptors[5];
        int polled;
        if (now < 0) return reap(state, 129);
        if (observe(state) < 0) return 129;
        if (interrupted) stop(state, 127, now);
        owner_liveness(state, now);
        /* EOF starts the same finite teardown even when an SDK closes stdout
         * but remains alive. Child status and stream completion stay separate. */
        if (state->exited || state->output_eof) stop(state, 0, now);
        if (state->stopping && !state->terminated && now >= state->term_at) {
            group_signal(state, SIGTERM); state->terminated = 1;
        }
        if (state->stopping && !state->killed && now >= state->kill_at) {
            group_signal(state, SIGKILL); state->killed = 1;
        }
        if (state->stopping && state->exited && state->output_eof &&
            state->diagnostic < 0 && !state->to_owner.size)
            return reap(state, state->failure ? state->failure : state->child_status);
        if (state->stopping && now >= state->stop_at) return reap(state, 129);

        descriptors[0] = (struct pollfd){state->owner_live && !state->stopping &&
            state->to_sdk.size < state->to_sdk.capacity ? STDIN_FILENO : -1, POLLIN, 0};
        descriptors[1] = (struct pollfd){state->output,
            state->to_owner.size < state->to_owner.capacity ? POLLIN : 0, 0};
        descriptors[2] = (struct pollfd){state->to_sdk.size ? state->input : -1, POLLOUT, 0};
        descriptors[3] = (struct pollfd){state->owner_live ? STDOUT_FILENO : -1,
            state->to_owner.size ? POLLOUT : 0, 0};
        descriptors[4] = (struct pollfd){state->diagnostic, POLLIN, 0};
        polled = poll(descriptors, 5, poll_wait(state, now));
        if (polled < 0 && errno != EINTR) { stop(state, 126, now); continue; }
        now = monotonic_ms();
        if (now < 0) return reap(state, 129);
        read_owner(state, descriptors[0].revents, now);
        read_diagnostic(state, descriptors[4].revents, now);
        read_sdk(state, descriptors[1].revents, now);
        if (!state->stopping)
            write_queue(state, &state->to_sdk, state->input, descriptors[2].revents, 0, now);
        if (state->owner_live)
            write_queue(state, &state->to_owner, STDOUT_FILENO, descriptors[3].revents, 1, now);
    }
}

static int install_signals(void) {
    struct sigaction action;
    sigset_t mask;
    memset(&action, 0, sizeof(action));
    sigemptyset(&action.sa_mask);
    sigemptyset(&mask);
    if (sigprocmask(SIG_SETMASK, &mask, NULL) < 0) return -1;
    action.sa_handler = SIG_DFL;
    if (sigaction(SIGCHLD, &action, NULL) < 0) return -1;
    action.sa_handler = on_signal;
    if (sigaction(SIGTERM, &action, NULL) < 0 || sigaction(SIGINT, &action, NULL) < 0 ||
        sigaction(SIGHUP, &action, NULL) < 0) return -1;
    action.sa_handler = SIG_IGN;
    return sigaction(SIGPIPE, &action, NULL);
}

static void child_exec(int input[2], int output[2], int diagnostic[2],
                       int group_ready[2], char **argv) {
    unsigned char ready;
    ssize_t ready_size;
    close(group_ready[1]);
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    sigemptyset(&action.sa_mask);
    action.sa_handler = SIG_DFL;
    if (sigaction(SIGTERM, &action, NULL) < 0 || sigaction(SIGINT, &action, NULL) < 0 ||
        sigaction(SIGHUP, &action, NULL) < 0 || sigaction(SIGPIPE, &action, NULL) < 0) _exit(126);
    do ready_size = read(group_ready[0], &ready, 1); while (ready_size < 0 && errno == EINTR);
    close(group_ready[0]);
    if (ready_size != 1 || ready != 'G' || getpgrp() != getpid()) _exit(126);
    if (chdir(argv[4]) < 0) _exit(126);
    if (dup2(input[0], STDIN_FILENO) < 0 || dup2(output[1], STDOUT_FILENO) < 0 ||
        dup2(diagnostic[1], STDERR_FILENO) < 0) _exit(126);
    for (int index = 0; index < 2; ++index) {
        close(input[index]); close(output[index]); close(diagnostic[index]);
    }
    execv(argv[5], &argv[5]);
    _exit(126);
}

/* Before the release byte, this direct child cannot have executed or forked.
 * Failure therefore signals only its unreaped PID, never a guessed group. */
static int abort_startup(pid_t child, int64_t cleanup_ms) {
    int64_t started = monotonic_ms();
    (void)kill(child, SIGKILL);
    if (started < 0) return 129;
    int64_t deadline = started + cleanup_ms;
    for (;;) {
        pid_t result = waitpid(child, NULL, WNOHANG);
        if (result == child) return 126;
        if (result < 0 && errno != EINTR) return 129;
        int64_t current = monotonic_ms();
        if (current < 0 || current >= deadline) return 129;
        struct timespec pause = {0, 1000000};
        (void)nanosleep(&pause, NULL);
    }
}

int main(int argc, char **argv) {
    unsigned long long cleanup, input_capacity, output_capacity;
    int input[2] = {-1, -1}, output[2] = {-1, -1}, diagnostic[2] = {-1, -1};
    int group_ready[2] = {-1, -1};
    struct custody state;
    int outcome = 126;
    if (arguments(argc, argv) || positive(argv[1], 1000, &cleanup) ||
        positive(argv[2], MAX_QUEUE, &input_capacity) ||
        positive(argv[3], MAX_QUEUE, &output_capacity) || monotonic_ms() < 0) return 126;
    memset(&state, 0, sizeof(state));
    state.child = -1;
    state.input = state.output = state.diagnostic = -1;
    state.owner_live = 1;
    state.cleanup_ms = (int64_t)cleanup;
    state.to_sdk.capacity = (size_t)input_capacity;
    state.to_owner.capacity = (size_t)output_capacity;
    state.to_sdk.bytes = malloc(state.to_sdk.capacity);
    state.to_owner.bytes = malloc(state.to_owner.capacity);
    if (!state.to_sdk.bytes || !state.to_owner.bytes || close_inherited() < 0 ||
        install_signals() < 0 ||
        nonblocking(STDIN_FILENO) < 0 || nonblocking(STDOUT_FILENO) < 0 ||
        owned_pipe(input) < 0 || owned_pipe(output) < 0 || owned_pipe(diagnostic) < 0 ||
        owned_pipe(group_ready) < 0) goto done;
    state.child = fork();
    if (state.child < 0) goto done;
    if (state.child == 0) child_exec(input, output, diagnostic, group_ready, argv);
    close_fd(&group_ready[0]);
    if ((setpgid(state.child, state.child) < 0 && getpgid(state.child) != state.child) ||
        write(group_ready[1], "G", 1) != 1) {
        close_fd(&group_ready[1]);
        state.custody_lost = 1;
        outcome = abort_startup(state.child, state.cleanup_ms);
        state.child = -1;
        goto done;
    }
    close_fd(&group_ready[1]);
    close_fd(&input[0]); close_fd(&output[1]); close_fd(&diagnostic[1]);
    state.input = input[1]; input[1] = -1;
    state.output = output[0]; output[0] = -1;
    state.diagnostic = diagnostic[0]; diagnostic[0] = -1;
    if (nonblocking(state.input) < 0 || nonblocking(state.output) < 0 ||
        nonblocking(state.diagnostic) < 0) {
        stop(&state, 126, monotonic_ms());
    }
    outcome = supervise(&state);
done:
    group_signal(&state, SIGKILL);
    close_fd(&state.input); close_fd(&state.output); close_fd(&state.diagnostic);
    for (int index = 0; index < 2; ++index) {
        close_fd(&input[index]); close_fd(&output[index]); close_fd(&diagnostic[index]);
        close_fd(&group_ready[index]);
    }
    free(state.to_sdk.bytes); free(state.to_owner.bytes);
    return outcome;
}
