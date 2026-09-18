---
spec:
  id: WMA.13
  title: "Native backend, build and IPC contract"
  status: accepted
  version: 1.0.6
  owner: wotex-matter
  updated: 2026-09-18
---

# WMA.13 Native backend, build and IPC contract

This is the accepted native Matter target. [Current implementation and evidence](../provenance/executable-evidence.md)
are separate. This contract and the .00/.10/.11/.12 requirements jointly define
acceptance; documentation or a source archive alone is not completed software.

## WMA-B01 — Production and build boundary

The production backend is one first-party C++17 executable, `wotex-matter-host`,
started by an explicitly owned BEAM Port. It requires no Python interpreter,
Python package, shell command parser or NIF inside the BEAM. Module loading,
profile construction and pure values start no process and read no configuration.
The executable path is absolute, validated before startup, and executed directly
with separate arguments. Native runtime libraries are declared in the build
manifest; a missing or mismatched dependency fails startup.
The POSIX process boundary requires executable `/bin/kill`, invoked directly with
separate arguments for the owned child's positive PID. Cooperative close requires
an exact null result followed by native exit status zero within the same cleanup
deadline. A non-null result is `invalid_frame`; nonzero exit is
`invalid_transport_return` with numeric `exit_status`; expiration is `timeout`.
Failed or stalled teardown terminates the child before releasing its Port
identity; closing stdin alone is insufficient.
Missing process-termination support fails before native startup. Ready, flow
negotiation and controller open share one absolute startup deadline, and open
receives only its remaining budget.

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

The test-only example peers compile with
`CHIP_CONFIG_SECURE_SESSION_POOL_SIZE=2048`. The pool is heap-backed on the Linux
target and admits the 1,133 fresh one-shot controller generations without making
the peer's unrelated LRU session eviction part of the controller-lifetime
measurement. This setting does not apply to the production controller binary.
The persistent lifecycle stress fixture also assigns separate commissioned
lighting peers to its receiver-death and read-only open/close phases. Server-side
subscription teardown can therefore finish on the first peer without occupying
the report engine measured by the second phase. Counts, deadlines and controller
resource assertions remain unchanged.

`native-manifest.json` has schema `wotex.native-build`, version `1`, package,
source_revision (the commit of the enclosing repository, or `sha256:` plus the
source digest outside a Git checkout), source_path and source_tree (the package
path in that repository and its subtree object at that commit, null outside a
Git checkout), source_files (relative path/SHA-256), upstream sources (URL,
commit/version, archive SHA-256), recursive SDK gitlink commits where applicable,
toolchain (target triple, compiler/linker/generator versions and executable
SHA-256), exact arguments/environment allowlist, build_features, binaries
(relative path/SHA-256/ELF machine/needed libraries), and audit results. No
credential, absolute consumer path or host environment dump enters this file.
Downloads are source archives from the pinned upstreams; no remote is configured.
Every required transitive SDK source is content-bound before compilation.
Build failure, an unreviewed advisory, hash mismatch or missing required tool is
nonzero. A manifest is not successful execution evidence.

## WMA-B02 — Typed process boundary

C07 defines the production version-1 JSON-line envelopes. The native helper
emits exactly one ready frame before `open`; its exact backend is `matter-native`
and revision is `250a9e6c50ee2068107f3c4808b680f5f2925415`. The BEAM owner checks both. A different backend
never triggers an implicit fallback. Framing remains UTF-8 with 131072 bytes
including newline, JSON collection depth 24, at most 1024 entries per collection and 4096
aggregate nodes. Numbers retain signed/unsigned 64-bit precision. Non-finite
numbers, duplicate keys, invalid UTF-8 and extra envelope fields fail. Parsing
must enforce bounds during traversal, before an unbounded native allocation;
nlohmann/json 3.11.3 SAX or equivalent bounded callbacks are the selected parser.
The header source and SHA-256 are fixed below.

The TLV value depth remains eight. JSON element objects, child arrays,
context-tag arrays and request/result envelopes have separate representation
depth. The 24-level frame bound admits those wrappers around the bounded typed
values, including AccessControl subjects and targets; it does not admit deeper
TLV containers. Native parser tests assert acceptance at JSON depth 24 and
rejection at 25 before operation dispatch.

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
and 1048576 encoded bytes. Matter preserves distinct reports and terminates only the affected stream with
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
resume at 50 ms, then observe through 1050 ms. `value_bytes` measures the encoded
JSON TLV element, including whitespace inside its object, separately from report
metadata and newline framing. It does not denote Matter application payload
size. The value must pass the production descriptor and delivery checks before
credit returns. Exact normalized output contains
Boolean frame_bound/byte_bound (within the specified report/control reservations),
terminal_count, deliveries_after_terminal and owned_processes_after_grace.
The runner measures actual mailbox, frame-byte and ownership counters; an absent
source/owner or missing terminal fails. These are process boundary tests, with
SDK interoperability separately required. Separate ExUnit tests suspend the actual BEAM connection,
stream owner and final receiver in turn while a native producer generates 10000
callbacks. Assert finite Port mailbox/report byte counts, one terminal, bounded
cancellation, no late generation delivery and zero owned resources. A parser
or pure flow test alone cannot satisfy these process tests.

## WMA-B03 — Concrete native acceptance

[The native corpus](../../../../packages/wotex-matter/priv/fixtures/native-port-v1.json) has format
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

`test/wotex/matter/native_contract_test.exs` drives the corpus and fails unknown
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
### Matter request identity and one-shot ownership

Native request IDs are canonical decimal positive uint64 strings in actual
submission order. Track only the greatest accepted counter; reject duplicates,
decreased/out-of-order IDs, leading zeros or overflow before SDK entry. The
reserved `close` ID remains available after counter exhaustion. Queue timers use
internal references; assigning a wire ID occurs at dispatch, including controls.
No lifetime set, rollover or automatic replay is permitted.

The target `:oneshot` Runtime profile also executes this first-party native host.
`Native.connect/1` with `lifecycle: :oneshot` returns a passive, redacted options
handle. Each admitted request owns a fresh controller process and flow generation;
reusing the handle cannot reuse a live controller. The native wire owner opens
with its persistent storage protocol and is closed before the operation returns.
The native client and named API retain .11's typed results; Runtime applies the
separate scalar projection in I03. Unsupported operations, paths, schemas and
invalid inputs fail before native process acquisition.
It opens an explicitly configured existing durable store, performs one concrete
read/write/invoke within the same total deadline, and closes/reaps its owner.
It requires `storage_mode: :open_existing`, `authority: :stored` and S02's
identity/trust options; it cannot create authority, commission or subscribe.
The persistent `:controller` profile keeps the same host and storage owner across
calls. The former Python factory option is removed from the package. There is no
fallback from failed native initialization to a Python factory.

## WMA-B04 — Native controller and credentials

The SDK is connectedhomeip v1.6.0.0 commit
`250a9e6c50ee2068107f3c4808b680f5f2925415`,
[archive](https://codeload.github.com/project-chip/connectedhomeip/tar.gz/250a9e6c50ee2068107f3c4808b680f5f2925415),
SHA-256 `83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628`.
The source archive excludes gitlink contents: the build manifest must enumerate
and hash the exact recursive commits before building; a branch name or moving
package resolver is insufficient. SDK bootstrap/generation Python is build-only.

The first-party GN executable target is `wotex-matter-host`. It links the pinned
`src/controller:controller`, `src/controller/data_model:data_model`, Interaction
Model, platform and attestation-trust-store targets, not chip-tool's text command
interpreter. Controller/commissioning/read/write support is enabled. GN flags
include `chip_config_network_layer_ble=false`, `chip_enable_ble=false`,
`chip_inet_config_enable_ipv4=true`; IPv6 and DNS-SD remain enabled for on-network
commissioning. The required crypto selection is `chip_crypto="boringssl"`, using SDK gitlink
`third_party/boringssl/repo/src` at `9cac8a6b38c1cbd45c77aee108411d588da006fe`.
Its [source archive](https://codeload.github.com/google/boringssl/tar.gz/9cac8a6b38c1cbd45c77aee108411d588da006fe)
has SHA-256 `4d0310f2d8dc2bb19598ecc46907d44a93cc3bfbde97943c0e9e34ef4f0698b8`.
Required transitive source/toolchain hashes and enabled features are mandatory
manifest entries. A passing current native dependency audit is still required;
a pinned hash alone is not a security acceptance. Python wheels are not built or packaged for production.

The uriparser transitive source uses the reviewed 1.0.2 security override at
`9b2bed92f5deecf740819f9bf27724bee2fe9c12`, archive SHA-256
`879a0c62cd34216ad1076f3f1a6b4877078ac6cb55b5b38204eb94128a1eea2a`.
The [source register](../provenance/primary-sources.md) identifies the original
SDK gitlink and fixed advisories. Every controller and software-peer build uses
this override; the manifest records its actual revision separately from the SDK.

S02's store owns `chip::PersistentStorageDelegate`,
`chip::PersistentStorageOperationalKeystore` and
`chip::Credentials::PersistentStorageOpCertStore`. The helper owns one
DeviceControllerFactory system state and one DeviceCommissioner. Initialization
supplies an explicit operational-credentials delegate, trust verifier, fabric,
vendor and controller node. `create_new` requires `authority: :generate_root`;
`open_existing` requires `authority: :stored`. These are the complete admitted
authority modes. Root and operational keys are generated with the SDK crypto
provider only after explicit creation authorization and stored durably before
commissioning. Existing authority/key/certificate mismatch is fatal. No external
factory, test issuer credentials, unknown authority mode or default fabric is
accepted. External PKI import is outside this profile.

The first-party operational-credentials delegate issues NOCs only for the exact
configured fabric and commissioning operation using its owned persisted root.
It validates node/vendor ranges and the requested identity before signing, uses
the pinned SDK certificate/crypto primitives, and has no hard-coded test key.
PAA verification uses the configured trust directory and the SDK's production
attestation verifier. A certification declaration or DAC/PAI/PAA/signature failure
cannot be accepted by a callback override. All peer fixture credentials remain
isolated from production defaults.

## WMA-B05 — SDK thread, interactions and callback lifetime

Only the SDK event-loop thread enters controller/Interaction Model APIs. The
native stdin loop queues validated commands through PlatformMgr.ScheduleWork;
callbacks enqueue bounded immutable outputs. One owner record retains request
ID, fabric/node/path, deadline, submission state and callback generation. The
aggregate ordinary pending bound is 64; live subscriptions are separately at
most 64. Close and per-subscription cancellation are admitted through a bounded
control channel; inability to schedule cleanup closes the process generation
within C03. No pending context is reused for another request.

The production service mapping is exact:

| Operation | C++ service and terminal condition |
| --- | --- |
| read/read_paths/read_events | `chip::app::ReadClient` with `ReadPrepareParams`, explicit path arrays and fabric filtering; OnAttributeData/OnEventData record every status/value; OnDone closes a finite read |
| write | `WriteClient::PutPreencodedAttribute` with the concrete DataVersion path and typed TLV; `SendWriteRequest` with remaining budget; OnResponse validates exact path/status and OnDone releases the context |
| invoke | `CommandSender` with ExtendableCallback, typed generated command or bounded pre-encoded fields, explicit timed options and response enabled; path-specific OnResponse and terminal OnDone are distinct |
| subscribe | `ReadClient` Subscribe interaction; initial callbacks may precede OnSubscriptionEstablished and require a bounded establishment buffer |
| commission_on_network | DeviceCommissioner discovery with exact long-discriminator filter, PairDevice/AutoCommissioner and final DevicePairingDelegate commissioning callback; subsequent CASE probe is required |
| open_window | `CommissioningWindowOpener::OpenCommissioningWindow`, generated PIN/salt, final callback; its temporary SetupPayload is not success before callback |

SDK callbacks copy TLV before its reader/buffer expires. Public typed values use
.11's explicit elements and the pinned generated descriptor widths/nullability;
raw codec tests separately preserve actual TLV wire widths. S01's aggregate
98304-byte encoded result budget bounds batch retention and serialization; no
1024-path allocation may multiply the per-value limit into an unbounded result. The required registry
is .11's five recipe clusters plus AccessControl and AdministratorCommissioning.
Every registry entry binds numeric cluster/member/kind to its generated schema
and supported operations. Other schemas return unsupported_schema; arbitrary
runtime code imports and dynamic class-name lookup are prohibited.

Do not destroy ReadClient from report/data/error callbacks: schedule destruction
after callback return or release at OnDone, according to the pinned ownership
contract. ReadClient.Close is private and is not an adapter API. Default recovery
is disabled explicitly; `SendAutoResubscribeRequest` is used only for native
resubscribe:true with an overridden OnResubscriptionNeeded policy enforcing S04's
five attempts/60000 ms. Path arrays survive until the SDK's deallocation callback.
Cancel detaches delivery, retires the generation and destroys its ReadClient on
the SDK thread after callback return. This releases local native state; publisher
expiry is protocol-owned and is not an immediate remote resource guarantee.

WriteClient/CommandSender callback records survive until OnDone or whole SDK
shutdown. A submitted timeout sends one unknown-effect failure, never replays,
and retains bounded retired context until native completion. A delayed callback
cannot touch a destroyed receiver or complete a different request. Full shutdown
stops admission/delivery, cancels recovery timers, drains or terminates owned
transactions on the SDK thread and shuts down the commissioner. Once the event
loop stops, the message-counter manager shuts down and the unsolicited status
handler is unregistered before factory/system-state release. Cleanup flushes
required storage and releases the lock. SDK hangs trigger owned
process termination; no in-process NIF crash can take down the BEAM.

Required packages are P01 typed registry/results, P02 native storage/authority,
P03 native controller/IPC ownership, P04–P07 interactions/subscriptions/recovery/
commissioning and P08/P08a/P09 Runtime/software proof. There is no Python
controller acceptance path. Independent example peers are pinned C++ lighting,
all-clusters and the .11 bridge fixture extension; generic tooling is Mix/ExUnit.

Primary APIs: [controller factory](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/CHIPDeviceControllerFactory.h),
[ReadClient](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/ReadClient.h),
[WriteClient](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/WriteClient.h),
[CommandSender](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/CommandSender.h),
[storage delegate](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/lib/core/CHIPPersistentStorageDelegate.h).

`result_budget` invokes the production serializer budget guard with the specified
encoded byte count. It projects exact acceptance or response_limit. Separate
callback tests must encode actual paths/TLV/Base64 up to and beyond the same
limit, including a 1024-path batch and a single large byte value; count-only
guard cases do not accept callback allocation behavior.
