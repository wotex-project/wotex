/* SPDX-License-Identifier: Apache-2.0
 * WOP-X05 Publish sequence traces through the production sequence state.
 * Fixture digests derive only from the input payload identity.
 */
#include "publish_sequence.h"
#include "json_codec.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if(!(condition)) return __LINE__; } while(0)

static void digest_for(uint32_t sequence, unsigned variant, unsigned char digest[WOP_SEQUENCE_DIGEST]) {
    memset(digest, 0, WOP_SEQUENCE_DIGEST);
    memcpy(digest, &sequence, sizeof(sequence));
    digest[31] = (unsigned char)variant;
}

static bool text_is(yyjson_val *value, const char *literal) {
    return yyjson_is_str(value) && strcmp(yyjson_get_str(value), literal) == 0;
}

static bool uint_array_equal(yyjson_val *expected, const uint32_t *actual, size_t count) {
    if(!yyjson_is_arr(expected) || yyjson_arr_size(expected) != count) return false;
    for(size_t i = 0; i < count; i++)
        if(yyjson_get_uint(yyjson_arr_get(expected, i)) != actual[i]) return false;
    return true;
}

/* Replays one publish_trace case; republish outcomes come from the input map. */
static int publish_trace(yyjson_val *fixture) {
    yyjson_val *input = yyjson_obj_get(fixture, "input");
    yyjson_val *expected = yyjson_obj_get(yyjson_obj_get(fixture, "expectation"), "value");
    yyjson_val *previous = yyjson_obj_get(input, "previous_sequence");
    bool same_payload = yyjson_get_bool(yyjson_obj_get(input, "same_payload"));
    static WopSequence state;
    wop_sequence_init(&state, previous ? (uint32_t)yyjson_get_uint(previous) : 0U);
    uint32_t delivered[256], requests[256];
    size_t delivered_count = 0, request_count = 0;
    const char *terminal = NULL;
    unsigned char digest[WOP_SEQUENCE_DIGEST];
    yyjson_val *sequences = yyjson_obj_get(input, "sequences");
    size_t index, count;
    yyjson_val *item;
    unsigned seen = 0;
    yyjson_arr_foreach(sequences, index, count, item) {
        if(terminal) break;
        uint32_t sequence = (uint32_t)yyjson_get_uint(item);
        digest_for(sequence, same_payload ? 0U : seen++, digest);
        uint32_t first = 0, missing = 0;
        switch(wop_sequence_classify(&state, sequence, digest, &first, &missing)) {
        case WOP_SEQUENCE_DELIVER:
            CHECK(wop_sequence_record(&state, sequence, digest));
            delivered[delivered_count++] = sequence;
            break;
        case WOP_SEQUENCE_DUPLICATE:
            break;
        case WOP_SEQUENCE_GAP: {
            CHECK(wop_sequence_begin(&state, sequence, digest, first, missing));
            uint32_t pending = 0;
            while(!terminal && wop_sequence_pending(&state, &pending)) {
                requests[request_count++] = pending;
                char key[16];
                (void)snprintf(key, sizeof(key), "%" PRIu32, pending);
                yyjson_val *outcome = yyjson_obj_get(yyjson_obj_get(input, "republish"), key);
                unsigned char missing_digest[WOP_SEQUENCE_DIGEST];
                digest_for(pending, 0U, missing_digest);
                WopRecovery recovery = wop_sequence_republished(&state, pending, text_is(outcome, "ok"),
                                                                pending, missing_digest);
                if(recovery == WOP_RECOVERY_FAILED) {
                    terminal = "sequence_gap";
                } else {
                    delivered[delivered_count++] = pending;
                    if(recovery == WOP_RECOVERY_COMPLETE) {
                        CHECK(wop_sequence_record(&state, state.target, state.target_digest));
                        delivered[delivered_count++] = state.target;
                    }
                }
            }
            break;
        }
        default:
            terminal = "sequence_gap";
            break;
        }
    }
    CHECK(uint_array_equal(yyjson_obj_get(expected, "delivered_sequences"), delivered, delivered_count));
    CHECK(uint_array_equal(yyjson_obj_get(expected, "republish_requests"), requests, request_count));
    yyjson_val *expected_terminal = yyjson_obj_get(expected, "terminal");
    CHECK(terminal ? text_is(expected_terminal, terminal) : yyjson_is_null(expected_terminal));
    return 0;
}

static int matrix(void) {
    static WopSequence state;
    unsigned char digest[WOP_SEQUENCE_DIGEST], other[WOP_SEQUENCE_DIGEST];
    uint32_t first = 0, missing = 0;
    wop_sequence_init(&state, 0);
    digest_for(1, 0, digest);
    CHECK(wop_sequence_classify(&state, 0, digest, &first, &missing) == WOP_SEQUENCE_INVALID);
    CHECK(wop_sequence_classify(&state, 1, digest, &first, &missing) == WOP_SEQUENCE_DELIVER);
    CHECK(!wop_sequence_record(&state, 2, digest));
    CHECK(wop_sequence_record(&state, 1, digest));
    digest_for(1, 7, other);
    CHECK(wop_sequence_classify(&state, 1, other, &first, &missing) == WOP_SEQUENCE_CONFLICT);
    /* 100 missing messages recover; 101 are terminal. */
    digest_for(102, 0, digest);
    CHECK(wop_sequence_classify(&state, 102, digest, &first, &missing) == WOP_SEQUENCE_GAP &&
          first == 2 && missing == 100);
    digest_for(103, 0, digest);
    CHECK(wop_sequence_classify(&state, 103, digest, &first, &missing) == WOP_SEQUENCE_TOO_LARGE);
    /* Accept 1024 contiguous messages; the oldest then leaves the cache. */
    for(uint32_t sequence = 2; sequence <= 1025; sequence++) {
        digest_for(sequence, 0, digest);
        CHECK(wop_sequence_record(&state, sequence, digest));
    }
    CHECK(state.count == WOP_SEQUENCE_CACHE);
    digest_for(2, 0, digest);
    CHECK(wop_sequence_classify(&state, 2, digest, &first, &missing) == WOP_SEQUENCE_DUPLICATE);
    digest_for(1, 0, digest);
    CHECK(wop_sequence_classify(&state, 1, digest, &first, &missing) == WOP_SEQUENCE_STALE);
    /* A mismatched or out-of-order Republish fails and ends recovery. */
    digest_for(1028, 0, digest);
    CHECK(wop_sequence_classify(&state, 1028, digest, &first, &missing) == WOP_SEQUENCE_GAP &&
          wop_sequence_begin(&state, 1028, digest, first, missing));
    CHECK(!wop_sequence_begin(&state, 1028, digest, first, missing));
    digest_for(1027, 0, other);
    CHECK(wop_sequence_republished(&state, 1026, true, 1027, other) == WOP_RECOVERY_FAILED);
    CHECK(!state.recovering && state.last == 1025);
    /* Wrap from UINT32_MAX to one. */
    wop_sequence_init(&state, UINT32_MAX - 1U);
    digest_for(UINT32_MAX, 0, digest);
    CHECK(wop_sequence_classify(&state, UINT32_MAX, digest, &first, &missing) == WOP_SEQUENCE_DELIVER &&
          wop_sequence_record(&state, UINT32_MAX, digest));
    digest_for(2, 0, digest);
    CHECK(wop_sequence_classify(&state, 2, digest, &first, &missing) == WOP_SEQUENCE_GAP &&
          first == 1 && missing == 1);
    CHECK(wop_sequence_next(UINT32_MAX) == 1U);
    return 0;
}

int main(int argc, char **argv) {
    if(argc == 2 && strcmp(argv[1], "--matrix") == 0) {
        int line = matrix();
        printf("{\"status\":\"%s\",\"line\":%d}\n", line ? "failed" : "passed", line);
        return line ? 1 : 0;
    }
    if(argc != 3) return 64;
    FILE *file = fopen(argv[1], "rb");
    if(!file) return 66;
    static char corpus[1 << 20];
    size_t length = fread(corpus, 1, sizeof(corpus), file);
    fclose(file);
    yyjson_doc *document = yyjson_read(corpus, length, 0);
    yyjson_val *cases = yyjson_obj_get(yyjson_doc_get_root(document), "cases");
    yyjson_val *selected = NULL, *candidate;
    size_t index, count;
    yyjson_arr_foreach(cases, index, count, candidate) {
        if(text_is(yyjson_obj_get(candidate, "id"), argv[2])) selected = candidate;
    }
    int line = selected && text_is(yyjson_obj_get(selected, "operation"), "publish_trace") ?
               publish_trace(selected) : -1;
    printf("{\"status\":\"%s\",\"case\":\"%s\",\"line\":%d}\n",
           line == 0 ? "passed" : "failed", argv[2], line);
    yyjson_doc_free(document);
    return line == 0 ? 0 : 1;
}
