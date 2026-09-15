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

## Native parser and ready corpus cohort

`test/wotex/matter/native_contract_test.exs` executes WMA-B-F01–F06 from the
unchanged native corpus. F01–F05 invoke the production `HostProtocol` request
validator through `test/native/contract_driver.cpp`; the executable receives
only the operation and input file. It bounds input, checks the final newline
and rejects additional frames. ExUnit compares the returned JSON with the
corpus expectation outside the implementation. F06 starts the actual SDK host,
compares the exact ready object, closes stdin and observes zero surviving owned
OS children within the cleanup grace.

The software/native builders compile and retain separate normal and sanitized
contract executables and bind them in their artifact manifests. Select the
ExUnit cohort with `--include software`, supplying absolute
`WOTEX_MATTER_CONTRACT_DRIVER` and `WOTEX_MATTER_NATIVE_EXECUTABLE` paths.
Missing executables, malformed corpus identities and unknown operations fail.
Each parser process has a 1000 ms deadline; the existing Mix command owner
reaps it on failure. Both two-test Linux runs pass: normal with Elixir 1.20.2 /
OTP 29.0.4, and ASan/UBSan with Elixir 1.18.4 / OTP 27.3.4.15 and leak detection
on. Both six-test native CTest lanes also pass. Production host hashes remain
`b38ae768...74b3af` and `e806d61d...0236b`, recorded in full above.

| Corpus artifact | SHA-256 |
| --- | --- |
| Native test source | `d154fae0c108b4ea3cdd8612c4ddf1f99d2ff165739b21ee4cc28bdbc5c28f2d` |
| ExUnit test source | `09dd5c1ca8c5afc7af43b40217e6a2cf9ac58ab0db5660006ed4c2fd5bebe58e` |
| Native corpus | `a42e47c8d620cc9598996921cf44175d30f0a4c36ebf5b5ecf1233fe53c540ce` |
| Normal contract executable | `c58bca9bf13107e780d9f5fae9dbf70006bd676f9aa378f08f4799e744cfca90` |
| Sanitized contract executable | `7e212fa5629a98489f6c4e99f3ca24023ec71a0cfad3d169a3cd430ef22dc348` |
| Current Linux test log | `b2581694a8f7d140d9fa1634181e59acd9610d6b9259373b6f11d3f48ffd363a` |
| Minimum Linux sanitizer test log | `992b5ec919a45de90f18159112a2ef5f82f14169f111016507987a3cb42c6fb8` |

This cohort accepts six parser/startup cases only. The eleven flow-trace,
process-flow and result-budget cases remain required; the corpus as a whole
retains its `specified_unexecuted` status. Parser execution does not establish
SDK peer interoperability or complete WMA-B03 acceptance.

## Startup deadline and stalled-child cleanup

Two C03 regression cases fail before the correction: a 600 ms ready delay plus
a 600 ms open delay produces an accepted connection under a 1100 ms total
budget, and an executable stalled after a request survives closed stdin beyond
the 1000 ms cleanup grace. Both pass after the correction. The connection now
starts its absolute deadline before process initialization, sends only the
remaining open budget and rejects expired startup frames. Teardown invokes
executable `/bin/kill` directly for the exact child PID obtained from the still
owned Port, then releases the Port. A cooperative close still completes native
controller/storage shutdown before its response; failed requests can terminate
a noncooperative child. Missing termination support fails before host startup.

The focused connection/subscription/recovery cohort passes all 27 tests on
Elixir 1.20.2 / OTP 29.0.4 and Elixir 1.18.4 / OTP 27.3.4.15. The default gate
passes 132 checks with 13 opt-in exclusions, and ExDoc passes with warnings as
errors. Both Linux real-peer lifecycle lanes were repeated with this code and
pass their full 1000-read, 32-caller, 100-receiver-death, 100-open/close counts,
including durable-store reopening and exact child/Port cleanup. The unchanged
native host and peer use the full binary hashes in the lifecycle cohort above.

| Cleanup artifact | SHA-256 |
| --- | --- |
| Current Linux lifecycle log | `ac1db98d136ce8301ffa5507a39e072e3639535c465801c70f6edd3e193a1742` |
| Minimum Linux lifecycle log | `9b8d9b5b98e0fa027d4eb8b509f25b90dc85ef0561e600c8557d45d4f9fdddd0` |
| `lib/wotex/matter/native/connection.ex` | `9d65c469af8e511a7a46e2225fde7f3809d01e1287cd5072f7592e1d6d94497b` |
| `test/wotex/matter/persistent_bridge_test.exs` | `4c8ff43407cea121567d004f1bdb9491a61fc739e40a05f3c63f1ae3915e4d4b` |

This verifies total startup-budget ownership and stalled-child termination at
the Port boundary. It does not close the remaining admission, control-channel,
native resource instrumentation or process-flow corpus requirements.

## First-party native one-shot operations

`Native.connect/1` admits `lifecycle: :oneshot` only with an existing store and
stored authority. Its redacted options handle retains no process or lock. Every
admitted concrete read/write/invoke validates its descriptor before acquiring a
fresh native controller and flow generation, and closes that controller before
returning. Startup, request and close use the remaining operation budget;
startup expiry and malformed close replies cannot become successful operations.
Unsupported discovery, event-history, commissioning, health and subscription
operations acquire no native process. The wire controller still uses the
persistent storage protocol for each individual operation.

The named API preserves typed reports and values. `RuntimeOneshot` applies the
existing descriptor conversion for the scalar Runtime profile, preserves zero
and null, returns `"written"` for acknowledged writes and nil for status-only
commands. Native Runtime routes require the lifecycle that matches their profile.
The injected-boundary tests verify fresh generation per call, no retained owned
Port, pre-acquisition rejection, scalar/null results, startup expiry and failed
close handling. The complete default gate passes 136 checks with 14 opt-in
exclusions; 33 focused connection/Runtime tests pass on the minimum toolchain.
ExDoc passes with warnings as errors.

`test/interop/native_oneshot_test.exs` passes on both Linux lanes: Elixir 1.20.2 /
OTP 29.0.4 and Elixir 1.18.4 / OTP 27.3.4.15. Supply the explicit existing-store
controller/node configuration and exclusive result path through
`WOTEX_MATTER_NATIVE_ONESHOT_FIXTURE`, and select `--include interop --include software`.
The test discovers its thermostat/OnOff endpoint, performs five typed native
operations and six real ConsumedThing operations against the pinned all-clusters
peer, verifies writes by readback, invokes On/Off and restores the heating value.
Every operation returns the owned Port set and matching Linux native process
set to baseline within the cleanup grace. The production host is
`b38ae768...74b3af` and the all-clusters peer is `b32c2359...82d0`, with full hashes
recorded above; no C++ or SDK input changed in this cohort.

| One-shot artifact | SHA-256 |
| --- | --- |
| Native client | `dfdbb2ae3ecc90411e3a3f1076364c8c91c7e3ae781469e3d8ae0cc4207b3f54` |
| Native connection | `399f6fdb983fafaec2c34b23d12261d5d242ccb14011e4c8a7c1a04aa7b3a26b` |
| One-shot handle | `d515c52dddd8246008dbef3098fc0313ac24e2f5da9e6bdeb403a3cfba8695a5` |
| Runtime one-shot projection | `faf6193943e9b9cf430fe5a6051684f707f88a6b339ec38c8f81b460ff21e99f` |
| Runtime transport | `e2a498389ac91d77601d181475f53504fa38928887e3749878fe5a396ba46bf6` |
| Peer test | `1b9ba27e110a8f4117e4327d3b8940f9dcbff8e53519a3dd4f84ecfbc4216225` |
| Current Linux peer log | `94042afeed1d70d9e055c8b76862424cee1d5e350f222a3fbd3d7a192990d6f3` |
| Minimum Linux peer log | `367e11c995b5f4e6846864e94d87f901256dc1a37ccf5c5d0c00d34372910683` |

This is the native one-shot API/Runtime workflow cohort. It does not replace the
remaining full stress/admission, flow corpus, software-run task, coverage or
released-dependency archive gates for P09.

## Native commissioning timeout

`PendingCommissioning::Wait` reads its mutation flag while holding its existing
mutex. Calling the locking accessor from that critical section deadlocks before
the SDK timeout response can be published. The regression attempts on-network
commissioning with a 1000 ms discovery budget and no matching advertisement.
It requires `timeout`, effect `none` and SDK status `0x32`, then verifies the
connection's timeout retirement policy and exact child cleanup. Before the
correction, the BEAM deadline expires without an SDK status. Both rebuilt native
hosts return the required SDK status after the correction.

`test/interop/native_commissioning_timeout_test.exs` passes with the normal host
on Linux Elixir 1.20.2 / OTP 29.0.4 and the ASan/UBSan host on Linux Elixir
1.18.4 / OTP 27.3.4.15. Supply an explicit fresh-store controller and absent
discriminator through `WOTEX_MATTER_NATIVE_TIMEOUT_FIXTURE`. Both six-test CTest
lanes and all fifteen pinned-source advisory queries pass. The native source
was rebuilt incrementally against the pinned SDK; this is not a fresh complete
software-build receipt or complete expired-window acceptance.

| Timeout artifact | SHA-256 |
| --- | --- |
| Normal native host | `03268cdbb3db87177154433dc54c6d5e9357f4ee06f503a00edf1051056fdc72` |
| Sanitized native host | `0d313e14bae98f457f54400739a24ef483772a66a3e4690af337fa5f7558006c` |
| ExUnit regression | `bc400911dc333d301d5783e3a04a197671fdbfe2121692fc442d40c74b8f8279` |
| Current Linux log | `61c2eca6235c30d9fa4bbd96854adaa0fe59c41498c8e29b4d503ac383b3bba3` |
| Minimum Linux sanitizer log | `cf59b0ee1dd8155b41eb7fcd0065a5d6f0a54e168c4d7354dd346e3ee588ce0b` |

## Cooperative native exit

Explicit disconnect requires a null close response and native exit status zero
within its existing absolute deadline. A delayed successful exit completes
before the caller returns. Malformed close results, nonzero exit statuses and
stalled post-response shutdown produce structured failures. Failed cleanup still
terminates the exact owned child. The regression cases expose both premature
termination after a close response and a `CaseClauseError` for a non-null result
before the correction. All 33 focused lifecycle tests pass on the current and
minimum toolchains after the correction.

The real native one-shot/ConsumedThing workflow passes on both Linux lanes with
the timeout-cohort binaries above. The minimum lane uses ASan/UBSan with leak
detection enabled and now observes each cooperative native process's successful
exit, including sanitizer finalization. The default gate passes 138 checks with
15 opt-in exclusions; ExDoc passes with warnings as errors.

| Exit artifact | SHA-256 |
| --- | --- |
| Native connection | `aaf40e05deb757ce19ea41fda0a1ea3be27b1b56b90c199d65503a481f57724a` |
| Connection regression tests | `40a417f22f9e875e4785291c7a0fdf3739f9951acaf691a228b1bf8d47c7ae48` |
| Current Linux native log | `1a1356cb4ec370cee18302b067e2d6875ce45f39acc8dae63280e3afa08882b5` |
| Minimum Linux sanitizer log | `315ee538c8598321530f0e61add040264f97433ad1b05db283093c69c6f9c18f` |

## Attestation failure before fabric mutation

The native commissioning delegate records possible fabric mutation only when
`kSendTrustedRootCert` or `kSendNOC` starts. The numerically later `kCleanup`
stage does not imply either credential command ran. With a valid PAA trust
directory that excludes the peer's root, the pinned SDK returns
`CHIP_ERROR_FAILED_DEVICE_ATTESTATION` (`0x20`) before those stages. The regression
requires `commissioning_failed`, effect `none`, a usable controller afterward,
successful cooperative disconnect and no surviving owned child. Before the
correction the same test fails because cleanup incorrectly sets effect `unknown`.

`test/interop/native_attestation_failure_test.exs` passes on both pinned Linux
toolchains, with the sanitized host and leak detection on the minimum lane.
Its explicit `WOTEX_MATTER_NATIVE_ATTESTATION_FIXTURE` provides a fresh controller
store and a commissionable pinned lighting peer. No attestation bypass is used.
Both six-test CTest lanes, fifteen advisory queries, the 138-check default gate
and ExDoc pass. These hosts were incrementally rebuilt against the pinned SDK.
This accepts the untrusted-root branch of WMA-S05; other attestation failures and
the complete WMA-V10 family still require their own executed cases.

| Attestation artifact | SHA-256 |
| --- | --- |
| Normal native host | `be453277536ab39f41cf8f3d0ced1d0d95c2cac09ee0b51c46541193d6c13c9e` |
| Sanitized native host | `708fd3090ee031f486b37619bfede86003e3ec31de3ad232c31577805df0a672` |
| ExUnit regression | `adf0650a8af6450f5600d4b763e639cdc4738727ec6fee8b48a56423b8bcbcab` |
| Current Linux log | `804632604b02764536b06fca9040c8b212dc3dab7c6a7a85a40c61749f87e762` |
| Minimum Linux sanitizer log | `731c118baa023daa1ab4ff1283e0b966c308e51bf5aff15bbb3c1d18f862e7ac` |

## Build-command Port close race

The software command owner preserves its collected result when its native child
exits between checking the Port identity and closing the Port. Closing an already
closed owned Port is idempotent; unrelated argument errors remain failures.
An instrumented 1000-timeout diagnostic reproduced one `Port.close/1` argument
error that replaced `command_timeout` with `command_failed` before the correction.
The same diagnostic returns 1000 `command_timeout` results after the correction.
The direct closed-Port regression and all ten build tests pass on the minimum
toolchain; the default 139-check gate and ExDoc also pass.

| Command artifact | SHA-256 |
| --- | --- |
| Command owner | `0959f5c4f76eb4e1016e4d5e16c43a4e125d30ab25572507ad1d19c4814eb996` |
| Build tests | `255185da36201d58cfac230c9c40ef3e95186460f647a3f05ebd490a06520366` |
| Diagnostic before correction | `593af9f25d39a8925b3350341d54e3d5e9722a802393772c84715b60ccf9a5f0` |
| Diagnostic after correction | `d8ccb63a9c40eaa6a91148326a5e5b107d97fcdcdfbbb8bc1f286fcf806756b3` |

## Native one-shot lifecycle load

`test/software/native_oneshot_stress_test.exs` executes 1000 sequential reads,
100 additional connect/read/disconnect cycles and 32 concurrent callers against
the pinned all-clusters peer. Every read acquires a fresh native controller from
the explicit existing store. Sequential values remain equal; each cycle returns
the matching owned Port and Linux process census to zero within 1000 ms.
The concurrent cohort returns one correct value and 31 `storage_open_failed`
results on each lane, reflecting exclusive controller-store ownership without
implicit retries. One-shot subscriptions are unsupported and this cohort does
not synthesize receiver cycles for them.

Both Linux toolchains pass: the current normal run takes 412.9 seconds and the
minimum ASan/UBSan run takes 727.2 seconds with leak detection enabled. Successful
operations observe native exit status zero before returning. The normal host is
`03268cdb...56fdc72` and the sanitized host is `0d313e14...58006c`, with full hashes
in the timeout cohort; the later attestation change is not part of these binary
identities. The all-clusters peer remains `b32c2359...82d0` as recorded above.
Ten caller-heap samples are collected separately from native process ownership;
they are not native RSS measurements or a heap-leak acceptance threshold.

Select `--include interop --include software` and provide
`WOTEX_MATTER_NATIVE_ONESHOT_STRESS_FIXTURE` with the controller, node, endpoint
and exclusive result path. Linux procfs is required for the process census.
This is the successful-operation/exclusive-store load cohort. The combined
forced-failure, native instrumentation and full C09 admission requirements remain
open. The default gate passes 139 checks with the software cases excluded.

| One-shot load artifact | SHA-256 |
| --- | --- |
| ExUnit test | `f90f9c6d3acd378f79738c77f1002707afdbc0e3debd96226692e8ee2fd3b6cd` |
| Current Linux log | `4f41aed021dffea4a3506d3fb38bca4746accc362b9550a2cb8d2a2028a58ddb` |
| Minimum Linux sanitizer log | `0a4af09f395f99d978f50cc112fa3261f706fbfb1d74b28074c154683aec9bf0` |

## Enhanced commissioning window expiry

`test/interop/native_window_expiry_test.exs` starts from an operational pinned
bridge peer and reads AdministratorCommissioning WindowStatus `0`. It opens a
180-second enhanced window, verifies WindowStatus `1`, waits at least 180200 ms
and verifies WindowStatus `0`. A separate fresh controller then attempts
commissioning with the returned, now expired material and receives SDK timeout
`0x32` with effect `none`. Both controller owners and exact native children are
released before the test writes its result. Onboarding material remains in memory
and is not included in the result artifact.

The final test passes in 182.0 seconds on the current Linux toolchain and 182.7
seconds on the minimum sanitizer lane. The measured intervals before the failed
attempt are 180206 ms and 180203 ms. These lanes use the attestation-cohort hosts
`be453277...c13c9e` and `708fd309...f0a672`, with full hashes above, and the pinned
bridge binary `89333e48...3963f` recorded in the bridge cohort. Provide an existing
controller, a fresh controller and an exclusive result path through
`WOTEX_MATTER_NATIVE_WINDOW_FIXTURE` and select the software/interop tags.

The generic commissioning fixture also requires an explicit `expected_code` for
each negative scenario, limited to `commissioning_failed` or `timeout`. Its
attestation and expired-material cases pass on both Linux lanes with exact SDK
statuses and effects. The other three generic cases are excluded from that
focused run. These results establish the expired-window branch of WMA-S05/V10;
they do not replace the remaining commissioning, process-flow or full-run gates.

| Window artifact | SHA-256 |
| --- | --- |
| Expiry test | `40fc5dea2a4a05a13827899eb7d166dd71409be3b0f4580d545dedff3218f015` |
| Current Linux expiry log | `9836bb5e6ceedc8adb913a1b96ecf065d1032866fe637cdedc404166f189c5e8` |
| Minimum Linux sanitizer expiry log | `3800f4c8163596cb44efda4713e82025591b969ccade394159b1b90b84f70e18` |
| Generic commissioning test | `db1d6b3424bed816cc043abd8b6011c468d937854863aee835500527f5e7564c` |
| Current Linux status log | `cb85b20c1df877d116de9e14caedaa190b79ef353978d0b6e08d1846f5c17528` |
| Minimum Linux sanitizer status log | `2782b2a8f1cba8397e3b15ec0db8672af3dd81a176a52e1eb07de1f7b0ec832c` |

## Encoded-result budget corpus

WMA-B-F16 and F17 execute `valid_encoded_result_size`, the shared production
predicate applied to serialized interaction results before the response envelope
is emitted. The exact 98304-byte boundary is accepted; 98305 bytes returns the
`response_limit` projection. ExUnit supplies only the decimal input byte count
to the bounded native contract driver and compares its result with the unchanged
corpus expectation. The previous driver rejects the unsupported operation.
The native runtime retains the same limit and separate pre-serialization
retention bounds.

All three native-corpus tests pass on the current Linux toolchain and the minimum
ASan/UBSan lane with leak detection enabled. They execute F01–F06 and F16–F17,
eight of seventeen cases. The six flow traces and three process-flow cases remain
unexecuted, so the corpus retains `specified_unexecuted` status. These pure size
checks do not establish process-flow bounds or SDK peer interoperability.
Both SDK hosts were incrementally rebuilt, both six-test CTest lanes pass,
fifteen advisory queries pass, and the default 139-check gate and ExDoc pass.

| Result-budget artifact | SHA-256 |
| --- | --- |
| Shared interaction header | `0b061fe2e9d18a9dc10512693771b17276125a755d938c9f6a2e34eb991a209f` |
| Shared interaction implementation | `37d015a4d530ad507e549cc1a2b2f1031879c9bb5acec278dc038897ba3d7844` |
| Production protocol | `e68cbe8ea05896b55043cbebce886c1e1b2197e90158253dae9874ece821b12c` |
| Native contract driver | `84238017eaae065eb908dbb36ed64736e1574a8cb9d4737829164275ed23aca7` |
| ExUnit corpus tests | `c62835669a58dedf1f4e04c311d50971379a081f376168a53a4300f815325d2a` |
| Normal host | `bc7a3aeff0a607cb019c514a7fc928211c6afe0ff99a38278ae7aa69a32c83df` |
| Sanitized host | `026ded05969e3044ca0de63b7a49b715e0b1f59c7e26c355658a4873e7e64abf` |
| Normal contract executable | `69316fd21d18117c976d1c539c120e086488b8618b0a889df0e692e48788abea` |
| Sanitized contract executable | `15f9fe35622d70799c3db279cb027c9106dbc167cbd9633bac699c05d1f99b89` |
| Current Linux corpus log | `dc3159c6c1bb1083b7585d6f83edfd8b61f121d81b94b3bcd920f7c2a35e0ba2` |
| Minimum Linux sanitizer corpus log | `c6400e9660a3469c2772cab02dd9bd070abf7b8b2be00b1667d836608c62412b` |

## Native report-credit trace corpus

WMA-B-F07–F10 drive the shared production `ReportCreditManager`. A read-only
snapshot exposes its queued frame count and remaining session frame/byte credit.
The native driver writes each transmitted payload and its newline to stdout,
counts only successful writes and emits the observed credit projection last.
ExUnit verifies the actual stdout frame count and byte lengths independently of
the manager snapshot, then compares the projection with the corpus expectation.
Input JSON passes the same bounded document parser used by the production host.
No expected counters or terminal outcomes are supplied to the native driver.

These cases exercise an exact cumulative acknowledgement, an incorrect byte
acknowledgement, a duplicate acknowledgement and seventeen sequential enqueues
against the per-stream credit of sixteen. Failed acknowledgements preserve the
last valid counters. The fixture payloads exercise byte accounting without
claiming to be SDK subscription reports. Unsupported retire/consume events fail
the driver; they are not projected as successful traces.

All four corpus tests pass on both Linux toolchains, including ASan/UBSan and
leak detection on the minimum lane. The suite now executes twelve of seventeen
cases. F11–F15, including both retirement traces and all three suspended-process
cases, remain unexecuted and the corpus status remains `specified_unexecuted`.
Both SDK hosts were incrementally rebuilt; both six-test CTest lanes, fifteen
advisory queries, the default 139-check gate and ExDoc pass.

| Credit-trace artifact | SHA-256 |
| --- | --- |
| Credit manager header | `f8bb890e8bd55ad992e7e504f9b8b8b59bf1192aea3195320a7b38d733160de9` |
| Credit manager implementation | `ec1c02b6c715740addd6221f0479b66e14d1edc5b96be3f013f77b7a353792e7` |
| Protocol header | `dee32ce21e6ca41eb858207d60e30733e976ba35fad708845dc9d01f9bc3b0f9` |
| Protocol implementation | `c5ff69dea33b356bf01023a91d4c91c15f6699838e3e8a65e66e64b721da6732` |
| Native driver | `af6828cbd07bc5bfca50e24a0d0db4049eafc1357f9554a597abd7885eba7db0` |
| ExUnit tests | `e1ac58d8a998621cec5a07580609de7d8e0b2383b0906d54080d7bd4b61d3a85` |
| Normal contract executable | `9acd7f3774473df15a8428b86b0d56e25a6e5d588069328834c810abd0178f8f` |
| Sanitized contract executable | `cc935f52ed6aff21eca5d45b907a1814f71d54c2de980460e31f337974dcf545` |
| Normal host | `197bbd3a346e1459ce6bcc6323b84add221933344c89d0fa207ed0368f82c2d3` |
| Sanitized host | `33c06a9aa816c17e761c6d788cf62db4e8f96b4b86ca92e4bdd00c7db4cbcaf0` |
| Current Linux corpus log | `96a919215d1c8ba08919b0b1ec68b80c79a2bfa4776ad9b3f728452ef4c7fac5` |
| Minimum Linux sanitizer corpus log | `5125b2775baba5b8511bfc3918ffb3b052f52092392bf108b03c1949c6dd94c1` |

## Runtime consumption and native report credit

The native Runtime route retains report credit until its bound Runtime owner
decodes the validated frame. An internal delivery token binds consumption to the
connection generation, subscription reference and exact report sequence. Invalid
tokens and replayed consumption do not advance credit. Out-of-order consumption
remains pending until the contiguous prefix is complete. Retirement consumes
only the validated reports belonging to that subscription. Named direct
subscriptions retain their public delivery tuples and queue-admission behavior.

The connection also bounds retained reports to 64 frames and 1048576 encoded
bytes, including newlines. A producer exceeding that bound terminates the
connection and sends one error to each active subscription. Channel failures,
invalid replies and expired operations notify active streams before controller
cleanup. These notifications cover normal connection error handling; abrupt
external termination of the BEAM connection remains a separate ownership case.

Four regressions exercise token validation and replay, deferred Runtime decoding,
retirement with unconsumed reports, and an excessive producer. The focused
22-test suite passes on both supported toolchains. The complete default gate
passes 143 checks with 20 excluded, and ExDoc passes without warnings. The real
lighting/ConsumedThing workflow passes on both pinned Linux toolchains, including
ASan/UBSan and leak detection on the minimum lane, using the credit-trace hosts
`197bbd3a...c2d3` and `33c06a9a...caf0` recorded above. That peer run precedes the
final error-notification review; the final default and minimum focused suites
include those error-path changes. The suspended-process corpus cases and full
C09 gate remain open.

| Runtime credit artifact | SHA-256 |
| --- | --- |
| Native API | `2bae8c562a7f39a74f0a90cb35acaf077f218a3f3e1f190682a8921dbe9d7e9d` |
| Native connection | `822a4ee59be13178866bb1531c2b63c54e18976a32ce689f49c03319ea8f041b` |
| Internal delivery | `b3b29bddad5f2207b9e48573bfcbcece1dd765f56e7ba59f55e9954beba8a8ef` |
| Runtime relay | `4636aa35274cbd0fdab6f86ca10f86a054f88337b6296a759d0e3f7f6948d775` |
| Subscription tests | `82c9104d66ab0cef7d7b7a7575319103ac19804a384e12d01bbf5341049ca9ed` |
| Minimum focused log | `aca6605df3af52dce154433774447ec4065699328d36cf238e292a06b002ce38` |
| Current Linux lighting log | `ebcc541c0487a025540f40b848e7d43a43f242eef19299a0a10b90ee694cb59b` |
| Minimum Linux sanitizer lighting log | `7be94d2ef772a0bcc8baa8688301e4dd4c3f01bb896ae6133ffefd8e4c469d74` |

## Runtime route termination on native owner loss

The Runtime relay monitors its bound native connection. If that connection exits
without a terminal notification, the relay emits `transport_closed`, closes its
original route and invalidates pending frames. Normal native errors and the
subsequent monitor signal cannot produce duplicate terminal notifications.
The regression fails before the monitor is added: killing the connection leaves
the relay alive and the expected error absent after 1000 ms. The focused
subscription and Runtime suites pass 33 tests on both supported BEAM versions.

`test/interop/native_runtime_loss_test.exs` subscribes through the real native
controller to the pinned lighting peer. It separately kills the BEAM connection
and the native child, observes one error/status pair, rejects decoding of the
retained frame and verifies zero surviving owned processes within 1000 ms.
Current Linux cleanup takes 20/26 ms; minimum Linux takes 61/30 ms. Both lanes
use the credit-trace host binaries recorded above. The minimum host is built
with ASan/UBSan, but deliberately killed processes cannot establish successful
sanitizer finalization. This is an established-subscription loss test, not an
in-flight interaction cancellation or full C09 claim.

Provide an existing lighting controller, node, endpoint and exclusive result
path through `WOTEX_MATTER_NATIVE_RUNTIME_LOSS_FIXTURE` and select interop/software
tags. The default gate passes 144 checks with 21 excluded; ExDoc passes without
warnings.

| Native loss artifact | SHA-256 |
| --- | --- |
| Runtime relay | `598c4584d3390f5fee9a18241f287f46e18fc07a2cf5a2384436ef857723dbe4` |
| Subscription tests | `1d9149bc844d934a6492c202182a141be9fc909cb27591dad09b3d6cb176923e` |
| Native peer test | `1d2e48c530527d33268240ca71a69b42739acc9220e50c51cff3c419eb84bcc7` |
| Regression before fix | `4fe0d683fe89098d0b7f131f500a889188c923589a5b5741667ca8fb5c79de5a` |
| Current focused log | `308e4f7ebda631423b12c9360e5b43da7a8c45e74d67faa28aa10da480bfa972` |
| Minimum focused log | `38ff9ba414f21b9b86c5a7a0089e02a7f1e7a1a2467292e82bc30fa975cc1b7b` |
| Current Linux native log | `6c42b6f94c69319fb145475f20abc8e96b9ce97af38ba6d20856b8668bced50f` |
| Minimum Linux native log | `ba9c8e267a8fbde9f4d494af5a17125e475b792e4cc077ec4edf5b1e8d3d39d3` |

## SDK reaper callback lifetime

An additional lifecycle run detects an AddressSanitizer heap-use-after-free in
`SdkControllerBackend::Impl::ReapPending`. The API thread removes a completed
interaction from its ownership vector while the SDK event loop still has a
queued reaper holding that interaction's raw pointer. The next read can trigger
the invalid access. Subscription admission contains the same premature removal.

Interaction and subscription admission now retain completed contexts until their
scheduled SDK reaper removes them. Pending completion schedules at most one
reaper. Shutdown retains its separate cleanup after the event loop stops. The
existing 64-entry admission limits include contexts awaiting their reaper;
completion does not release ownership early.

The failing minimum Linux run takes 2.0 seconds on the earlier sanitized host
`33c06a9a...caf0`. Its normal counterpart passes in 149.5 seconds, so a normal
pass alone does not expose this race. Those discovery runs include a pending
BEAM ledger refactor. The corrective runs use the preceding committed BEAM
implementation and the new native binaries below. The same tracked lifecycle
test passes in 148.8 seconds on current Linux and 179.4 seconds on minimum Linux
with ASan/UBSan and leak detection enabled. Each executes 1000 sequential reads,
32 concurrent callers, 100 receiver-death cycles and 100 open/read/close cycles.
Native children, Ports, monitors and retained subscription maps return to their
asserted baselines. Ten native FD samples remain 16. Normal RSS remains 21036 KiB;
sanitizer RSS increases from 164756 to 189016 KiB and is not a plateau claim.
Cooperative native exits complete without sanitizer errors.

Both SDK binaries are incrementally rebuilt. Both six-test CTest lanes, fifteen
advisory queries, the default 144-check gate and ExDoc pass. This callback-lifetime
fix does not complete the remaining C09 fault, admission or full matrix gates.

| Reaper lifetime artifact | SHA-256 |
| --- | --- |
| Native controller source | `3631d75125532f936fdcc6bb33eec4c8d38776b02acafabd7e63a91f50a95c99` |
| Lifecycle test | `80387262b4c80489270fff1fd9c104bc21d72747973317aaf99784b229aa56f6` |
| Normal host | `cc9a45e39c698fc60136c080e6bcdbbbb48c0f6aa9e6603c04edbc0add3e976a` |
| Sanitized host | `db5d30cbd377a28bf51c049fe14788fdc781e28565316ed8794418c586e99469` |
| Failing minimum sanitizer log | `42b484c8e385d62d7e6f39122175b938c45d73f77306d88275a7508cc1c16f00` |
| Earlier normal log | `fa2082322e222a993b9aa8f3519f939436f9bb8e2ecfdfa39cdccec3f95c5662` |
| Corrected current Linux log | `6232b5aa1d74d3478b845f6e5102fc622080df93999f1be479fce12aaf86f695` |
| Corrected minimum sanitizer log | `f6654ddc48a65a33897f0f7031b1c18e441b55fe3ed418318a6842dab3b9b3bf` |

## Shared BEAM report ledger

`Wotex.Matter.Native.ReportLedger` now owns the connection's immutable report
accounting. Its stream identities include the delivery generation. Registering
validated frames enforces sequential uint64 counters, 64 outstanding frames,
1048576 retained encoded bytes and 128 stream identities. Supplied consumption
tokens bind the exact stream and sequence. An exact retirement barrier marks
only that stream's validated reports consumed, removes its active identity and
leaves another stream's unconsumed reports holding credit.

Advancement returns a proposed cumulative ACK and replacement ledger. The
connection installs the replacement only after its Port accepts the ACK. Tests
exercise false and repeated barriers, reports after retirement, two generations
sharing an identity, out-of-order consumption, replay, exact byte/frame bounds
and exhausted counters. The ledger supplies the shared production bookkeeping
needed by retirement corpus traces; those traces are not accepted by these
unit tests alone.

The focused subscription/recovery/Runtime and ledger suites pass 27 tests on
both supported BEAM versions. The default gate passes 148 checks with 21
excluded, and ExDoc passes without warnings. Default-suite coverage is 89.6%,
below the unchanged 95% gate; release acceptance remains open.

The real lifecycle workload also passes with this ledger and the corrected
reaper binaries: 149.7 seconds on current Linux and 180.5 seconds on the minimum
sanitizer lane with leak detection enabled. Each repeats the 1000-read,
32-caller, 100-receiver-death and 100-open/close workload. The drain assertions
now include both pending reports and retained stream identities; each returns
to zero. Both lanes use the `cc9a45e3...976a` and `db5d30cb...9469` native hosts
recorded in the reaper cohort above.

| BEAM ledger artifact | SHA-256 |
| --- | --- |
| Report ledger | `f149431ee6513e98f15f48acec23dd0ef5ccf84271fc303cb3e67c4dac614cc6` |
| Native connection | `f9f05010d0d401bddd947557e84fef22e03d6cf5b9d397df6c05daaaf87edb20` |
| Ledger tests | `aece8b1745f41f59bbb5d4eb689e8cb84764897f50542f8a866c26911330baa0` |
| Subscription tests | `0e6428ddd265a57e5c3d4f364b816857fa454dad842eac98487b07b825810b36` |
| Lifecycle test | `faa2a63a705ef63c4baad067c196e070ac7702184dbea093db88beb01701269a` |
| Runtime loss test | `b57a972e3fd34fc2f77c959338db76c11e16f660e3a47401cd114401acf61b93` |
| Current focused log | `56885c45fcac0e394d25074fa3cd9543ff6fd956ecf368b58854dee03fa9db38` |
| Minimum focused log | `e225e8beed926673d5179ca0a0ca887184b5aa5d9c35f1a9b9e4ff6455cfa272` |
| Coverage log | `afdbd45008fbd6fa693c59b2c925bd47a4ed2999746e38b74387fcd33b451687` |
| Current Linux lifecycle log | `6d79a9814d38733aab56260e4ef52053329c6c11ab9eff30f01fa0972caf4d6b` |
| Minimum Linux sanitizer lifecycle log | `e1df2fabee5ed92465867f5097b43115860f37c9297d58f0b7ff84d8a6575eae` |
