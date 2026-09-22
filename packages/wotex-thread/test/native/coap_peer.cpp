#include <openthread/coap.h>
#include <openthread/dataset.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/link.h>
#include <openthread/message.h>
#include <openthread/openthread-system.h>
#include <openthread/platform/logging.h>
#include <openthread/tasklet.h>
#include <openthread/thread.h>
#include <openthread/thread_ftd.h>

#include <sys/select.h>

#include <cerrno>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
volatile std::sig_atomic_t stopping = 0;

void stop(int) { stopping = 1; }

void check(otError error) {
  if (error != OT_ERROR_NONE) throw std::runtime_error("openthread failure");
}

struct Options final {
  std::string radio;
  std::string interface;
  std::string storage;
  std::string dataset;
  std::string mode;
  std::string report;
};

Options options(int argc, char **argv) {
  if (argc != 13) throw std::runtime_error("invalid arguments");
  Options result;

  for (int index = 1; index < argc; index += 2) {
    const std::string key(argv[index]);
    const std::string value(argv[index + 1]);
    if (value.empty() || value.size() > 4096) throw std::runtime_error("invalid argument");
    if (key == "--radio" && result.radio.empty()) result.radio = value;
    else if (key == "--interface" && result.interface.empty()) result.interface = value;
    else if (key == "--storage" && result.storage.empty()) result.storage = value;
    else if (key == "--dataset" && result.dataset.empty()) result.dataset = value;
    else if (key == "--mode" && result.mode.empty()) result.mode = value;
    else if (key == "--report" && result.report.empty()) result.report = value;
    else throw std::runtime_error("invalid argument");
  }

  if (result.interface.size() > 15 || (result.mode != "sensor" && result.mode != "light")) {
    throw std::runtime_error("invalid argument");
  }
  return result;
}

otOperationalDatasetTlvs dataset(const std::string &path) {
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) throw std::runtime_error("dataset unavailable");
  const std::streamsize size = input.tellg();
  otOperationalDatasetTlvs result{};
  if (size <= 0 || size > static_cast<std::streamsize>(sizeof(result.mTlvs))) {
    throw std::runtime_error("invalid dataset");
  }
  input.seekg(0);
  result.mLength = static_cast<std::uint8_t>(size);
  if (!input.read(reinterpret_cast<char *>(result.mTlvs), size) ||
      !otDatasetIsValid(&result, true)) {
    throw std::runtime_error("invalid dataset");
  }
  return result;
}

const char *role_name(otDeviceRole role) {
  switch (role) {
  case OT_DEVICE_ROLE_CHILD:
    return "child";
  case OT_DEVICE_ROLE_ROUTER:
    return "router";
  case OT_DEVICE_ROLE_LEADER:
    return "leader";
  case OT_DEVICE_ROLE_DETACHED:
    return "detached";
  case OT_DEVICE_ROLE_DISABLED:
    return "disabled";
  default:
    return "unknown";
  }
}

class Peer final {
 public:
  explicit Peer(const Options &options)
      : options_(options), sleepy_(options.mode == "sensor"), value_(sleepy_ ? "21.50" : "0") {
    otPlatformConfig config{};
    config.mTunDevice = "/dev/net/tun";
    config.mInterfaceName = options_.interface.c_str();
    config.mCoprocessorUrls.mUrls[0] = options_.radio.c_str();
    config.mCoprocessorUrls.mNum = 1;
    config.mSpeedUpFactor = 1;
    config.mDataPath = options_.storage.c_str();
    config.mSettingsFile = "settings";
    instance_ = otSysInit(&config);
    if (instance_ == nullptr || config.mCoprocessorType != OT_COPROCESSOR_RCP) {
      throw std::runtime_error("instance unavailable");
    }

    const auto active = dataset(options_.dataset);
    check(otDatasetSetActiveTlvs(instance_, &active));
    if (sleepy_) {
      otLinkModeConfig mode{};
      mode.mRxOnWhenIdle = false;
      mode.mDeviceType = false;
      mode.mNetworkData = false;
      check(otThreadSetLinkMode(instance_, mode));
      check(otThreadSetRouterEligible(instance_, false));
      check(otLinkSetPollPeriod(instance_, 500));
    }

    resource_.mUriPath = sleepy_ ? "sensor/temperature" : "light/on_off";
    resource_.mHandler = handle_request;
    resource_.mContext = this;
    resource_.mNext = nullptr;
    otCoapAddResource(instance_, &resource_);
    check(otCoapStart(instance_, OT_DEFAULT_COAP_PORT));
    check(otIp6SetEnabled(instance_, true));
    check(otThreadSetEnabled(instance_, true));
  }

  ~Peer() {
    if (instance_ != nullptr) {
      otCoapRemoveResource(instance_, &resource_);
      (void)otCoapStop(instance_);
      (void)otThreadSetEnabled(instance_, false);
      (void)otIp6SetEnabled(instance_, false);
      otSysDeinit();
    }
  }

  Peer(const Peer &) = delete;
  Peer &operator=(const Peer &) = delete;

  void run() {
    const std::uint64_t deadline = now_ms() + 30'000;
    bool announced = false;

    while (stopping == 0) {
      step();
      const otDeviceRole role = otThreadGetDeviceRole(instance_);
      if (!announced && (role == OT_DEVICE_ROLE_CHILD || role == OT_DEVICE_ROLE_ROUTER)) {
        char address[OT_IP6_ADDRESS_STRING_SIZE]{};
        otIp6AddressToString(otThreadGetMeshLocalEid(instance_), address, sizeof(address));
        std::cout << "{\"ready\":true,\"mode\":\"" << options_.mode << "\",\"role\":\""
                  << role_name(role) << "\",\"address\":\"" << address
                  << "\",\"sleepy\":" << (sleepy_ ? "true" : "false") << "}\n";
        announced = true;
      }
      if (!announced && now_ms() >= deadline) throw std::runtime_error("attachment timeout");
    }

    write_report();
  }

 private:
  static std::uint64_t now_ms() {
    timespec value{};
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) throw std::runtime_error("clock unavailable");
    return static_cast<std::uint64_t>(value.tv_sec) * 1000U +
        static_cast<std::uint64_t>(value.tv_nsec) / 1'000'000U;
  }

  void step() {
    otSysMainloopContext context{};
    context.mTimeout = {0, 100'000};
    otTaskletsProcess(instance_);
    if (otTaskletsArePending(instance_)) context.mTimeout = {0, 0};
    otSysMainloopUpdate(instance_, &context);
    const int result = select(context.mMaxFd + 1, &context.mReadFdSet, &context.mWriteFdSet,
                              &context.mErrorFdSet, &context.mTimeout);
    if (result < 0 && errno == EINTR) return;
    if (result < 0) throw std::runtime_error("event loop failure");
    otSysMainloopProcess(instance_, &context);
  }

  static void handle_request(void *context, otMessage *message, const otMessageInfo *information) {
    static_cast<Peer *>(context)->request(message, information);
  }

  void request(otMessage *request, const otMessageInfo *information) {
    otCoapCode response_code = OT_COAP_CODE_METHOD_NOT_ALLOWED;
    bool include_value = false;
    const otCoapCode code = otCoapMessageGetCode(request);

    if (code == OT_COAP_CODE_GET) {
      ++get_requests_;
      response_code = OT_COAP_CODE_CONTENT;
      include_value = true;
    } else if (!sleepy_ && code == OT_COAP_CODE_PUT && text_plain(request) &&
               payload(request) == "1") {
      ++put_requests_;
      value_ = "1";
      response_code = OT_COAP_CODE_CHANGED;
    } else if (!sleepy_ && code == OT_COAP_CODE_PUT) {
      response_code = OT_COAP_CODE_BAD_REQUEST;
    }

    otMessage *response = otCoapNewMessage(instance_, nullptr);
    if (response == nullptr) return;
    otError error = otCoapMessageInitResponse(
        response, request,
        otCoapMessageGetType(request) == OT_COAP_TYPE_CONFIRMABLE ? OT_COAP_TYPE_ACKNOWLEDGMENT
                                                                  : OT_COAP_TYPE_NON_CONFIRMABLE,
        response_code);
    if (error == OT_ERROR_NONE && include_value) {
      error = otCoapMessageAppendContentFormatOption(response,
                                                     OT_COAP_OPTION_CONTENT_FORMAT_TEXT_PLAIN);
      if (error == OT_ERROR_NONE) error = otCoapMessageSetPayloadMarker(response);
      if (error == OT_ERROR_NONE) {
        error = otMessageAppend(response, value_.data(), static_cast<std::uint16_t>(value_.size()));
      }
    }
    if (error == OT_ERROR_NONE) error = otCoapSendResponse(instance_, response, information);
    if (error != OT_ERROR_NONE) otMessageFree(response);
  }

  static bool text_plain(otMessage *message) {
    otCoapOptionIterator iterator{};
    std::uint64_t value = 0;
    return otCoapOptionIteratorInit(&iterator, message) == OT_ERROR_NONE &&
        otCoapOptionIteratorGetFirstOptionMatching(&iterator, OT_COAP_OPTION_CONTENT_FORMAT) !=
        nullptr &&
        otCoapOptionIteratorGetOptionUintValue(&iterator, &value) == OT_ERROR_NONE &&
        value == OT_COAP_OPTION_CONTENT_FORMAT_TEXT_PLAIN;
  }

  static std::string payload(otMessage *message) {
    const std::uint16_t offset = otMessageGetOffset(message);
    const std::uint16_t length = otMessageGetLength(message);
    if (length < offset || length - offset > 32) return {};
    std::string result(length - offset, '\0');
    if (otMessageRead(message, offset, result.data(), static_cast<std::uint16_t>(result.size())) !=
        static_cast<std::uint16_t>(result.size())) {
      return {};
    }
    return result;
  }

  void write_report() const {
    std::ofstream output(options_.report, std::ios::binary | std::ios::out | std::ios::trunc);
    if (!output) throw std::runtime_error("report unavailable");
    output << "{\"format\":\"wotex.thread.coap-peer\",\"version\":1,\"mode\":\"" << options_.mode
           << "\",\"get_requests\":" << get_requests_ << ",\"put_requests\":" << put_requests_
           << ",\"final\":\"" << value_ << "\"}\n";
    output.flush();
    if (!output) throw std::runtime_error("report unavailable");
  }

  Options options_;
  bool sleepy_;
  std::string value_;
  otInstance *instance_ = nullptr;
  otCoapResource resource_{};
  std::uint32_t get_requests_ = 0;
  std::uint32_t put_requests_ = 0;
};
} // namespace

extern "C" void otPlatReset(otInstance *) { stopping = 1; }
extern "C" void otPlatLog(otLogLevel, otLogRegion, const char *, ...) {}
extern "C" void otPlatLogOutput(otInstance *, otLogLevel, const char *) {}

int main(int argc, char **argv) {
  std::signal(SIGINT, stop);
  std::signal(SIGTERM, stop);
  try {
    const Options configuration = options(argc, argv);
    Peer peer(configuration);
    peer.run();
    return 0;
  } catch (...) {
    return 2;
  }
}
