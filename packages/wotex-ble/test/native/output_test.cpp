// SPDX-License-Identifier: Apache-2.0
#include "output.hpp"
#include <array>
#include <chrono>
#include <csignal>
#include <iostream>

using namespace wotex::ble;
static void verify(bool value, unsigned line) {
  if (!value) throw std::runtime_error("native output assertion at line " + std::to_string(line));
}
#define CHECK(value) verify((value), __LINE__)
template<class Function> static void rejected(Function function) {
  bool failed = false; try { function(); } catch (const InvalidFrame &) { failed = true; } CHECK(failed);
}
struct Pipe {
  std::array<int, 2> values{-1, -1};
  explicit Pipe(bool nonblocking = true) {
    CHECK(::pipe(values.data()) == 0);
    if (nonblocking) for (const int value : values) CHECK(::fcntl(value, F_SETFL, ::fcntl(value, F_GETFL) | O_NONBLOCK) == 0);
  }
  ~Pipe() { for (const int value : values) if (value >= 0) ::close(value); }
  Pipe(const Pipe &) = delete;
  int read() const { return values[0]; }
  int write() const { return values[1]; }
};
static std::uint64_t hash(std::uint64_t prior, std::string_view value) {
  for (const unsigned char byte : value) { prior ^= byte; prior *= 1099511628211ULL; }
  return prior;
}
static void serialization() {
  // WBL-B02: limits apply during serialization, including escapes and newline.
  for (const Json &value : {Json(), Json(true), Json(false), Json(INT64_MIN), Json(UINT64_MAX), Json(1.5),
      Json("quotes\"\n\\\t"), Json("åäö"), Json::array({1, "two", nullptr}), Json{{"value", "\n"}}}) {
    const auto encoded = EncodedFrame::from(value); CHECK(parse_line(encoded.bytes()) == value);
    CHECK(encoded.bytes().back() == '\n' && encoded.bytes().find('\n') == encoded.size() - 1);
  }
  CHECK(EncodedFrame::from(Json(std::string(max_line - 3, 'x'))).size() == max_line);
  rejected([] { EncodedFrame::from(Json(std::string(max_line - 2, 'x'))); });
  rejected([] { EncodedFrame::from(Json(std::string(30000, '\0'))); });
  rejected([] { EncodedFrame::from(Json(std::string("\xc3", 1))); });
  rejected([] { EncodedFrame::from(Json(std::numeric_limits<double>::quiet_NaN())); });
  rejected([] { EncodedFrame::from(Json(std::numeric_limits<double>::infinity())); });
  rejected([] { EncodedFrame::from(Json::binary({1})); });
  rejected([] { EncodedFrame::from(Json(), 0); });
  rejected([] { EncodedFrame::from(Json(), max_line + 1); });
  CHECK(EncodedFrame::from(Json(), 5).bytes() == "null\n");
  rejected([] { EncodedFrame::from(Json(), 4); });
  Json depth = 1;
  for (unsigned index = 0; index < 7; ++index) depth = Json::array({depth});
  CHECK(parse_line(EncodedFrame::from(depth).bytes()) == depth);
  rejected([&] { EncodedFrame::from(Json::array({depth})); });
  Json wide = std::vector<int>(1024, 0); CHECK(!EncodedFrame::from(wide).bytes().empty());
  wide.push_back(0); rejected([&] { EncodedFrame::from(wide); });
  Json nodes = Json::array({std::vector<int>(1022, 0), std::vector<int>(1022, 0), std::vector<int>(1022, 0), std::vector<int>(1024, 0)});
  CHECK(!EncodedFrame::from(nodes).bytes().empty()); // 4095 values and containers
  nodes[0].push_back(0); CHECK(!EncodedFrame::from(nodes).bytes().empty());
  nodes[1].push_back(0); rejected([&] { EncodedFrame::from(nodes); });
  std::cout << "native output serialization passed\n";
}
static void capacity() {
  NativeOutput output, foreign;
  const auto frame = EncodedFrame::from(Json{{"value", 1}});
  std::vector<NativeOutput::ReplySlot> slots;
  for (unsigned index = 0; index < 64; ++index) {
    // NOLINTBEGIN(bugprone-unchecked-optional-access): CHECK ends the test when a slot is empty.
    const auto slot = output.reserve_reply(); CHECK(bool(slot)); slots.push_back(*slot);
    CHECK(output.reply(*slot, frame) && !output.reply(*slot, frame) && !output.release_reply(*slot));
    // NOLINTEND(bugprone-unchecked-optional-access)
    CHECK(output.report(frame));
  }
  CHECK(!output.reserve_reply() && !output.report(frame) && output.reply_reservations() == 64 && output.report_frames() == 64);
  for (unsigned index = 0; index < 256; ++index) CHECK(output.control(frame));
  CHECK(!output.control(frame) && output.pending_frames() == 384 && output.retained_bytes() == 384 * frame.size());
  CHECK(!foreign.release_reply(slots.front()) && !foreign.reply(slots.front(), frame) &&
    !output.reply(NativeOutput::ReplySlot{}, frame) && !output.release_reply(NativeOutput::ReplySlot{}));
  CHECK(!foreign.control(EncodedFrame::from(Json(std::string(4094, 'x')))));
  CHECK(foreign.control(EncodedFrame::from(Json(std::string(4093, 'x')))));
  NativeOutput churn;
  auto previous = churn.reserve_reply(); CHECK(previous && churn.release_reply(*previous));
  for (unsigned index = 0; index < 100000; ++index) {
    // NOLINTBEGIN(bugprone-unchecked-optional-access): CHECK ends the test when a slot is empty.
    auto current = churn.reserve_reply(); CHECK(current && !churn.release_reply(*previous) && !churn.reply(*previous, frame));
    CHECK(churn.release_reply(*current) && !churn.release_reply(*current) && churn.reply_reservations() == 0); previous = current;
    // NOLINTEND(bugprone-unchecked-optional-access)
  }
  std::cout << "native output capacity passed\n";
}
static void pipes() {
  NativeOutput output; Pipe pipe;
  const auto maximum = EncodedFrame::from(Json(std::string(max_line - 3, 'x')));
  const auto control = EncodedFrame::from(Json{{"event", "stream_retired"}}, 4096);
  constexpr std::uint64_t initial_hash = 14695981039346656037ULL;
  std::uint64_t expected = initial_hash, actual = initial_hash;
  std::size_t expected_bytes = 0, received_bytes = 0;
  auto observe = [&](const EncodedFrame &frame) { expected = hash(expected, frame.bytes()); expected_bytes += frame.size(); };
  for (unsigned index = 0; index < 8; ++index) { CHECK(output.report(maximum)); observe(maximum); }
  CHECK(!output.report(control) && output.report_bytes() == 1048576);
  std::vector<NativeOutput::ReplySlot> slots;
  for (unsigned index = 0; index < 64; ++index) {
    // NOLINTNEXTLINE(bugprone-unchecked-optional-access): CHECK ends the test when a slot is empty
    auto slot = output.reserve_reply(); CHECK(slot && output.reply(*slot, maximum)); slots.push_back(*slot); observe(maximum);
  }
  CHECK(output.control(control)); observe(control); // independent reservation under report/reply pressure
  std::array<char, 8192> buffer{};
  std::size_t padding = 0;
  for (;;) {
    const auto count = ::write(pipe.write(), buffer.data(), buffer.size());
    if (count < 0) { CHECK(errno == EAGAIN || errno == EWOULDBLOCK); break; }
    CHECK(count > 0); padding += static_cast<std::size_t>(count);
  }
  const auto retained = output.retained_bytes(), frames = output.pending_frames(); output.flush(pipe.write());
  CHECK(output.retained_bytes() == retained && output.pending_frames() == frames && output.reply_reservations() == 64);
  while (padding) {
    const auto count = ::read(pipe.read(), buffer.data(), std::min(padding, buffer.size())); CHECK(count > 0); padding -= static_cast<std::size_t>(count);
  }
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while ((output.pending_frames() || received_bytes < expected_bytes) && std::chrono::steady_clock::now() < deadline) {
    output.flush(pipe.write());
    for (;;) {
      const auto count = ::read(pipe.read(), buffer.data(), buffer.size());
      if (count < 0) { CHECK(errno == EAGAIN || errno == EWOULDBLOCK); break; }
      CHECK(count > 0); received_bytes += static_cast<std::size_t>(count);
      actual = hash(actual, {buffer.data(), static_cast<std::size_t>(count)});
    }
  }
  CHECK(received_bytes == expected_bytes && actual == expected && !output.pending_frames() && !output.retained_bytes() &&
    !output.reply_reservations() && !output.control_frames() && !output.report_frames() && !output.report_bytes());
  CHECK(!output.reply(slots.front(), control) && !output.release_reply(slots.front()));
  CHECK(output.control(control)); ::close(pipe.values[0]); pipe.values[0] = -1;
  bool closed = false; try { output.flush(pipe.write()); } catch (const std::runtime_error &error) { closed = std::string(error.what()) == "output_closed"; }
  CHECK(closed && output.pending_frames() == 1);
  Pipe blocking(false); bool rejected = false;
  try { output.flush(blocking.write()); } catch (const std::runtime_error &error) { rejected = std::string(error.what()) == "invalid_output"; }
  CHECK(rejected);
  std::cout << "native output pipe ownership passed\n";
}
int main(int argc, char **argv) {
  std::signal(SIGPIPE, SIG_IGN);
  try {
    if (argc == 3 && std::string(argv[1]) == "--serialize-input") {
      const auto input = parse_line(std::string(argv[2]) + "\n");
      CHECK(fields(input, {"value", "limit"}) && integer(input.at("limit"), 1, max_line));
      Json result;
      try {
        const auto encoded = EncodedFrame::from(input.at("value"), input.at("limit").get<std::size_t>());
        result = {{"accepted", true}, {"line", encoded.bytes()}, {"bytes", encoded.size()}};
      } catch (const InvalidFrame &) { result = {{"accepted", false}}; }
      std::cout << result.dump() << '\n'; return 0;
    }
    if (argc == 3 && std::string(argv[1]) == "--encode") {
      std::cout << EncodedFrame::from(parse_line(std::string(argv[2]) + "\n")).bytes(); return 0;
    }
    if (argc != 2) return 2;
    const std::string operation = argv[1];
    if (operation == "serialization") serialization();
    else if (operation == "capacity") capacity();
    else if (operation == "pipes") pipes();
    else return 2;
    return 0;
  } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
}
