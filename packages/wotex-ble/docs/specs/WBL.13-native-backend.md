---
spec:
  id: WBL.13
  title: "Native backend, build and IPC contract"
  status: accepted
  version: 1.0.22
  owner: wotex-ble
  updated: 2026-09-17
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

### Native build workspace

`mix wotex.native.build` (qualified task `mix wotex.ble.native.build`) runs only
on Linux. Before workspace mutation it resolves `cmake`, `ninja`, `pkg-config`,
`cc`, `c++`, `readelf` and `xz` from the caller's `PATH` and records each path and
executable SHA-256. The compiler's target architecture must equal the running
BEAM architecture. The libdbus source is the pinned archive in
`priv/bluez/native/dependencies.json`, transferred over verified HTTPS without
redirects within 8 MiB and 120 seconds, and admitted only as a regular-file tree
below its pinned root.

CMake and Ninja build the shared `libdbus-1.so.3` and the private-bus fixture
`dbus-daemon` with tests, documentation, systemd, GLib, X11 and pkg-config
output disabled and origin-relative build runpaths. The host is compiled from
`main.cpp` with `-std=c++17 -O2 -Wall -Wextra -Werror -pedantic` and runpath
`$ORIGIN/../lib`; the runtime guardian is compiled from `custody.c` as C11.
Every command after bootstrap runs through the packaged `build_command.c`
guardian with an explicit `HOME`, `LC_ALL`, `PATH` and `TMPDIR` environment, a
finite deadline of at most 600 seconds and a retained log.

Outputs are `output/bin/wotex-ble-host`, `output/bin/wotex-ble-guardian`,
`output/lib/libdbus-1.so.3` and `output/bin/dbus-daemon`. The audit rejects a
Python runtime dependency, an absolute runpath, a host without
`libdbus-1.so.3` through `$ORIGIN/../lib` and a library with another soname. The
host then starts once with closed input and must emit exactly the pinned ready
frame and exit with status 1. The manifest records `advisory_scan:
"not_performed"`; advisory review remains a separate release obligation. A
failed build keeps its lock and diagnostic logs and cannot be reused.

### Software fixture workspace

`mix wotex.software.build` (qualified `mix wotex.ble.software.build`) runs from
a Wotex BLE source checkout with adjacent `wotex` and `wotex-runtime` checkouts.
It requires `docker` and `cc` on `PATH` and hashes every fixture asset and the
`mix.exs`, `mix.lock`, `config`, `lib`, `priv` and `test` files of the three
packages, with modes, before mutation. BlueZ, Hex 2.5.1 and Rebar3 3.27.0 source
archives must match their SHA-256 pins. Three Linux arm64 images are built in
order through the command guardian, each within 600 seconds, with tags owned by
the workspace path: `Dockerfile.system`, `Dockerfile.bluez` and
`Dockerfile.public`. The public image compiles all three packages in both BEAM
lanes and runs `mix wotex.native.build`. It is exported to `rootfs.tar` and a
6 GiB `rootfs.raw` guest disk. `software-manifest.json` binds inputs, tools,
downloads, images, guest build evidence, the guest native manifest, logs and
artifact digests; sources that change during the build fail it.

`mix wotex.software.run` verifies that manifest read-only and never builds. For
each lane it creates a copy-on-write overlay and boots one QEMU TCG guest in an
owned container within 600 seconds. The guest runs the public BLE and Runtime
interoperability tests and the `:software` WBL-C09 lifecycle stress file with
`WOTEX_REQUIRE_SOFTWARE=1` and native selectors from its native build manifest. Owned containers are removed and counted after every
lane. A lane passes only with an exact guest success record, no kernel panic,
clean peer release, zero remaining owned containers and exactly the literal
public and stress test count passed with no other status. Every run keeps a separate
result directory and `result.json`.

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
500 ms. Both native guardians normalize SIGCHLD and the signal mask before fork. A
parent-release pipe prevents the child from executing before its process group
is established and checked. Failed pre-release admission kills and reaps only
the unreleased direct child under the existing cleanup budget; unknown reaping
or clock failure is an explicit failure. Both guardian and SDK executable paths are absolute and both SHA-256
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
`max_queue_length` option with C05's range. Every value
report includes the exact `session_generation` and a strictly increasing
unsigned-64 `report_sequence`, starting at 1 for the session. Encoded bytes
include the newline. The sender reserves frame and byte credit before stdout
submission. It retains only bounded outstanding sequence/stream/byte records.
An acknowledgement cannot cover a frame that is queued or only partly written.
No report is transmitted without both credits, and sequence exhaustion closes
the generation without rollover or replay. Terminal error controls omit
`report_sequence`, consume no report credit and participate only in the separate
finite control reservation. Their exact shape is specified in WBL.10 S04.

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
and 1048576 encoded bytes. Each queued value retains its stream ID and at most
512 decoded bytes; immutable established metadata is stored once per active
stream. Queue byte admission uses the encoded line length with a twenty-digit
uint64 sequence, an upper bound on the eventual assigned sequence length. Report
credits use the exact assigned and serialized length. BLE preserves distinct reports and terminates only the affected stream with
`:queue_overflow` before accepting an excess report.
SDK callbacks never wait for stdout. Per-stream queued reports also obey C05
queue_limit; a shared byte/frame queue limit may terminate earlier. A stream
without available credit cannot prevent another stream with sufficient credit
from progressing. Pending values preserve order within each stream, including
when a later value is smaller than an earlier blocked value. Termination retires that stream delivery generation, cancels
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

Output serialization enforces C07's tree bounds before traversal and its encoded
byte bound while writing into the serializer sink. The serializer reserves the
newline within that bound. Invalid UTF-8, binary/discarded JSON values, nonfinite
numbers and oversized output fail before queue insertion; an oversized temporary
serialized string is not the implementation of this check.

An ordinary reply reservation has an opaque owner-generation reference and a
monotonic uint64 identifier. The host acquires it before admitting work. It can
release an unused reservation or enqueue precisely one result, but cannot release
or reuse a queued reservation before the entire frame is written. Stale and
foreign-owner reservations do not change accounting. The reservation table has
at most 64 records and no lifetime history. Report and control admission use
separate counters and the byte bounds above. Report credits remain outstanding
after local stdout completion until the valid BEAM acknowledgement.

The output queue preserves whole-frame FIFO order across partial writes. Each
loop turn attempts at most 64 writes and 65536 bytes on an explicitly nonblocking
descriptor. EAGAIN retains the frame, offset and reservations without waiting;
closed or invalid output fails the channel. The executable owns SIGPIPE policy
and descriptor lifetime. Encoded-byte counters retain a partially written frame's
full storage until completion. The independent reservations do not bypass
retirement-barrier order or authorize uncredited report transmission.

A stream delivery generation is distinct from the IPC session generation.
Stream cancellation/overflow preserves other streams and the connection unless
the shared channel itself is malformed, exhausted or unresponsive. Native
retirement stops new reports, discards unsent reports and emits exactly one
control barrier: `version: 1`, `event: "stream_retired"`, `session_generation`,
`subscription_id`, stream `generation`, and `last_report_sequence` (zero if none).
A terminal error control, when present, follows the stream's preceding values
and precedes the barrier. The barrier follows every transmitted frame for that stream in stdout order;
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

`report_lifecycle` cases execute `NativeReports`, `Credits`, `NativeOutput` and
an actual nonblocking pipe. Inputs contain the explicit session generation,
established metadata, queue limit and ordered `open`, `publish`, `retire`,
`flush`, or exact `ack` events. Outputs compare native admission results, complete
decoded wire frames and frame/byte/stream counters. A rejected acknowledgement
stops the trace and records the last valid counters before teardown; it never
flushes previously unwritten output as an implicit acceptance step. Error controls
and barriers do not enter the cumulative report byte sum. These component traces
do not substitute for the BEAM process-flow cases below.

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
`agent_prompt` constructs the exact typed D-Bus method in `member`, `signature`
and ordered `body`, using fixture sender `:1.9`, destination `:1.8` and serial 31.
Its input also names the selected `device_path` and explicit `decision`. The
fixture builder admits only representable object-path/string/uint32/uint16
arguments; invalid fixture shapes fail the harness. The production Agent prompt
and decision validators produce the result. A valid result contains `accepted:
true`, `kind`, `value`, `decision_accepted` and `reply`. The reply records exact
`signature`, ordered `body`, `error` or null, `reply_serial` and `destination`.
An invalid prompt or decision projects exactly `{"accepted":false}`. Explicit
policy rejection is a valid decision with `decision_accepted: false` and the
fixed rejection error; it is not successful pairing. No daemon or Pair call occurs.
`pair_lifecycle` starts the actual private D-Bus daemon and its independent Agent
manager/device fixture, then executes the production native pairing owner. Its
input is exactly `capability` and `decision`. The fixture presents
RequestConfirmation for passkey 123456 and the selected synthetic peer. It sends
Pair completion only after the Agent reply. The result records observed method
order, challenge kind/value, Agent reply signature/acceptance, operation result,
connection state, completion count, native pending/export/reply/prompt counts,
remote Agent count, unique-sender release events and explicit Disconnect calls.
Remote Agent count changes only on an observed registration/unregistration or
the daemon's actual unique-sender release signal. Expected results remain in
ExUnit and never enter the native process. This fixture establishes D-Bus
procedure ownership; it does not establish BlueZ or controller interoperability.
`gatt_procedure` starts the actual private D-Bus daemon and an independent GATT
method receiver. Its exact input is `operation`, `parameters`, ordered octets in
`peer_value` and `response` (`ok`, `remote`, `malformed` or `held`). The receiver
validates the actual method signature, source and options; it accepts acknowledged
writes only. It encodes read bytes independently from the production decoder.
The result records observed method order, emitted events, final peer bytes,
operation result, write-submission state, connection state, completion count,
native pending calls, actual sender-release events and explicit Disconnect calls.
A successful result has a `value` key containing the canonical byte envelope for
read or null for write. Failure is the bounded native error envelope. A held
response uses a 100 ms operation deadline; expected output compares terminal
state rather than elapsed scheduling time. These vectors establish actual D-Bus
procedure ownership without claiming BlueZ or ATT interoperability.
`notify_mode` executes the production mode selector with exact `flags` and
`mode`. Success projects `requested_mode` and `effective_mode`; failure projects
one stable `error` code. `notify_lifecycle` executes the actual private D-Bus
notification owner. Inputs are `flags`, `mode`, `early_values` (at most two byte
arrays), `values` (at most 64 byte arrays), and Boolean `output_capacity`. The
independent method receiver checks original source/path and empty StartNotify/
StopNotify signatures, and emits actual PropertiesChanged messages. Its report
callback is a deterministic admission boundary; false capacity accepts no report.
The projection records method order, exact establishment result, report attempts
with full bound metadata, admitted report count, retirement/error/cancellation,
active entry/path/pending/listener counters, observed remote subscriptions,
connection state and actual sender releases. These component vectors do not
represent Port transmission or replace the process-flow vectors above.
`serialize_frame` runs the production bounded serializer with exact JSON `value`
and integer `limit` in 1..131072. Success projects `accepted: true`, the complete
UTF-8 `line` including its newline, and its encoded `bytes` count. Failure projects
exactly `accepted: false`. Key order is lexicographic, output is compact, valid
non-ASCII UTF-8 remains UTF-8, and required JSON escapes are included in the byte
bound. This operation performs no SDK or descriptor I/O.
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
once. Optional local pending-call tickets bind an opaque connection-generation
reference and a strictly increasing uint64 counter. Canceling a ticket removes
only that pending reply; stale, completed, foreign-generation and default tickets
do not affect another call. Ticket cancellation cannot retract a transmitted
method or attest its remote effect. Active records have the existing 64-call
bound; there is no historical ticket registry or counter rollover. A cancelled
post-establishment discovery refresh detaches its exact pending query and callback
while preserving the established connection and existing subscriptions.
Never block the only event loop in send_with_reply_and_block. Configure
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
messages remain owned until reply/rejection.

Local method exports bind one exact object path and interface to the selected
BlueZ unique sender and this connection's unique destination. At most 64 active
exports are admitted; duplicate routes fail. Their positive uint64 registration
counter never rolls over, and removal retains no tombstones. Foreign senders
receive only `org.bluez.Error.Rejected` with no message body. A no-reply request
receives no response and reaches no policy callback. Unsupported members,
signatures and peer/challenge values are rejected by the Agent operation.
Callbacks do not block the shared event loop and may remove their own export.

Agent method returns admit only an empty body, uint32 passkey in 0..999999, or
1..16 printable ASCII PIN bytes. Method errors admit only the fixed rejection
name and an empty body. All response headers are bounded D-Bus fields; no
object path, interface, member, sender, descriptor or diagnostic text is admitted
in a response. Each encoded response is below 1024 bytes. Two responses can wait
in the native owner's queue; at most one additional response is submitted to
libdbus until `dbus_connection_has_messages_to_send` reports an empty outgoing
queue. Full response admission fails `:resource_limit` and ends the affected
session. The SDK's approximate outgoing byte counter is not an allocation bound.
Closing releases queued replies and active export records. Pipe/guardian cleanup
remains required when the native process or selected daemon stops making progress.
The signatures follow the [pinned BlueZ Agent API](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Agent.rst).

Prompt decoding admits exactly S02/.11's seven request kinds and their D-Bus
signatures. The first object path must equal the selected device path byte for
byte. PIN/passkey/display progress and service UUID values are bounded before
copying. A prompt retains its original method request until one explicit valid
answer or rejection; no caller-supplied replacement request can redirect its
reply. A valid decision consumes that request ownership, and a second answer
fails `:pairing_rejected`. Invalid decisions cannot produce a method return;
the pairing owner rejects and tears down according to S02. The pure prompt
boundary does not read a clock or infer policy. The operation owner enforces
the absolute deadline and challenge ID before invoking it.

The pairing owner derives its peer from the connection's immutable validated
identity. A stale discovery snapshot is reconciled before Agent registration.
Registration precedes Pair on the same unique sender, and its acknowledgement
is required before Pair submission. The supported capability names are exactly
`NoInputNoOutput`, `DisplayYesNo` and `KeyboardOnly`; there is no empty/default
capability. Agent paths use the owning session's accepted positive uint64 request
counter. Challenge IDs contain that counter, a colon and a positive uint64
per-attempt prompt counter, at most 41 ASCII bytes. The shared C07 request counter
prevents path/challenge reuse within a session; neither counter rolls over.

At most one prompt awaits an explicit decision. Its response parameters contain
exactly `challenge_id` and `decision`. A foreign sender reaches no policy callback;
a wrong peer, overlapping prompt, expired or wrong challenge, unsupported method,
invalid decision or unavailable event capacity rejects pairing. Cancel and Release
acknowledge their empty method bodies, reject any owned prompt and finish the
attempt. Release identifies an already removed registration. Pair success while
a policy prompt is still pending is invalid. Success requires both Pair completion
and verified Agent unregistration before the interaction deadline.

Local exports and retained prompts are detached before cleanup waits. Unregistration
uses at most half the remaining cooperative cleanup allowance, reserving the rest
for connection closure. The same absolute deadline is passed into that closure;
repeated cancellation and destruction cannot restart it. Unknown registration or
Pair completion, failed unregistration and capacity exhaustion close this unique
sender. Exact remote Pair/RegisterAgent errors complete the corresponding pending
call; they do not attest that no remote state changed. Unknown-effect Pair errors
follow C04, remain non-retryable and must receive permanent Runtime classification
when projected through a public error boundary. Late replies never revive an attempt.

Native failures preserve only fixed library codes and the S03-admitted BlueZ error
name. Known BlueZ names map to the corresponding stable code; unknown admitted
names use `remote_error`. Unadmitted names and diagnostic bodies are omitted.
Unexpected local diagnostic text normalizes to `transport_error`, never to an IPC
string supplied by the operating system or SDK. The operation signatures follow
[AgentManager](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.AgentManager.rst)
and [Device](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Device.rst)
at the pinned BlueZ revision.
No default agent registration,
trust change, bond removal or CancelPairing is permitted. S03's write_submitted
event precedes WriteValue submission and has its exact active request ID;
loss without a received pre-submission rejection is conservatively unknown.

A read or write resolves an immutable typed address against a refreshed snapshot
before GATT submission. Its exact address fields are `service`, `characteristic`,
`object_path`, `handle` and `generation`. UUIDs use .11 normalization; optional
selectors are null or a valid D-Bus object path of at most 4096 bytes, uint16 handle
in 1..65535 and uint64 discovery generation. Booleans and floating-point values
are not integers. Every supplied selector must match the same characteristic;
a stale generation, no match and multiple matches have distinct stable errors.
Malformed address/value/parameter fields fail before discovery or GATT I/O.

Read admits the `read` flag and sends ReadValue with an empty options dictionary.
Write admits the `write` flag and sends WriteValue with precisely `type: "request"`
as a string variant and `offset: 0` as a uint16 variant. A
`write-without-response` flag does not authorize this procedure. Attribute bytes
are bounded to 512 octets before native copying; empty and maximum-length values
are valid. A successful read requires exactly `ay`; the fixed array length is
checked before copying and encoding the canonical byte envelope. Write success
requires an empty acknowledgement and returns null. There is no implicit readback,
command-mode fallback, offset continuation or retry. Explicit readback is a
separate read operation with a separate deadline.

The write-submission event is admitted before WriteValue. Unavailable event
capacity or cancellation during event delivery prevents the call. Once submitted,
a lost or malformed acknowledgement remains an unknown-effect mutation under
C04. Operation timeout, malformed reply, selected-owner loss or unusable transport
closes this connection generation within the existing cooperative cleanup budget;
late replies cannot deliver a second completion. Bounded explicit remote errors
preserve their admitted name and require no automatic retry. Ordinary borrowed
link teardown sends no Disconnect; owned-link cleanup retains the same absolute
deadline even when a GATT reply and Disconnect are both withheld.

Ordinary pending operations, including active work and asynchronous unsubscribe
controls, have an aggregate bound of 64; live subscriptions have a separate bound
of 64. Controls overtake blocked data. If cleanup cannot acquire a pending slot,
the owner closes the session generation within C03 rather than waiting behind
ordinary work or evicting a request. The one active Pair Agent response and close
remain available without ordinary admission. C07's shared monotonic dispatch
counter and generation-bound subscription IDs are unchanged.

One notification manager routes source-checked PropertiesChanged signals to
at most 64 active characteristic records. It uses one local listener alongside
discovery's listeners, independent of the number of subscriptions. Each record
retains the original characteristic path, discovery metadata, requested/effective
mode, pending-call ticket and one early byte value. Duplicate characteristic
admission cannot remove or retarget an existing record. Initial establishment
has no synthetic read; S04 governs acknowledgement-before-value ordering and
the early-value overflow error.

Value decoding requires an actual byte-array variant and copies at most 512
octets after inspecting its fixed-array length. Notifying requires a Boolean
variant. Invalidated Value, malformed admitted fields, identity metadata change
and notification loss terminate the affected record under S04. Unknown
properties remain bounded by the ObjectReader envelope and produce no value.
A repeated equal Value is a distinct report. The report callback performs
nonblocking admission into the host's credit/output layer; failure is
`queue_overflow`, never silent loss. Component callbacks do not write stdout;
only the enclosing host supplies the mandatory IPC generation, sequence and
frame/byte reservation before transmission.

Cancellation first disables report delivery and retires its pending StartNotify
reply or owned discovery refresh. StopNotify uses the same original sender/path
and an independent pending-call ticket, so it can complete while an unrelated
ReadValue remains blocked. Verified StopNotify releases the entry/path/listener
before local cancellation completion. Failed, malformed, capacity-blocked or
stalled StopNotify closes the owned connection within the same cleanup deadline.
An explicit remote StartNotify rejection creates no cleanup method; an unknown
StartNotify outcome retains cleanup ownership. No terminal callback or late
reply can revive a retired record. The enclosing host applies the stream-retired
barrier and normal cumulative credit retirement specified above.

The Linux virtual-controller peer is the existing isolated BlueZ/btvirt design
in [virtual-controller.md](../provenance/virtual-controller.md). Its Python GATT
server is an allowed independent peer: it exports server objects to real BlueZ,
sets test stimuli and observes indication Confirm calls. It never answers native
client IPC. Its source/dbus-next hashes are fixture dependencies only; production
ELF/runtime dependency inspection must contain no Python dependency. Generic VM,
build, manifest, result and cleanup orchestration belongs to Mix/ExUnit.
Earlier virtual-controller results for the retired Python adapter define
scenarios only; they do not establish execution of the accepted C++ helper.

Required implementation package WBL-P00: native host, libdbus event loop, bounded
parser/output, unchanged BEAM connection API, backend readiness, all corpus cases
and equivalent D-Bus ownership/Agent/procedure/stream regressions under sanitizers.
P01–P08 acceptance then uses that exact native binary; existing satisfied value
and Runtime behaviors need no duplicate implementation.

Primary APIs: [libdbus connections](https://dbus.freedesktop.org/doc/api/html/group__DBusConnection.html),
[pinned GATT API](https://github.com/bluez/bluez/blob/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.GattCharacteristic.rst).

## Native live peer health

The native `health` operation has empty parameters and uses the same bounded
operation owner as acknowledged GATT procedures. It sends
`org.freedesktop.DBus.Properties.GetAll("org.bluez.Device1")` to the original
Device1 path and pinned BlueZ unique sender. It does not infer health from a
cached discovery result or a successful characteristic read. No radio scan,
reconnect, pairing or GATT rediscovery is required by this query.

The reply is exactly `a{sv}`. Decode at most 256 unique property names, each a
valid D-Bus member name. Required Adapter/Address/AddressType values have their
native object-path/string types and pass the peer constructor's bounds;
Connected/ServicesResolved are native booleans. Normalize the address before
comparing all three identity fields with the original peer. Unknown property
values stay inside the bounded libdbus message and are not copied into JSON.
Duplicate names, missing fields and wrong types fail `invalid_response`; a valid
changed identity fails `peer_changed`, false state fails `disconnected`, and the
property-count ceiling fails `object_limit`. These failures close the owned
sender through its existing cleanup path. A typed remote permission error
preserves a usable sender. Borrowed cleanup emits no Device1.Disconnect.

The success value is exactly `{"connected":true,"services_resolved":true}`.
The request's original absolute deadline bounds reply validation and cancellation;
a late response cannot complete it twice or turn a timeout into success. Health
attests neither GATT permissions nor encryption/MITM protection. These fields
follow the pinned [Device1 API](https://raw.githubusercontent.com/bluez/bluez/2123ab772fbe97d1369fc9e179ea87c3469cf98f/doc/org.bluez.Device.rst)
and [D-Bus specification 0.43 Properties interface](https://dbus.freedesktop.org/doc/dbus-specification.html#standard-interfaces-properties).

`peer_health` corpus cases construct independently typed D-Bus replies from the
input name/signature/value list, or deliberately withhold/send a remote error.
They execute the production native operation and compare its value, closed error
envelope, actual GetAll calls, observed unique-sender releases and Disconnect
calls. The fixed missing-reply case uses a 100 ms operation deadline. These
cases are private D-Bus component evidence; the complete BEAM/Port health route
requires the first-party host and artifact admission.


## Native discovery page ownership

Discovery pages expose the validated, ordered snapshot of WBL-B04. A request has
only optional `cursor` (null or 32 lowercase hexadecimal characters) and `limit`
(integer 1..64, default 64). The host validates the cursor against its own bounded
ledger before a D-Bus refresh. A continuation uses its immutable generation;
metadata invalidation fails it before I/O. A request without a cursor obtains a
stable current snapshot before constructing its first page.

The owner retains at most 1,024 token records, each binding one generation and
nonzero offset. Repeated requests for that position reuse the token. At capacity,
it evicts the lowest generation and then the lowest offset. It never evicts a
current-generation token; a snapshot contains at most 1,024 characteristics and
therefore at most 1,023 continuation offsets. Known retired-generation tokens fail
`stale_discovery`. Unknown, evicted or foreign tokens fail `invalid_cursor`, even
when the current snapshot is stale. Both errors require the caller to restart
without a cursor. Generation counters cannot roll over or decrease.

The host explicitly supplies 16 bytes from the operating system random source for
each token; tokens are opaque identifiers, not credentials. The pure paging
component receives this source as a callback. Invalid source output or eight
consecutive collisions fails `resource_limit` without evicting any token. No
lifetime count or unbounded issued-token set is retained.

A page contains `generation`, ordered `characteristics`, and a nullable next
`cursor`. It admits at most the requested count. Each candidate is encoded in the
complete C07 success envelope with the actual request ID, including its newline,
so the 131,072-byte and JSON structure limits apply to the aggregate reply. A
smaller page may be returned to fit these bounds. If one characteristic cannot
fit, the result is `response_limit`; no token is issued for the failed page.
A continuation offset outside the current immutable snapshot is an invalid
response. Page construction does not perform D-Bus I/O or allocate a second full
snapshot.

The `discovery_page` vectors WBL-B-F56 through WBL-B-F58 supply exact
characteristics and ordered request events. Each event names its result; a cursor
object `{"result": "name"}` references that earlier result's cursor. All other
parameters are passed unchanged to the pure request constructor. The result
projection contains each page or fixed error, retained token count and random
source call count. The deterministic fixture source emits increasing uint64
integers as zero-padded, 32-character lowercase hexadecimal tokens.

The `discovery_cursor_ledger` vectors WBL-B-F59 and WBL-B-F60 issue the first
one-characteristic page of a supplied two-characteristic snapshot for each
generation 1 through `generations`. Each snapshot's characteristic generation
matches that iteration. The input then supplies exact cursor lookups and stale
flags. The projection contains the lookup offset or error and the same ledger
and random-source counters. These vectors execute production paging and token
ownership; they do not imply complete native host or BEAM discovery routing.


## Native SDK host dispatch

The SDK executable accepts no command-line arguments. Its configuration arrives
through C07 after the exact ready and flow initialization exchange. The process
owns stdin/stdout in nonblocking mode, one bounded partial line, and one explicit
private BlueZ sender. The reference Linux token source is one 16-byte
`getrandom(..., GRND_NONBLOCK)` call; a short result or error fails token admission.
This choice follows [Linux man-pages 6.18, getrandom(2)](https://man7.org/linux/man-pages/man2/getrandom.2.html).
The separately evidenced Darwin development lane uses `getentropy`.

Requests reserve one of the 64 aggregate reply slots before entering SDK work;
the slot remains occupied through complete stdout transmission. Ordinary
operations dispatch serially in received order. Pair policy replies and
unsubscribe controls use the same monotonic dispatch counter and aggregate
admission bound, but do not wait behind an ordinary operation. Every queued
request retains its own absolute deadline and expires independently of an
active request. Exhausted admission or malformed/replayed protocol input closes
the process channel. The close request uses its separate finite control
reservation and remains admissible when all ordinary slots are held.

The host composes discovery, GATT procedures, Device1 health, pairing and
notifications with the bounded output and report-credit owners. A subscription's
successful reply is queued before its first value report. Subscription cleanup
retires report credit records through the defined cumulative ACK and FIFO
barrier, including when another read is blocked. An explicit close cancels
unfinished StartNotify work as well as established streams, rejects pending
Agent prompts, unregisters owned Agents, and closes only the owned sender/link.
All cooperative SDK cleanup shares one deadline of at most 500 ms. Remaining
SDK or output work after that deadline yields a failing process status. The
separate runtime guardian owns the remaining forced-cleanup budget; the SDK host
does not claim to reap itself or recover a blocked native call.

Each loop turn reads at most eight 8,192-byte input fragments. The bounded output
writer independently limits its writes. Idle poll intervals are at most 5 ms;
queued request and closing deadlines further shorten that wait. Malformed input,
stdin loss, output loss, SIGTERM and SIGINT initiate bounded cleanup. Arbitrary
exception text never enters stdout or stderr. Successful explicit close emits
its final null result and exits zero after complete output transmission.

The `native_host` vectors WBL-B-F61 through WBL-B-F63 execute the actual SDK
binary and a separate private D-Bus service. `parameters.bus_address` contains
exactly `$PRIVATE_BUS`, resolved to that fixture's private bus address; all other
parameters are passed unchanged. The modes are `normal` (open, discover, close),
`open_eof` (withhold ObjectManager's reply, then close stdin), and
`duplicate_flow` (send the exact initialization twice). Results contain the
actual ready frame, complete discovery page where applicable, process status,
snapshot/Disconnect counters and independent NameHasOwner checks for the
released client sender and retained service sender. No sender identity is
fabricated or normalized into a success value.


## Explicit native artifact selectors

The persistent native selector set contains exactly `executable`,
`executable_sha256`, `guardian` and `guardian_sha256`. Pure construction accepts
keyword options or revalidates the corresponding typed selector value. Missing,
extra, duplicate, malformed and forged fields return `invalid_options` with
field `native_artifacts`; this phase performs no filesystem I/O. Paths and digest
strings use WBL.10's exact bounds. Inspection exposes digests, never paths.

Explicit verification reads the SDK and guardian sequentially under one supplied
signed-64 BEAM monotonic millisecond deadline. Deadline equality is expired and
returns `timeout`. Each file must be a nonempty executable regular file of at
most 67,108,864 bytes; a final symlink is not admitted. Missing, unreadable,
non-executable, oversized or non-regular files return `transport_unavailable`.
SHA-256 hashing uses 65,536-byte chunks and checks the original deadline before
each read and after final identity validation. No descriptor remains open after
verification.

Admission compares inode, device, size, mode, modification time and change time
between the initial lstat, the opened descriptor before and after hashing, and
final lstat. A digest or identity mismatch returns `incompatible_backend` with
permanent classification. The error field is `executable` or `guardian`; no path,
file content or operating-system diagnostic enters details. Both verifications
must succeed before any native process is started. A monitored startup worker
must retain the original owner and deadline while filesystem work is pending.

These checks require immutable consumer deployment files. Later path-based
execution is not atomic against adversarial replacement, including mutation by
another process of the same operating-system user. System loader and dynamic
library identity remain explicit deployment and build-manifest concerns.
Verification does not provide a signature or independent build-provenance claim.

`native_artifact_selectors` vectors WBL-B-F64 through WBL-B-F67 encode keyword
options as ordered `[name, value]` pairs, preserving duplicates. The runner maps
only the four declared names to their fixed atoms and invokes pure construction.
The exact result is `accepted: true`, or `accepted: false` with the fixed code
and field. The nonexistent fixture paths are intentional: accepted selector
syntax proves no filesystem or executable availability.
