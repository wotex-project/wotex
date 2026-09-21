#include "management.hpp"
#include <cassert>
#include <chrono>
#include <fstream>
#include <string>

using namespace wotex::thread;
using namespace std::chrono_literals;

namespace {
Request request(const char *id, const char *operation, std::uint32_t timeout_ms) {
  return {id, operation, Json::object(), timeout_ms};
}

Json fixture(const Json &corpus, const std::string &id) {
  for (const auto &item : corpus.at("cases")) {
    if (item.at("id") == id) return item;
  }
  assert(false);
  return nullptr;
}
} // namespace

int main(int argc, char **argv) {
  assert(argc == 2);
  std::ifstream input(argv[1], std::ios::binary);
  const Json corpus = Json::parse(input);
  assert(corpus.at("status") == "executed");
  const auto origin = ManagementOwner::Clock::now();
  ManagementOwner owner;

  const Json acceptance_case = fixture(corpus, "WTH-F07");
  assert(acceptance_case.at("operation") == "management_callback_acceptance");
  assert(owner.begin(request("request-1", "management_pending_set", 100), origin + 100ms));
  assert(owner.busy() && owner.active_contexts() == 1);
  const std::size_t results_before_callback = owner.take(origin + 1ms).has_value() ? 1 : 0;
  owner.complete(0);
  const auto accepted = owner.take(origin + 2ms);
  assert(accepted && accepted->command.id == "request-1");
  assert(accepted->outcome == ManagementOwner::Outcome::accepted && accepted->status == 0);
  assert(!owner.busy() && owner.active_contexts() == 0);
  const Json acceptance_observation = {
      {"results_before_callback", results_before_callback},
      {"result", {{"ok", {{"accepted", true}, {"effective", "not_verified"}}}}},
      {"calls", {{"sdk_management_pending_set", 1}}},
      {"active_request_contexts", owner.active_contexts()}};
  assert(acceptance_observation == acceptance_case.at("expectation").at("value"));

  const Json timeout_case = fixture(corpus, "WTH-F08");
  assert(timeout_case.at("operation") == "management_timeout_late_callback");
  assert(owner.begin(request("request-2", "management_active_set", 10), origin + 20ms));
  const auto timed_out = owner.take(origin + 20ms);
  assert(timed_out && timed_out->command.id == "request-2");
  assert(timed_out->outcome == ManagementOwner::Outcome::timed_out && !timed_out->status);
  assert(owner.busy() && owner.active_contexts() == 1);
  const bool second_admitted = owner.begin(request("request-3", "management_active_set", 10),
                                           origin + 30ms);
  assert(!second_admitted);

  owner.complete(0);
  const std::size_t late_successes = owner.take(origin + 21ms).has_value() ? 1 : 0;
  assert(!owner.busy() && owner.active_contexts() == 0);
  const Json timeout_observation = {
      {"results",
       Json::array({{{"error", {{"code", "timeout"}, {"effect", "unknown"}}}},
                    {{"error", {{"code", "busy"}, {"effect", "none"}}}}})},
      {"calls", {{"sdk_management_active_set", second_admitted ? 2 : 1}}},
      {"late_successes", late_successes},
      {"active_request_contexts", owner.active_contexts()}};
  assert(timeout_observation == timeout_case.at("expectation").at("value"));

  assert(owner.begin(request("request-4", "management_active_set", 10), origin + 40ms));
  owner.complete(37);
  const auto rejected = owner.take(origin + 31ms);
  assert(rejected && rejected->command.id == "request-4");
  assert(rejected->outcome == ManagementOwner::Outcome::rejected && rejected->status == 37);

  assert(owner.begin(request("request-5", "management_active_set", 10), origin + 50ms));
  owner.submission_failed();
  assert(!owner.busy() && owner.active_contexts() == 0);
  return 0;
}
