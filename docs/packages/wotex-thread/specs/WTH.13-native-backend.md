---
spec:
  id: WTH.13
  title: "Native backend, build and IPC contract"
  status: accepted
  version: 1.0.6
  owner: wotex-thread
  updated: 2026-09-18
---

# WTH.13 Native backend, build and IPC contract

This is the accepted native OpenThread target. [Current implementation and evidence](../provenance/executable-evidence.md)
are separate. This contract and the .00/.10/.11/.12 requirements jointly define
acceptance; documentation or a source archive alone is not completed software.
The explicit Mix native build now owns finite HTTPS downloads, regular-file
archive admission, exact before/after SDK fixes, a C process guardian, empty
workspace admission and content-bound manifest reuse. It replaces the generic
Python build utility. A Debian 12 arm64 build emitted the expected native ready
frame. The shared report-flow owner and BEAM ledger execute the parser and
flow_trace corpus cases through a contract driver. The host admits flow
initialization and acknowledgements with reserved output lanes, and the real
host ready case executes. The software build and run tasks pass for both BEAM
lanes on Linux arm64 and on the required Debian 12 GCC 12.2.0 x86_64 toolchain
under emulation. Native State subscriptions are the report source, and the
process-flow cases execute with a test-only callback source. The C09 lifecycle
stress cases pass on all four lanes. The live native advisory check reports one
unreviewed OpenThread advisory, CVE-2025-36939, and clean archive validation
still needs evidence, so B01–B03 are not accepted.

## WTH-B01 — Production and build boundary

The production backend is one first-party C++17 executable, `wotex-thread-host`,
started by an explicitly owned BEAM Port. It requires no Python interpreter,
Python package, shell command parser or NIF inside the BEAM. Module loading,
profile construction and pure values start no process and read no configuration.
The executable path is absolute, validated before startup, and executed directly
with separate arguments. Native runtime libraries are declared in the build
manifest; a missing or mismatched dependency fails startup.

The generic entry points are Mix tasks. These package aliases of the
`wotex.thread.*` tasks run inside `packages/wotex-thread`:

```sh
mix wotex.native.build --workspace /absolute/disposable/native
mix wotex.software.build --workspace /absolute/disposable/software
mix wotex.software.run --workspace /absolute/disposable/software
```

From the repository root, the native build runs as
`mix native.build --package wotex-thread --workspace /absolute/disposable/native`,
which dispatches the same package task.

The package tasks require exactly one `--workspace` argument. Unknown/duplicate options,
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

## WTH-B02 — Typed process boundary

C07 defines the production version-1 JSON-line envelopes. The native helper
emits exactly one ready frame before `open`; its exact backend is `openthread`
and revision is `5c8c318627954c99cd1a957a290bbd4b1027d04b`. The BEAM owner checks both. A different backend
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
1.4.0; partial native resources are owned before any blocking establishment wait.

Without credit, native callbacks enter a separately bounded queue of 64 reports
and 1048576 encoded bytes. Thread coalesces only within one event-loop iteration under S06. Distinct
iterations retain their report identity; excess queued reports terminate only
the affected stream with `:queue_overflow`.
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

### State stream frames

`subscribe_state` parameters are exactly `queue_limit`, an integer in 1..10000.
Its success result is exactly `subscription_id`, equal to the request `id`, and
`generation`, the host's next stream generation starting at 1. The reply is
written before the stream's initial report so the owner registers the stream
first. `unsubscribe` parameters are exactly `subscription_id` and `generation`;
its null success follows that stream's barrier, and an unknown or already
retired stream returns `subscription_not_found`. A registration beyond 64 live
streams returns `busy`.

A State report has exactly `version: 1`, `event: "state"`,
`session_generation`, `subscription_id`, `generation`, `report_sequence`,
`value` and `metadata`. `value` is the non-secret S02 State object and
`metadata` is exactly `changed_flags`, an unsigned 32-bit integer. The initial
report carries flags zero. SDK callbacks only accumulate flags; once per event-loop
iteration the host takes one snapshot and reports it with the OR of that
iteration's flags to every live stream. Flags observed while no stream exists
are discarded. When a stream's report cannot be queued, the host writes one
control frame with exactly `version: 1`, `event: "stream_error"`,
`session_generation`, `subscription_id`, `generation` and
`code: "queue_overflow"`, then that stream's barrier.

The BEAM owner validates every field and the credit ledger before delivery. It
delivers reports already validated for a stream ahead of that stream's terminal
error. An unknown stream, a report beyond stream or session credit, a barrier
for a stream that is neither cancelled nor terminally failed, or a malformed
field closes the IPC generation.

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

## WTH-B03 — Concrete native acceptance

[The native corpus](../../../../packages/wotex-thread/priv/fixtures/native-port-v1.json) has format
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

`test/wotex/thread/native_contract_test.exs` drives the corpus and fails unknown
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
## WTH-B04 — Existing native host and completion boundary

The production host is the C++ executable from `priv/openthread/host.cpp` and
its shared headers. `priv/openthread/dependencies.json` fixes OpenThread commit
`5c8c318627954c99cd1a957a290bbd4b1027d04b`, archive SHA-256
`90b4ce8905d21e2901b930436ed8de3abfcee95b9dfadd78528c7026564572db`,
Mbed TLS 3.6.7 commit `068ff080b369adfac81509f9b57b2afabaf82dc5`, archive SHA-256
`ca6bd316bbec49ef20088f39b8755fcaec0b7e45781506de55b17cd191ae6937`, and its
framework commit `dde0c4a0e448a0552f18817dcea633bb851fd288`, archive SHA-256
`3b0d4864fa877dc9165b90ff3d5b68505c6176c0b22d317d99fe8c89a993e9fd`.
The exact before/after hashes for the unsigned Spinel shift and full-width
Joiner discerner fixes in that manifest are mandatory. Patching a different
source or silently accepting an unpatched build is prohibited.

The Mix native build task owns the manifest/download/build work formerly held
by the generic Python utility. Generic Python protocol/process test drivers
are outside target tooling: ExUnit sends frames to the real C++ helper, and
C++ tests exercise parser/storage/SDK boundaries. OpenThread's upstream build
or generation tools may use Python with explicit manifest attribution. The
actual simulated RCP/FTD peer is a compiled upstream executable, not Python.

The native host retains its existing version-1 envelopes, openthread backend,
SDK revision, typed State/Dataset results and bounded opaque request IDs. S03's
owned RCP, interface, exclusive settings lock and guardian/reaping lifecycle are
mandatory. There is one SDK instance, one event-loop owner and no shared radio.
Callbacks use stable native contexts through completion or instance shutdown;
management acceptance and pending Dataset activation remain distinct.

P05 completes `otJoinerStart`/`otJoinerStop`: one exact typed attempt, finite
PSKd/options, terminal callback and explicit follow-up Thread enablement. Joiner
completion does not assert attachment or create a hidden interface policy.
P06 registers generation-bound State subscriptions with initial snapshot,
non-secret flags, bounded coalescing and original-owner cancellation. Callback
storage survives any already-running callback; stopped generations cannot
reappear after reuse. Default Runtime remains the read-only daemon inspection
profile. Native SDK state subscriptions are not Runtime application streams.

P07 requires a real simulated network with separate SDK/RCP owners and a separate
daemon instance. Formation, joining, management response/activation and state
reports use upstream SDK callbacks. Temperature/light workflows compose a real
CoAP software peer over explicit IPv6 routing; no Thread property protocol,
exactly-once guarantee or guessed application payload ceiling is invented.
P08 requires the full C09 lifecycle/version/package and ASan/UBSan evidence,
including both pinned source fixes and retired callback contexts. Current
partial native tests remain valid scoped evidence; they do not accept this
complete network workflow.

Primary APIs: [POSIX/RCP architecture](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/src/posix/README.md),
[pinned joiner API](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/joiner.h).
