/* SPDX-License-Identifier: Apache-2.0
 * Derived from Wotex OPC UA ca2c4afc2fe8d4afa42b7621363c567da89ce288.
 * Standalone pipe-level fault checks. The tested consumer is independent of an
 * Erlang Port driver, so blocked reads here really apply kernel backpressure.
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
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif

struct run { pid_t guardian, sdk, background; int input, output; int status; char file[4096]; };
static const char *guardian, *self, *workspace;
static unsigned serial;
static int inherit_signals;
static size_t sent_bytes, received_bytes;
static int64_t cleanup_elapsed, guardian_exit_elapsed, guardian_post_reap_elapsed;
static int instrumented_exit_allowance;
static int direct_reaped, background_stopped;
static int input_limit, output_limit;
static pid_t active_guardians[32];
static void stop_active(void) {
    /* These are only direct, unreaped children; no recycled PID lookup. */
    for (size_t index = 0; index < sizeof(active_guardians)/sizeof(active_guardians[0]); ++index)
        if (active_guardians[index] > 0) (void)kill(active_guardians[index], SIGTERM);
}
static void fail(const char *message) {
    int saved_errno = errno; stop_active();
    fprintf(stderr, "custody check: %s (%d)\n", message, saved_errno); exit(1);
}
static void on_alarm(int ignored) { (void)ignored; stop_active(); _exit(121); }
#define CHECK(value, message) do { if (!(value)) fail(message); } while (0)

static int64_t now(void) {
    struct timespec value;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &value) == 0, "clock");
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}
static void sleep_ms(int milliseconds) {
    struct timespec value = {milliseconds / 1000, (milliseconds % 1000) * 1000000L};
    while (nanosleep(&value, &value) < 0 && errno == EINTR) {}
}
static void nonblock(int fd) {
    int flags = fcntl(fd, F_GETFL);
    CHECK(flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0, "nonblocking");
}
static unsigned char pattern(size_t offset) { return (unsigned char)(offset % 256); }
static void forever(void) { signal(SIGTERM, SIG_IGN); for (;;) pause(); }
static void write_all(int fd, const unsigned char *data, size_t count) {
    while (count) {
        ssize_t size = write(fd, data, count);
        if (size < 0 && errno == EINTR) continue;
        CHECK(size > 0, "SDK write"); data += size; count -= (size_t)size;
    }
}
static void produce(size_t count) {
    unsigned char bytes[4096];
    size_t offset = 0;
    while (offset < count) {
        size_t size = count - offset < sizeof(bytes) ? count - offset : sizeof(bytes);
        for (size_t index = 0; index < size; ++index) bytes[index] = pattern(offset + index);
        write_all(STDOUT_FILENO, bytes, size); offset += size;
    }
}
static int sdk(int argc, char **argv) {
    FILE *file;
    pid_t background = 0;
    CHECK(argc == 5, "SDK arguments");
    const char *mode = argv[2];
    if (!strcmp(mode, "background")) {
        background = fork(); CHECK(background >= 0, "SDK fork");
        if (!background) forever();
    }
    if (!strcmp(mode, "signals")) {
        struct sigaction action; sigset_t mask;
        CHECK(sigaction(SIGCHLD, NULL, &action) == 0 && action.sa_handler == SIG_DFL &&
              !(action.sa_flags & SA_NOCLDWAIT), "child wait disposition reset");
        CHECK(sigprocmask(SIG_SETMASK, NULL, &mask) == 0 && !sigismember(&mask, SIGTERM) &&
              !sigismember(&mask, SIGCHLD) && !sigismember(&mask, SIGPIPE), "child signal mask reset");
        CHECK(getpgrp() == getpid(), "child group established before execution");
    }
    signal(SIGTERM, SIG_IGN);
    file = fopen(argv[3], "wx"); CHECK(file != NULL, "SDK PID file");
    fprintf(file, "%ld %ld\n", (long)getpid(), (long)background); CHECK(fclose(file) == 0, "SDK PID flush");
    if (!strcmp(mode, "stopped")) { raise(SIGSTOP); forever(); }
    if (!strcmp(mode, "hang")) forever();
    if (!strcmp(mode, "closed_output")) { close(STDOUT_FILENO); forever(); }
    if (!strcmp(mode, "diagnostic")) { write_all(STDERR_FILENO, (const unsigned char *)"private SDK diagnostic", 22); return 0; }
    if (!strcmp(mode, "fd")) {
        errno = 0; CHECK(fcntl(127, F_GETFD) == -1 && errno == EBADF, "inherited descriptor closed");
        produce(513); return 0;
    }
    if (!strcmp(mode, "signal")) { raise(SIGKILL); return 1; }
    if (!strcmp(mode, "reserved")) return 129;
    size_t count = (size_t)strtoul(argv[4], NULL, 10);
    if (!strcmp(mode, "signals") || !strcmp(mode, "final") || !strcmp(mode, "background") || !strcmp(mode, "flood")) {
        produce(count); return 0;
    }
    if (!strcmp(mode, "duplex")) produce(count);
    size_t received = 0;
    while (received < count) {
        unsigned char bytes[113];
        size_t capacity = count - received < sizeof(bytes) ? count - received : sizeof(bytes);
        ssize_t size = read(STDIN_FILENO, bytes, capacity);
        if (size < 0 && errno == EINTR) continue;
        CHECK(size > 0, "SDK input completeness");
        for (ssize_t index = 0; index < size; ++index) CHECK(bytes[index] == pattern(received + (size_t)index), "SDK exact input");
        write_all(STDOUT_FILENO, bytes, (size_t)size); received += (size_t)size;
    }
    return !strcmp(mode, "echo7") ? 7 : 0;
}

static struct run start(const char *mode, size_t count, int input_capacity, int output_capacity,
                        int prefill, const char *bad) {
    struct run run;
    int input[2], output[2];
    char in[24], out[24], amount[24];
    memset(&run, 0, sizeof(run)); run.status = -1;
    input_limit = input_capacity; output_limit = output_capacity;
    CHECK(snprintf(run.file, sizeof(run.file), "%s/child-%u.pid", workspace, ++serial) > 0, "PID path");
    CHECK(pipe(input) == 0 && pipe(output) == 0, "owner pipes");
    nonblock(input[1]); nonblock(output[0]);
    if (prefill) {
        unsigned char bytes[4096] = {0};
        nonblock(output[1]);
        while (write(output[1], bytes, sizeof(bytes)) > 0) {}
        CHECK(errno == EAGAIN, "prefill blocked pipe");
    }
    snprintf(in, sizeof(in), "%d", input_capacity);
    snprintf(out, sizeof(out), "%d", output_capacity);
    snprintf(amount, sizeof(amount), "%zu", count);
    run.guardian = fork(); CHECK(run.guardian >= 0, "guardian fork");
    if (!run.guardian) {
        CHECK(dup2(input[0], STDIN_FILENO) >= 0 && dup2(output[1], STDOUT_FILENO) >= 0, "guardian standard pipes");
        close(input[0]); close(input[1]); close(output[0]); close(output[1]);
        /* Deliberately pass an unintended descriptor without CLOEXEC. */
        int extra = open("/dev/null", O_RDONLY); CHECK(extra >= 0, "canary open");
        CHECK(dup2(extra, 127) == 127, "canary high descriptor"); close(extra);
        struct rlimit descriptors;
        CHECK(getrlimit(RLIMIT_NOFILE, &descriptors) == 0, "descriptor limit");
        descriptors.rlim_cur = 64;
        CHECK(setrlimit(RLIMIT_NOFILE, &descriptors) == 0, "lower descriptor limit");
        const char *cleanup = "500", *cwd = workspace, *executable = self;
        if (bad && !strcmp(bad, "cleanup")) cleanup = "1001";
        if (bad && !strcmp(bad, "zero")) cleanup = "0";
        if (bad && !strcmp(bad, "cwd")) cwd = "relative";
        if (bad && !strcmp(bad, "executable")) executable = "relative";
        if (bad && !strcmp(bad, "missing")) executable = "/wotex-custody-executable-must-not-exist";
        if (bad && !strcmp(bad, "missing-cwd")) cwd = "/wotex-custody-directory-must-not-exist";
        char *args[270] = {(char *)guardian, (char *)cleanup, in, out, (char *)cwd,
            (char *)executable, "--sdk", (char *)mode, run.file, amount, NULL};
        char large[8194]; memset(large, 'x', sizeof(large)); large[sizeof(large)-1] = '\0';
        if (bad && !strcmp(bad, "large")) args[9] = large;
        if (bad && !strcmp(bad, "many")) {
            for (int index = 6; index < 263; ++index) args[index] = "x";
            args[263] = NULL;
        }
        if (bad && !strcmp(bad, "aggregate")) {
            large[8192] = '\0';
            for (int index = 6; index < 15; ++index) args[index] = large;
            args[15] = NULL;
        }
        if (inherit_signals) {
            struct sigaction action; sigset_t mask;
            memset(&action, 0, sizeof(action)); sigemptyset(&action.sa_mask);
            action.sa_handler = SIG_IGN; action.sa_flags = SA_NOCLDWAIT; sigfillset(&mask);
            CHECK(sigaction(SIGCHLD, &action, NULL) == 0 &&
                  sigprocmask(SIG_SETMASK, &mask, NULL) == 0, "inherited signal state");
        }
        execv(guardian, args); _exit(120);
    }
    size_t slot;
    for (slot = 0; slot < sizeof(active_guardians)/sizeof(active_guardians[0]); ++slot)
        if (!active_guardians[slot]) { active_guardians[slot] = run.guardian; break; }
    CHECK(slot < sizeof(active_guardians)/sizeof(active_guardians[0]), "fixture guardian capacity");
    close(input[0]); close(output[1]); run.input = input[1]; run.output = output[0]; return run;
}
static void ready(struct run *run) {
    int64_t deadline = now() + 3000;
    while (now() < deadline) {
        FILE *file = fopen(run->file, "r");
        if (file) {
            long sdk_pid, background;
            int count = fscanf(file, "%ld %ld", &sdk_pid, &background); fclose(file);
            if (count == 2) { run->sdk = (pid_t)sdk_pid; run->background = (pid_t)background; return; }
        }
        sleep_ms(2);
    }
    fail("SDK readiness file");
}
static int observe(struct run *run) {
    int status; pid_t result;
    if (run->status >= 0) return 1;
    result = waitpid(run->guardian, &status, WNOHANG);
    CHECK(result >= 0 || errno == EINTR, "wait guardian");
    if (result != run->guardian) return 0;
    for (size_t index = 0; index < sizeof(active_guardians)/sizeof(active_guardians[0]); ++index)
        if (active_guardians[index] == run->guardian) active_guardians[index] = 0;
    CHECK(WIFEXITED(status), "guardian normal exit"); run->status = WEXITSTATUS(status); return 1;
}
static void wait_status(struct run *run, int expected, int64_t deadline) {
    while (!observe(run) && now() < deadline + instrumented_exit_allowance) sleep_ms(2);
    if (run->status != expected) fprintf(stderr, "expected status %d, received %d\n", expected, run->status);
    CHECK(run->status == expected, "exact guardian status");
}
static void release(struct run *run) {
    if (run->input >= 0) close(run->input);
    if (run->output >= 0) close(run->output);
    if (run->sdk > 0) {
        int status; errno = 0;
        /* On Linux the test driver adopts any child the guardian failed to
         * reap. A successful check must have no such adopted direct SDK. */
        CHECK(waitpid(run->sdk, &status, WNOHANG) == -1 && errno == ECHILD, "SDK reaped by guardian");
        CHECK(kill(run->sdk, 0) == -1 && errno == ESRCH, "SDK no longer exists"); direct_reaped++;
    }
    if (run->background > 0) {
        int64_t deadline = now() + 1000;
        for (;;) {
#ifdef __linux__
            int status; pid_t result = waitpid(run->background, &status, WNOHANG);
            if (result == run->background) { CHECK(WIFSIGNALED(status), "group member terminated"); break; }
#else
            if (kill(run->background, 0) < 0 && errno == ESRCH) break;
#endif
            CHECK(now() < deadline, "owned background group member stopped"); sleep_ms(2);
        }
        background_stopped++;
    }
    unlink(run->file);
}
static void transfer(struct run *run, size_t input_count, size_t output_count, size_t fragment,
                     int slow, int expected) {
    size_t sent = 0, received = 0; int eof = 0;
    int64_t deadline = now() + 10000;
    while (!eof || run->status < 0) {
        struct pollfd fds[2] = {{run->input, sent < input_count ? POLLOUT : 0, 0},
            {run->output, POLLIN, 0}};
        CHECK(now() < deadline, "transfer deadline");
        CHECK(poll(fds, 2, 10) >= 0 || errno == EINTR, "transfer poll");
        if (fds[0].revents & POLLOUT) {
            unsigned char bytes[4096];
            size_t count = input_count - sent < fragment ? input_count - sent : fragment;
            if (count > sizeof(bytes)) count = sizeof(bytes);
            for (size_t index = 0; index < count; ++index) bytes[index] = pattern(sent + index);
            ssize_t size = write(run->input, bytes, count);
            CHECK(size >= 0 || errno == EAGAIN || errno == EINTR, "owner input write");
            if (size > 0) sent += (size_t)size;
        }
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            unsigned char bytes[4096];
            ssize_t size = read(run->output, bytes, slow ? 511 : sizeof(bytes));
            CHECK(size >= 0 || errno == EAGAIN || errno == EINTR, "owner output read");
            if (size == 0) eof = 1;
            if (size > 0) {
                for (ssize_t index = 0; index < size; ++index)
                    CHECK(bytes[index] == pattern(received + (size_t)index), "exact output bytes");
                received += (size_t)size;
                CHECK(received <= output_count, "output byte ceiling");
                if (slow) sleep_ms(1);
            }
        }
        observe(run);
    }
    if (sent != input_count || received != output_count || run->status != expected)
        fprintf(stderr, "transfer sent=%zu/%zu received=%zu/%zu status=%d/%d\n", sent, input_count, received, output_count, run->status, expected);
    CHECK(sent == input_count && received == output_count && run->status == expected, "complete exact transfer");
    sent_bytes += sent; received_bytes += received;
}
static int sdk_reaped(struct run *run) {
    int status;
    if (kill(run->sdk, 0) == 0) return 0;
    CHECK(errno == ESRCH, "SDK disappearance");
    errno = 0;
    CHECK(waitpid(run->sdk, &status, WNOHANG) == -1 && errno == ECHILD,
          "SDK reaped by guardian, not adopted by independent driver");
    return 1;
}
static void record_cleanup(int64_t began, int64_t reaped_at) {
    int64_t exited_at = now();
    CHECK(reaped_at - began <= 500, "SDK exit and reap allowance");
    CHECK(exited_at - began <= 500 + instrumented_exit_allowance, "guardian exit allowance");
    if (reaped_at - began > cleanup_elapsed) cleanup_elapsed = reaped_at - began;
    if (exited_at - began > guardian_exit_elapsed) guardian_exit_elapsed = exited_at - began;
    if (exited_at - reaped_at > guardian_post_reap_elapsed) guardian_post_reap_elapsed = exited_at - reaped_at;
}
static void end_owner(struct run *run, int expected) {
    int64_t began = now(); close(run->input); run->input = -1;
    while (!sdk_reaped(run)) { CHECK(now() - began <= 500, "SDK reap deadline"); sleep_ms(2); }
    int64_t reaped_at = now();
    wait_status(run, expected, began + 500);
    record_cleanup(began, reaped_at);
}
static void fill_input(struct run *run) {
    unsigned char data[4096] = {0};
    int64_t deadline = now() + 1000;
    for (;;) {
        ssize_t size = write(run->input, data, sizeof(data));
        if (size < 0 && errno == EAGAIN) break;
        CHECK(size > 0 && now() < deadline, "input reaches finite backpressure"); sent_bytes += (size_t)size;
    }
    sleep_ms(30);
    while (write(run->input, data, sizeof(data)) > 0) sent_bytes += sizeof(data);
    CHECK(errno == EAGAIN, "full ingress remains blocked");
}
static void check_case(const char *name) {
    struct run run;
    if (!strcmp(name, "WCO-G01")) {
        const char *bad[] = {"cleanup", "zero", "cwd", "executable", "missing", "missing-cwd", "large", "many", "aggregate"};
        for (size_t index = 0; index < sizeof(bad)/sizeof(bad[0]); ++index) {
            run = start("fd", 0, 17, 23, 0, bad[index]); wait_status(&run, 126, now()+3000);
            CHECK(access(run.file, F_OK) < 0, "invalid input never executes SDK"); release(&run);
        }
        int limits[][2] = {{0, 23}, {262145, 23}, {17, 0}, {17, 262145}};
        for (size_t index = 0; index < sizeof(limits)/sizeof(limits[0]); ++index) {
            run = start("fd", 0, limits[index][0], limits[index][1], 0, NULL);
            wait_status(&run, 126, now()+3000); CHECK(access(run.file, F_OK) < 0, "invalid byte capacity"); release(&run);
        }
        run = start("fd", 0, 17, 23, 0, NULL); ready(&run); transfer(&run, 0, 513, 1, 0, 0); release(&run);
    } else if (!strcmp(name, "WCO-G02")) {
        run = start("echo7", 4097, 17, 23, 0, NULL); ready(&run); transfer(&run, 4097, 4097, 7, 0, 7); release(&run);
    } else if (!strcmp(name, "WCO-G03")) {
        run = start("duplex", 1048576, 3072, 4096, 0, NULL); ready(&run);
        transfer(&run, 1048576, 2097152, 257, 0, 0); release(&run);
    } else if (!strcmp(name, "WCO-G04")) {
        run = start("stopped", 0, 17, 23, 0, NULL); ready(&run); fill_input(&run); end_owner(&run, 127); release(&run);
    } else if (!strcmp(name, "WCO-G05")) {
        run = start("flood", 67108864, 17, 23, 0, NULL); ready(&run); sleep_ms(100);
        CHECK(!observe(&run), "blocked producer cannot complete 64 MiB"); end_owner(&run, 127); release(&run);
    } else if (!strcmp(name, "WCO-G06")) {
        run = start("flood", 67108864, 17, 23, 0, NULL); ready(&run);
        close(run.output); run.output = -1; wait_status(&run, 127, now()+1000); release(&run);
        run = start("diagnostic", 0, 17, 23, 0, NULL); ready(&run);
        transfer(&run, 0, 0, 1, 0, 131); release(&run);
        run = start("closed_output", 0, 17, 23, 0, NULL); ready(&run);
        transfer(&run, 0, 0, 1, 0, 128); release(&run);
    } else if (!strcmp(name, "WCO-G07")) {
        run = start("final", 131072, 17, 23, 0, NULL); ready(&run); sleep_ms(30);
        transfer(&run, 0, 131072, 1, 1, 0); release(&run);
        run = start("final", 4096, 17, 23, 1, NULL); ready(&run);
        wait_status(&run, 129, now()+1000); release(&run);
        run = start("background", 4096, 17, 23, 0, NULL); ready(&run);
        transfer(&run, 0, 4096, 1, 0, 0); release(&run);
        run = start("reserved", 0, 17, 23, 0, NULL); ready(&run);
        transfer(&run, 0, 0, 1, 0, 128); release(&run);
        run = start("signal", 0, 17, 23, 0, NULL); ready(&run);
        transfer(&run, 0, 0, 1, 0, 128); release(&run);
    } else if (!strcmp(name, "WCO-G08")) {
        run = start("hang", 0, 17, 23, 0, NULL); ready(&run);
        struct run other = start("echo7", 1024, 17, 23, 0, NULL); ready(&other);
        end_owner(&run, 127); release(&run); CHECK(kill(other.sdk, 0) == 0, "other SDK survives");
        transfer(&other, 1024, 1024, 7, 0, 7); release(&other);
    } else if (!strcmp(name, "WCO-G09")) {
        run = start("stopped", 0, 17, 23, 0, NULL); ready(&run);
        int64_t caller_began = now(); sleep_ms(400);
        int64_t began = now(); close(run.input); run.input = -1;
        while (!sdk_reaped(&run)) {
            CHECK(now() - caller_began < 1000 && now() - began <= 500, "one total caller deadline");
            CHECK(kill(run.guardian, SIGTERM) == 0 || errno == ESRCH, "repeat stop signal"); sleep_ms(5);
        }
        int64_t reaped_at = now();
        wait_status(&run, 127, began + 500);
        record_cleanup(began, reaped_at);
        CHECK(now() - caller_began <= 1000 + instrumented_exit_allowance, "caller plus named instrumentation allowance");
        release(&run);
    } else if (!strcmp(name, "WCO-G10")) {
        for (int iteration = 0; iteration < 200; ++iteration) {
            inherit_signals = iteration % 2;
            run = start("signals", 17, 17, 23, 0, NULL); ready(&run);
            transfer(&run, 0, 17, 1, 0, 0); release(&run);
        }
    } else if (!strcmp(name, "WCO-G11")) {
        inherit_signals = 1;
        run = start("hang", 0, 17, 23, 0, NULL); ready(&run);
        int64_t began = now();
        CHECK(kill(run.guardian, SIGTERM) == 0, "inherited guardian TERM");
        while (!sdk_reaped(&run)) { CHECK(now() - began <= 500, "SDK reap deadline"); sleep_ms(2); }
        int64_t reaped_at = now(); wait_status(&run, 127, began + 500);
        record_cleanup(began, reaped_at); release(&run);
    } else fail("unknown case");
}
int main(int argc, char **argv) {
    self = argv[0];
    if (argc > 1 && !strcmp(argv[1], "--sdk")) return sdk(argc, argv);
    CHECK(argc == 4 || (argc == 5 && !strcmp(argv[4], "--leak-audit")), "check arguments");
    instrumented_exit_allowance = argc == 5 ? 1000 : 0;
    guardian = argv[1]; workspace = argv[3];
    CHECK(signal(SIGPIPE, SIG_IGN) != SIG_ERR, "test SIGPIPE");
#ifdef __linux__
    CHECK(prctl(PR_SET_CHILD_SUBREAPER, 1) == 0, "test-only orphan audit");
#endif
    CHECK(signal(SIGALRM, on_alarm) != SIG_ERR, "test deadline signal");
    /* Leak scans of 200 separate short processes need an explicit aggregate
     * fixture allowance. Per-child cleanup deadlines remain unchanged. */
    alarm(instrumented_exit_allowance ? 180 : 20); check_case(argv[2]);
    printf("{\"case\":\"%s\",\"status\":\"passed\",\"sent_bytes\":%zu,\"received_bytes\":%zu,"
           "\"cleanup_ms\":%lld,\"guardian_exit_ms\":%lld,\"guardian_post_reap_ms\":%lld,"
           "\"input_capacity\":%d,\"output_capacity\":%d,"
           "\"instrumented_exit_allowance_ms\":%d,\"direct_reaped\":%d,\"background_stopped\":%d}\n",
           argv[2], sent_bytes, received_bytes, (long long)cleanup_elapsed,
           (long long)guardian_exit_elapsed, (long long)guardian_post_reap_elapsed,
           input_limit, output_limit,
           instrumented_exit_allowance, direct_reaped, background_stopped);
    return 0;
}
