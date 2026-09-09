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

The selected macOS fixture and Linux ARM64 and x86_64 GCC ASan/UBSan component
executables pass against private daemons. The
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

## Native typed discovery snapshots

`test/native/objects_test.hpp` constructs actual libdbus typed ObjectManager
messages and exercises the production `objects.hpp` decoder through the explicit
native fixture. Assertions cover exact peer/device/service associations,
UUID normalization, optional uint16 handles, generation precision and bounded
unknown flags. Wrong variant types, duplicate dictionary keys, FD-bearing
messages and malformed peer values fail. A real one-descriptor signal on the
private daemon produces no callback and releases its descriptor on connection
close; a second connection remains usable. The over-capacity two-descriptor
fault runs in an owned native child that exits and is reaped within 1000 ms.
The parent retains no descriptors after that child fixture completes. On macOS,
the observed ancillary-data truncation leaves a descriptor after connection
close alone; process teardown supplies the required cleanup. Linux ARM64's
connection-close path also passes the two-descriptor fault. Neither result
substitutes for the final BEAM/native-host lifecycle fixture.
Native peer and snapshot constructors
restrict discovery to validated values.

The fixture exercises 4096 objects, 64 interfaces, 256 properties, 65536 aggregate
dictionary entries, 4096-byte paths and 1024 selected services/characteristics
at their boundaries. Unknown variant payloads are skipped without copying them
into the owned snapshot. These are typed native decoding tests; the separate
live ObjectManager fixture below exercises acquisition and reconciliation.

The native decoder also accepts exact typed metadata change/removal signals.
Its signal vectors exercise changed booleans, unknown-property omission,
invalidated properties, added objects and removed interfaces. Wrong signatures,
wrong variants, duplicate names, changed/invalidated overlap and the 256/64-entry
boundaries are asserted. This validates decoding; notification delivery is a
separate procedure.

## Native live ObjectManager discovery

`test/native/discovery_test.hpp` serves typed ObjectManager replies and metadata
signals through an actual private D-Bus daemon. It exercises `discovery.hpp`:
listeners precede the first snapshot, a signal before a stale reply forces a
fresh query, and four continuously raced replies fail `snapshot_unstable`.
Only the pinned BlueZ unique sender can change state. A directly addressed
forged signal from another sender is ignored; Value-only and unknown-property
changes do not invalidate discovery.

The fixture checks stable generations, changes restored before refresh, changes
visible only in a new snapshot, identity retargeting rejection, selected service
removal with no characteristics, malformed variants, loss of ServicesResolved
and owner replacement. A pending query admits no second refresh. Its deadline
returns `timeout`; close and late replies leave zero pending calls, listeners,
watches and timers. A callback can close its own discovery owner.

This peer implements the D-Bus boundary without a Bluetooth controller. These
tests do not establish radio discovery, real BlueZ Connect/Pair/ReadValue/WriteValue,
GATT notifications, the complete Port helper or the virtual-controller profile.
The existing public Elixir connection still executes the separately described
Python adapter baseline.

The native connection cases issue actual D-Bus Connect and Disconnect methods to
the private fixture service. Both owned and borrowed modes preserve an initially
connected link without either method. Borrowed disconnected/unresolved devices
fail. Owned startup waits for an actual ServicesResolved signal and a fresh typed
snapshot after Connect acknowledgement. Lost or malformed Connect acknowledgements
retain the attempt's cleanup responsibility; a typed rejection acquires no link.
The fixture asserts the identical unique sender for Connect and Disconnect,
suppression of late replies, and cancellation of pending calls. A blocked
Disconnect reply releases local resources within the cooperative allowance.
This is native D-Bus procedure/ownership evidence. BlueZ/controller execution
and full guardian/SDK integration remain separate acceptance requirements.

## Native canonical byte envelopes

`test/wotex/ble/native_bytes_test.exs` builds the production `bytes.hpp` codec
under the bounded native command guardian. WBL-B-F16 through WBL-B-F18 bind
exact corpus inputs to native results. RFC 4648 section 10 known answers and
an independent BEAM Base codec comparison establish the expected byte order
and encoding. Native checks cover every length from zero through 512, all octet
values, 513-byte rejection, zero-length views, invalid schema fields, embedded
NULs, non-alphabet text, missing padding and every nonzero pad-bit value.
The codec enforces decoded length before allocating output storage. It has no
SDK or process side effects. ReadValue, WriteValue and stream delivery through
the complete native backend remain separate procedure acceptance requirements.

## Native process custody

`test/wotex/ble/native_custody_test.exs` compiles the packaged runtime `custody.c`
and the standalone pipe-level `test/native/custody_check.c` fault driver under
the tooling command guardian. WBL-G01 through WBL-G09 bind the exact custody
corpus to observed byte counts, resource reaping and timing. The shared runtime
source is SHA-256
`ba2e2cc2ef7d32ed5e9691fce34a58f1f04e8605b73f3257caee31d619c71e41`.

Cases cover malformed startup, unintended inherited descriptors above a lowered
descriptor limit, fragmented and simultaneous bidirectional streams, full pipes,
stopped helpers, receiver loss, contained stderr, complete final output, ordinary
background group cleanup, isolation and one unchanged cleanup deadline. The
consumer is a native pipe reader independent of Erlang's Port driver. Its blocked
reads establish kernel backpressure; they do not establish a suspended BEAM
mailbox bound. The guardian implementation has no SDK or GATT behavior. Admission
of both executable digests, actual host integration and report-credit acceptance
remain separate requirements.

## Native Agent method boundary

The actual libdbus fixture in `test/interop/native_bus_test.exs` executes
`exported_methods` in `test/native/bus_test.cpp`. It checks exact unique sender,
object path and interface routing, bounded PIN/passkey returns, fixed rejection
without diagnostic text, deferred same-serial replies and no-reply suppression.
Malformed registrations and duplicate routes fail. One hundred thousand export
lifetimes retain no closed records; 64 concurrent exports exhaust admission.
A callback can remove its own export or close its bus connection.

The fault driver stops its own independent D-Bus daemon to apply kernel
backpressure. The producer reaches the explicit two-response queue bound and
fails closed; close releases queued responses and export records. The driver
resumes only its owned daemon. This is method dispatch and allocation evidence,
not acceptance of RegisterAgent, Device1.Pair, policy challenge forwarding or
bond/connection cleanup through the complete native helper.

## Native pairing prompt values

`test/native/agent_test.hpp` exercises the production `agent.hpp` boundary for
all seven Agent prompt kinds, exact peer association, PIN/passkey limits,
display progress, UUID normalization and explicit compatible decisions. It
checks original request retention after the caller releases its reference,
one-answer ownership, exact reply serial/destination, wrong kinds, forged
options, unknown members and fixed rejection without diagnostic text.

WBL-B-F19 through WBL-B-F24 execute concrete prompt/decision inputs through
`test/interop/native_bus_test.exs`. The native driver receives input only;
ExUnit compares the independently encoded reply projection with the corpus.
The pure cases construct actual typed libdbus messages and perform no bus or
pairing operation. Registration, policy callback deadlines, late replies and
native Pair/UnregisterAgent cleanup still require operation-level acceptance.
