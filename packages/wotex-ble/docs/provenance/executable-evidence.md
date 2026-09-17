# Executable evidence

Current implementation: typed domain APIs, persistent Python/dbus-next ownership,
native SDK components, verified guardian-owned native startup, Agent/procedure/
stream behavior and Runtime integration. The current source has a passing full
local gate: 9 doctests, 17 properties and 250 tests, 46 declared interoperability/
hardware exclusions; 58 Python contract tests; 96.2% coverage.
The [virtual-controller evidence](virtual-controller.md) identifies 15 real BlueZ
cases with two software controllers. These exercise the Python adapter and a
shared BlueZ wire stack. They do not execute the accepted C++ .13 backend.
Public BEAM/Runtime virtual-peer acceptance, native build tasks and complete
stress/package evidence remain required. Uncommitted fixture work is not
acceptance evidence.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check --no-retry` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Acceptance boundary

[WBL.13](../specs/WBL.13-native-backend.md) defines the required native binary,
Mix/ExUnit tasks, exact version lanes and credit/resource tests. The executed
component, startup and BEAM credit cases are identified below; unlisted native
build and software-flow requirements remain open. A passing current gate,
a listed test path or a source hash cannot establish execution of that target.
Each completed software run must
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
Production selection requires the complete verified SDK/guardian cohort described
below; selection alone does not establish the remaining native flow obligations.

## Native build workspace

`test/wotex/ble/native_build_test.exs` and `native_source_test.exs` execute the
WBL-B01 build contract in the default suite. Deterministic build operations
drive the production recipe, workspace lock, manifest and audit code: exact
arguments, tool and platform admission before mutation, manifest identity and
read-only reuse, forged or changed manifests, retained failure locks and logs,
architecture mismatch, failed or expired steps, missing libraries, Python and
absolute-runpath dependencies, wrong sonames and malformed ready probes. The
source tests admit the packaged libdbus pin, reject links and foreign archive
roots, and transfer from a local verified-TLS server with trust, status, digest,
size and deadline failures. The packaged command guardian is compiled and run
for output, deadline and argument bounds, including a guardian that ignores
them.

The [native build receipt](native-build-v1.json) records two actual Linux runs
of `mix wotex.native.build` from a Debian 12, Elixir 1.18.4 / OTP 27.3.4.15 image
defined by `test/native/Dockerfile`: native arm64 and x86_64 under Docker Desktop
emulation. Each downloads and verifies libdbus 1.16.2, builds the shared library,
fixture daemon, host and guardian with GCC 12.2.0, CMake 3.25.1 and Ninja 1.11.1,
and verifies reuse on a second invocation. The actual host emits the exact
ready frame with closed input on both lanes. These runs establish artifact and
startup identity only; advisory scanning, sanitizer builds, the software tasks,
the complete native corpus and BlueZ/GATT execution remain open.

## Native report reservations

`test/wotex/ble/native_credit_test.exs` binds B-F07 through B-F10, B-F14 and
B-F15 to the production `credit.hpp` manager and `report_queue.hpp` deferred
queue. Exact byte/sequence acknowledgements release only the consumed prefix;
retirement preserves outstanding credits until acknowledged and cannot release a
different stream's reservations. A transmit attempt without credit enters the
same bounded queue that `NativeReports` uses; B-F10's seventeenth attempt stays
queued after the sixteen-report stream window. Native tests exercise 64 active
streams, 64 outstanding frames, the 1 MiB byte ceiling, forged acknowledgements,
a false retirement barrier, 100000 subscription lifetimes with no retained
closed-stream records and the queue's per-stream, 64-entry, 1 MiB, ordering and
discard bounds. The seven focused ExUnit tests pass. A Debian 12 Linux ARM64
lane with GCC 12.2.0 (`g++-12 12.2.0-14+deb12u1`), ASan/UBSan and leak
detection compares all six flow traces with the corpus and runs the credit and
report invariants. These traces use explicit byte lengths and component calls;
they are not process-flow or SDK callback evidence.

`test/wotex/ble/report_flow_test.exs` exercises the production BEAM
`ReportFlow` ledger and `SubscriptionOwner` admission boundary. Two live stream
owners complete out of order without acknowledging a gap; a retirement barrier
consumes only its stream, a later live-stream completion advances the exact
contiguous prefix, and duplicate/post-retirement frames cannot resurrect the
stream. Receiver overflow sends no internal acknowledgement. The ledger asserts
the 64-frame, 1 MiB, per-stream window, uint64 and exact generation boundaries.

`test/wotex/ble/native_startup_test.exs` compiles
`test/native/beam_startup_sdk.c`, verifies its identity, and launches it through
the packaged guardian. The real Port exchange sends the exact native
`queue_limit`, accepts two sequenced value reports, and requires acknowledgements
whose cumulative byte counts include each encoded newline. It then emits the
retirement barrier before cancellation success. Separate cases inject wrong
generation, unknown stream, malformed terminal and false retirement controls;
the exact connection generation closes. A valid terminal control retires only
that stream and preserves the session.

This is actual guardian/Port/BEAM credit-flow evidence against a deterministic
C process boundary. It does not execute the C++ SDK against BlueZ, sustained
callback stress, the required sanitizer matrix or public Runtime virtual-peer
acceptance.

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
`d08b553ed0cd4ba9b166e8b01aae8eddd96f97a8accc418632d68e3c75ad37d2`.

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

## Native Pair and Agent lifecycle

`test/native/pairing_test.hpp` drives the production `NativePairing` owner against
an independent private D-Bus Agent manager/device fixture. It checks registration,
explicit policy, Pair completion and unregistration on the same actual unique
sender for all three supported capabilities. WBL-B-F25 and WBL-B-F26 execute exact
accept/reject lifecycle inputs and compare observed method/resource projections.
The fixture observes the daemon's unique-sender release signal to clear remote
Agent records when a sender closes; its counters do not infer remote release
from a local function return.

Fault cases cover missing/malformed acknowledgements, explicit remote errors,
wrong peer/challenge/decision, overlapping prompts, premature Pair completion,
foreign senders, Cancel/Release, event-capacity failure, owner replacement and
cancellation while registration or discovery is pending. A full native pending
queue escalates cleanup without silently evicting ordinary work to admit another
method. One hundred successive Agent lifetimes leave no exports, pending calls,
queued replies or retained prompts. A borrowed link receives no explicit
Disconnect. A blocked UnregisterAgent and blocked owned-link Disconnect share
the caller's original cleanup deadline; repeated cancellation cannot extend it.
Native errors retain admitted names and exclude arbitrary diagnostic bodies.

These tests exercise actual libdbus messages and native component ownership.
They do not execute the complete Port helper, BEAM native route, persistent BlueZ
service or virtual Bluetooth controller. Those implementation and interoperability
requirements remain open. Public Pair effect classification must satisfy C04
when the native backend is connected to the BEAM owner.

## Native acknowledged GATT procedures

`test/native/procedures_test.hpp` executes the production typed address and
`NativeProcedure` owner against an independent GATT receiver on the private
libdbus daemon. WBL-B-F27 through WBL-B-F32 compare concrete read/write, malformed
value, remote rejection and missing/malformed response projections. The native
driver receives inputs only; expected values remain in ExUnit.

The receiver checks exact source, object path, signatures, byte arrays and typed
request-only write options. Read/write sizes 0, 1, 2, 255, 256 and 512 are exercised;
513-byte read replies and noncanonical write envelopes fail. Admission tests cover
unknown fields, invalid UUID/path/handle/generation types, stale snapshots,
conflicting selectors, duplicate UUID matches and absent procedure flags.
Malformed inputs cause no discovery or GATT request.

Lifecycle tests cover cancellation before submission, during discovery and while
an acknowledgement is pending; unavailable submission-event capacity; selected
owner loss; late replies; borrowed and owned link cleanup; and a blocked owned
Disconnect within the original deadline. One thousand successive reads on the
same connection leave no pending calls or extra listeners. No write is retried.
These results establish native component behavior through actual D-Bus messages.
Complete Port-host dispatch, BEAM native integration and independent BlueZ/ATT
interoperability remain separate open requirements.

## Native notification ownership

`test/native/notify_value_test.hpp` checks the production mode selector and typed
PropertiesChanged decoder. Exact byte-array and Boolean variants are required;
empty through 512-byte values are retained independently of their D-Bus message.
Repeated equal values remain distinct. WBL-B-F33 through WBL-B-F37 execute exact
mode-selection inputs and outputs.

`test/native/notifications_test.hpp` drives `NativeNotifications` against an
independent private D-Bus characteristic receiver. WBL-B-F38 through WBL-B-F41
execute concrete early-value, repeated-value, notification/indication mode and
report-admission traces. Establishment results and report metadata are compared
with exact corpus values. The receiver observes actual StartNotify/StopNotify
calls and unique-sender release; local return values do not infer remote cleanup.

The boundary matrix covers one versus two early reports, cancellation during
establishment or its completion callback, remote/malformed/missing responses,
foreign senders, wrong paths/interfaces, invalidated Value, Notifying loss,
metadata changes and selected owner loss. One stream's failed report admission
preserves another stream. Sixty-four simultaneous subscriptions use one manager
listener, and 1,000 successive subscribe/cancel lifetimes leave no active entries,
paths, pending calls or extra listeners. StopNotify completes while an unrelated
ReadValue remains pending. Full native pending-call admission escalates cleanup
by closing the owned sender within the supplied deadline.

`test/native/pending_test.hpp` checks opaque generation-bound cancellation tickets:
foreign, stale, completed and default tickets cannot cancel another call, and
1,000 successive pending calls retain no tombstones. A cancelled discovery refresh
can be followed by successful establishment on the same connection.

These are actual libdbus component tests. The report callback represents bounded
host admission; it is not a Port transport or proof of BEAM mailbox flow control.
Complete host dispatch/output, cumulative credits across the BEAM boundary and
independent BlueZ/ATT interoperability remain open requirements.

## Native output serialization and reservations

`test/wotex/ble/native_output_test.exs` runs the production `EncodedFrame` and
`NativeOutput` components through an owned native test executable. WBL-B-F42
through WBL-B-F44 compare exact bounded serialization outputs. Independent BEAM
JSON decoding checks native integers, Boolean/null values, UTF-8, escapes and
structured values. Native cases exercise exact line size, newline/escape growth,
invalid UTF-8, nonfinite/binary values, depth, collection and node limits.

The reservation matrix fills all 64 ordinary reply reservations, 64 report
frames and 256 control frames. Stale, foreign, default and already queued reply
tickets cannot release or reuse a reservation. One hundred thousand reservation
lifetimes leave no historical records. An eight-frame 1 MiB report backlog still
admits separate ordinary replies and a terminal control frame.

The pipe fixture fills an actual nonblocking pipe, checks retained counters under
backpressure, drains partial frames and compares the complete ordered byte-stream
hash with an independently accumulated expected hash. Reply capacity returns
only after complete transmission. Closed-reader and blocking-descriptor paths
fail explicitly. Queue byte counts measure retained encoded bytes, not total
allocator or process RSS. These tests do not execute the complete host or prove
report credit acknowledgements across the BEAM Port boundary; those remain open.

## Native value flow and terminal controls

`test/wotex/ble/native_reports_test.exs` executes `reports.hpp`, `credit.hpp`
and `output.hpp` together through actual nonblocking pipes. WBL-B-F45 through
WBL-B-F48 compare exact native admission results, complete wire frames and
remaining counters. Value reports carry cumulative sequence/byte credits;
terminal errors use the separate control reservation and precede the single
retirement barrier. A queued or partly written value cannot be acknowledged.

The native matrix checks forged metadata, stale IDs, invalid error fields,
partial writes, exact cumulative byte acknowledgements, per-stream windows,
64 active streams, 64 queued reports and the 1 MiB queued/credited byte limits.
A blocked stream preserves another stream's progress and its own report order.
Retirement discards unsent values and retains only outstanding credit records;
1,000 subscribe/report/retire/acknowledge lifetimes leave no historical records.
Ten thousand callbacks after overflow cannot queue another value or terminal.
Control exhaustion fails the shared channel rather than growing without bound.
The byte-pressure cases use explicit test-only metadata padding to reach generic
IPC bounds; they do not assert that BlueZ accepts that metadata as a characteristic.

The error-code/name shape is shared with actual SDK failures. These are native
component and wire-serialization tests. SDK notification callbacks, complete
host dispatch and actual BEAM process suspension still require their integrated
execution; this evidence does not complete the accepted Port backend.

## Native guardian startup ownership

`test/wotex/ble/native_command_test.exs` checks the fixture guardian through
actual BEAM Ports: 1,000 short commands retain exact exit status, 32 concurrent
commands retain separate groups, and inherited ignored SIGCHLD/blocked signals
cannot discard child status. An injected parent setpgid failure leaves the
child's marker file absent and returns a bounded setup failure.

`test/wotex/ble/native_guardian_startup_test.exs` and
`test/native/guardian_startup_check.c` exercise the runtime guardian's release
barrier with 1,000 short SDK processes, inherited signal state and injected group
admission failures. Both guardians establish the group before releasing their
child. The native probe checks its own process-group identity and inherited
signal state. The existing opaque-stream custody matrix remains applicable;
startup serialization grants no additional time or report credits.

## Native live Device1 query

`test/native/health_test.hpp` executes the native `health` operation against an
independent private D-Bus receiver. WBL-B-F49 through WBL-B-F55 supply exact typed
reply fields and compare values, bounded error envelopes, GetAll calls and
observed sender release. The fixture sees the original client sender, Device1
path, Properties interface and exact `s` request argument. Successful health
requires current Connected and ServicesResolved booleans plus the original
adapter/address/address-type identity.

The matrix checks missing fields, wrong variants, valid changed identities,
malformed identities, false state, duplicate and excessive properties, bounded
skipping of unknown properties, permission errors, malformed replies, deadline expiry,
late replies and explicit cancellation. No borrowed case issues Disconnect.
The cases use the actual libdbus operation/lifecycle code; they do not establish
complete native-host routing or a BlueZ/ATT interoperability result.


## Native bounded discovery pages

`test/wotex/ble/native_pages_test.exs` compiles `test/native/pages_test.cpp` and
executes the production `NativePages` component through the owned command
fixture. WBL-B-F56 through WBL-B-F60 provide exact page, invalidation, foreign
cursor, eviction and 2,000-generation ledger projections. Other native cases
cover complete ordering across 1,024 characteristics, aggregate line and JSON
node limits, forged options, generation regression and exhaustion boundaries,
repeat-position token reuse, eight-collision rejection and random-source failure
without ledger mutation. The page component performs no D-Bus I/O. Complete
native host routing and the BEAM discovery API remain separate proof obligations.


## Native SDK host composition

`test/native/host_test.hpp` drives the combined `NativeHost` against an independent
private D-Bus service. Cases execute typed health, read/write, discovery,
pairing challenges and policy replies, notification overflow and cumulative
report ACKs. A held read does not postpone StopNotify or a different queued
request's timeout. Close cancels a pending StartNotify and remains admitted
with all 64 ordinary reply reservations held. Unknown characteristic flags
remain present in discovery results.

`test/native/host_process_test.hpp` executes `priv/bluez/native/main.cpp` as an
owned child with actual stdin/stdout pipes. WBL-B-F61 through WBL-B-F63 project
startup, complete discovery, explicit close, duplicate flow rejection and stdin
loss during a withheld opening response. A regression sends `close` and then
closes input before the reply: the admitted close still returns a null result
and exit status zero instead of a `cleanup_timeout` failure. Before the fix the
same trace failed its exit-status assertion on the Linux arm64 lane. Independent NameHasOwner queries check
client-sender release and service-sender isolation after process exit. The fixture
owns and reaps this direct, non-forking SDK child; runtime guardian process-group
custody has its separate fault corpus. This evidence does not establish native
artifact admission, BEAM native selection, Runtime report flow or virtual ATT
interoperability.


## Native executable identity admission

`test/wotex/ble/native_artifacts_test.exs` executes pure selector construction
and bounded verification of temporary executable files. WBL-B-F64 through
WBL-B-F67 cover the exact four selectors and missing, duplicate and malformed
fields without file lookup. ExUnit cases cover independent SDK/guardian digests,
field-specific missing and mismatched errors, descriptor-backed multi-chunk
hashing, final symlink and permission rejection, empty and oversized sparse
files, deadline equality and deployment replacement between explicit checks.
The deterministic module example is a real doctest. Verification starts no
process; integration with the BEAM native startup owner remains a separate
acceptance obligation.

## BEAM native artifact admission and startup

`test/wotex/ble/native_startup_test.exs` compiles the production guardian and
the deterministic `test/native/beam_startup_sdk.c` process fixture into an
OS-temporary directory. WBL-B01/WBL-B02 assertions prove that a complete native
selector cohort verifies both SHA-256 identities under the caller's original
deadline, launches the SDK only through the guardian, accepts only the exact
native ready identity, sends a fresh 128-bit lowercase session generation in
`flow_open` before `open`, and completes bounded `close`. Incomplete selectors
and an executable digest mismatch fail before either process starts. The
fixture accepts no arguments or environment configuration; it is executable
boundary evidence, not an adapter implementation or an agent harness.

This closes only BEAM admission and startup for the already implemented native
host. BEAM report acknowledgement/retirement, native build tasks, sanitizer
matrix execution and complete virtual-ATT software acceptance remain open in
WBL-P00 and later ordered packages.
