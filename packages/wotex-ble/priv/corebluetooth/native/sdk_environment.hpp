// SPDX-License-Identifier: Apache-2.0
#pragma once
#import <CoreBluetooth/CoreBluetooth.h>
#include <functional>
#include "sdk.hpp"

namespace wotex::ble::corebluetooth {
// Internal SDK construction seam. Normal execution uses CBManager authorization
// and CBCentralManager directly; tests supply NSObject selector implementations.
struct SDKEnvironment {
  std::function<CBManagerAuthorization()> authorization;
  std::function<CBCentralManager *(id<CBCentralManagerDelegate>, dispatch_queue_t)> central;
};
} // namespace wotex::ble::corebluetooth
