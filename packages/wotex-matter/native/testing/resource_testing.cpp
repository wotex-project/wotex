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
#include <chrono>
#include <fcntl.h>
#include <stdexcept>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

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
std::string startup_directory;
std::string startup_stage;
std::string startup_action;

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

std::optional<std::string> ReadBounded(const std::string &path, std::size_t maximum) {
  const int fd = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) {
    return std::nullopt;
  }
  struct stat status{};
  if (fstat(fd, &status) != 0 || !S_ISREG(status.st_mode) || status.st_size < 0 ||
      static_cast<std::uint64_t>(status.st_size) > maximum) {
    close(fd);
    return std::nullopt;
  }
  std::string contents(maximum + 1, '\0');
  std::size_t size = 0;
  while (size < contents.size()) {
    const ssize_t received = read(fd, contents.data() + size, contents.size() - size);
    if (received < 0) {
      close(fd);
      return std::nullopt;
    }
    if (received == 0) {
      break;
    }
    size += static_cast<std::size_t>(received);
  }
  close(fd);
  if (size > maximum) {
    return std::nullopt;
  }
  contents.resize(size);
  return contents;
}

bool WriteExclusive(const std::string &path, const std::string &contents) {
  const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0) {
    return false;
  }
  std::size_t offset = 0;
  while (offset < contents.size()) {
    const ssize_t written = write(fd, contents.data() + offset, contents.size() - offset);
    if (written <= 0) {
      close(fd);
      return false;
    }
    offset += static_cast<std::size_t>(written);
  }
  const bool synced = fsync(fd) == 0;
  return close(fd) == 0 && synced;
}

bool WriteAtomicExclusive(const std::string &path, const std::string &contents) {
  const std::string temporary = path + ".partial";
  if (!WriteExclusive(temporary, contents)) {
    return false;
  }
  const bool published = link(temporary.c_str(), path.c_str()) == 0;
  const bool removed = unlink(temporary.c_str()) == 0;
  return published && removed;
}

void ConfigureStartup(std::string directory, std::string stage, std::string action) {
  // Configuration precedes every SDK and observer thread and is then immutable.
  startup_directory = std::move(directory);
  startup_stage = std::move(stage);
  startup_action = std::move(action);
}

bool StartupStage(const char *stage) {
  if (startup_stage != stage) {
    return false;
  }
  const nlohmann::json observation{{"stage", stage}, {"action", startup_action}};
  if (!WriteAtomicExclusive(startup_directory + "/startup-stage.json", observation.dump())) {
    throw std::runtime_error("startup observation failed");
  }
  if (startup_action == "throw") {
    throw std::runtime_error("injected startup failure");
  }
  while (startup_action == "wait") {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return true;
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
