// SPDX-License-Identifier: Apache-2.0
// Per-subscription notification sequence state of the OPC UA host
// (priv/native/publish_sequence.c): classification of each data-change
// notification against the last delivered sequence and the cache of up to 1024
// accepted sequence/digest pairs, recording of delivered notifications, duplicate
// detection and ordered Republish recovery of a 100-message gap. The unit is one
// notification.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <nanobench.h>

extern "C" {
#include "publish_sequence.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "publish_sequence: " << what << " failed\n";
  std::exit(1);
}

// The payload digest of `sequence`; the host hashes the notification payload.
void digest_of(uint32_t sequence, unsigned char digest[WOP_SEQUENCE_DIGEST]) {
  for (unsigned i = 0; i < WOP_SEQUENCE_DIGEST; ++i)
    digest[i] = static_cast<unsigned char>((sequence >> ((i % 4U) * 8U)) ^ (i * 29U));
}

// Classifies the next notification, expects delivery and records it.
void deliver(WopSequence *state) {
  unsigned char digest[WOP_SEQUENCE_DIGEST];
  const uint32_t sequence = wop_sequence_next(state->last);
  digest_of(sequence, digest);
  uint32_t first = 0;
  uint32_t missing = 0;
  check(wop_sequence_classify(state, sequence, digest, &first, &missing) == WOP_SEQUENCE_DELIVER,
        "classify as deliver");
  check(wop_sequence_record(state, sequence, digest), "record");
}

// Classifies an already delivered notification with its original payload.
void duplicate(const WopSequence *state, uint32_t sequence) {
  unsigned char digest[WOP_SEQUENCE_DIGEST];
  digest_of(sequence, digest);
  uint32_t first = 0;
  uint32_t missing = 0;
  check(wop_sequence_classify(state, sequence, digest, &first, &missing) == WOP_SEQUENCE_DUPLICATE,
        "classify as duplicate");
}

// A notification 101 ahead of the expected one: 100 missing messages are
// republished in order, then the held notification is delivered.
void recover_gap(WopSequence *state) {
  unsigned char digest[WOP_SEQUENCE_DIGEST];
  const uint32_t target = state->last + WOP_SEQUENCE_REPUBLISH + 1U;
  digest_of(target, digest);
  uint32_t first = 0;
  uint32_t missing = 0;
  check(wop_sequence_classify(state, target, digest, &first, &missing) == WOP_SEQUENCE_GAP &&
            missing == WOP_SEQUENCE_REPUBLISH,
        "classify as gap");
  check(wop_sequence_begin(state, target, digest, first, missing), "begin recovery");
  uint32_t pending = 0;
  WopRecovery recovery = WOP_RECOVERY_CONTINUE;
  while (wop_sequence_pending(state, &pending)) {
    unsigned char republished[WOP_SEQUENCE_DIGEST];
    digest_of(pending, republished);
    recovery = wop_sequence_republished(state, pending, true, pending, republished);
    check(recovery != WOP_RECOVERY_FAILED, "republished message");
  }
  check(recovery == WOP_RECOVERY_COMPLETE, "recovery complete");
  check(wop_sequence_record(state, state->target, state->target_digest), "record target");
}

} // namespace

int main() {
  auto state = std::make_unique<WopSequence>();
  wop_sequence_init(state.get(), 0);
  for (unsigned i = 0; i < WOP_SEQUENCE_CACHE; ++i) deliver(state.get());
  check(state->count == WOP_SEQUENCE_CACHE, "full cache");

  ankerl::nanobench::Bench bench;
  bench.title("publish sequence")
      .unit("notification")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));
  bench.run("in order, full 1024-entry cache", [&] { deliver(state.get()); });
  bench.run("duplicate of the latest notification", [&] { duplicate(state.get(), state->last); });
  bench.run("duplicate of the oldest cached notification",
            [&] { duplicate(state.get(), state->last - (WOP_SEQUENCE_CACHE - 1U)); });
  bench.batch(WOP_SEQUENCE_REPUBLISH + 1U).run("gap of 100 recovered by Republish", [&] {
    recover_gap(state.get());
  });

  auto fresh = std::make_unique<WopSequence>();
  bench.batch(16).run("first 16 notifications of a subscription", [&] {
    wop_sequence_init(fresh.get(), 0);
    for (unsigned i = 0; i < 16; ++i) deliver(fresh.get());
    check(fresh->last == 16, "16 delivered");
  });
  return 0;
}
