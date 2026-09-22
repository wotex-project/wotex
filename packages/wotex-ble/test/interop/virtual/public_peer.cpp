/* SPDX-License-Identifier: Apache-2.0 */
/* Test-only virtual-controller GATT provider. GDBus is deliberately independent
 * from the production libdbus client. The Unix control socket supplies fixture
 * stimuli and observations only; it never answers client transport requests. */
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <glib-unix.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

#include "json.hpp"

using Json = nlohmann::json;

namespace {

constexpr const char *kProperties = "org.freedesktop.DBus.Properties";
constexpr const char *kObjectManager = "org.freedesktop.DBus.ObjectManager";
constexpr const char *kAdapter = "org.bluez.Adapter1";
constexpr const char *kCharacteristic = "org.bluez.GattCharacteristic1";
constexpr const char *kService = "org.bluez.GattService1";
constexpr const char *kDevice = "org.bluez.Device1";
constexpr const char *kAgent = "org.bluez.Agent1";
constexpr const char *kAdvertisement = "org.bluez.LEAdvertisement1";
constexpr const char *kServiceUuid = "9bf00000-4689-4b5b-bdea-8d9f7c1b6000";
constexpr const char *kRoot = "/fixture";
constexpr const char *kServicePath = "/fixture/service0";
constexpr const char *kExpectedDevice = "/org/bluez/hci1/dev_00_AA_01_00_00_00";
constexpr const char *kBluez = "org.bluez";
constexpr const char *kBus = "org.freedesktop.DBus";
constexpr const char *kBusPath = "/org/freedesktop/DBus";

const std::array<std::string, 5> kLabels = {"value", "notify", "indicate", "duplicate_a",
                                            "duplicate_b"};

const std::map<std::string, std::string> kUuids = {
    {"value", "9bf00001-4689-4b5b-bdea-8d9f7c1b6000"},
    {"notify", "9bf00002-4689-4b5b-bdea-8d9f7c1b6000"},
    {"indicate", "9bf00003-4689-4b5b-bdea-8d9f7c1b6000"},
    {"duplicate_a", "9bf00004-4689-4b5b-bdea-8d9f7c1b6000"},
    {"duplicate_b", "9bf00004-4689-4b5b-bdea-8d9f7c1b6000"}};

const std::map<std::string, std::vector<std::string>> kFlags = {{"value", {"read", "write"}},
                                                                {"notify", {"read", "notify"}},
                                                                {"indicate", {"read", "indicate"}},
                                                                {"duplicate_a", {"read"}},
                                                                {"duplicate_b", {"read"}}};

struct VariantDeleter {
  void operator()(GVariant *value) const {
    if (value) g_variant_unref(value);
  }
};
using Variant = std::unique_ptr<GVariant, VariantDeleter>;

struct ErrorDeleter {
  void operator()(GError *error) const {
    if (error) g_error_free(error);
  }
};
using Error = std::unique_ptr<GError, ErrorDeleter>;

struct ObjectDeleter {
  void operator()(gpointer value) const {
    if (value) g_object_unref(value);
  }
};

template <typename T> using Object = std::unique_ptr<T, ObjectDeleter>;

[[noreturn]] void fail(const std::string &message) { throw std::runtime_error(message); }

void require(bool condition, const std::string &message) {
  if (!condition) fail(message);
}

std::string hex(const std::vector<std::uint8_t> &bytes) {
  std::ostringstream stream;
  stream << std::hex << std::setfill('0');
  for (std::uint8_t byte : bytes) stream << std::setw(2) << static_cast<unsigned>(byte);
  return stream.str();
}

std::vector<std::uint8_t> decode_hex(const std::string &encoded) {
  require(encoded.size() <= 1024 && encoded.size() % 2 == 0, "invalid_value");
  std::vector<std::uint8_t> output;
  output.reserve(encoded.size() / 2);
  for (std::size_t index = 0; index < encoded.size(); index += 2) {
    const auto digit = [](char value) -> int {
      if (value >= '0' && value <= '9') return value - '0';
      if (value >= 'a' && value <= 'f') return value - 'a' + 10;
      return -1;
    };
    int high = digit(encoded[index]), low = digit(encoded[index + 1]);
    require(high >= 0 && low >= 0, "invalid_value");
    output.push_back(static_cast<std::uint8_t>((high << 4) | low));
  }
  return output;
}

GVariant *bytes(const std::vector<std::uint8_t> &value) {
  return g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, value.empty() ? nullptr : value.data(),
                                   value.size(), sizeof(std::uint8_t));
}

std::vector<std::uint8_t> byte_vector(GVariant *value) {
  require(value && g_variant_is_of_type(value, G_VARIANT_TYPE("ay")), "invalid byte array");
  gsize count = 0;
  const auto *data = static_cast<const std::uint8_t *>(
      g_variant_get_fixed_array(value, &count, sizeof(std::uint8_t)));
  return count == 0 ? std::vector<std::uint8_t>() : std::vector<std::uint8_t>(data, data + count);
}

struct AsyncCall {
  GMainLoop *loop = nullptr;
  GVariant *result = nullptr;
  GError *error = nullptr;
};

void call_finished(GObject *source, GAsyncResult *result, gpointer data) {
  auto *call = static_cast<AsyncCall *>(data);
  call->result = g_dbus_connection_call_finish(reinterpret_cast<GDBusConnection *>(source), result,
                                               &call->error);
  g_main_loop_quit(call->loop);
}

Variant call(GDBusConnection *connection, const char *destination, const char *path,
             const char *interface, const char *member, GVariant *parameters = nullptr,
             const GVariantType *reply = nullptr, int timeout_ms = 10000) {
  AsyncCall state;
  state.loop = g_main_loop_new(nullptr, FALSE);
  require(state.loop != nullptr, "main loop allocation failed");
  g_dbus_connection_call(connection, destination, path, interface, member, parameters, reply,
                         G_DBUS_CALL_FLAGS_NONE, timeout_ms, nullptr, call_finished, &state);
  g_main_loop_run(state.loop);
  g_main_loop_unref(state.loop);
  Error error(state.error);
  if (error) fail(std::string("D-Bus call failed: ") + error->message);
  require(state.result != nullptr, "D-Bus call returned no result");
  return Variant(state.result);
}

Object<GDBusConnection> connect_bus(const std::string &address) {
  GError *raw_error = nullptr;
  GDBusConnection *connection = g_dbus_connection_new_for_address_sync(
      address.c_str(),
      // GLib models this bitmask as an enum even though callers combine flags.
      // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
      static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                        G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &raw_error);
  Error error(raw_error);
  if (error) fail(std::string("D-Bus connection failed: ") + error->message);
  require(connection != nullptr, "D-Bus connection missing");
  g_dbus_connection_set_exit_on_close(connection, FALSE);
  return Object<GDBusConnection>(connection);
}

std::set<std::string> list_names(GDBusConnection *connection) {
  Variant reply = call(connection, kBus, kBusPath, kBus, "ListNames", nullptr,
                       G_VARIANT_TYPE("(as)"));
  Variant names(g_variant_get_child_value(reply.get(), 0));
  GVariantIter iterator;
  const char *name = nullptr;
  std::set<std::string> output;
  g_variant_iter_init(&iterator, names.get());
  while (g_variant_iter_next(&iterator, "&s", &name)) output.insert(name);
  return output;
}

std::optional<std::string> property_string(GVariant *properties, const char *name,
                                           const GVariantType *type) {
  Variant value(g_variant_lookup_value(properties, name, type));
  if (!value) return std::nullopt;
  return std::string(g_variant_get_string(value.get(), nullptr));
}

std::optional<bool> property_boolean(GVariant *properties, const char *name) {
  Variant value(g_variant_lookup_value(properties, name, G_VARIANT_TYPE_BOOLEAN));
  if (!value) return std::nullopt;
  return g_variant_get_boolean(value.get()) != FALSE;
}

Variant interface_properties(GVariant *interfaces, const char *wanted) {
  GVariantIter iterator;
  const char *name = nullptr;
  GVariant *properties = nullptr;
  g_variant_iter_init(&iterator, interfaces);
  while (g_variant_iter_next(&iterator, "{&s@a{sv}}", &name, &properties)) {
    if (std::string(name) == wanted) return Variant(properties);
    g_variant_unref(properties);
  }
  return Variant(nullptr);
}

struct ObjectEntry {
  std::string path;
  Variant interfaces;
  ObjectEntry(std::string path_value, GVariant *interfaces_value)
      : path(std::move(path_value)), interfaces(interfaces_value) {}
  ObjectEntry(ObjectEntry &&) noexcept = default;
  ObjectEntry &operator=(ObjectEntry &&) noexcept = default;
  ObjectEntry(const ObjectEntry &) = delete;
  ObjectEntry &operator=(const ObjectEntry &) = delete;
};

std::vector<ObjectEntry> object_entries(GVariant *reply) {
  Variant objects(g_variant_get_child_value(reply, 0));
  GVariantIter iterator;
  const char *path = nullptr;
  GVariant *interfaces = nullptr;
  std::vector<ObjectEntry> output;
  g_variant_iter_init(&iterator, objects.get());
  while (g_variant_iter_next(&iterator, "{&o@a{sa{sv}}}", &path, &interfaces))
    output.emplace_back(path, interfaces);
  return output;
}

class OwnershipMonitor {
 public:
  explicit OwnershipMonitor(const std::string &address) : connection_(connect_bus(address)) {
    Variant owner = call(connection_.get(), kBus, kBusPath, kBus, "GetNameOwner",
                         g_variant_new("(s)", kBluez), G_VARIANT_TYPE("(s)"));
    const char *name = nullptr;
    g_variant_get(owner.get(), "(&s)", &name);
    bluez_owner_ = name;
    filter_ = g_dbus_connection_add_filter(connection_.get(), filter, this, nullptr);
    GVariantBuilder rules;
    g_variant_builder_init(&rules, G_VARIANT_TYPE("as"));
    Variant monitored = call(
        connection_.get(), kBus, kBusPath, "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
        g_variant_new("(@asu)", g_variant_builder_end(&rules), 0U), G_VARIANT_TYPE("()"));
    (void)monitored;
  }

  ~OwnershipMonitor() {
    if (filter_) g_dbus_connection_remove_filter(connection_.get(), filter_);
    if (connection_) g_dbus_connection_close_sync(connection_.get(), nullptr, nullptr);
  }

  void watch(const std::string &sender) {
    std::lock_guard<std::mutex> lock(mutex_);
    require(senders_.count(sender) || senders_.size() < 64, "native fixture sender bound exceeded");
    senders_.insert(sender);
  }

  Json snapshot_counts() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!failure_.empty()) fail(failure_);
    Json calls = Json::object();
    for (const auto &[sender, path, interface, member] : calls_) {
      (void)path;
      (void)interface;
      if (senders_.count(sender)) calls[member] = calls.value(member, 0U) + 1U;
    }
    return {{"agents", agents_.size()},
            {"notification_sessions", notifications_.size()},
            {"pending_controls", pending_.size()},
            {"calls", calls}};
  }

  void assert_released() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!failure_.empty()) fail(failure_);
    require(agents_.empty(), "fixture agents retained");
    require(notifications_.empty(), "fixture notifications retained");
    require(pending_.empty(), "fixture controls retained");
  }

  void reset_traces() {
    std::lock_guard<std::mutex> lock(mutex_);
    senders_.clear();
    calls_.clear();
    acknowledgements_.clear();
  }

 private:
  struct Pending {
    std::string member;
    std::string target;
  };

  using PendingKey = std::pair<std::string, guint32>;

  static GDBusMessage *filter(GDBusConnection *, GDBusMessage *message, gboolean incoming,
                              gpointer data) {
    auto *monitor = static_cast<OwnershipMonitor *>(data);
    try {
      monitor->account(message);
    } catch (const std::exception &error) {
      std::lock_guard<std::mutex> lock(monitor->mutex_);
      monitor->failure_ = error.what();
    } catch (...) {
      std::lock_guard<std::mutex> lock(monitor->mutex_);
      monitor->failure_ = "private D-Bus monitor failure";
    }
    // A monitor receives copies of every bus message. Returning an incoming
    // method call to GDBus dispatch would synthesize UnknownMethod from this
    // read-only connection, which the bus correctly closes. The outgoing
    // BecomeMonitor call and its incoming reply still need normal dispatch.
    if (incoming && g_dbus_message_get_message_type(message) == G_DBUS_MESSAGE_TYPE_METHOD_CALL)
      return nullptr;
    return message;
  }

  static std::string first_object_path(GDBusMessage *message) {
    GVariant *body = g_dbus_message_get_body(message);
    require(body && g_variant_n_children(body) >= 1, "missing monitor target");
    Variant target(g_variant_get_child_value(body, 0));
    require(g_variant_is_of_type(target.get(), G_VARIANT_TYPE_OBJECT_PATH),
            "invalid monitor target");
    return g_variant_get_string(target.get(), nullptr);
  }

  void account(GDBusMessage *message) {
    std::lock_guard<std::mutex> lock(mutex_);
    const GDBusMessageType type = g_dbus_message_get_message_type(message);
    const char *sender_value = g_dbus_message_get_sender(message);
    const char *destination_value = g_dbus_message_get_destination(message);
    const char *member_value = g_dbus_message_get_member(message);
    const std::string sender = sender_value ? sender_value : "";
    const std::string destination = destination_value ? destination_value : "";
    const std::string member = member_value ? member_value : "";
    if (type == G_DBUS_MESSAGE_TYPE_METHOD_CALL) {
      require(calls_.size() < 4096, "private D-Bus trace bound exceeded");
      const char *path = g_dbus_message_get_path(message);
      const char *interface = g_dbus_message_get_interface(message);
      calls_.emplace_back(sender, path ? path : "", interface ? interface : "", member);
      if (!senders_.count(sender) ||
          (member != "RegisterAgent" && member != "UnregisterAgent" && member != "StartNotify" &&
           member != "StopNotify"))
        return;
      require(pending_.size() < 256, "private D-Bus accounting bound exceeded");
      require(destination == bluez_owner_, "owned call destination changed");
      const std::string target = (member == "RegisterAgent" || member == "UnregisterAgent")
          ? first_object_path(message)
          : std::string(path ? path : "");
      pending_[{sender, g_dbus_message_get_serial(message)}] = {member, target};
      return;
    }
    if (type == G_DBUS_MESSAGE_TYPE_METHOD_RETURN || type == G_DBUS_MESSAGE_TYPE_ERROR) {
      auto found = pending_.find({destination, g_dbus_message_get_reply_serial(message)});
      if (found == pending_.end()) return;
      Pending operation = found->second;
      pending_.erase(found);
      if (type == G_DBUS_MESSAGE_TYPE_ERROR) return;
      require(sender == bluez_owner_, "owned acknowledgement sender changed");
      GVariant *body = g_dbus_message_get_body(message);
      require(!body || g_variant_n_children(body) == 0, "owned acknowledgement has payload");
      require(acknowledgements_.size() < 4096, "acknowledgement trace bound exceeded");
      acknowledgements_.emplace_back(destination, operation.member, operation.target);
      if (operation.member == "RegisterAgent") {
        require(!agents_.count(destination), "duplicate agent registration");
        agents_[destination] = operation.target;
      } else if (operation.member == "UnregisterAgent") {
        auto agent = agents_.find(destination);
        require(agent != agents_.end() && agent->second == operation.target,
                "unknown agent unregistration");
        agents_.erase(agent);
      } else if (operation.member == "StartNotify") {
        require(!notifications_.count({destination, operation.target}),
                "duplicate notification registration");
        notifications_.insert({destination, operation.target});
      } else if (operation.member == "StopNotify") {
        notifications_.erase({destination, operation.target});
      }
      return;
    }
    if (type != G_DBUS_MESSAGE_TYPE_SIGNAL || sender != kBus || member != "NameOwnerChanged")
      return;
    GVariant *body = g_dbus_message_get_body(message);
    if (!body || !g_variant_is_of_type(body, G_VARIANT_TYPE("(sss)"))) return;
    const char *name = nullptr, *previous = nullptr, *current = nullptr;
    g_variant_get(body, "(&s&s&s)", &name, &previous, &current);
    if (!*previous || *current) return;
    agents_.erase(name);
    for (auto iterator = notifications_.begin(); iterator != notifications_.end();) {
      if (iterator->first == name) iterator = notifications_.erase(iterator);
      else ++iterator;
    }
    for (auto iterator = pending_.begin(); iterator != pending_.end();) {
      if (iterator->first.first == name) iterator = pending_.erase(iterator);
      else ++iterator;
    }
  }

  Object<GDBusConnection> connection_;
  guint filter_ = 0;
  std::string bluez_owner_;
  mutable std::mutex mutex_;
  std::set<std::string> senders_;
  std::map<PendingKey, Pending> pending_;
  std::map<std::string, std::string> agents_;
  std::set<std::pair<std::string, std::string>> notifications_;
  std::deque<std::tuple<std::string, std::string, std::string, std::string>> calls_;
  std::deque<std::tuple<std::string, std::string, std::string>> acknowledgements_;
  std::string failure_;
};

const char *kIntrospection = R"XML(
<node>
  <interface name='org.freedesktop.DBus.ObjectManager'>
    <method name='GetManagedObjects'><arg type='a{oa{sa{sv}}}' direction='out'/></method>
  </interface>
  <interface name='org.bluez.Agent1'>
    <method name='Release'/><method name='Cancel'/>
    <method name='RequestConfirmation'><arg type='o' direction='in'/><arg type='u' direction='in'/></method>
    <method name='RequestAuthorization'><arg type='o' direction='in'/></method>
    <method name='AuthorizeService'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>
  </interface>
  <interface name='org.bluez.LEAdvertisement1'>
    <method name='Release'/>
    <property name='Type' type='s' access='read'/><property name='Discoverable' type='b' access='read'/>
    <property name='ServiceUUIDs' type='as' access='read'/><property name='LocalName' type='s' access='read'/>
  </interface>
  <interface name='org.bluez.GattService1'>
    <property name='UUID' type='s' access='read'/><property name='Primary' type='b' access='read'/>
  </interface>
  <interface name='org.bluez.GattCharacteristic1'>
    <method name='ReadValue'><arg type='a{sv}' direction='in'/><arg type='ay' direction='out'/></method>
    <method name='WriteValue'><arg type='ay' direction='in'/><arg type='a{sv}' direction='in'/></method>
    <method name='StartNotify'/><method name='StopNotify'/><method name='Confirm'/>
    <property name='Service' type='o' access='read'/><property name='UUID' type='s' access='read'/>
    <property name='Flags' type='as' access='read'/><property name='Value' type='ay' access='read'/>
    <property name='Notifying' type='b' access='read'/>
  </interface>
</node>
)XML";

class Fixture {
 public:
  explicit Fixture(std::string address)
      : address_(std::move(address)), connection_(connect_bus(address_)), monitor_(address_) {
    GError *raw_error = nullptr;
    introspection_ = g_dbus_node_info_new_for_xml(kIntrospection, &raw_error);
    Error error(raw_error);
    if (error) fail(std::string("invalid fixture introspection: ") + error->message);
    require(introspection_ != nullptr, "missing fixture introspection");
    initialize_values();
    register_objects();
    request_name();
    subscribe_names();
    baseline_ = list_names(connection_.get());
  }

  ~Fixture() {
    for (guint id : registrations_) g_dbus_connection_unregister_object(connection_.get(), id);
    if (name_subscription_)
      g_dbus_connection_signal_unsubscribe(connection_.get(), name_subscription_);
    if (introspection_) g_dbus_node_info_unref(introspection_);
    if (connection_) g_dbus_connection_close_sync(connection_.get(), nullptr, nullptr);
  }

  Json start() {
    call(connection_.get(), kBluez, "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent",
         g_variant_new("(os)", "/fixture/agent", "DisplayYesNo"), G_VARIANT_TYPE("()"));
    call(connection_.get(), kBluez, "/org/bluez", "org.bluez.AgentManager1", "RequestDefaultAgent",
         g_variant_new("(o)", "/fixture/agent"), G_VARIANT_TYPE("()"));
    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
    call(connection_.get(), kBluez, "/org/bluez/hci1", "org.bluez.GattManager1",
         "RegisterApplication", g_variant_new("(o@a{sv})", kRoot, g_variant_builder_end(&options)),
         G_VARIANT_TYPE("()"));
    return reset();
  }

  Json operation(const Json &request) {
    require(request.is_object() && request.size() == 2 && request.contains("operation") &&
                request.contains("parameters") && request["operation"].is_string(),
            "invalid_request");
    const std::string operation = request["operation"];
    const Json &parameters = request["parameters"];
    if (operation == "reset" && parameters == Json::object()) return reset();
    if (operation == "stats" && parameters == Json::object()) return snapshot();
    if (operation == "value") {
      exact_keys(parameters, {"label", "hex", "emit"}, "invalid_value");
      require(parameters["label"].is_string() && parameters["hex"].is_string() &&
                  parameters["emit"].is_boolean(),
              "invalid_value");
      const std::string label = parameters["label"];
      require(kUuids.count(label), "invalid_value");
      std::vector<std::uint8_t> value = decode_hex(parameters["hex"]);
      if (parameters["emit"].get<bool>()) changed(label, value);
      else values_[label] = std::move(value);
      return Json::object();
    }
    if (operation == "deny") {
      exact_keys(parameters, {"label", "denied"}, "invalid_denial");
      require(parameters["label"].is_string() && parameters["denied"].is_boolean(),
              "invalid_denial");
      const std::string label = parameters["label"];
      require(kUuids.count(label), "invalid_denial");
      if (parameters["denied"].get<bool>()) denied_.insert(label);
      else denied_.erase(label);
      return Json::object();
    }
    if (operation == "delay") {
      exact_keys(parameters, {"label", "milliseconds"}, "invalid_delay");
      require(parameters["label"].is_string() && parameters["milliseconds"].is_number_integer(),
              "invalid_delay");
      const std::string label = parameters["label"];
      const std::int64_t milliseconds = parameters["milliseconds"];
      require(kUuids.count(label) && milliseconds >= 0 && milliseconds <= 5000, "invalid_delay");
      delays_[label] = static_cast<unsigned>(milliseconds);
      return Json::object();
    }
    if (operation == "disconnect" && parameters == Json::object()) {
      require(!device_.empty(), "device unavailable");
      call(connection_.get(), kBluez, device_.c_str(), kDevice, "Disconnect", nullptr,
           G_VARIANT_TYPE("()"));
      return Json::object();
    }
    fail("unsupported_operation");
  }

  void shutdown() {
    Json statistics = snapshot();
    const bool clean = statistics["native_senders"].empty() && statistics["agents"] == 0 &&
        statistics["notification_sessions"] == 0 && notifying_.empty() && failure_.empty();
    try {
      if (advertising_)
        call(connection_.get(), kBluez, "/org/bluez/hci1", "org.bluez.LEAdvertisingManager1",
             "UnregisterAdvertisement", g_variant_new("(o)", "/fixture/advertisement"),
             G_VARIANT_TYPE("()"));
      call(connection_.get(), kBluez, "/org/bluez/hci1", "org.bluez.GattManager1",
           "UnregisterApplication", g_variant_new("(o)", kRoot), G_VARIANT_TYPE("()"));
      call(connection_.get(), kBluez, "/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent",
           g_variant_new("(o)", "/fixture/agent"), G_VARIANT_TYPE("()"));
    } catch (...) {
      write_result(false, statistics);
      throw;
    }
    write_result(clean, statistics);
    require(clean, "fixture resources not released");
  }

  void record_failure(const std::string &failure) { failure_ = failure; }

 private:
  struct DeferredReply {
    GDBusMethodInvocation *invocation;
    std::vector<std::uint8_t> value;
  };

  static void exact_keys(const Json &value, std::initializer_list<const char *> keys,
                         const char *error) {
    require(value.is_object() && value.size() == keys.size(), error);
    for (const char *key : keys) require(value.contains(key), error);
  }

  void initialize_values() {
    for (const auto &label : kLabels)
      values_[label] = label == "value" ? std::vector<std::uint8_t>{0x34, 0x12}
                                        : std::vector<std::uint8_t>{0x00};
    values_["duplicate_a"] = {0xA1};
    values_["duplicate_b"] = {0xB2};
  }

  void request_name() {
    Variant reply = call(connection_.get(), kBus, kBusPath, kBus, "RequestName",
                         g_variant_new("(su)", "io.wotex.BLESoftwarePeer", 0U),
                         G_VARIANT_TYPE("(u)"));
    guint32 result = 0;
    g_variant_get(reply.get(), "(u)", &result);
    require(result == 1U, "fixture service name unavailable");
  }

  static void name_changed(GDBusConnection *, const char *, const char *, const char *,
                           const char *, GVariant *parameters, gpointer data) {
    auto *fixture = static_cast<Fixture *>(data);
    const char *name = nullptr, *previous = nullptr, *current = nullptr;
    g_variant_get(parameters, "(&s&s&s)", &name, &previous, &current);
    if (!*previous && std::string(current) == name && name[0] == ':' &&
        !fixture->baseline_.count(name)) {
      try {
        fixture->monitor_.watch(name);
      } catch (const std::exception &error) {
        fixture->failure_ = error.what();
      }
    }
  }

  void subscribe_names() {
    name_subscription_ = g_dbus_connection_signal_subscribe(
        connection_.get(), kBus, kBus, "NameOwnerChanged", kBusPath, nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE, name_changed, this, nullptr);
    require(name_subscription_ != 0, "name-owner subscription failed");
  }

  static void method_call(GDBusConnection *, const char *, const char *path, const char *interface,
                          const char *method, GVariant *parameters,
                          GDBusMethodInvocation *invocation, gpointer data) {
    auto *fixture = static_cast<Fixture *>(data);
    try {
      fixture->handle_method(path, interface, method, parameters, invocation);
    } catch (const std::exception &error) {
      fixture->failure_ = error.what();
      g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Failed",
                                                 "Fixture method failed");
    } catch (...) {
      fixture->failure_ = "fixture method failure";
      g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Failed",
                                                 "Fixture method failed");
    }
  }

  static GVariant *property_get(GDBusConnection *, const char *, const char *path,
                                const char *interface, const char *property, GError **,
                                gpointer data) {
    auto *fixture = static_cast<Fixture *>(data);
    try {
      return fixture->get_property(path, interface, property);
    } catch (const std::exception &error) {
      fixture->failure_ = error.what();
      return nullptr;
    } catch (...) {
      fixture->failure_ = "fixture property failure";
      return nullptr;
    }
  }

  static const GDBusInterfaceVTable kVtable;

  GDBusInterfaceInfo *interface(const char *name) {
    GDBusInterfaceInfo *info = g_dbus_node_info_lookup_interface(introspection_, name);
    require(info != nullptr, std::string("missing interface ") + name);
    return info;
  }

  void register_object(const char *path, const char *name) {
    GError *raw_error = nullptr;
    guint id = g_dbus_connection_register_object(connection_.get(), path, interface(name), &kVtable,
                                                 this, nullptr, &raw_error);
    Error error(raw_error);
    if (error) fail(std::string("fixture object registration failed: ") + error->message);
    require(id != 0, "fixture object registration missing");
    registrations_.push_back(id);
  }

  void register_objects() {
    register_object(kRoot, kObjectManager);
    register_object("/fixture/agent", kAgent);
    register_object("/fixture/advertisement", kAdvertisement);
    register_object(kServicePath, kService);
    for (const auto &label : kLabels) register_object(path(label).c_str(), kCharacteristic);
  }

  std::string path(const std::string &label) const {
    return std::string(kServicePath) + "/" + label;
  }

  std::optional<std::string> label_for(const std::string &candidate) const {
    for (const auto &label : kLabels)
      if (path(label) == candidate) return label;
    return std::nullopt;
  }

  void trace(const std::string &member, const std::string &path_value, const char *sender = "") {
    require(trace_.size() < 4096, "GATT fixture trace bound exceeded");
    trace_.push_back({{"member", member}, {"path", path_value}, {"sender", sender ? sender : ""}});
  }

  static gboolean deferred_reply(gpointer data) {
    std::unique_ptr<DeferredReply> reply(static_cast<DeferredReply *>(data));
    g_dbus_method_invocation_return_value(reply->invocation,
                                          g_variant_new("(@ay)", bytes(reply->value)));
    g_object_unref(reply->invocation);
    return G_SOURCE_REMOVE;
  }

  void handle_method(const std::string &path_value, const std::string &interface_value,
                     const std::string &member, GVariant *parameters,
                     GDBusMethodInvocation *invocation) {
    const char *sender = g_dbus_method_invocation_get_sender(invocation);
    trace(member, path_value, sender);
    if (interface_value == kObjectManager && member == "GetManagedObjects" && path_value == kRoot) {
      g_dbus_method_invocation_return_value(invocation,
                                            g_variant_new("(@a{oa{sa{sv}}})", objects()));
      return;
    }
    if (interface_value == kAgent && path_value == "/fixture/agent") {
      if (member == "Release" || member == "Cancel") {
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
      }
      require(g_variant_n_children(parameters) >= 1, "missing Agent device");
      Variant device(g_variant_get_child_value(parameters, 0));
      require(g_variant_is_of_type(device.get(), G_VARIANT_TYPE_OBJECT_PATH) &&
                  std::string(g_variant_get_string(device.get(), nullptr)) == kExpectedDevice,
              "unexpected Agent device");
      if (member == "RequestConfirmation" || member == "RequestAuthorization" ||
          member == "AuthorizeService") {
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
      }
      g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Rejected",
                                                 "Unsupported fixture challenge");
      return;
    }
    if (interface_value == kAdvertisement && member == "Release") {
      g_dbus_method_invocation_return_value(invocation, nullptr);
      return;
    }
    auto label = label_for(path_value);
    if (interface_value != kCharacteristic || !label) fail("unsupported fixture method");
    if (denied_.count(*label) && (member == "ReadValue" || member == "WriteValue")) {
      g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.NotPermitted",
                                                 "Fixture denial");
      return;
    }
    if (member == "ReadValue") {
      require(g_variant_is_of_type(parameters, G_VARIANT_TYPE("(a{sv})")),
              "invalid ReadValue signature");
      trace_.back()["value"] = hex(values_.at(*label));
      unsigned delay = delays_[*label];
      if (delay) {
        auto *reply = new DeferredReply{
            reinterpret_cast<GDBusMethodInvocation *>(g_object_ref(invocation)),
            values_.at(*label)};
        require(g_timeout_add(delay, deferred_reply, reply) != 0, "read delay unavailable");
      } else {
        g_dbus_method_invocation_return_value(invocation,
                                              g_variant_new("(@ay)", bytes(values_.at(*label))));
      }
      return;
    }
    if (member == "WriteValue") {
      require(g_variant_is_of_type(parameters, G_VARIANT_TYPE("(aya{sv})")),
              "invalid WriteValue signature");
      Variant value(g_variant_get_child_value(parameters, 0));
      values_[*label] = byte_vector(value.get());
      trace_.back()["value"] = hex(values_.at(*label));
      g_dbus_method_invocation_return_value(invocation, nullptr);
      return;
    }
    if (member == "StartNotify") {
      require(!notifying_.count(*label), "duplicate StartNotify");
      notifying_.insert(*label);
      g_dbus_method_invocation_return_value(invocation, nullptr);
      return;
    }
    if (member == "StopNotify") {
      notifying_.erase(*label);
      g_dbus_method_invocation_return_value(invocation, nullptr);
      return;
    }
    if (member == "Confirm") {
      confirms_++;
      g_dbus_method_invocation_return_value(invocation, nullptr);
      return;
    }
    fail("unsupported characteristic method");
  }

  GVariant *get_property(const std::string &path_value, const std::string &interface_value,
                         const std::string &property) {
    if (interface_value == kService && path_value == kServicePath) {
      if (property == "UUID") return g_variant_new_string(kServiceUuid);
      if (property == "Primary") return g_variant_new_boolean(TRUE);
    }
    if (interface_value == kAdvertisement && path_value == "/fixture/advertisement") {
      if (property == "Type") return g_variant_new_string("peripheral");
      if (property == "Discoverable") return g_variant_new_boolean(TRUE);
      if (property == "LocalName") return g_variant_new_string("WBL Software Fixture");
      if (property == "ServiceUUIDs") {
        const char *values[] = {kServiceUuid, nullptr};
        return g_variant_new_strv(values, 1);
      }
    }
    auto label = label_for(path_value);
    if (interface_value == kCharacteristic && label) {
      if (property == "Service") return g_variant_new_object_path(kServicePath);
      if (property == "UUID") return g_variant_new_string(kUuids.at(*label).c_str());
      if (property == "Value") return bytes(values_.at(*label));
      if (property == "Notifying") return g_variant_new_boolean(notifying_.count(*label));
      if (property == "Flags") {
        GVariantBuilder flags;
        g_variant_builder_init(&flags, G_VARIANT_TYPE("as"));
        for (const auto &flag : kFlags.at(*label)) g_variant_builder_add(&flags, "s", flag.c_str());
        return g_variant_builder_end(&flags);
      }
    }
    return nullptr;
  }

  GVariant *properties(const std::string &path_value, const std::string &interface_value) {
    GVariantBuilder properties;
    g_variant_builder_init(&properties, G_VARIANT_TYPE("a{sv}"));
    const std::vector<std::string> names = interface_value == kService
        ? std::vector<std::string>{"UUID", "Primary"}
        : std::vector<std::string>{"Service", "UUID", "Flags", "Value", "Notifying"};
    for (const auto &name : names)
      g_variant_builder_add(&properties, "{sv}", name.c_str(),
                            get_property(path_value, interface_value, name));
    return g_variant_builder_end(&properties);
  }

  void add_object(GVariantBuilder *objects_builder, const std::string &path_value,
                  const std::string &interface_value) {
    GVariantBuilder interfaces;
    g_variant_builder_init(&interfaces, G_VARIANT_TYPE("a{sa{sv}}"));
    g_variant_builder_add(&interfaces, "{s@a{sv}}", interface_value.c_str(),
                          properties(path_value, interface_value));
    g_variant_builder_add(objects_builder, "{o@a{sa{sv}}}", path_value.c_str(),
                          g_variant_builder_end(&interfaces));
  }

  GVariant *objects() {
    GVariantBuilder result;
    g_variant_builder_init(&result, G_VARIANT_TYPE("a{oa{sa{sv}}}"));
    add_object(&result, kServicePath, kService);
    for (const auto &label : kLabels) add_object(&result, path(label), kCharacteristic);
    return g_variant_builder_end(&result);
  }

  Variant managed_objects() {
    return call(connection_.get(), kBluez, "/", kObjectManager, "GetManagedObjects", nullptr,
                G_VARIANT_TYPE("(a{oa{sa{sv}}})"));
  }

  Json reset() {
    if (!baseline_.empty()) {
      Json statistics = snapshot();
      require(statistics["native_senders"].empty() && statistics["agents"] == 0 &&
                  statistics["notification_sessions"] == 0,
              "fixture reset retained client resources");
    }
    if (advertising_) {
      call(connection_.get(), kBluez, "/org/bluez/hci1", "org.bluez.LEAdvertisingManager1",
           "UnregisterAdvertisement", g_variant_new("(o)", "/fixture/advertisement"),
           G_VARIANT_TYPE("()"));
      advertising_ = false;
    }
    Variant before = managed_objects();
    std::vector<std::pair<std::string, std::string>> devices;
    for (auto &entry : object_entries(before.get())) {
      Variant properties = interface_properties(entry.interfaces.get(), kDevice);
      if (!properties) continue;
      auto adapter = property_string(properties.get(), "Adapter", G_VARIANT_TYPE_OBJECT_PATH);
      if (adapter && (*adapter == "/org/bluez/hci0" || *adapter == "/org/bluez/hci1"))
        devices.emplace_back(*adapter, entry.path);
    }
    for (const auto &[adapter, device] : devices)
      call(connection_.get(), kBluez, adapter.c_str(), kAdapter, "RemoveDevice",
           g_variant_new("(o)", device.c_str()), G_VARIANT_TYPE("()"));
    for (unsigned index = 0; index < 2; index++) {
      const std::string adapter = "/org/bluez/hci" + std::to_string(index);
      for (bool powered : {false, true})
        call(connection_.get(), kBluez, adapter.c_str(), kProperties, "Set",
             g_variant_new("(ssv)", kAdapter, "Powered", g_variant_new_boolean(powered)),
             G_VARIANT_TYPE("()"));
    }
    Variant powered = managed_objects();
    std::string remote_address;
    for (auto &entry : object_entries(powered.get())) {
      if (entry.path != "/org/bluez/hci1") continue;
      Variant properties = interface_properties(entry.interfaces.get(), kAdapter);
      auto address = properties
          ? property_string(properties.get(), "Address", G_VARIANT_TYPE_STRING)
          : std::nullopt;
      if (address) remote_address = *address;
    }
    require(!remote_address.empty(), "fixture adapter address unavailable");
    GVariantBuilder filter;
    g_variant_builder_init(&filter, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&filter, "{sv}", "Transport", g_variant_new_string("le"));
    call(connection_.get(), kBluez, "/org/bluez/hci0", kAdapter, "SetDiscoveryFilter",
         g_variant_new("(@a{sv})", g_variant_builder_end(&filter)), G_VARIANT_TYPE("()"));
    call(connection_.get(), kBluez, "/org/bluez/hci0", kAdapter, "StartDiscovery", nullptr,
         G_VARIANT_TYPE("()"));
    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
    call(connection_.get(), kBluez, "/org/bluez/hci1", "org.bluez.LEAdvertisingManager1",
         "RegisterAdvertisement",
         g_variant_new("(o@a{sv})", "/fixture/advertisement", g_variant_builder_end(&options)),
         G_VARIANT_TYPE("()"));
    advertising_ = true;
    std::string address_type;
    wait_until("public fixture advertisement", [&] {
      Variant current = managed_objects();
      for (auto &entry : object_entries(current.get())) {
        Variant properties = interface_properties(entry.interfaces.get(), kDevice);
        if (!properties) continue;
        auto address = property_string(properties.get(), "Address", G_VARIANT_TYPE_STRING);
        auto adapter = property_string(properties.get(), "Adapter", G_VARIANT_TYPE_OBJECT_PATH);
        if (address && adapter && *address == remote_address && *adapter == "/org/bluez/hci0") {
          device_ = entry.path;
          address_type =
              property_string(properties.get(), "AddressType", G_VARIANT_TYPE_STRING).value_or("");
          return true;
        }
      }
      return false;
    });
    call(connection_.get(), kBluez, "/org/bluez/hci0", kAdapter, "StopDiscovery", nullptr,
         G_VARIANT_TYPE("()"));
    call(connection_.get(), kBluez, device_.c_str(), kDevice, "Connect", nullptr,
         G_VARIANT_TYPE("()"));
    wait_until("public fixture service resolution", [&] {
      Variant reply = call(connection_.get(), kBluez, device_.c_str(), kProperties, "GetAll",
                           g_variant_new("(s)", kDevice), G_VARIANT_TYPE("(a{sv})"));
      Variant properties(g_variant_get_child_value(reply.get(), 0));
      return property_boolean(properties.get(), "Connected").value_or(false) &&
          property_boolean(properties.get(), "ServicesResolved").value_or(false);
    });
    initialize_values();
    denied_.clear();
    delays_.clear();
    require(notifying_.empty(), "fixture notification retained across reset");
    trace_.clear();
    confirms_ = 0;
    monitor_.assert_released();
    monitor_.reset_traces();
    generation_++;
    return {{"peer",
             {{"adapter", "/org/bluez/hci0"},
              {"address", remote_address},
              {"address_type", address_type}}},
            {"bus_address", address_}};
  }

  template <typename Function> void wait_until(const char *label, Function function) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(15);
    while (std::chrono::steady_clock::now() < deadline) {
      if (function()) return;
      while (g_main_context_iteration(nullptr, FALSE)) {}
      g_usleep(20000);
    }
    fail(std::string("timed out: ") + label);
  }

  void changed(const std::string &label, const std::vector<std::uint8_t> &value) {
    values_[label] = value;
    trace_.push_back({{"member", "stimulus"}, {"label", label}, {"value", hex(value)}});
    GVariantBuilder changed_values, invalidated;
    g_variant_builder_init(&changed_values, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&changed_values, "{sv}", "Value", bytes(value));
    g_variant_builder_init(&invalidated, G_VARIANT_TYPE("as"));
    GError *raw_error = nullptr;
    gboolean sent = g_dbus_connection_emit_signal(
        connection_.get(), nullptr, path(label).c_str(), kProperties, "PropertiesChanged",
        g_variant_new("(s@a{sv}@as)", kCharacteristic, g_variant_builder_end(&changed_values),
                      g_variant_builder_end(&invalidated)),
        &raw_error);
    Error error(raw_error);
    if (error) fail(std::string("fixture signal failed: ") + error->message);
    require(sent, "fixture signal not sent");
  }

  Json snapshot() {
    Json monitor = monitor_.snapshot_counts();
    std::set<std::string> current = list_names(connection_.get());
    Json native = Json::array();
    for (const auto &name : current)
      if (!baseline_.count(name) && !name.empty() && name[0] == ':') native.push_back(name);
    Json peer_calls = Json::object();
    for (const Json &entry : trace_) {
      const std::string member = entry.at("member");
      peer_calls[member] = peer_calls.value(member, 0U) + 1U;
    }
    bool connected = false;
    Variant managed = managed_objects();
    for (auto &entry : object_entries(managed.get())) {
      if (entry.path != device_) continue;
      Variant properties = interface_properties(entry.interfaces.get(), kDevice);
      if (properties) connected = property_boolean(properties.get(), "Connected").value_or(false);
    }
    Json values = Json::object();
    for (const auto &[label, value] : values_) values[label] = hex(value);
    Json notifying = Json::array();
    for (const auto &label : notifying_) notifying.push_back(label);
    return {{"peer_connected", connected},
            {"native_senders", native},
            {"agents", monitor["agents"]},
            {"notification_sessions", monitor["notification_sessions"]},
            {"pending_controls", monitor["pending_controls"]},
            {"calls", monitor["calls"]},
            {"peer_calls", peer_calls},
            {"notifying", notifying},
            {"confirms", confirms_},
            {"values", values},
            {"generation", generation_}};
  }

  static void write_result(bool clean, const Json &statistics) {
    std::ofstream output("/results/public-peer-result.json", std::ios::binary | std::ios::trunc);
    require(output.good(), "cannot write peer result");
    output << Json{{"clean", clean}, {"statistics", statistics}}.dump(2) << '\n';
    require(output.good(), "cannot finish peer result");
  }

  std::string address_;
  Object<GDBusConnection> connection_;
  OwnershipMonitor monitor_;
  GDBusNodeInfo *introspection_ = nullptr;
  std::vector<guint> registrations_;
  guint name_subscription_ = 0;
  std::set<std::string> baseline_;
  std::map<std::string, std::vector<std::uint8_t>> values_;
  std::set<std::string> notifying_;
  std::set<std::string> denied_;
  std::map<std::string, unsigned> delays_;
  Json trace_ = Json::array();
  unsigned confirms_ = 0;
  bool advertising_ = false;
  std::string device_;
  std::uint64_t generation_ = 0;
  std::string failure_;
};

const GDBusInterfaceVTable Fixture::kVtable = {
    Fixture::method_call, Fixture::property_get, nullptr, {nullptr}};

struct ControlServer {
  Fixture *fixture;
  Object<GSocketService> service;
  std::string path;
};

gboolean incoming(GSocketService *, GSocketConnection *connection, GObject *, gpointer data) {
  auto *server = static_cast<ControlServer *>(data);
  try {
    GSocket *socket = g_socket_connection_get_socket(connection);
    g_socket_set_timeout(socket, 5);
    auto *stream = reinterpret_cast<GIOStream *>(connection);
    Object<GDataInputStream> input(g_data_input_stream_new(g_io_stream_get_input_stream(stream)));
    gsize length = 0;
    GError *raw_error = nullptr;
    char *raw = g_data_input_stream_read_line(input.get(), &length, nullptr, &raw_error);
    Error error(raw_error);
    if (error) fail(std::string("control read failed: ") + error->message);
    std::unique_ptr<char, decltype(&g_free)> line(raw, g_free);
    require(line && length <= 4096, "invalid_frame");
    Json response;
    try {
      Json request = Json::parse(line.get(), line.get() + length);
      response = {{"ok", server->fixture->operation(request)}};
    } catch (const std::exception &operation_error) {
      server->fixture->record_failure(operation_error.what());
      response = {{"error", operation_error.what()}};
    }
    const std::string encoded = response.dump() + "\n";
    require(encoded.size() <= 16384, "control response too large");
    gsize written = 0;
    raw_error = nullptr;
    gboolean ok = g_output_stream_write_all(g_io_stream_get_output_stream(stream), encoded.data(),
                                            encoded.size(), &written, nullptr, &raw_error);
    Error write_error(raw_error);
    if (write_error) fail(std::string("control write failed: ") + write_error->message);
    require(ok && written == encoded.size(), "short control write");
    g_io_stream_close(stream, nullptr, nullptr);
  } catch (const std::exception &error) {
    server->fixture->record_failure(error.what());
  } catch (...) {
    server->fixture->record_failure("control failure");
  }
  return TRUE;
}

gboolean stop_loop(gpointer data) {
  g_main_loop_quit(static_cast<GMainLoop *>(data));
  return G_SOURCE_CONTINUE;
}

void start_control(ControlServer *server) {
  g_unlink(server->path.c_str());
  Object<GSocketAddress> address(g_unix_socket_address_new(server->path.c_str()));
  GError *raw_error = nullptr;
  gboolean listening = g_socket_listener_add_address(
      reinterpret_cast<GSocketListener *>(server->service.get()), address.get(),
      G_SOCKET_TYPE_STREAM, G_SOCKET_PROTOCOL_DEFAULT, nullptr, nullptr, &raw_error);
  Error error(raw_error);
  if (error) fail(std::string("control listen failed: ") + error->message);
  require(listening, "control listener unavailable");
  g_signal_connect(server->service.get(), "incoming", G_CALLBACK(incoming), server);
  g_socket_service_start(server->service.get());
}

void write_config(const Json &config) {
  std::ofstream output("/run/wbl/software.json", std::ios::binary | std::ios::trunc);
  require(output.good(), "cannot write software configuration");
  output << config.dump() << '\n';
  require(output.good(), "cannot finish software configuration");
}

} // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::string(argv[1]) == "--version") {
    std::cout << "wotex-ble-public-peer 1\n";
    return 0;
  }
  if (argc != 1) return 2;
  try {
    const char *address = std::getenv("DBUS_SYSTEM_BUS_ADDRESS");
    require(address && *address, "DBUS_SYSTEM_BUS_ADDRESS is required");
    GMainLoop *loop = g_main_loop_new(nullptr, FALSE);
    require(loop != nullptr, "main loop allocation failed");
    Fixture fixture(address);
    Json config = fixture.start();
    ControlServer server{&fixture, Object<GSocketService>(g_socket_service_new()),
                         "/run/wbl/control.sock"};
    start_control(&server);
    config["control_socket"] = server.path;
    write_config(config);
    const guint term = g_unix_signal_add(SIGTERM, stop_loop, loop);
    const guint interrupt = g_unix_signal_add(SIGINT, stop_loop, loop);
    require(term && interrupt, "signal registration failed");
    g_main_loop_run(loop);
    g_source_remove(term);
    g_source_remove(interrupt);
    g_socket_service_stop(server.service.get());
    g_unlink(server.path.c_str());
    fixture.shutdown();
    g_main_loop_unref(loop);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "public peer failed: " << error.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "public peer failed\n";
    return 1;
  }
}
