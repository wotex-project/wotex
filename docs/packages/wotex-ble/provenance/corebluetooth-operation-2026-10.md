# CoreBluetooth native operation evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source parent: `e8e58cdd4345d0187c07c74c507115e6de18626d`. The dirty source
identities below bind the operation and corpus before their owning commit.
Owner: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.3.0
and [CB-OP1–CB-OP5](../specs/WBL.08-corebluetooth-host-v1.md).

The component receives explicit time, immutable route/ticket inputs, a scripted
SDK port and a result sink. It performs no I/O and instantiates no manager.
The test port records exact bytes/mode/order and controls authorization, route,
readiness, per-mode length, submission and retirement independently of the
component. No fixture calls a production validator to construct its expected
result. This establishes operation behavior under those supplied facts, not
the truth of any real SDK or installed-host fact.

## Commands and observations

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple clang 21.0.0 and LLVM clang-tidy/clang-format 23.1.3:

```text
mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs
clang-tidy packages/wotex-ble/test/native/corebluetooth_operation_test.cpp -- -std=c++17
mix check.fast --package wotex-ble
mix test test/wotex/workspace/native_suite_test.exs test/wotex/workspace/native_files_test.exs test/wotex/workspace/native_tidy_test.exs
mix native.lint --package wotex-ble --fix
mix wotex.boundary --package wotex-ble
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
mix workspace
```

All fourteen operation cases pass in ordinary and ASan/UBSan builds. They
exercise exact read/request/command evidence, empty/512-byte and SDK bounds,
invalid starts/properties, refused markers, readiness without submission,
changing facts, deadline equality, foreign/malformed/late callbacks, submitted
uncertainty, original 500 ms retirement, clock regression, separate owners and
unfinished destruction in a child process. No case uses a clock sleep.

The fast gate passes 323 cases (nine doctests, seventeen properties and 297
tests), with 58 explicit-lane cases excluded. After its run, fixture allocation
failure handlers and exhaustive switch defaults were added to satisfy tidy;
both fourteen-case native lanes were rerun successfully against the exact
identities below. Clang-tidy reports no first-party findings; changed native
formatting, BLE boundary checks and docs pass. The focused root run passes
thirteen tests. The manifest change registers only the new portable test unit.

`mix workspace` passes root compilation, formatting, strict Credo, all 435 root
tests (one explicit exclusion), catalogue and Markdown links. Its family-wide
boundary phase fails because other package checkouts lack their dependencies.
The prepared BLE package's separate boundary check passes. Dependencies were
not installed across unrelated packages to complete that phase.

The full package gate, coverage, Dialyzer, Linux libdbus/native suite, real
CoreBluetooth/permission/peripheral operation, installed lifecycle, archive
consumers and physical qualification were not run for this component. No public
Elixir function or inferred return changed. Sanitizers disable leak scanning
under the existing component-lane policy. The test runner removes its owned
temporary executables and directories on exit.

## Exact source identities

Paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `priv/corebluetooth/native/operation.hpp` | `3e58bc659b21807ae7919e8c0ce50b514ad8b694ad437a0254ca5d8bca314c2e` |
| `test/native/corebluetooth_operation_test.cpp` | `8cb64b7bf05aec4e480d1a75ac6bba9568a023f62846b6de64cd4cdf4f358c2f` |
| `test/wotex/ble/corebluetooth_operation_test.exs` | `4db013377c8469010c15c2f9907e23298023591f0bd1c9d647a55a69665cd70b` |

The SDK adapter, explicit host/build, public Client, discovery/notifications,
sleep/reset/permission handling and Runtime/archive joins remain required by
WBL.08. A passing scripted operation is not a working macOS backend.
