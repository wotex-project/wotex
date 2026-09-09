---
spec:
  id: WBL.13
  title: "Native backend, build and IPC contract"
  status: accepted
  version: 1.0.0
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
The header source and SHA-256 are fixed below.

Request parameters and results have the exact operation-specific shapes in .10
and .11. No native pointer, process address or foreign object name crosses IPC.
Bytes use the exact canonical Base64 envelope from C07 and obey the owning
protocol's decoded-size bound. Only fixed library error codes and admitted
numeric status/error-name fields cross the boundary; native exception text,
credentials and values do not. Unknown mutation effect remains non-retryable
and maps to permanent Runtime classification. A late native result cannot turn
an expired request into success.

The native event loop keeps stdin and framed output nonblocking. Its report
output backlog is at most 1048576 bytes, with the separate control reservation
below; overflow terminates the owned generation
and releases its resources. Logs use a separate sink. EOF, owner death, bad
framing and deadline escalation share the cleanup path. The owner allows C03's
1000 ms local cleanup grace, then terminates and reaps its own native process
and descendants. Neither graceful close nor timeout claims remote rollback.
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
`wotex.native-contract`, version `1.0.0`, and `specified_unexecuted` status.
It supplements the .11 value/lifecycle and .12 Runtime corpora. Every case names
an operation, exact input and exact normalized expectation. `line_utf8` includes
the terminating newline when one is required. `parse_request` calls the shared
production frame/request validator without SDK I/O and projects either
`{"accepted":true}` or `{"accepted":false}`; it is not a fabricated protocol
response. The native contract-test binary receives input only. ExUnit reads the
expected projection and compares the independently observed result.
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
received message size at 4 MiB and aggregate receive storage at 8 MiB, then apply
S01 object/catalogue bounds while decoding ObjectManager replies. The single
private connection supplies the unique sender for open, discovery, Agent1,
ReadValue, WriteValue, StartNotify and StopNotify. It closes and unreferences
only its own connection.

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
