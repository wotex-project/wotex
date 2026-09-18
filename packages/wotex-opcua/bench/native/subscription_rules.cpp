// SPDX-License-Identifier: Apache-2.0
// Subscription parameter rules of the OPC UA host
// (priv/native/subscription_rules.c): wop_subscription_read on the closed
// parameter map of a parsed subscribe request, accepted and rejected, and
// wop_subscription_revision_valid on the parameters a server revised. The unit
// is one check.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <nanobench.h>

extern "C" {
#include "subscription_rules.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "subscription_rules: " << what << " failed\n";
  std::exit(1);
}

// The subscribe request the BEAM host writes (Wotex.OPCUA.Open62541.subscribe/4).
std::string subscribe(unsigned keepalive, unsigned lifetime) {
  return R"({"version":1,"generation":1,"id":"subscribe-1","operation":"subscribe",)"
         R"("parameters":{"node_id":"ns=2;s=plant/line-4/oven-2/temperature",)"
         R"("publishing_interval_ms":100,"sampling_interval_ms":50.5,"queue_size":10,)"
         R"("discard_oldest":true,"keepalive_count":)" +
      std::to_string(keepalive) + R"(,"lifetime_count":)" + std::to_string(lifetime) +
      R"(},"timeout_ms":5000,"deadline_ms":86400000})"
      "\n";
}

// A parsed line that keeps its pool.
struct Parsed {
  std::unique_ptr<unsigned char[]> pool{new unsigned char[WOP_JSON_POOL_BYTES]};
  WopJson json{};

  explicit Parsed(const std::string &line) {
    check(wop_json_read(line.data(), line.size(), pool.get(), WOP_JSON_POOL_BYTES, &json) ==
              WOP_JSON_OK,
          "wop_json_read");
  }
  ~Parsed() { wop_json_clear(&json); }
  Parsed(const Parsed &) = delete;
  Parsed &operator=(const Parsed &) = delete;
  Parsed(Parsed &&) = delete;
  Parsed &operator=(Parsed &&) = delete;

  yyjson_val *parameters() const {
    return yyjson_obj_get(yyjson_doc_get_root(json.document), "parameters");
  }
};

} // namespace

int main() {
  const Parsed accepted(subscribe(10, 30));
  // Lifetime must be at least three keepalives.
  const Parsed rejected(subscribe(10, 29));
  // A server revision within the requestable ranges, with a noninteger interval.
  const WopSubscriptionParameters revised = {100.0, 62.5, 10, true, 10, 30};

  ankerl::nanobench::Bench bench;
  bench.title("subscription rules")
      .unit("check")
      .warmup(100)
      .minEpochTime(std::chrono::milliseconds(20));
  bench.run("wop_subscription_read, accepted parameters", [&] {
    WopSubscriptionParameters parameters;
    check(wop_subscription_read(accepted.parameters(), &parameters) &&
              parameters.sampling_interval_ms == 50.5 && parameters.lifetime_count == 30,
          "accepted parameters");
  });
  bench.run("wop_subscription_read, lifetime below three keepalives", [&] {
    WopSubscriptionParameters parameters;
    check(!wop_subscription_read(rejected.parameters(), &parameters), "rejected parameters");
  });
  bench.run("wop_subscription_revision_valid, server revision",
            [&] { check(wop_subscription_revision_valid(&revised), "revision"); });
  return 0;
}
