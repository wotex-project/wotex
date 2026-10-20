# CoreBluetooth public notification receiving evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source commit: `5498ee6a9518fbc80a813cf34c4325857d41952d`.
Owners: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md) version 0.9.0,
its [public receiving contract](../specs/WBL.08-corebluetooth-host-v1.md) version
0.7.0 and [completion contract](../plans/wotex-ble-completion.md) version 1.9.0.
This milestone joins native notification IPC to the public Client and Runtime.
Sleep observation, independent CoreBluetooth archive consumers and installed
Mac/controller qualification remain open.

## Executed boundary

The Client corpus now has 27 process/facade/Runtime cases, including the original
thirteen point cases. Its independent C++ process peer imports no production
framing or connection implementation. New stream cases exercise exact native
binding, equal updates and typed codecs, original generation, forged handles,
malformed/early/foreign/gapped/oversized reports, missing or changed retirement,
control timeout, receiver loss/overflow and actual process retirement.

The public handle handoff keeps reports within native credit until the caller
consumes its opening reply. A one-frame receiver case verifies that the reply
does not count as an outstanding report. Queued expiry and queued caller death
release unsent custody without interrupting an unrelated submitted write.
Cancellation during an active submitted write instead closes the generation and
preserves unknown effect. A killed delivery owner cannot establish cleanup by
its own death: cancellation joins the native process before success. Exact
retired handles preserve idempotence and reject forged references.

Sixteen independent public streams reserve four credits each; the next refuses
until a stream retires. A separate case traverses the production Host loop with
concurrent 512-byte reports, a live public receiver and a point write. Real
Runtime Property and Event streams preserve CoreBluetooth metadata and uint16
decoding, then close their private sessions. Runtime-owner loss during pending
native establishment also closes the process.

Five pure stream/ledger cases consume all twelve independent literal mode cells,
check per-stream consumed prefixes, reject wrong owners/private tokens and
malformed frames, retain used routes and distinguish sixteen live streams from
64 shared credits. Runtime metadata checks refuse a changed backend/mode or
extra fields and ignore a well-formed foreign native route. These checks use
the actual public Form constructor and mapping.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple SDK 27.0 and LLVM 23.1.3 clang tools.

```text
mix pkg wotex-ble test test/wotex/ble/report_flow_test.exs test/wotex/ble/corebluetooth_stream_test.exs test/wotex/ble/corebluetooth_client_test.exs
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_host_test.exs
mix native.lint --package wotex-ble --fix
MIX_ENV=test mix pkg wotex-ble format
mix check.fast --package wotex-ble
clang-tidy packages/wotex-ble/test/native/corebluetooth_client_peer.cpp -- -std=c++17
clang-tidy packages/wotex-ble/test/native/corebluetooth_host_peer.cpp -- -std=c++17
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs
mix test test/wotex/workspace/catalogue_test.exs
mix affected --base 0391a250 --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The final focused run passes 37 cases: 27 Client, five CoreBluetooth stream and
five existing BlueZ report-flow cases. The final fast gate passes 408 cases:
nine doctests, seventeen properties and 382 tests, with 58 explicit-lane
exclusions. It includes the existing BlueZ stream/Runtime suites and three
offline macOS build/reuse/tamper cases. Strict Credo and native formatting pass.
Both independent C++ peers pass clang-tidy. The native ASan/UBSan corpus passes
64 cases: fourteen operations, 25 injected-selector SDK and 25 Host cases; this
is separate from the ordinary public Client process corpus. Six catalogue
tests, catalogue generation, Markdown links and ExDoc pass.

The ordinary archive check verifies exact members and source bytes, including
both new runtime stream modules, then compiles extracted Elixir source out of
tree. Archive SHA-256 is
`6526b64062ff8ce867c2a0dac22bebb95709e70fb8f174f3f1d6e4b2c6563001`;
package lock SHA-256 is
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.
The existing optional write-mode consumer-module warning remains; that optional
lane was not executed. Retained archive directories were removed after exact
file-list and digest verification; test workspaces clean up on exit.

The affected set is BLE only. Full gates, Dialyzer, coverage, dependency audits,
Linux native/software lanes, leak-audit mode, independent CoreBluetooth archive
consumers and installed permission/peripheral tests were not run. The native
Host case uses an independent Driver; SDK cases use injected selectors. These
software results establish no actual permission, connection, pairing, RF,
physical effect or canonical Property truth. WBL.08 remains partial.

## Exact inputs

Paths are relative to `packages/wotex-ble`; the source commit pins the remaining
package and documentation inputs.

| File | SHA-256 |
| --- | --- |
| `lib/wotex/ble/core_bluetooth/connection.ex` | `5cdffc12324b17c86ea4cb7f654bce96139ed78d87c0ac17b37d6b9cecd98521` |
| `lib/wotex/ble/core_bluetooth/stream.ex` | `8102eda54da989ea7a53ed69bdddded65d384e31c180b6407c54975191597b79` |
| `lib/wotex/ble/core_bluetooth/report_flow.ex` | `536f481507b7761e779592300a4d97cda8607c12b2d0fe9c98bd59299ea8a676` |
| `lib/wotex/ble/bluez/subscription_owner.ex` | `5aac32f2d0ede8e3e77ee6acc3d48601f0b9a98906758d526c6632883818a373` |
| `lib/wotex/ble/runtime_frame.ex` | `896814e979b8b6bffa5c73cab1aed83221dff499a6305b4b2a578853b5c37199` |
| `lib/wotex/ble/runtime_relay.ex` | `993c2aef00cd3a990d86f68ba6da2caea3f5e1536474c55c94e94a60c9067059` |
| `lib/wotex/ble/transport.ex` | `bfa3d2b11b152c95746f0cf18c7f548be85da303446850c1ce25e6f42e257661` |
| `test/native/corebluetooth_client_peer.cpp` | `07049618339d52730779c8b481ed5ac7047b8375eaf34f4839a024bc2d2b1900` |
| `test/native/corebluetooth_host_peer.cpp` | `8ade014d42e039d21586ec3257076aed094972ae97c70d4fbb62e8205de07588` |
| `test/wotex/ble/corebluetooth_client_test.exs` | `5eda5276eb1006661ce69345ec73bd13032ab6eb4b62310a2a6001e5e7368e33` |
| `test/wotex/ble/corebluetooth_stream_test.exs` | `46dbc86b356c0f2c94a2915adf2ec7b9af033be9bd54cec3f80247d4e6a1b33e` |
