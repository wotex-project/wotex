/* SPDX-License-Identifier: Apache-2.0 */
#include "output.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void wop_output_init(WopOutput *output) {
    if (output) memset(output, 0, sizeof(*output));
}

void wop_output_clear(WopOutput *output) {
    if (!output) return;
    for (size_t i = 0; i < output->count; i++)
        free(output->queue[(output->head + i) % WOP_OUTPUT_FRAMES].bytes);
    free(output->active.bytes);
    memset(output, 0, sizeof(*output));
}

static bool line(const char *bytes, size_t size, size_t maximum) {
    return bytes && size >= 2 && size <= maximum && bytes[size - 1] == '\n' &&
           !memchr(bytes, '\n', size - 1);
}

WopOutputStatus wop_output_control(WopOutput *output, const char *bytes, size_t size,
                                   bool terminal) {
    if (!output || output->terminal || !line(bytes, size, WOP_CONTROL_BYTES) ||
        size > WOP_CONTROL_BYTES - output->control_size)
        return WOP_OUTPUT_INVALID;
    memcpy(output->control + output->control_size, bytes, size);
    output->control_size += size;
    if (terminal) {
        output->terminal = true;
        for (size_t i = 0; i < output->count; i++) {
            WopOutputFrame *frame = &output->queue[(output->head + i) % WOP_OUTPUT_FRAMES];
            output->pending_bytes -= frame->size;
            free(frame->bytes);
            frame->bytes = NULL;
            frame->size = 0;
        }
        output->head = 0;
        output->count = 0;
    }
    return WOP_OUTPUT_OK;
}

WopOutputStatus wop_output_credit(WopOutput *output, const WopIpcCredit *credit) {
    if (!output || !credit || output->terminal || credit->generation == 0 ||
        credit->messages == 0 || credit->messages > WOP_CREDIT_MESSAGES ||
        credit->bytes == 0 || credit->bytes > WOP_CREDIT_BYTES)
        return WOP_OUTPUT_INVALID;
    if (output->generation == 0) {
        if (credit->sequence != 1) return WOP_OUTPUT_INVALID;
        output->generation = credit->generation;
        output->sequence = 1;
        output->credit_messages = credit->messages;
        output->credit_bytes = credit->bytes;
        return WOP_OUTPUT_OK;
    }
    if (credit->generation != output->generation || output->sequence == UINT64_MAX ||
        credit->sequence != output->sequence + 1 ||
        credit->messages > output->used_messages || credit->bytes > output->used_bytes ||
        credit->messages > WOP_CREDIT_MESSAGES - output->credit_messages ||
        credit->bytes > WOP_CREDIT_BYTES - output->credit_bytes)
        return WOP_OUTPUT_INVALID;
    output->sequence = credit->sequence;
    output->credit_messages += credit->messages;
    output->credit_bytes += credit->bytes;
    output->used_messages -= credit->messages;
    output->used_bytes -= credit->bytes;
    return WOP_OUTPUT_OK;
}

WopOutputStatus wop_output_normal(WopOutput *output, const char *bytes, size_t size) {
    if (!output || output->terminal || !line(bytes, size, WOP_JSON_FRAME_BYTES))
        return WOP_OUTPUT_INVALID;
    if (output->count == WOP_OUTPUT_FRAMES ||
        size > WOP_OUTPUT_BYTES - output->pending_bytes)
        return WOP_OUTPUT_OVERFLOW;
    char *copy = malloc(size);
    if (!copy) return WOP_OUTPUT_OVERFLOW;
    memcpy(copy, bytes, size);
    WopOutputFrame *frame = &output->queue[(output->head + output->count) % WOP_OUTPUT_FRAMES];
    frame->bytes = copy;
    frame->size = size;
    output->count++;
    if (output->count > output->peak_count) output->peak_count = output->count;
    output->pending_bytes += size;
    return WOP_OUTPUT_OK;
}

typedef enum { WRITE_DONE, WRITE_BLOCKED, WRITE_FAILED } WriteStatus;

static WriteStatus write_some(int descriptor, const char *bytes, size_t size, size_t *sent) {
    while (*sent < size) {
        ssize_t count = write(descriptor, bytes + *sent, size - *sent);
        if (count > 0) {
            *sent += (size_t)count;
        } else if (count < 0 && errno == EINTR) {
            continue;
        } else if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            return WRITE_BLOCKED;
        } else {
            return WRITE_FAILED;
        }
    }
    return WRITE_DONE;
}

static bool front_credited(const WopOutput *output) {
    if (output->count == 0 || output->terminal) return false;
    const WopOutputFrame *front = &output->queue[output->head];
    return output->credit_messages > 0 && output->credit_bytes >= front->size;
}

WopOutputStatus wop_output_flush(WopOutput *output, int descriptor) {
    if (!output) return WOP_OUTPUT_INVALID;
    for (;;) {
        if (output->active.bytes) {
            WriteStatus status = write_some(descriptor, output->active.bytes,
                                            output->active.size, &output->active_sent);
            if (status == WRITE_BLOCKED) return WOP_OUTPUT_OK;
            if (status == WRITE_FAILED) return WOP_OUTPUT_CLOSED;
            output->pending_bytes -= output->active.size;
            output->emitted_messages++;
            output->emitted_bytes += output->active.size;
            free(output->active.bytes);
            output->active.bytes = NULL;
            output->active.size = 0;
            output->active_sent = 0;
            continue;
        }
        if (output->control_sent < output->control_size) {
            WriteStatus status = write_some(descriptor, output->control,
                                            output->control_size, &output->control_sent);
            if (status == WRITE_BLOCKED) return WOP_OUTPUT_OK;
            if (status == WRITE_FAILED) return WOP_OUTPUT_CLOSED;
            continue;
        }
        if (!front_credited(output)) return WOP_OUTPUT_OK;
        output->active = output->queue[output->head];
        output->queue[output->head].bytes = NULL;
        output->queue[output->head].size = 0;
        output->head = (output->head + 1) % WOP_OUTPUT_FRAMES;
        output->count--;
        output->credit_messages--;
        output->credit_bytes -= output->active.size;
        output->used_messages++;
        output->used_bytes += output->active.size;
    }
}

bool wop_output_writable(const WopOutput *output) {
    return output && (output->active.bytes || output->control_sent < output->control_size ||
                      front_credited(output));
}

bool wop_output_drained(const WopOutput *output) {
    return output && !output->active.bytes && output->control_sent == output->control_size &&
           output->count == 0;
}
