// Test-only real-SDK fixture setup; never part of the packaged controller API.
#include "sdk.hpp"
#include <openthread/platform/logging.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <chrono>
#include <fstream>
#include <iostream>
#include <thread>

extern "C" void otPlatReset(otInstance *) { ::_exit(3); }
extern "C" void otPlatLog(otLogLevel, otLogRegion, const char *, ...) {}
extern "C" void otPlatLogOutput(otInstance *, otLogLevel, const char *) {}

int main() {
  using namespace wotex::thread;
  if (::prctl(PR_SET_CHILD_SUBREAPER, 1) != 0) return 1;
  int result = 0;
  try {
    std::string line;
    for (char byte; std::cin.get(byte);) {
      if (line.size() == kMaximumLine) throw ProtocolError();
      line.push_back(byte);
      if (byte == '\n') break;
    }
    const Json request = parse_line(line);
    if (!exact_keys(request, {"config", "active", "pending"})) throw ProtocolError();
    DatasetValue active(request.at("active")), pending(request.at("pending"));
    if (!active.valid(true) || !pending.valid(false)) throw DatasetError();
    Sdk sdk(request.at("config"));
    otInstance *instance = otInstanceGetSingle();
    if (!otInstanceIsInitialized(instance) || otDatasetSetActiveTlvs(instance, &active.tlvs) != OT_ERROR_NONE ||
        otDatasetSetPendingTlvs(instance, &pending.tlvs) != OT_ERROR_NONE) throw DatasetError();
    sdk.close();
  } catch (...) { result = 1; }
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(900);
  for (;;) {
    while (::waitpid(-1, nullptr, WNOHANG) > 0) {}
    std::ifstream children("/proc/self/task/" + std::to_string(::getpid()) + "/children");
    pid_t child; bool remaining = false;
    while (children >> child) { remaining = true; ::kill(child, SIGKILL); }
    if (!remaining) break;
    if (std::chrono::steady_clock::now() >= deadline) return 2;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return result;
}
