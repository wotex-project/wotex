# Executable evidence

Current implementation: typed domain APIs, persistent Python/dbus-next ownership,
Agent/procedure/stream behavior and Runtime integration. The committed documentation
cohort `60d1e3c` has a passing full local gate: 8 doctests, 16 properties and
146 tests, one hardware exclusion; 51 Python contract tests; 95.0% coverage.
The [virtual-controller evidence](virtual-controller.md) identifies 15 real BlueZ
cases with two software controllers. These exercise the Python adapter and a
shared BlueZ wire stack. They do not execute the accepted C++ .13 backend.
Public BEAM/Runtime virtual-peer acceptance, native credit-flow execution and
complete stress/package evidence remain required. Uncommitted fixture work is
not acceptance evidence.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Acceptance boundary

[WBL.13](../specs/WBL.13-native-backend.md) defines the required native binary,
Mix/ExUnit tasks, exact version lanes and credit/resource tests. Its corpus records partial execution of the parser cases; all other native
backend and process-flow cases remain unexecuted. A passing current gate, a listed test path or a source
hash cannot establish execution of that target. Each completed software run must
bind case, corpus, source, SDK/binary, toolchain and cleanup-result hashes.
The mandatory runtime matrix is Elixir 1.18.4/OTP 27.3.4.15 and Elixir
1.20.2/OTP 29.0.4. Only identified executed lanes count as passing evidence.

## Committed source identities

These hashes identify the committed implementation/test inputs reviewed here;
they are not release artifacts or a claim about every future run. Fixture WIP is
excluded. Native software results require their own immutable manifest.

| Source | SHA-256 |
| --- | --- |
| `test/wotex/ble/contract_fixture_test.exs` | `3730f210ddcfa19258ccbdafd2721d50beae5234f431b8e81560b894bed32a7d` |
| `test/wotex/ble/runtime_integration_test.exs` | `9c32f64eabf16aff5e4121e2508b801ca6efb92975a4614f3aaca6ec6bbed470` |
| `test/wotex/ble/dbus_bridge_test.exs` | `7caf2b7d067ba761eeadc0d2b8886b8ccb3683012701a6d46c03b2c968c0b96d` |
| `test/wotex/ble/stream_bridge_test.exs` | `5d6aa2bb8bc287acab7e1a83cac9c8f686767fa6a00ced315d87cf8b10e58246` |
| `test/interop/virtual/native_gatt.py` | `e188f44614f59ad358658a461949d0346d1795d17062eb4c4ee86bf0ae72c83b` |

## Native C++ request parsing

`test/wotex/ble/native_frame_test.exs` compiles the shared production
`priv/bluez/native/frame.hpp` parser and executes B-F01 through B-F05 with exact
corpus inputs. `test/native/frame_test.cpp` also exercises uint64/int64 limits,
overflow, duplicate/escaped keys, malformed UTF-8 and surrogate pairs, depth/node/
collection/line bounds, every split point, coalesced frames, truncated EOF and
100000 monotonic request IDs. The pinned nlohmann header hash is an assertion.

The focused ExUnit lane and Linux ARM64 GCC ASan/UBSan executable pass. This is
native parser evidence, not D-Bus ownership, complete .13 flow control or GATT
interoperability. The required Linux x86_64 reference lane remains separate.
No production connection selects an incomplete native helper.

## Native report reservations

`test/wotex/ble/native_credit_test.exs` binds B-F07/B-F08/B-F09/B-F14/B-F15
to the production `credit.hpp` manager. Exact byte/sequence acknowledgements
release only the consumed prefix; retirement preserves outstanding credits until
acknowledged and cannot release a different stream's reservations. Native tests
exercise 64 active streams, 64 outstanding frames, the 1 MiB byte ceiling, forged
acknowledgements, a false retirement barrier and 100000 subscription lifetimes
with no retained closed-stream records. The six focused ExUnit tests and Linux
ARM64 GCC ASan/UBSan invariants pass.

These cases exercise the native accounting component. The trace fixture supplies
consumer acknowledgements from observed reservations; actual BEAM/Port credit
flow, bounded unsent report storage and sustained-callback process cases remain
unexecuted. No native SDK or software GATT claim follows from this unit evidence.

## Native private D-Bus ownership

`test/interop/native_bus_test.exs` compiles `test/native/bus_test.cpp` against
libdbus 1.16.2. The production `bus.hpp` component owns a private connection,
asynchronous Hello registration, watches, timers and at most 64 pending calls.
It rejects reused message serials, invalid reply signatures and success after
the absolute deadline. Closing cancels pending calls and releases only that
connection; a second sender retains its bus identity and remains usable.
Closing from a reply callback is an asserted lifecycle case.

The selected macOS fixture and Linux ARM64 GCC ASan/UBSan component executable
pass against private daemons. The Linux x86_64 reference lane is separate. The
ExUnit test command
guardian owns the daemon's process group and bounds command time/output/cleanup.
The fixture does not open the host system or session bus. Exact libdbus source
identity is specified in WBL.13; the selected fixture requires explicit source
and build directories and rejects a runtime library version mismatch.

The same fixture exercises source/path/signature-checked signal listeners,
removal inside callbacks, a 64-listener limit and 100000 listener lifetimes with
no retained records. `service.hpp` installs its ownership listener before the
asynchronous match/owner lookup. The fixture owns `org.bluez` on the private
daemon, asserts the distinct client/service unique names, then releases and
reacquires that name from a separate sender. The original service tracker
terminates once, cancels pending work and closes its private connection without
adopting the replacement. Cancelled establishment and late Hello also clean up.

The service-name fixture is an identity/ownership test, not a BlueZ GATT peer.
This evidence does not establish GATT, Agent1 procedures, the complete native
Port helper or the planned SDK build task.
