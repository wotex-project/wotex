# CoreBluetooth SDK notification evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source commit: `4e9e009a420b0de1e7642967eecab28c4f5eaeab`.
Owners: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.7.0,
its [native notification contract](../specs/WBL.08-corebluetooth-host-v1.md)
version 0.5.0 and [completion contract](../plans/wotex-ble-completion.md) version
1.7.0. This milestone implements the SDK ownership seam. Notification IPC,
public Client/Runtime delivery and sleep observation remain open.

## Executed boundary

The real Objective-C++ SDK boundary calls the actual CoreBluetooth selectors
against independently supplied NSObject implementations. It constructs no real
central manager and requests no Bluetooth permission or peripheral operation.
The SDK's existing fifteen behavioral cases and unfinished-lifetime case are
joined by eight notification families, for 24 SDK cases in total.

The fixture consumes all twelve literal property/mode cells and six state/error
cells from `priv/fixtures/corebluetooth-notifications-v1.json`. These outcomes
are supplied independently of the implementation's selection predicates. The
mode policy follows the installed SDK header and
[Apple's setNotifyValue contract](https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:)):
both advertised properties select notifications, and forcing indications in that
cell refuses before the SDK toggle.

Cases exercise exact start/stop characteristic identity, deferred establishment,
early/equal/empty/512-byte values, explicit over-bound refusal, owned byte copies,
one control deadline, sixteen live streams and 64 shared credits. Future,
regressing, duplicate and foreign acknowledgement cannot create extra credit;
stopping a stream retains its published unacknowledged credit. Reusing a retired
route refuses within the same generation. Value and state errors, changed
association/properties, sink refusal, credit exhaustion, deadline equality,
backward clock, permission/adapter loss and SDK exceptions retire the owner.

Point reads on a stream route refuse; another route's read and an acknowledged
write retain their own callback/result path while stream values arrive. Foreign
and detached old delegates cannot settle another owner. Weak references verify
that active-stream teardown releases the actual SDK objects. Pending control
failure is observed only after delegate detachment; confirmed and exception-
affected cleanup remain distinct. Sequence-exhaustion refusal is implemented;
no practical uint64-exhaustion workload is claimed.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple SDK 27.0 and LLVM 23.1.3 clang tools. The macOS 14 deployment
target is a compiler setting, not runtime qualification on macOS 14.

```text
mix pkg wotex-ble test test/wotex/ble/corebluetooth_sdk_test.exs
mix pkg wotex-ble test test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_build_test.exs test/wotex/ble/corebluetooth_host_test.exs test/wotex/ble/corebluetooth_client_test.exs
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_host_test.exs
mix native.lint --package wotex-ble --fix
MIX_ENV=test mix pkg wotex-ble format
mix check.fast --package wotex-ble
mix wotex.native.suite --package wotex-ble --suite corebluetooth --tidy
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs
mix test test/wotex/workspace/catalogue_test.exs
mix affected --base 136edb0d --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The SDK run passes 24 cases. The focused SDK/build/Host/Client run passes 50,
including three actual offline macOS build/reuse/tamper cases. The final
ASan/UBSan run passes all 48 component cases: fourteen operations, 24 SDK and ten
Host cases, with the existing leak-scanning policy unchanged. The fast gate
passes 373 cases: nine doctests, seventeen properties and 347 tests, with 58
explicit-lane exclusions. Strict Credo and native formatting pass. All three
selected native translation units have clean clang-tidy inputs; one localized
test suppression documents the deliberate unnamed enum value used to test
closed-input refusal. The final SDK fixture is rerun after that annotation.
Six focused catalogue tests, catalogue generation, Markdown links and ExDoc pass.

The archive check verifies exact members and source bytes, including the new
literal corpus, then compiles extracted Elixir source out of tree. Archive
SHA-256 is `bca601bd0a66594fe9acbbb8664c51575c17f6ffed38c053e86b82c4fb9251d7`;
package lock SHA-256 is
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.
The existing optional write-mode consumer-module warning remains; that optional
lane was not executed. No extracted native notification consumer is claimed.
The retained ordinary archive was removed after exact file-list and digest
verification; test workspaces clean up on exit and normal tooling caches remain.

The affected set is BLE only. Full gates, Dialyzer, coverage, dependency audits,
Linux native/software lanes, leak-audit mode, installed permissions/peripherals,
physical RF and independent notification IPC/archive consumers were not run.
WBL.08 remains partial. Neither an SDK callback nor accepted bytes establish
canonical Property truth, authority or a physical effect.

## Exact inputs

Paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `priv/corebluetooth/native/sdk.cpp` | `7f9a9ffda20333191a8a65d021b876903420f5f68ce4a8c981102f99affd7e2e` |
| `priv/corebluetooth/native/sdk.hpp` | `38ce41ac6fe14aa46c4d1c07081a738ab3d97327f18a4e7547f67366e2631e5e` |
| `priv/fixtures/corebluetooth-notifications-v1.json` | `37445565178e76cf9e739cc8cb3d6fd0130dfad9014801bae2e3bce636b5f247` |
| `test/native/corebluetooth_sdk_test.cpp` | `23253b654be03da18dce8323d95f55c5bea75ab49ec59e37fdbb71607d977051` |
| `test/wotex/ble/corebluetooth_sdk_test.exs` | `b01b23f6dd7cb4fa9466968dbfa4bd247075da947ca083f4d49a194db039d341` |
| `bin/check_archive.exs` | `25ff43f2d07b1d95309ff701c3666d1a3df55cf8726908c19004d969b65f1d52` |
