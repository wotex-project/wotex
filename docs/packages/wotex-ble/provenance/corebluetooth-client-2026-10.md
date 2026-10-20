# CoreBluetooth public Client evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source commit: `dae4962a4c0f90c560186df95b62cea56ace061d` (Client milestone
`ff42fa9533488f81d53e467443ae0220e2cd1d58` plus joined verification-worker cleanup).
Owner: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.6.0
and its [CoreBluetooth Client entry](../specs/WBL.08-corebluetooth-host-v1.md)
version 0.4.0. This record covers software point operations and ownership.

## Executed boundaries

Thirteen public Client cases run through real pipes and the pinned runtime
guardian. A separate C++ process peer imports no production framing, validation
or lifecycle implementation. Its literal replies and deliberate faults check
exact mode/bytes/routes, duplicate UUID selection, immutable discovery,
unsupported properties, missing/duplicate/foreign submission markers, a command
answered as an acknowledged write, explicit unsent refusal, submitted refusal
and abrupt native loss. The facade retains typed read results, acknowledged
writes and exact command queue evidence without fallback or replay.

Lifecycle cases cover one active plus 63 queued calls, refusal of a further
call, queued expiry and caller loss without dispatch, active expiry/caller loss,
configured-owner exit, independent instances, stale handles, linked startup,
late replies, startup faults, cleanup refusal and an unresponsive closing peer.
An abrupt connection-process kill preserves write uncertainty while the
independent guardian reaps the native child. Tests inspect actual child liveness,
not just a closed BEAM handle. Status inspection omits private routing identity
and artifact paths.

A separate case uses the production native Host framing, deadline, output and
retirement loop with its independent Driver, validates all 256 discovered
routes, then performs a read and both write modes through the public facade.
This joins the Client to the production protocol loop without a real SDK
peripheral. Public ConsumedThing operations additionally check typed reads,
acknowledged writes, command `:accepted` results, exact target binding, security
and unsupported-profile refusal, original deadlines and connection cleanup.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, using the installed C/C++ compiler and LLVM 23.1.3 clang tools.

```text
mix pkg wotex-ble test test/wotex/ble/corebluetooth_client_test.exs test/wotex/ble/identity_value_test.exs test/wotex/ble/mapping_test.exs test/wotex/ble/write_mode_test.exs
mix pkg wotex-ble test test/wotex/ble/corebluetooth_client_test.exs test/wotex/ble/procedure_test.exs test/wotex/ble/bluez_test.exs test/wotex/ble/port_test.exs test/wotex/ble/runtime_integration_test.exs
MIX_ENV=test mix pkg wotex-ble format
mix native.lint --package wotex-ble --fix
mix check.fast --package wotex-ble
clang-tidy packages/wotex-ble/test/native/corebluetooth_client_peer.cpp -- -std=c++17
mix wotex.boundary --package wotex-ble
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs
mix test test/wotex/workspace/native_suite_test.exs test/wotex/workspace/native_check_test.exs test/wotex/workspace/catalogue_test.exs
mix affected --base 8dd29a5101c60add5c618cd9fa8de8814aa45607 --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The focused runs passed 44 and 34 cases while building. After the final
discovery and worker-retirement corrections, the owning fast gate passes 365 cases: nine
doctests, seventeen properties and 339 tests, with 58 explicit-lane exclusions.
Strict Credo, native formatting and package boundaries pass. Clang-tidy reports
no first-party finding; its suppressed diagnostics are from non-user code and
the existing header allowances. The 23 focused root tooling tests pass.
Markdown links, catalogue generation and ExDoc pass.

The archive check clears the sibling switch for Hex assembly, verifies exact
members/source bytes and compiles extracted source out of tree. Its SHA-256 is
`a4fcaa34ed2eb8dbfa631105026231c1d14a8153ee7f338934cea18751fa91ab`;
package lock SHA-256 is
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.
The existing warning about the optional write-mode consumer module remains;
that optional lane was not executed. Extracted compilation does not establish
independent CoreBluetooth archive runtime interoperability.

The native compile-list addition marks all packages affected. Checks remain
bounded to BLE and the owning root tooling; no family-wide application gate
ran. Full gates, Dialyzer, coverage, dependency audits, Linux native/software
lanes, renewed SDK sanitizer/build lanes, independent CoreBluetooth archive
consumers and installed permission/peripheral/physical qualification were not
run. Test workspaces clean up on exit. All three retained ordinary archive cohorts
were removed only after checking their exact file lists and archive digests;
normal tooling caches remain reusable.

## Exact inputs

Paths are relative to `packages/wotex-ble`. The source commit also fixes facade,
Address, BlueZ refusal, Procedure, Mapping, consumer guidance and native metadata.

| File | SHA-256 |
| --- | --- |
| `lib/wotex/ble/core_bluetooth.ex` | `7d6238a4628711c44940a216767e6a489b743e1178363e2f7221209b21616b09` |
| `lib/wotex/ble/core_bluetooth/peer.ex` | `cc81b13522c7345cf836e3b748adfb79c136bf75973d873d5808532596d86dd3` |
| `lib/wotex/ble/core_bluetooth/options.ex` | `4aeddea1d9553748d3d36e36006d3efe298935efe63d011460bc8020bc129dd2` |
| `lib/wotex/ble/core_bluetooth/characteristic.ex` | `1e4764516dd44ab7874490fd28484f5de66ceb1b98742a51f85e614d766e2056` |
| `lib/wotex/ble/core_bluetooth/response.ex` | `954fb5ec37e72ef65f0a3fe09b16339e9b448686b4571d0281fa6af5b6c4bb0e` |
| `lib/wotex/ble/core_bluetooth/connection.ex` | `86206839aa915cb1c7ba58f9b9431708e06cc269b9dc8076eaa2fb84897e016f` |
| `test/native/corebluetooth_client_peer.cpp` | `05295af2644b8d49bcf9000fb8a829ad34c406ffcb73db49c703ae86db22b278` |
| `test/wotex/ble/corebluetooth_client_test.exs` | `896036115f2a54c1889d8ac8e5f4249cd8449261eca8d4cda23c05a9069e39cf` |
| `priv/bluez/native/custody.c` | `d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2` |

Notifications, explicit sleep observation, installed Mac/controller qualification
and independent CoreBluetooth archive consumers remain open. WBL.08 stays
partial. None of these software outcomes grants consumer authority or proves a
physical effect.
