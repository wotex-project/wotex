# CoreBluetooth SDK owner evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source parent: `0be5dcda43810ca27ceff154884d8219fb309613`. The exact dirty-input
identities below bind the SDK owner and renewed operation component before
their owning commit. Owner: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md)
version 0.4.0 and the [SDK entry](../specs/WBL.08-corebluetooth-host-v1.md)
version 0.2.0.

## Executed scope

The Objective-C++ owner compiles and links the actual Foundation/CoreBluetooth
interfaces. Its injected factory returns separately implemented NSObject SDK
selector objects, not a real CBCentralManager. Tests control authorization,
connection/discovery facts and delegate delivery, then inspect exact selectors,
NSData bytes, modes, results and released weak references. No test opens a
Bluetooth manager, prompts, scans, connects or sends radio traffic.

Sixteen SDK cases join fourteen portable operation cases. Ordinary and
ASan/UBSan runs pass all thirty. SDK cases cover default/explicit permission
entry, malformed startup, exact selected identifier, missing peripheral,
complete duplicate-UUID discovery, exact 64-service/256-characteristic capacity,
one-over and association refusals, three procedure modes, original opening and
operation deadlines, current command readiness, notifying-read refusal, empty/
oversized/error values, old delegates, continuity loss, cleanup exceptions,
separate owners and unfinished destruction. Weak references establish that
retirement actually releases the injected central, peripheral, service and
characteristic objects after external references are removed.

Marker hooks independently change time, authorization and maximum write length
between the marker and the SDK call. All four variants refuse before an SDK
write and preserve conservative submission classification. The SDK submission
also returns an elapsed observation; the operation rejects expired/regressed
observations before queue success. This record does not qualify a real clock.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple SDK 27.0, Apple clang 21.0.0 and LLVM 23.1.3. Objective-C++
arguments select ARC and a macOS 14 minimum deployment target; no macOS 14 runtime
result is claimed.

```text
mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs test/wotex/ble/corebluetooth_sdk_test.exs
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs test/wotex/ble/corebluetooth_sdk_test.exs
mix wotex.native.suite --package wotex-ble --suite corebluetooth --tidy
mix wotex.native.suite --package wotex-ble --suite corebluetooth --test
mix check.fast --package wotex-ble
mix compile --warnings-as-errors
mix credo --strict
mix test
mix wotex.boundary --package wotex-ble
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The final package fast gate passes 339 cases (nine doctests, seventeen properties
and 313 tests), with 58 explicit-lane exclusions. Both native lanes pass thirty
cases; sanitizer leak scanning follows the existing disabled component-lane
policy. The explicit native suite runs its two SDK translation units through
clang-tidy without first-party findings. An earlier direct clang-tidy run also
checks the portable operation test. Final native formatting, strict Credo,
BLE boundary checks, catalogue, Markdown links and ExDoc pass.

The root host-selection changes pass compilation, strict Credo and 437 tests,
with one unrelated explicit exclusion. Tests select Darwin/Linux identities
and prove an out-of-scope suite performs no build, preparation, flag lookup,
analysis or tests. Only its explicit units are exempt from current-host compile
coverage; an undeclared unit still fails. A non-applicable result records no
analysed paths or qualification. The SDK suite declares `hosts: [darwin]` and
was executed on Darwin. No Linux execution of this SDK source is claimed.

The explicit native test suite preceded the final single-value NSData retention
and temporary-name PID adjustment. The final ordinary fast and sanitizer runs
execute all thirty cases against the exact inputs below; clang-tidy is renewed
against the final SDK source. Harness directories/binaries are removed on exit;
normal tooling analysis caches remain reusable.

The full package gate, Dialyzer, coverage, dependency audits, Linux libdbus/native
suite, archive consumers and installed/physical qualification were not run.
No public Elixir behavior or return type changed. Root tooling changed bounded
suite metadata and host selection; package gates across the family were not
run for that tooling change.

## Exact inputs

Paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `priv/corebluetooth/native/operation.hpp` | `07870d7fb91276e36e76b8ea91290a36b206745c07ae31de4af2ff31e80c4467` |
| `priv/corebluetooth/native/sdk.cpp` | `63505c7dab33a91e49bd2ac1a4d50f41808fd41e16464a3fc099f494acb867d7` |
| `priv/corebluetooth/native/sdk.hpp` | `1bc6661555d9105406aec0300e80be94f795786ac8dc2f826f04d30abfda3ab6` |
| `priv/corebluetooth/native/sdk_environment.hpp` | `0ec32126569c575addf282d6bc2183aa97bff80c7952faf9971d0566476fecb6` |
| `test/native/corebluetooth_sdk_test.cpp` | `df94b3c3a6ae60e493fbf5d6c222f7d1288e6882b9172787776520b42e5377ec` |
| `test/native/corebluetooth_operation_test.cpp` | `48c299825e482c383e3b9974f90155a32ab0527301ac97c3eff0a580c9dbdca0` |
| `test/wotex/ble/corebluetooth_sdk_test.exs` | `73a70ac51c6586344263d4dd3bc15d843a28f8c86a24d397e923af677792dd93` |
| `test/wotex/ble/corebluetooth_operation_test.exs` | `b8d608ae4999e89eebc7c130cd51a510682117d7a86cd9fff4152b8fdcfd2194` |

## Remaining host delivery

These internal SDK sources are not yet selected by a shipped build task or
public Client. The native process, immutable build/artifact admission, usage
description metadata, public private-route values, notification receiving,
sleep handling, Runtime/archive joins and installed permission/peripheral
qualification remain required. Existing BlueZ evidence cannot qualify these
Mac cells. The SDK owner is not an end-to-end macOS backend.
