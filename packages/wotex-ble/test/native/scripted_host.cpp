// SPDX-License-Identifier: Apache-2.0
// Test-only scripted native protocol peer for the BEAM Connection,
// SubscriptionOwner and Runtime relay contracts. It links no SDK and opens no
// D-Bus sender. The executable path plus ".json" selects one scripted scenario;
// received requests, submitted-write events and the close or EOF ledger are
// appended to the path plus ".jsonl". Framing, request order, reply/control
// output, discovery cursors, report credit, deferred reports and stream barriers
// use the production components. Every reply value is a scripted input, so this
// process proves BEAM adapter contracts only, never BlueZ or D-Bus behavior.
#include "pages.hpp"
#include "reports.hpp"
#include <array>
#include <csignal>
#include <fstream>
#include <poll.h>
#include <sstream>
#include <sys/random.h>
#include <unistd.h>

namespace {
using namespace wotex::ble;
using Steady = std::chrono::steady_clock;

const std::set<std::string> known_modes{
  "wrong_ready", "silent", "oversize", "truncated", "uncooperative", "open_error", "close_slow",
  "discover_blocked", "discover_slow", "discover_error", "discover_invalid_frame", "discover_wrong_id",
  "health_error", "health_blocked", "procedure_blocked", "procedure_error", "procedure_crash",
  "procedure_slow", "procedure_missing_event", "procedure_wrong_event", "procedure_extra_event",
  "procedure_duplicate_event", "procedure_malformed", "procedure_read_event", "subscribe_blocked",
  "subscribe_error", "stop_blocked", "stop_error", "stop_bad_ack", "stop_lost", "stop_slow",
  "report_wrong_generation", "report_wrong_metadata", "report_extra", "report_unknown", "read_overtaken",
  "repeat", "subscribe_wrong_binding", "close_blocked", "close_drain"};

struct Scenario {
  std::set<std::string> modes;
  std::size_t characteristics = 2;
  Json flags = Json::array({"read", "future-flag"});
  Json value = AttributeBytes::from_bytes(std::string("\x2a\x00", 2)).envelope();
  Json early = Json::array();
  std::size_t read_reports = 0;
  Json error = {{"code", "remote_error"}};
  Json challenge = {{"kind", "confirm_passkey"}, {"value", 123456}};

  static Scenario load(const std::string &path) {
    std::ifstream file(path, std::ios::binary);
    std::stringstream bytes;
    bytes << file.rdbuf();
    if (!file) throw std::runtime_error("scenario");
    const auto input = Json::parse(bytes.str());
    Scenario scenario;
    for (const auto &[key, value] : input.items()) {
      if (key == "modes") for (const auto &item : value) scenario.modes.insert(item.get<std::string>());
      else if (key == "characteristics") scenario.characteristics = value.get<std::size_t>();
      else if (key == "flags") scenario.flags = value;
      else if (key == "value") scenario.value = AttributeBytes::from(value).envelope();
      else if (key == "early") scenario.early = value;
      else if (key == "read_reports") scenario.read_reports = value.get<std::size_t>();
      else if (key == "error") scenario.error = value;
      else if (key == "challenge") scenario.challenge = value;
      else throw std::runtime_error("scenario");
    }
    if (!std::all_of(scenario.modes.begin(), scenario.modes.end(), [](const std::string &item) { return known_modes.count(item) != 0; }) ||
        scenario.characteristics < 1 || scenario.characteristics > 1024 ||
        !scenario.flags.is_array() || !scenario.early.is_array() || !native_error(scenario.error)) throw std::runtime_error("scenario");
    for (const auto &early : scenario.early) AttributeBytes::from(early);
    return scenario;
  }
};

class Record {
  std::string path_;
public:
  explicit Record(std::string path) : path_(std::move(path)) {}
  void write(const Json &value) const {
    std::ofstream file(path_, std::ios::app | std::ios::binary);
    file << value.dump() << '\n';
    if (!file.flush()) throw std::runtime_error("record");
  }
};

bool nonblocking(int descriptor) {
  const int flags = ::fcntl(descriptor, F_GETFL);
  return flags >= 0 && ::fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0;
}

void raw(std::string_view bytes) {
  while (!bytes.empty()) {
    const auto written = ::write(STDOUT_FILENO, bytes.data(), bytes.size());
    if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
      pollfd descriptor{STDOUT_FILENO, POLLOUT, 0};
      ::poll(&descriptor, 1, 5);
      continue;
    }
    if (written <= 0) throw std::runtime_error("output_closed");
    bytes.remove_prefix(static_cast<std::size_t>(written));
  }
}

std::string random_token() {
  std::array<unsigned char, 16> bytes{};
  if (::getentropy(bytes.data(), bytes.size()) != 0) throw std::runtime_error("resource_limit");
  constexpr char alphabet[] = "0123456789abcdef";
  std::string result;
  for (const auto byte : bytes) { result += alphabet[byte >> 4]; result += alphabet[byte & 15]; }
  return result;
}

bool flag(const Json &flags, const char *name) {
  return std::any_of(flags.begin(), flags.end(), [name](const Json &item) { return item == name; });
}

class Script {
  struct Pending {
    std::string id, operation;
    Json parameters;
    NativeOutput::ReplySlot slot;
  };
  struct Stream { std::string path; Json metadata; bool silenced = false; };
  struct Timer { Steady::time_point at; std::function<void()> action; };

  const Scenario scenario_;
  const Record record_;
  NativeOutput output_;
  Sequence sequence_;
  NativePages pages_{random_token};
  std::unique_ptr<NativeReports> reports_;
  std::string generation_;
  Json characteristics_ = Json::array();
  std::map<std::string, Json> values_;
  Json peer_;
  std::vector<Pending> pending_;
  std::map<std::uint64_t, Stream> streams_;
  std::vector<Timer> timers_;
  std::optional<std::string> overtaken_, challenge_;
  std::uint64_t challenges_ = 0;
  bool closed_ = false, close_replied_ = false, stalled_ = false, faulted_ = false, overtook_ = false;

  static std::uint64_t number(const std::string &text) {
    std::uint64_t value = 0;
    for (char digit : text) {
      if (digit < '0' || digit > '9') throw InvalidFrame();
      value = value * 10 + static_cast<unsigned>(digit - '0');
    }
    return value;
  }
  bool mode(const char *name) const { return scenario_.modes.count(name) != 0; }
  void after(unsigned milliseconds, std::function<void()> action) {
    timers_.push_back({Steady::now() + std::chrono::milliseconds(milliseconds), std::move(action)});
  }
  void emit(const Json &frame) {
    if (!output_.control(EncodedFrame::from(frame, NativeOutput::control_frame_limit))) throw InvalidFrame();
  }
  Pending take(const std::string &id) {
    const auto found = std::find_if(pending_.begin(), pending_.end(), [&](const Pending &item) { return item.id == id; });
    if (found == pending_.end()) throw InvalidFrame();
    auto pending = std::move(*found);
    pending_.erase(found);
    return pending;
  }
  void answer(const std::string &id, const Json &frame) {
    if (closed_) return;
    const auto pending = take(id);
    if (!output_.reply(pending.slot, EncodedFrame::from(frame))) throw InvalidFrame();
  }
  void reply(const std::string &id, const Json &result) {
    answer(id, {{"version", 1}, {"id", id}, {"ok", true}, {"result", result}});
  }
  void fail(const std::string &id, const Json &error) {
    answer(id, {{"version", 1}, {"id", id}, {"ok", false}, {"error", error}});
  }
  void fail(const std::string &id, const char *code) { fail(id, Json{{"code", code}}); }
  void ledger(const char *event) {
    Json pending = Json::array();
    for (const auto &item : pending_) pending.push_back(item.operation);
    record_.write({{event, true}, {"streams", streams_.size()}, {"pending", pending}});
  }

  // Selects one scripted characteristic by the exact address fields the BEAM sent.
  std::optional<std::size_t> resolve(const std::string &id, const Json &address) {
    std::vector<std::size_t> matches;
    const char *failure = "invalid_characteristic";
    for (std::size_t index = 0; index < characteristics_.size(); ++index) {
      const auto &item = characteristics_[index];
      if (item.at("service_uuid") != address.at("service") || item.at("characteristic_uuid") != address.at("characteristic")) continue;
      if (!address.at("object_path").is_null() && item.at("object_path") != address.at("object_path")) continue;
      if (!address.at("handle").is_null() && item.at("handle") != address.at("handle")) continue;
      if (!address.at("generation").is_null() && item.at("generation") != address.at("generation")) { failure = "stale_discovery"; continue; }
      matches.push_back(index);
    }
    if (matches.size() == 1) return matches.front();
    fail(id, matches.empty() ? failure : "ambiguous_characteristic");
    return std::nullopt;
  }

  void open(const std::string &id, const Json &parameters) {
    peer_ = parameters.at("peer");
    if (mode("open_error")) { fail(id, scenario_.error); return; }
    reply(id, {{"generation", 1}, {"device_path", "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"},
      {"link_owned", parameters.at("connection") == "owned"}, {"sender", ":1.1"}});
  }
  void page(const std::string &id, const Json &parameters) {
    try {
      const auto request = PageRequest::from(parameters);
      reply(id, pages_.page(request, id, characteristics_, 1));
    } catch (const PageFailure &failure) { fail(id, failure.what()); }
  }
  void discover(const std::string &id, const Json &parameters) {
    if (mode("discover_blocked")) return;
    if (mode("discover_error")) { fail(id, scenario_.error); return; }
    if (mode("discover_invalid_frame")) { output_.flush(STDOUT_FILENO); raw("{\"version\":1,\"version\":1}\n"); return; }
    if (mode("discover_wrong_id")) { emit({{"version", 1}, {"id", "foreign"}, {"ok", true}, {"result", nullptr}}); return; }
    if (mode("discover_slow")) { after(50, [this, id, parameters] { page(id, parameters); }); return; }
    page(id, parameters);
  }
  void health(const std::string &id) {
    if (mode("health_blocked")) return;
    if (mode("health_error")) { fail(id, scenario_.error); return; }
    reply(id, {{"connected", true}, {"services_resolved", true}});
  }
  void read(const std::string &id, const Json &parameters) {
    const auto index = resolve(id, parameters.at("address"));
    if (!index) return;
    const auto &item = characteristics_[*index];
    if (!flag(item.at("flags"), "read")) { fail(id, "not_permitted"); return; }
    if (mode("procedure_blocked")) return;
    if (mode("procedure_error")) { fail(id, scenario_.error); return; }
    if (mode("read_overtaken") && !std::exchange(overtook_, true)) { overtaken_ = id; return; }
    const auto path = item.at("object_path").get<std::string>();
    const auto value = values_.count(path) ? values_.at(path) : scenario_.value;
    for (std::size_t count = 0; count < scenario_.read_reports; ++count) changed(path, value);
    if (mode("procedure_read_event")) submitted({{"version", 1}, {"id", id}, {"event", "write_submitted"}});
    reply(id, value);
  }
  void submitted(const Json &event) {
    record_.write({{"submitted", event.at("id")}});
    emit(event);
  }
  void write(const std::string &id, const Json &parameters) {
    const auto index = resolve(id, parameters.at("address"));
    if (!index) return;
    const auto &item = characteristics_[*index];
    if (!flag(item.at("flags"), "write")) { fail(id, "not_permitted"); return; }
    Json value;
    try { value = AttributeBytes::from(parameters.at("value")).envelope(); }
    catch (const InvalidValue &) { fail(id, "invalid_value"); return; }
    if (mode("procedure_crash")) { output_.flush(STDOUT_FILENO); ::_exit(0); }
    Json event{{"version", 1}, {"id", id}, {"event", "write_submitted"}};
    if (mode("procedure_wrong_event")) event["id"] = "foreign";
    if (mode("procedure_extra_event")) event["extra"] = true;
    if (!mode("procedure_missing_event")) submitted(event);
    if (mode("procedure_duplicate_event")) submitted(event);
    if (mode("procedure_blocked")) return;
    if (mode("procedure_error")) { fail(id, scenario_.error); return; }
    if (mode("procedure_malformed")) { reply(id, true); return; }
    values_[item.at("object_path").get<std::string>()] = value;
    if (mode("procedure_slow")) { after(50, [this, id] { reply(id, nullptr); }); return; }
    reply(id, nullptr);
  }
  void pair(const std::string &id) {
    challenge_ = id;
    emit({{"version", 1}, {"id", id}, {"event", "agent_challenge"},
      {"challenge", {{"id", id + ":" + std::to_string(++challenges_)}, {"peer", peer_},
        {"kind", scenario_.challenge.at("kind")}, {"value", scenario_.challenge.at("value")}, {"timeout_ms", 60000}}}});
  }
  void agent_reply(const std::string &id, const Json &parameters) {
    if (!challenge_) { fail(id, "pairing_rejected"); return; }
    const auto pair = *std::exchange(challenge_, std::nullopt);
    const auto &action = parameters.at("decision").at("action");
    const auto &kind = scenario_.challenge.at("kind");
    const bool accepted = (kind == "confirm_passkey" && action == "accept") ||
      (kind == "request_pin" && action == "pin") || (kind == "request_passkey" && action == "passkey");
    reply(id, nullptr);
    if (accepted) reply(pair, {{"paired", true}});
    else fail(pair, "pairing_rejected");
  }

  void publish(std::uint64_t stream, const Json &value) {
    if (streams_.at(stream).silenced) return;
    const auto &metadata = streams_.at(stream).metadata;
    Json report{{"version", 1}, {"subscription_id", std::to_string(stream)}, {"generation", 1},
      {"event", "value"}, {"value", value}, {"metadata", metadata}};
    if (!faulted_ && (mode("report_wrong_generation") || mode("report_wrong_metadata") ||
                      mode("report_extra") || mode("report_unknown"))) {
      faulted_ = true;
      Json forged = report;
      forged["session_generation"] = generation_;
      forged["report_sequence"] = 1;
      if (mode("report_wrong_generation")) forged["generation"] = 2;
      if (mode("report_wrong_metadata")) forged["metadata"]["effective_mode"] = "indicate";
      if (mode("report_extra")) forged["extra"] = true;
      if (mode("report_unknown")) forged["subscription_id"] = "999";
      emit(forged);
      return;
    }
    if (!reports_->publish(report)) retire(stream, Json{{"code", "queue_overflow"}});
  }
  void changed(const std::string &path, const Json &value) {
    std::vector<std::uint64_t> selected;
    for (const auto &[id, stream] : streams_) if (stream.path == path) selected.push_back(id);
    for (const auto id : selected) if (streams_.count(id)) publish(id, value);
  }
  void silence(std::uint64_t stream) {
    streams_.at(stream).silenced = true;
    reports_->silence(stream);
  }
  void retire(std::uint64_t stream, const std::optional<Json> &failure = std::nullopt) {
    if (reports_->retire(stream, failure)) streams_.erase(stream);
  }
  void subscribe(const std::string &id, const Json &parameters) {
    if (mode("subscribe_blocked")) return;
    if (mode("subscribe_error")) { fail(id, scenario_.error); return; }
    const auto index = resolve(id, parameters.at("address"));
    if (!index) return;
    const auto &item = characteristics_[*index];
    const auto path = item.at("object_path").get<std::string>();
    for (const auto &[unused, stream] : streams_) { (void)unused; if (stream.path == path) { fail(id, "already_subscribed"); return; } }
    const bool notify = flag(item.at("flags"), "notify"), indicate = flag(item.at("flags"), "indicate");
    const auto requested = parameters.at("mode").get<std::string>();
    std::string effective;
    if (notify && indicate) effective = requested == "auto" ? "bluez_selected" : "";
    else if (notify && requested != "indicate") effective = "notify";
    else if (indicate && requested != "notify") effective = "indicate";
    if (effective.empty()) { fail(id, notify && indicate ? "unsupported_procedure_selection" : "not_supported"); return; }
    const auto stream = number(id);
    const Json metadata{{"source", "bluez_value_change"}, {"characteristic", item},
      {"requested_mode", requested}, {"effective_mode", effective}};
    if (!reports_->open(stream, metadata, parameters.at("queue_limit").get<std::size_t>())) { fail(id, "resource_limit"); return; }
    streams_.emplace(stream, Stream{path, metadata});
    reply(id, {{"subscription_id", mode("subscribe_wrong_binding") ? std::string("foreign") : id}, {"generation", 1}, {"characteristic", item},
      {"requested_mode", requested}, {"effective_mode", effective}});
    for (const auto &value : scenario_.early) if (streams_.count(stream)) publish(stream, value);
    if (mode("repeat")) {
      after(50, [this, stream] {
        for (unsigned count = 0; count < 2; ++count)
          if (streams_.count(stream)) publish(stream, scenario_.early.at(0));
      });
    }
  }
  void unsubscribe(const std::string &id, const Json &parameters) {
    const auto &text = parameters.at("subscription_id");
    std::uint64_t stream = 0;
    try { stream = number(text.get<std::string>()); } catch (...) { fail(id, "invalid_subscription"); return; }
    if (!streams_.count(stream)) { fail(id, "invalid_subscription"); return; }
    silence(stream);
    if (mode("stop_blocked")) return;
    if (mode("stop_error")) { fail(id, scenario_.error); return; }
    if (mode("stop_lost")) { retire(stream); return; }
    if (mode("stop_bad_ack")) { retire(stream); reply(id, true); return; }
    if (mode("stop_slow")) { after(50, [this, id, stream] { retire(stream); reply(id, nullptr); }); return; }
    retire(stream);
    reply(id, nullptr);
    if (overtaken_) {
      const auto read = *std::exchange(overtaken_, std::nullopt);
      reply(read, scenario_.value);
    }
  }
  void close() {
    ledger("closed");
    closed_ = true;
    const auto finish = [this] {
      for (const auto &[stream, unused] : streams_) { (void)unused; silence(stream); }
      const auto slot = output_.reserve_reply();
      if (!slot || !output_.reply(*slot, EncodedFrame::from(Json{{"version", 1}, {"id", "close"}, {"ok", true}, {"result", nullptr}})))
        throw InvalidFrame();
      close_replied_ = true;
    };
    if (mode("close_blocked")) return;
    if (mode("close_slow")) after(50, finish);
    // A real host may reply after using its complete 500 ms cooperative allowance.
    else if (mode("close_drain")) after(560, finish);
    else finish();
  }

public:
  Script(Scenario scenario, Record record) : scenario_(std::move(scenario)), record_(std::move(record)) {
    for (std::size_t index = 0; index < scenario_.characteristics; ++index) {
      characteristics_.push_back({{"service_uuid", "0000180f-0000-1000-8000-00805f9b34fb"},
        {"characteristic_uuid", "00002a19-0000-1000-8000-00805f9b34fb"}, {"service_path", "/another"},
        {"object_path", "/another/characteristic" + std::to_string(index)}, {"handle", index + 1},
        {"generation", 1}, {"flags", scenario_.flags}});
    }
    std::sort(characteristics_.begin(), characteristics_.end(), [](const Json &left, const Json &right) {
      return left.at("object_path").get_ref<const std::string &>() < right.at("object_path").get_ref<const std::string &>();
    });
    const std::string revision = mode("wrong_ready") ? "0.0.0" : "2123ab772fbe97d1369fc9e179ea87c3469cf98f";
    emit({{"version", 1}, {"event", "ready"}, {"backend", "bluez-native"}, {"revision", revision}});
  }
  void receive(const Json &frame) {
    if (frame.contains("event")) {
      if (frame.at("event") == "flow_open" && !reports_) {
        generation_ = frame.at("session_generation").get<std::string>();
        reports_ = std::make_unique<NativeReports>(output_, generation_);
      } else if (reports_) {
        reports_->acknowledge(frame);
      } else throw InvalidFrame();
      return;
    }
    if (!reports_ || !sequence_.accept(frame)) throw InvalidFrame();
    const auto id = frame.at("id").get<std::string>();
    const auto operation = frame.at("operation").get<std::string>();
    record_.write({{"wire_id", id}, {"operation", operation}});
    if (closed_) return;
    if (operation == "close") { close(); return; }
    const auto slot = output_.reserve_reply();
    if (!slot) throw InvalidFrame();
    const auto &parameters = frame.at("parameters");
    pending_.push_back({id, operation, parameters, *slot});
    if (operation == "open") open(id, parameters);
    else if (operation == "discover") discover(id, parameters);
    else if (operation == "health") health(id);
    else if (operation == "read") read(id, parameters);
    else if (operation == "write") write(id, parameters);
    else if (operation == "pair") pair(id);
    else if (operation == "agent_reply") agent_reply(id, parameters);
    else if (operation == "subscribe") subscribe(id, parameters);
    else if (operation == "unsubscribe") unsubscribe(id, parameters);
    else throw InvalidFrame();
    if (mode("uncooperative") && operation == "open") stalled_ = true;
  }
  void eof() { ledger("eof"); }
  int wait() const {
    auto wait = std::chrono::milliseconds(5);
    for (const auto &timer : timers_)
      wait = std::min(wait, std::max(std::chrono::milliseconds(0),
        std::chrono::duration_cast<std::chrono::milliseconds>(timer.at - Steady::now())));
    return static_cast<int>(wait.count());
  }
  void run_timers() {
    const auto now = Steady::now();
    std::vector<Timer> due;
    for (auto item = timers_.begin(); item != timers_.end();) {
      if (item->at <= now) { due.push_back(std::move(*item)); item = timers_.erase(item); }
      else ++item;
    }
    for (auto &timer : due) timer.action();
  }
  void flush() { output_.flush(STDOUT_FILENO); }
  bool pending() const { return output_.pending_frames() != 0; }
  bool finished() const { return close_replied_ && !pending(); }
  bool stalled() const { return stalled_ && !pending(); }
};
} // namespace

int main(int argc, char **argv) {
  if (argc != 1) return 2;
  std::signal(SIGPIPE, SIG_IGN);
  try {
    const std::string executable(*argv);
    const Record record(executable + ".jsonl");
    record.write({{"pid", ::getpid()}});
    auto scenario = Scenario::load(executable + ".json");
    if (scenario.modes.count("silent")) for (;;) ::pause();
    if (scenario.modes.count("oversize")) { raw(std::string(131073, 'x') + "\n"); for (;;) ::pause(); }
    if (scenario.modes.count("truncated")) { raw("{\"version\":1"); return 0; }
    if (scenario.modes.count("uncooperative")) std::signal(SIGTERM, SIG_IGN);
    if (!nonblocking(STDIN_FILENO) || !nonblocking(STDOUT_FILENO)) return 2;
    Script script(std::move(scenario), record);
    Lines lines;
    for (;;) {
      script.flush();
      if (script.finished()) return 0;
      if (script.stalled()) for (;;) ::pause();
      std::array<pollfd, 2> descriptors{{{STDIN_FILENO, POLLIN, 0},
        {STDOUT_FILENO, static_cast<short>(script.pending() ? POLLOUT : 0), 0}}};
      if (::poll(descriptors.data(), descriptors.size(), script.wait()) < 0 && errno != EINTR) return 1;
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
          if (!count) { script.eof(); lines.eof(); return 1; }
          lines.feed(std::string_view(bytes.data(), static_cast<std::size_t>(count)),
            [&](std::string_view line) { script.receive(parse_line(line)); });
        }
      }
      script.run_timers();
    }
  } catch (...) { return 1; }
}
