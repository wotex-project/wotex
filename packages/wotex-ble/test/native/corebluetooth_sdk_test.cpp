// SPDX-License-Identifier: Apache-2.0
#include "../../priv/corebluetooth/native/sdk_environment.hpp"
#include "../../priv/corebluetooth/native/driver.hpp"
#include "../../priv/bluez/native/vendor/json.hpp"
#include <atomic>
#include <cstdlib>
#include <fstream>
#include <future>
#include <iostream>
#include <map>
#include <thread>
#include <sys/wait.h>
#include <unistd.h>

using namespace wotex::ble::corebluetooth;
using Json = nlohmann::json;
static void check(bool value, int line = __builtin_LINE()) {
  if (!value) {
    std::cerr << "failed check at line " << line << '\n';
    std::abort();
  }
}
static const std::string identifier = "01234567-89ab-cdef-0123-456789abcdef";
static const std::vector<std::uint8_t> payload{0, 1, 127, 128, 255};
@interface TestCharacteristic : NSObject
@property(nonatomic, weak) CBService *service;
@property(nonatomic, strong, getter=UUID) CBUUID *uuidValue;
@property(nonatomic) CBCharacteristicProperties properties;
@property(nonatomic) BOOL isNotifying;
@property(nonatomic, copy) NSData *value;
@end
@implementation TestCharacteristic
@end
@interface TestService : NSObject
@property(nonatomic, weak) CBPeripheral *peripheral;
@property(nonatomic, strong, getter=UUID) CBUUID *uuidValue;
@property(nonatomic, copy) NSArray<CBCharacteristic *> *characteristics;
@end
@implementation TestService
@end
@interface TestPeripheral : NSObject
@property(nonatomic, weak) id<CBPeripheralDelegate> delegate;
@property(nonatomic, copy) NSUUID *identifier;
@property(nonatomic) CBPeripheralState state;
@property(nonatomic, copy) NSArray<CBService *> *services;
@property(nonatomic) BOOL canSendWriteWithoutResponse;
@property(nonatomic) NSUInteger writeMaximum, commandMaximum, reads, writes, serviceCalls,
    characteristicCalls;
@property(nonatomic, copy) NSData *lastWrite;
@property(nonatomic, weak) CBCharacteristic *lastTarget;
@property(nonatomic) CBCharacteristicWriteType lastMode;
@property(nonatomic, assign) std::vector<std::string> *events;
@property(nonatomic) NSUInteger notifyCalls;
@property(nonatomic) BOOL notifyEnabled, failNotify;
@property(nonatomic, weak) CBCharacteristic *notifyTarget;
@property(nonatomic, assign) std::function<void()> *onNotify;
@end
@implementation TestPeripheral
- (NSUInteger)maximumWriteValueLengthForType:(CBCharacteristicWriteType)type {
  return type == CBCharacteristicWriteWithoutResponse ? _commandMaximum : _writeMaximum;
}
- (void)discoverServices:(NSArray<CBUUID *> *)services {
  check(!services);
  ++_serviceCalls;
}
- (void)discoverCharacteristics:(NSArray<CBUUID *> *)characteristics
                     forService:(CBService *)service {
  check(!characteristics && service);
  ++_characteristicCalls;
}
- (void)readValueForCharacteristic:(CBCharacteristic *)characteristic {
  ++_reads;
  _lastTarget = characteristic;
}
- (void)writeValue:(NSData *)data
    forCharacteristic:(CBCharacteristic *)characteristic
                 type:(CBCharacteristicWriteType)type {
  _events->emplace_back("sdk");
  ++_writes;
  _lastWrite = [data copy];
  _lastTarget = characteristic;
  _lastMode = type;
}
- (void)setNotifyValue:(BOOL)enabled forCharacteristic:(CBCharacteristic *)characteristic {
  ++_notifyCalls;
  _notifyEnabled = enabled;
  _notifyTarget = characteristic;
  if (_onNotify && *_onNotify) (*_onNotify)();
  if (_failNotify)
    @throw [NSException exceptionWithName:@"private-notify" reason:@"private" userInfo:nil];
}
@end
@interface TestCentral : NSObject
@property(nonatomic, weak) id<CBCentralManagerDelegate> delegate;
@property(nonatomic) CBManagerState state;
@property(nonatomic, copy) NSArray<CBPeripheral *> *found;
@property(nonatomic, copy) NSArray<NSUUID *> *requested;
@property(nonatomic) NSUInteger connects, cancels;
@property(nonatomic) BOOL failCleanup;
@end
@implementation TestCentral
- (NSArray<CBPeripheral *> *)retrievePeripheralsWithIdentifiers:(NSArray<NSUUID *> *)identifiers {
  _requested = [identifiers copy];
  return _found;
}
- (void)connectPeripheral:(CBPeripheral *)peripheral
                  options:(NSDictionary<NSString *, id> *)options {
  check(peripheral && !options);
  ++_connects;
}
- (void)cancelPeripheralConnection:(CBPeripheral *)peripheral {
  check(peripheral);
  ++_cancels;
  if (_failCleanup)
    @throw [NSException exceptionWithName:@"private" reason:@"private" userInfo:nil];
}
@end

struct Clock final : SDKClock {
  std::atomic<std::int64_t> now{100};
  std::int64_t sample() noexcept override { return now.load(); }
};
struct Output final : SDKSink {
  bool admit = true;
  std::function<void()> onMarker;
  std::vector<std::string> events;
  std::vector<Code> opens, losses;
  std::vector<Characteristic> routes;
  std::vector<Result> results;
  bool admitState = true, admitValue = true;
  std::function<void(const NotificationResult &)> onState;
  std::vector<NotificationResult> notifications;
  std::vector<NotificationValue> values;
  bool notification_state(NotificationResult value) noexcept override try {
    if (!admitState) return false;
    if (onState) onState(value);
    events.emplace_back("state");
    notifications.push_back(value);
    return true;
  } catch (...) {
    std::abort();
  }
  bool notification_value(NotificationValue &&value) noexcept override try {
    if (!admitValue) return false;
    events.emplace_back("value");
    values.push_back(std::move(value));
    return true;
  } catch (...) {
    std::abort();
  }
  bool opened(Code code, std::uint64_t generation,
              std::vector<Characteristic> values) noexcept override try {
    check(generation == 7);
    opens.push_back(code);
    routes = std::move(values);
    return true;
  } catch (...) {
    std::abort();
  }
  void lost(Code code) noexcept override try { losses.push_back(code); } catch (...) {
    std::abort();
  }
  bool submitted(Ticket ticket, Mode) noexcept override try {
    check(ticket.generation == 7);
    events.emplace_back("marker");
    if (onMarker) onMarker();
    return admit;
  } catch (...) {
    std::abort();
  }
  void result(Result value) noexcept override try {
    results.push_back(std::move(value));
  } catch (...) {
    std::abort();
  }
};
struct PowerFixture {
  std::function<void()> on_dispatch;
  int port_storage = 0;
  void *context = nullptr;
  IOServiceInterestCallback callback = nullptr;
  dispatch_queue_t queue = nil;
  unsigned starts = 0, stops = 0, destroys = 0, closes = 0;
  unsigned refusal = 0;
  bool fail_allow = false, fail_stop = false, fail_close = false, throw_destroy = false;
  std::vector<intptr_t> allowed;
  std::vector<std::string> events;
  IONotificationPortRef port() { return reinterpret_cast<IONotificationPortRef>(&port_storage); }
  PowerAPI api() {
    return {[this](void *owner, IONotificationPortRef *output, IOServiceInterestCallback function,
                   io_object_t *notifier) {
      ++starts;
      events.emplace_back("subscribe");
      context = owner;
      callback = function;
      *output = refusal == 1 || refusal == 3 ? nullptr : port();
      *notifier = refusal == 1 || refusal == 4 ? IO_OBJECT_NULL : 53;
      return refusal == 1 || refusal == 2 ? IO_OBJECT_NULL : 47;
    },
            [this](IONotificationPortRef value, dispatch_queue_t target) {
      check(value == port() && target);
      queue = target;
      events.emplace_back("dispatch");
      if (on_dispatch) on_dispatch();
    },
            [this](io_connect_t connection, intptr_t token) {
      check(connection == 47);
      allowed.push_back(token);
      events.emplace_back("allow");
      return fail_allow ? kIOReturnError : kIOReturnSuccess;
    },
            [this](io_object_t *notifier) {
      check(*notifier == 53);
      ++stops;
      events.emplace_back("unsubscribe");
      *notifier = IO_OBJECT_NULL;
      return fail_stop ? kIOReturnError : kIOReturnSuccess;
    },
            [this](IONotificationPortRef value) {
      check(value == port());
      ++destroys;
      events.emplace_back("destroy");
      if (throw_destroy) throw std::bad_alloc();
    },
            [this](io_connect_t connection) {
      check(connection == 47);
      ++closes;
      events.emplace_back("close");
      return fail_close ? kIOReturnError : kIOReturnSuccess;
    }};
  }
  void event(natural_t message, intptr_t token = 19) {
    check(queue && callback);
    dispatch_sync(queue, ^{ callback(context, 0, message, reinterpret_cast<void *>(token)); });
  }
};
struct Fixture {
  Clock clock;
  Output output;
  std::atomic<CBManagerAuthorization> auth{CBManagerAuthorizationAllowedAlways};
  std::size_t constructions = 0;
  dispatch_queue_t queue = nil;
  TestCentral *central = [TestCentral new];
  TestPeripheral *peripheral = [TestPeripheral new];
  TestService *service = [TestService new];
  TestCharacteristic *characteristic = [TestCharacteristic new];
  PowerFixture power;
  std::unique_ptr<SDK> sdk;
  Fixture() {
    central.state = CBManagerStatePoweredOn;
    peripheral.identifier = [[NSUUID alloc]
        initWithUUIDString:@"01234567-89ab-cdef-0123-456789abcdef"];
    peripheral.state = CBPeripheralStateDisconnected;
    peripheral.canSendWriteWithoutResponse = YES;
    peripheral.writeMaximum = 512;
    peripheral.commandMaximum = 20;
    peripheral.events = &output.events;
    service.peripheral = (CBPeripheral *)peripheral;
    service.uuidValue = [CBUUID UUIDWithString:@"181A"];
    characteristic.service = (CBService *)service;
    characteristic.uuidValue = [CBUUID UUIDWithString:@"2A6E"];
    characteristic.properties = CBCharacteristicPropertyRead | CBCharacteristicPropertyWrite |
        CBCharacteristicPropertyWriteWithoutResponse;
    service.characteristics = @[ (CBCharacteristic *)characteristic ];
    peripheral.services = @[ (CBService *)service ];
    central.found = @[ (CBPeripheral *)peripheral ];
    sdk = std::make_unique<SDK>(clock, output, SDKEnvironment{[this] {
      return auth.load();
    }, [this](id<CBCentralManagerDelegate> delegate, dispatch_queue_t target) {
      ++constructions;
      queue = target;
      central.delegate = delegate;
      return (CBCentralManager *)central;
    }, power.api()});
  }
  SDKConfig config() const {
    return {identifier, 7, Permission::require_authorized, Pairing::system};
  }
  template <typename F> void event(F action) {
    dispatch_sync(queue, ^{ action(); });
  }
  void begin() {
    check(sdk->open(config(), 100, 200) == Code::ok && constructions == 1);
    event([&] { [central.delegate centralManagerDidUpdateState:(CBCentralManager *)central]; });
    check(central.connects == 1 && central.requested.count == 1 &&
          [central.requested[0] isEqual:peripheral.identifier]);
  }
  void connect() {
    peripheral.state = CBPeripheralStateConnected;
    event([&] {
      [central.delegate centralManager:(CBCentralManager *)central
                  didConnectPeripheral:(CBPeripheral *)peripheral];
    });
    check(peripheral.serviceCalls == 1);
  }
  void discover() {
    event([&] {
      [peripheral.delegate peripheral:(CBPeripheral *)peripheral didDiscoverServices:nil];
    });
    check(peripheral.characteristicCalls == 1);
    event([&] {
      [peripheral.delegate peripheral:(CBPeripheral *)peripheral
          didDiscoverCharacteristicsForService:(CBService *)service
                                         error:nil];
    });
    check(output.opens == std::vector<Code>{Code::ok} &&
          output.routes.size() == service.characteristics.count);
  }
  void ready() {
    begin();
    connect();
    discover();
  }
  void notify_ready() {
    characteristic.properties |= CBCharacteristicPropertyNotify;
    ready();
  }
  void notification_state(bool enabled, NSError *error = nil) {
    characteristic.isNotifying = enabled;
    event([&] {
      [peripheral.delegate peripheral:(CBPeripheral *)peripheral
          didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
                                                error:error];
    });
  }
  void notification_value(const std::vector<std::uint8_t> &bytes, NSError *error = nil) {
    characteristic.value = [NSData dataWithBytes:bytes.data() length:bytes.size()];
    event([&] {
      [peripheral.delegate peripheral:(CBPeripheral *)peripheral
          didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
                                    error:error];
    });
  }
  void close() {
    sdk->close(clock.sample());
    check(sdk->closed());
    check(!central.delegate && !peripheral.delegate && central.cancels == 1);
    sdk->close(clock.sample());
    check(central.cancels == 1);
  }
  ~Fixture() {
    if (sdk && !sdk->closed()) sdk->close(clock.sample());
  }
};
static void permissions() {
  for (const auto auth : {CBManagerAuthorizationNotDetermined, CBManagerAuthorizationDenied,
                          CBManagerAuthorizationRestricted}) {
    Fixture f;
    f.auth = auth;
    check(f.sdk->open(f.config(), 100, 200) == Code::ok && f.constructions == 0 &&
          f.power.starts == 0);
    check(f.output.opens == std::vector<Code>{Code::not_authorized} && f.sdk->closed());
  }
  Fixture f;
  f.auth = CBManagerAuthorizationNotDetermined;
  auto config = f.config();
  config.permission = Permission::request;
  check(f.sdk->open(config, 100, 200) == Code::ok && f.constructions == 1);
  f.event([&] { [f.central.delegate centralManagerDidUpdateState:(CBCentralManager *)f.central]; });
  check(f.central.connects == 0 && f.output.opens.empty());
  f.auth = CBManagerAuthorizationAllowedAlways;
  f.event([&] { [f.central.delegate centralManagerDidUpdateState:(CBCentralManager *)f.central]; });
  check(f.central.connects == 1);
  f.close();
}
static void invalid_options() {
  Fixture f;
  for (unsigned int i = 0; i < 8; ++i) {
    auto config = f.config();
    std::int64_t now = 100, deadline = 200;
    switch (i) {
    case 0:
      config.identifier[0] = 'A';
      break;
    case 1:
      config.identifier.resize(35);
      break;
    case 2:
      config.generation = 0;
      break;
    case 3:
      config.pairing = Pairing::unspecified;
      break;
    case 4:
      config.permission = static_cast<Permission>(99);
      break;
    case 5:
      now = -1;
      break;
    case 6:
      deadline = now;
      break;
    case 7:
      deadline = now + 60001;
      break;
    default:
      std::abort();
    }
    check(f.sdk->open(config, now, deadline) == Code::invalid_options && f.constructions == 0);
  }
  check(f.output.opens.empty());
}
static void discovery() {
  Fixture f;
  auto *duplicate = [TestCharacteristic new];
  duplicate.service = (CBService *)f.service;
  duplicate.uuidValue = [CBUUID UUIDWithString:@"2A6E"];
  duplicate.properties = CBCharacteristicPropertyRead;
  f.service.characteristics = @[
    (CBCharacteristic *)f.characteristic, (CBCharacteristic *)duplicate
  ];
  f.begin();
  f.connect();
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral didDiscoverServices:nil];
  });
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didDiscoverCharacteristicsForService:(CBService *)f.service
                                       error:nil];
  });
  check(f.output.routes.size() == 2 && f.output.routes[0].route.token == 1 &&
        f.output.routes[1].route.token == 2);
  check(f.output.routes[0].service == "0000181a-0000-1000-8000-00805f9b34fb" &&
        f.output.routes[0].characteristic == "00002a6e-0000-1000-8000-00805f9b34fb" &&
        f.output.routes[1].characteristic == f.output.routes[0].characteristic);
  f.close();
}
static void discovery_refusal() {
  for (unsigned int kind = 0; kind < 4; ++kind) {
    Fixture f;
    f.begin();
    f.connect();
    if (kind == 0) f.service.peripheral = nil;
    if (kind == 1) {
      NSMutableArray *values = [NSMutableArray new];
      for (int i = 0; i < 65; ++i) [values addObject:f.service];
      f.peripheral.services = values;
    }
    if (kind == 2) f.characteristic.service = nil;
    if (kind == 3) {
      NSMutableArray *values = [NSMutableArray new];
      for (int i = 0; i < 257; ++i) [values addObject:f.characteristic];
      f.service.characteristics = values;
    }
    f.event([&] {
      [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral didDiscoverServices:nil];
    });
    if (!f.sdk->closed())
      f.event([&] {
        [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
            didDiscoverCharacteristicsForService:(CBService *)f.service
                                           error:nil];
      });
    check(f.sdk->closed() && f.central.cancels == 1 && f.output.opens.size() == 1 &&
          f.output.opens[0] ==
              (kind == 0 || kind == 2 ? Code::invalid_response : Code::resource_limit));
  }
}
static void discovery_capacity() {
  Fixture f;
  NSMutableArray<CBService *> *services = [NSMutableArray new];
  for (int s = 0; s < 64; ++s) {
    auto *service = [TestService new];
    service.peripheral = (CBPeripheral *)f.peripheral;
    service.uuidValue = [CBUUID UUIDWithString:@"181A"];
    NSMutableArray<CBCharacteristic *> *characteristics = [NSMutableArray new];
    for (int c = 0; c < 4; ++c) {
      auto *characteristic = [TestCharacteristic new];
      characteristic.service = (CBService *)service;
      characteristic.uuidValue = [CBUUID UUIDWithString:@"2A6E"];
      characteristic.properties = CBCharacteristicPropertyRead;
      [characteristics addObject:(CBCharacteristic *)characteristic];
    }
    service.characteristics = characteristics;
    [services addObject:(CBService *)service];
  }
  f.peripheral.services = services;
  f.begin();
  f.connect();
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral didDiscoverServices:nil];
  });
  for (CBService *service in services) {
    f.event([&] {
      [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
          didDiscoverCharacteristicsForService:service
                                         error:nil];
    });
  }
  check(f.output.routes.size() == 256 && f.output.opens == std::vector<Code>{Code::ok});
  check(f.output.routes.back().route.token == 256 && f.peripheral.characteristicCalls == 64);
  f.close();
}
static void missing_and_expired() {
  Fixture missing;
  missing.central.found = @[];
  check(missing.sdk->open(missing.config(), 100, 200) == Code::ok);
  missing.event([&] {
    [missing.central.delegate centralManagerDidUpdateState:(CBCentralManager *)missing.central];
  });
  check(missing.output.opens == std::vector<Code>{Code::peer_not_found} &&
        missing.central.connects == 0);
  Fixture expired;
  expired.begin();
  id<CBCentralManagerDelegate> old = expired.central.delegate;
  expired.clock.now = 200;
  expired.peripheral.state = CBPeripheralStateConnected;
  expired.event([&] {
    [expired.central.delegate centralManager:(CBCentralManager *)expired.central
                        didConnectPeripheral:(CBPeripheral *)expired.peripheral];
  });
  check(expired.output.opens == std::vector<Code>{Code::timeout} && expired.sdk->closed());
  expired.event([&] {
    [old centralManager:(CBCentralManager *)expired.central
        didConnectPeripheral:(CBPeripheral *)expired.peripheral];
  });
  check(expired.output.opens.size() == 1 && expired.central.cancels == 1);
}
static void modes() {
  Fixture f;
  f.ready();
  check(f.sdk->request(1, 1, Mode::read, {}, 100, 200) == Code::ok && f.peripheral.reads == 1 &&
        f.output.events.empty());
  f.characteristic.value = [NSData dataWithBytes:payload.data() length:payload.size()];
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didUpdateValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                  error:nil];
  });
  check(f.output.results.size() == 1 && f.output.results[0].evidence == Evidence::value &&
        f.output.results[0].bytes == payload);
  check(f.sdk->request(2, 1, Mode::write, payload, 100, 200) == Code::ok);
  check(f.output.events == std::vector<std::string>({"marker", "sdk"}) &&
        f.peripheral.lastMode == CBCharacteristicWriteWithResponse);
  check(f.output.results.size() == 1);
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didWriteValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                 error:nil];
  });
  check(f.output.results[1].evidence == Evidence::att_response);
  f.peripheral.canSendWriteWithoutResponse = NO;
  check(f.sdk->request(3, 1, Mode::command, payload, 100, 200) == Code::ok &&
        f.peripheral.writes == 1);
  f.clock.now = 150;
  f.peripheral.canSendWriteWithoutResponse = YES;
  f.event([&] {
    [f.peripheral.delegate
        peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)f.peripheral];
  });
  check(f.peripheral.writes == 2 && f.peripheral.lastMode == CBCharacteristicWriteWithoutResponse &&
        [f.peripheral.lastWrite
            isEqualToData:[NSData dataWithBytes:payload.data() length:payload.size()]]);
  check(f.output.results[2].evidence == Evidence::native_queue_accepted &&
        f.output.results[2].ticket.request == 3);
  f.close();
}
static void operation_refusal() {
  Fixture f;
  f.ready();
  check(f.sdk->request(1, 1, Mode::command, std::vector<std::uint8_t>(21), 100, 200) == Code::ok);
  check(f.output.results.back().code == Code::invalid_value_length && f.peripheral.writes == 0 &&
        f.output.events.empty());
  f.peripheral.commandMaximum = 0;
  check(f.sdk->request(2, 1, Mode::command, {}, 100, 200) == Code::ok &&
        f.output.results.back().code == Code::not_supported);
  f.output.admit = false;
  check(f.sdk->request(3, 1, Mode::write, payload, 100, 200) == Code::ok &&
        f.output.results.back().code == Code::resource_limit);
  check(f.peripheral.writes == 0 && !f.output.results.back().submitted);
  f.characteristic.isNotifying = YES;
  check(f.sdk->request(4, 1, Mode::read, {}, 100, 200) == Code::not_supported &&
        f.peripheral.reads == 0);
  check(f.sdk->request(3, 1, Mode::read, {}, 100, 200) == Code::invalid_options);
  f.close();
}
static void submission_boundary() {
  for (unsigned int kind = 0; kind < 4; ++kind) {
    Fixture f;
    f.ready();
    f.output.onMarker = [&] {
      if (kind == 0) f.clock.now = 200;
      if (kind == 1) f.clock.now = 99;
      if (kind == 2) f.auth = CBManagerAuthorizationDenied;
      if (kind == 3) f.peripheral.writeMaximum = payload.size() - 1;
    };
    check(f.sdk->request(1, 1, Mode::write, payload, 100, 200) == Code::ok);
    const Code expected[] = {Code::timeout, Code::clock_regressed, Code::not_authorized,
                             Code::invalid_value_length};
    check(f.sdk->closed() && f.peripheral.writes == 0 && f.output.results.size() == 1);
    check(f.output.results[0].code == expected[kind] && f.output.results[0].submitted &&
          f.output.results[0].cleanup_confirmed && f.central.cancels == 1);
  }
}
static void read_callbacks() {
  for (unsigned int kind = 0; kind < 4; ++kind) {
    Fixture f;
    f.ready();
    check(f.sdk->request(1, 1, Mode::read, {}, 100, 200) == Code::ok);
    if (kind == 0) f.characteristic.value = [NSData data];
    if (kind == 1) f.characteristic.value = [NSMutableData dataWithLength:513];
    if (kind == 2) f.characteristic.isNotifying = YES;
    NSError *error = kind == 3 ? [NSError errorWithDomain:@"private" code:123 userInfo:nil] : nil;
    f.event([&] {
      [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
          didUpdateValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                    error:error];
    });
    check(f.output.results.size() == 1);
    const auto &result = f.output.results[0];
    check(result.code ==
          (kind == 0       ? Code::ok
               : kind == 3 ? Code::transport_error
                           : Code::invalid_response));
    check(!result.submitted && result.bytes.empty());
    if (kind == 0) check(result.evidence == Evidence::value);
    f.close();
  }
}
static void released_objects() {
  std::unique_ptr<Fixture> f;
  __weak TestCentral *central;
  __weak TestPeripheral *peripheral;
  __weak TestService *service;
  __weak TestCharacteristic *characteristic;
  @autoreleasepool {
    f = std::make_unique<Fixture>();
    f->notify_ready();
    check(f->sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
    f->notification_state(true);
    central = f->central;
    peripheral = f->peripheral;
    service = f->service;
    characteristic = f->characteristic;
    f->central = nil;
    f->peripheral = nil;
    f->service = nil;
    f->characteristic = nil;
  }
  check(central && peripheral && service && characteristic);
  f->sdk->close(100);
  check(f->sdk->closed() && !central && !peripheral && !service && !characteristic);
}
static void callback_identity() {
  Fixture f;
  f.ready();
  check(f.sdk->request(1, 1, Mode::write, payload, 100, 200) == Code::ok);
  auto *foreign = [TestCharacteristic new];
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didWriteValueForCharacteristic:(CBCharacteristic *)foreign
                                 error:nil];
  });
  check(f.output.results.empty());
  id<CBPeripheralDelegate> old = f.peripheral.delegate;
  f.close();
  check(f.output.results.size() == 1 && f.output.results[0].submitted &&
        f.output.results[0].cleanup_confirmed);
  f.event([&] {
    [old peripheral:(CBPeripheral *)f.peripheral
        didWriteValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                 error:nil];
  });
  check(f.output.results.size() == 1 && f.output.losses.size() == 1);
  check(f.sdk->request(2, 1, Mode::write, payload, 101, 200) == Code::disconnected);
}
static void continuity_loss() {
  for (unsigned int kind = 0; kind < 5; ++kind) {
    Fixture f;
    f.ready();
    f.peripheral.canSendWriteWithoutResponse = NO;
    check(f.sdk->request(1, 1, Mode::command, payload, 100, 200) == Code::ok);
    if (kind == 0) f.auth = CBManagerAuthorizationDenied;
    if (kind == 1) f.central.state = CBManagerStateResetting;
    if (kind == 2) f.clock.now = 99;
    if (kind == 3) f.clock.now = 200;
    if (kind == 4) {
      f.event([&] {
        [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
                        didModifyServices:@[ (CBService *)f.service ]];
      });
    } else f.sdk->poll(f.clock.sample());
    const Code expected[] = {Code::not_authorized, Code::disconnected, Code::clock_regressed,
                             Code::timeout, Code::stale_discovery};
    check(f.sdk->closed() && f.output.results.size() == 1 &&
          f.output.results[0].code == expected[kind] && !f.output.results[0].submitted &&
          f.peripheral.writes == 0 && f.central.connects == 1);
    check(f.output.losses == std::vector<Code>{expected[kind]});
  }
}
static void cleanup_fault() {
  Fixture f;
  f.ready();
  check(f.sdk->request(1, 1, Mode::write, payload, 100, 200) == Code::ok);
  f.central.failCleanup = YES;
  f.clock.now = 200;
  f.sdk->poll(200);
  check(f.sdk->closed() && f.central.cancels == 1 && !f.central.delegate && !f.peripheral.delegate);
  check(f.output.results[0].code == Code::cleanup_timeout &&
        f.output.results[0].cause == Code::timeout && f.output.results[0].submitted &&
        !f.output.results[0].cleanup_confirmed);
  check(f.output.losses == std::vector<Code>{Code::cleanup_timeout});
}
static void independent() {
  Fixture first, second;
  first.ready();
  second.ready();
  check(first.sdk->request(1, 1, Mode::write, payload, 100, 200) == Code::ok);
  first.close();
  check(second.output.losses.empty() && second.central.cancels == 0);
  check(second.sdk->request(1, 1, Mode::command, payload, 100, 200) == Code::ok);
  check(second.output.results[0].evidence == Evidence::native_queue_accepted);
  second.close();
}
static Json notification_vectors(const char *path) {
  std::ifstream input(path);
  Json value;
  input >> value;
  check(value["format"] == "wotex.ble.corebluetooth.notifications" && value["version"] == "1.0.0");
  check(value["mode_cases"].size() == 12 && value["control_cases"].size() == 6);
  return value;
}
static void notification_modes(const Json &vectors) {
  const std::map<std::string, NotificationMode> modes{{"auto", NotificationMode::automatic},
                                                      {"notify", NotificationMode::notify},
                                                      {"indicate", NotificationMode::indicate}};
  for (const auto &cell : vectors["mode_cases"]) {
    Fixture f;
    if (cell["notify"].get<bool>()) f.characteristic.properties |= CBCharacteristicPropertyNotify;
    if (cell["indicate"].get<bool>())
      f.characteristic.properties |= CBCharacteristicPropertyIndicate;
    f.ready();
    const auto mode = modes.at(cell["requested"].get<std::string>());
    const bool supported = !cell["effective"].is_null();
    check(f.sdk->subscribe(1, 1, mode, 4, 100, 200) ==
          (supported ? Code::ok : Code::not_supported));
    check(f.peripheral.notifyCalls == (supported ? 1u : 0u));
    check(f.output.notifications.empty() && f.peripheral.reads == 0);
    if (supported) {
      check(f.peripheral.notifyEnabled &&
            f.peripheral.notifyTarget == (CBCharacteristic *)f.characteristic);
      f.notification_state(true);
      check(f.output.notifications.size() == 1);
      const auto &result = f.output.notifications[0];
      check(result.code == Code::ok && result.enabled && result.requested == mode &&
            result.effective == modes.at(cell["effective"].get<std::string>()));
    }
    f.close();
  }
  Fixture f;
  f.notify_ready();
  for (unsigned i = 0; i < 8; ++i) {
    check(f.sdk->subscribe(i == 0 ? 0 : 1,
                           i == 1       ? 0
                               : i == 2 ? 257
                                        : 1,
                           // An unnamed fixed-underlying enum value deliberately tests refusal.
                           // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
                           i == 3 ? static_cast<NotificationMode>(99) : NotificationMode::automatic,
                           i == 4       ? 0
                               : i == 5 ? 65
                                        : 4,
                           i == 6 ? -1 : 100, i == 7 ? 100 : 200) == Code::invalid_options);
  }
  f.characteristic.isNotifying = YES;
  check(f.sdk->subscribe(1, 1, NotificationMode::automatic, 4, 100, 200) == Code::not_permitted);
  check(f.peripheral.notifyCalls == 0);
  f.close();
}
static void notification_controls(const Json &vectors) {
  const std::map<std::string, Code> codes{{"ok", Code::ok},
                                          {"invalid_response", Code::invalid_response},
                                          {"transport_error", Code::transport_error}};
  for (const auto &cell : vectors["control_cases"]) {
    Fixture current;
    current.notify_ready();
    check(current.sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
    if (!cell["enable"].get<bool>()) {
      current.notification_state(true);
      current.output.notifications.clear();
      check(current.sdk->unsubscribe(2, 1, 100, 200) == Code::ok);
    }
    current.notification_state(
        cell["callback_enabled"].get<bool>(),
        cell["error"].get<bool>() ? [NSError errorWithDomain:@"private" code:1 userInfo:nil] : nil);
    check(current.output.notifications.size() == 1 &&
          current.output.notifications[0].code == codes.at(cell["code"].get<std::string>()));
    check(current.sdk->closed() == (cell["code"] != "ok"));
    current.close();
  }
  Fixture f;
  f.notify_ready();
  check(f.sdk->subscribe(1, 1, NotificationMode::automatic, 4, 100, 200) == Code::ok);
  auto *foreign = [TestCharacteristic new];
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)foreign
                                              error:nil];
  });
  check(f.output.notifications.empty());
  f.notification_state(true);
  check(f.output.notifications.size() == 1 && f.output.notifications[0].subscription == 1 &&
        f.output.notifications[0].ticket == (Ticket{7, 1, 1}));
  check(f.sdk->subscribe(2, 1, NotificationMode::notify, 4, 100, 200) == Code::not_permitted);
  check(f.sdk->unsubscribe(2, 999, 100, 200) == Code::invalid_options);
  check(f.sdk->unsubscribe(2, 1, 100, 200) == Code::ok);
  check(f.peripheral.notifyCalls == 2 && !f.peripheral.notifyEnabled);
  f.notification_value(payload);
  check(f.output.values.empty());
  f.notification_state(false);
  check(f.output.notifications.size() == 2 && !f.output.notifications[1].enabled &&
        f.output.notifications[1].ticket == (Ticket{7, 2, 1}) &&
        f.output.notifications[1].cleanup_confirmed);
  f.notification_state(false);
  f.notification_value(payload);
  check(f.output.notifications.size() == 2 && f.output.values.empty());
  check(f.sdk->subscribe(3, 1, NotificationMode::notify, 4, 100, 200) == Code::not_permitted);
  check(f.sdk->request(3, 1, Mode::read, {}, 100, 200) == Code::not_supported);
  f.close();
}
static void notification_values() {
  Fixture f;
  f.notify_ready();
  check(f.sdk->subscribe(1, 1, NotificationMode::automatic, 4, 100, 200) == Code::ok);
  f.notification_value(payload);
  f.notification_value(payload);
  check(f.output.values.empty() && f.peripheral.reads == 0);
  check(f.sdk->acknowledge(1, 1, 100) == Code::invalid_options);
  f.notification_state(true);
  check(f.output.events == std::vector<std::string>({"state", "value", "value"}));
  check(f.output.values.size() == 2 && f.output.values[0].bytes == payload &&
        f.output.values[1].bytes == payload);
  f.notification_value({});
  f.notification_value(std::vector<std::uint8_t>(512, 255));
  check(f.output.values.size() == 4 && f.output.values[2].bytes.empty() &&
        f.output.values[3].bytes == std::vector<std::uint8_t>(512, 255));
  for (std::size_t i = 0; i < 4; ++i) {
    const auto &value = f.output.values[i];
    check(value.generation == 7 && value.route == 1 && value.subscription == 1 &&
          value.sequence == i + 1);
  }
  check(f.sdk->acknowledge(1, 2, 100) == Code::ok);
  f.notification_value({7});
  f.notification_value({8});
  check(f.output.values.size() == 6 && f.output.values[4].sequence == 5 &&
        f.output.values[5].sequence == 6 && f.output.values[0].bytes == payload);
  f.close();
}
static void notification_credit() {
  Fixture f;
  f.notify_ready();
  check(f.sdk->subscribe(1, 1, NotificationMode::notify, 2, 100, 200) == Code::ok);
  f.notification_state(true);
  f.notification_value({1});
  f.notification_value({2});
  check(f.sdk->acknowledge(1, 3, 100) == Code::invalid_options);
  check(f.sdk->acknowledge(999, 1, 100) == Code::invalid_options);
  check(f.sdk->acknowledge(1, 1, 100) == Code::ok);
  check(f.sdk->acknowledge(1, 1, 100) == Code::ok);
  check(f.sdk->acknowledge(1, 0, 100) == Code::invalid_options);
  f.notification_value({3});
  check(f.output.values.size() == 3 && f.output.values.back().sequence == 3);
  f.notification_value({4});
  check(f.sdk->closed() && f.output.values.size() == 3 &&
        f.output.losses == std::vector<Code>{Code::resource_limit});
  Fixture early;
  early.notify_ready();
  check(early.sdk->subscribe(1, 1, NotificationMode::notify, 1, 100, 200) == Code::ok);
  early.notification_value({1});
  early.notification_value({2});
  check(early.sdk->closed() && early.output.values.empty() &&
        early.output.notifications.size() == 1 &&
        early.output.notifications[0].code == Code::resource_limit &&
        early.output.notifications[0].cleanup_confirmed);
}
static void notification_capacity() {
  for (unsigned kind = 0; kind < 2; ++kind) {
    Fixture f;
    NSMutableArray<CBCharacteristic *> *items = [NSMutableArray new];
    for (unsigned i = 0; i < 17; ++i) {
      auto *item = [TestCharacteristic new];
      item.service = (CBService *)f.service;
      item.uuidValue = [CBUUID UUIDWithString:@"2A6E"];
      item.properties = CBCharacteristicPropertyNotify;
      [items addObject:(CBCharacteristic *)item];
    }
    f.service.characteristics = items;
    f.ready();
    const auto start = [&](std::uint64_t number, std::uint64_t route, unsigned credit) {
      check(f.sdk->subscribe(number, route, NotificationMode::notify, credit, 100, 200) ==
            Code::ok);
      ((TestCharacteristic *)items[route - 1]).isNotifying = YES;
      f.event([&] {
        [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
            didUpdateNotificationStateForCharacteristic:items[route - 1]
                                                  error:nil];
      });
    };
    if (kind == 0) {
      for (unsigned i = 1; i <= 16; ++i) start(i, i, 1);
      check(f.sdk->subscribe(17, 17, NotificationMode::notify, 1, 100, 200) ==
            Code::resource_limit);
      check(f.peripheral.notifyCalls == 16);
    } else {
      start(1, 1, 64);
      for (unsigned i = 0; i < 64; ++i) {
        ((TestCharacteristic *)items[0]).value = [NSData data];
        f.event([&] {
          [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
              didUpdateValueForCharacteristic:items[0]
                                        error:nil];
        });
      }
      check(f.output.values.size() == 64);
      check(f.sdk->subscribe(2, 2, NotificationMode::notify, 1, 100, 200) == Code::resource_limit);
      check(f.sdk->unsubscribe(3, 1, 100, 200) == Code::ok);
      ((TestCharacteristic *)items[0]).isNotifying = NO;
      f.event([&] {
        [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
            didUpdateNotificationStateForCharacteristic:items[0]
                                                  error:nil];
      });
      check(f.sdk->subscribe(4, 2, NotificationMode::notify, 1, 100, 200) == Code::resource_limit);
      check(f.sdk->acknowledge(1, 64, 100) == Code::ok);
      start(5, 2, 64);
      check(f.sdk->subscribe(6, 1, NotificationMode::notify, 1, 100, 200) == Code::not_permitted);
    }
    f.close();
  }
}
static void notification_faults() {
  for (unsigned kind = 0; kind < 10; ++kind) {
    Fixture f;
    f.notify_ready();
    if (kind == 7) f.peripheral.failNotify = YES;
    if (kind == 6) f.output.admitState = false;
    check(f.sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
    if (kind != 7) f.notification_state(true);
    if (kind < 6) {
      if (kind == 0) f.characteristic.value = nil;
      else f.characteristic.value = [NSMutableData dataWithLength:kind == 1 ? 513 : 1];
      if (kind == 3) f.characteristic.service = nil;
      if (kind == 4) f.characteristic.properties = CBCharacteristicPropertyRead;
      if (kind == 5) f.output.admitValue = false;
      f.event([&] {
        [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
            didUpdateValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                      error:kind == 2
                                          ? [NSError errorWithDomain:@"private" code:1 userInfo:nil]
                                          : nil];
      });
    }
    if (kind == 8)
      f.notification_state(true, [NSError errorWithDomain:@"private" code:1 userInfo:nil]);
    if (kind == 9) f.notification_state(false);
    check(f.sdk->closed() && f.output.losses.size() == 1 && f.central.cancels == 1 &&
          f.output.values.empty());
    check(!f.central.delegate && !f.peripheral.delegate);
  }
}
static void notification_deadlines() {
  for (unsigned kind = 0; kind < 7; ++kind) {
    Fixture f;
    f.notify_ready();
    check(f.sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
    if (kind == 5 || kind == 6) {
      f.notification_state(true);
      check(f.sdk->unsubscribe(2, 1, 100, 200) == Code::ok);
      f.output.notifications.clear();
    }
    f.output.onState = [&](const NotificationResult &value) {
      check(value.code != Code::ok && !f.central.delegate && !f.peripheral.delegate);
    };
    if (kind == 0 || kind == 5) f.clock.now = 200;
    if (kind == 1) f.clock.now = 99;
    if (kind == 2) f.auth = CBManagerAuthorizationDenied;
    if (kind == 3) f.central.state = CBManagerStateResetting;
    if (kind == 4 || kind == 6) f.sdk->close(100);
    else f.sdk->poll(f.clock.sample());
    const Code expected[] = {Code::timeout,      Code::clock_regressed, Code::not_authorized,
                             Code::disconnected, Code::disconnected,    Code::timeout,
                             Code::disconnected};
    check(f.sdk->closed() && f.output.notifications.size() == 1 &&
          f.output.notifications[0].code == expected[kind] &&
          f.output.notifications[0].cleanup_confirmed);
  }
  Fixture f;
  f.notify_ready();
  std::function<void()> elapsed = [&] { f.clock.now = 200; };
  f.peripheral.onNotify = &elapsed;
  check(f.sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
  check(f.sdk->closed() && f.output.notifications.size() == 1 &&
        f.output.notifications[0].code == Code::timeout);
  Fixture uncertain;
  uncertain.notify_ready();
  check(uncertain.sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
  uncertain.central.failCleanup = YES;
  uncertain.sdk->close(100);
  check(uncertain.sdk->closed() && uncertain.output.notifications.size() == 1 &&
        uncertain.output.notifications[0].code == Code::cleanup_timeout &&
        !uncertain.output.notifications[0].cleanup_confirmed &&
        uncertain.output.losses == std::vector<Code>{Code::cleanup_timeout});
}
static void notification_aliases() {
  Fixture f, other;
  auto *reader = [TestCharacteristic new];
  reader.service = (CBService *)f.service;
  reader.uuidValue = [CBUUID UUIDWithString:@"2A19"];
  reader.properties = CBCharacteristicPropertyRead;
  f.service.characteristics = @[ (CBCharacteristic *)f.characteristic, (CBCharacteristic *)reader ];
  f.notify_ready();
  other.notify_ready();
  check(f.sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
  check(f.sdk->request(2, 2, Mode::read, {}, 100, 200) == Code::resource_limit);
  check(other.sdk->subscribe(1, 1, NotificationMode::notify, 4, 100, 200) == Code::ok);
  other.notification_state(true);
  check(f.output.notifications.empty());
  f.notification_state(true);
  check(f.sdk->request(2, 1, Mode::read, {}, 100, 200) == Code::not_supported);
  check(f.sdk->request(2, 2, Mode::read, {}, 100, 200) == Code::ok);
  f.notification_value(payload);
  check(f.output.results.empty() && f.output.values.size() == 1);
  reader.value = [NSData data];
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didUpdateValueForCharacteristic:(CBCharacteristic *)reader
                                  error:nil];
  });
  check(f.output.results.size() == 1 && f.output.results[0].evidence == Evidence::value &&
        f.output.results[0].bytes.empty());
  check(f.sdk->request(3, 1, Mode::write, payload, 100, 200) == Code::ok);
  f.notification_value({42});
  check(f.output.results.size() == 1 && f.output.values.size() == 2);
  f.event([&] {
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didWriteValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                 error:nil];
  });
  check(f.output.results.size() == 2 && f.output.results[1].evidence == Evidence::att_response);
  id<CBPeripheralDelegate> retired = f.peripheral.delegate;
  f.close();
  f.event([&] {
    [retired peripheral:(CBPeripheral *)f.peripheral
        didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)f.characteristic
                                              error:nil];
    [retired peripheral:(CBPeripheral *)f.peripheral
        didUpdateValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                  error:nil];
  });
  check(f.output.values.size() == 2 && f.output.notifications.size() == 1);
  other.notification_value(payload);
  check(other.output.values.size() == 1 && other.output.losses.empty());
  other.close();
}
static void power_registration() {
  Fixture passive;
  check(passive.power.starts == 0);
  passive.sdk->close(100);
  check(passive.power.starts == 0 && passive.constructions == 0);
  for (unsigned refusal = 1; refusal <= 4; ++refusal) {
    Fixture f;
    f.power.refusal = refusal;
    check(f.sdk->open(f.config(), 100, 200) == Code::ok);
    check(f.sdk->closed() && f.constructions == 0 && f.power.starts == 1);
    check(f.output.opens == std::vector<Code>{Code::transport_error});
    check(f.power.stops == (refusal == 1 || refusal == 4 ? 0u : 1u));
    check(f.power.destroys == (refusal == 1 || refusal == 3 ? 0u : 1u));
    check(f.power.closes == (refusal <= 2 ? 0u : 1u));
    f.sdk->close(100);
    check(f.power.starts == 1);
  }
  for (unsigned changed = 0; changed < 3; ++changed) {
    Fixture f;
    f.power.on_dispatch = [&] {
      if (changed == 0) f.clock.now = 200;
      if (changed == 1) f.clock.now = 99;
      if (changed == 2) f.auth = CBManagerAuthorizationDenied;
    };
    check(f.sdk->open(f.config(), 100, 200) == Code::ok);
    const Code expected[] = {Code::timeout, Code::clock_regressed, Code::not_authorized};
    check(f.sdk->closed() && f.constructions == 0 &&
          f.output.opens == std::vector<Code>{expected[changed]});
    check(f.power.stops == 1 && f.power.destroys == 1 && f.power.closes == 1);
  }
  Fixture opening;
  opening.begin();
  opening.power.event(kIOMessageSystemWillSleep);
  check(opening.sdk->closed() && opening.output.opens == std::vector<Code>{Code::disconnected});
  check(opening.power.allowed == std::vector<intptr_t>{19});
  check(opening.power.stops == 1 && opening.power.destroys == 1 && opening.power.closes == 1);
}
static void power_messages() {
  Fixture f;
  f.ready();
  f.power.event(kIOMessageCanSystemSleep, 17);
  f.power.event(kIOMessageSystemWillNotSleep);
  f.power.event(UINT32_MAX);
  check(f.power.allowed == std::vector<intptr_t>{17} && f.output.losses.empty() &&
        !f.sdk->closed());
  f.power.event(kIOMessageSystemWillSleep, 23);
  check(f.power.allowed == std::vector<intptr_t>({17, 23}));
  check(f.power.events ==
        std::vector<std::string>(
            {"subscribe", "dispatch", "allow", "allow", "unsubscribe", "destroy", "close"}));
  check(f.sdk->closed() && f.output.losses == std::vector<Code>{Code::disconnected});
  check(!f.central.delegate && !f.peripheral.delegate && f.central.cancels == 1);
  f.power.event(kIOMessageCanSystemSleep);
  f.power.event(kIOMessageSystemHasPoweredOn);
  check(f.power.allowed.size() == 2 && f.output.losses.size() == 1);
}
static void power_operations() {
  for (const auto mode : {Mode::read, Mode::write, Mode::command}) {
    Fixture f;
    f.ready();
    f.peripheral.canSendWriteWithoutResponse = NO;
    check(f.sdk->request(1, 1, mode, mode == Mode::read ? std::vector<std::uint8_t>{} : payload,
                         100, 200) == Code::ok);
    id<CBPeripheralDelegate> old = f.peripheral.delegate;
    f.power.event(kIOMessageSystemWillSleep);
    check(f.sdk->closed() && f.output.results.size() == 1);
    const auto &result = f.output.results[0];
    check(result.code == Code::disconnected && result.cleanup_confirmed &&
          result.submitted == (mode == Mode::write));
    check(f.peripheral.writes == (mode == Mode::write ? 1u : 0u));
    f.peripheral.canSendWriteWithoutResponse = YES;
    f.event(
        [&] { [old peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)f.peripheral]; });
    check(f.output.results.size() == 1 && f.peripheral.writes == (mode == Mode::write ? 1u : 0u));
    check(f.sdk->request(2, 1, Mode::write, payload, 100, 200) == Code::disconnected);
  }
}
static void power_notifications() {
  for (unsigned phase = 0; phase < 3; ++phase) {
    Fixture f;
    f.notify_ready();
    check(f.sdk->subscribe(1, 1, NotificationMode::notify, 2, 100, 200) == Code::ok);
    if (phase > 0) {
      f.notification_state(true);
      f.notification_value(payload);
    }
    if (phase == 2) check(f.sdk->unsubscribe(2, 1, 100, 200) == Code::ok);
    f.output.notifications.clear();
    f.output.onState = [&](const NotificationResult &result) {
      check(f.power.stops == 1 && f.power.destroys == 1 && f.power.closes == 1);
      check(!f.central.delegate && !f.peripheral.delegate && result.cleanup_confirmed);
    };
    f.power.event(kIOMessageSystemHasPoweredOn);
    check(f.sdk->closed() && f.output.losses == std::vector<Code>{Code::disconnected});
    check(f.power.allowed.empty());
    check(f.output.notifications.size() == (phase == 1 ? 0u : 1u));
    if (!f.output.notifications.empty())
      check(f.output.notifications[0].code == Code::disconnected);
    const auto count = f.output.values.size();
    f.notification_value(payload);
    f.power.event(kIOMessageSystemWillPowerOn);
    check(f.output.values.size() == count && f.output.losses.size() == 1);
  }
}
static void power_cleanup() {
  for (unsigned fault = 0; fault < 4; ++fault) {
    Fixture f;
    f.ready();
    check(f.sdk->request(1, 1, Mode::write, payload, 100, 200) == Code::ok);
    f.power.fail_stop = fault == 0;
    f.power.fail_close = fault == 1;
    f.power.throw_destroy = fault == 2;
    f.power.fail_allow = fault == 3;
    f.power.event(kIOMessageSystemWillSleep);
    check(f.sdk->closed() && f.output.results.size() == 1);
    const auto &result = f.output.results[0];
    check(result.submitted && result.cleanup_confirmed == (fault == 3));
    check(result.code == (fault == 3 ? Code::transport_error : Code::cleanup_timeout));
    check(f.power.stops == 1 && f.power.destroys == 1 && f.power.closes == 1);
    f.sdk->close(100);
    check(f.power.stops == 1 && f.power.destroys == 1 && f.power.closes == 1);
  }
  Fixture regressed;
  regressed.ready();
  regressed.clock.now = 99;
  regressed.power.event(kIOMessageSystemWillSleep);
  check(regressed.output.losses == std::vector<Code>{Code::clock_regressed});
}
static void power_independent() {
  for (const auto event : {kIOMessageSystemWillPowerOn, kIOMessageSystemHasPoweredOn}) {
    Fixture first, second;
    first.ready();
    second.ready();
    first.power.event(event);
    check(first.sdk->closed() && first.power.allowed.empty());
    check(!second.sdk->closed() && second.power.stops == 0 && second.output.losses.empty());
    second.close();
    check(second.power.stops == 1);
  }
}
static void notification_host_join(bool sleep = false) {
  Fixture f;
  f.sdk.reset();
  f.characteristic.properties |= CBCharacteristicPropertyNotify;
  int input[2], output[2], toggles[2];
  check(pipe(input) == 0 && pipe(output) == 0 && pipe(toggles) == 0);
  std::promise<void> constructed;
  std::promise<int> finished;
  auto opened = constructed.get_future();
  auto stopped = finished.get_future();
  SDKEnvironment environment{[&] { return f.auth.load(); },
                             [&](id<CBCentralManagerDelegate> delegate, dispatch_queue_t queue) {
    f.queue = queue;
    f.central.delegate = delegate;
    constructed.set_value();
    return (CBCentralManager *)f.central;
  }, f.power.api()};
  std::function<void()> toggle = [&] { check(::write(toggles[1], "t", 1) == 1); };
  f.peripheral.onNotify = &toggle;
  std::thread owner([&] {
    finished.set_value(run_host(f.clock, [&](SDKClock &clock, SDKSink &sink) {
      return std::make_unique<SDKDriver>(clock, sink, environment);
    }, input[0], output[1]));
  });
  const auto send = [&](const Json &value) {
    const auto bytes = value.dump() + "\n";
    check(::write(input[1], bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size()));
  };
  const auto request = [&](const char *id, const char *operation, Json parameters) {
    send({{"version", 1},
          {"id", id},
          {"operation", operation},
          {"parameters", std::move(parameters)},
          {"timeout_ms", 1000}});
  };
  const auto frame = [&] {
    std::string bytes;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    for (;;) {
      const auto left = std::chrono::duration_cast<std::chrono::milliseconds>(
                            deadline - std::chrono::steady_clock::now())
                            .count();
      check(left > 0 && bytes.size() < 131072);
      pollfd descriptor{output[0], POLLIN, 0};
      check(::poll(&descriptor, 1, static_cast<int>(left)) > 0);
      char byte = 0;
      check(::read(output[0], &byte, 1) == 1);
      bytes.push_back(byte);
      if (byte == '\n') return Json::parse(bytes);
    }
  };
  const auto toggled = [&] {
    pollfd descriptor{toggles[0], POLLIN, 0};
    check(::poll(&descriptor, 1, 2000) > 0);
    char byte = 0;
    check(::read(toggles[0], &byte, 1) == 1 && byte == 't');
  };
  check(frame() ==
        Json({{"version", 1},
              {"event", "ready"},
              {"backend", "corebluetooth-native"},
              {"revision", "1"}}));
  request("open", "open",
          {{"identifier", identifier},
           {"generation", 7},
           {"permission", "require_authorized"},
           {"pairing", "system"}});
  check(opened.wait_for(std::chrono::seconds(2)) == std::future_status::ready);
  f.event([&] {
    [f.central.delegate centralManagerDidUpdateState:(CBCentralManager *)f.central];
    f.peripheral.state = CBPeripheralStateConnected;
    [f.central.delegate centralManager:(CBCentralManager *)f.central
                  didConnectPeripheral:(CBPeripheral *)f.peripheral];
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral didDiscoverServices:nil];
    [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
        didDiscoverCharacteristicsForService:(CBService *)f.service
                                       error:nil];
  });
  check(frame() ==
        Json({{"version", 1},
              {"generation", 7},
              {"id", "open"},
              {"ok", true},
              {"result", {{"generation", 7}}}}));
  request("1", "subscribe",
          {{"stream_version", 1},
           {"address", {{"generation", 7}, {"route", 1}}},
           {"mode", "auto"},
           {"credit", 2}});
  toggled();
  f.notification_state(true);
  check(frame() ==
        Json({{"version", 1},
              {"generation", 7},
              {"id", "1"},
              {"ok", true},
              {"result",
               {{"stream_version", 1},
                {"subscription_id", "1"},
                {"route", 1},
                {"requested_mode", "auto"},
                {"effective_mode", "notify"},
                {"credit", 2}}}}));
  f.notification_value(payload);
  const auto first = frame();
  check(first.size() == 8 && first["sequence"] == 1 && first["generation"] == 7 &&
        first["subscription_id"] == "1" &&
        first["value"] == Json({{"type", "bytes"}, {"base64", "AAF/gP8="}}));
  send({{"version", 1},
        {"generation", 7},
        {"stream_version", 1},
        {"event", "notification_ack"},
        {"subscription_id", "1"},
        {"sequence", 1}});
  request("2", "health", Json::object());
  check(frame()["id"] == "2");
  request("3", "write",
          {{"address", {{"generation", 7}, {"route", 1}}},
           {"value", {{"type", "bytes"}, {"base64", "AAF/gP8="}}}});
  const auto submitted = frame();
  check(submitted["event"] == "write_submitted" && submitted["id"] == "3");
  if (sleep) {
    f.power.event(kIOMessageSystemWillSleep);
    const auto result = frame();
    check(result["id"] == "3" && result["ok"] == false &&
          result["error"]["code"] == "disconnected" && result["error"]["submitted"] == true &&
          result["error"]["cleanup_confirmed"] == true);
    const auto loss = frame();
    check(loss["event"] == "connection_lost" && loss["code"] == "disconnected");
    check(stopped.wait_for(std::chrono::seconds(2)) == std::future_status::ready &&
          stopped.get() == 1);
  } else {
    f.event([&] {
      check(f.peripheral.writes == 1);
      [f.peripheral.delegate peripheral:(CBPeripheral *)f.peripheral
          didWriteValueForCharacteristic:(CBCharacteristic *)f.characteristic
                                   error:nil];
    });
    const auto written = frame();
    check(written["id"] == "3" && written["ok"] == true && written["result"].is_null());
    f.notification_value({});
    f.notification_value(payload);
    check(frame()["sequence"] == 2 && frame()["sequence"] == 3);
    request("4", "unsubscribe", {{"stream_version", 1}, {"subscription_id", "1"}});
    toggled();
    f.notification_state(false);
    const auto retired = frame();
    check(retired["event"] == "notification_retired" && retired["last_sequence"] == 3);
    const auto closed_stream = frame();
    check(closed_stream["id"] == "4" && closed_stream["ok"] == true &&
          closed_stream["result"].is_null());
    send({{"version", 1},
          {"generation", 7},
          {"stream_version", 1},
          {"event", "notification_ack"},
          {"subscription_id", "1"},
          {"sequence", 3}});
    request("close", "close", Json::object());
    const auto closed = frame();
    check(closed["id"] == "close" && closed["ok"] == true && closed["result"].is_null());
    check(stopped.wait_for(std::chrono::seconds(2)) == std::future_status::ready &&
          stopped.get() == 0);
  }
  owner.join();
  check(!f.central.delegate && !f.peripheral.delegate && f.central.cancels == 1 &&
        f.peripheral.notifyCalls == (sleep ? 1u : 2u) && f.peripheral.reads == 0);
  check(f.power.stops == 1 && f.power.destroys == 1 && f.power.closes == 1);
  for (const auto descriptor : {input[0], input[1], output[0], output[1], toggles[0], toggles[1]})
    close(descriptor);
}
int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc != 2 && argc != 3) return 2;
    const std::string name(argv[1]);
    const bool vectors = name == "notification_modes" || name == "notification_controls";
    if (argc != (vectors ? 3 : 2)) return 2;
    if (name == "permissions") permissions();
    else if (name == "invalid_options") invalid_options();
    else if (name == "discovery") discovery();
    else if (name == "discovery_refusal") discovery_refusal();
    else if (name == "discovery_capacity") discovery_capacity();
    else if (name == "missing_and_expired") missing_and_expired();
    else if (name == "modes") modes();
    else if (name == "operation_refusal") operation_refusal();
    else if (name == "submission_boundary") submission_boundary();
    else if (name == "read_callbacks") read_callbacks();
    else if (name == "released_objects") released_objects();
    else if (name == "callback_identity") callback_identity();
    else if (name == "continuity_loss") continuity_loss();
    else if (name == "cleanup_fault") cleanup_fault();
    else if (name == "independent") independent();
    else if (name == "notification_modes") notification_modes(notification_vectors(argv[2]));
    else if (name == "notification_controls") notification_controls(notification_vectors(argv[2]));
    else if (name == "notification_values") notification_values();
    else if (name == "notification_credit") notification_credit();
    else if (name == "notification_capacity") notification_capacity();
    else if (name == "notification_faults") notification_faults();
    else if (name == "notification_deadlines") notification_deadlines();
    else if (name == "notification_aliases") notification_aliases();
    else if (name == "notification_host_join") notification_host_join();
    else if (name == "power_registration") power_registration();
    else if (name == "power_messages") power_messages();
    else if (name == "power_operations") power_operations();
    else if (name == "power_notifications") power_notifications();
    else if (name == "power_cleanup") power_cleanup();
    else if (name == "power_independent") power_independent();
    else if (name == "power_host_join") notification_host_join(true);
    else if (name == "unfinished_destruction") {
      std::set_terminate([] { _exit(73); });
      Fixture f;
      f.ready();
      f.sdk.reset();
      std::abort();
    } else return 2;
    std::cout << "ok " << name << '\n';
  }
}
