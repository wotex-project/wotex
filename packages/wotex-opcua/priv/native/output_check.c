/* SPDX-License-Identifier: Apache-2.0
 * Bounded output queue, credit and control-allowance assertions.
 */
#include "output.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(condition) do { if (!(condition)) return __LINE__; } while (0)

static WopIpcCredit grant(uint64_t sequence, uint64_t messages, uint64_t bytes) {
    WopIpcCredit credit = {7, sequence, messages, bytes};
    return credit;
}

static int nonblocking_pipe(int descriptors[2]) {
    if (pipe(descriptors) != 0) return 0;
    int flags = fcntl(descriptors[1], F_GETFL);
    return flags >= 0 && fcntl(descriptors[1], F_SETFL, flags | O_NONBLOCK) == 0;
}

static char *frame(size_t size, char fill) {
    char *bytes = malloc(size);
    if (!bytes) return NULL;
    memset(bytes, fill, size - 1);
    bytes[size - 1] = '\n';
    return bytes;
}

static size_t drain(int descriptor, char *buffer, size_t capacity) {
    int flags = fcntl(descriptor, F_GETFL);
    (void)fcntl(descriptor, F_SETFL, flags | O_NONBLOCK);
    size_t used = 0;
    for (;;) {
        if (used == capacity) break;
        ssize_t count = read(descriptor, buffer + used, capacity - used);
        if (count > 0) used += (size_t)count;
        else if (count < 0 && errno == EINTR) continue;
        else break;
    }
    (void)fcntl(descriptor, F_SETFL, flags);
    return used;
}

/* Normal output waits for explicit initial credit and never exceeds it. */
static int credit_gates_emission(void) {
    int pipe_fds[2];
    CHECK(nonblocking_pipe(pipe_fds));
    WopOutput output;
    wop_output_init(&output);
    char *report = frame(1024, 'r');
    CHECK(report);
    /* NOLINTNEXTLINE(clang-analyzer-unix.Malloc): a failed step fails the check, which exits */
    CHECK(wop_output_normal(&output, report, 1024) == WOP_OUTPUT_OK);
    CHECK(!wop_output_writable(&output));
    CHECK(wop_output_flush(&output, pipe_fds[1]) == WOP_OUTPUT_OK);
    CHECK(output.emitted_messages == 0);

    WopIpcCredit initial = grant(1, 2, 2048);
    CHECK(wop_output_credit(&output, &initial) == WOP_OUTPUT_OK);
    for (int i = 0; i < 2; i++)
        CHECK(wop_output_normal(&output, report, 1024) == WOP_OUTPUT_OK);
    CHECK(wop_output_flush(&output, pipe_fds[1]) == WOP_OUTPUT_OK);
    CHECK(output.emitted_messages == 2 && output.emitted_bytes == 2048);
    CHECK(output.count == 1 && !wop_output_writable(&output));
    CHECK(output.used_messages == 2 && output.used_bytes == 2048);

    /* Replenishment above the consumed amount or a replayed sequence fails. */
    WopIpcCredit excessive = grant(2, 3, 1024);
    CHECK(wop_output_credit(&output, &excessive) == WOP_OUTPUT_INVALID);
    WopIpcCredit replay = grant(1, 1, 1024);
    CHECK(wop_output_credit(&output, &replay) == WOP_OUTPUT_INVALID);
    WopIpcCredit foreign = {8, 2, 1, 1024};
    CHECK(wop_output_credit(&output, &foreign) == WOP_OUTPUT_INVALID);
    WopIpcCredit skipped = grant(3, 1, 1024);
    CHECK(wop_output_credit(&output, &skipped) == WOP_OUTPUT_INVALID);
    WopIpcCredit replenish = grant(2, 1, 1024);
    CHECK(wop_output_credit(&output, &replenish) == WOP_OUTPUT_OK);
    CHECK(wop_output_flush(&output, pipe_fds[1]) == WOP_OUTPUT_OK);
    CHECK(output.emitted_messages == 3 && output.count == 0);
    CHECK(wop_output_drained(&output));

    char buffer[4096];
    CHECK(drain(pipe_fds[0], buffer, sizeof(buffer)) == 3072);
    free(report);
    wop_output_clear(&output);
    close(pipe_fds[0]);
    close(pipe_fds[1]);
    return 0;
}

/* The first grant must be sequence one; outstanding credit cannot exceed maxima. */
static int initial_credit_bounds(void) {
    WopOutput output;
    wop_output_init(&output);
    WopIpcCredit late = grant(2, 1, 1);
    CHECK(wop_output_credit(&output, &late) == WOP_OUTPUT_INVALID);
    WopIpcCredit empty = grant(1, 0, 1);
    CHECK(wop_output_credit(&output, &empty) == WOP_OUTPUT_INVALID);
    WopIpcCredit full = grant(1, 16, 262144);
    CHECK(wop_output_credit(&output, &full) == WOP_OUTPUT_OK);
    output.used_messages = 1;
    output.used_bytes = 1;
    WopIpcCredit over = grant(2, 1, 1);
    CHECK(wop_output_credit(&output, &over) == WOP_OUTPUT_INVALID);
    output.sequence = UINT64_MAX;
    WopIpcCredit wrapped = grant(0, 1, 1);
    CHECK(wop_output_credit(&output, &wrapped) == WOP_OUTPUT_INVALID);
    wop_output_clear(&output);
    return 0;
}

/* Frame count, aggregate bytes and envelope shape bound queue admission. */
static int queue_bounds(void) {
    WopOutput output;
    wop_output_init(&output);
    char *small = frame(16, 'q');
    char *large = frame(WOP_JSON_FRAME_BYTES, 'l');
    /* NOLINTNEXTLINE(clang-analyzer-unix.Malloc): an allocation failure fails the check, which exits */
    CHECK(small && large);
    for (size_t i = 0; i < WOP_OUTPUT_FRAMES; i++)
        CHECK(wop_output_normal(&output, small, 16) == WOP_OUTPUT_OK);
    CHECK(wop_output_normal(&output, small, 16) == WOP_OUTPUT_OVERFLOW);
    CHECK(output.count == WOP_OUTPUT_FRAMES && output.pending_bytes == 1024);
    wop_output_clear(&output);

    for (size_t i = 0; i < WOP_OUTPUT_BYTES / WOP_JSON_FRAME_BYTES; i++)
        CHECK(wop_output_normal(&output, large, WOP_JSON_FRAME_BYTES) == WOP_OUTPUT_OK);
    CHECK(output.pending_bytes == WOP_OUTPUT_BYTES);
    CHECK(wop_output_normal(&output, small, 16) == WOP_OUTPUT_OVERFLOW);
    wop_output_clear(&output);

    char unterminated[4] = {'a', 'b', 'c', 'd'};
    char embedded[4] = {'a', '\n', 'c', '\n'};
    char *oversized = frame(WOP_JSON_FRAME_BYTES + 1, 'o');
    CHECK(oversized);
    CHECK(wop_output_normal(&output, unterminated, 4) == WOP_OUTPUT_INVALID);
    CHECK(wop_output_normal(&output, embedded, 4) == WOP_OUTPUT_INVALID);
    CHECK(wop_output_normal(&output, oversized, WOP_JSON_FRAME_BYTES + 1) == WOP_OUTPUT_INVALID);
    CHECK(output.count == 0 && output.pending_bytes == 0);
    free(small);
    free(large);
    free(oversized);
    return 0;
}

/* Backpressure retains one partial frame; terminal control follows it intact. */
static int partial_write_then_terminal(void) {
    int pipe_fds[2];
    CHECK(nonblocking_pipe(pipe_fds));
    WopOutput output;
    wop_output_init(&output);
    WopIpcCredit credit = grant(1, 16, 262144);
    CHECK(wop_output_credit(&output, &credit) == WOP_OUTPUT_OK);
    char *first = frame(WOP_JSON_FRAME_BYTES, 'a');
    char *second = frame(512, 'b');
    /* NOLINTNEXTLINE(clang-analyzer-unix.Malloc): an allocation failure fails the check, which exits */
    CHECK(first && second);
    CHECK(wop_output_normal(&output, first, WOP_JSON_FRAME_BYTES) == WOP_OUTPUT_OK);
    CHECK(wop_output_normal(&output, second, 512) == WOP_OUTPUT_OK);
    CHECK(wop_output_flush(&output, pipe_fds[1]) == WOP_OUTPUT_OK);
    CHECK(output.active.bytes != NULL);
    CHECK(output.active_sent > 0 && output.active_sent < WOP_JSON_FRAME_BYTES);
    CHECK(output.count == 1);

    static const char terminal[] =
        "{\"version\":1,\"generation\":7,\"event\":\"terminal\",\"error\":"
        "{\"code\":\"receiver_overflow\",\"phase\":\"exchange\",\"effect\":\"none\"}}\n";
    CHECK(wop_output_control(&output, terminal, sizeof(terminal) - 1, true) == WOP_OUTPUT_OK);
    CHECK(output.count == 0);
    CHECK(wop_output_normal(&output, second, 512) == WOP_OUTPUT_INVALID);
    CHECK(wop_output_control(&output, terminal, sizeof(terminal) - 1, true) ==
          WOP_OUTPUT_INVALID);

    size_t capacity = WOP_JSON_FRAME_BYTES + sizeof(terminal);
    char *received = malloc(capacity);
    CHECK(received);
    size_t used = 0;
    for (int rounds = 0; rounds < 1024 && !wop_output_drained(&output); rounds++) {
        used += drain(pipe_fds[0], received + used, capacity - used);
        CHECK(wop_output_flush(&output, pipe_fds[1]) == WOP_OUTPUT_OK);
    }
    used += drain(pipe_fds[0], received + used, capacity - used);
    CHECK(wop_output_drained(&output));
    CHECK(used == WOP_JSON_FRAME_BYTES + sizeof(terminal) - 1);
    CHECK(memcmp(received, first, WOP_JSON_FRAME_BYTES) == 0);
    CHECK(memcmp(received + WOP_JSON_FRAME_BYTES, terminal, sizeof(terminal) - 1) == 0);
    CHECK(output.emitted_messages == 1 && output.pending_bytes == 0);
    free(received);
    free(first);
    free(second);
    wop_output_clear(&output);
    close(pipe_fds[0]);
    close(pipe_fds[1]);
    return 0;
}

/* Ready and terminal share one 4096-byte allowance; a failed descriptor is closed. */
static int control_allowance_and_closed_descriptor(void) {
    WopOutput output;
    wop_output_init(&output);
    char *ready = frame(4000, 'c');
    char *terminal = frame(97, 't');
    char *exact = frame(96, 't');
    /* NOLINTNEXTLINE(clang-analyzer-unix.Malloc): an allocation failure fails the check, which exits */
    CHECK(ready && terminal && exact);
    CHECK(wop_output_control(&output, ready, 4000, false) == WOP_OUTPUT_OK);
    CHECK(wop_output_control(&output, terminal, 97, true) == WOP_OUTPUT_INVALID);
    CHECK(!output.terminal);
    CHECK(wop_output_control(&output, exact, 96, true) == WOP_OUTPUT_OK);

    int pipe_fds[2];
    CHECK(nonblocking_pipe(pipe_fds));
    close(pipe_fds[0]);
    CHECK(wop_output_flush(&output, pipe_fds[1]) == WOP_OUTPUT_CLOSED);
    close(pipe_fds[1]);
    free(ready);
    free(terminal);
    free(exact);
    wop_output_clear(&output);
    return 0;
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    struct {
        const char *name;
        int (*run)(void);
    } cases[] = {
        {"credit_gates_emission", credit_gates_emission},
        {"initial_credit_bounds", initial_credit_bounds},
        {"queue_bounds", queue_bounds},
        {"partial_write_then_terminal", partial_write_then_terminal},
        {"control_allowance_and_closed_descriptor", control_allowance_and_closed_descriptor},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int line = cases[i].run();
        if (line) {
            printf("{\"status\":\"failed\",\"case\":\"%s\",\"line\":%d}\n", cases[i].name, line);
            return 1;
        }
    }
    printf("{\"status\":\"passed\",\"cases\":%zu}\n", sizeof(cases) / sizeof(cases[0]));
    return 0;
}
