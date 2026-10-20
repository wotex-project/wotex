# CoreBluetooth system-power evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source commit: `fc997cb39158b0ada517bb87e9a714991aede69d`.
Owners: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.10.0,
its [system-power contract](../specs/WBL.08-corebluetooth-host-v1.md) version
0.8.0 and [completion contract](../plans/wotex-ble-completion.md) version 1.10.0.
This milestone implements an owned IOKit observer and SDK/Host retirement on
observed sleep or wake. Installed sleep/wake qualification remains open.

## Executed boundary

The SDK corpus has 32 cases, including seven power families. Explicit functions
with the actual IOKit C signatures supply registration, queue selection,
acknowledgement, deregistration, port destruction and connection close. These
fixtures create no real manager or system-power observer and trigger no system
sleep/wake. The existing framework-selector fixtures remain independent of real
Bluetooth permission, peripheral and radio state.

Cases verify passive and denied startup, all four partial-registration shapes,
and post-registration expiry, clock regression and changed permission before
manager construction. Queries are allowed without veto; will-not-sleep and
unrelated messages receive no acknowledgement. Sleep preserves its exact opaque
notification ID; either wake callback ends continuity without acknowledgement.
Late callbacks cannot reopen the stopped source or another independent owner.

Sleep during read, acknowledged write or command-readiness wait preserves the
submitted/unsent distinction and prevents a late delegate from sending work.
Wake during notification start, active delivery or stop retires ownership before
pending control failure. Acknowledgement, deregistration, port destruction and
connection-close faults preserve fixed errors and confirmed/unconfirmed cleanup.
Cleanup is attempted once in order and continues after earlier failure.

A production SDKDriver/Host case uses real pipes, a live stream and a submitted
write. A supplied sleep callback produces a conservative disconnected write
failure with submitted=true, then connection_lost after driver retirement and
destruction. The ordinary notification Host join still completes its write and
stream stop successfully. No callback or process result proves a physical effect.

The installed SDK 27.0 headers define the message/cleanup signatures. Source
review of [IOKitUser at 323ead896d04424f87184d8f6ff0cce811aab106](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/IOKitLib.c)
informed dispatch cancellation and retained notification-port lifetime. This is
review evidence, not execution evidence for the installed IOKit implementation.
No upstream implementation text was imported.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple SDK 27.0 and LLVM 23.1.3 clang tools. The macOS 14 deployment
target is a compiler setting, not runtime qualification on macOS 14.

```text
mix pkg wotex-ble test test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_build_test.exs test/wotex/ble/corebluetooth_client_test.exs
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_host_test.exs
mix native.lint --package wotex-ble --fix
MIX_ENV=test mix pkg wotex-ble format
mix wotex.native.suite --package wotex-ble --suite corebluetooth --tidy
mix check.fast --package wotex-ble
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs
mix test test/wotex/workspace/catalogue_test.exs
mix affected --base 82f8f483 --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The final focused SDK/build/Client run passes 62 cases: 32 SDK, three build and
27 public Client cases. ASan/UBSan passes 71 native cases: fourteen operations,
32 SDK and 25 Host cases. The fast gate passes 415 cases: nine doctests,
seventeen properties and 389 tests, with 58 explicit-lane exclusions. Strict
Credo and native formatting pass. All three selected native translation units
pass clang-tidy. Six catalogue tests, catalogue generation, Markdown links and
ExDoc pass.

The offline build executes actual compilation/linkage, passive startup, reuse
and tamper refusal. Assertions verify IOKit linkage, selected API-header identity
and system_power_observation=iokit build features. The ordinary archive check
verifies exact members/source bytes, including power.hpp, then compiles extracted
Elixir source out of tree. Archive SHA-256 is
`6874d2507b504f1c0258e3121a8d87e986c2904e3175b26a65222269bd968ae4`;
package lock SHA-256 is
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.
The existing optional write-mode consumer-module warning remains; that optional
lane was not executed. The retained ordinary archive was removed after exact
file-list and digest verification; test workspaces clean up on exit.

The affected set is BLE only. Full gates, Dialyzer, coverage, dependency audits,
Linux native/software lanes, leak-audit mode, independent CoreBluetooth archive
consumers, real power registration and installed permission/peripheral tests
were not run. These results establish no actual sleep/wake, permission, pairing,
peripheral connection, RF or physical-effect result. WBL.08 remains partial.

## Exact inputs

Package paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `priv/corebluetooth/native/power.hpp` | `925aa385b95980b7f6661c316d49974cb2a6e394273694020dc7716f9be04142` |
| `priv/corebluetooth/native/sdk.cpp` | `0cdc5b8885dc2631c25f8928b0dfdffecbdbf2bb80cc3912c39667812240e612` |
| `priv/corebluetooth/native/sdk_environment.hpp` | `19a29ff49f8a8b241d335ad9c4735bf84e3f45fc052456d3e0a4aa864c723827` |
| `lib/wotex/ble/core_bluetooth/build.ex` | `2f1af6586d2c0cb4515fdad6485f1d91e356adf2ba249968910b290c2a7cb2fc` |
| `test/native/corebluetooth_sdk_test.cpp` | `de6b27c11c68cc9930034bdbfb8d96541e1113d1507c440e015e982853f6d5a9` |
| `test/wotex/ble/corebluetooth_sdk_test.exs` | `1023255018a50cb5cad00c0953088ef1bb1bee77e510a21069cfffe3e30e5fc6` |
| `test/wotex/ble/corebluetooth_build_test.exs` | `5c99e11d0e58e0c7e5d4099f9ee4b973163886550985c0baa18bde310ab01185` |
| `bin/check_archive.exs` | `71ba6a85fe5fe578d629b15b0103ab6b3abfcd6ec601223ade1fefbab1969c91` |

Selected header paths are relative to the installed Apple SDK.

| Header | SHA-256 |
| --- | --- |
| `System/Library/Frameworks/IOKit.framework/Headers/IOKitLib.h` | `553869588e8c0b162b232e294dea2579cfd739d83e772a0b8a79e2be91a5816e` |
| `System/Library/Frameworks/IOKit.framework/Headers/IOMessage.h` | `e09e00c2607119880171250e57596aa5effa39b455d74d25dc67b12b27a31350` |
| `System/Library/Frameworks/IOKit.framework/Headers/pwr_mgt/IOPMLib.h` | `9c6b97c780b655c93db5a2b7c787fda8a49e3289fea178cd2856c7802556945a` |
