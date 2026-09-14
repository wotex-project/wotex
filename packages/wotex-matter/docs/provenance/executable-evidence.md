# Executable evidence

The implemented profile includes concrete and wildcard read paths, bounded
TLV, the P01 descriptor/report/batch-result value layer, P02 durable SDK
storage, the P03 first-party persistent controller owner, and P04 finite
Interaction Model reads, event reads, writes, invokes and Descriptor discovery.
P05 adds bounded native attribute/event subscription delivery and cancellation.
P06 adds bounded, explicitly selected subscription recovery and delivery-generation
retirement. P07 adds filtered commissioning, final CASE confirmation, generated
enhanced-window material and typed operational ACL values.
P08 adds typed Runtime request and stream projection. P08a adds explicit Runtime
profiles, classified failures and public ConsumedThing integration.
The earlier one-shot Python factory adapter remains an injected baseline.
The P09 ACL cohort below executes commissioning and typed ACL operations against
a pinned SDK example peer. Remaining software workflows are separate P09 evidence.

## Developer gate

`WOTEX_PATH_DEPS=1 mix check --no-retry` runs warnings-as-errors compilation,
formatting and the behavioral test suite. Runtime path dependencies require the
explicit switch; the archive preserves ordinary Hex dependency declarations.
Strict Credo, dependency audits, Dialyzer, Doctor, ExDoc, coverage, packaging,
out-of-tree compilation, Application-free loading and native builds are
separate release or packet evidence. The pinned Decimal parser regression
remains active; there are no advisory waivers. See `SECURITY.md` and the
dependency-security test.

## P09 reproducible build tasks

`mix wotex.native.build --workspace ABS` and `mix wotex.software.build
--workspace ABS` use the checked-in Mix runner and
`test/support/software/sources.json`. They require one absolute empty workspace
or a verified matching receipt. Seven deterministic build tests exercise exact
argument admission, symlink ancestors, unrelated/locked directories, artifact
and log tampering, duplicate JSON members, bounded command output/timeouts,
caller-death termination, environment isolation and project-root validation.
Both build task modules are covered through their public task entry points.

The complete software build passes on 2026-09-14 with the pinned Debian 12
Linux x86_64 native lane: GCC 12.2.0, CMake 3.25.1, Ninja 1.11.1, GN
2255 (97b68a0bb62b) and the recorded ZAP executable. It compiles normal and
ASan/UBSan controllers, passes all six native CTest executables in both modes
with leak detection, and builds lighting, all-clusters and bridge peers.
Eight native source commit queries and eight build-only Python version queries
return no OSV advisories. The runner checks ELF architecture and runtime
linkage, records exact commands/tool hashes and removes its owned build
container before writing a ready workspace receipt. No build container remains.

Both tasks successfully reuse this software workspace by verifying all source,
binary, manifest and log hashes. An earlier workspace with changed source
identity fails with `manifest_mismatch`. Build results identify:

| Build artifact | SHA-256 |
| --- | --- |
| source file set | `6d80d3429ddfa419038d2cf4148086d28cdbce16edc56a298504095aa774fbcd` |
| native manifest | `9cd31b77d93f9a183fb49a8f827601918cb08ca4f193e940c9f65218673ba8a2` |
| native controller | `2acc3532909f26c8bbe5c07a895c6bc0caba73abd6553ab5a1d76488a983dc97` |
| sanitizer controller | `0558c07f1a96f4d4214555c0ff0aac648f7117aa9911f4db6aee64d806436699` |
| lighting peer | `5d0c28f58af14c25569ef08c13bbea51b6dd853e5e46c684dc20fdbc3faa32c0` |
| all-clusters peer | `3f1f898ed77d6d707483163d25586dbf9fe9eadf8d00b1795b815fa0fd62be7e` |
| bridge peer | `402b58988806e04874cfd719e60932cc3734107700f658a9310a2df157801c11` |

The manifest records the contemporaneous Git revision and the exact source
file hashes, including the build task files. The source package includes the
native unit sources and build assets and passes out-of-tree Elixir compilation.
This is compilation, native-unit and build-ownership evidence. Its manifest
explicitly records protocol interoperability as `not_executed`.
`mix wotex.software.run`, complete peer workflows and the remaining P09 gates
are still required.

## P09 ACL and framing cohort

On 2026-09-14, `test/interop/native_acl_test.exs` passes against an owned
Linux x86_64 all-clusters example from connectedhomeip
`250a9e6c50ee2068107f3c4808b680f5f2925415`. The controller commissions a fresh
peer with explicit fixture PAA trust, requires final CASE establishment, writes
three ACL entries whose typed TLV exceeds 64 bytes, and reads back the exact
subjects, nullable fields and nested targets. A subsequent acknowledged ACL
write removes the controller's access; the next read returns remote status
`0x7e`. The test disconnects its BEAM owner. The owned peer container is removed
after each run. This is shared-SDK software-peer evidence, not independent-stack
interoperability or certification.

The same ExUnit case passes under Elixir 1.20.2 / OTP 29.0.4 and Elixir 1.18.4 /
OTP 27.3.4.15, with the native controller and peer running in Linux containers.
The BEAM runs on macOS arm64 in these two executions. Each has fresh peer and
controller state. The minimum-runtime default suite separately passes 85 checks
(2 doctests, 1 property and 82 selected tests), with seven interoperability tests
excluded. The current-runtime `WOTEX_PATH_DEPS=1 mix check --no-retry` also passes
those 85 checks. An earlier concurrent run exceeded two fixture-start deadlines;
the isolated gate passes without deadline or exclusion changes.

The selected case command is:

```sh
WOTEX_PATH_DEPS=1 WOTEX_MATTER_NATIVE_ACL_FIXTURE=/absolute/fixture.json mix test test/interop/native_acl_test.exs --include interop --include software
```

The same selected case also passes with both BEAM and native processes running
inside Linux x86_64 containers against source revision
`3ae87ae` and the rebuilt binary hashes above. Each lane has fresh controller
and peer state, exact runtime-version probes, one passing case and a native
process absence check after disconnect. Both owned fixture containers are
removed and absent after execution. The two content-pinned Hex project images
are:

| BEAM lane | Image index SHA-256 |
| --- | --- |
| Elixir 1.18.4 / OTP 27.3.4.15 | `473f77ee88977dc8cc5d05fb91080a308be86be3fc27d50aef9a837d07c8268b` |
| Elixir 1.20.2 / OTP 29.0.4 | `5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da` |

Both use Debian bookworm `20260713` from the
[Hex project image registry](https://hub.docker.com/r/hexpm/elixir), with
`procps`, `libglib2.0-0`, `libasan8` and `libubsan1` installed for the test tools
and declared native linkage. Docker executes the x86_64 lane under host
emulation. The fixture explicitly sets `ERL_FLAGS="+JMsingle true +S 4:4"`;
[Erlang documents single JIT mapping](https://www.erlang.org/doc/apps/erts/erl_cmd.html)
for emulators that cannot handle dual mapping. This is an identified emulated
Linux ACL lane; broader Linux peer/stress and immutable-package acceptance
remain open.

The fixture supplies a caller-selected executable, fresh controller storage,
vendor/fabric/controller identity and PAA directory under `controller`, plus
the owned peer's `node_id`, `setup_pin` and `discriminator`. The runner owns and
removes this disposable peer; the test intentionally removes its controller's
ACL access and must not target an operational device.

`test/native/interaction_test.cpp` reproduces the former native parser rejection
of a nonempty ACL subjects list. Native framing now admits up to 24 JSON
collection levels while retaining the eight-level TLV bound. The request
envelope, element objects and child arrays require separate representation depth.
`test/native/controller_test.cpp` asserts the 24/25 boundary.
`test/wotex/matter/native_frame_test.exs` checks the corresponding BEAM boundary,
aggregate keys/values, collection size, duplicate keys, UTF-8, integer precision
and encoded byte limits. The persistent-owner test rejects duplicate ready
fields before returning a handle. These are the executable basis for the
WMA.00/WMA.13 representation-depth correction.

`WOTEX_PATH_DEPS=1 mix run bin/check_p07_native.exs` rebuilds both complete native
controller variants with the uriparser 1.0.2 security override and passes all six
CMake executables normally and under ASan/UBSan with leak detection. The actual
SDK lifecycle lane also passes its 1000 operations, 100 open/close cycles,
32 concurrent owners, storage fault cases and EOF cleanup checks. These lifecycle
operations do not replace the still-required peer interaction stress tests.
Correct OSV commit queries for the seven native source pins and version queries
for eight build-only Python artifacts return no advisories in this execution.

| Cohort input or artifact | SHA-256 |
| --- | --- |
| native protocol source | `bc5314889c043459fd118fa0b62a35e9f8bd40bc6ae54cb3999d0b4618d19541` |
| native controller source | `d75169bf54c373fd7e77926947f03b67533c98bcc61d4104fd0e85a69b532d5d` |
| native interaction test | `a07662cbe366f8e2067de4363101d3a529af02b7d25f0abfd8ec00cb5739d415` |
| BEAM frame test | `cbd4bde51ec6d94a4156e22dbd45c3bd732479d23252fd1d6fbdfad72b54d66c` |
| ACL peer test | `8392494d28132706ce3132daba9de393f9ec2177aa784318fb565fbad07aa93a` |
| native controller | `2acc3532909f26c8bbe5c07a895c6bc0caba73abd6553ab5a1d76488a983dc97` |
| sanitizer controller | `0558c07f1a96f4d4214555c0ff0aac648f7117aa9911f4db6aee64d806436699` |
| all-clusters peer | `3f1f898ed77d6d707483163d25586dbf9fe9eadf8d00b1795b815fa0fd62be7e` |

This cohort does not accept all of P09. The complete reproducible software
runner, lighting/thermostat/bridge workflows, negative commissioning matrix,
peer interaction/subscription stress, Linux BEAM matrix and immutable archive
consumer remain required.

## P01 native value evidence

`elixir bin/check_p01_native.exs` runs outside the developer gate. It uses the
content-pinned `node:24-bookworm` container as a Debian 12 environment, selects
Linux x86_64, and requires G++ 12.2.0, CMake 3.25.1 and Ninja 1.11.1. It compiles
`native/src/value.cpp` with C++17 and warnings as errors, then runs
`test/native/value_test.cpp` in normal and AddressSanitizer/
UndefinedBehaviorSanitizer builds. Both variants pass. This proves the P01 pure
descriptor and conversion unit; it does not prove SDK linkage, IPC, controller
ownership or interoperability.

## P02 durable storage evidence

`elixir bin/check_p02_native.exs` runs outside the developer gate in the same
pinned Debian 12/Linux x86_64 environment. It verifies the connectedhomeip
`250a9e6c50ee2068107f3c4808b680f5f2925415` archive, the exact nlassert/nlio
gitlink archives and nlohmann/json 3.11.3 before compilation. The production
storage class derives from the pinned `chip::PersistentStorageDelegate`; the SDK
binding compiles calls to `PersistentStorageOperationalKeystore::Init` and
`PersistentStorageOpCertStore::Init` with that delegate.

`test/native/storage_test.cpp` passes normal and ASan/UBSan builds. It observes
create/open authority combinations, exact fabric/controller/vendor identity,
exclusive locking, 0700/0600 permissions, opaque empty/binary/65535-byte values,
SDK short-buffer semantics, durable restart and delete behavior, malformed,
duplicate, noncanonical Base64, extra-field, 4096-key, 16 MiB and symlink
boundaries. Forked children terminate at every temporary-write, fsync, intent,
rename and directory-fsync checkpoint. An incomplete commit cannot reopen stale
state; state past the durable rename boundary retains the written value. A
commit failure poisons the live owner.

`elixir bin/check_p02_advisories.exs` separately submits Open Source
Vulnerabilities (OSV) GIT queries for the exact connectedhomeip, nlohmann/json,
nlassert and nlio revisions. The recorded P02 run returned no advisories for
those revisions. This is a live result at execution time, not a guarantee about
future disclosures or unqueried transitive sources.

## P03 first-party controller evidence

`WOTEX_PATH_DEPS=1 mix run bin/check_p03_native.exs` reconstructs the controller
build in a disposable pinned Linux x86_64 container. It verifies the
connectedhomeip, Pigweed, BoringSSL, nlassert, nlio, uriparser and nlohmann/json
contents; exact GN, ZAP and build-only Python inputs; and the C++17 first-party
target. GN links `src/controller/data_model:data_model`, keeps IPv4, IPv6 and
DNS Service Discovery enabled, disables Bluetooth Low Energy, selects
BoringSSL, and routes SDK logs away from stdout.

The lane builds the complete SDK host both normally and with ASan/UBSan. Its
CMake executables also pass in normal and sanitizer modes. The actual host
then exercises new authority generation, controller health, exact durable
reopen, identity mismatch, invalid Product Attestation Authority trust,
incomplete-start fail-closed behavior, authority corruption, an active storage
lock, EOF cleanup within 1000 ms, and reopen after EOF. WMA-F07 rejects a wrong
fabric before SDK entry. The load lane
runs 1000 sequential operations, 100 controller open/close cycles and 32
concurrent process owners without shared `/tmp/chip_*` state. The sanitizer host
also executes successful startup, failed startup and EOF cleanup with leak and
undefined-behavior failure enabled.

`test/wotex/matter/persistent_bridge_test.exs` separately runs on
Elixir 1.18.4/OTP 27.3.4.15 and Elixir 1.20.2/OTP 29.0.4. It checks exact ready
identity, fresh flow generations, request correlation, malformed request
rejection, explicit close and creating-process ownership. Its executable fixture
tests BEAM Port behavior only; it is not SDK evidence.

`WOTEX_PATH_DEPS=1 mix run bin/check_p03_advisories.exs` submits live OSV
queries for all seven native source revisions and eight build-only Python
packages. The recorded P03 run returned no advisories. GN and ZAP are bound by
CIPD instance and executable hashes because OSV does not provide package queries
for those artifacts. The native runner emits a transient manifest that binds
the source files, upstream contents, build arguments, tool executables, native
binaries and measured cleanup result. The manifest and SDK build stay outside
the source package.

## P04 Interaction Model evidence

`WOTEX_PATH_DEPS=1 mix run bin/check_p04_native.exs` extends the P03 pinned
native reconstruction with the generated cluster bindings and direct
connectedhomeip `ReadClient`, `WriteClient` and `CommandSender` integration.
The lane builds the complete host normally and with ASan/UBSan, then runs all
four CMake executables in both modes. `test/native/interaction_test.cpp` checks
finite timing and DataVersion propagation, local read-only rejection without a
backend call, partial path and cluster status preservation, event identity, and
single mutation completion.

`test/wotex/matter/interaction_test.exs` runs on both supported BEAM lanes. It
checks the named read, write, invoke and event helpers, strict native wire
decoding, WMA-F11 local rejection without client I/O, and bounded non-atomic
Descriptor discovery.

This is native compilation, protocol and lifecycle evidence. It does not record
a successful interaction with an independent Matter device. P09 owns the pinned
software-peer workflow; no physical-device result is inferred.

## P05 subscription evidence

`WOTEX_PATH_DEPS=1 mix run bin/check_p05_native.exs` rebuilds the complete pinned
host normally and with ASan/UBSan. All five CMake executables pass in both modes.
`test/native/subscription_test.cpp` exercises the production establishment
buffer, revised intervals, attribute and event identity rules, bounded report
credit, cumulative byte acknowledgements, queue retirement without sequence
gaps, protocol frames and zero accepted reports after cancellation. The GN host
build compiles the same owner against connectedhomeip `ReadClient` Subscribe
callbacks and callback-safe SDK-thread destruction.

`test/wotex/matter/subscription_test.exs` runs through the real BEAM Port owner.
It covers WMA-F08 equal values with distinct report/DataVersion identity,
explicit null, event number/priority/timestamp, receiver death, receiver queue
overflow, foreign handles, exact ACKs and idempotent cancellation. Its small
executable peer supplies deterministic native frames; it proves the Port and
BEAM ownership contract, while P09 still owns a successful independent Matter
publisher interaction.

## P06 recovery evidence

`WOTEX_PATH_DEPS=1 mix run bin/check_p06_native.exs` extends the same pinned
normal and ASan/UBSan reconstruction. The C++ subscription test checks that
recovery is opt-in, attempts are strictly ordered and limited to five, the
deadline is exactly 60000 ms, each recovery advances delivery generation, old
generation reports are rejected, attribute snapshots restart, and event identity
remains deduplicated across a continuity gap. The complete owner compiles against
the pinned `SendAutoResubscribeRequest`, `OnResubscriptionNeeded` and retry APIs.

`test/wotex/matter/subscription_recovery_test.exs` drives the production BEAM
Port owner with deterministic native frames. It executes WMA-F09 terminal default
loss, the opted-in continuity-loss/status transition, a fresh recovered snapshot,
five-attempt exhaustion and cancellation of generation 2 through the original
opaque handle. No mutation request is emitted during recovery. This lane does not
claim gap-free event replay or an independent publisher interaction.

## P07 commissioning and authorization evidence

`WOTEX_PATH_DEPS=1 mix run bin/check_p07_native.exs` extends the pinned normal
and ASan/UBSan reconstruction with the production commissioning controller.
The complete host compiles its exact long-discriminator
`DiscoverCommissionableNodes` filter, network-only `PairDevice` path, final
`DevicePairingDelegate` result, CASE probe and
`CommissioningWindowOpener`. The enhanced-window request supplies no caller PIN
or salt. The same build uses the production attestation verifier configured by
the explicit PAA trust directory; it does not enable an attestation bypass or
test commissioner mode.

`test/native/commissioning_test.cpp` executes request bounds, final-result
validation, numeric SDK failure status and effect, expired-window failure and
operational ACL denial. `test/native/value_test.cpp` exercises the generated
AccessControl and AdministratorCommissioning value schemas, including rejection
of PASE as ACL authority. `test/wotex/matter/commissioning_test.exs` checks the
public explicit operations, invalid and reserved setup PINs, secret/redacted
onboarding material, strict wire results and pre-I/O ACL validation.

`test/interop/commissioning_test.exs` is the executable WMA-V10 peer contract.
It requires an explicit `WOTEX_MATTER_COMMISSIONING_FIXTURE` and covers trusted
commissioning plus CASE, a valid wrong PIN, untrusted attestation, expired
window material and peer-enforced ACL denial. It is excluded from the developer
gate and has not yet been executed here because P09 owns construction and
orchestration of those pinned peers. Its presence is not interoperability
evidence.

## P08 Runtime mapping and stream evidence

`test/wotex/matter/runtime_stream_test.exs` executes WMA-V11 at the binding
transport boundary. It proves typed controller Property/Action results,
attribute DataVersion and Event identity, one-use frame decoding,
unrelated-reference and forged-frame rejection, terminal session loss,
Runtime-owner cleanup, original-subscription cancellation, and the concrete read
health probe. The default suite also reruns the legacy one-shot mapping behavior,
so P08 does not silently change that payload profile.

P08 changes no C++ or SDK build input, so it has no new native lane. P09 remains
responsible for the pinned SDK example peers.

## P08a public Wotex integration evidence

`test/wotex/matter/runtime_integration_test.exs` executes every case in
`docs/specs/fixtures/wotex-integration-v1.json` through public core and Runtime
APIs. The deterministic ports receive only fixture inputs. The test owns the
expected projections and checks both Runtime profiles, two-Form precedence,
read/write/Action values, exact result correlation, bounded metadata, strict
nosec resolution, deadlines and the full failure/retry classification table.
Unsupported selectors, descriptors and malformed inputs acquire no client.

The same test starts real Runtime Property and Event child specifications. It
checks equal fresh reports, stale and forged deliveries, changed stop routes,
failed establishment, owner/receiver death, overflow and terminal session loss,
including cleanup of the original native subscription. This is injected-port
integration evidence; it does not claim an independent Matter peer or released
archive adoption. P08a changes no C++ or SDK build input and therefore has no
new native lane.

## Acceptance boundary

The WMA-C03/C04/C07 persistent-owner regressions require the open reply to
match the configured lifecycle, fabric, controller node and vendor exactly.
Malformed or oversized replies, EOF during a request and owner death retire
the connection generation. A malformed operation result also invalidates its
original connection. Broken replies after write/invoke submission return
unknown-effect permanent errors; an explicitly received native failure retains
its reported effect. The tests assert both behaviors without retrying a
mutation. Wrong handle generations cannot invalidate a live controller.
The current developer gate passes 122 checks with seven interop cases excluded;
the 32-case persistent/interaction/subscription suite passes on both required
BEAM versions, with separate temporary directories for the runtime lanes.
The packet changes no native C++ build input.

Further WMA-C03 regressions prove that a mutation whose deadline expires in the
BEAM call queue emits no native request, successful read/write replies received
after the original deadline cannot become success, and 32 concurrent disconnect
calls return success while emitting one native close. The original deadline
travels with each connection call; the owner debits queue and serialization
time, checks before Port submission and after result validation, and performs
typed result decoding before admitting another call. Native timeout fields
carry the remaining positive budget instead of restarting the caller's timeout
at dispatch. This closes the reproduced late-submission and late-success paths;
it does not claim remote rollback of an already submitted mutation.
The current gate passes 125 checks with seven interop cases excluded; the
35-case persistent/interaction/subscription suite passes on both required BEAM
versions. Native C++ sources and the pinned binary identities are unchanged.

WMA.11 version 1.1.0 named reads now validate the returned path and descriptor
against the requested attribute. WMA-C02 option validation rejects non-keyword
lists before client entry, and event batch indexing validates each bounded
entry/path without destructuring untrusted input. Duplicate normalized paths
and extra result fields fail. Descriptor PartsList validation rejects reserved
endpoint `65535`, matching the existing native conversion rules. Four new
regressions fail on the preceding implementation and pass after these fixes.
The focused standalone/descriptor/interaction/Runtime suite passes 44 cases on
both required BEAM versions; the current developer gate passes 118 checks with
seven interop cases excluded. This packet changes no native C++ build input.

`test/wotex/matter/native_wire_test.exs` adds ten deterministic boundary tests
for WMA-B02, C01, C02 and C04. They assert full-width integer and timestamp
preservation, null/false/empty values, nested context tags, per-path result
identity, exact subscription metadata, bounded error status and non-retryable
unknown mutation effects. Malformed envelopes, out-of-range values and unknown
wire types fail with structured errors.

`test/wotex/matter/descriptor_boundary_test.exs` adds five WMA-S01/S05 tests
that round-trip each admitted scalar/structured recipe through actual TLV bytes
and reject incompatible schema fields. ACL assertions distinguish null from
empty subjects/targets, preserve optional read fields, reject fabric-index
writes and prevent well-formed TLV from bypassing field validation. These are
pure conversion assertions, separate from the executed SDK ACL peer cohort.

The additional standalone and persistent-owner boundary tests assert that
invalid sessions/options/versions, malformed mutation acknowledgments, ambiguous
event batches, duplicate discovered endpoints, foreign handle generations and
invalid native subscription fields return structured failures. Request audits
prove rejected native input emits no request and leaves the original live
controller usable. The default suite passes 114 checks with seven interop cases
excluded. Coverage is 89.7% in this cohort; the required 95% release gate remains
unsatisfied and its threshold and exclusions are unchanged.

WMA.10 and WMA.11 version 1.1.1 specify complete bounded event history.
`StandaloneBoundaryTest` adds regressions for multiple reports on one event path,
request-path grouping, ascending event numbers, explicit errors and empty filtered
history. Duplicate fabric/node/event identities, conflicting per-path status,
foreign paths, schema violations, below-minimum numbers and excessive counts fail
with structured errors. Duplicate requested event paths fail before client entry.
The real bridge peer exposed the previous one-result-per-path assumption; both
new BEAM tests fail before the fix. Native `interaction_test.cpp` separately
reproduces the rejection of a successful empty history. The native owner now
preserves that empty success without inventing a missing attribute-style result.
The focused standalone/interaction suite passes 20 cases on both BEAM versions;
the default gate passes 128 checks. All six native tests pass normally and under
ASan/UBSan with leak detection. Normal and sanitized SDK hosts rebuild with
SHA-256 values respectively
`b38ae7688b8136e26f1f02a07570d311a404fde9a4df49875056110b9274b3af`
and `e806d61d4439604d2fe70e10030ca7ca6591e6809307e75bd8af236d29d0236b`.
This changes no upstream dependency pin and makes no broader P09 acceptance claim.

WMA-S01 cluster validation follows the pinned SDK's `IsValidClusterId`, including
manufacturer suffixes `FC00..FFFE` and vendor prefixes `0001..FFF4`. The
all-clusters peer exposed the previous rejection of its valid `FFF1FC05` cluster
in Descriptor ServerList. Concrete paths, read selectors, Descriptor conversion,
ACL targets and native request validation now use the SDK ranges. Unknown valid
cluster IDs remain numeric; their interaction schemas are still unsupported.
The BEAM path/descriptor regression and native value/interaction regressions fail
on the previous implementation, then pass with valid boundary IDs and reserved
prefix/suffix rejection. The 19-case BEAM suite passes on both required versions;
all six native tests pass normally and under ASan/UBSan with leak detection.
The default gate passes 126 checks. The unchanged pinned native/Python
dependencies pass all 15 P03 advisory queries.

Both SDK host variants rebuild against the unchanged source pins. The normal
host SHA-256 is
`f978e073884abf966bfbc63ea2c2a11ca3525ed973488fbdcc2d97501886f5f3`;
the ASan/UBSan host SHA-256 is
`6fa2978d9d00cb040fc0bc526fca80457fb8f63820a0b86dc665029a01fc0e2c`.
Earlier peer results below retain their originally executed binary identities.

`test/interop/native_lighting_test.exs` executes the WMA-N03 lighting workflow
against the pinned, unmodified `chip-lighting-app`, using the native host above.
Its source SHA-256 is
`c4bd52de2d8dc670c71c419593e5b9e493d679ff130a6cc47b63ba3c686f9659`.
Both required Linux BEAM lanes pass with the same binaries: lighting SHA-256
`5d0c28f58af14c25569ef08c13bbea51b6dd853e5e46c684dc20fdbc3faa32c0`
and host SHA-256
`2acc3532909f26c8bbe5c07a895c6bc0caba73abd6553ab5a1d76488a983dc97`.
The command is `mix test test/interop/native_lighting_test.exs --include interop
--include software`, with `WOTEX_MATTER_NATIVE_LIGHTING_FIXTURE` identifying a
fresh controller/peer fixture. The fixture supplies explicit controller
identity, executable, storage and PAA paths, onboarding inputs, and an exclusive
result output path; it supplies no expected responses.

Both peers complete commissioning and final CASE. Descriptor discovery locates
endpoint 1 in these fixtures. The test reads false, rejects a local OnOff write,
invokes On and separately reads true, then invokes Off and reads false. Native
subscriptions preserve report IDs 1, 2 and 3, including equal first/third values
with different DataVersions. After idempotent cancellation, a further On and
read produce no delivery during the asserted 1100 ms observation window.
The store reopens with the original identity and performs CASE reads without
recommissioning. Real `ConsumedThing` reads and an Off Action use the controller
profile, preserve typed values and metadata, and independently reopen that same
fabric. Every explicitly opened owner exits normally, its exact OS child is
observed absent, and the final owned Port count is zero. Separate OS process
queries find no remaining native host in either lane. This is shared-SDK peer
evidence with a finite post-cancellation observation window.

The current and minimum lane test-log SHA-256 values are respectively
`4f96820cfce410563380a34098a7802718415afc7273b8f8a02364215e6c6adc`
and `463026995c9b01d9eaf2c9ace08d72a4797e9c00431152f22554f31f8156618f`.
The developer gate passes 125 checks with eight interop cases excluded. This
adds lighting workflow evidence; thermostat, bridge, remaining native process
stress, the software-run task and final archive acceptance remain open.

The WMA-N03 thermostat and bridge workflows execute in
`test/interop/native_thermostat_test.exs` and
`test/interop/native_bridge_test.exs`, whose SHA-256 values are respectively
`8f819b1e4159a0e14629e2d9a071c2c88b3616b3aa37b56f3ca4b3b539e67437`
and `ea3e42f383a4f4687760dda08775cf7d49849017a75587dabd6e6c6d7411b116`.
Both pass against real Linux SDK peers on both required BEAM versions. Invoke
each test with `--include interop --include software`, supplying respectively
`WOTEX_MATTER_NATIVE_THERMOSTAT_FIXTURE` or
`WOTEX_MATTER_NATIVE_BRIDGE_FIXTURE`. Their JSON configuration carries explicit
controller identity/trust/storage, commissioning inputs, named-pipe control path
and exclusive result path. Expected protocol results remain in ExUnit.

The all-clusters control sets the peer's real SDK temperature attributes; the
bridge control calls the SDK's existing reachability setter and event machinery.
The production controller contains neither control. The Mix software builder
requires exact original source hashes, applies these test-only extensions and
records original, extension and patched-source hashes in `peer_extensions`.
Its source identity includes all Elixir test helpers used by peer assertions.
Extension admission rejects an unrecognized SDK source before modifying it.

| Peer artifact | SHA-256 |
| --- | --- |
| All-clusters control source | `0862ea120d0162851191057eecedc434f7dc72fca0635ac0383d1044c45792b4` |
| Patched all-clusters delegate | `ffb55dffc21e07f617a6ed8f569689f15068c766e45fc17befcc22622756893b` |
| All-clusters executable | `b32c235943a96a30bcf7b220c66e783bb0a4b16a8a67bd1cff4d24c9c4a582d0` |
| Bridge control source | `09b09ddeea86c5aff1c91d3716da3190c32ba055f950bf6f483ed77ed9c8df41` |
| Patched bridge main | `362bd634411c669a0cb8315d22d2c151e5a98a138575216fd0973828851b8a0c` |
| Bridge executable | `89333e487346ab1e256a9c6b91b9efa9ae6b3005dca30bad540df823a3f3963f` |

These executables were rebuilt incrementally from the previously verified pinned
SDK/toolchain workspace, with the exact extension records retained. This cohort
does not replace a fresh complete build-task receipt for the final P09 source.
The thermostat cohort uses host `f978e073...86f5f3`; the bridge cohort uses
`b38ae768...74b3af`, with complete host digests above.

Thermostat discovery retains the peer's `FFF1FC05` manufacturer cluster and
locates endpoint 1. The test reads signed 2150 and explicit sensor null, writes
heating 2000 then 2050 with expected DataVersion and a timed request, verifies
new DataVersion, observes stale-write status `0x92`, and confirms 2050 remains.
It writes/reads mode values 0, 1, 3 and 4. Further peer controls produce signed
2200 and sensor zero, preserving zero separately from null.

Bridge discovery locates the controlled sensor at endpoint 4. The test observes
ReachableChanged false/true with distinct report and event numbers, checks
attribute readback, and reads both historical events with their exact timestamps.
A minimum above the newest event returns an empty success. After cancellation,
a further reachability change and read yield no delivery during the asserted
1100 ms window; the requested maximum report interval is one second. Both
workflows observe normal owner exit and disappearance of its exact OS child
before writing a passing result. Separate process queries find no native host
in either Linux lane after the tests.

| Test log | Current BEAM SHA-256 | Minimum BEAM SHA-256 |
| --- | --- | --- |
| Thermostat | `80e8ed183ebee68ed7344de6eac6a936c15c2039117fc84be09de45984baa28a` | `0e0e8e566842b36a6722570528cbf9acf161e00e1a4c70221a46e078bb2775ff` |
| Bridge | `3cf5c9ab3329195031bb04e45783c30b64d064adad71edb5b3996d879aab2885` | `dbb29de848dfd41cb6eed0a145373e13157b8dc51a42525a4b48ae67182592cb` |

[WMA.13](../specs/WMA.13-native-backend.md) defines the complete native binary,
Mix/ExUnit tasks, version lanes and credit/resource tests. P01–P08 are executed
at their stated deterministic and native-compilation boundaries, and P08a is
executed at its public Runtime/injected-port boundary. P09 still requires all
pinned software-peer workflows, including WMA-V10, plus the isolated package
archive consumer run. A passing P07 native lane does not establish an actual
peer result, physical-device
behavior, CSA certification or publication readiness.

Each completed native run must bind source, SDK/binary, toolchain and cleanup
result identities in its manifest. The mandatory BEAM matrix is
Elixir 1.18.4/OTP 27.3.4.15 and Elixir 1.20.2/OTP 29.0.4. Only identified
executed lanes count as passing evidence.

## Fresh peer build and native lifecycle checks

A clean-source `mix wotex.software.build --workspace ABS` run at local commit
`5a2471d486768f9cb9b76859d17295e32018d089` completed with source SHA-256
`1c936c9250466bb617a15edff0610f22f9591a4539c4c64cb9d052479ce2698c`.
The emitted workspace passed `SoftwareManifest.verify_local/4`, including every
artifact and log digest, before subsequent source edits. Its normal and
ASan/UBSan controllers, lighting, all-clusters and bridge binaries match the
complete hashes recorded above. Both six-test native CTest lanes and the build's
advisory checks passed. The runner removed its owned build container. The native
manifest SHA-256 is
`f669af0936a87282f4aeeabe874332b1b6bca22692922bd736a6c93751cd41f5`.
This is a build receipt for that source identity; later source changes require
a new matching receipt before reuse by the software runner.

`test/software/lifecycle_stress_test.exs` selects the lowest discovered endpoint
advertising OnOff and runs read-only load against an explicitly supplied,
previously commissioned SDK peer. Both Linux lanes pass: Elixir 1.20.2 /
OTP 29.0.4 and Elixir 1.18.4 / OTP 27.3.4.15. The fixture is supplied through
`WOTEX_MATTER_NATIVE_STRESS_FIXTURE`; select `--include interop --include software`.
It contains controller identity/trust/storage, node ID and an exclusive result
path. The test uses stored authority and never commissions or writes the peer.

The native host is `b38ae768...74b3af` and the all-clusters peer is
`b32c2359...82d0`, with full hashes above. Each lane executes 1000 sequential
reads, 32 concurrent callers, 100 subscription receiver-death cycles and 100
stored-controller open/read/close cycles. Native descriptor count remains 16;
receiver monitors and the Connection's live subscription, generation, monitor,
internal request and pending-report tables return to baseline. Every closed
controller has a normal owner exit, no surviving exact OS child and no extra
BEAM Port before the next cycle. The test records RSS separately: all ten
100-read samples are 20900 KiB in each lane. Those samples do not measure the
SDK's internal subscription/timer allocations.

| Lifecycle artifact | SHA-256 |
| --- | --- |
| Test source | `80387262b4c80489270fff1fd9c104bc21d72747973317aaf99784b229aa56f6` |
| Current Linux test log | `9e72cde7816723639a060b960313a27c91e48de3455f85840f4d2a9694e71593` |
| Minimum Linux test log | `16d5d9188600bbcbe2c20492eade21dd1140d15429a65cdc4f9307a2a1826b61` |

The default gate passes 130 checks with 11 opt-in exclusions. C09 remains open
for forced deadline/peer-close/malformed-response stress, complete admission and
native resource instrumentation, and the full process-flow corpus. The latest
coverage run is 90.0%; the required 95% threshold is unchanged.

The clean `5a2471d` archive has SHA-256
`0a4961bbfbeba2add799dcaafb9db32bf99719781b99dca48aa78c63082f02e8`.
Its existing out-of-tree compilation check passes with development dependencies.
A separate production Mix consumer extracted that archive with
`WOTEX_PATH_DEPS` unset and attempted `mix deps.get`; the Hex registry could not
resolve `wotex` or `wotex_runtime`, ending with “No package with name wotex”.
That released-dependency consumer gate is blocked on manual publication and is
not replaced by the development compilation result.
