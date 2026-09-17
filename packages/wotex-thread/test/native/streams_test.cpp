#include "streams.hpp"
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

using namespace wotex::thread;

namespace {
const std::string kSession = "0123456789abcdef0123456789abcdef";

void check_at(bool value, int line) {
  if (!value) {
    std::cerr << "check failed at line " << line << "\n";
    std::abort();
  }
}
#define check(value) check_at((value), __LINE__)

struct Harness {
  std::vector<Json> reports, controls;
  bool control_open = true;
  ReportFlow flow{kSession,
                  [this](const std::string &frame) { reports.push_back(Json::parse(frame)); return true; },
                  [this](const std::string &frame) { controls.push_back(Json::parse(frame)); return control_open; }};
  StateStreams streams{flow, [this](const std::string &frame) {
                         controls.push_back(Json::parse(frame));
                         return control_open;
                       }};
};

Json state(const char *role) {
  return {{"role", role}, {"network_name", "fixture"}, {"rloc16", nullptr},
          {"ipv6_enabled", true}, {"thread_enabled", true}, {"generation", 1}};
}
}  // namespace

int main() {
  {
    // WTH-S06/WTH-V10: registration reports nothing until its initial snapshot.
    Harness harness;
    const auto generation = harness.streams.open("s1", 64);
    check(generation == 1 && harness.reports.empty() && harness.streams.size() == 1);
    harness.streams.initial("s1", generation, state("detached"));
    check(harness.reports.size() == 1);
    const Json &initial = harness.reports[0];
    check((initial.size() == 8 && initial.at("event") == "state" && initial.at("session_generation") == kSession));
    check(initial.at("subscription_id") == "s1" && initial.at("generation") == 1 && initial.at("report_sequence") == 1);
    const Json metadata = {{"changed_flags", 0}};
    check((initial.at("value") == state("detached") && initial.at("metadata") == metadata));

    // Changes within one iteration coalesce to the latest snapshot and the OR of their flags;
    // unknown bits remain numeric.
    harness.streams.changed(4);
    harness.streams.changed(2147483648U);
    harness.streams.flush([] { return state("child"); });
    check(harness.reports.size() == 2 && harness.reports[1].at("value").at("role") == "child");
    check(harness.reports[1].at("metadata").at("changed_flags") == 2147483652U);
    harness.streams.flush([]() -> Json { std::abort(); });
    check(harness.reports.size() == 2 && harness.streams.pending_flags() == 0);

    // Cancellation writes one barrier naming the last transmitted report, and no later report.
    check(harness.streams.remove("s1", generation));
    check(harness.controls.size() == 1 && harness.controls[0].at("event") == "stream_retired");
    check(harness.controls[0].at("last_report_sequence") == 2 && harness.streams.size() == 0);
    check(!harness.streams.remove("s1", generation) && !harness.streams.failed());
    harness.streams.changed(4);
    harness.streams.flush([]() -> Json { std::abort(); });
    check(harness.reports.size() == 2);
  }
  {
    // Flags observed without listeners are not attributed to a later listener.
    Harness harness;
    harness.streams.changed(4);
    harness.streams.flush([]() -> Json { std::abort(); });
    const auto generation = harness.streams.open("late", 64);
    harness.streams.initial("late", generation, state("leader"));
    harness.streams.flush([]() -> Json { std::abort(); });
    check(harness.reports.size() == 1 && harness.reports[0].at("metadata").at("changed_flags") == 0);
  }
  {
    // WTH-B02: without credit a stream queues distinct iterations up to queue_limit, then
    // receives one terminal error followed by its barrier while other streams continue.
    Harness harness;
    const auto first = harness.streams.open("limited", 2);
    const auto second = harness.streams.open("other", 64);
    check(first == 1 && second == 2);
    harness.streams.initial("limited", first, state("detached"));
    harness.streams.initial("other", second, state("detached"));
    for (int iteration = 0; iteration < 4; ++iteration) {
      harness.streams.changed(4);
      harness.streams.flush([] { return state("child"); });
    }
    // "limited" transmits two (its credit), queues two, and overflows on the fifth report.
    check(harness.controls.size() == 2 && harness.controls[0].at("event") == "stream_error");
    check(harness.controls[0].at("code") == "queue_overflow" && harness.controls[0].at("subscription_id") == "limited");
    check(harness.controls[1].at("event") == "stream_retired" && harness.controls[1].at("last_report_sequence") == 3);
    check(harness.streams.size() == 1 && !harness.streams.failed());
    harness.streams.changed(4);
    harness.streams.flush([] { return state("router"); });
    check(harness.reports.back().at("subscription_id") == "other" && harness.reports.back().at("value").at("role") == "router");
  }
  {
    // A blocked control reservation during retirement fails the generation.
    Harness harness;
    const auto generation = harness.streams.open("s1", 64);
    harness.control_open = false;
    check(!harness.streams.remove("s1", generation) && harness.streams.failed());
  }
  {
    // Live stream capacity is bounded by the report-flow owner.
    Harness harness;
    for (int index = 0; index < 64; ++index) check(harness.streams.open("s" + std::to_string(index), 1) != 0);
    check(harness.streams.open("s64", 1) == 0);
  }
  std::cout << "WTH-S06 WTH-B02 state stream coalescing, overflow and retirement checks passed\n";
  return 0;
}
