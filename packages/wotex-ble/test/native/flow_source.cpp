// SPDX-License-Identifier: Apache-2.0
// Test-only native callback source for the WBL-B-F11 through WBL-B-F13 process
// flows. It links no SDK and opens no D-Bus sender. After one subscription is
// admitted, each event-loop iteration performs one value callback into the
// production NativeReports, Credits, ReportQueue and NativeOutput owners, exactly
// as NativeNotifications does. Production starts only after the test creates the
// executable path plus ".start", so the selected BEAM process is suspended at
// callback zero. The BEAM owner decides credit, delivery and cancellation; this
// process supplies no expected result.
#include "reports.hpp"
#include <array>
#include <csignal>
#include <poll.h>
#include <unistd.h>

#if !defined(WOTEX_FLOW_CALLBACKS) || !defined(WOTEX_FLOW_VALUE_BYTES)
#error "the process-flow source requires explicit callback count and value size"
#endif

namespace {
using namespace wotex::ble;

bool nonblocking(int descriptor) {
  const int flags = ::fcntl(descriptor, F_GETFL);
  return flags >= 0 && ::fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0;
}

std::uint64_t identifier(const std::string &text) {
  std::uint64_t value = 0;
  for (char digit : text) value = value * 10 + static_cast<unsigned>(digit - '0');
  return value;
}

class Source {
  NativeOutput output_;
  Sequence sequence_;
  std::unique_ptr<NativeReports> reports_;
  const AttributeBytes value_ = AttributeBytes::from_bytes(std::string(WOTEX_FLOW_VALUE_BYTES, '\x5a'));
  Json metadata_;
  std::uint64_t stream_ = 0;
  std::size_t callbacks_ = 0;
  std::string start_;
  bool active_ = false, producing_ = false, started_ = false, closed_ = false;

  void retire(const std::optional<Json> &failure = std::nullopt) {
    active_ = producing_ = false;
    reports_->retire(stream_, failure);
  }

  void reply(const Json &request, const Json &result) {
    const auto slot = output_.reserve_reply();
    if (!slot || !output_.reply(*slot, EncodedFrame::from(
        Json{{"version", 1}, {"id", request.at("id")}, {"ok", true}, {"result", result}}))) throw InvalidFrame();
  }
  void fail(const Json &request, std::string_view code) {
    const auto slot = output_.reserve_reply();
    if (!slot || !output_.reply(*slot, EncodedFrame::from(Json{{"version", 1}, {"id", request.at("id")},
        {"ok", false}, {"error", {{"code", std::string(code)}}}}))) throw InvalidFrame();
  }
  void subscribe(const Json &request) {
    const auto &parameters = request.at("parameters");
    const auto &address = parameters.at("address");
    const Json characteristic{{"service_uuid", address.at("service")}, {"characteristic_uuid", address.at("characteristic")},
      {"service_path", "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service0001"}, {"object_path", address.at("object_path")},
      {"handle", address.at("handle")}, {"generation", address.at("generation")}, {"flags", {"notify"}}};
    stream_ = identifier(request.at("id").get<std::string>());
    metadata_ = {{"source", "bluez_value_change"}, {"characteristic", characteristic},
      {"requested_mode", parameters.at("mode")}, {"effective_mode", "notify"}};
    if (!reports_->open(stream_, metadata_, parameters.at("queue_limit").get<std::size_t>())) throw InvalidFrame();
    reply(request, {{"subscription_id", request.at("id")}, {"generation", 1}, {"characteristic", characteristic},
      {"requested_mode", parameters.at("mode")}, {"effective_mode", "notify"}});
    active_ = producing_ = true;
  }

public:
  explicit Source(std::string start) : start_(std::move(start)) {
    if (!output_.control(EncodedFrame::from({{"version", 1}, {"event", "ready"}, {"backend", "bluez-native"},
        {"revision", "2123ab772fbe97d1369fc9e179ea87c3469cf98f"}}, NativeOutput::control_frame_limit))) throw InvalidFrame();
  }
  void receive(const Json &frame) {
    if (frame.contains("event")) {
      if (frame.at("event") == "flow_open" && !reports_) {
        reports_ = std::make_unique<NativeReports>(output_, frame.at("session_generation").get<std::string>());
      } else if (reports_) {
        reports_->acknowledge(frame);
      } else throw InvalidFrame();
      return;
    }
    if (!reports_ || !sequence_.accept(frame)) throw InvalidFrame();
    const auto &operation = frame.at("operation");
    if (operation == "open") {
      reply(frame, {{"generation", 1}, {"device_path", "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"},
        {"link_owned", false}, {"sender", ":1.1"}});
    } else if (operation == "subscribe" && !stream_) {
      subscribe(frame);
    } else if (operation == "unsubscribe") {
      if (active_) { retire(); reply(frame, nullptr); }
      else fail(frame, "invalid_subscription");
    } else if (operation == "close") {
      if (active_) retire();
      reply(frame, nullptr); closed_ = true;
    } else throw InvalidFrame();
  }
  // One SDK-equivalent value callback per loop turn. A rejected admission
  // silences the stream and emits its bounded terminal control and barrier.
  void callback() {
    if (!producing_) return;
    if (!started_ && ::access(start_.c_str(), F_OK) != 0) return;
    started_ = true;
    if (callbacks_ == WOTEX_FLOW_CALLBACKS) { producing_ = false; return; }
    ++callbacks_;
    const Json report{{"version", 1}, {"subscription_id", std::to_string(stream_)}, {"generation", 1},
      {"event", "value"}, {"value", value_.envelope()}, {"metadata", metadata_}};
    if (!reports_->publish(report)) retire(Json{{"code", "queue_overflow"}});
  }
  void flush(int descriptor) { output_.flush(descriptor); }
  bool producing() const { return producing_ && started_; }
  bool pending() const { return output_.pending_frames() != 0; }
  bool finished() const { return closed_ && !pending(); }
};
} // namespace

int main(int argc, char **argv) {
  if (argc != 1 || !nonblocking(STDIN_FILENO) || !nonblocking(STDOUT_FILENO)) return 2;
  std::signal(SIGPIPE, SIG_IGN);
  try {
    Source source(std::string(*argv) + ".start"); Lines lines;
    for (;;) {
      source.flush(STDOUT_FILENO);
      if (source.finished()) return 0;
      std::array<pollfd, 2> descriptors{{{STDIN_FILENO, POLLIN, 0},
        {STDOUT_FILENO, static_cast<short>(source.pending() ? POLLOUT : 0), 0}}};
      if (::poll(descriptors.data(), descriptors.size(), source.producing() ? 0 : 1) < 0 && errno != EINTR) return 1;
      if (descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) return 1;
      if (descriptors[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
        std::array<char, 8192> bytes{};
        for (unsigned attempt = 0; attempt < 8; ++attempt) {
          const auto count = ::read(STDIN_FILENO, bytes.data(), bytes.size());
          if (count < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            if (errno == EINTR) continue;
            return 1;
          }
          if (!count) { lines.eof(); return 1; }
          lines.feed(std::string_view(bytes.data(), static_cast<std::size_t>(count)),
            [&](std::string_view line) { source.receive(parse_line(line)); });
        }
      }
      source.callback();
    }
  } catch (...) { return 1; }
}
