/* SPDX-License-Identifier: Apache-2.0 */
#include "frame.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct probe { struct wco_json *json; unsigned calls, accepted; };

static int parse(const char *line, size_t length, void *argument) {
    struct probe *probe = argument;
    probe->calls++;
    if (wco_json_parse(probe->json, line, length) != WCO_JSON_OK) return 0;
    probe->accepted++;
    return 1;
}

static void erased(const struct wco_frame *frame) {
    assert(frame->used == 0);
    for (size_t index = 0; index < sizeof(frame->bytes); index++) assert(frame->bytes[index] == 0);
}

static void splitting(struct wco_frame *frame, struct probe *probe) {
    const char *line = "{\"version\":1,\"event\":\"ready\",\"label\":\"snowman \xe2\x98\x83\"}\n";
    size_t length = strlen(line);
    for (size_t split = 0; split <= length; split++) {
        wco_frame_init(frame); probe->calls = probe->accepted = 0;
        assert(wco_frame_feed(frame, line, split, parse, probe));
        assert(probe->accepted == (split == length ? 1u : 0u));
        assert(wco_frame_feed(frame, line + split, length - split, parse, probe));
        assert(probe->calls == 1 && probe->accepted == 1);
        assert(frame->peak == length);
        erased(frame);
        assert(wco_frame_eof(frame));
        assert(!wco_frame_feed(frame, line, length, parse, probe));
        assert(probe->calls == 1);
    }
    wco_frame_init(frame); probe->calls = probe->accepted = 0;
    for (size_t index = 0; index < length; index++)
        assert(wco_frame_feed(frame, line + index, 1, parse, probe));
    assert(probe->accepted == 1 && frame->peak == length);
    erased(frame);
    puts("WCO-C07 WCO-N03: every UTF-8 byte split and one-byte delivery preserve exact single frame");
}

static void coalescing(struct wco_frame *frame, struct probe *probe) {
    const char *lines = "{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n";
    size_t length = strlen(lines);
    for (size_t split = 0; split <= length; split++) {
        wco_frame_init(frame); probe->calls = probe->accepted = 0;
        assert(wco_frame_feed(frame, lines, split, parse, probe));
        assert(wco_frame_feed(frame, lines + split, length - split, parse, probe));
        assert(probe->calls == 3 && probe->accepted == 3 && frame->peak == 8);
        erased(frame);
    }
    /* Callback failure terminates this generation before any later valid frame. */
    lines = "{}\n{\"id\":1,\"id\":2}\n{}\n";
    wco_frame_init(frame); probe->calls = probe->accepted = 0;
    assert(!wco_frame_feed(frame, lines, strlen(lines), parse, probe));
    assert(frame->failed && probe->calls == 2 && probe->accepted == 1);
    erased(frame);
    assert(!wco_frame_feed(frame, "{}\n", 3, parse, probe));
    assert(probe->calls == 2);
    puts("WCO-C07 WCO-N03: coalesced frames stay ordered; malformed middle frame permanently closes ingress");
}

static void boundaries(struct wco_frame *frame, struct probe *probe) {
    char *line = malloc(WCO_JSON_FRAME_MAX + 1);
    assert(line);
    memcpy(line, "{\"x\":\"", 6);
    memset(line + 6, 'a', WCO_JSON_FRAME_MAX - 9);
    memcpy(line + WCO_JSON_FRAME_MAX - 3, "\"}\n", 3);
    wco_frame_init(frame); probe->calls = probe->accepted = 0;
    assert(wco_frame_feed(frame, line, WCO_JSON_FRAME_MAX - 1, parse, probe));
    assert(probe->calls == 0);
    assert(wco_frame_feed(frame, line + WCO_JSON_FRAME_MAX - 1, 1, parse, probe));
    assert(probe->accepted == 1 && frame->peak == WCO_JSON_FRAME_MAX);
    erased(frame);
    /* 131073 bytes without a delimiter never allocate or retain the extra byte. */
    memset(line, 'a', WCO_JSON_FRAME_MAX + 1);
    wco_frame_init(frame); probe->calls = probe->accepted = 0;
    assert(!wco_frame_feed(frame, line, WCO_JSON_FRAME_MAX + 1, parse, probe));
    assert(frame->failed && frame->peak == WCO_JSON_FRAME_MAX && probe->calls == 0);
    erased(frame);
    wco_frame_init(frame);
    assert(wco_frame_feed(frame, line, WCO_JSON_FRAME_MAX, parse, probe));
    assert(!wco_frame_feed(frame, "\n", 1, parse, probe));
    assert(frame->peak == WCO_JSON_FRAME_MAX && probe->calls == 0);
    erased(frame);
    free(line);
    puts("WCO-C07 WCO-N03: 128-KiB line accepted; plus-one contiguous/split ingress fails with bounded erased buffer");
}

static void terminal(struct wco_frame *frame, struct probe *probe) {
    const char *truncated[] = {"{", "{}", "{\"secret\":\"material\"}"};
    for (size_t index = 0; index < sizeof(truncated) / sizeof(truncated[0]); index++) {
        wco_frame_init(frame); probe->calls = probe->accepted = 0;
        assert(wco_frame_feed(frame, truncated[index], strlen(truncated[index]), parse, probe));
        assert(!wco_frame_eof(frame));
        assert(frame->failed && probe->calls == 0);
        erased(frame);
        assert(!wco_frame_feed(frame, "\n", 1, parse, probe));
    }
    wco_frame_init(frame);
    assert(wco_frame_feed(frame, NULL, 0, parse, probe));
    assert(!wco_frame_feed(frame, NULL, 1, parse, probe));
    erased(frame);
    wco_frame_init(frame);
    assert(!wco_frame_feed(frame, "{}\n", 3, NULL, probe));
    erased(frame);
    wco_frame_init(frame);
    assert(wco_frame_eof(frame));
    assert(!wco_frame_eof(frame));
    assert(!wco_frame_feed(frame, "{}\n", 3, parse, probe));
    puts("WCO-C07 WCO-N03: truncated/clean EOF and invalid callbacks cannot revive terminated generation");
}

int main(void) {
    struct wco_frame *frame = calloc(1, sizeof(*frame));
    struct probe probe = { .json = wco_json_new() };
    assert(frame && probe.json);
    splitting(frame, &probe);
    coalescing(frame, &probe);
    boundaries(frame, &probe);
    terminal(frame, &probe);
    wco_json_free(probe.json);
    free(frame);
    return 0;
}
