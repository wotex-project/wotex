// SPDX-License-Identifier: Apache-2.0
// Compile this Apple SDK boundary as Objective-C++17 with ARC.
#include "sdk_environment.hpp"
#include <cctype>

using namespace wotex::ble::corebluetooth;
@interface WotexCBDelegate : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property(nonatomic, assign) SDKState *owner;
@end

namespace wotex::ble::corebluetooth {
static bool peripheral_uuid(const std::string &value) {
  if (value.size() != 36) return false;
  for (std::size_t i = 0; i < value.size(); ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (value[i] != '-') return false;
    } else if (!((value[i] >= '0' && value[i] <= '9') || (value[i] >= 'a' && value[i] <= 'f')))
      return false;
  }
  return true;
}
static std::string bluetooth_uuid(CBUUID *uuid) {
  NSString *text = uuid.UUIDString.lowercaseString;
  if (!text || text.length > 36) return {};
  const char *utf8 = text.UTF8String;
  if (!utf8) return {};
  std::string value(utf8);
  if (value.size() == 4) value = "0000" + value;
  if (value.size() == 8) value += "-0000-1000-8000-00805f9b34fb";
  return peripheral_uuid(value) ? value : std::string{};
}
struct SDKState final : Port, Sink {
  enum class Phase { fresh, opening, connecting, services, characteristics, open, closed };
  SDKClock &clock;
  SDKSink &sink;
  SDKEnvironment environment;
  dispatch_queue_t queue;
  CBCentralManager *central = nil;
  CBPeripheral *peripheral = nil;
  WotexCBDelegate *delegate = nil;
  NSUUID *identifier = nil;
  NSArray<CBService *> *services = nil;
  NSMutableArray<CBCharacteristic *> *characteristics = nil;
  NSMutableArray<CBService *> *route_services = nil;
  CBCharacteristic *selected = nil;
  Phase phase = Phase::fresh;
  SDKConfig config;
  std::vector<Characteristic> routes;
  std::size_t service_index = 0;
  std::uint64_t last_request = 0;
  std::int64_t last_time = 0, opening_deadline = 0;
  std::unique_ptr<Operation> operation;
  Ticket ticket{};
  Mode mode = Mode::read;
  Retirement retired = Retirement::pending;
  bool opened = false, loss_sent = false;

  SDKState(SDKClock &time, SDKSink &output, const SDKEnvironment &env)
      : clock(time), sink(output), environment(env),
        queue(dispatch_queue_create("wotex.ble.corebluetooth", DISPATCH_QUEUE_SERIAL)) {
    if (!queue) throw std::bad_alloc();
    dispatch_queue_set_specific(queue, this, this, nullptr);
  }
  void assert_external() const {
    if (dispatch_get_specific(this)) std::terminate();
  }
  void loss(Code code) noexcept {
    if (opened && !loss_sent) {
      loss_sent = true;
      sink.lost(code);
    }
  }
  void retire_native() noexcept {
    if (phase == Phase::closed) return;
    phase = Phase::closed;
    retired = Retirement::confirmed;
    delegate.owner = nullptr;
    @try {
      peripheral.delegate = nil;
    } @catch (NSException *) {
      retired = Retirement::unconfirmed;
    } @
    try {
      central.delegate = nil;
    } @catch (NSException *) {
      retired = Retirement::unconfirmed;
    } @
    try {
      if (central && peripheral) [central cancelPeripheralConnection:peripheral];
    } @catch (NSException *) {
      retired = Retirement::unconfirmed;
    }
    selected = nil;
    characteristics = nil;
    route_services = nil;
    services = nil;
    peripheral = nil;
    central = nil;
    delegate = nil;
    identifier = nil;
    routes.clear();
    config.identifier.clear();
  }
  void fail(Code code, std::int64_t now) noexcept {
    if (phase == Phase::fresh || phase == Phase::closed) return;
    const bool was_open = opened;
    if (operation && operation->active()) operation->cancel(std::max(now, last_time), code);
    else {
      retire_native();
      loss(retired == Retirement::confirmed ? code : Code::cleanup_timeout);
    }
    if (!was_open)
      sink.opened(retired == Retirement::confirmed ? code : Code::cleanup_timeout,
                  config.generation, {});
  }
  template <typename F> void guard(F action) noexcept {
    @autoreleasepool {
      @try {
        try {
          action();
        } catch (...) {
          fail(Code::resource_limit, last_time);
        }
      } @catch (NSException *) {
        fail(Code::transport_error, last_time);
      }
    }
  }
  bool tick(std::int64_t now) {
    if (phase == Phase::fresh || phase == Phase::closed) return false;
    if (now < 0 || now < last_time) {
      fail(Code::clock_regressed, last_time);
      return false;
    }
    last_time = now;
    if (!opened && now >= opening_deadline) {
      fail(Code::timeout, now);
      return false;
    }
    const auto auth = environment.authorization();
    const bool asking = phase == Phase::opening && config.permission == Permission::request &&
        auth == CBManagerAuthorizationNotDetermined;
    if (auth != CBManagerAuthorizationAllowedAlways && !asking) {
      fail(Code::not_authorized, now);
      return false;
    }
    if (phase != Phase::opening && central.state != CBManagerStatePoweredOn) {
      fail(Code::disconnected, now);
      return false;
    }
    if (operation && operation->active()) operation->poll(now);
    return phase != Phase::closed;
  }
  Code open(const SDKConfig &input, std::int64_t now, std::int64_t deadline) {
    if (phase != Phase::fresh || !input.generation || !peripheral_uuid(input.identifier) ||
        input.pairing != Pairing::system ||
        (input.permission != Permission::require_authorized &&
         input.permission != Permission::request) ||
        now < 0 || deadline <= now || deadline - now > 60000)
      return Code::invalid_options;
    config = input;
    last_time = now;
    opening_deadline = deadline;
    phase = Phase::opening;
    guard([&] {
      const auto auth = environment.authorization();
      if (auth != CBManagerAuthorizationAllowedAlways &&
          !(auth == CBManagerAuthorizationNotDetermined &&
            input.permission == Permission::request)) {
        fail(Code::not_authorized, now);
        return;
      }
      NSString *text = [NSString stringWithUTF8String:input.identifier.c_str()];
      if (!text) {
        fail(Code::resource_limit, now);
        return;
      }
      identifier = [[NSUUID alloc] initWithUUIDString:text];
      delegate = [WotexCBDelegate new];
      if (!identifier || !delegate) {
        fail(Code::resource_limit, now);
        return;
      }
      delegate.owner = this;
      central = environment.central(delegate, queue);
      if (!identifier || !delegate || !central) fail(Code::resource_limit, now);
    });
    return Code::ok;
  }
  void manager_state(CBCentralManager *sender) noexcept {
    if (sender != central) return;
    guard([&] {
      if (!tick(clock.sample())) return;
      if (central.state == CBManagerStateUnsupported) {
        fail(Code::not_supported, last_time);
        return;
      }
      if (central.state == CBManagerStateUnauthorized) {
        fail(Code::not_authorized, last_time);
        return;
      }
      if (central.state == CBManagerStateUnknown && phase == Phase::opening) return;
      if (central.state != CBManagerStatePoweredOn) {
        fail(Code::disconnected, last_time);
        return;
      }
      if (phase != Phase::opening || !authorized()) return;
      NSArray<CBPeripheral *> *found = [central retrievePeripheralsWithIdentifiers:@[ identifier ]];
      if (found.count == 0) {
        fail(Code::peer_not_found, last_time);
        return;
      }
      if (found.count != 1 || ![found[0].identifier isEqual:identifier]) {
        fail(Code::invalid_response, last_time);
        return;
      }
      peripheral = found[0];
      peripheral.delegate = delegate;
      phase = Phase::connecting;
      [central connectPeripheral:peripheral options:nil];
    });
  }
  void connected(CBCentralManager *sender, CBPeripheral *peer, bool success) noexcept {
    if (sender != central || peer != peripheral || phase != Phase::connecting) return;
    guard([&] {
      if (!tick(clock.sample())) return;
      if (!success || peer.state != CBPeripheralStateConnected) {
        fail(Code::disconnected, last_time);
        return;
      }
      phase = Phase::services;
      [peripheral discoverServices:nil];
    });
  }
  void disconnected(CBCentralManager *sender, CBPeripheral *peer) noexcept {
    if (sender == central && peer == peripheral) fail(Code::disconnected, clock.sample());
  }
  void next_service() {
    if (service_index < services.count) {
      phase = Phase::characteristics;
      [peripheral discoverCharacteristics:nil forService:services[service_index]];
    } else {
      auto published = routes;
      phase = Phase::open;
      opened = true;
      if (!sink.opened(Code::ok, config.generation, std::move(published)))
        fail(Code::resource_limit, last_time);
    }
  }
  void discovered_services(CBPeripheral *peer, NSError *error) noexcept {
    if (peer != peripheral || phase != Phase::services) return;
    guard([&] {
      if (!tick(clock.sample())) return;
      if (error) {
        fail(Code::transport_error, last_time);
        return;
      }
      if (!peer.services || peer.services.count > 64) {
        fail(Code::resource_limit, last_time);
        return;
      }
      services = [peer.services copy];
      characteristics = [NSMutableArray new];
      route_services = [NSMutableArray new];
      for (std::size_t i = 0; i < services.count; ++i) {
        if (services[i].peripheral != peripheral || bluetooth_uuid(services[i].UUID).empty()) {
          fail(Code::invalid_response, last_time);
          return;
        }
        for (std::size_t j = 0; j < i; ++j)
          if (services[i] == services[j]) {
            fail(Code::invalid_response, last_time);
            return;
          }
      }
      next_service();
    });
  }
  void discovered_characteristics(CBPeripheral *peer, CBService *service, NSError *error) noexcept {
    if (peer != peripheral || phase != Phase::characteristics || service != services[service_index])
      return;
    guard([&] {
      if (!tick(clock.sample())) return;
      if (error) {
        fail(Code::transport_error, last_time);
        return;
      }
      if (!service.characteristics || service.characteristics.count > 256 - routes.size()) {
        fail(Code::resource_limit, last_time);
        return;
      }
      for (CBCharacteristic *characteristic in service.characteristics) {
        const auto uuid = bluetooth_uuid(characteristic.UUID);
        if (characteristic.service != service || uuid.empty()) {
          fail(Code::invalid_response, last_time);
          return;
        }
        for (CBCharacteristic *prior in characteristics)
          if (prior == characteristic) {
            fail(Code::invalid_response, last_time);
            return;
          }
        const auto flags = characteristic.properties;
        routes.push_back(
            {{config.generation, routes.size() + 1, (flags & CBCharacteristicPropertyRead) != 0,
              (flags & CBCharacteristicPropertyWrite) != 0,
              (flags & CBCharacteristicPropertyWriteWithoutResponse) != 0},
             bluetooth_uuid(service.UUID),
             uuid,
             (flags & CBCharacteristicPropertyNotify) != 0,
             (flags & CBCharacteristicPropertyIndicate) != 0});
        [characteristics addObject:characteristic];
        [route_services addObject:service];
      }
      ++service_index;
      next_service();
    });
  }
  Code request(std::uint64_t number, std::uint64_t token, Mode kind,
               const std::vector<std::uint8_t> &bytes, std::int64_t now, std::int64_t deadline) {
    if (phase != Phase::open) return Code::disconnected;
    if (operation && operation->active()) return Code::resource_limit;
    if (!number || number <= last_request || !token || token > routes.size() ||
        bytes.size() > 512 ||
        (kind != Mode::read && kind != Mode::write && kind != Mode::command) ||
        (kind == Mode::read && !bytes.empty()) || now < 0 || deadline <= now ||
        deadline - now > 60000)
      return Code::invalid_options;
    if (!tick(now)) return Code::disconnected;
    selected = characteristics[token - 1];
    mode = kind;
    if (kind == Mode::read && selected.isNotifying) return Code::not_supported;
    auto next = std::make_unique<Operation>(*this, *this);
    ticket = {config.generation, number, token};
    last_request = number;
    operation = std::move(next);
    if (!operation->start(ticket, routes[token - 1].route, kind, bytes, now, deadline))
      return Code::invalid_options;
    return Code::ok;
  }
  bool authorized() const noexcept override try {
    return environment.authorization() == CBManagerAuthorizationAllowedAlways;
  } catch (...) {
    return false;
  }
  bool connected() const noexcept override {
    return phase == Phase::open && peripheral.state == CBPeripheralStateConnected;
  }
  bool current(const Route &route) const noexcept override {
    if (phase != Phase::open || route.generation != config.generation ||
        route.token != ticket.route || !selected ||
        selected.service != route_services[route.token - 1] ||
        selected.service.peripheral != peripheral)
      return false;
    const auto flags = selected.properties;
    return route.readable == ((flags & CBCharacteristicPropertyRead) != 0) &&
        route.writable == ((flags & CBCharacteristicPropertyWrite) != 0) &&
        route.command == ((flags & CBCharacteristicPropertyWriteWithoutResponse) != 0);
  }
  std::size_t maximum(Mode kind) const noexcept override {
    return [peripheral maximumWriteValueLengthForType:kind == Mode::command
                           ? CBCharacteristicWriteWithoutResponse
                           : CBCharacteristicWriteWithResponse];
  }
  bool ready() const noexcept override { return peripheral.canSendWriteWithoutResponse; }
  SubmissionResult submit(Ticket, const Route &route, Mode kind,
                          const std::vector<std::uint8_t> &bytes, std::int64_t now,
                          std::int64_t deadline) noexcept override {
    @try {
      NSData *data = kind == Mode::read ? nil
                                        : [NSData dataWithBytes:bytes.data() length:bytes.size()];
      if (kind != Mode::read && !data)
        return {Submission::refused, Code::resource_limit, clock.sample()};
      auto at = clock.sample();
      if (at < now || at < last_time) return {Submission::refused, Code::clock_regressed, at};
      if (at >= deadline) return {Submission::refused, Code::timeout, at};
      if (!authorized()) return {Submission::refused, Code::not_authorized, at};
      if (!connected()) return {Submission::refused, Code::disconnected, at};
      if (!current(route)) return {Submission::refused, Code::stale_discovery, at};
      if (kind == Mode::read && selected.isNotifying)
        return {Submission::refused, Code::not_supported, at};
      if (kind != Mode::read) {
        const auto max = maximum(kind);
        if (!max) return {Submission::refused, Code::not_supported, at};
        if (bytes.size() > std::min<std::size_t>(512, max))
          return {Submission::refused, Code::invalid_value_length, at};
      }
      if (kind == Mode::command && !ready()) return {Submission::refused, Code::resource_limit, at};
      at = clock.sample();
      if (at < now || at < last_time) return {Submission::refused, Code::clock_regressed, at};
      if (at >= deadline) return {Submission::refused, Code::timeout, at};
      last_time = at;
      if (kind == Mode::read) [peripheral readValueForCharacteristic:selected];
      else {
        [peripheral writeValue:data
             forCharacteristic:selected
                          type:kind == Mode::command ? CBCharacteristicWriteWithoutResponse
                                                     : CBCharacteristicWriteWithResponse];
      }
      const auto observed = clock.sample();
      if (observed < last_time) return {Submission::uncertain, Code::clock_regressed, observed};
      last_time = observed;
      return {Submission::accepted, Code::ok, observed};
    } @catch (NSException *) {
      return {Submission::uncertain, Code::transport_error, clock.sample()};
    }
  }
  void retire(Ticket) noexcept override { retire_native(); }
  Retirement retirement(Ticket) const noexcept override { return retired; }
  bool submitted(Ticket id, Mode kind) noexcept override { return sink.submitted(id, kind); }
  void result(Result value) noexcept override {
    const auto code = value.code;
    sink.result(std::move(value));
    if (phase == Phase::closed) loss(code);
  }
  void value(CBPeripheral *peer, CBCharacteristic *characteristic, NSError *error) noexcept {
    if (peer != peripheral || characteristic != selected || mode != Mode::read || !operation ||
        !operation->active())
      return;
    guard([&] {
      if (!tick(clock.sample())) return;
      NSData *value = characteristic.value;
      if (characteristic.isNotifying || value.length > 512) {
        operation->cancel(last_time, Code::invalid_response);
        return;
      }
      if (error) {
        operation->cancel(last_time, Code::transport_error);
        return;
      }
      if (!value) {
        operation->cancel(last_time, Code::invalid_response);
        return;
      }
      std::vector<std::uint8_t> bytes(value.length);
      [value getBytes:bytes.data() length:bytes.size()];
      operation->complete(ticket, Mode::read, Code::ok, std::move(bytes), last_time);
    });
  }
  void wrote(CBPeripheral *peer, CBCharacteristic *characteristic, NSError *error) noexcept {
    if (peer != peripheral || characteristic != selected || mode != Mode::write || !operation ||
        !operation->active())
      return;
    guard([&] {
      if (!tick(clock.sample())) return;
      operation->complete(ticket, Mode::write, error ? Code::transport_error : Code::ok, {},
                          last_time);
    });
  }
  void writable(CBPeripheral *peer) noexcept {
    if (peer != peripheral || !operation || !operation->active()) return;
    guard([&] {
      if (tick(clock.sample())) operation->ready(ticket, last_time);
    });
  }
};

SDK::SDK(SDKClock &clock, SDKSink &sink)
    : SDK(clock, sink,
          SDKEnvironment{[] { return CBManager.authorization; },
                         [](id<CBCentralManagerDelegate> delegate, dispatch_queue_t queue) {
                           return [[CBCentralManager alloc]
                               initWithDelegate:delegate
                                          queue:queue
                                        options:@{
                                          CBCentralManagerOptionShowPowerAlertKey : @NO
                                        }];
                         }}) {}
SDK::SDK(SDKClock &clock, SDKSink &sink, const SDKEnvironment &environment)
    : impl_(std::make_unique<SDKState>(clock, sink, environment)) {}
SDK::~SDK() {
  auto *state = impl_.get();
  state->assert_external();
  __block bool safe = false;
  dispatch_sync(state->queue, ^{
    safe = (state->phase == SDKState::Phase::fresh || state->phase == SDKState::Phase::closed) &&
        (!state->operation || !state->operation->active());
  });
  if (!safe) std::terminate();
}
Code SDK::open(const SDKConfig &config, std::int64_t now, std::int64_t deadline) {
  auto *state = impl_.get();
  state->assert_external();
  const auto *input = &config;
  Code code = Code::resource_limit;
  auto *output = &code;
  dispatch_sync(state->queue,
                ^{ state->guard([&] { *output = state->open(*input, now, deadline); }); });
  return code;
}
Code SDK::request(std::uint64_t number, std::uint64_t token, Mode mode,
                  const std::vector<std::uint8_t> &bytes, std::int64_t now, std::int64_t deadline) {
  auto *state = impl_.get();
  state->assert_external();
  const auto *input = &bytes;
  Code code = Code::resource_limit;
  auto *output = &code;
  dispatch_sync(state->queue, ^{
    state->guard([&] { *output = state->request(number, token, mode, *input, now, deadline); });
  });
  return code;
}
void SDK::poll(std::int64_t now) {
  auto *state = impl_.get();
  state->assert_external();
  dispatch_sync(state->queue, ^{ state->guard([&] { state->tick(now); }); });
}
void SDK::close(std::int64_t now) {
  auto *state = impl_.get();
  state->assert_external();
  dispatch_sync(state->queue, ^{
    @autoreleasepool {
      state->fail(Code::disconnected, now);
    }
  });
}
bool SDK::closed() const {
  auto *state = impl_.get();
  state->assert_external();
  __block bool value = false;
  dispatch_sync(state->queue, ^{ value = state->phase == SDKState::Phase::closed; });
  return value;
}
} // namespace wotex::ble::corebluetooth

@implementation WotexCBDelegate
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  if (_owner) _owner->manager_state(central);
}
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
  if (_owner) _owner->connected(central, peripheral, true);
}
- (void)centralManager:(CBCentralManager *)central
    didFailToConnectPeripheral:(CBPeripheral *)peripheral
                         error:(NSError *)error {
  (void)error;
  if (_owner) _owner->connected(central, peripheral, false);
}
- (void)centralManager:(CBCentralManager *)central
    didDisconnectPeripheral:(CBPeripheral *)peripheral
                      error:(NSError *)error {
  (void)error;
  if (_owner) _owner->disconnected(central, peripheral);
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
  if (_owner) _owner->discovered_services(peripheral, error);
}
- (void)peripheral:(CBPeripheral *)peripheral
    didDiscoverCharacteristicsForService:(CBService *)service
                                   error:(NSError *)error {
  if (_owner) _owner->discovered_characteristics(peripheral, service, error);
}
- (void)peripheral:(CBPeripheral *)peripheral
    didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
                              error:(NSError *)error {
  if (_owner) _owner->value(peripheral, characteristic, error);
}
- (void)peripheral:(CBPeripheral *)peripheral
    didWriteValueForCharacteristic:(CBCharacteristic *)characteristic
                             error:(NSError *)error {
  if (_owner) _owner->wrote(peripheral, characteristic, error);
}
- (void)peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)peripheral {
  if (_owner) _owner->writable(peripheral);
}
- (void)peripheral:(CBPeripheral *)peripheral didModifyServices:(NSArray<CBService *> *)services {
  (void)services;
  if (_owner && peripheral == _owner->peripheral)
    _owner->fail(Code::stale_discovery, _owner->clock.sample());
}
@end
