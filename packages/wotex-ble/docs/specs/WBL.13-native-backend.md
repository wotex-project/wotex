---
spec:
  id: WBL.13
  title: "Native backend, build and IPC contract"
  status: accepted
  version: 1.0.6
  owner: wotex-ble
  updated: 2026-09-09
---

# WBL.13 Native backend, build and IPC contract

This is the accepted native BlueZ target. [Current implementation and evidence](../provenance/executable-evidence.md)
are separate. This contract and the .00/.10/.11/.12 requirements jointly define
acceptance; documentation or a source archive alone is not completed software.

## WBL-B01 — Production and build boundary

The production backend is one first-party C++17 executable, `wotex-ble-host`,
started by an explicitly owned BEAM Port. It requires no Python interpreter,
Python package, shell command parser or NIF inside the BEAM. Module loading,
profile construction and pure values start no process and read no configuration.
The executable path is absolute, validated before startup, and executed directly
with separate arguments. Native runtime libraries are declared in the build
manifest; a missing or mismatched dependency fails startup.

The generic entry points are Mix tasks:

```sh
mix wotex.native.build --workspace /absolute/disposable/native
mix wotex.software.build --workspace /absolute/disposable/software
mix wotex.software.run --workspace /absolute/disposable/software
```

They require exactly one `--workspace` argument. Unknown/duplicate options,
relative paths, symlink workspaces and unrelated nonempty directories fail before
mutation. Only a matching manifest permits reuse. Mix owns source download,
hash verification, bounded process launch, result collection and cleanup. ExUnit
owns assertion orchestration and machine-readable case results. Native C++ unit
executables exercise the same production parser/ownership code under sanitizers.
There is no new generic Python runner. Required upstream generation/bootstrap
programs may use Python at build time; the manifest names each executable,
source hash and purpose. Independent Python peers require the explicit exception
below and cannot implement responses on behalf of the production adapter.

The required reference native lane is Linux x86_64, Debian 12, GCC/G++ 12.2.0;
CMake 3.25.1 applies to CMake targets, Ninja 1.11.1 to native builds. SDK-required
GN/generation tools use the immutable upstream lock entries and are recorded by
actual executable SHA-256. Cross compilation requires an explicit target triple;
an architecture mismatch fails before execution. Additional architectures are
separate evidenced lanes. BEAM matrix: Elixir 1.18.4/OTP 27.3.4.15 and
Elixir 1.20.2/OTP 29.0.4. The software runner executes the native client and real
Runtime calls in both lanes, independently of physical hardware.

`native-manifest.json` has schema `wotex.native-build`, version `1`, package,
source_revision, source_files (relative path/SHA-256), upstream sources (URL,
commit/version, archive SHA-256), recursive SDK gitlink commits where applicable,
toolchain (target triple, compiler/linker/generator versions and executable
SHA-256), exact arguments/environment allowlist, build_features, binaries
(relative path/SHA-256/ELF machine/needed libraries), and audit results. No
credential, absolute consumer path or host environment dump enters this file.
Downloads are source archives from the pinned upstreams; no remote is configured.
Every required transitive SDK source is content-bound before compilation.
Build failure, an unreviewed advisory, hash mismatch or missing required tool is
nonzero. A manifest is not successful execution evidence.

## WBL-B02 — Typed process boundary

C07 defines the production version-1 JSON-line envelopes. The native helper
emits exactly one ready frame before `open`; its exact backend is `bluez-native`
and revision is `2123ab772fbe97d1369fc9e179ea87c3469cf98f`. The BEAM owner checks both. A different backend
never triggers an implicit fallback. Framing remains UTF-8 with 131072 bytes
including newline, depth eight, at most 1024 entries per collection and 4096
aggregate nodes. Numbers retain signed/unsigned 64-bit precision. Non-finite
numbers, duplicate keys, invalid UTF-8 and extra envelope fields fail. Parsing
must enforce bounds during traversal, before an unbounded native allocation;
nlohmann/json 3.11.3 SAX or equivalent bounded callbacks are the selected parser.
The header source and SHA-256 are fixed below. The exact header and its MIT
license are packaged under `priv/bluez/native/vendor`; this parser dependency
does not require a runtime or test-time download.

Request parameters and results have the exact operation-specific shapes in .10
and .11. No native pointer, process address or foreign object name crosses IPC.
Bytes use the exact canonical Base64 envelope from C07 and obey the owning
protocol's decoded-size bound. Attribute byte envelopes admit exactly `type:
"bytes"` and a string `base64`, with no extra fields. The encoded string has at
most 684 bytes and the decoded value at most 512 bytes; reject a larger decoded
length before allocating its storage. Empty values are valid. The standard
alphabet, required final padding and zero pad bits follow
[RFC 4648 sections 3–4](https://www.rfc-editor.org/rfc/rfc4648.html#section-3).
Whitespace, URL-safe alphabet variants, misplaced/excess padding and nonzero pad
bits fail `:invalid_value`; the wire profile has one encoding per byte sequence.
Only fixed library error codes and admitted
numeric status/error-name fields cross the boundary; native exception text,
credentials and values do not. Unknown mutation effect remains non-retryable
and maps to permanent Runtime classification. A late native result cannot turn
an expired request into success.

The native event loop keeps stdin and framed output nonblocking. Its report
output backlog is at most 1048576 bytes, with the separate control reservation
below; overflow terminates the owned generation
and releases its resources. Logs use a separate sink. EOF, owner death, bad
framing and deadline escalation share the cleanup path. Cooperative SDK cleanup
uses at most the first 500 ms of C03's single 1000 ms local cleanup deadline.
The independent process guardian has the remaining 500 ms to terminate and
reap its direct SDK child and terminate ordinary members of that child's process
group. The BLE SDK host does not fork. This portable boundary does not claim
containment of deliberate process-group/session escapes or uninterruptible kernel
state. Repeated close, EOF or signals cannot restart either allowance. Neither
graceful close nor timeout claims remote rollback.

The runtime guardian contract in `priv/bluez/native/runtime-guardian.md`
defines opaque bidirectional forwarding, bounded queue capacities, stable direct
child/process-group custody, descriptor inheritance, fixed exit statuses and
pipe-level fault cases WBL-G01 through WBL-G10. This profile fixes guardian
input/output capacities at 131072/65536 bytes and its cleanup allowance at
500 ms. Both guardian and SDK executable paths are absolute and both SHA-256
identities are checked before spawn. Credentials and connection values travel
through typed SDK IPC, never argv. The cleared environment contains only explicit
reviewed SDK execution values. Transparent guardian buffers do not replace
report credits or bound the BEAM mailbox.
The admission record bounds, original-route cancellation and callback ownership
below apply even when data work is blocked or the ordinary queue is full.

### Report credits across the Port boundary

Frame size and native queue limits do not by themselves bound the BEAM Port
mailbox. Before `open`, the BEAM owner sends exactly one flow initialization
frame: `{"version":1,"event":"flow_open","session_generation":"0123456789abcdef0123456789abcdef"}`.
The example generation is test data; production uses a fresh 128-bit random
value encoded as 32 lowercase hexadecimal characters. It is an identity token,
not a credential. A duplicate initialization or wrong generation fails closed.

The session has 64 report-frame credits and 1048576 encoded-byte credits;
a stream has at most `min(16, queue_limit)` unacknowledged reports. `queue_limit`
is an explicit validated native subscribe parameter translating the public
`max_queue_length` option with C05's range. Every
report includes the exact `session_generation` and a strictly increasing
unsigned-64 `report_sequence`, starting at 1 for the session. Encoded bytes
include the newline. The sender reserves frame and byte credit before stdout
submission. It retains only bounded outstanding sequence/stream/byte records.
No report is transmitted without both credits, and sequence exhaustion closes
the generation without rollover or replay.

The only acknowledgement frame is
`{"version":1,"event":"report_ack","session_generation":"0123456789abcdef0123456789abcdef","report_sequence":1,"acknowledged_bytes":128}`.
`report_sequence` is the cumulative consumed prefix; `acknowledged_bytes` is the
exact cumulative sum of encoded report lengths through that prefix. The native
owner compares it with its own outstanding records. Repeated, decreased, skipped
untransmitted, wrong-generation or wrong-byte acknowledgements fail closed;
there is no caller-selected credit increment. Counter exhaustion terminates.
Reports consumed out of order remain in the bounded BEAM acknowledgement map
until the contiguous prefix is complete. Credits return only for that prefix.

The connection transfers a report to its exact stream owner and receives an
internal acknowledgement only after that owner validates the report and admits
delivery under C05. It then advances the cumulative prefix. A suspended stream
or connection owner cannot acknowledge. A suspended final receiver reaches
C05's admission limit; that stream terminates instead of replenishing credits.
This bounds library-originated messages; it does not claim ownership of unrelated
messages sent to a consumer's shared mailbox. Process.info sampling alone is not
native flow control. Runtime opening-worker/final-owner identity follows WRT.01
1.3.1; partial native resources are owned before any blocking establishment wait.

Without credit, native callbacks enter a separately bounded queue of 64 reports
and 1048576 encoded bytes. BLE preserves distinct reports and terminates only the affected stream with
`:queue_overflow` before accepting an excess report.
SDK callbacks never wait for stdout. Per-stream queued reports also obey C05
queue_limit; a shared byte/frame queue limit may terminate earlier. Termination retires that stream delivery generation, cancels
its SDK listener and discards its queued reports. Repeated callbacks cannot emit
more terminal messages. Control frames and terminal errors have a separate reservation of 256 frames
of at most 4096 bytes each. At most one error per admitted operation/stream, one
retirement barrier per stream and one close response are queued; duplicate
terminal attempts are suppressed. Ordinary successful operation replies have a
separate finite reservation: at most 64 frames, each within the 131072-byte C07
ceiling (8388608 aggregate bytes). A result cannot use the control reservation.
Native admission retains its reply reservation through transmission; it cannot
admit new work indefinitely while replies are undrained. Exhausting this reservation terminates the owned process rather
than blocking cancellation behind reports.

A stream delivery generation is distinct from the IPC session generation.
Stream cancellation/overflow preserves other streams and the connection unless
the shared channel itself is malformed, exhausted or unresponsive. Native
retirement stops new reports, discards unsent reports and emits exactly one
control barrier: `version: 1`, `event: "stream_retired"`, `session_generation`,
`subscription_id`, stream `generation`, and `last_report_sequence` (zero if none).
The barrier follows every transmitted frame for that stream in stdout order;
no such frame is valid after it. Cancellation success follows this barrier.
The native owner retains bounded outstanding credit records until the BEAM's
normal cumulative acknowledgement; retirement cannot mint credits independently.

The BEAM connection marks already validated reports for a retired stream as
consumed/discarded, including those awaiting a dead stream owner's internal
acknowledgement. It validates/discards any preceding in-flight reports before
processing the barrier, then advances the contiguous global ACK prefix. A report
for a live different stream still requires that stream owner's acknowledgement.
This releases cancelled-stream credit without an unbounded tombstone collection.
After the barrier and its cumulative acknowledgement, delete the retired record;
no later frame may resurrect it. A false barrier sequence, second barrier or
post-barrier report is an invalid channel, not a new subscription. Counter/ID
ownership remains bounded by active and outstanding records.

`flow_trace` corpus cases drive the shared production credit manager with exact
encoded byte lengths. `transmit` means a frame reached stdout, `consume` means
the real stream owner admitted delivery, and `ack` supplies the exact control
frame. The result reports observed transmitted/queued counts, terminal code and
remaining credit. A transmit event count defaults to one and otherwise means
that exact number of sequential attempted enqueues, one per event-loop iteration.
A retire event exercises the real stream retirement path and barrier; its
projection advances an ACK only over actually validated/discarded reports.
A consume event acknowledges its exact live report before advancing the prefix. On a rejected acknowledgement
the projection captures the last valid counters before teardown. `process_flow` cases use a test-only native callback source feeding the same
production delivery/credit code, not a fabricated SDK response. They suspend
the selected actual BEAM process at zero, enqueue the input callback count, one per event-loop iteration,
resume at 50 ms, then observe through 1050 ms. Exact normalized output contains
Boolean frame_bound/byte_bound (within the specified report/control reservations),
terminal_count, deliveries_after_terminal and owned_processes_after_grace.
The runner measures actual mailbox, frame-byte and ownership counters; an absent
source/owner or missing terminal fails. These are process boundary tests, with
SDK interoperability separately required. Separate ExUnit tests suspend the actual BEAM connection,
stream owner and final receiver in turn while a native producer generates 10000
callbacks. Assert finite Port mailbox/report byte counts, one terminal, bounded
cancellation, no late generation delivery and zero owned resources. A parser
or pure flow test alone cannot satisfy these process tests.

## WBL-B03 — Concrete native acceptance

[The native corpus](fixtures/native-port-v1.json) has format
`wotex.native-contract`, version `1.0.0`, and explicit execution status. Its executed_cases list
identifies only cases bound to passing tests in executable-evidence.md.
It supplements the .11 value/lifecycle and .12 Runtime corpora. Every case names
an operation, exact input and exact normalized expectation. `line_utf8` includes
the terminating newline when one is required. `parse_request` calls the shared
production frame/request validator without SDK I/O and projects either
`{"accepted":true}` or `{"accepted":false}`; it is not a fabricated protocol
response. The native contract-test binary receives input only. ExUnit reads the
expected projection and compares the independently observed result.
`decode_bytes` calls the production bounded byte-envelope decoder, with exact
input in `value`. Its projection is `{"accepted":true,"bytes":[0,255]}` with
the actual ordered octets, or exactly `{"accepted":false}`. No SDK call occurs.
`ready` starts the actual helper, captures its first frame and closes its input;
the expectation is exact JSON-object equality plus zero surviving owned
processes after the grace. Parser cases never count as SDK interoperability.

`test/wotex/ble/native_contract_test.exs` drives the corpus and fails unknown
formats/operations, absent assertions or mismatches. The process fixture splits
each valid request at every byte, coalesces two frames, closes mid-frame, sends
oversized lines and leaves stderr noisy. Native ASan/UBSan runs include malformed
bytes, full admission, late callbacks, startup failures, EOF during pending work
and cleanup. Each callback test records acquisition, terminal delivery,
cancellation, destructor and native-resource counts from the implementation;
the oracle does not synthesize those counts. Every resource count returns to
baseline. C09 additionally requires 1000 operations, 100 open/close cycles,
100 receiver-death cycles for stream profiles, 32 concurrent callers, both BEAM
lanes, dependency audit and clean archive/out-of-tree package validation.

Results identify case ID, test path, corpus/source/binary hashes, runtime/native
versions, command, result and cleanup counters. Missing software peers, optional
kernel facilities required by the selected fixture, skipped required cases and
zero-case runs fail. Evidence for a different backend does not accept this one.

The separate [custody corpus](fixtures/custody-contract-v1.json) binds WBL-G01
through WBL-G09 to the native `custody_check.c` driver and ExUnit assertions.
The driver receives the case ID and its workspace, never expected results. It
emits observed capacities, byte counts, direct reaping, background termination
and cleanup durations. WBL-G10 requires the same cases on macOS and Linux,
including the separately identified ordinary, ASan/UBSan and LeakSanitizer lanes.
Its instrumentation-only post-main allowance does not extend SDK reaping or
production cleanup deadlines. These cases establish transparent process custody;
SDK credit-flow and full native GATT acceptance require their own execution.

Parser header: [nlohmann/json 3.11.3](https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp),
SHA-256 `9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6`.
## WBL-B04 — Native BlueZ owner

Runtime links libdbus 1.16.2 from
[dbus-1.16.2.tar.xz](https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz),
SHA-256 `0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2`.
The exact software peer uses BlueZ 5.85 commit
`2123ab772fbe97d1369fc9e179ea87c3469cf98f`, archive SHA-256
`53a95c3dc9897f617b8bae0121d3f4c55c28a757bd48546c707bd2bbac45af0a`.
BlueZ owns Bluetooth HCI/GAP/ATT/GATT and security. The helper owns D-Bus lifecycle;
it is not a second Bluetooth stack.

Use `dbus_connection_open_private`, register the connection with the selected
bus, disable exit-on-disconnect, and integrate D-Bus watch/timeout functions with
poll and stdin/output readiness. `dbus_connection_send_with_reply` creates
bounded pending calls; callbacks unref each pending call and message exactly
once. Never block the only event loop in send_with_reply_and_block. Configure
received message size at 4 MiB and the aggregate receive watermark at 8 MiB, then
apply S01 object/catalogue bounds while decoding ObjectManager replies.
The libdbus watermark pauses further reads after outstanding messages exceed
the threshold; its documented overshoot includes one maximum-sized message and
a read buffer. It is not an exact native allocation or RSS ceiling. The decoded
snapshot has the independent entry bounds below. Unix file-descriptor transfer
has a one-FD per-message receive slot and aggregate watermark of one. Reject
every FD-bearing message before invoking an operation or signal callback and
close the private connection, then terminate and reap the native host within
C03's cleanup grace. The receive slot permits libdbus to own and close
the received descriptor on rejection; it grants no admitted FD procedure. Zero
for the aggregate watermark stalls all libdbus dispatch, including messages
without FDs. This profile does not use Acquire* procedures. ObjectManager
decoding independently rejects an FD-bearing message. Ancillary-data truncation
can leave descriptors that the platform does not return to libdbus; graceful
connection close alone does not establish zero native descriptors. Fatal
channel teardown therefore ends the owned process rather than reusing it.
The single
private connection supplies the unique sender for open, discovery, Agent1,
ReadValue, WriteValue, StartNotify and StopNotify. It closes and unreferences
only its own connection.

The ObjectManager decoder admits at most 64 interfaces per object, 256
properties per interface and 65536 aggregate dictionary entries, including
object, interface and property entries. These limits supplement S01's object
and selected-catalogue bounds. Check every count before inserting its entry.
Object paths retain the 4096-byte limit; interface and property names obey the
D-Bus interface/member grammar and 255-byte limits. Reject duplicate object,
interface and property keys, including keys in unselected interfaces.

Validate known property variants before extracting their values: Device1
Adapter, GattService1 Device and GattCharacteristic1 Service are object paths;
UUID, Address and AddressType are strings; Connected and ServicesResolved are
booleans; Handle is uint16 in 1..65535; Flags is an array of at most 64 distinct
UTF-8 strings of 1..64 bytes. A uint32 Handle or string-encoded object path is
an invalid response even when its apparent value fits. Unknown properties and
interfaces are structurally traversed within the entry budget, then skipped
without expanding their variant payloads. Only a successfully decoded snapshot
and a validated peer value enter discovery association. Selected services must
name the exact device path; selected characteristics must name a selected
service path. Lexical path-prefix similarity establishes no association.

Metadata change decoding uses the exact PropertiesChanged `sa{sv}as`,
InterfacesAdded `oa{sa{sv}}` and InterfacesRemoved `oas` signatures. Known
property variants use the snapshot rules above. Invalidated property names have
a 256-entry bound; removed interface names have a 64-entry bound. Names obey the
same grammar as snapshot keys, and duplicate names fail. A property cannot occur
in both the changed and invalidated collections, including an unknown property.
Changed metadata does not itself constitute a characteristic notification;
S04's byte/source/subscription validation separately governs report delivery.

ObjectManager ownership installs all local metadata listeners, then awaits both
Properties and ObjectManager AddMatch acknowledgements before its first
GetManagedObjects call to the pinned unique sender. The metadata revision is
captured at dispatch. Every reply is decoded within the same bounds; a revision
change discards that snapshot and permits at most four total snapshot attempts
within the original absolute deadline. Four raced replies fail
`:snapshot_unstable` and close this sender. At most one discovery refresh is
pending; admission of another refresh fails before D-Bus submission.

The owner retains the exact selected Device1 path and selected service paths,
including services without characteristics. A different matching Device1 path
fails `:peer_changed`; there is no automatic retargeting. Relevant typed metadata
changes mark the current discovery stale immediately. The next stable snapshot
advances its uint64 generation once if metadata changed or its selected topology
differs. Even a change restored before refresh invalidates the previous
generation. Unknown properties and Value-only signals do not alter discovery.
The conservative revision scope includes known metadata from the pinned BlueZ
sender; an unrelated peer change may therefore invalidate a cursor without
authorizing any operation on that peer. There is no generation rollover.

Before a Central accepts a resolved link, its discovery owner may return the
selected device's false Connected or ServicesResolved state for explicit owned
connection handling. After that acceptance, false state or removal of the
selected adapter, device, service or characteristic terminates the generation.
NameOwnerChanged reports `:owner_changed`; it never adopts the replacement.
Metadata-only acquisition issues no link procedure. Explicit connection startup
adopts the caller's owned/borrowed mode. An initially connected device remains
borrowed even in owned mode. An initially disconnected device in owned mode
permits exactly one Connect attempt, followed by event-driven waiting and
reconciliation of Connected and ServicesResolved within the original deadline.
There is no Connect retry. A typed remote rejection does not confer link
ownership; a missing or malformed acknowledgement retains responsibility for
cleaning up this explicitly owned attempt.

An owned attempt's cleanup cancels ordinary pending D-Bus calls, submits
Disconnect to the original unique sender and exact device path, and drains
that call only within the 500 ms cooperative allowance. It then releases its
private connection, listeners and timers. A blocked Disconnect reply cannot
extend that allowance. Disconnect submission is distinct from BlueZ controller
disconnection under S02. Loss of the original D-Bus channel prevents further
method submission; cleanup never acquires a replacement sender or targets a new
BlueZ owner. Borrowed links receive no Disconnect. Explicit close joins a single
closing phase. Startup failure is reported only after this local cleanup;
cancelled queries and late replies produce no callback. Integer libdbus timeouts round
up to milliseconds, while the absolute deadline still rejects late success.

The pinned libdbus 1.16.2 [connection API](https://dbus.freedesktop.org/doc/api/html/group__DBusConnection.html)
defines the receive watermark. Its [transport dispatch condition](https://dbus.freedesktop.org/doc/api/html/dbus-transport_8c_source.html#l01129)
defines the zero-FD-watermark behavior. The [Unix ancillary-data reader](https://dbus.freedesktop.org/doc/api/html/dbus-sysdeps-unix_8c_source.html#l00547)
describes descriptor loss on truncation; the process-teardown requirement above
is the package's ownership rule for that failure.

S02 owns peer association and listener/snapshot reconciliation. The Agent1 object
is exported only for the pending explicit Pair operation; exact-peer prompts
cross IPC to the existing monitored BEAM policy worker. Native pending Agent
messages remain owned until reply/rejection. No default agent registration,
trust change, bond removal or CancelPairing is permitted. S03's write_submitted
event precedes WriteValue submission and has its exact active request ID;
loss without a received pre-submission rejection is conservatively unknown.

Ordinary pending operations, including active work and asynchronous unsubscribe
controls, have an aggregate bound of 64; live subscriptions have a separate bound
of 64. Controls overtake blocked data. If cleanup cannot acquire a pending slot,
the owner closes the session generation within C03 rather than waiting behind
ordinary work or evicting a request. The one active Pair Agent response and close
remain available without ordinary admission. C07's shared monotonic dispatch
counter and generation-bound subscription IDs are unchanged.

The Linux virtual-controller peer is the existing isolated BlueZ/btvirt design
in [virtual-controller.md](../provenance/virtual-controller.md). Its Python GATT
server is an allowed independent peer: it exports server objects to real BlueZ,
sets test stimuli and observes indication Confirm calls. It never answers native
client IPC. Its source/dbus-next hashes are fixture dependencies only; production
ELF/runtime dependency inspection must contain no Python dependency. Generic VM,
build, manifest, result and cleanup orchestration belongs to Mix/ExUnit.
The existing native SDK results concern the Python adapter baseline; they define
scenarios and do not establish execution of the accepted C++ helper.

Required implementation package WBL-P00: native host, libdbus event loop, bounded
parser/output, unchanged BEAM connection API, backend readiness, all corpus cases
and equivalent D-Bus ownership/Agent/procedure/stream regressions under sanitizers.
P01–P08 acceptance then uses that exact native binary; existing satisfied value
and Runtime behaviors need no duplicate implementation.

Primary APIs: [libdbus connections](https://dbus.freedesktop.org/doc/api/html/group__DBusConnection.html),
[pinned GATT API](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst).
