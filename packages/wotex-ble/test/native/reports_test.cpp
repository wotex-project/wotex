// SPDX-License-Identifier: Apache-2.0
#include "reports.hpp"
#include <array>
#include <chrono>
#include <csignal>
#include <iostream>

using namespace wotex::ble;
static void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("native reports assertion at line " + std::to_string(line));
}
#define CHECK(value) verify((value), __LINE__)
template<class Function> static void rejected(Function function) {
  bool failed = false; try { function(); } catch (const InvalidFrame &) { failed = true; } CHECK(failed);
}
static const std::string generation = "0123456789abcdef0123456789abcdef";
static Json metadata() {
  return {{"source", "bluez_value_change"}, {"requested_mode", "auto"}, {"effective_mode", "notify"},
    {"characteristic", {{"service_uuid", "0000180f-0000-1000-8000-00805f9b34fb"},
      {"characteristic_uuid", "00002a19-0000-1000-8000-00805f9b34fb"}, {"service_path", "/org/bluez/hci0/device/service"},
      {"object_path", "/org/bluez/hci0/device/service/char"}, {"handle", 17}, {"flags", {"read", "notify"}}, {"generation", 1}}}};
}
static Json value(std::uint64_t id, const Json &bound = metadata(), std::string bytes = "\x01") {
  return {{"version", 1}, {"subscription_id", std::to_string(id)}, {"generation", 1}, {"event", "value"},
    {"value", AttributeBytes::from_bytes(bytes).envelope()}, {"metadata", bound}};
}
struct Fixture {
  NativeOutput output;
  NativeReports reports{output, generation};
  std::array<int, 2> descriptors{-1, -1};
  std::string partial;
  std::vector<Json> frames;
  std::map<std::uint64_t, std::uint64_t> sums;
  std::uint64_t bytes = 0;
  Fixture() {
    CHECK(::pipe(descriptors.data()) == 0);
    for (int fd : descriptors) CHECK(::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK) == 0);
  }
  ~Fixture() { for (int fd : descriptors) if (fd >= 0) ::close(fd); }
  Fixture(const Fixture &) = delete;
  void receive() {
    std::array<char, 8192> buffer{};
    for (;;) {
      const auto count = ::read(descriptors[0], buffer.data(), buffer.size());
      if (count < 0) { CHECK(errno == EAGAIN || errno == EWOULDBLOCK); break; }
      CHECK(count > 0); partial.append(buffer.data(), static_cast<std::size_t>(count));
      for (auto at = partial.find('\n'); at != std::string::npos; at = partial.find('\n')) {
        auto frame = parse_line(partial.substr(0, at + 1)); partial.erase(0, at + 1);
        if (frame.at("event") == "value") { bytes += at + 1; sums.emplace(frame.at("report_sequence").get<std::uint64_t>(), bytes); }
        frames.push_back(std::move(frame));
      }
    }
  }
  void flush() {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (output.pending_frames() && std::chrono::steady_clock::now() < deadline) { output.flush(descriptors[1]); receive(); }
    receive(); CHECK(!output.pending_frames() && partial.empty());
  }
  Json ack(std::uint64_t sequence) const {
    return {{"version", 1}, {"event", "report_ack"}, {"session_generation", generation},
      {"report_sequence", sequence}, {"acknowledged_bytes", sums.at(sequence)}};
  }
};
static void boundaries() {
  Fixture f; const auto bound = metadata();
  rejected([&] { NativeReports other(f.output, "invalid"); });
  rejected([&] { f.reports.open(0, bound, 2); });
  rejected([&] { f.reports.open(1, bound, 0); });
  rejected([&] { f.reports.open(1, bound, 10001); });
  for (const auto &key : {"source", "characteristic", "requested_mode", "effective_mode"}) {
    auto wrong = bound; wrong.erase(key); rejected([&] { f.reports.open(1, wrong, 2); });
  }
  auto large = bound; large["characteristic"]["large"] = std::string(max_line, 'x');
  rejected([&] { f.reports.open(1, large, 2); });
  CHECK(f.reports.open(1, bound, 2)); rejected([&] { f.reports.open(1, bound, 2); });
  for (const auto &key : {"version", "subscription_id", "generation", "event", "metadata", "value"}) {
    auto wrong = value(1); wrong.erase(key); rejected([&] { f.reports.publish(wrong); });
  }
  for (const Json &identifier : {Json("0"), Json("01"), Json("-1"), Json("+1"), Json("18446744073709551616"), Json(true), Json(1), Json("2")}) {
    auto wrong = value(1); wrong["subscription_id"] = identifier; rejected([&] { f.reports.publish(wrong); });
  }
  auto wrong = value(1); wrong["metadata"]["characteristic"]["handle"] = 18; rejected([&] { f.reports.publish(wrong); });
  CHECK(f.reports.publish(value(1)));
  auto premature = Json{{"version", 1}, {"event", "report_ack"}, {"session_generation", generation}, {"report_sequence", 1}, {"acknowledged_bytes", 1}};
  rejected([&] { f.reports.acknowledge(premature); }); CHECK(f.reports.available_frames() == 63);
  f.output.flush(f.descriptors[1], 1); CHECK(!f.output.transmitted_report_sequence());
  rejected([&] { f.reports.acknowledge(premature); }); f.flush(); CHECK(f.output.transmitted_report_sequence() == 1);
  for (const auto &key : {"version", "event", "session_generation", "report_sequence", "acknowledged_bytes"}) {
    auto wrong = f.ack(1); wrong.erase(key); rejected([&] { f.reports.acknowledge(wrong); });
  }
  for (const Json &wrong : {Json{{"session_generation", "fedcba9876543210fedcba9876543210"}}, Json{{"report_sequence", 2}},
      Json{{"acknowledged_bytes", f.bytes + 1}}, Json{{"extra", true}}}) {
    auto ack = f.ack(1); ack.update(wrong); rejected([&] { f.reports.acknowledge(ack); });
  }
  f.reports.acknowledge(f.ack(1)); rejected([&] { f.reports.acknowledge(f.ack(1)); });
  for (const Json &error : {Json{{"code", "private diagnostic"}}, Json{{"code", "timeout"}, {"message", "private diagnostic"}},
      Json{{"code", "timeout"}, {"name", "org.bluez.Error.1Invalid"}}, Json{{"code", "timeout"}, {"name", std::string(129, 'x')}}})
    rejected([&] { f.reports.retire(1, error); });
  CHECK(f.reports.retire(1, Json{{"code", "remote_error"}, {"name", "org.bluez.Error.Failed"}})); f.flush();
  CHECK(f.reports.available_frames() == 64 && !f.reports.credit_records() && !f.reports.active_streams());
  CHECK(!f.frames[1].contains("report_sequence") && f.frames[1].at("event") == "error" && f.frames[2].at("event") == "stream_retired");
  rejected([&] { f.reports.publish(value(1)); });
  std::cout << "native report boundaries passed\n";
}
static Json overflow() {
  Fixture f; CHECK(f.reports.open(1, metadata(), 2));
  for (unsigned i = 0; i < 4; ++i) CHECK(f.reports.publish(value(1)));
  CHECK(f.reports.queued_reports() == 2 && f.output.report_frames() == 2 && f.reports.queued_bytes() > 0);
  CHECK(!f.reports.publish(value(1)) && !f.reports.queued_reports() && !f.reports.queued_bytes());
  for (unsigned i = 0; i < 10000; ++i) CHECK(!f.reports.publish(value(1)));
  CHECK(f.reports.retire(1, Json{{"code", "queue_overflow"}}) && !f.reports.retire(1, Json{{"code", "queue_overflow"}}));
  CHECK(f.output.control_frames() == 2 && f.reports.credit_records() == 1 && f.reports.available_frames() == 62);
  f.flush(); CHECK(f.frames.size() == 4 && f.frames[0].at("report_sequence") == 1 && f.frames[1].at("report_sequence") == 2);
  CHECK(f.frames[2].at("event") == "error" && !f.frames[2].contains("report_sequence") && f.frames[3].at("last_report_sequence") == 2);
  f.reports.acknowledge(f.ack(2)); CHECK(!f.reports.credit_records() && f.reports.available_bytes() == 1048576);
  return {{"events", {"value", "value", "error", "stream_retired"}}, {"sequences", {1, 2}},
    {"terminal_has_sequence", f.frames[2].contains("report_sequence")}, {"terminal_code", f.frames[2].at("metadata").at("error").at("code")},
    {"barrier_sequence", f.frames[3].at("last_report_sequence")}, {"queued", f.reports.queued_reports()},
    {"remaining_frames", f.reports.available_frames()}, {"credit_records", f.reports.credit_records()}};
}
static void fairness() {
  Fixture f;
  for (unsigned id = 1; id <= 4; ++id) {
    CHECK(f.reports.open(id, metadata(), 32));
    for (unsigned j = 0; j < 16; ++j) CHECK(f.reports.publish(value(id)));
  }
  for (unsigned id = 1; id <= 4; ++id) CHECK(f.reports.publish(value(id)));
  CHECK(!f.reports.available_frames() && f.reports.queued_reports() == 4);
  CHECK(f.reports.silence(1) && !f.reports.silence(1) && f.reports.queued_reports() == 3);
  CHECK(f.reports.retire(1)); f.flush(); CHECK(f.frames.size() == 65 && f.frames.back().at("last_report_sequence") == 16);
  f.reports.acknowledge(f.ack(16)); // stream 2..4 still hold their own 16-credit windows
  CHECK(f.reports.queued_reports() == 3 && f.reports.available_frames() == 16 && f.reports.credit_records() == 3);
  f.reports.acknowledge(f.ack(32)); // stream 2 progresses despite stream 3..4 being blocked
  CHECK(f.reports.queued_reports() == 2 && f.output.report_frames() == 1); f.flush();
  CHECK(f.frames.back().at("subscription_id") == "2" && f.frames.back().at("report_sequence") == 65);
  f.reports.acknowledge(f.ack(64)); CHECK(!f.reports.queued_reports()); f.flush();
  CHECK(f.frames[f.frames.size() - 2].at("subscription_id") == "3" && f.frames.back().at("subscription_id") == "4");
  for (unsigned id = 2; id <= 4; ++id) CHECK(f.reports.retire(id));
  f.flush();
  f.reports.acknowledge(f.ack(67)); CHECK(!f.reports.credit_records() && f.reports.available_frames() == 64);
  Fixture queue;
  CHECK(queue.reports.open(1, metadata(), 10000) && queue.reports.open(2, metadata(), 10000));
  for (unsigned i = 0; i < 80; ++i) CHECK(queue.reports.publish(value(1)));
  CHECK(queue.reports.queued_reports() == 64); CHECK(!queue.reports.publish(value(1)));
  CHECK(queue.reports.publish(value(2)) && !queue.reports.queued_reports() && queue.output.report_frames() == 17);
  Fixture active;
  for (unsigned i = 1; i <= 64; ++i) CHECK(active.reports.open(i, metadata(), 2));
  CHECK(!active.reports.open(65, metadata(), 2)); CHECK(active.reports.retire(1));
  CHECK(active.reports.open(65, metadata(), 2) && active.reports.active_streams() == 64);
  std::cout << "native report fairness and retirement passed\n";
}
static void byte_limits() {
  Fixture f; Json bound = metadata(); bound["characteristic"]["fixture_padding"] = std::string(64000, 'x');
  for (unsigned id = 1; id <= 3; ++id) CHECK(f.reports.open(id, bound, 10000));
  for (unsigned i = 0; i < 16; ++i) CHECK(f.reports.publish(value(1, bound)));
  CHECK(f.reports.available_bytes() < 64000);
  for (unsigned i = 0; i < 16; ++i) CHECK(f.reports.publish(value(2, bound)));
  CHECK(f.reports.queued_reports() == 16 && f.reports.queued_bytes() <= 1048576);
  CHECK(!f.reports.publish(value(2, bound)) && !f.reports.queued_reports());
  CHECK(f.reports.publish(value(3, bound)) && f.reports.queued_reports() == 1);
  f.flush(); f.reports.acknowledge(f.ack(16)); CHECK(!f.reports.queued_reports()); f.flush();
  CHECK(f.frames.back().at("subscription_id") == "3");
  // A blocked large report cannot let a smaller later value overtake its stream.
  Fixture order; bound["characteristic"]["fixture_padding"] = std::string(64100, 'x');
  CHECK(order.reports.open(1, bound, 10000));
  for (unsigned i = 0; i < 16; ++i) CHECK(order.reports.publish(value(1, bound, std::string(512, 'a'))));
  CHECK(order.reports.publish(value(1, bound, std::string(512, 'b'))));
  CHECK(order.reports.publish(value(1, bound, "c"))); order.flush(); order.reports.acknowledge(order.ack(1));
  order.flush(); CHECK(order.frames.back().at("value") == AttributeBytes::from_bytes(std::string(512, 'b')).envelope());
  CHECK(order.reports.queued_reports() == 1);
  Fixture blocked; const auto small = metadata(); auto filler = small;
  const auto prototype = Json{{"version", 1}, {"session_generation", generation}, {"report_sequence", 2},
    {"subscription_id", "2"}, {"generation", 1}, {"event", "value"},
    {"value", AttributeBytes::from_bytes("a").envelope()}, {"metadata", filler}};
  filler["characteristic"]["fixture_padding"] = "";
  auto sized = prototype; sized["metadata"] = filler;
  const auto overhead = EncodedFrame::from(sized).size();
  filler["characteristic"]["fixture_padding"] = std::string(65479 - overhead, 'x');
  CHECK(blocked.reports.open(1, small, 10000) && blocked.reports.open(2, filler, 10000) && blocked.reports.open(3, small, 10000));
  CHECK(blocked.reports.publish(value(1, small)));
  for (unsigned i = 0; i < 16; ++i) CHECK(blocked.reports.publish(value(2, filler, "a")));
  CHECK(blocked.reports.publish(value(3, small, std::string(512, 'b'))));
  CHECK(blocked.reports.publish(value(3, small, "c"))); CHECK(blocked.reports.queued_reports() == 2);
  blocked.flush(); blocked.reports.acknowledge(blocked.ack(1));
  CHECK(blocked.reports.available_bytes() > 800 && blocked.reports.available_bytes() < 1000);
  CHECK(blocked.reports.queued_reports() == 2 && !blocked.output.pending_frames());
  blocked.reports.acknowledge(blocked.ack(2)); blocked.flush();
  CHECK(!blocked.reports.queued_reports() && blocked.frames[blocked.frames.size() - 2].at("value") ==
    AttributeBytes::from_bytes(std::string(512, 'b')).envelope() && blocked.frames.back().at("value") == AttributeBytes::from_bytes("c").envelope());
  std::cout << "native report byte limits passed\n";
}
static void churn() {
  Fixture f;
  for (unsigned id = 1; id <= 1000; ++id) {
    CHECK(f.reports.open(id, metadata(), 1) && f.reports.publish(value(id)) && f.reports.retire(id));
    CHECK(f.reports.credit_records() == 1); f.flush(); f.reports.acknowledge(f.ack(id));
    CHECK(!f.reports.credit_records() && !f.reports.queued_reports() && !f.reports.active_streams());
    f.frames.clear(); f.sums.clear();
  }
  CHECK(f.output.pending_frames() == 0 && f.output.control_frames() == 0 && f.output.report_frames() == 0 && f.reports.available_frames() == 64);
  Fixture controls;
  for (unsigned id = 1; id <= 128; ++id) {
    CHECK(controls.reports.open(id, metadata(), 1)); CHECK(controls.reports.retire(id, Json{{"code", "queue_overflow"}}));
  }
  CHECK(controls.output.control_frames() == 256 && !controls.reports.credit_records());
  CHECK(controls.reports.open(129, metadata(), 1)); rejected([&] { controls.reports.retire(129); });
  CHECK(controls.output.control_frames() == 256);
  std::cout << "native report churn and control bounds passed\n";
}
static Json trace(const Json &input) {
  CHECK(fields(input, {"session_generation", "metadata", "queue_limit", "events"}) && input.at("session_generation") == generation &&
    integer(input.at("queue_limit"), 1, 10000) && input.at("events").is_array());
  Fixture f; Json results = Json::array(); std::string failure;
  for (const auto &event : input.at("events")) {
    try {
      if (fields(event, {"open"}) && integer(event.at("open"), 1, UINT64_MAX))
        results.push_back(f.reports.open(event.at("open").get<std::uint64_t>(), input.at("metadata"), input.at("queue_limit").get<std::size_t>()));
      else if (fields(event, {"publish"}) && fields(event.at("publish"), {"id", "bytes"}) && integer(event.at("publish").at("id"), 1, UINT64_MAX)) {
        auto report = value(event.at("publish").at("id").get<std::uint64_t>(), input.at("metadata"));
        report["value"] = event.at("publish").at("bytes"); results.push_back(f.reports.publish(report));
      } else if (fields(event, {"retire"}) && fields(event.at("retire"), {"id", "error"}) && integer(event.at("retire").at("id"), 1, UINT64_MAX)) {
        const auto &error = event.at("retire").at("error");
        results.push_back(f.reports.retire(event.at("retire").at("id").get<std::uint64_t>(),
          error.is_null() ? std::nullopt : std::optional<Json>(error)));
      } else if (fields(event, {"flush"}) && event.at("flush") == true) f.flush();
      else if (fields(event, {"ack"})) f.reports.acknowledge(event.at("ack"));
      else throw InvalidFrame();
    } catch (const InvalidFrame &) { failure = "invalid_frame"; break; }
  }
  return {{"results", results}, {"frames", f.frames}, {"failure", failure.empty() ? Json() : Json(failure)},
    {"queued", f.reports.queued_reports()}, {"remaining_frames", f.reports.available_frames()},
    {"remaining_bytes", f.reports.available_bytes()}, {"credit_records", f.reports.credit_records()},
    {"active_streams", f.reports.active_streams()}, {"output_frames", f.output.pending_frames()}};
}
int main(int argc, char **argv) {
  std::signal(SIGPIPE, SIG_IGN);
  try {
    if (argc == 3 && std::string(argv[1]) == "--report-input") {
      std::cout << trace(parse_line(std::string(argv[2]) + "\n")).dump() << '\n'; return 0;
    }
    if (argc != 2) return 2;
    const std::string operation = argv[1];
    if (operation == "boundaries") boundaries();
    else if (operation == "overflow") { overflow(); std::cout << "native report overflow passed\n"; }
    else if (operation == "fairness") fairness();
    else if (operation == "bytes") byte_limits();
    else if (operation == "churn") churn();
    else return 2;
    return 0;
  } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
}
