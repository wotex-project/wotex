// SPDX-License-Identifier: Apache-2.0
#include "../../priv/corebluetooth/native/sdk_environment.hpp"
#include <atomic>
#include <cstdlib>
#include <iostream>
#include <sys/wait.h>
#include <unistd.h>

using namespace wotex::ble::corebluetooth;
static void check(bool value) {
  if (!value) std::abort();
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
    }});
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
    check(output.opens == std::vector<Code>{Code::ok} && output.routes.size() == 1);
  }
  void ready() {
    begin();
    connect();
    discover();
  }
  void close() {
    sdk->close(clock.sample());
    check(sdk->closed());
    check(!central.delegate && !peripheral.delegate && central.cancels == 1);
    sdk->close(clock.sample());
    check(central.cancels == 1);
  }
  ~Fixture() {
    if (!sdk->closed()) sdk->close(clock.sample());
  }
};
static void permissions() {
  for (const auto auth : {CBManagerAuthorizationNotDetermined, CBManagerAuthorizationDenied,
                          CBManagerAuthorizationRestricted}) {
    Fixture f;
    f.auth = auth;
    check(f.sdk->open(f.config(), 100, 200) == Code::ok && f.constructions == 0);
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
    f->ready();
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
int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc != 2) return 2;
    const std::string name(argv[1]);
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
