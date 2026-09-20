#include "joiner.hpp"
#include <cassert>
#include <cstddef>
#include <string>
#include <vector>

using namespace wotex::thread;

namespace {
struct Callback {
  otJoinerCallback function;
  void *context;
};

bool commissioned = false;
otError start_status = OT_ERROR_NONE;
std::size_t starts = 0;
std::size_t stops = 0;
std::vector<Callback> callbacks;
std::optional<otJoinerDiscerner> selected_discerner;

Json parameters(Json discerner = nullptr) {
  return {{"pskd", "WTEST123"},     {"discerner", discerner},    {"provisioning_url", nullptr},
          {"vendor_name", "Wotex"}, {"vendor_model", "Fixture"}, {"vendor_sw_version", "1.0"},
          {"vendor_data", "opaque"}};
}

bool fails_with(JoinerOwner &owner, const Json &value, const std::string &code) {
  try {
    owner.start(value);
  } catch (const JoinerError &error) {
    return error.what() == code;
  }
  return false;
}
} // namespace

extern "C" bool otDatasetIsCommissioned(otInstance *) { return commissioned; }

extern "C" otError otJoinerSetDiscerner(otInstance *, otJoinerDiscerner *discerner) {
  if (discerner == nullptr) {
    selected_discerner.reset();
  } else {
    selected_discerner = *discerner;
  }
  return OT_ERROR_NONE;
}

extern "C" otError otJoinerStart(otInstance *, const char *, const char *, const char *,
                                 const char *, const char *, const char *,
                                 otJoinerCallback callback, void *context) {
  ++starts;
  if (start_status == OT_ERROR_NONE) callbacks.push_back({callback, context});
  return start_status;
}

extern "C" void otJoinerStop(otInstance *) { ++stops; }

int main() {
  otInstance instance{};
  JoinerOwner owner(&instance);

  assert(fails_with(owner, Json::object(), "invalid_joiner_config"));
  Json invalid = parameters();
  invalid["vendor_name"] = "line\nbreak";
  assert(fails_with(owner, invalid, "invalid_joiner_config"));
  invalid = parameters();
  invalid["extra"] = true;
  assert(fails_with(owner, invalid, "invalid_joiner_config"));
  assert(starts == 0);

  commissioned = true;
  assert(fails_with(owner, parameters(), "dataset_exists"));
  commissioned = false;

  start_status = OT_ERROR_BUSY;
  try {
    owner.start(parameters());
    assert(false);
  } catch (otError error) {
    assert(error == OT_ERROR_BUSY);
  }
  start_status = OT_ERROR_NONE;

  const Json discerner = {{"type", "discerner"}, {"length", 64}, {"value", "18446744073709551615"}};
  owner.start(parameters(discerner));
  assert(selected_discerner && selected_discerner->mLength == 64 &&
         selected_discerner->mValue == UINT64_MAX);
  assert(fails_with(owner, parameters(), "busy"));
  const Callback retired = callbacks.back();
  owner.stop();
  assert(stops == 1);

  owner.start(parameters());
  const Callback current = callbacks.back();
  retired.function(OT_ERROR_NONE, retired.context);
  assert(!owner.take_result());
  current.function(OT_ERROR_SECURITY, current.context);
  assert(owner.take_result() == OT_ERROR_SECURITY);

  owner.start(parameters());
  callbacks.back().function(OT_ERROR_NONE, callbacks.back().context);
  assert(fails_with(owner, parameters(), "busy"));
  assert(owner.take_result() == OT_ERROR_NONE);
  owner.close();
  assert(stops == 1);
  return 0;
}
