#include "wotex_matter/resource_testing.hpp"

#ifndef WOTEX_MATTER_RESOURCE_TESTING
#error "Native resource observations belong only to test executables"
#endif

#include <nlohmann/json.hpp>
#include <system/SystemStats.h>

#include <array>
#include <cstdint>
#include <map>
#include <mutex>

#if !CHIP_SYSTEM_CONFIG_PROVIDE_STATISTICS
#error "Native resource acceptance requires SDK resource statistics"
#endif

namespace wotex::matter::resource_testing {
namespace {

constexpr std::size_t kCount = static_cast<std::size_t>(Object::Count);
constexpr std::array<const char *, kCount> kNames{
    "interaction", "commissioning", "window", "subscription", "read_client",
    "write_client", "command_sender", "window_opener", "recovery_timer"};
std::mutex mutex;
std::array<std::uint64_t, kCount> acquired{};
std::array<std::uint64_t, kCount> destroyed{};
std::map<std::string, std::uint64_t> events;

} // namespace

void Acquired(Object object) {
  std::lock_guard<std::mutex> lock(mutex);
  ++acquired[static_cast<std::size_t>(object)];
}

void Destroyed(Object object) {
  std::lock_guard<std::mutex> lock(mutex);
  ++destroyed[static_cast<std::size_t>(object)];
}

void Event(const char *name) {
  std::lock_guard<std::mutex> lock(mutex);
  ++events[name];
}

// The caller owns the SDK thread or has stopped the SDK event loop. Reading
// SDK counters from an arbitrary running observer thread is not permitted.
std::string SnapshotJson() {
  std::lock_guard<std::mutex> lock(mutex);
  nlohmann::json objects = nlohmann::json::object();
  for (std::size_t index = 0; index < kCount; ++index) {
    objects[kNames[index]] = {{"acquired", acquired[index]},
                              {"destroyed", destroyed[index]}};
  }
  nlohmann::json sdk = nlohmann::json::object();
  const auto *counts = chip::System::Stats::GetResourcesInUse();
  const auto *names = chip::System::Stats::GetStrings();
  for (int index = 0; index < chip::System::Stats::kNumEntries; ++index) {
    sdk[names[index]] = static_cast<int>(counts[index]);
  }
  return nlohmann::json{{"objects", objects}, {"events", events}, {"sdk", sdk}}.dump();
}

} // namespace wotex::matter::resource_testing
