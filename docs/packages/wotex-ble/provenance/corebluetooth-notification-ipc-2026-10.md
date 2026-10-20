# CoreBluetooth native notification IPC evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source commit: `c97fbd0500d311ea7c9baac7ef1a5c8da778bea7`.
Owners: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.8.0,
its [CoreBluetooth contract](../specs/WBL.08-corebluetooth-host-v1.md) version
0.6.0 and [completion contract](../plans/wotex-ble-completion.md) version 1.8.0.
This record covers native stream IPC. Public Client/Runtime receiving and sleep
observation remain open.

## Executed boundary

Twenty-five independent Driver-process cases traverse the production Host
framing/output loop. Literal wire and mode corpora exercise closed subscription,
binding, report, acknowledgement and retirement frames, all twelve property/mode
cells and malformed control parameters. Empty/equal updates remain separate.
Future, regressing, foreign, duplicate-key, noncanonical and unsent-record
acknowledgements cannot fabricate credit. Stopped outstanding records retain
their share of the 64-credit budget; sixteen live streams are bounded separately.

Fault cases include early, foreign, gapped, oversized and over-credit Driver
reports, control expiry, cleanup refusal, busy control admission and active
point-operation closure. A late native write success during close becomes a
conservative failure with its submission phase retained. Missing-marker faults
cannot create a false known-unsent write receipt. Concurrent 512-byte reports
and a completely filled, unread stdout pipe exercise callback admission,
transmission-bound acknowledgement and bounded process retirement. Invalid
cleanup-clock arithmetic cannot overflow or extend output draining.

The SDK corpus has 25 cases, including a production `SDKDriver`/Host case using
actual Objective-C++ framework selectors against injected NSObject objects and
real pipes. It traverses establishment, report delivery, cumulative credit,
an acknowledged write alongside the live stream, empty/equal updates, stop,
retirement and joined object cleanup. No real central manager is constructed.
Callbacks enter a fixed 80-entry inbox without the output mutex; a one-use
atomic gate admits the exact write marker before SDK handoff.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple SDK 27.0 and LLVM 23.1.3 clang tools. The macOS 14 deployment
target is a compiler setting, not runtime qualification on macOS 14.

```text
mix pkg wotex-ble test test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_host_test.exs test/wotex/ble/corebluetooth_client_test.exs
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_host_test.exs
mix native.lint --package wotex-ble --fix
MIX_ENV=test mix pkg wotex-ble format
mix check.fast --package wotex-ble
mix wotex.native.suite --package wotex-ble --suite corebluetooth --tidy
clang-tidy packages/wotex-ble/test/native/corebluetooth_host_peer.cpp -- -std=c++17
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs
mix test test/wotex/workspace/catalogue_test.exs
mix affected --base b0327879 --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The focused SDK/Host/Client run passes 63 cases. The ASan/UBSan run passes all
64 component cases: fourteen operations, 25 SDK and 25 Host cases. The fast gate
passes 389 cases: nine doctests, seventeen properties and 363 tests, with 58
explicit-lane exclusions. It includes three actual offline macOS build, reuse
and artifact-tamper cases. Strict Credo and native formatting pass. All three
selected native translation units and the independent Driver peer pass
clang-tidy. Six catalogue tests, catalogue generation, Markdown links and ExDoc
pass.

The ordinary archive check verifies exact members and source bytes, including
the new adapter header and literal wire corpus, then compiles extracted Elixir
source out of tree. Archive SHA-256 is
`4c7a453f5ed8d39ef4e722639c1b68496a5287fd1d846e2c546de9e8ec97a58f`;
package lock SHA-256 is
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.
The existing optional write-mode consumer-module warning remains; that optional
lane was not executed. The retained archive was removed after exact file-list
and digest verification; ordinary test workspaces clean up on exit.

The affected set is BLE only. Full gates, Dialyzer, coverage, dependency audits,
Linux native/software lanes, leak-audit mode, public notification receiving,
independent CoreBluetooth archive consumers and installed Mac/controller tests
were not run. No actual authorization, peripheral connection, pairing, RF or
physical-effect result is established. WBL.08 remains partial.

## Exact inputs

Paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `priv/corebluetooth/native/host.hpp` | `d700270ca0222935ac8f78edd7ab3cc972de180779dd3af9e9d8d74655e4e45b` |
| `priv/corebluetooth/native/driver.hpp` | `6809f86a8d48cf7f542596a7ee8e2e74ff327c7fd7aab2282df300e55d6914a1` |
| `priv/corebluetooth/native/main.cpp` | `f65b6421a68ae1e5825f6b6117d36a0b18b9516ea8fd0a927f66498f9e17a356` |
| `priv/corebluetooth/native/sdk.cpp` | `7f9a9ffda20333191a8a65d021b876903420f5f68ce4a8c981102f99affd7e2e` |
| `priv/corebluetooth/native/sdk.hpp` | `38ce41ac6fe14aa46c4d1c07081a738ab3d97327f18a4e7547f67366e2631e5e` |
| `priv/fixtures/corebluetooth-notification-wire-v1.json` | `f4bf9734b60e86e41bc72ef25c1a0b8f51cc03eb43c6d0532e69435d76bc4654` |
| `priv/fixtures/corebluetooth-notifications-v1.json` | `37445565178e76cf9e739cc8cb3d6fd0130dfad9014801bae2e3bce636b5f247` |
| `test/native/corebluetooth_host_peer.cpp` | `a97c143b06e5973400516f71a7e77acb5dce9158c969fe445eb74dbb687b38dd` |
| `test/native/corebluetooth_sdk_test.cpp` | `8887e4ed1ae1c86029fae7014e59bbafbfe33d3b4e1d66d91fe0dadf7be2a48f` |
| `test/wotex/ble/corebluetooth_host_test.exs` | `abeeeb043a4e4fe7377675fed78f0ae0fbf73cb6f3c711740d9a80eaf06ff589` |
| `test/wotex/ble/corebluetooth_sdk_test.exs` | `56204ca21d216c06898fa94c12f7b3c2ee7698c0a7f5f91a1759931ff8e261b9` |
| `bin/check_archive.exs` | `ac34832acb57981f1c14afe762fcb424103ca7a07a509d20d23d7c7dd873cb01` |
