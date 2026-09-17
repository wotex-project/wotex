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
The earlier one-shot Python factory adapter has been removed. The first-party
native client owns both persistent and one-shot controller lifecycles.
P09 executes the complete pinned SDK example-peer, negative-security,
interaction, subscription, restart, stress and resource matrix in both required
Linux BEAM lanes. The prior public build/run and clean package receipts are
recorded below with their source identities. They do not automatically attest a
later source tree.

## Native-only runtime boundary, 2026-09-17

The development package no longer contains `Wotex.Matter.SDK`, its Python
bridge, or the Python bridge tests. `Wotex.Matter.Native` is the selected
first-party controller for persistent and one-shot use. The removed factory
option has no equivalent native credential-import contract; callers must
provide the explicit existing-store or creation options in WMA.13. The generic
`Client` injection boundary remains for consumers and tests. Upstream pinned
SDK generation still uses Python at build time and is recorded separately.

`WOTEX_PATH_DEPS=1 mix check` passed after removal and the strict lint fixes:
warnings-as-errors compile, format, and 242 checks (2 doctests, 1 property,
239 tests), with 37 excluded. The default suite also launched the pinned
software-acceptance fixture in both current and minimum BEAM lanes. `mix lint`
passed with zero Credo findings and zero Dialyzer warnings. `mix coveralls`
passed the 95.0% floor at 95.1%. Doctor, ExDoc, Hex and dependency audits,
`mix hex.build`, the archive contents and out-of-tree compilation check, and
the Application-free check passed. The archive contained no Python source.
These local checks do not renew the older source-bound P09 native build/run and
full Linux matrix receipts below. Those lanes must be regenerated for a
current-source release claim.

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

## Native retirement trace corpus

WMA-B-F14 and F15 couple the native `ReportCreditManager` to the same BEAM
`ReportLedger` used by the connection. The bounded interactive driver writes
trace reports of the requested encoded byte length to stdout. ExUnit reads those
bytes, checks their length including the newline, records their actual sequence
and assigns consumption tokens. Native retirement emits its barrier through the
credit manager's production retirement path. The BEAM ledger validates the
observed barrier and supplies any resulting cumulative ACK back to the native
manager. Final counters come from that manager and are checked against the
number of report frames actually received.

F14 retires the first stream and consumes the second stream's exact report,
restoring all session credit. F15 supplies a false retirement sequence; the BEAM
ledger rejects it and emits no ACK, preserving the last valid native counters.
The driver receives inputs and generated ACKs, never expected counters or a
terminal-result oracle. These are accounting traces with explicit test payloads,
not SDK device reports or suspended Runtime-process proof.

All five corpus tests pass on current Linux and minimum Linux with ASan/UBSan
and leak detection enabled. The corpus now executes fourteen of seventeen cases;
F11–F13 remain unexecuted and its status remains `specified_unexecuted`. Both
six-test native CTest lanes, fifteen advisory queries, the 148-check default gate
with 22 excluded and ExDoc pass. The SDK host source is unchanged; the ready case
uses the corrected reaper hosts recorded above. Both contract executables are
rebuilt from the final driver source.

| Retirement trace artifact | SHA-256 |
| --- | --- |
| Native driver | `85482a229b539e08dfcedbc97d2f1e090027fb8ceadacfb80f939a4d85921206` |
| ExUnit corpus tests | `d8e979c162f3d31187d9089707366048b289859e27d8a0190354bce41c21c330` |
| Normal contract executable | `663e91e8a1bf17ac92e1dae376b826b4b5ae63bb6bec714c61a8da82b7ebb6d3` |
| Sanitized contract executable | `e2cfa9b19c7ae6a137e843ef2eed277563b69cfa0ce287addb9c7a18d91482be` |
| Current Linux corpus log | `c5bd838dd86633a7fc2c20ae0ddcfc84c25c7d0c83833b46950fd7cc64e4051d` |
| Minimum Linux sanitizer corpus log | `30e2ef9d1d7bea8ec79ccb16b0d7847d2087251954282d0aad7d3d00e91391b6` |

## Native cumulative report-byte overflow

The shared `next_report_byte_count` guard rejects addition beyond uint64 before
the report reaches the output sink. The credit manager installs the proposed
cumulative count only after successful transmission. Its encoded-size check also
precedes addition of the newline byte. Native boundary assertions cover an
initial 128-byte report, an exact uint64 maximum, one-byte overflow and an already
exhausted counter. This closes the unchecked native addition; generation-wide
failure escalation remains part of the broader C03 work.

Both SDK hosts and contract executables are incrementally rebuilt. Both six-test
CTest lanes pass, as do all five corpus tests on both Linux toolchains, including
ASan/UBSan and leak detection. Fifteen advisory queries, the default 148-check
gate with 22 excluded and ExDoc pass. The corpus remains fourteen of seventeen
executed cases, and the 95% coverage gate remains open.

| Byte-counter artifact | SHA-256 |
| --- | --- |
| Subscription header | `d0ae47550f9fa705341d27f85c3df5482ea017ea9354f4544c7987e4bd58e299` |
| Subscription implementation | `b9d7594a8991f33bf950b4066328976731ee632bf72ac556a50e8e8dff5bc205` |
| Native subscription tests | `84b343039695be4646f041318cb808f99bd7edd7f76f9f56bf50fb5f374bf0a9` |
| Normal host | `73ec6a7481a3d6ecf4c26f62112f6e6d1ef55ff7ffe8cecfb94d540f68dbfcd4` |
| Sanitized host | `e54d56a80c47b013119124e6e462a9cafe2d90bd4c4a5286a89874eb9590597b` |
| Normal contract executable | `cbf62b6fc4831fd3a5af8a80e0cf78ed36618afa32c0835d28f24420bd0b1799` |
| Sanitized contract executable | `a6e94424754cda5eebdcc0d28f6cb193aa506424e05852bce34d98ec7d45d0f3` |
| Current Linux corpus log | `dedd2a4b47be0bf63228f63bf75fb4128c8623c39ba0d24b0e3a1ad272a66617` |
| Minimum Linux sanitizer corpus log | `09cfd96a0cc8e2f72c1651457b346754e3ccbd809bb58f5e0fada616bd2244f4` |

## BEAM request admission bound

The native handle carries an unnamed ETS admission table owned by its connection.
Atomic reservations limit pending API calls, including the active call, to 64
before messages enter the connection mailbox. Each reservation binds its caller,
deadline and unique token; the table binds its process owner and session
generation. The connection releases reservations after consuming their calls.
Caller timeout alone cannot release a slot while the message remains queued.
Connection termination deletes the table with all remaining reservations.

The suspended-owner regression fails before this change: call 65 enters the
mailbox and returns `:timeout`. It now returns `:busy` with effect `:none`, leaves
the mailbox at 64 messages and performs no native I/O. Two further cases prove
that 64 expired callers retain their reservations until consumption, that expired
queued work performs no I/O, that capacity is reusable afterward, and that foreign
table or generation capabilities fail without reserving or transmitting work.
The table disappears after disconnect and its capability is excluded from Inspect.

The default gate passes 151 checks with 22 excluded; all 25 persistent-connection
tests pass on Elixir 1.18.4/OTP 27.3.4.15. ExDoc passes without warnings. These are
Port-boundary tests, not a new SDK peer or sanitizer cohort. Native source and
binaries are unchanged. Caller monitoring, interruptible control during I/O,
complete WMA-C03/C09 evidence and the unchanged 95% coverage gate remain open.

| Admission artifact | SHA-256 |
| --- | --- |
| Native API | `6ac8162330768f5175d8cc10827e7776feb49444a0c856e86a48bc7f0c97dc2c` |
| Admission implementation | `50a922001f3f039d213d961ebb3121f0bc5ca1a2633a7e424fc765e4a5901f6d` |
| Connection | `e274a0e68a65de4af8d1ebb5b43783964601861157f06162f1873daabc13894f` |
| Handle | `a1811a13b8a140c35939bf9c2740972bde61e03a0a1b434c1b4e51d5ef6dbf56` |
| Persistent connection tests | `49e9405dce072fbd0610497342b8cd76363bc6b7512edc1dfa01f6c6bf96085d` |
| Failing regression log | `f945f9c5b7bdbed67aea318d382c7d3a2db08e59cfee898c4f9607aa1360c951` |
| Current default gate log | `56d4e5e9579a2ec07514a73856cd408a0e7f6ca8b76fcc5673c8a1bbcd6a957d` |
| Minimum focused log | `047c0ebba8b1a6615f466772421a2799104ff1992934c3e14c1af75bf5dd9eb8` |

## Caller cancellation during native response waits

The connection receives admitted calls into a bounded FIFO queue and retains one
caller monitor and deadline timer per call. Its native response wait also handles
new calls, queue expiry, caller and receiver death, report consumption and initial
report delivery. Dead or expired queued calls release their reservations without
transmission. Active-caller death fails the generation, closes its native child
and returns effect `:none` to queued mutations that were never transmitted.

Two regressions fail on the preceding implementation and pass after the change:
a dead queued caller releases its slot during a blocked ten-second native call,
and active-caller death closes the connection within one second while rejecting
the queued mutation without effects. The first case also requires an expired
queued mutation to return effect `:none` while native I/O remains blocked. A
separate Port fixture withholds a health response until it receives a real report
ACK; the connection consumes its two existing report tokens and sends that ACK
without waiting for the health response. This fixture proves BEAM scheduling and
credit handling, not SDK device interoperability.

The default gate passes 154 checks with 22 excluded. The minimum supported BEAM
passes all 51 connection, subscription, recovery and Runtime stream tests. ExDoc
passes without warnings. Both host test lanes use four scheduler threads with two
dirty CPU and two dirty I/O threads. Earlier simultaneous runs with the default
VM scheduler count missed fixture startup deadlines; no deadline or assertion is
relaxed in the passing runs.

Both real SDK peer lifecycle lanes pass: 149.8 seconds on current Linux and
180.3 seconds on the minimum Linux sanitizer lane with leak detection enabled.
Each executes 1000 reads, 32 concurrent callers, 100 receiver-death cycles and
100 open/read/close cycles. The added assertions require empty request maps,
FIFO, caller-monitor maps and admission slots after sequential and concurrent
work, and deletion of the admission table after every connection closes. Owned
Ports and children return to baseline. FD counts remain 16 in all ten samples.
Current native RSS remains 21024 KiB; sanitizer RSS grows from 165000 to 189244
KiB, so this cohort makes no sanitizer RSS plateau claim.

These runs use the unchanged byte-counter native hosts recorded above. Both
BEAM lanes compile into fresh build directories: incremental compilation against
read-only source mounts failed while updating cached dependency timestamps before
any lifecycle case ran. This cohort is not a fresh full native/software build
receipt. Default-suite coverage is 89.2%, below the unchanged 95% gate. Explicit
cancellation when ordinary admission is full, complete fault/instrumentation and
C09 matrix evidence, and the remaining process-flow corpus remain open.

| Caller-control artifact | SHA-256 |
| --- | --- |
| Connection | `e0d20c85e01e30d62908d552b9ac86914f32188a1eab656884e592b1506c623d` |
| Persistent connection tests | `9010abfee0626a64c73d4a377a76c0df8e8f1a3a2a4bdd57bb5d91ee2beb1dde` |
| Subscription tests | `c463e4de5c8a94f95624d7842aba95865dc4652fd333c9d478a2837b9fb83aac` |
| Lifecycle test | `e87f0ae9111fa783d8ad659143c3f00c5aa4d413b8addca57a7ea2dbd8edd669` |
| Failing caller-control log | `021c69411405000a4b7c1df64febc6548df95396f0c9d18f165daf7ed5f94a22` |
| Current default gate log | `c42464ce4a1348d08f0d0d9a9a9bd93423fc7525a22ed114cf39afb2414256df` |
| Minimum focused log | `fc584da32be84262e4a745f3231f1e1386685dea236af24dcf510e8bf8856500` |
| Current Linux lifecycle log | `81e418ed5b4c82e2ee368347630aaf3a1a29513eb8f707ba8b52c9e5c1bcb667` |
| Minimum Linux sanitizer lifecycle log | `6831c8893a42dd43aa589cfb9a778ff80af7a759d2a36fb7f68e156330599c77` |

## Disconnect with full ordinary admission

Disconnect and invalidation reserve one separate closing record. Only its first
caller sends a control message; concurrent close callers monitor the connection
instead of extending an owner-side queue. Closing rejects new ordinary requests
and queued requests cannot start another native operation. An idle controller
closes cooperatively, including validation of its close reply and successful
process exit. A close during a pending native response terminates that generation
and reaps its owned child. It does not claim rollback of an active mutation.

The full-admission Port regression fails before this change with `:busy` from
disconnect. It now closes the blocked generation within one second and rejects
all queued work without transmission. The default gate passes 155 checks with
23 excluded; the minimum supported BEAM passes all 28 persistent-connection
tests. Existing concurrent-disconnect, malformed-close, nonzero-exit and stalled
shutdown cases remain passing. ExDoc passes without warnings.

The real SDK case reads a lighting peer, stops its exact owned native child with
SIGSTOP, admits 64 requests and runs 32 concurrent disconnect callers. Both
Linux lanes close successfully in 25 ms, release the Port, child and admission
table, and report effect `:none` for the queued toggle. Reopening the same durable
controller and rereading the peer proves that toggle did not change its value.
The final case passes in 1.0 seconds on current Linux and 1.6 seconds on minimum
Linux using the unchanged byte-counter hosts. Sanitizers and leak detection are
enabled for the minimum executable, but forced termination of the stopped child
does not execute its leak finalization. The reopened controller closes normally.

This cohort covers explicit connection cleanup under full ordinary admission.
Reservation-to-message caller failure, full native control/instrumentation and
fault matrices, remaining process-flow cases, full build/archive receipts and
the unchanged 95% coverage requirement remain open.

| Close-control artifact | SHA-256 |
| --- | --- |
| Native API | `b767b2d35e542e5b5a31cec205aa2a88ef881ee26910ecb4d602a97dfee4c837` |
| Admission implementation | `07529ca98b741ff4ed83412fe52eb72e8f62e2268fdcced9b8d467ce191e8bf3` |
| Connection | `0f865db064def982cf2e8ea007b38735c0e2c1ce682a25335c79a0b23aef97b8` |
| Persistent connection tests | `652b40c2edab79529f087e7a30f165fce845743526d6503746992a650d889787` |
| SDK close test | `8446468fdc472fba82dfa4d686418fd49931a00bae07f207e885932c923c8613` |
| Failing close regression log | `6c1f3b1d71dd9daa0d2ddb8fd7db3f901f109d75fdb220d9bea41c8decd7a802` |
| Current default gate log | `e4139d2e2269e7acfa1fa060ac96d4a6b0bc1fc038b3e731421358c946d0d82e` |
| Minimum focused log | `15207d6e309b131dd09a82c9c3afa7a62720c42a16793ea288e357fa453f386d` |
| Current Linux close log | `eb0fabd3d892e1b63b1368bd1bd95e2ed513d714fcb953268b14a5fb82f54d6f` |
| Minimum Linux sanitizer close log | `4625e2cd43ea0f341779aec8611cecaf4e4b9ed8971028274a7b59c0fb494e33` |

## Abandoned admission reservations

The connection owns one 50 ms maintenance timer for reservations whose callers
have not yet submitted their messages. It reclaims a reservation when its caller
dies or its deadline expires, consuming an already queued matching call before
releasing the slot. Requests already in the FIFO retain their caller monitors
and individual timers. Late messages for expired reservations return `:timeout`
with effect `:none` and cause no I/O. Closing records also retain their caller
and deadline; an abandoned close terminates its generation. Maintenance runs
during native response waits and stops with the connection. A suspended owner
retains at most its 64 ordinary call messages plus one maintenance message.

Two cut-point regressions fail before this change: a caller dies after acquiring
a request reservation but before sending the GenServer call, and a caller dies
after reserving close but before submitting its control message. The corrected
cases reclaim the unused request slot during blocked native I/O and close the
abandoned generation within one second. Two further cases cover an expired
unsubmitted request followed by a late mutation message, and an unsubmitted close
whose caller remains alive after its deadline.

The default gate passes 159 checks with 23 excluded, minimum BEAM passes all 32
persistent-connection tests, and ExDoc passes without warnings. The real SDK
lifecycle and stopped-child close cases both pass on current Linux in 150.4
seconds and minimum Linux in 181.5 seconds, with the unchanged byte-counter
hosts. Request queues, caller monitors and reservations drain to baseline;
admission tables, owned Ports and children disappear after close. All ten FD
samples remain 16. Current native RSS remains 21016 KiB; sanitizer RSS grows from
164992 to 189252 KiB, so no sanitizer plateau is claimed. The stopped child is
forcibly terminated; its leak finalization is not claimed.

Default-suite coverage is 88.6%, below the unchanged 95% gate. Native pipe
backpressure, full native control/instrumentation and fault matrices, remaining
process-flow cases and full build/archive acceptance remain open.

| Orphan-admission artifact | SHA-256 |
| --- | --- |
| Admission implementation | `6dd6f4983da8043ca230988b076688740f91807f8c825ad4bc8c65efc7d95d59` |
| Connection | `c642ec93665717bf0604115f6768f0b515af3961106be1e01b266181e26efd55` |
| Persistent connection tests | `25209bd459cc58bf5a3151ed43121bdab926172f0992b4f1d7bf102c43375cd9` |
| Failing cut-point log | `839ff353e9ae7687f93419872f610f30b4d6728c1dc5d4e5aeb9dad8ba39b2e5` |
| Current default gate log | `8a67499cb1b0df0ef1c804f58f34fac916a2c7666bc6e1f4e9e9ccc8e082e2aa` |
| Minimum focused log | `29cea15a0167fe77fc314de437c259c36ed9656ed9e881fff2fb87b14c92c022` |
| Current Linux lifecycle/close log | `1a62b26902b30425d3bf4c71c34887fe9bbc7bbc99cd9476b10ed6e4cea50c90` |
| Minimum Linux sanitizer lifecycle/close log | `13972ecc20ad23b415c15262b3deb75f15be5f1b41edc53c04dbdcb1aeac70b2` |

## Native stdin backpressure

Both request and control writes use non-suspending Port submission. A busy stdin
pipe cannot suspend the connection inside the Port BIF and prevent deadline,
caller-death or close handling. Failed report ACK and internal unsubscribe writes
schedule one generation failure. The ledger retains its last acknowledged prefix
until the ACK is accepted; failed submission cannot restore credit. The failure
is handled both while idle and during another native response wait.

The request regression fails before the change by returning caller timeout while
the owner remains suspended in the write. A second regression fails when a busy
ACK write leaves the subscription open. Both now pass, including ACK failure
during a pending request, one terminal notification and cleanup within one second.
The fixtures stop the exact owned child and fill its stdin with bounded transport
fault bytes using non-suspending test writes; those bytes are not application
requests, and the child is killed without resuming it to parse them.

The real SDK case exercises request and report-ACK pressure separately. The ACK
case first establishes a real lighting subscription and receives its SDK report.
Both Linux lanes reach a busy pipe after 16384 injected bytes. Current Linux
cleanup takes 13 ms for the request and 12 ms for the ACK; the minimum sanitizer
lane takes 19 ms and 18 ms. Ports, children and admission tables are released,
and each case reopens the durable controller and completes a health probe and
cooperative close. The full cases pass in 1.0 and 2.0 seconds. Forced children do
not execute leak finalization; sanitizers and leak detection remain enabled for
the normally closed reopened controllers. Native binaries remain the unchanged
byte-counter cohort.

The default gate passes 161 checks with 24 excluded; minimum BEAM passes all 48
persistent-connection and subscription tests. ExDoc passes without warnings.
Full native instrumentation/fault matrices, the remaining process-flow corpus,
full committed-source build/archive receipts and the 95% coverage gate remain
open. The most recent coverage measurement, in the preceding cohort, is 88.6%.

| Input-pressure artifact | SHA-256 |
| --- | --- |
| Connection | `0aa71e7ccc33ed3c1787048374e483f2d8bc28b0085212e566fabc9d2856013f` |
| Persistent connection tests | `3c7022b1cb9254110bee291ee0a039b140f818eefd35c4a525940b75950aed4b` |
| Subscription tests | `a5887f4f0809459c5b23d3d1675b1d7e234170e11329e12c584801f670f8d65a` |
| SDK input-pressure test | `af631bec1a29780f6fe3454ef0bda442f20aa77486be6baec355d21ec4b63b27` |
| Failing request-pressure log | `99ce76b9da2d6e04065bdfdfe22d801601bea0c6f1507ed490e5969c589c140c` |
| Failing ACK-pressure log | `c9cdee22d72398efa9e5523bfa5616aa1c5440033c13f822e9afc0df70aaee4b` |
| Current default gate log | `9ea774b3f1b6f53cf8bb296e43f6ddb7234ed099993ac7e2547a689881a52833` |
| Minimum focused log | `ca6d55896255b58e44d2565ca9575fee3fa99f124e065ecc037c303e6809461a` |
| Current Linux SDK pressure log | `27c6b47aa56b47e11e3f1791d49116ffa5e5772617a7e1cd5dd75b34982e51b3` |
| Minimum Linux sanitizer SDK pressure log | `4dfcb171ed6defb826bcf5fbd2a3fb4ee30b3628183c15294fd7d2d1f820d37a` |

## Request representation bounds before admission

The native request validator walks caller terms before mailbox submission or
recursive key conversion. It counts escaped JSON bytes, collection depth, entries
and aggregate nodes including keys. It bounds integer conversion to the signed
and unsigned 64-bit domain and rejects invalid UTF-8, improper lists, structs,
unsupported terms and atom/string key collisions. Context tags account for their
array representation. Final request and control envelopes are validated again
before JSON encoding, including correlation fields and the newline reservation.
Operation-specific schemas remain owned by their API and backend validators.

Persistent requests compute their absolute deadline before this validation and
pass it unchanged through admission and native I/O. One-shot requests validate
their representation before controller acquisition and retain their original
deadline through the same path.

The suspended-owner regression previously returned timeout with unknown effect
for an oversized mutation term. It now rejects ten malformed or excessive values
with `:invalid_request`, effect `:none`, zero request messages, no admission slot
and no native I/O. Pure boundary cases verify exactly 131071 JSON bytes plus one
newline, escaped control bytes, depth 24 versus 25, 1024 versus 1025 collection
entries, 4096 versus 4097 aggregate nodes including keys, and both integer
endpoints. Accepted encoded values also pass the bounded wire decoder.

The default gate passes 166 checks with 24 excluded. Minimum BEAM passes all 38
request-boundary and persistent-connection tests; ExDoc passes without warnings.
Both real SDK lanes pass the existing one-shot native/Runtime workflow and input
pressure cases in 5.6 seconds on current Linux and 9.9 seconds on minimum Linux.
The one-shot case performs five native operations and six Runtime operations,
including reads, writes, invokes, scalar preservation and resource cleanup.
Pressure cleanup and durable reopen also remain passing. These runs use the
unchanged byte-counter native binaries and enabled sanitizer/leak checks; the
previous forced-child finalization limitation still applies.

This cohort establishes representation bounds and deadline propagation. It does
not replace operation-specific schema evidence, remaining native fault/counter
and process-flow work, full build/archive receipts, or the unchanged 95% coverage
gate. The most recent coverage measurement remains 88.6% from the orphan-admission
cohort.

| Request-bound artifact | SHA-256 |
| --- | --- |
| Native API | `e838d63e6f1cffdb7c7e1a0a35763adb5313b2328e54e54b9f5d16c66c94a5a7` |
| Connection | `dcabccfcb42a604fb8994fe2c67cec12f8b2ebe467b427124ea1a83090b4f892` |
| Request validator | `580d19c69e754430ea1ca4d14b801b6a1b0f6b68f69134655639e8fb977a9135` |
| Pure request tests | `b0ba45a44c505dc9f2e44633b866f827c306c85aedc9d78ad254b729e02245f5` |
| Persistent connection tests | `4f3a8598a58102a596b6a7f069d6da8b614a678fe00ec72445ccb8379da6a2f9` |
| Failing request-bound log | `ec603cdb9ac24d8460dc10577b9562d120a4cfa9a74835f6c5c25903e0c30fbc` |
| Current default gate log | `27a8aaeb32f1e4df1b428e1fccf930d07b0830100b5ed6e6873b03a302830306` |
| Minimum focused log | `5df82a3ed65e9752992d01f2fae0cd1c5b4a188833f0e1fb05f610ed47848cba` |
| Current Linux SDK log | `c6282db7d933995a3b7fd966111acde793619d3cd757fe28731bf1afb5d9f05b` |
| Minimum Linux sanitizer SDK log | `a7e32b5b7de94f574f33524fb284b633bac875899c41ca970f1f0552fd6102ec` |

## Submission effect after caller timeout or connection loss

Each admission token retains an atomic submission state after its connection
and ETS table terminate. Caller failure atomically cancels an unsubmitted token;
the owner cannot subsequently submit it. Port submission first claims the token,
and a refused nonblocking write clears that claim. A write or invoke whose claim
survives owner loss returns unknown effect and remains permanently non-retryable.
The claim covers the last local step before the Port BIF, so owner death in that
interval is conservatively unknown and does not assert that the peer received it.

The queued-mutation regression failed before this change with unknown effect on
caller timeout. It now passes for both timeout and abrupt owner death, verifies
no native write, and rejects a later attempt to claim the cancelled token. A
second case observes the actual mutation in the fixture input before killing
the owner and verifies unknown effect without retry. Reservations remain bounded
and are not released merely because a caller timed out.

The default gate passes 168 checks with 24 excluded. Minimum BEAM passes all 36
persistent-connection tests; ExDoc passes without warnings. Both real SDK lanes
pass the one-shot native/Runtime workflow and full-admission close test, in 5.6
seconds on current Linux and 9.8 seconds on minimum Linux. Native binaries are
the unchanged byte-counter cohort; the prior forced-child leak-finalization
limitation applies to the stopped-child test. This establishes write/invoke
submission classification, not the remaining commissioning/window failure,
native fault/counter, process-flow, full build/archive or 95% coverage acceptance.
The latest measured coverage remains 88.6% from the orphan-admission cohort.

| Submission-effect artifact | SHA-256 |
| --- | --- |
| Admission | `46e0aa419688b1c9b9e4be2e7b264aaed790a2c38fff8874874f6e5042f46946` |
| Connection | `4f3dfe737218fba1dab27b91b744ed37e51aa96973232911009fe105da257f71` |
| Persistent connection tests | `9a5e5de3738466f0c04dea208bf99fb36c5649318edfd7159d6e8b5279fed47a` |
| Failing queued-effect log | `6980a1391373a27fe4b2912708fca618bba1a64c78d4f159ff500118edea8858` |
| Current default gate log | `c56f50d89cc77bd2b06d6cb9cef85f624163eb547cd38952acf51cc700408195` |
| Minimum focused log | `58138d75f7101dd30b456d427f7d7175b7749b9bc76a1faca450c106030fe17f` |
| Current Linux SDK log | `185bf9977b4c414db678ca82fd4787a1a259cba07fa748f0e45a380526a7d361` |
| Minimum Linux sanitizer SDK log | `593e6c66a70d4c2b4c64ca44600dd0f746384217c9bcb3e9fee128843aa33d8b` |

## Commissioning mutation effect at the IPC boundary

Commissioning and commissioning-window operations use the same submitted-mutation
classification as write and invoke when the owner disappears or a reply is
missing, malformed or decoded after the deadline. The expanded regressions
previously returned no effect after a malformed commissioning reply, and even
marked abrupt owner loss retryable. They now return unknown effect, permanent
classification and no retry. Both queued commissioning operations still return
no effect after timeout or owner loss, and cannot be submitted afterward.

Validated native failures retain their SDK submission evidence. The real SDK
commissioning-timeout case passes on both Linux lanes, preserving numeric status
0x32 and no effect for expired discovery before fabric mutation, and releasing
the controller. Current Linux passes in 1.2 seconds; the minimum sanitizer lane
passes in 1.7 seconds. Both use the unchanged byte-counter native binaries.
The default gate passes 168 checks with 24 excluded; minimum BEAM passes all 43
persistent-connection and commissioning tests. ExDoc passes without warnings.
The remaining native control/fault/counter and process-flow work, full build and
archive receipts, and unchanged 95% coverage acceptance remain open.

| Commissioning-effect artifact | SHA-256 |
| --- | --- |
| Connection | `d7c285ffe5912cf4c61d41f4fa1375fc1b90d89a19dcd1c5f09e426a113dcb50` |
| Persistent connection tests | `a252deb92a16141d239903582eeee77bf2003a2a2fadcd7b662a9109a555851b` |
| Failing valid-request log | `4d2a0e915fa9f81a9c2e20987e52ce6691d5c78ebcf1b28cf21178eb8afb505f` |
| Current default gate log | `6bb61f7f78d79affc2744f691dff4bbc5b3168d3a6482b8a6c6abef1c1008681` |
| Minimum focused log | `c30ef061355f02528357b16627804f75c099305d025927e59721d27b88f4ccac` |
| Current Linux SDK timeout log | `15339df7a103af60ce8e39efa14dba8635fbfc2036ab96d646710b73c0d39fc9` |
| Minimum Linux sanitizer SDK timeout log | `2ef7ba6abdffd4ff835984e9e7f214fef0857b444a82f7098cc05701e103d792` |

## Request identity exhaustion and Port release

The native parser admits the reserved `close` ID only for the exact close
operation with empty parameters. It can close an opened controller after the
ordinary uint64 counter is exhausted without advancing or resetting that counter.
Native tests accept the maximum ID, reject overflow, leading-zero and signed
forms, reject decreased IDs after the maximum, and reject the reserved ID on
another operation or with extra parameters. The reserved-close parser assertion
fails against the preceding implementation.

The BEAM allocator handles ordinary dispatch and internal cancellation with one
counter. The final uint64 value changes it to a fixed exhausted state and
schedules generation cleanup after the outstanding response. Cleanup uses the
reserved close ID; subsequent work cannot allocate another ordinary ID. The
connection regression previously stayed open after the maximum. It now observes
exactly open, the final health request and reserved close, followed by no further
I/O and removal of the admission table.

The minimum-BEAM blocked-ACK case also exposed a Port release race: connection
termination and native child exit could precede removal of Port driver state.
Waiting for the Port monitor alone reproduced the failure. Cleanup now waits
for both the monitor and `Port.info` removal within its existing deadline. The
final default gate passes 169 checks with 25 excluded, and all 52 minimum-BEAM
connection/subscription tests pass. Host lanes run sequentially because
simultaneous fixture VMs also caused unrelated startup-deadline failures; no
test deadline or assertion was relaxed. ExDoc passes without warnings.

Normal and sanitizer SDK host builds pass, as do six CTest executables in each
configuration and all 15 pinned advisory queries. The SDK request-ID case
exercises both a final ordinary health request and receiver-death cancellation
of a real lighting subscription. Both must receive the actual reserved null
close response, observe exit status zero and release their child, Port and
admission table within one second. The same Linux cohort runs the one-shot
native/Runtime workflow, native pipe pressure and five native corpus tests.
All eight cases pass in 6.4 seconds on current Linux and 11.8 seconds on the
minimum sanitizer lane. Final-ID cleanup takes 15/11 ms for ordinary/cancellation
on current Linux and 56/57 ms on minimum Linux. These final runs use freshly
commissioned, separately owned lighting peers, which are also reaped afterward.
A preceding run against a long-lived fault-test peer timed out during subscription
establishment after old subscription-resumption traffic; that run is not counted
as passing evidence. A local orchestration attempt also failed before tests
because its environment omitted the installed Mix/Hex homes; the final run
supplies those paths and the UTF-8 locale explicitly.

The corpus remains 14 of 17 executed cases; F11–F13 are still open. Native
stdin interruptibility, callback/resource instrumentation, full fault matrices,
committed-source build/archive receipts and the unchanged 95% coverage gate
remain open. Forced pipe-pressure children still do not provide leak finalization.

| Request-ID artifact | SHA-256 |
| --- | --- |
| Connection | `0c37003c005881c4e8669cd7ae80c35b1df8c1909287586aa36cd305492044b6` |
| Native protocol | `65dd646b1d0cead661520a87ee91e8888d026d5615272980eeec2b0d81e55466` |
| Native controller tests | `8450171444567227c25f072e29bac3c8013d935928e9007c7570c0a1adc0ab99` |
| Persistent connection tests | `16344de4ad2ec4f4eb06a9a8990ead9b10634bd7a7b5311fc2561733b134d645` |
| SDK request-ID test | `40f96a9365dc206f6d72788ff09abeac1e2b19e842a06db5d2ef5730f24e915f` |
| Current native host | `504102f778c2dd0cfe861618fbfef3529da07b50aaf1881990a779f5ea9b6866` |
| Minimum sanitizer native host | `bfa39ca5139dc4d28992b5a905ed0f4dda6a1bcf3a298b58dae1924ec5b15d7a` |
| Current contract driver | `97f729b1a69442a2cbbe71e71b27efc083f90ca98739544d9c39beb5f8457048` |
| Minimum sanitizer contract driver | `d8554972e5bbe5df98ddaeb5522a542c6b246579d92b7e72852c41a8538378c5` |
| Failing maximum-ID connection log | `f4cc648014a9367781ff8212dcde4179411034fc8fe230069c0efce0245e19f9` |
| Failing reserved-close native test | `67005468125832ec6253005ca6fd67ac7d13a3d016c05ecb22381bcb5fea5ade` |
| Failing monitor-only release log | `62249eed1d4f95a0dce0d9531703aff5b9c52e4462c86476eaa845d6b4cc0ab5` |
| Final current default gate log | `4ed38757fa146ce46fdf50b13fd514cc28b0c959045b4289115017c723cdee21` |
| Final minimum focused log | `d485780897a86b040a74f327be66b502931c0417b7e7b0bb267801f09545a0d0` |
| Native CTest log | `97a87b0eb728951f5e8ec3d13d0174690d9c5bb3e4342e367595d29932df5fc3` |
| Native SDK build log | `75a52ce1a003c02b230240537508bed51afebe35b9b481bdf056470b5b2fd542` |
| Advisory audit log | `947d36e4c60803d5242b03f9d04555a254b09399c2f8881ec39964b3c09c20a5` |
| Final current Linux SDK/corpus log | `52242432779d891fb6b7fc5ed8772ddb0f3bfc443a54eb05923db6453f6291e3` |
| Final minimum Linux sanitizer SDK/corpus log | `cd4aaca9df3dfb9d9375a289e0484b403789156af635d54740e05a0b669b40d3` |

## Native input lifetime during pending work

The native host owns one input-lifetime thread through controller destruction.
It polls stdin hangup/error state without reading command bytes. Loss of stdin
starts a 750 ms cooperative grace; if native execution or destruction remains
blocked, the monitor terminates the process. Normal return joins the thread.
The monitor never invokes SDK cleanup concurrently with an interaction.

The real SDK regression submits a read for an unresolved operational node and
kills its BEAM connection while that request remains pending. The preceding
host survived the one-second limit and returned only with its five-second request
deadline. The corrected host releases the child in 760 ms on current Linux and
767 ms on minimum Linux. Both cases release the Port and admission table and
reopen the durable controller successfully. Native unit tests also exercise
ordinary monitor destruction and hangup during a blocked child, including reaping.

Both newly built SDK hosts pass the full lifecycle workload against freshly
commissioned lighting peers: 1000 sequential reads, 32 concurrent callers,
100 receiver-death cycles and 100 open/close cycles. Current Linux passes in
149.4 seconds and minimum Linux in 179.4 seconds. Admission, caller-monitor and
Port counts return to baseline, and every native FD sample remains 16. Current
native RSS remains 20988 KiB; sanitizer RSS grows from 165756 to 190080 KiB, so
no sanitizer plateau is claimed. All nine subsequent owner-loss, request-ID,
one-shot, pressure and native-corpus tests pass in 7.9 and 13.7 seconds. The
fixture-owned peers are also reaped.

The default gate passes 169 checks with 26 excluded; ExDoc, both SDK builds,
six CTest executables in each native configuration and 15 advisory queries pass.
ASan/UBSan and leak detection remain enabled. The hangup fallback and deliberately
killed pressure children do not execute callback destructors or leak finalization;
their evidence establishes process/resource release only. Normally closed
controllers retain the sanitizer cleanup checks. Native control interruptibility,
full callback/resource instrumentation and fault matrices, F11–F13, complete
build/archive receipts and the unchanged 95% coverage gate remain open.

| Pending-owner artifact | SHA-256 |
| --- | --- |
| Input lifetime | `ec4f9066a4a2c65ca68b9b3eaa6f4826b37a192ef30698c3807e0be88653ae55` |
| Native entry point | `911d66c61b30a6c4693df3d174ee241ad8ab94198f8d1705e0f006d31373c4cc` |
| Native controller tests | `633abbe0d13f03e82fb375916312d36b9b8c15180c1b51a4d9a0c55bfb8e2c1d` |
| SDK pending-owner test | `ffb56588d141a92f505f312a8571ab9101691563429e9236e7905361fb1e4609` |
| Current native host | `85ad7deadd3198c7a03cd05bad7c61ca2e7870fab45ecf1f1c2e67fdb0b3ad36` |
| Minimum sanitizer native host | `a915362353c5d0bd9fd6f4cd194993fab8f7ad0ff94c3805e154978aa4eadba3` |
| Failing SDK pending-owner log | `9ebbefd9143acfb8da1cfa7cc551031b3a90e61b972deeb7c97c8a24893a4b55` |
| Default gate log | `988fff4c065ea61245503ad66e819f9fbd7f8e13da01be1b684a6464a6966116` |
| Native build log | `58cb1fe3e81fef3b36b9541416e486266cee32ed808c4267e5d5b0f51fac9ffa` |
| Native CTest log | `6dff125ed425183961a2b2b6c77917028eaedac892a9eaf3179eb751339ebc96` |
| Advisory audit log | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |
| Current Linux lifecycle log | `7dbafc18161996cedb961a8a227eaf4295875f04dc137ff4222462b3c4c935de` |
| Minimum Linux sanitizer lifecycle log | `2651e791861d75df07b5094f91ca76aefe797d2faec2ea734ca5481b57ee5175` |
| Current Linux nine-case log | `61e18de459e671a2dd3d28ed0575351b0c4a5c7bfb66e643863183666cf26013` |
| Minimum Linux sanitizer nine-case log | `dd6c34b90b4160a7b2cc12a11653a9c3d00e3c04a9cdb5da346e7e27c841f048` |

## Native output failure and writer ownership

A failed native output write or exhausted output reservation marks the shared
writer unhealthy, rejects later output and signals the input-lifetime owner.
That owner retains one 750 ms cooperative grace even when stdin remains open
or repeated failures arrive. Output failure never invokes concurrent SDK
destruction. The writer joins its thread even when the thread has already
marked itself stopped. Ordinary and exception-enabled stream failures use the
same path; each writer signals channel failure at most once.

The native regression reproduced an abort from destruction of an unjoined
writer. Both stream modes now return failure normally. A separate owned-child
test keeps stdin open and repeats failure signals; the child still exits and
is reaped within one second. The SDK test redirects stdout to `/dev/full` and
keeps its command input open. The preceding SDK host exceeded one second and
required test cleanup. The corrected normal and sanitizer hosts exit with
failure in 806 ms and 919 ms, including process startup. This test covers
ready-frame output failure before controller initialization.

Both Linux toolchain lanes pass ten real-SDK/native-corpus cases in 8.8 and
14.7 seconds against fresh owned lighting peers, including this regression,
pending-read owner loss, request-ID retirement, one-shot native/Runtime
operations and pipe pressure. Fixture-owned peers are reaped. The default gate passes 169 checks with 27 excluded; ExDoc, both SDK builds,
six CTest executables in each configuration and 15 advisory queries pass.
ASan/UBSan and leak detection remain enabled; forced lifetime termination
does not establish callback destruction or child leak finalization. Normal
controller close retains the sanitizer checks. The preceding full lifecycle
workload remains identified by its preceding binary digests.

The last full coverage run passes its tests but reports 89.0%, below the
unchanged 95% requirement. Native control interruptibility, report-counter
exhaustion escalation, F11–F13, full callback/resource and fault matrices,
complete software-run orchestration and fresh build/archive receipts remain
open.

| Output-failure artifact | SHA-256 |
| --- | --- |
| Input lifetime | `9c42537441f8b3afbd23a3e22899bb9c1cc92373882e5bc570e9b041b3e7a614` |
| Native protocol header | `302a5d1fd30fba074caf50ab7493fa4e7b5f1e263c56f710427e5430b6ab8dc4` |
| Native protocol | `416cf7a857e4734613df04decd19940b7d7897bd6edc8d7bc3bff368b994ca67` |
| Native entry point | `b98da65e9cc751acb317e114b2cee5c11ed1ce40671ba4870785780096d00795` |
| Native controller tests | `11938776366bd2206c5b939a25b7f38309599c32f5e5732f5c27431ad5565d0f` |
| SDK output-failure test | `548776efd47e3f236771b03f64bbbe68e2475a03593a1b988460efa3fcd98482` |
| Current native host | `d3d74b75c3fd55afda0954781045e66a45ea08c329a697923034a8a938c7e632` |
| Minimum sanitizer native host | `7f8e2a16c007a00d5e9e4509d660acdfcb2f74f673eba289554b53dda232232e` |
| Current contract driver | `96173bba653cd321424232e0c0c64a8171416dc85eaea29341391e8b062ffe3f` |
| Minimum sanitizer contract driver | `3c267bcea35f6474440a6582f354d8cc0c116c8e0ef1747a8d054ce11b3d4aa0` |
| Current output harness | `fefbf5b4a950d081b410ca83cdd4e6b62bc676ed19c74070c9eea8374750d2b7` |
| Minimum sanitizer output harness | `05cd37b2761e6710f6ceb41c61d5a13028fbfcd3b9c75435b8d4dee1634989ce` |
| Failing writer-destruction log | `2c72eacce15b9cf69d42dee11ebdc84385a6112b440eaccb76e45d149bb60ecf` |
| Failing SDK output log | `1c18252900ac7460c2e08f6fabae94de4cfbba7d2469068e51051a465290d6e0` |
| Native CTest and SDK output log | `f637ca081765d6d7270ec8547d8857199747ebb803d8357a8c4dd962f504c4ea` |
| Native build log | `58cb1fe3e81fef3b36b9541416e486266cee32ed808c4267e5d5b0f51fac9ffa` |
| Advisory audit log | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |
| Current Linux ten-case log | `a8d8935c2b00a655901f817c74dbc48b53ccbf0a3e4e900c7423f2f0ac154ad4` |
| Minimum Linux ten-case log | `5b5a51780caa4b80a824dc3c71288dac174885fea8bd0de65895fd7993fc3ba1` |
| Default gate log | `eb88afcb8a71329770b8897e3416feba83ffee2d98d14cfb5cc9ad3a9f461704` |
| Last full coverage log | `689557793bf71675007004d7aea485a21f9a62be10285e4836cd1f25b1618500` |

## Native report-counter generation failure

Exhausting the shared report sequence or cumulative byte counter fails the
IPC generation. The protocol latches failure, rejects subsequent reports and
operations, and signals the lifetime owner once. SDK callback paths do not
invoke controller destruction. Reports, subscription errors, recovery status
and retirement barriers share this output-failure path. Failure while draining
acknowledged or retired credit also closes the generation. A stream queue
overflow with functioning control output retains the connection and emits one
stream terminal and retirement barrier.

The boundary regression seeds sequence and byte counters separately in a
dedicated native unit-test library. Before correction, a health request still
succeeded after exhaustion. Both exhausted states now reject reports, signal
failure once and close on the next command without a healthy response. Adjacent
last-valid counter tests retain exactly one accepted frame and its exact credit,
reject excess output and acknowledge the retained record without rollover.
Report, error, barrier and status sink failures suppress repeated output and
never run teardown inside the callback. The stream-overflow test preserves a
healthy response and does not signal generation failure.

`WOTEX_MATTER_PROTOCOL_TESTING` is defined only for the separate subscription
unit-test library. Its counter-seeding methods are absent from both production
SDK hosts and both shared contract drivers, verified with their symbol tables.
No wire command or production host option can seed these counters. The seeded
cutpoints establish protocol/accounting behavior, not an SDK workload containing
2^64 reports. Real SDK resource-release evidence remains separately identified.

The default gate passes 169 checks with 27 excluded. ExDoc, both SDK builds,
six CTest executables in each configuration and 15 advisory queries pass. Both
Linux lanes pass the ten SDK/corpus cases in 8.3 and 13.3 seconds against fresh
owned lighting peers, which are reaped. The minimum lane retains ASan/UBSan
and leak detection; forced lifetime exits still do not establish callback
destruction or leak finalization. F11–F13, native command interruptibility,
full callback/resource and fault matrices, software-run orchestration, fresh
complete build/archive receipts and the unchanged 95% coverage floor remain
open. Last full measured coverage is 89.0%.

| Counter-generation artifact | SHA-256 |
| --- | --- |
| Native CMake targets | `622dacdf72730071bfc3f1050cc59be815adbfe47c4eca204dbc3b7f5e7c8e3a` |
| Native protocol header | `f2b7ef21a17545d1225671a800e1e01fa8e400da860369b187c98915ec220b02` |
| Native protocol | `d5c65c8f1aa15fff19904d69e34fc7687aa02d2e928d31e0a2177ef99a16aead` |
| Native report-credit header | `ac193433104b2c1e4f985c1dc8d1fd1fb192fe18bfee7a04b2094f2389afa6e4` |
| Native report-credit implementation | `6a74b6c3ee362982a5c6483757b935c7cef67bafb9cf39fb3b31214fa8f1c8aa` |
| Native subscription tests | `6d52bfbb3903741e7cc94d685b7277280d2675751bbfe85ce10b44570f2f7d93` |
| Current native host | `c0e7377ed8ba943355f740c51169006b9e834c3ff59177cfff9f6e305493c720` |
| Minimum sanitizer native host | `8f15e5f371f4b19e8065854d1ccc2a4257a5fa2c4e6f3970168a3a8ca0033a6f` |
| Current contract driver | `984dda63f141d5102bfd680403677067a068536835e26dfccd1cf8fb9189bc09` |
| Minimum sanitizer contract driver | `0e47ddf12c01567962fac73366e3ccbb4e6e27ac6532ea594a3f55f9ad361784` |
| Counter-exhaustion failing log | `2bfc16fa3b8c494a2e2b7cf9ee3f781908f83eee1e4148a0938ebebee0dba060` |
| Native CTest log | `806bfc718d8c245731849b6cd488e38a3e106217b45c6dc49b8ace0093c050f5` |
| Native SDK build log | `cd72e80c42169268074173399ff10d4c9e873d45bc605749952810a9d2d083c7` |
| Advisory audit log | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |
| Default gate log | `f570d8c65a6d73c7561933ddfccfe1d4619706af64bf08b72b0aeaddf35476d0` |
| Current Linux ten-case log | `dea02366ecb4fbfaff5036652da6cd05433c55d2f6ec21f3aa05173a1b0d9e69` |
| Minimum Linux ten-case log | `79186d981d46e5709e73bc6812b5ff4165986cfbbce87528f3b13ff509122714` |

## Ordinary native stream ownership

Each admitted ordinary native subscription owns a linked and monitored report
validator before waiting for SDK establishment. The validator checks the admitted
path, descriptor value and receiver capacity, then returns the opaque report
token to the connection. The connection verifies the owner, active subscription
and outstanding token, checks receiver capacity again and sends the public
tuple before acknowledging native credit. The connection alone sends public
reports and terminal messages, so delayed validator replies cannot become
post-terminal deliveries. Runtime acknowledged subscriptions retain their
existing relay ownership.

Cancellation marks the subscription closing before attempting native control
output and reaps its validator. A failed unsubscribe write cannot cause a second
terminal during channel cleanup. Retirement and session close also reap owned
validators; an abnormal connection exit propagates through their links, including
to suspended validators. Final receiver capacity remains the configured C05
limit. The intermediate validator mailbox is bounded by the 64-report session
credit ledger. A descriptor-mismatched value fails before public delivery or ACK.

The initial regressions failed because ordinary subscriptions had no separate
owner. The corrected tests suspend that owner while a fixture health request
waits for report credit, then verify delivery and completion after resume.
Stream-owner loss, owner loss with a blocked native pipe and connection loss
with a suspended validator release ownership. The blocked-pipe regression also
reproduced a duplicate terminal before the closing-state correction. Tests for
Event identity, explicit null, recovery and receiver overflow remain passing.
The default gate passes 172 checks with 28 excluded; all 21 minimum-toolchain
subscription/recovery tests and ExDoc pass.

Both real SDK lanes pass the full lifecycle workload: 1000 reads, 32 concurrent
callers, 100 receiver-death cycles and 100 open/close cycles. Every receiver-death
cycle now identifies and monitors its actual stream owner and proves that owner
is gone. Current Linux passes in 149.4 seconds and minimum Linux in 174.5 seconds.
All native FD samples remain 16. Current native RSS remains 21084 KiB; minimum
sanitizer RSS grows from 166192 to 190496 KiB, without a plateau claim.

The subsequent eleven-case SDK/corpus cohort passes in 9.9 and 15.5 seconds.
The new SDK test pauses an ordinary stream owner, invokes Toggle on its owned
lighting peer and verifies that the real report retains native credit until
resume. It also kills the stream owner while preserving native health and
kills the connection while its stream owner is suspended, checking both
process lifetimes. The fresh fixture-owned peers are reaped. Native binaries
are the preceding counter-generation cohort; ASan/UBSan and leak detection
remain enabled, with the same exclusion of destructor/leak-finalization claims
for forced exits. These tests do not discharge the 10000-callback F11–F13 corpus
cases, native command interruptibility, full fault/resource instrumentation,
software-run orchestration or fresh complete build/archive receipts.

| Named-owner artifact | SHA-256 |
| --- | --- |
| Connection | `69f2975e68701391e1162669c6bba8518388c028a1c8ac675fe15f76ce106a8a` |
| Named stream owner | `d07fd50e83259eb442bcbaee1a8e2248aeb966622d16a02961613e832358ed1f` |
| Opaque delivery | `40f973344dd632895b38c256675637c8397c2f0895ce8ec870543e75a28c661d` |
| Subscription tests | `56b853782b0c1acc068b76452e466dac83a6aaa1302dd6afdf6ffa9443383986` |
| SDK stream-owner test | `3716633263edba925c3d527b7248c214443d1e40bfc69241e0ac6e2805a2343e` |
| Lifecycle stress test | `3cc00ec15d0961cec1aa6958c99c230aab5ee8fd6d360cf93760ac750eccac5f` |
| Missing-owner failing log | `1579b55a93fc71bbb5a35831b1ee2838c55026fe6075f30389c1b31ca8833b88` |
| Duplicate-terminal failing log | `dabb3de7896f72323eae5024f6c7517c5d0006fff6a99c6e75845a9f564a5096` |
| Current default gate log | `4452725020f4dcd6d14d3839ebe19ffd2b5b04b51468dd2589088c433245c978` |
| Minimum focused log | `ecdab58c22609efa9568fac3747776669dbe21f907a1de57048c97d050f82279` |
| Current Linux lifecycle log | `16337496fc50fc666bf5f44172c5fa16626bc71ce790f266d9820655ce07c1e9` |
| Minimum Linux lifecycle log | `9799bbeff32870c2d5f382a4ba22d29e83111ef49c853d5af0a3cfccc9e2beb2` |
| Current Linux eleven-case log | `61cf02a6dc7445ef4fc680c56d83f1b27aa17d01bdefcc7d084231c12da74dd0` |
| Minimum Linux eleven-case log | `4f15599887f9b2393785182141cf215d5ae98ac7be10f3de00defa1075433e66` |
| Full coverage log | `69353b9a0ec84d34b060b00e45df206bf35bffe6c8cb36b3d804a0132af398f9` |

The full coverage run passes all 172 checks with 28 excluded and reports
89.0%. The unchanged 95% coverage gate remains unsatisfied.

## Ownership loss during subscription establishment

Receiver or stream-owner loss during unconfirmed subscription registration
closes the native generation. The SDK wait may prevent control input from
confirming cancellation, so the connection bounds teardown without assuming
that registration succeeded. Established and recovering subscriptions retain
their ordinary unsubscribe path. A successful registration reply can install
a handle only while the subscription remains establishing and both receiver
and stream owner remain alive.

The bridge regression previously retained a pending API call beyond one second
after receiver loss. The real SDK regression likewise retained its connection
while registration for an unresolved operational node remained pending. Both
receiver and stream-owner loss now terminate the pending call with a structured
no-effect error and release the connection, stream owner, Port, child and
admission table within one second. Focused current-Linux cleanup takes 13/11 ms
and minimum-Linux cleanup 29/19 ms for receiver/stream-owner loss. Every case
reopens the durable controller and checks health. A separate controlled bridge
test queues receiver loss before a successful native registration reply; after
resuming the connection, the call returns `:receiver_closed` without a live
handle.

The default gate passes 174 checks with 29 excluded. All 23 minimum-toolchain
subscription/recovery tests and ExDoc pass. Both fresh-peer SDK/corpus cohorts
pass all twelve cases in 10.8 and 17.1 seconds; their fixture-owned peers are
reaped. Native binaries remain the counter-generation cohort. ASan/UBSan and
leak detection stay enabled, but forced pending-child termination does not
establish SDK callback destruction or leak finalization. Normal reopened
controllers retain the sanitizer close checks. The preceding full lifecycle
workload remains identified by the named-owner receipt. F11–F13, native command
interruptibility, complete fault/resource instrumentation, software-run and
fresh build/archive receipts remain open. Last full measured coverage is
89.0%, below the unchanged 95% requirement.

| Pending-subscription artifact | SHA-256 |
| --- | --- |
| Connection | `979ee60937dee312787bf1b06c98f60455735c6f985237c979b8ee46a1501933` |
| Subscription tests | `53bf88862f384ed08bf03c7f03164cb3971d06121158869e198e4881eafb4ff0` |
| SDK pending-subscription test | `7974b4421bbc330587f5d1d0f03c58d752630cace2ae985bcd5c5ba37daf665e` |
| Failing pending bridge log | `f1e9d626db70fde33c4f9cd3c746a6f8b919d65eeec19e0b86f2b937e5d9eb10` |
| Failing pending SDK log | `39509a83803c906cce7a7503b60275379faa46133b3f39d972bfc2b84d04a681` |
| Current default gate log | `2f8f80a4e0f3c44420844d88ca1300d50c77a77b899678388fcc34bc7643c39f` |
| Minimum focused log | `d7859501ce5c3049fe66f5cc171c2231b6b0fd6b58d82a426d4161fd005490be` |
| Current focused SDK log | `1289843032fedba67f3a8ce8973229a8e33de93123d1264208feacfb518f7c01` |
| Minimum focused SDK log | `ec58f3c8dc69dcccb7665be001dd21afe54eaef9f1d5b75ae9c485bb276b0cbc` |
| Current twelve-case SDK/corpus log | `6e9f3fba3e1e4ac06c1f1fd220e7c9243f2b19587215d245a621f6cbf60db753` |
| Minimum twelve-case SDK/corpus log | `d0342fd2c5804f4efa670747217088815a76959510a70abd1c15a3c82f11adbf` |

## Native result identifier bounds

The BEAM decoder enforces WMA-B02's signed/unsigned 64-bit integer domain at
every JSON value depth. Attribute and event report identities are positive
uint64 values, and commissioning fabric IDs remain within that domain.
WMA-S01 concrete result paths use `Address.new/1` for identifier widths and
reserved ranges, including paths in batch success and failure entries. Valid
boundary values retain their exact integers; finite JSON floats retain their
representation and remain subject to operation-specific type checks.

The failing run exposed six boundary failures, including a public subscription
report with ID 18446744073709551616 and a successful native read with reserved
endpoint 65535. The corrected process-boundary tests reject the report before
public delivery or credit acknowledgement and retire the generation. Reserved
read/write result paths likewise retire the generation; the submitted write
retains unknown effect and permanent, non-retryable classification. These
malformed bridge fixtures establish decoder behavior, not SDK interoperability.

On Elixir 1.20.2/OTP 29.0.4, `WOTEX_PATH_DEPS=1 mix check --no-retry` passes
178 checks with 29 excluded. On Elixir 1.18.4/OTP 27.3.4.15,
`WOTEX_PATH_DEPS=1 mix test test/wotex/matter/native_frame_test.exs test/wotex/matter/native_wire_test.exs test/wotex/matter/persistent_bridge_test.exs test/wotex/matter/subscription_test.exs`
passes all 74 tests. ExDoc passes with warnings treated as errors.

Both fresh-peer SDK/corpus cohorts pass all twelve cases in 10.8 and 17.1
seconds, and their owned peers are reaped. Native binaries remain the
counter-generation cohort. The minimum lane retains ASan/UBSan and leak
detection, with the preceding forced-exit limitation. These decoder changes do
not establish the missing F11–F13 process-flow cases, native command
interruptibility, full fault/resource instrumentation, software-run orchestration
or fresh complete build/archive receipts. The last full measured coverage
remains 89.0%, below the unchanged 95% requirement.

| Identifier-bound artifact | SHA-256 |
| --- | --- |
| Native decoder | `f30be9ffaaa20bd5b36baa7b48e078ce70e824771bda6a93941d73338f85edc1` |
| Frame vectors | `967b996f6a1f3fd2e742490fb12299e5fbd7a5add153236c5e001b554163c993` |
| Result vectors | `6c908b7bb55964a8d8c3dacddf9554ef0ae15cc77cac70a3250da64ec70fbd0b` |
| Persistent boundary tests | `852d00322c6fe230489f062fc24d1ac6db3e795747d26bf1e64be69a5b80bded` |
| Subscription boundary tests | `a2226e2a545c702e7d6c124f8cafa26276204e7c43a62436dc86ccdeb7973aa5` |
| Failing boundary log | `407f019ef4416915d6a9138bf37aedd5f395663fc6c0652604c907a31b5cea17` |
| Current default gate log | `56b40033b465534bb0907f0b85d399f89e36e130186c3b54e946289de4d9bb86` |
| Minimum focused log | `58e815df2f69393884b2e6a82c565f4ac84d759d96bcb574d206af807562a94e` |
| Current twelve-case SDK/corpus log | `19a671ef2de79a11adf9671ea579c5441ddd21663384475c7769e5aba67f54e5` |
| Minimum twelve-case SDK/corpus log | `c15e02659ce97ff9f17e752e551b6cdc84f64b22bc4fb3c37d7ab0c1993726d1` |

## Native process-flow backpressure and cancellation

The WMA-B-F11–F13 process-flow cases execute against a separate SDK-linked test
host. One owned producer derives 10000 distinct report identities from an
actual lighting subscription report, retains one callback value per iteration
and feeds the production report-credit path. Each callback value is destroyed
after its attempt, including callbacks refused after retirement. The encoded
JSON TLV value occupies 128 bytes, including internal whitespace; its Boolean
value still passes the production descriptor and delivery checks. The BEAM
observer suspends the actual connection, stream owner or receiver, observes
native reservations and actual mailbox contents, checks native health after
retirement, then closes and reaps the connection, owners, admission table,
Port and native child. Expected corpus outputs are never passed to the host.

The report queue retains its complete head value until both stream and session
credit permit transmission. The previous drain moved from the head before that
check, losing report identity and byte accounting on a later acknowledgement.
The failing C++ regression reproduces that loss. Partial-credit and other-stream
acknowledgements now preserve FIFO values and exact reservations.

A local cancellation may cross a native terminal and retirement barrier. The
BEAM connection accepts one matching native terminal while closing, preserving
the already selected public terminal and rejecting duplicates. Native
cancellation recognizes an exact retired stream through its bounded outstanding
credit record, or through the ownership established before its in-flight SDK
cancellation. It does not repeat the SDK cancellation or retirement barrier.
Unknown and mismatched generations fail before SDK dispatch. Tests exercise
retirement before and during SDK cancellation, including SDK cancellation
failure, and reject the identity again after its retirement record is released.
The failing BEAM regression closes a healthy connection before this correction;
the corrected regression preserves health and emits one public terminal.

The software build requires normal and sanitizer process-flow binaries and
includes their hashes in its receipt. Native-only receipts do not require them.
Both ordinary production binaries pass a symbol audit excluding process-flow
instrumentation and counter seeding. Both SDK builds and all six CTest targets
in each normal/sanitizer configuration pass. The live OSV audit passes all 15
queries for the pinned dependencies. The default gate passes 179 checks with
32 excluded on Elixir 1.20.2/OTP 29.0.4; ExDoc passes with warnings as errors.
All 35 focused subscription, recovery and build-receipt tests pass on the
minimum toolchain in 21.4 seconds.

Both fresh-peer cohorts pass all 15 SDK/corpus tests, including all 17 native
corpus cases, in 15.1 seconds on current Linux and 22.5 seconds on minimum Linux
(Elixir 1.18.4/OTP 27.3.4.15). The owned peer tasks finish and their processes
are reaped. Each process-flow case records 10000 callback acquisitions,
destructions and iterations, one completed SDK cancellation, one retirement
barrier, one public terminal, no post-terminal delivery and normal native exit.
Queues reach 64 reports while outstanding native credit reaches 16 reports.
The source runs take 25.5–28.4 ms on current Linux and 65.2–68.3 ms on minimum
Linux. Resume observations occur at 50–52 ms; a stream owner already retired
before resume is recorded as closed. All owned resources are gone at
83/56/76 ms for F11/F12/F13 on current Linux and 124/126/119 ms on minimum
Linux, within the unchanged 1050 ms limit. Every normalized five-field result
matches the immutable corpus oracle.

The separate lifecycle workloads pass 1000 sequential reads, 32 concurrent
callers, 100 receiver-death cycles and 100 open/close cycles in 149.1 and
174.6 seconds. Every receiver-death cycle reaps its actual stream owner.
Native FD samples remain 16. Current native RSS remains 20980 KiB; minimum
sanitizer RSS increases from 166064 to 190364 KiB, so it does not establish a
plateau. ASan/UBSan and leak detection remain enabled. Normal process-flow
exits complete sanitizer finalization; forced-exit fault cases retain their
previous limitation. Producer callback-value counters and SDK cancellation
completion do not establish the full SDK callback/destructor census.

These results discharge the concrete F11–F13 cases. Native command
interruptibility, the full C09 fault/resource matrix, software-run orchestration,
fresh complete build/archive receipts and the unchanged 95% coverage gate
remain open. Last full measured coverage is 89.0%.

| Process-flow artifact | SHA-256 |
| --- | --- |
| Connection | `0c16199f037bd0fa0234ab27a357bc9c8183ec80f6db508e526962ad117899d1` |
| Native GN targets | `fc5e1301dadb0219512e8fbad821604ff366040f72b9c768abbc27af77f62b9d` |
| Native protocol | `dc894f60cb76bee8f0d45fd1c832ecac42755ea25b3781c50fdf444ac43dd706` |
| Native report-credit header | `4c7de2f77568bb0bacde062dad0e1c300636d67b98ea62dc491169915335727f` |
| Native report-credit implementation | `954d50ba0a17bf1c31a42f579c3d69f4e7c77261589442c68e40c27ba0017e49` |
| Native subscription regressions | `d6281fbad34c968b5ee8bcdf194515426a7c667fa28f6b51b599b382d0aa5547` |
| Process-flow instrumentation header | `1271714ed00bb5c79fef08a41e52d8db803b7d493b04fd065a6de94761d71fbd` |
| Process-flow native source | `e00399d128ffbd4c8c17ea060d4bf721beabdf8d3d58f4e5a4dd445bb4b435f6` |
| Process-flow BEAM observer | `94bf94c9adfadb661a05c6ebf237fc3956e90d7667edbb92d573ace5201ca73d` |
| Native corpus runner | `ed5bc8b1e9761c6067af4fff84c19c58195145003ddf0e28abd91f3902a174cc` |
| Native corpus | `a42e47c8d620cc9598996921cf44175d30f0a4c36ebf5b5ecf1233fe53c540ce` |
| Subscription regressions | `4459f9e19bc5b9487f4cc2e955271f2c9f9db7c92779efdaad3e944e431582c5` |
| Software build helper | `5b9e1dcdaf36611d3b6d69312cc11bebf3930ae565169cf41057ab510bb8bf38` |
| Software manifest helper | `c5e302d62a1c464f6c019e15a8fe2f54538f1a73cf0d592e0b03c0c0fcd7169e` |
| Software receipt tests | `6c6cbff2fea730294b558652d0def48e59b0c27b3400248d32273819bb25862d` |
| Lifecycle stress test | `3cc00ec15d0961cec1aa6958c99c230aab5ee8fd6d360cf93760ac750eccac5f` |
| Blocked-drain failing log | `f95520136fe9e5e83f9ffaa19594e35261442e0a45bb6b38cbabb657f42f3de8` |
| Native cancellation failing log | `49233aafdf6f0e64a7f1edc17e56adfaba8478153991c2bebed8cc04a31f38f1` |
| BEAM cancellation failing log | `2739f96928808926fd5bea503204d252b76c20095ebfc7d3db8fc2ec226c1758` |
| Native CTest log | `70686f7a18beba3530804e798baf31e7f52743ec38f36644ac0d8a04cf896858` |
| SDK build log | `91bf5bd6ebc4cebfd889446ded451861b59336a8a46eb49a6a6fc3a08930b2ed` |
| Production symbol audit | `4a3f5f18ee06a947fd0d8b7de694c4f7dd254e54f5fde2cf8fa2ac1580bbcc7f` |
| Live advisory audit | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |
| Default gate log | `5a042111871574c6b06fd81f974b90178b65a64a428127328b686a840b51f892` |
| ExDoc log | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Current native host | `30a2bc25d1582586bde0a6e041df4b30b8e77b89283e79ffc6d5ddfd16f6bbba` |
| Current process-flow host | `89097bf45ecdd174a84ed1b42c56fddb34bf1478e6d58c8f3f3060f7c55bc73b` |
| Current contract driver | `bdbd392fe8f3a3d2cc92bc34bf57c4bb9ee9c6cb34cdf91b5a7e58c3136dc1d1` |
| Current lifecycle log | `bb61d1af0d9faeb595d0feb6683f22a0437aa3965785c3ee8f9aa2900f2397e5` |
| Current lifecycle result | `d06f076d859956df717030c4d3b6f9cfd0002ac5aebd182f32bd9be2c35672d9` |
| Current fifteen-case SDK/corpus log | `3eaee4c82947ff0059dbc55ae2ba2988eecf633e6d9fb952cd5041839ef68bd2` |
| Current WMA-B-F11 observation | `e6f928eb2c489f4632104bf3db440f4a95e1475ddc4954e89d1c70d9b37fae66` |
| Current WMA-B-F12 observation | `b475ca4ec7973155321f907c7fcc4332f01b8c1fa25da4cb11d77d01b7ce6891` |
| Current WMA-B-F13 observation | `92aaa7af36bbde8eddadd2a38f8c9fe646ad9d3c79bba4d5fd9a7ee5132e9291` |
| Minimum native host | `db8ca4b6a659b1ffa023d486e471908ea2df21cf8515b867581659831a3c0862` |
| Minimum process-flow host | `2107db1cf0242016a998312125f4ce66dee9b5d97e7d3263c340ef076371cb42` |
| Minimum contract driver | `3152ba3efaa1318d54982df591a87c4030cb84f437e767925ecb0259c23cdde5` |
| Minimum lifecycle log | `f732feda2e2214f2665d77b28b058e4e09acd96452399396523a146cee1b584e` |
| Minimum lifecycle result | `800f1612616f77366a1a7e7ab743dad62af1cdee0af7f27de5992bb76df1dfe6` |
| Minimum fifteen-case SDK/corpus log | `fc7d5eac98b360907d852cdb591d4c414a345c3f8fde6c8da000318322a3bece` |
| Minimum WMA-B-F11 observation | `2636a9562e533378b7a9a73e8087e2b4939a9344ecd3b863e51dcec35ed225fb` |
| Minimum WMA-B-F12 observation | `32f2831337b473d5590a3477041dd9e13a3dfdd960aa3c17819c7f15fd25c242` |
| Minimum WMA-B-F13 observation | `3603c7649f8a1a1c899bf282f9441d8fd2696d04686a8128d128be4dce6c2c2f` |
| Minimum focused log | `aae3413d20b74f2f592419890cbf299248b9a6038b5625ce0d240a6e9c418609` |

## Native controls during SDK waits

The native input owner uses one nonblocking descriptor parser for ordinary
input and control polling during SDK waits. The parser retains at most one
131071-byte partial line and one 4096-byte read buffer, distinguishes clean EOF
from truncated input, and restores the descriptor flags when released. Each
poll processes at most 16 frames before the active operation rechecks its
deadline. Report acknowledgements, health, unsubscribe and close remain
available while read, subscription, commissioning and window contexts wait.
A second data command cannot recursively dispatch SDK work. At most one SDK
cancellation waits at a time; another receives `subscription_busy` rather than
creating an unbounded recursive wait.

The SDK wait helper releases its context mutex before polling controls and
uses the original remaining deadline. Nested cancellation also inherits the
parent deadline. Only the recorded native input thread invokes this helper's
control callback; the process-flow producer retains its separate SDK wait.
Startup and shutdown SDK work retain their existing callback-ownership wait
and bounded process-lifetime escalation.

Close marks the protocol closing before the active operation unwinds. Reports
cannot be admitted in that state, late operation replies cannot reactivate a
subscription or reopen the controller, and SDK destruction occurs after the
pending host call returns. Scoped ownership clears the input callback and
restores protocol call depth on exceptional exits. Protocol destruction precedes
output-writer destruction, keeping the callback sink alive through SDK cleanup.
Output admission and subscription activation failures retain a failing native
exit status.

The native regression fails against the serial host because health and close
are not consumed during its pending interaction. Corrected tests cover those
controls, clean and truncated EOF, duplicate request IDs, rejection of recursive
data dispatch, health without cancellation, exact frame-size boundaries,
coalesced frames and restored descriptor flags. A separate real SDK regression
against the previous binary fails to receive stream retirement within 500 ms
while an unresolved five-second read is pending.

The default `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 179 checks with
33 excluded on Elixir 1.20.2/OTP 29.0.4. The full default suite also passes on
Elixir 1.18.4/OTP 27.3.4.15 in 46.6 seconds, with the same 179 executed checks
and 33 excluded. ExDoc passes with warnings as errors. Normal and sanitizer
SDK builds pass for both the ordinary host and separate process-flow host;
all six CTest targets pass in each configuration. The production symbol audit
excludes process-flow instrumentation and counter seeding. All 15 live OSV
queries pass for the pinned dependency revisions.

Both lifecycle workloads pass 1000 sequential reads, 32 concurrent callers,
100 receiver-death cycles and 100 open/close cycles in 149.1 seconds on current
Linux and 174.7 seconds on minimum Linux. Native FD samples remain 16. Current
native RSS changes from 21120 to 21124 KiB and remains at the latter value from
300 reads onward. Minimum sanitizer RSS increases from 166548 to 191612 KiB;
this result does not establish the required resource plateau or full SDK
callback/destructor census.

The first minimum SDK cohort exposes an obsolete lower timing assertion in the
failed-output test: it requires cleanup to take at least 750 ms, although C03
sets a maximum grace. Failure observed before the input poll now exits directly;
a separate sanitizer execution releases its child in 110 ms. The assertion now
accepts prompt cleanup while retaining the unchanged 1000 ms maximum, failing
exit status, sanitizer-diagnostic checks and zero surviving children. The native
watchdog tests retain their blocked-input and repeated-failure assertions.

The corrected fresh-peer SDK cohorts pass all 16 cases in 16.5 seconds on
current Linux and 23.6 seconds on minimum Linux. Their owned peers are reaped.
All 17 native corpus cases pass, including F11–F13's exact normalized results.
For pending read/subscription/window operations, current-Linux control times are
14/12/13 ms and close times are 25/35/33 ms. Minimum-Linux control times are
29/20/20 ms and close times are 68/54/71 ms. Every pending case accepts the exact
report acknowledgement and original-stream cancellation, retains health, emits
no late operation reply and exits normally with its Port and child released.
ASan/UBSan and leak detection remain enabled; stopped or forcibly terminated
fault cases retain the preceding limitation on sanitizer finalization.

The complete C09 fault/resource census, pending commissioning interruption
matrix, startup/shutdown failure instrumentation, software-run orchestration
and fresh complete build/archive receipts remain open. The last full measured
coverage is 89.3%, below the unchanged 95% gate. These results establish the
listed control and lifetime cases, not completion of P09.

| Control-polling artifact | SHA-256 |
| --- | --- |
| Bounded descriptor input | `453a47241e0d60ddc7ec50b2b5f3231b981738b3b361790dc9e7564aff4a5b40` |
| Native protocol header | `7634bc5d782605e8eb0f634808fd565af91a0f5d26aed2e90d64c49543e5f13b` |
| SDK controller header | `b9b8e084c3bb18eeb81e096c172c314c7018505d697223180c56fb1407c59511` |
| Native protocol | `ef1da868111a5bbdc3d5c04cdf130a0547748cda5de706f1412d38a73949dac5` |
| SDK wait implementation | `4ad3625bc873674deaeb951003c77997a1e805a2552188aaadf0a9e27461ac84` |
| Ordinary native entry point | `00b5d22d153cfdf891157c11c9229a509cff6cd95eccec10f7e7c340a686980a` |
| Process-flow entry point | `b676ff3aa78dc3b6edab80a861d43f3b4738d414e546a980353c5f1abb764230` |
| Native control/input tests | `fa4e089ae7c80fae35d85dec1aba7c5a62f08fb6bcd4754efb7be97dd89e53fd` |
| SDK control-polling test | `ce38304acaa89e964e36fa03ce7da74ba9ca5cd4803de7dfbfa60a3b05852138` |
| SDK failed-output test | `9569a7c3b855b6ec88835e45432fcb7336570a8f27a74cfcdc9f8f63bd28faaa` |
| Native corpus | `a42e47c8d620cc9598996921cf44175d30f0a4c36ebf5b5ecf1233fe53c540ce` |
| Native failing regression | `d0a24363b5ebebc94a6704e6325615cd04cf93db0316653f1737bd03eeee2361` |
| Final native builds and CTest | `f3c171516c49099dbfa665f61dd463c586e74f9f4cbabfca0fe4ddef76518bdd` |
| Production symbol audit | `6c26fa871b04bf5773b01f50dffc038a3f7c4a447e0e94b0ecb6e77ea899780c` |
| Live advisory audit | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |
| Final default gate | `65f693d20444a30230273909e43a1cc81eec01f4bcd8e3cbd668f9b72085bc73` |
| Minimum default suite | `6386bf0a9ebfd2dc58cf3684151488f4ec85f86cb0a84ae9dfe9145e4fe07704` |
| ExDoc | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Prompt failed-output cleanup | `5d60610e05737b6e4eb6991a613b4650b110af566f103c5171d4ada952ceacaf` |
| Previous SDK failing control log | `3016e16159554cf203849b19349a2abc9ee932cdc01b911502ca588b12cde241` |
| Obsolete cleanup-floor failing log | `e0f6260e7e13478bc5a206c7cffa8c73536f4c86da3ef3e1e7ae068275f192bd` |
| Last full coverage log | `06821d4d56a69331a7e2f8b07b65b6229b3ca6adff79932d3ccd67695336765e` |
| Current native host | `8272c0a989bdd8da3be57947b788b661ff26ceede00e058d696a66aa50803cb0` |
| Current process-flow host | `93f43b4074b0a5d6d5de367c0c0287d212b1016501f30f6512df7d688787d687` |
| Current native controller test | `4815ad55dad869236f4efa1e5e057abab68cbc232d31de80469e21bfb0ff35f7` |
| Current contract driver | `98ba15bbb146830a445dc269c07190efc1397c913f71b6f9e144be6c71d420c9` |
| Current lifecycle log | `68d6680ed207193ed2c5178414a16e36d0e005809130f7f3e59da02c2625c8b1` |
| Current lifecycle result | `4081dc030e5a77c1bbdef8e4c73eb9e56eef35fd7641b90ec6782f632ec9157a` |
| Current sixteen-case SDK/corpus log | `e3f1d0ad3e433233480580f11f5298f5079ba91ada0fc3b255b190a598338662` |
| Current pending-control result | `740c27ad74bf2b4c309b95f4abbbbd646bbc06d0ffc1a7b185d61d8f21e811eb` |
| Current WMA-B-F11 observation | `a617ed6237231df8601e9b6322ece35589b2d0679bd94086faa751de01c46b5e` |
| Current WMA-B-F12 observation | `0d4906062476d796224886daf4ba9d500bda2a4f874a2c78b11f1632531a77ad` |
| Current WMA-B-F13 observation | `1a4e54e6767e8cfb6dcf33f995530444f626ebd1ea71a67bac9e860583698a39` |
| Minimum native host | `54f7ee4b208a06dd769bcd8470675725ce57ca84d53d52734bc5924ca3f3cd2a` |
| Minimum process-flow host | `8f66c332093ed7c17575ada2684fe8c3eb45aa72642264ab15cb12dde5415bc1` |
| Minimum native controller test | `b92aa0e91833ea018f87a293ecb3320f8e5a5a0b8d9859cc8891335d5e4adef4` |
| Minimum contract driver | `e89330a5f24d98a774ce3eff0a6a0b33921fa70e537aea071616f8b379556002` |
| Minimum lifecycle log | `fdc453b61a00965f4c65ad3bbd28c0bf8a5eecf34cd06df3d70f4b9870b2302b` |
| Minimum lifecycle result | `f33bb05d373f67cdaca93e1e99f113bb6d44e13b53a39bb212cff1dad86a812c` |
| Minimum sixteen-case SDK/corpus log | `d594b0ac7a344f92d612183b8512e2530656d01baa07988ef40f75b659ebacb3` |
| Minimum pending-control result | `1e462e4034b08001addd323b5946fd3e60f49d0846860c9ab04fac704bf2eda0` |
| Minimum WMA-B-F11 observation | `524aa45465318c6450d7fd352b8b6bee290cb2ed6eba1cb8fac73643ddb6aed9` |
| Minimum WMA-B-F12 observation | `2ab881dcadb54d848a922e75ace8b113fd5d4ee015e39a2495f0f1c208dc74b1` |
| Minimum WMA-B-F13 observation | `d31befea01fa360eccc998afe172ca34fbbe12659388a3d9626ee5b4784efc2e` |

## Rejected mutation acknowledgements and one-shot Runtime values

The named write, invoke, commissioning and commissioning-window operations
classify rejected successful-return values with unknown mutation effect.
Validation of inputs and operation options still precedes client dispatch.
After dispatch, a malformed acknowledgement, mismatched write path, incomplete
command response or invalid commissioning result cannot establish that no
mutation occurred. These errors are permanent and non-retryable. Untyped client
failures and callback exceptions during commissioning/window requests likewise
retain unknown effect; structured SDK failures retain their explicit submission
classification. Accepted acknowledgement shapes and scalar projections remain
unchanged.

The initial named-API regressions fail because rejected write and commissioning
results carry `effect: :none` and protocol classification. The corrected cases
cover malformed shapes, wrong identities, invalid status, command path/value
pairing, untyped callback failures and explicit SDK errors. Input-boundary tests
continue to reject invalid requests before the selected client is invoked.

The native one-shot Runtime boundary tests use the existing controlled wire
fixture. Signed-16 scalar boundaries and zero become anonymous i16 writes and
return `"written"`; empty Action input becomes an empty TLV structure and
preserves either status-only null or an admitted empty response structure.
Read projections preserve zero, false and null. Invalid scalar inputs and an
unsupported descriptor path acquire no bridge. Rejected mutation acknowledgements
produce permanent Runtime errors; the recorded input contains one mutation and
one close, and no owned Port remains after the result. These fixtures establish
API/framing behavior, not SDK interoperability.

The default `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 183 checks with
33 excluded on Elixir 1.20.2/OTP 29.0.4. All 59 focused standalone, commissioning
and persistent-bridge tests pass on Elixir 1.18.4/OTP 27.3.4.15 in 45.3 seconds.
ExDoc passes with warnings as errors. The internal standalone, one-shot and
relay value modules now document their ownership and validation contracts;
the remaining production `@moduledoc false` declarations are removed.

Both fresh-peer SDK/corpus cohorts pass all 16 cases, including all 17 native
corpus cases, in 15.6 seconds on current Linux and 23.6 seconds on minimum Linux.
Their owned peers are reaped. Native binaries remain the preceding control-polling
cohort. ASan/UBSan and leak detection remain enabled, with the preceding
forced-exit limitation. The previous full lifecycle receipt remains the native
resource measurement; this acknowledgement-validation change does not establish
a resource plateau, complete C09 fault instrumentation, software-run orchestration
or fresh complete build/archive receipts.

The full coverage run passes all 183 checks with 33 excluded and reports 90.0%.
The unchanged 95% coverage requirement remains unsatisfied.

| Mutation-acknowledgement artifact | SHA-256 |
| --- | --- |
| Standalone operations | `c642a812ad767e997359449d6e5ceccf321af061990d660faf1969aeb312b624` |
| One-shot Runtime projection | `6ef1261c6b5a272dfeef7e35e896e2478471f525b19efc2d489a97b314f742f9` |
| Error contract | `ead50ab43317654a43c175df8b54384ce344d48970a31d60aef51e9e982e92c6` |
| Relay frame contract | `744c3fd1ba3288728d446b0f4bc3ea21a2b96c54d6928fb8fe2322688850f4bc` |
| Relay handle contract | `93548abb1ffd138532d1bfc9d62cbe11c57c7120c3897d9525b8fc80ea1cb1a4` |
| Named mutation regressions | `4c26d380efd2d00d66eb9772e4a37c54bb7be9760e31128267dea357358e6c9a` |
| Commissioning mutation regressions | `d9eb033837cfbdb8d11878f256a90685a34e4f9947e81136161fb2f53601671e` |
| Native Runtime boundary tests | `b4b12449efec183b5f3943fff7e28674ff529e3a8b205950e070d1032a8b778a` |
| Failing named acknowledgement log | `1297af27a8f3adb81cfef4cbfe94e598ff689a7750405d4ac9474ec43156285c` |
| Focused Runtime boundary log | `f14c11495317df98d06b3005015dcc4848ffd4383a09f1c1c113c9f526403b27` |
| Default gate log | `bb6048527e30299dc1ec9a0a312c2820c10b914041b13b070225454290b2e8ed` |
| Minimum focused log | `3855ec806e4997650127948b8893bfb4685f44302becd65d21feff5bf4da203d` |
| ExDoc log | `d4576f92450d1af2e790429235edd6139115f02c5e9e864018bfb82e9616710f` |
| Full coverage log | `87b82d8cf91dd51f368cfdbf7369379aa82852657453a157b28e6ed601efaf13` |
| Current sixteen-case SDK/corpus log | `3591c53056db14205ddf8d0e75ffd108911937b16d9ef10f7ecd84aea54da692` |
| Minimum sixteen-case SDK/corpus log | `e08a7d709dedb240652c6d90b9a282ba7ff1a68b0f18336ab32c01dee484d7b0` |


## Required software case receipts

`WOTEX_REQUIRE_SOFTWARE=1` enables explicit fixture admission and required-case
accounting in the ExUnit helper. The checked-in inventory identifies all 32
registered software cases and their 23 fixture/executable variables. Fixture
JSON is bounded, duplicate-free and owner-only. Source and fixture paths reject
symlinks and traversal. Result creation is exclusive; an existing receipt is
never replaced.

The formatter records actual ExUnit completion states for each expected case.
Missing, excluded, skipped, failed, invalid, duplicate and unexpected software
cases fail acceptance. An executed hardware case or an ordinary test failure
also prevents success. Source digests before and after execution must agree.
The receipt retains the inventory digest, exact Elixir/OTP versions, seed and
evidence categories. Shared-SDK cases and native contract cases remain distinct;
fixture credentials, exception contents and skip reasons do not enter the
structured result. ExUnit's after-suite callback rejects a failed or absent
receipt, including an otherwise successful run with no selected required cases.

Five deterministic acceptance tests execute real isolated ExUnit processes.
They cover a successful receipt, existing-result refusal, missing and malformed
fixtures, invalid inventories, skips, filters, omitted and zero-case runs,
assertion and setup failures, unexpected software cases, hardware execution,
ordinary test failures and changed source. Canary fixture/exception contents are
absent from failure receipts. A separate compile-only inventory check compares
registered software test identities with the manifest without starting peers.
These are test-orchestration assertions, not additional SDK interoperability.

The default `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes all 188 checks
(two doctests, one property and 185 tests), with 33 excluded, in 67.8 seconds on
Elixir 1.20.2/OTP 29.0.4. All five acceptance tests pass in 7.2 seconds on
Elixir 1.18.4/OTP 27.3.4.15. ExDoc passes with warnings as errors. An actual
`mix test --no-compile` invocation with required mode and missing fixtures exits
nonzero before test execution. The preceding coverage measurement remains
90.0%, below the unchanged 95% requirement.

Peer startup, the complete `mix wotex.software.run` task, complete C09 native
fault/resource evidence and fresh build/archive acceptance remain open. This
receipt harness does not itself establish a successful 32-case SDK/software run.

| Software acceptance artifact | SHA-256 |
| --- | --- |
| Case inventory | `04f0b813fd3feabf4a0a1e08953a9075f258ac1b37eac1954a4f094ffb2ccbc0` |
| Fixture admission and result gate | `16ca32b70aa0da951295f28fc0c053b705440df0a39773fa33186159f5a37c3f` |
| ExUnit case formatter | `b6be596cb1c0258affe9149fd9a5baabb847a94f8d7dced516dc956bdf0cd49c` |
| Test helper | `fd3e4d21afc2a44686a256b77c4ffee51ae21eb52c63c36d0c9e703ec8ebc815` |
| Executable acceptance tests | `3ac3cfe026e1a9c245aa0b10000db936b0ba4f10bc5fa7b9b974d417d5fb4ff2` |
| Current focused log | `67f80d977f8f5ee005b52a1ee28032e2025583ca3d8aa1d8b5d26a7e48959caf` |
| Default gate log | `7b9a60d29438603d1ebce267700e172206ab96dd16dd4194a283c4062a0612ae` |
| Minimum focused log | `4154eb6d116c781874a045143697297d9cc897eae466d8b8e3def56abff31064` |
| Missing-fixture CLI log | `c77d145b93af61772e9cc81a062dc97bca4117aceac3d2de220969fb0cb4e56d` |
| ExDoc log | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |


## Owned software peer readiness and cancellation

The software command helper supports explicit asynchronous ownership and
reference-bound cancellation. Its worker monitors the calling process, including
normal caller exit. The synchronous build-command interface uses the same owner.
Readiness emits at most one startup identity and one ready notification; neither
contains peer output. A marker is at most 256 bytes, may span output chunks and
retains only its bounded unmatched suffix. The existing 16 MiB output bound
remains in force. Logs use exclusive owner-only files.

The peer helper requires explicit startup and lifetime budgets. It retains the
Port and child identity through startup cancellation, rejects early process exit
and checks reaping at teardown. The pinned SDK's `src/app/server/Server.cpp`
emits `Server Listening...` after successful server initialization and identifies
that log as a test-harness marker. The fixture uses that marker without supplying
Matter protocol responses.

The late-readiness regression suspends the caller, observes the actual command
worker sending ready after the 100 ms startup budget, then resumes the caller.
The initial implementation incorrectly returns an active peer. The corrected
helper checks the absolute deadline when consuming ready, cancels the command
and confirms cleanup. Six peer tests additionally cover split output, missing
readiness, successful and failed early exit, normal and abrupt caller exit,
exclusive cancellation identity and owner-only logs. These controlled process
fixtures establish orchestration behavior, not SDK protocol interoperability.

The final `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes all 194 checks
(two doctests, one property and 191 tests), with 33 excluded, in 69.5 seconds on
Elixir 1.20.2/OTP 29.0.4. All 21 build-command, peer and acceptance-receipt tests
pass in 10.0 seconds on Elixir 1.18.4/OTP 27.3.4.15. ExDoc passes with warnings
as errors.

Both fresh SDK cohorts start the pinned lighting peer through this helper,
commission a new stored controller, execute all 16 selected SDK/corpus cases
(including the 17 native corpus cases), and verify peer cleanup through the
helper. Current Linux completes the cases in 16.3 seconds; minimum Linux
completes them in 23.3 seconds. Both cohort processes exit successfully after
cleanup. The production and sanitizer native binaries remain the preceding
control-polling build; native code is unchanged. ASan/UBSan and leak detection
remain enabled with the previously documented forced-exit limitation.

The complete software-run command, full required-case execution, native C09
fault/resource instrumentation and fresh build/archive receipts remain open.
The preceding library coverage result remains 90.0%, below the unchanged 95%
requirement. Peer ownership alone does not complete those requirements.

| Software peer artifact | SHA-256 |
| --- | --- |
| Command owner | `86d45e6fc3f5ba65f2e77e5f03f564916b51ed545515b2165d18b860c4be0b82` |
| Peer readiness and cleanup | `10b62231f00f7fb0f7c3e0a044bd78e07d155d793bfb1ee38bcaa7f85a5c1313` |
| Peer lifecycle tests | `904c71cf72501ea2c8fd2c2b58b71e645803fbaca15338b05c63b4b409b9d0bf` |
| Failing late-readiness regression | `304cfe2342f956a9c734f77e243329c6e52c22d880624150032946a43cf409bc` |
| Passing late-readiness regression | `67efc8f2a9422a1abe012c9e77b40c18610385de1762a724fd4dba3baf8ab390` |
| Default gate log | `831725d80cf2ea92a53fc6f854e8901725093cb0e54bbfb566fed11006910e32` |
| Minimum focused log | `fd3b6d9c049227867122ee3fd67c31b268ca7feeeae652b201a46ffe9faea313` |
| ExDoc log | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Current sixteen-case SDK/corpus log | `ed2f1842e46d7efc39606bac3bdba9a2ce2154f4895f6105d963797d23c98dc0` |
| Minimum sixteen-case SDK/corpus log | `62270d291528a6dfa7352c478619ba4248fae83e154480f4b32387e9642736b0` |


## Software harness distribution and verification inputs

Software builds export the normal and sanitizer controller-test executables
alongside the process-flow hosts. The controller tests already execute in the
native CMake lane and provide the failed-output harness used by the SDK suite.
The exported files are owner-executable artifacts, with hashes, architecture
and runtime-library records in the software manifest. Native-only builds retain
their narrower required file set. Workspace validation rejects a missing or
changed software harness.

Source identity includes the check, coverage, formatting and Mix configuration
and all named verification scripts. Regression cases reject reuse after changing
the coverage floor or disabling the test command. The package allowlist includes
acceptance tests, their helpers and corpus, native verification scripts and the
check/coverage configuration. The archive checker requires every inventory case
source and the 95% coverage floor and rejects generated documentation, coverage
and Python cache directories as development state.

`WOTEX_PATH_DEPS=1 mix check --no-retry` passes all 194 checks with 33 excluded
in 66.4 seconds on Elixir 1.20.2/OTP 29.0.4. All 15 focused build/acceptance tests
pass in 7.7 seconds on Elixir 1.18.4/OTP 27.3.4.15. ExDoc passes with warnings
as errors. This change does not provide a fresh complete software-build receipt
or close the remaining software-run, native resource, coverage or archive gates.

| Software distribution artifact | SHA-256 |
| --- | --- |
| Build orchestration | `0d1f68c378d5f009a07922440f136d703c62535617dc59810a4ac08770a588cd` |
| Workspace and source identity | `9713c196aa4c448626af23773f48835f1819de8ca460419cac3d64b808854502` |
| Build-reuse regressions | `3845a1fda198a834a9f649d07eaeb729f10e99b5171135df7f2d440f56e9b216` |
| Package definition | `a324f5c617f51d546c299667e7d39bb0478b1942ebc870b97c5948c90be92fd6` |
| Archive verification | `443143718dd636a3b01ae6403d6a06f040938277461eac67df677d7be97f4e28` |
| Default gate log | `e3456faab009ee8b017824b7f3871182a74ab6c52da319487a6e9d6c70be0b73` |
| Minimum focused log | `0ea904bf6404ce0ec74b55afc189a15f8b6dfa5b7366b469a58c42372e8c7c51` |
| ExDoc log | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |


## Archive verification across isolated Mix builds

The archive verifier loads compiled dependencies from the active
`Mix.Project.build_path/0`. A minimum-version check against the clean `0cf698e`
archive exposes the preceding hardcoded test-cache path: OTP 27 attempts to
load OTP 29 dependency beams and reports invalid atom tables. Selecting the
active Mix build removes that cross-toolchain dependency reuse.

The clean `0cf698e` source produces `wotex_matter-0.1.0.tar` with
`WOTEX_PATH_DEPS` unset during `mix hex.build`. Its SHA-256 is
`25cd4ff7b8f498776c665443bd99900ef51c95796d5f0cc5c019e9a9c2d76a6e`.
Archive contents, the 32-case source inventory, the 95% coverage configuration
and out-of-tree compilation pass on Elixir 1.20.2/OTP 29.0.4 and
Elixir 1.18.4/OTP 27.3.4.15 with the corrected verifier. The library sources in
the archive are unchanged by the verifier correction. Compilation uses the
selected lane's compiled development dependencies; this does not establish
released Hex dependency resolution or package publication.

The corrected verifier passes `WOTEX_PATH_DEPS=1 mix check --no-retry`: 194
checks, 33 excluded, in 70.9 seconds on the current toolchain. ExDoc passes
with warnings as errors. The minimum
archive failure and corrected execution are retained separately. Packaged-suite
execution and the remaining software-run, complete native build and C09 resource
requirements remain open; the last coverage measurement is still 90.0%.

| Archive build-path artifact | SHA-256 |
| --- | --- |
| Archive verifier | `49d7f3b6ec019a8f2390ed05a4fb96fa0412ab0aea56e15d113103cfde76de76` |
| Clean source Hex build log | `e769732768d733ef5b881f8eda5b7cc28504e61e2adb90e2476917056db06246` |
| Minimum mismatched-cache failure | `a974d392b4796bebfddbe049da365c8eca4445a4e2bb5fe1332ce4e74d914054` |
| Corrected minimum archive log | `2ccc4001f666d566301142c535d780bc3eae2fbbcc98ff7cee5e34371c446740` |
| Corrected current archive log | `67e0f258c45ec28c4b5ee7b393d43fd3b3bb3ab3b74cb4ca7b6aeac76980e3ef` |
| Default gate log | `28db81cf7d94ba0f80845a231713263eb26e36073e47ed15b2e77e22652655f5` |
| ExDoc log | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |


## Packaged default-suite execution

The clean `8d81e32` archive has SHA-256
`66e8e9f374fbc863fa2a527497a0a8081d9fbab2598785c6d6b8673e294cde3c`.
Its 46 ExUnit test source files execute outside the repository with the
committed lockfile, whose SHA-256 is
`3e07ae876d85087f0d539bec1bb2a3556e37f06b3b3360a322ea6131acfe73b5`.
Dependency retrieval uses the existing offline cache and `--check-locked`;
the explicit development switch selects Wotex dependency sources. Each BEAM
lane compiles into its own build directory.

The packaged current-version `mix check --no-retry` passes all 194 checks with
33 excluded in 69.2 seconds. Minimum-version execution passes the same 194
checks with 33 excluded in 66.8 seconds, but its formatter rejects one test
comprehension that Elixir 1.20 formats differently. Binding the peer filename
list separately preserves the test and satisfies both formatters. The corrected
source passes the minimum formatter and the current full gate: 194 checks,
33 excluded, in 70.7 seconds. The original packaged minimum gate remains a
recorded failure, not a passing archive receipt.

These default-suite results do not execute the 32 required SDK/software cases,
prove released Hex dependency resolution or satisfy the 95% coverage floor.
The native build, complete runner and C09 resource requirements remain separate.

| Packaged-suite artifact | SHA-256 |
| --- | --- |
| Clean archive build log | `9b3497259c3fbef50065dc73b4302389220b87ca1c105006e60756302a5a170d` |
| Offline locked dependency log | `09df673601945644491df1aba84b22d19d896f866199a7b70f63cbd763d1b0b9` |
| Packaged current full gate | `202eb94e4a129041d6bb4a810e1ac9a6deab59480f128386e72add0b9f1d7528` |
| Packaged minimum formatter failure and passing tests | `e57cc4f15ea6af24fc7e5ecfbaa021fac4c30685f765a9f80c4a768fa00ee436` |
| Minimum corrected formatting | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Corrected source full gate | `a8b778df757ec8e9ebf896a564706405d0636c8e057e23c35c3e0e688130cea3` |
| Cross-version test formatting | `86c9c532d984dad5d36a645714696b56db45deb3182f2cdaacba191186ebae66` |

The corrected clean `4e572d2` archive has SHA-256
`ef6704fd010b6e6208444ca2db1629a21b294d83996c975d22cda87ef25ad94d`.
Its packaged full gate passes on Elixir 1.20.2/OTP 29.0.4 in 71.0 seconds
and Elixir 1.18.4/OTP 27.3.4.15 in 62.8 seconds. Each lane executes 194 checks
with 33 excluded and passes formatting and compilation. Both lanes also pass
`bin/check_archive.exs` and `bin/check_application_free.exs` against this archive.
The same committed lockfile and explicit development dependency sources apply;
the project is force-compiled from the extracted archive into each lane's build.
This closes the recorded formatter failure for that archive without changing
the dependency-publication, coverage or software-profile limitations above.

| Corrected archive artifact | SHA-256 |
| --- | --- |
| Clean archive build log | `0dff60426d28c5e09eb23689a39bc587234685eb02aa2eb2aa1f827e234f22e7` |
| Packaged current full gate | `cbb3c25aa926e89d1eb4cbb827eaeb69a9ecef69b47bb8038f9763c2ba039c17` |
| Packaged minimum full gate | `876a9f0c5d410eaa2f3ffbbda4a27f0613308ecb5957ff48679d46323cc97b2b` |
| Archive inspection and out-of-tree compilation, each lane | `645eca9ec7bba65da3642c3b0769dd7d0e6e0772805f4a8b8a648a4f80756b46` |

## Joining a pending native cancellation

WMA-C03/C05 explicit unsubscribe joins an owner-loss cancellation that is already
waiting for native retirement. The connection preserves the original request ID,
waits for retirement and the pending cancellation acknowledgement, and retains
the explicit caller's deadline. It sends no second cancellation. Expiry or a
malformed frame closes the generation and its owned native process.

The deterministic `gated_cancel` fixture delays the first cancellation reply.
Before correction, explicit unsubscribe sends a second cancellation and returns
`invalid_frame` after duplicate retirement. The regression now returns `:ok`,
observes exactly one native cancellation, and keeps health usable. A separate
100 ms caller-deadline case closes the stalled connection, Port and admission
table without a second terminal delivery. All 24 subscription tests pass on the
current toolchain. Automatic cancellation without a waiting API caller remains
a separate deadline case; this result does not establish that bound.

The real SDK stream-owner case stops its exact native child before owner loss,
observes the pending cancellation, starts explicit unsubscribe, then resumes
the child. Unsubscribe completes without advancing the native request counter;
health remains usable. Both fresh 16-case SDK/corpus cohorts pass, including all
17 native corpus vectors: 17.2 seconds on the current normal lane and 23.7 seconds
on the minimum ASan/UBSan lane with leak detection enabled. Their owned peers
are reaped. The native C++ sources and binaries remain the `9a4d124` inputs.

The current `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 196 checks with
33 excluded in 70.0 seconds. The minimum toolchain passes all 29 subscription
and acceptance-harness tests in 29.4 seconds. ExDoc passes with warnings as errors.
The full software runner and complete C09 resource
census remain unaccepted. The last coverage measurement is 90.0%; it predates
this cancellation change and does not meet the unchanged 95% floor.

| Pending-cancellation artifact | SHA-256 |
| --- | --- |
| Native connection | `1b9c50bafa1462156a5c15fb526c5ec77465cea0c24391cfc00f754fef486081` |
| Subscription assertions | `0cd9fa74d0ae007bbec82a7b33afeed81fafcc20bb6e833d97393fb95602d94d` |
| Real SDK stream-owner assertions | `c9a9b70fd9f4df450b6462061af20b4e3a8697f6558f810af0e046f3b197bbc4` |
| Deterministic failure before correction | `04b1b561692c27ccc8220adbd66f3e386666e2d2fe14080e9bae814035260ccd` |
| Current subscription gate | `625d850fedd395f29a558776a19da6853e330de9c81c24baf7d925a45aa2ec43` |
| Current SDK/corpus log | `79afe1f8a381cb2e082cf93c34de09528e1bff713f8d02aa80e1bd91fd227f7f` |
| Minimum SDK/corpus log | `d278d50ddc1863c7abf260fb42bd1c0754a5e3fcc71560da2bef7978f6dd1bcd` |
| Stream-owner result, each SDK lane | `43b360b5e7d3d6b272e95ac9c0ecfff237a3fbf723ed51c1d221063d30ff2ec4` |
| Default gate | `888cee6a1ef584c168e4788f2f5a3f8dd22c22135caabb087817454e47fc5547` |
| Minimum focused gate | `4cedef5ef61ed81768e47fe914b00d3174b432b1653a5c514c4087aaf0e02a79` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |

## Automatic native cancellation deadlines

WMA-C03/C05 automatic cancellation retains one absolute 750 ms deadline until
both native retirement and cancellation acknowledgement arrive. Receiving only
one frame cannot release the watch. The existing 50 ms admission-maintenance
tick enforces expiry and leaves time to reap the native child within the
1000 ms local cleanup grace. No additional timer or global process is created.
A native terminal error also requires retirement within this bound. Late frames
cannot reset an expired watch. Explicit unsubscribe uses the earlier of its
caller deadline and the existing cancellation deadline, including when retirement
has arrived but its acknowledgement is still missing.

Before correction, the gated cancellation fixture retains the connection beyond
1000 ms when no subsequent API call occurs. The 26 subscription tests now pass.
The new cases withhold both replies, send only the acknowledgement, send only
retirement, or emit a terminal error without retirement. They assert connection,
Port, admission-table and stream-owner cleanup, as applicable, with no duplicate
terminal delivery. Explicit 100 ms cancellation joins also cover both incomplete
reply orders.

The real SDK case stops the native child, kills the stream owner and makes no
further API call. The connection and exact native process are reaped within
1000 ms on both BEAM lanes. Full lifecycle stress also passes: 1000 sequential
reads, 32 concurrent callers, 100 receiver-loss cycles and 100 open/close cycles.
Every receiver-loss cycle clears the cancellation-watch map. Current normal
stress takes 151.7 seconds; minimum ASan/UBSan stress takes 174.4 seconds with
leak detection enabled. Both retain 16 native file descriptors. Current RSS is
21124 KiB at every sample; sanitizer RSS increases from 166560 to 191612 KiB.
The latter remains a separate resource investigation, not a flat-RSS claim.
The following 16 SDK/corpus tests pass in 18.6 and 25.5 seconds, including all
17 native corpus vectors. Both owned peers are reaped. Native C++ inputs and
binaries remain `9a4d124`.

The current `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 198 checks with
33 excluded in 63.4 seconds. The minimum toolchain passes all 31 subscription
and acceptance-harness tests in 35.8 seconds. ExDoc passes with warnings as
errors. These focused SDK results do not accept the complete software runner,
the C09 resource census or the unchanged 95% coverage floor.

| Automatic-cancellation artifact | SHA-256 |
| --- | --- |
| Native connection | `d5e529b7657a526da54ef4383ce97fe7d44ecc1ca855b06dc65c368375fbe80c` |
| Subscription assertions | `1cbf0c9e04577822cc2e9b39b1089e70c97809160024b76c5b00ab041659adec` |
| Real SDK stream-owner assertions | `69a8b2cb32550f02dbdbc5e0728285bc225d171aa10b057624c67e40649467a5` |
| Lifecycle stress assertions | `0344b41d56f63bf1f4592433c20e7296d4e7a5ee9fb80cb44c8e52fca1b77188` |
| Failure before correction | `2f670658210bf43aa938751fd9c0326a87d762b96385ddaff27a6d2bd5a6c13b` |
| Current subscription gate | `a44ed7153a0cb8c21e87db2973406bf292f2e721c1c56555880b6e097d577b13` |
| Current lifecycle stress | `060dc8ae1e87d1871ffd199ac61a94aa33c5f70a72ff197a5c99882d1559d705` |
| Minimum lifecycle stress | `2bc19d79b848a0c0a1f346dab10a5d74094f006da5002bdc37861a0419092788` |
| Current SDK/corpus log | `ae59776cccd6f8f5c7a6d4f541cf9409899cec317b4586dd8af963f9c934f895` |
| Minimum SDK/corpus log | `75361269a6a7cfd948e17366d40309d83f8c3973652b2fdbea5ef8801d8583d7` |
| Stream-owner result, each SDK lane | `38db5e2adb531b8c05dfc937af138314562bcf039ae71056ca1c9ac087666a66` |
| Default gate | `45bf461d58010c3b2ab6e527c95486632f52cd1a7a7f1240fe2a24bfae8b2e19` |
| Minimum focused gate | `08357707262a4e774e93b8b63732ca8f6abd7480220ef69d1d60c00c838b34e5` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |

## Owned software scenario preparation

The P09 scenario helper owns thirteen pinned SDK peers with private controller
stores, generated valid setup codes, distinct ports and discriminators. It
prepares all 23 required fixture/executable inputs, including real commissioning,
CASE, typed ACL denial and an observed 180-second commissioning-window expiry.
A separate public SDK test root produces the untrusted-attestation scenario.
The helper supplies fixture configuration and invokes the actual ExUnit suite;
it does not supply protocol results.

Two deterministic tests fail the third peer startup or controller setup after all
thirteen peers become ready. Every acquired peer process is reaped, fixture
execution is withheld and directories retain mode 0700. These injected lifecycle
tests establish helper ownership only. Isolated acceptance-harness child VMs use
single-map JIT and a UTF-8 locale; their five Linux tests pass in 18.2 seconds.
Before that environment correction, three child-VM tests failed in the full
software cohort. Raw control-pump opening projects only the admitted native wire
keys from controller fixture configuration.

The first complete current-toolchain fixture cohort is rejected: 220 of 226
checks pass, six fail, one hardware case is excluded, and 30 of 32 required
software cases pass. All thirteen peers are reaped. The receipt binds unchanged
source before and after execution. The failures include the separately corrected
pending-cancellation race, three child-VM environment failures, the raw opening
fixture mismatch and a one-shot read timeout. The five commissioning/security
scenarios and the lighting, thermostat and bridge recipes pass in that cohort.
This partial result does not accept the complete software profile.

The one-shot failure occurs during CASE establishment: the peer sends and
retransmits Sigma2Resume, while the controller records no received response.
A later diagnostic with the same peer/controller stores passes 1000 reads in
393.722 seconds with the unchanged ten-second operation deadline. Every read
records ready, open, read and close IPC frames; the longest takes 458 ms. The
owned peer is reaped. This diagnostic does not establish the cause of the earlier
failure or replace a complete required-mode cohort.

The current `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 200 checks with
33 excluded in 64.2 seconds. The minimum toolchain passes all seven scenario
ownership and acceptance-harness tests in 9.0 seconds. ExDoc passes with warnings
as errors. Native inputs remain `9a4d124`. The complete run command, fresh native
build receipt, C09 resource census and 95% coverage gate remain separate work.

| Scenario-preparation artifact | SHA-256 |
| --- | --- |
| Scenario helper | `8f48bb334a2f642a2a8f47c161101b260950c37edec5be12f102f8224fba3b74` |
| Scenario ownership assertions | `327ebc1a015eb51de2038fdf73e7f062a538623c479c0e8683350c8e482c5d29` |
| Raw control-pump assertions | `ae1b679895db03b71b009f3ce3ae5bcbbae915ef494558b43220b833b9c51fa4` |
| Acceptance-harness assertions | `bb47a134bc5404e94aa8d98ff8321a1ac26105d94da08ef7f11c9c90c3b29aae` |
| Rejected required-mode receipt | `8e70d19ae5b9fe199746fddbcad867ddae82f1f526c87a514991b809aa442a12` |
| Rejected cohort log | `76ce4997b999610740c31df6ffe244b8140de64f5714dc0b681b88b911ea81e6` |
| Child-VM Linux failure before correction | `6a27f3912b54e1eb3704d59d317c8a661770c84d62f6f8b29ba689b15ea4f749` |
| Child-VM Linux passing gate | `a2ececa8c12e82e1870371a97d54a2f3d63d89fb6e658ca6ae64c6387fa6f3d6` |
| One-shot diagnostic frame receipts | `7dc2607a88834dc03e00323f14af2e54862cc72bcad3463fcec229b7562aa80a` |
| Default gate | `e2e01f2964e2cd5888f2ef3ea7fa235cbcc49423d76869c44c580b13212556ed` |
| Minimum focused gate | `4b4e58cd736abcd8bc7772cb0fa4affb5e07d754884024ac767be43c4fae201f` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |

## Verified-workspace software run command

`mix wotex.software.run --workspace ABS` admits a matching software build receipt
under the workspace lock. It runs separate current Elixir 1.20.2/OTP 29.0.4 and
minimum Elixir 1.18.4/OTP 27.3.4.15 Docker lanes. The minimum lane selects the
ASan/UBSan native binaries with leak detection enabled. Each lane owns a private
bridge network, container, run directory and peer cohort. Source and native
artifacts are mounted read-only. Command budgets share a 90-minute absolute
lane deadline with 30 seconds reserved for cleanup.

The runner verifies architecture and procfs, resolves locked dependencies,
compiles the source and executes the required-mode suite. Its final receipt
requires matching source and BEAM-version fields, successful owned-resource
cleanup and unchanged source, build artifacts and development dependencies.
Development path dependencies retain their source identities and an explicit
mode label. Their identity includes embedded JSON schemas. These labels record
which resolution path runs; injected orchestration tests establish neither
released Hex availability nor protocol interoperability.

The software build exports and hashes three public SDK attestation roots with
the native and peer executables. Reuse rejects missing or changed test roots.
Runtime fixture trust is copied into private run directories; this introduces no
production trust default. The public run command rejects the previous complete
build workspace as `manifest_mismatch` before container startup and releases its
workspace lock. A fresh native build and successful real two-lane run receipt
for this source remain required.

Four injected Docker-command tests establish cleanup after an ordinary failure
and caller death, preservation of unrelated resources, both exact lane identities
on success, and rejection of missing, failed, wrong-source or wrong-version
receipts despite successful command exit. Workspace tests also reject absent or
mismatched manifests before fixture execution. All 15 runner/build tests pass on
the minimum toolchain in 2.2 seconds. The current
`WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 205 checks with 33 excluded
in 69.7 seconds. Both formatters and ExDoc pass with warnings as errors where
applicable. Native C++ sources remain `9a4d124`; complete P09/C09 acceptance and
the unchanged 95% coverage floor are not established by this command package.

| Software-run artifact | SHA-256 |
| --- | --- |
| Mix run entry point | `de7337d9c74abc3e3cc3aee9aa2903ab742e1d2a146018eef8c2be9ca07819c6` |
| Container/network runner | `0db497f21790ff0bad295a556fd291c8dd68b13009899cb7f1e8dd545774a6b2` |
| In-container scenario invocation | `97a0df8b6829dc7a4f704f253ac3ddefdbe72e7f35ae972aa8b4179d32088a0b` |
| Workspace entry and locking | `346578d0b394842583fc4793f5a8fb17e374e6c810524ead7a88fc2478d0da9a` |
| Build exports | `71c182bca6a73a77ad4ca1d5f404abb2beeaaa957fb6053becbf762937ef33bb` |
| Build/source receipt validation | `b1fe253640214f381bfa2d7572e77045b46d6191ff6f6f9f3b20ac14621f30fd` |
| Runner assertions | `46b2568a2f649fdd8f34c7c408244b5de2b3ee17429642f45914cac74cdc0e20` |
| Workspace assertions | `15b14c5cede7c8acbc0e4b2eb2ac0ef90cc61e4cfde4f5987f77bb5d7ad53a8e` |
| Default gate | `3e4c96795abc9205df9f6b0cd070bee688e843e7d71064c222a27766576eb063` |
| Minimum focused gate | `c6affb0c20d1bd7be47bd49c33fabd3e6f89a5d3530c2122e6405a32ef43d770` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Public command stale-workspace rejection | `cc475649d7905440fbfdaf00c6d5c19280f4bbc61701fb9cb9686544ebcefe9b` |

## Mutation response identity and rejected backend effects

WMA-C04/S03 command data responses retain the invoked fabric, node, endpoint and
cluster. Their returned command identifier remains independently schema-checked.
Write acknowledgements retain the complete requested attribute path. Native
response validation also rejects unpaired command path/value fields and values
outside the returned descriptor. Status-only command replies remain distinct
from present empty structures.

The standalone regression previously accepts a response for fabric 2 after
invocation on fabric 1. The native protocol regression also accepts a mismatched
write acknowledgement. Both now reject these responses. A second native
regression demonstrates that backend-result rejection omitted unknown mutation
effect. The protocol now retains that effect for rejected write, invoke,
commissioning and window results and oversized mutation responses. Validation
before backend invocation retains its existing effect classification.

The native interaction assertions vary every write path component and every
command target component. They reject unpaired fields, unknown response schemas
and an incompatible scalar while retaining the supported status-only and typed
empty-structure replies. Commissioning/window assertions reject a different
returned node with unknown effect. The standalone assertions reject changed
fabric, node and endpoint without replay; a schema-valid response command
identifier may differ from the requested identifier on the same target.

Both native CMake gates pass all six tests: 2.55 seconds normally and 3.16 seconds
with ASan/UBSan and leak detection. All 15 pinned OSV queries pass. Fresh normal
and sanitizer SDK builds pass the 16-case SDK/corpus cohort, including all 17
native corpus vectors, in 18.1 and 25.7 seconds. Both owned peers are reaped.
The current `WOTEX_PATH_DEPS=1 mix check --no-retry` gate passes 206 checks with
33 excluded in 68.8 seconds. The minimum toolchain passes 21 standalone and
interaction tests in 2.6 seconds; ExDoc passes with warnings as errors.

The latest coverage measurement is 90.1% at `c8f7496`, before this response
change. It has 2447 executable lines and 241 uncovered lines and does not meet
the unchanged 95% floor. Complete software-run and C09 resource acceptance
remain separate from these focused native results.

| Mutation-response artifact | SHA-256 |
| --- | --- |
| Standalone implementation | `cf0eb18aa1dcf095fb44e9e7939ef83059d64e2d003ef9a45a8cdc8ae931d527` |
| Native interaction validation | `378d1384700bbd28a064aa7079b6dbb6afe1d1550513c1b54cb193fc66d25996` |
| Native protocol effects | `9b6d270a1b4fec1bc5b34cda62ed18363c457796e0fde19f84d3f62c16d528d5` |
| Standalone assertions | `8affb7a2ba4173d6661fa10e5608cc395684d6d902b17989bb200fbb62e89db1` |
| Native interaction assertions | `b1d8b1d7417490a82f58a98dc13fb2f3e2e4f4a31adba13567aae321cc7122aa` |
| Native commissioning assertions | `14eecaa02b8001f6d8cc46da7ed3e5168a7589e571c05a263203c36195d2bac3` |
| Standalone identity failure before correction | `8423b7413757a1ee35794ca1c2b1fb033d891786f344af4facefbbbc279be2d3` |
| Native identity failure before correction | `6dcf8e9b6182433d7845bf26a766c1da87309e60c082495a2bffa918572d2c4e` |
| Native effect failure before correction | `61bfda9b7388906e4011689812630edca5c1f09d1f6c08d803a30da833919a1f` |
| Normal CTest gate | `7e9822865d8a8ff67dce77591d2c493edbfa7d9f80cbb0ceacc4d93c27034027` |
| ASan/UBSan CTest gate | `a5f1dd81acfc4ea2c67a9a7bd9cb788e6affbcf01f08f76382ce639c98e91db8` |
| Pinned advisory gate | `947d36e4c60803d5242b03f9d04555a254b09399c2f8881ec39964b3c09c20a5` |
| Current SDK/corpus gate | `9f16174220b91e58afef00decb333c95adc00dd859de3af5cfe4b252bbfcba1b` |
| Minimum SDK/corpus gate | `289ff0399d1b4ba6765ce4cdf2ce0f2c616e622d339a234c60d0deb043cce586` |
| Current native host | `c0aec70fe1137a33729031cf03a5dd110b6b22f19281764c9d96e45591bd4001` |
| Minimum sanitizer native host | `e667f5d4b5fdc03cc4d769d9b133ca247d4319e5c397ae3ef7866f602a0a9eb8` |
| Current native flow host | `8d10b0c873d79452dc670a40e35a1694865ecd4b7efcf52c0fd5c6a848ee4eac` |
| Minimum sanitizer flow host | `2e8d170227e462b0f058d7192135e234751b57bda98f6df53d47ccff2070d7f7` |
| Default gate | `7b6983b993fd6e306d170f1b85b7f4c7c03699457dd93a50e084832184d6c375` |
| Minimum focused gate | `3f8ace98270fe51d6761d5db5f5acf14893a72929bf240dfc0ccc616a1bf4b5c` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Pre-change coverage log | `e314440b7a6abe76981ff5bbc50970129f6663023b917645a3ef8476b5f13cad` |
| Pre-change coverage JSON | `4b3fc36a1d938f929c3159569522da82353eecce427bd3558846bdb46a023bc2` |

## Peer log retention and lifetime under continuous output

The second complete current-toolchain cohort, from frozen `9be7331` source,
rejects acceptance: 229 of 232 executed checks pass in 966.8 seconds, with one
hardware case excluded and 29 of 32 required software cases passing. The
one-shot stress case completes 1000 sequential reads before failing during its
100 open/close cycles. Its peer reaches the fixture command's 16 MiB output
limit and is terminated. Lighting and ACL commissioning fail after their
previously started peers' basic pairing windows close. All thirteen owned
peers are reaped. These results do not establish complete P09 acceptance.

The verbose-peer regression confirms that the output cap terminates a live
fixture. `SoftwarePeer` now explicitly selects bounded log truncation while
other fixture commands retain failure at the output limit. The retained prefix
and truncation marker occupy at most 16 MiB. Continuous output cannot postpone
cancellation, owner-loss cleanup or the original absolute lifetime. Assertions
write more than twice the limit, verify a later peer checkpoint, cancel the
still-live peer, and check exact log size, marker, permissions and child cleanup.
A separate continuously writing peer expires within its lifetime and cleanup
budget. All 23 peer/build/runner tests pass in 8.0 seconds on the current
toolchain and 6.5 seconds on the minimum toolchain. The current default gate
passes 208 checks with 33 excluded in 71.5 seconds; ExDoc passes. Native sources
are unchanged. Case-time startup of uncommissioned peers and a fresh complete
software run remain required.

| Peer-lifetime artifact | SHA-256 |
| --- | --- |
| Rejected second cohort receipt | `a1d2cdea5421de869a1a27aaea3248f450e7673361ce86c6550e907dc223895a` |
| Rejected second cohort test log | `65d37d27a7ece827f272a3a9adc98cd0d22f2b04ca1d19fd2d54292d23880c28` |
| Peer command owner | `757270c195265b9f1831e2ad57fcad8e7db127b34c852a49556199360f9e67fb` |
| Peer lifetime | `b2b4d4f72a9c0bb994ffbd2429b676449955f6a78e89aee67f4fbc9b99d8dcca` |
| Peer assertions | `d8199f9eedc1853f100003519cf6aa2e013627ac431dfe60f3ef2d13bc6820c7` |
| Verbose-peer failure before correction | `a02b26348589d6d5e52b91ddc97a8163fbaf824663d739d9be1f0b26946c25cc` |
| Current focused gate | `87cfcb9e1a0001528756bb95be5ca750f0fb8afc11ba00844d41d32fe5c1783e` |
| Minimum focused gate | `09f8aabb74aa44a2db4fcfb310e468118aed3f3ba4b76d2c86a4f6825e4f1483` |
| Default gate | `702bc2f9011d9096a36d8be4b4db028e328b1781dbd2ed7cf8ce54ea746b4b56` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |

## Commissioning-peer ownership within each case

The required scenario helper starts only the four peers needed for preparatory
commissioning, one-shot interactions, the real expired window and ACL denial.
The other nine fixture descriptors retain their private executable arguments
and directories. Their consuming cases start the peer, await readiness, execute
the operation and verify peer cleanup before returning. Generated wrong-PIN
requests do not replace the peer's original setup PIN. Externally configured
fixtures without this descriptor retain their existing caller-owned lifecycle.
Per-case recipe observations are written after successful peer cleanup.

The preparation regression previously observes thirteen child processes where
only four are required. Its partial-startup variant observes eleven attempts
before the expired-window fixture fails. Both now observe the intended four
and three children and verify that all owned children are reaped. Callback
success and exception tests observe the deferred child alive only inside the
case scope and reaped afterward. An externally owned fixture starts no process.
All 12 scenario/peer tests pass in 5.0 seconds on the current toolchain and
5.1 seconds on the minimum toolchain. The current default gate passes 210 checks
with 33 excluded in 73.2 seconds. Both formatters and ExDoc pass. These ownership
assertions do not replace the required fresh two-lane SDK acceptance run.

| Case-owned peer artifact | SHA-256 |
| --- | --- |
| Scenario preparation and case ownership | `9487b257d73420c80980d3f6cc66811dd3e4a958d67d7a2096075bef8d8ff83e` |
| Scenario ownership assertions | `32aa1f491f275a9f746e2f788dece1e9fef503d15e8a6e67b87a9dc849d9b944` |
| Preparation regression before correction | `b14913e8b27c86e40dc735ee31b9fe72a9300dc4a10444e2784878772b46ce81` |
| Current focused gate | `c38559f0886f21465d423f54b277094ee9597166b7a3972749a252c8be3b8132` |
| Minimum focused gate | `bba1b925a5a08ab271d280ea9f86da323955f69c412355c434a39132b2fc70f2` |
| Default gate | `a5d8fb844f6267ce46948fd12bb7478538cf373d48cb3dd305fcb673e674e8cf` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |

## Secure-channel handler cleanup and measured callback resources

The flow executable records actual acquisition and destruction of controller
contexts, SDK interaction clients, subscriptions, window openers and recovery
timers. Its SDK resource snapshots require `CHIP_SYSTEM_CONFIG_PROVIDE_STATISTICS`.
Snapshots occur before startup and after the event loop and backend are stopped.
The production target retains ordinary smart pointers and does not link the
observation implementation. Publication and cancellation counters contain no
request values or credentials.

The first instrumented sanitizer cohort rejects all three callback cases:
ReadClient and subscription acquisition/destruction balance at one each, but
two unsolicited-message-handler registrations remain in the SDK census. The
pinned factory's [system-state teardown](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/CHIPDeviceControllerFactory.cpp)
deletes the message-counter manager without calling its shutdown method and
deletes the unsolicited status handler without unregistering it. The
[exchange manager](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/messaging/ExchangeMgr.cpp)
updates registration statistics on unregister, while its shutdown does not clear
the handler slots. This observation establishes retained registrations in the
census, not a heap-leak measurement.

Controller cleanup now shuts down the message-counter manager and unregisters
the unsolicited StatusReport handler after the event loop stops and before
factory state is released. It uses SDK cleanup APIs without modifying the SDK
source or resetting counters. WMA-B-F11/F12/F13 pass on both BEAM lanes: each
actual SDK subscription and ReadClient is destroyed once, publication occurs
once, cancellation occurs, and all seven SDK resource counters return to zero.
The controlled callback producer remains distinct from the real SDK subscription.
Per-cycle stress snapshots and startup-stage faults remain separate requirements.

Both rebuilt native CMake gates pass six tests in 2.47 and 3.18 seconds; the latter
uses ASan/UBSan with leak detection. All 15 pinned OSV queries pass. The current
and minimum SDK/corpus cohorts pass 16 cases, including all 17 native corpus
vectors, in 18.3 and 25.6 seconds. Both owned peers are reaped. The current
default gate passes 210 checks with 33 excluded in 71.8 seconds. Both formatters
and ExDoc pass. Complete P09/C09 and the unchanged 95% coverage floor remain open.

| Native resource artifact | SHA-256 |
| --- | --- |
| Native controller cleanup and lifetime hooks | `454b9e21e3eb532996efec74806a8c1ddbc62f83ebd53739731082dd6c40d6b3` |
| Conditional resource ownership | `3554dc93b516373b3e909f69cda096e28740ac08333859c5b017aa49da39935c` |
| SDK resource observations | `091c266944268d5fd92fa73a71a5cc3843496be8e050460a595f0337a2e16f8a` |
| Native flow observations | `f4bcf8c415a72c28131ecfd62a5216c487d7bddacfa1090a003ce61d03b2a971` |
| Native build target definitions | `acd795328a9280d9bf659da3da142e0850e50dc17cadcb61ad3b5f9d24cc8448` |
| Resource assertions | `1797fcc37fd085d033c2c648f662b827bdae50b8e34bccb9dcd69f3e2e0fab70` |
| Legacy probe missing resource evidence | `08dc88bbb0de7207ef42324533ed316d461be154c70ee6a67cd47ee3e6625739` |
| SDK census failure before cleanup | `87e20ea31950d989d677e15fa7448e8e91e2372e747d1973341fe2d71884f60a` |
| Native build and both CTest gates | `e90033a36ab994dc13f33de721b5dde3db0b8f6a5b2a72d5e8fa3724db7b13de` |
| Pinned advisory gate | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |
| Current SDK/corpus gate | `1402584e5e4421e05d7f9eef94c4b3c8476ff5a87f841ea03d709aca3edd4818` |
| Minimum SDK/corpus gate | `c5d5e9240fd7d1e6d515b00580f5a3945fe5d60fa186d8fd512680aa86fc682f` |
| Default gate | `e93adab6f4aac829f8e24f604fe18a6970a7236bcae12e32a0d999d063a5b822` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Current wotex-matter-host | `ae7a3123ebb61adfaf0bbec4a84a7ec399cedff8fab219bfafa62cb492c44998` |
| Current wotex-matter-flow-host | `74569d394e611c9eb6c64222794dd0370e403f3646891abb150fe4fa6f34af98` |
| Current WMA-B-F11 native observation | `9e47acf6122ae4e91838bbc1604ec8253d68bbbfc1b322188cc20ea6ab12c58e` |
| Current WMA-B-F12 native observation | `dd33086c4ce35974b5be945e865647676791151329ac81e804109ff345902445` |
| Current WMA-B-F13 native observation | `6e4e4099d53d315ea4b00e9bf568bb5a16b17468d20b3790cb89ef9d76a3cd4b` |
| Minimum wotex-matter-host | `36c5a653eee72e9925143a58f83c66b7765b66a65561100901e617c1f1e6e65a` |
| Minimum wotex-matter-flow-host | `85b49b93105d29f7f134802c8772641e2b2111022c8300ccec44b31d0746f04e` |
| Minimum WMA-B-F11 native observation | `28dd49059226f95325f0767257d9f4fdb7152f66dc53d21615fcaeb6c4c33209` |
| Minimum WMA-B-F12 native observation | `7fdb9c051d3998317eef4f182f2b196948f5ad95d6aba80c143904ca8aeb2cea` |
| Minimum WMA-B-F13 native observation | `db84ff56e83fd21f73ac119575d3a95a72ee4b2a58dde52d7381e20a424eb46c` |

## Reports during pending control-pump observations

The third full current-toolchain cohort uses frozen `62c373e` source and the
`f15bd16` native implementation. It completes 241 of 242 checks in 875.5 seconds,
with one hardware case excluded and 31 of 32 required software cases passing.
Its source digest remains unchanged. All thirteen peers are reaped. The
one-shot case completes 1000 sequential reads, 100 open/close cycles and 32
concurrent callers; the live peer's final log is exactly 16 MiB with a truncation
marker. Lighting, ACL commissioning and all five generic commissioning cases
pass. The sole failure is the control-pump oracle's unconditional rejection of
Port data during its pending interval: it receives a valid second subscription
report. The full receipt remains rejected.

The control oracle accepts schema-valid reports for the original subscription,
session generation, negotiated SDK subscription identity and concrete path.
It tracks monotonic report identities and sequence numbers and acknowledges
exact cumulative encoded bytes. Outstanding reports retain the 64-frame/1-MiB
limits. Pending observation still rejects an operation reply; retirement requires
an exact barrier matching the last observed sequence. Reports do not reset the
250-ms pending interval or 500-ms control budget. Cleanup retains its 1000-ms
budget and rejects late replies.

Three deterministic channel tests cover multiple reports before and during
retirement, exact cumulative acknowledgements, preservation of the following
control reply, early replies, foreign identities, replay, schema failure,
excess unacknowledged reports and a forged retirement cutoff. They pass on both
BEAM toolchains in 0.1 seconds. Fresh SDK/corpus cohorts with the `0150337` native
implementation pass 16 cases, including all 17 native corpus vectors, in
18.5 seconds currently and 25.3 seconds on the minimum sanitizer lane. Both
owned peers are reaped. These focused SDK cases observe one report each; the
multiple-report condition is retained in the rejected full-cohort log and the
deterministic channel test. The current default gate passes 213 checks with
33 excluded in 72.4 seconds. Both formatters and ExDoc pass. A complete passing
two-lane software receipt and the remaining C09 gates are still required.

| Control/report artifact | SHA-256 |
| --- | --- |
| Control/report observation helper | `278fc4139a587c4ce359c96484307d4bae8e54ea59fb6932e27b214e5d889fad` |
| Control/report assertions | `b9c28f0880c5d9d22d634bb610243fd093fbf4596136bb7807227da84d5e6044` |
| SDK control-pump case | `e4471844bc68f6b751e9062e328d9988e8564ff8759da70ab7da3a73e83d1e1d` |
| Third rejected full-cohort receipt | `3e97a5b9c0416455e26dae7b553dbfb6ca571185cf35af560c73d1ec42022482` |
| Third rejected full-cohort test log | `3e4fd4dbcab9af51d9cd5cffd4a3c1f19641c803c98318bd1d2bfede9416b6b5` |
| Completed one-shot stress observation | `6831c410f635f506586098c970a3adcfd356d2f742bca32c9b36b00bbb88a8fd` |
| Current focused gate | `3d54b18ff37f3758a04ffc224db0593021fe5ef1a7a653533853489d87f8b732` |
| Minimum focused gate | `d8a450140d2a836125db89fc66eb4670c246da79ed15c29a29e5dae80b4d6e20` |
| Current SDK/corpus gate | `657de04c848c28373e4c9c9a6c5cbdf765a559eb9b434ec4b0ae888355950d93` |
| Minimum SDK/corpus gate | `562dcfd6222af86c2db23ea36f11b8056e5ad48b555f0b5f355d5a1cc8db4934` |
| Current control observation | `c3203972b8f7d897f20016abd117b09735c559d3872ab613f0eb3e5feebcf250` |
| Minimum control observation | `323e0d4d6c7f81d7cf49e6ca97123b588f88877b740d13db80d1ebd09ed0f8ff` |
| Default gate | `c0322039612c82f2ea491f9184e278a22d495cb3d0baf2187bf0beb7299b3e1e` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |


## Current full software cohort and native startup cleanup

The frozen `f6bbfa0` source with the `0150337` native implementation passes
245 checks in 900.0 seconds on Elixir 1.20.2 / OTP 29.0.4. All 32 required
software cases pass; one physical-hardware case is excluded. The source and
completed-source digests both equal
`ac73d1a1ac4295a02b0178bcca174eb6e2a2a41c29fc524e8c5fbfd6411e2370`.
Seed 450520 is retained. The outer runner verifies cleanup of all owned peers.
This receipt covers its frozen inventory and source; the following startup
case increases the required inventory to 33 cases.

`test/software/startup_resources_test.exs` binds WMA-V04 to eleven actual SDK
startup boundaries: memory, durable storage, process directory, SDK storage,
authority, attestation, groups, factory, retained system state, event loop and
commissioner. Each boundary exercises an injected failure return, an exception
and a wait interrupted by SIGKILL. Each of the 33 trials reaps its exact native
process and Port within 1000 ms, then reopens the same store and completes a
real SDK attribute read. Forced kills use process reaping and successful store
reopening as their cleanup evidence. Failure returns and exceptions additionally
require all nine native object acquisition/destruction counts to balance and
all seven SDK resource counters to return to zero. Every recovery read also
records the actual interaction and ReadClient lifetimes before final cleanup.

The test executable publishes bounded observations through private files. An
observer serializes with host operations and schedules resource snapshots on
the SDK thread while its event loop runs. Snapshot publication closes its file
descriptor before making the complete observation visible. Configuration,
startup faults and resource observation I/O are compiled only into explicitly
selected test executables. The software build exports both normal and sanitizer
resource executables and includes their hashes in artifact validation.

Before the cleanup change, an injected exception after factory initialization
aborts with exit status 134 instead of the required bounded exception exit.
The backend destructor now invokes idempotent shutdown even when startup has
not reached the open state. The production entry point catches standard
exceptions after stack cleanup and exits with status 1. It emits no fabricated
operation result. All 33 trials and their recovery reads pass in 16.0 seconds
on the current Linux lane and 28.6 seconds on Elixir 1.18.4 / OTP 27.3.4.15 with
ASan, UBSan and leak detection. Maximum observed cleanup is 41 ms and 84 ms.

Both native CTest gates pass six tests in 2.52 and 3.19 seconds. All 15 pinned
OSV queries pass. Fresh SDK/corpus cohorts pass 16 cases, including all 17 native
corpus vectors, in 18.6 and 25.8 seconds, and reap both owned peers. The default
gate passes 213 checks with 34 excluded in 71.9 seconds. Twenty build, fixture
ownership and acceptance-runner tests pass on both BEAM versions, in 10.2 and
9.0 seconds. Both formatters and ExDoc pass. Per-cycle stress resource checks,
forced stress failures, final-source two-lane software execution, coverage and
clean archive evidence remain required for complete P09/C09 acceptance.

| Startup cleanup artifact | SHA-256 |
| --- | --- |
| Fourth full-cohort receipt | `fa01c792a3e3e0ffa6eacbbc083dafadf9ce5f68e5dd25198bf1c67d77f90f90` |
| Fourth full-cohort test log | `d8309600ff3578f84f5166888dc487d870ce925e37c61015386c9eddb09f8e4f` |
| Startup resource case | `bb48e297eb24d85002c473c5e830170b1ef824ab0733ca772fcdeb4a6a5a5c4d` |
| Resource assertion helper | `5acaf5db6d1d97eccc5eeb4669483ef0d73a4faee760b55f648db620f1e94d59` |
| Native controller | `28e30636cd2c1f1a166ac23590a79dd02353d7db89b930fd2fc861583c3a9475` |
| Production exception boundary | `ea4a2f8d81fc86be7ac64c734013c18f8d626d92c931012993395f1dd9ccbd50` |
| Native resource executable source | `ef946343b9be451020cbd27e2722aff3c7829c90731958e87f1404908285899f` |
| Resource observation implementation | `fa9354605b2d7d22ecf9689c0d2f4f9e1be133e9df931392414a33c9b4e46dc3` |
| Required case inventory | `5bfce7360120903122d6fdeac1aaa1a060f80ff446d30e74598928a1c350eb31` |
| Regression before destructor cleanup | `7bc9863490e99d4be348f2990d08df35c448871e58594eb4e05180c13cf52ae3` |
| Native build and CTest gates | `5a74da404134ff4c2ceb5cc968b4b93c05171e88687369694f98333e824a9225` |
| Production entry-point rebuild | `58cb1fe3e81fef3b36b9541416e486266cee32ed808c4267e5d5b0f51fac9ffa` |
| Advisory gate | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |

| Default gate | `72ab1b235a452222d19d85483efca003a8a9bae9fc17495fc766a887ffa7d47c` |
| Minimum harness gate | `33d558fbf429ecd03b4348deade74e3c5fe93162ea02639d64ccb48673e8f18d` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Current startup observations | `4714aa68e14f2083788b9b475dee3d21d9df8f5ecdd574545e0aa90b8d775cf7` |
| Current startup test log | `252bcfa48ac479c44afcd62336c0fb517f66d1387e7e3dc8b2e9a2a4d13570b9` |
| Current SDK/corpus gate | `b29fae87f9910e5e298115e56297fd23264487f602fcc34aa8dedcca194bec7e` |
| Current wotex-matter-host | `e9ea6b9353520f0569a92dbd9b62694398fa8a9c37ba6521a72b4db1176ea2e2` |
| Current wotex-matter-flow-host | `89e488339028a76e2f20b8ff268ee3e8dd01e37f9b60bbe7ea00b0043e483098` |
| Current wotex-matter-resource-host | `95dc325a31793e282e52fb247d5bf7234e2aa389aa351b21d6dffcf36a0e111e` |
| Minimum startup observations | `375cc06a9a1d54f5518d4e4fdd8103756535d2fbf3f7d35cca7bce1c04da955f` |
| Minimum startup test log | `74d9d33af9bed67928e36fea0d29488c92e190db041b8c2393e5f347a3346202` |
| Minimum SDK/corpus gate | `c6e3005b88f8007e4c6ada19e071c31ae3e676540cd1a5e43a0b4e9b58c79776` |
| Minimum wotex-matter-host | `2291e908db21b109ad171594a954830285f915ea7cdf8bb829d25ad6e5436c01` |
| Minimum wotex-matter-flow-host | `4cdd9b65fb9be457b57f58b2183eabdb96abbaf846531cf3a721856ae11d3eff` |
| Minimum wotex-matter-resource-host | `d1617104e4319806d44889737519c5d07b43d1293824c873d9eb45d047b1e82b` |


## Resource census throughout persistent stress

The persistent software stress case selects the resource-observation executable.
After a warm read, each 100-read batch and the completed group of 32 concurrent
calls must return all nine tracked native object counts to balance and all seven
SDK counters to the warm baseline. Each of 100 receiver-termination cycles also
checks the completed subscription count against its cycle number. The existing
BEAM admission, monitor, stream-owner, Port and file-descriptor checks remain.
Snapshots retry only within one original 1000-ms cleanup deadline.

Every completed native generation, including discovery, the main stress session
and the 100 open/close cycles, must publish its final resource census. Both Linux
lanes complete 102 generations with balanced object acquisition/destruction and
zero SDK counters after shutdown, in 154.1 and 179.4 seconds. Each lane records
1235 interaction contexts, 1335 ReadClients and 100 subscription contexts, with
matching destruction counts. The actual live baseline on both lanes is
2 TCP endpoints, 4 UDP endpoints, 4 unsolicited-message handlers and 1 timer;
packet buffers, exchange contexts and platform events are zero. The stress
session creates and destroys exactly 100 subscriptions. All assertions use the
unchanged `61ba553` native implementation and its recorded binary hashes.

Heap/RSS observations are separate from this resource census. The current lane
records 21,688 KiB at each of its ten 100-read checkpoints. The sanitizer lane
records the sequence below. RSS growth does not identify an allocation owner;
these observations make no claim about its cause or a plateau. All native
processes exit with status 0 under the selected ASan/UBSan leak-detection lane.

Sanitizer RSS in KiB: 172944, 175752, 178664, 181460, 184284, 187048, 189880, 192744, 195572, 198420.

The default gate passes 213 checks with 34 excluded in 72.6 seconds. Both
formatters and ExDoc pass. The required software inventory remains 33 cases.
The passing persistent-resource case does not close the remaining one-shot
resource, forced-stress-failure, coverage, final software-build/run and clean
archive requirements.

| Persistent stress artifact | SHA-256 |
| --- | --- |
| Current stress results | `cd80433811a012dda1be0dc784c973922d283b17ad4e4928d0c1551ce7f734db` |
| Current stress test log | `42d7cc7bc9f75fb7b15135c8bebd8c2fddeb1d636a4d310f7276e66e6c179988` |
| Current resource-observation digests | `c19c79d1c328a7c39b8752a56a7ecbc4626a404d6bc81e22e0c8370367b31a22` |
| Minimum stress results | `00879fe920f0c9a697186b8623a34ca003b9ddebe3d2e903aa407acc399693dc` |
| Minimum stress test log | `a7f31b76b9211df9d710d0e14502498fc138d3dfedceab303b822dae37a4dd19` |
| Minimum resource-observation digests | `1d3d47c750ef47c3cbb37d980fce9255ad645e3dedb08eb6ad3eb324827abcb5` |
| Stress assertions | `a3c2b8b94ee07b66d726c533b8a40b71335a088fa2c8fec1661e6825ea77d9d2` |
| Software fixture selection | `8187efb97063a24f764f9f99c07787fa95db54edf556bfc819688268a9a94364` |
| Default gate | `e13311c14cd766ee8f54e7faccf933fc7d125c98e0c81f8eb9b4b438d32ed0dc` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |


## Runtime relay admission and unknown calls

The direct relay boundary rejects malformed client/stream keyword lists and
startup budgets outside 1–60,000 ms before client acquisition. Duplicate or
unsupported stream options and invalid interval/queue limits also fail before
connection setup. Finite upper boundaries preserve the normalized native request.
Unrecognized process calls return `invalid_handle` and preserve the live route.

The pre-change probes accept malformed option lists and budgets of -1 and 0.
An unknown call also crashes the relay with a function-clause exception. Its
OTP 29.0.4 crash report includes synthetic request data in callback arguments,
although `format_status/1` redacts the last message and displayed state.
The unknown-call fallback prevents that untrusted input from reaching the
exception path. This is a bounded input-handling result, not a claim that the
relay controls every external OTP crash-report mechanism.

Eight relay tests cover invalid startup input, valid limits, owner/request/path
binding, forged capabilities, single-use frame tokens, 64 pending opening
reports followed by overflow, invalid metadata, dead owners, connection failure
and unknown-call diagnostics. Together with the existing Runtime stream cases,
they pass 15 focused tests. The initial upper-bound oracle used the public option
name instead of the normalized client field; the corrected assertion checks
`queue_limit` and the final gates below pass.

Both Linux lanes pass those 15 cases and the real SDK Runtime-loss case:
16 cases in 1.6 and 2.1 seconds. Native connection/child loss emits one terminal
notification and reaps each generation within 1000 ms. Observed cleanup is
14/21 ms currently and 72/25 ms on the minimum ASan/UBSan lane. The native
implementation remains `61ba553`. The default gate passes 221 checks with
34 excluded in 70.3 seconds. Both formatters and ExDoc pass. This packet does
not accept the remaining C09 software, coverage or archive requirements.

| Relay boundary artifact | SHA-256 |
| --- | --- |
| Relay implementation | `c1d68dd6c206bc2cac388e92256794efe60f0c37bee5773beb34635e5c852e2d` |
| Relay boundary cases | `950ce0bcef8c38ea61698dc88b8905ab76d92c59c1c79c0a8b9f6988500ac3a3` |
| Before-fix regression log | `1d139402d3d2aabaa83402b5197e181013a37b51f50328c9ca2495555bf171c5` |
| Default gate | `4ca1f2b5bfe73644515d7c25be98f1f5adc5d5b2605ecddbe917231520770dac` |
| Focused gate | `3d5ce4b45521271ee90bc8b72d0fa26bc41d5d59072d283e2546abefc0546012` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Current relay and SDK tests | `4f7fe6ffbe841d18b3e8b3e4dcc3cfa3790ac8b775c22af104cf8bf5bde3d36e` |
| Current native loss observations | `4dea3cb88c029f6e37aefe6fa69936199d126cf1548907a4fc5ede812a442073` |
| Minimum relay and SDK tests | `c10c670b7ff5aaebd8cf93a0110ead760e7c477b6bdda44d0619567b05b187be` |
| Minimum native loss observations | `ce4dfb3e0037e1435628597a5d43e7863df6c7b4a09bdf17ee5ee5ace038a324` |


## One-shot and mutating-operation resource ownership

The resource test executable optionally creates a private directory for each
native PID. Each successful one-shot read must leave a complete final census:
its interaction and ReadClient are each acquired and destroyed once, all nine
tracked object lifetimes balance, and all seven SDK resource counters are zero.
A failed controller open records its completed SDK cleanup before the error
reply. This preserves that observation if BEAM subsequently kills the failed
startup before the executable publishes its final exit record.

Both Linux lanes pass 1000 sequential reads, 100 open/close cycles and 32
concurrent calls, plus one warm read. All 1133 native generations are observed
and their exact PIDs are reaped. Each lane records 1102 successful reads and
31 failed lock acquisitions; the concurrent outcomes are one success and
31 `storage_open_failed` results. Native failure observations match the public
API counts. The current lane publishes 1133 final records; the sanitizer lane
publishes 1130 final records and retains the pre-reply zero-resource census for
all 31 failed starts, including the three killed before their final record.
The cases complete in 421.8 and 696.7 seconds. Both owned all-clusters peers are
reaped. The minimum lane selects ASan, UBSan and leak detection. Caller heap
samples are recorded separately from the native resource census.

The first resource runs are rejected after 260 and 146 generations because their
executable-wide process census overlaps separate startup tests using the same
binary in another BEAM instance. The failure times fall inside both startup
case intervals. Every completed one-shot generation has a zero final SDK census,
and both owned peers are reaped. The accepted census is scoped to the current
probe's recorded PIDs. It preserves the 1000-ms cleanup allowance and the
10,000-ms read budget. No failed operation is retried. Both accepted frozen
cohorts contain byte-identical resource-executable source, resource assertions
and one-shot case source to this packet; the complete software profile still
requires a final-source run of its full inventory.

`test/software/operation_resources_test.exs` additionally binds WMA-V13 to a
case-owned lighting peer. It commissions that peer, reads its OnOff value,
invokes On, verifies the changed value, writes an administrative ACL, verifies
its decoded contents and opens an enhanced commissioning window. Resource
snapshots follow the actual SDK callbacks. Each lane records five interaction
contexts, three ReadClients and one each of commissioning context, CommandSender,
WriteClient, window context and WindowOpener, with matching destruction counts.
SDK counters return to the warm baseline after operations and zero after close.
The cases pass in 1.1 and 1.8 seconds and reap both peers. The fixture builder
prepares fourteen isolated peers and starts four during preparation; the
operation-resource peer starts inside its case. The required inventory contains
34 software cases.

Both rebuilt resource executables pass the existing 33 startup-boundary trials
and recovery reads. Both six-case CTest gates, all 15 pinned advisory queries,
20 minimum-toolchain build/fixture/acceptance cases, both formatters and ExDoc
pass. The default gate passes 221 checks with 35 excluded in 73.2 seconds.
Actual SDK resubscription/recovery-timer evidence, forced failures during stress,
the unchanged 95% coverage floor, the final public build/run and clean archive
evidence remain required for complete P09/C09 acceptance.

| One-shot and operation resource artifact | SHA-256 |
| --- | --- |
| Current one-shot results | `179ea3ba1b40ac288c936645e82c5a435e725d2ec4ce8b6796be4a52c5b2db2d` |
| Current one-shot test log | `5acb6199477f689d58eb95afbae01809d99c0d67526b5bc4f9c1c80747e87ee0` |
| Current one-shot resource digests | `8ed43565ed1600af90f03b7a0f66d68d1476670d9805ce0d8eea6577eeabf2d6` |
| Current owned peer cleanup | `53498677cb1ae4b8596fabc02a28acf4f02f710fb6da01e03fe0dc1e60d5826a` |
| Current resource executable | `c3544e7d50b6d11ef35b5b4004e5848e40df6fc19bc672530645815e5e4f410e` |
| Current operation resource results | `6c5abca3a0ad64472e085cea92626044d8131f83743d29fb2b3fbeac76aeacb7` |
| Current operation resource test log | `5213282bff51389d8d3409d14efbbe7ed9f5405c83e85b745d8522c3c07592fb` |
| Current startup resource test log | `dfd41fda768da08b730f617db75d25f36a4555b7fbd23f781417e2b07ab8efc0` |
| Minimum one-shot results | `cf66f3946aef4d0a878149f7d0cb23fb2c53f0f73d622cc28f4d611e0fa29739` |
| Minimum one-shot test log | `104a54c171c21902413d78b0038edad1b1df657a71c5cf645b42b7bde48fe94c` |
| Minimum one-shot resource digests | `07b98eb53b2ba94a70ff7af9ef2432b8929bee1495fd5c60b203edd146d63b20` |
| Minimum owned peer cleanup | `64278ded6f68f62500375e62bc2eed4244658338197821b029840cf3b9d4455d` |
| Minimum resource executable | `43b24b852164ec07fc85a8629a8ab528a920dc44602642b65c288e5c9bf47ef1` |
| Minimum operation resource results | `6c5abca3a0ad64472e085cea92626044d8131f83743d29fb2b3fbeac76aeacb7` |
| Minimum operation resource test log | `90d6d77716b2001f5691b1eb3bb5f2a50c39735ce4f1cd663e62457479042a04` |
| Minimum startup resource test log | `289b093d58c7153af5450bfda71efd33cba0e86faaf963949f71ca65f2f6e4fb` |
| Resource executable source | `c8cd9003afcf0000bf7f568834fcdcbb85c3ea602a325bac305a184f571434dd` |
| Resource assertions | `6bab41c8a411fe24798227dd619fac12897d3c2d0626f733fd0ac0d29b4a5c87` |
| One-shot resource case | `48c7521bf04ebee7bd34c9e50f62508bc89ffdcca8c09eb35b2837dd516a528b` |
| Operation resource case | `b543de2c5526dd12b7eba8435d0a89011edaae060b00c531257b83345b130586` |
| Required case inventory | `da67711ff6e18b1158429225c0ff1226932862644fd88d7822598cd98638d3a2` |
| Build and both CTest gates | `c00092b3ff7542e27b002ba6c32367a8fad7a5965939577d83ac65a94647538b` |
| Default gate | `cf809f14955b2b80b4ef6f88e6bed35d8dbea11337be150ffd5324e8297d0f4c` |
| Minimum harness gate | `8d5c79e2d803ba8a729e9808c7f559952fd926cbfd58141474fa937f6b78c2c0` |
| Advisory gate | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |
| ExDoc gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |

## Native channel failures after read load

The selected resource executable injects a deadline, EOF or malformed native
response after 101 successful SDK reads. Each mode first closes the SDK and
records its actual resource census before withholding or corrupting the native
response. The case observes 100 successful public reads and the corresponding
`timeout`, `transport_closed` or `invalid_frame` error on the next read, with
`effect: :none`. This is controlled native IPC failure evidence; it does not
represent a malformed Matter peer message or SDK resubscription.

Both Linux lanes pass all three modes. Request durations are 554/28/12 ms on the
current lane and 553/79/23 ms on the minimum ASan/UBSan lane. Cleanup after return
is 15/0/9 ms and 49/1/17 ms, respectively. Each exact connection process, Port,
native PID and admission table is gone within the original 1000-ms allowance.
Every pre-failure census balances 101 interaction contexts and 101 ReadClients,
all other tracked object lifetimes and all seven zero SDK counters. Each mode
then reopens the same controller store and completes another real read.

The required inventory contains 35 software cases. Both rebuilt resource
executables also pass the 33 startup trials with recovery reads and a separate
33-generation one-shot pilot: one warm read followed by one successful concurrent
read and 31 bounded storage-lock failures. Both six-case CTest gates and all
15 pinned advisory queries pass. The default gate passes 221 checks with
36 excluded in 76.8 seconds; the minimum harness passes 20 cases in 9.5 seconds.
Both formatters pass. The final full software profile and remaining P09/C09
requirements retain their separate acceptance gates.

| Native channel failure artifact | SHA-256 |
| --- | --- |
| Current stress failures | `b6df51ef08e40a731c2118aa9c6e7f4e7e6899eea9d459592c98fbf737ad7751` |
| Current stress test log | `604273a8f05507af9c338892fa91f97c61bf32c58b92cab4e7b846883ac2297e` |
| Current startup test log | `4d6127fde774f0089efb9f7d643138696665937ad23a31d04ee6e5d08b3929d6` |
| Current one-shot pilot | `61144734f22a3bee336e562d27cd17d5ecb13872126c35965d0e42b263073bb3` |
| Current resource executable | `dc456c9f08e5af1844055c482075309ceb21942c6dda27d0b02080d3960c158d` |
| Minimum stress failures | `70a5ee08ddd03e48d59fda88122f4c356d3ef284fc771763fa48df71a3423faa` |
| Minimum stress test log | `5a51e9af5930765cdd349658dd7d7a15f7c45ebd4231705ca7f8ad1b4d5c31d6` |
| Minimum startup test log | `78ffea2f1a1cec89a3dcbd229fb53bce83e97db6cdf94bf90eba57359ce13af1` |
| Minimum one-shot pilot | `61144734f22a3bee336e562d27cd17d5ecb13872126c35965d0e42b263073bb3` |
| Minimum resource executable | `ce5f25275679944134f9868ddf75ee0c1bfdaa095d957856b098bfaa33fb4af1` |
| Resource executable source | `8be57153b3d6f0811f4d58f6720c6341ebe66b039addc86010467a12956a57c9` |
| Stress failure case | `6710d7676a17b7c14b2b0ad964817095db33933777fa0d919df98101ebdf1f76` |
| Resource assertions | `02e9e15f21846c868e7f0a8698c76dd575372c14a11f51621741f56f92ee80f1` |
| Required inventory | `97e5d2651cba4508814f4040c437028b52208a9d6c995d0d85bbe7c8216b7a9d` |
| Native build and both CTest gates | `0e57f0707fa994a09fc656733df64f5a442e7d0cd90376170628a7e0f6861188` |
| Default gate | `6a2e590949eb6825b7457347b9fab2a088986c92810eaa50ff4ce39c78390bcc` |
| Minimum harness | `8f91fc361eab7243a2df5cb0bdf899997b6e1a8722e8a8e41390a5817df07749` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Advisory gate | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |

## SDK subscription recovery and shared session setup

The real recovery case commissions an owned lighting peer and stops and restarts
that peer with the same persistent identity. It observes continuity loss,
delivery generation 2, `resubscribed` with unknown continuity and a fresh initial
snapshot. Cancellation during a second recovery releases the subscription and
its timer. A separate lost subscription expires after 60,008 and 60,012 ms with
two attempts on the current and minimum lanes, within the 60,000-ms retry budget
plus 1000-ms cleanup allowance.
Two simultaneous subscriptions then lose their peer; cancelling one preserves
the other's recovery and initial snapshot. Each lane observes five actual
recovery-timer acquisitions and destructions, four subscription lifetimes, six
ReadClients, two interaction contexts and one commissioning context. All tracked
lifetimes balance, SDK counts return to the warm baseline after completed
cycles, and all seven SDK counters are zero after controller shutdown. The five
owned peer processes are reaped. The final cases pass in 119.5 and
120.1 seconds on the current and minimum ASan/UBSan lanes.

The pre-fix cancellation releases the ReadClient and recovery timer but retains
one extra SDK timer throughout the 1000-ms cleanup allowance. The pinned
[ReadClient destructor](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/ReadClient.cpp)
detaches callbacks without releasing the shared operational-session setup.
The controller's SDK-thread reapers now release a peer's unused setup after its
last local operation or subscription completes. This cancels its outstanding
address resolution or retry through the SDK's
[session-setup destructor](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/OperationalSessionSetup.cpp).
The SDK operation releases setup state; it does not evict established secure
sessions. A queued reaper checks for a live CASE manager because controller
shutdown may already have released that manager. The sanitizer control-pump
regression detects the missing guard before the final build.

Both final, fully owned SDK cohorts pass all 16 cases and all 17 native corpus
vectors in 18.4 and 25.4 seconds and reap their lighting and
all-clusters peers. Earlier evidence remains rejected: a long-lived-peer run
times out on a one-shot read, and both initial fully owned runs expose the
shutdown guard defect. The read-timeout cause is not established by the fresh
peer result. Operation budgets and cleanup allowances remain unchanged.
Both six-case CTest gates and all 15 pinned advisory queries pass. The default
gate passes 221 checks with 37 excluded in 69.1 seconds, and the minimum
harness passes 20 cases in 9.2 seconds. Both formatters pass. The required
inventory contains 36 software cases and adds a fifteenth peer that starts
within its case. Full
final-source software coverage, public build/run and archive acceptance remain
separate requirements.

| Subscription recovery artifact | SHA-256 |
| --- | --- |
| Current recovery observations | `cb2f88222bcce892e680bdcaca3c5d2fe2b11e05871595db54c39d00581bd50d` |
| Current recovery test log | `17eefbe96fb77a2966f9a67e8d92f97e20bc93bf697a75481adbf0c972aed3d6` |
| Current SDK regression log | `23b583f080f12c45f16ba41fde2a26ce0cadaf5172b0d47c43a46f8ce0d097e6` |
| Current controller executable | `9405de31d6dd4df41f9c230c250459ad812e888c062640890df4287935521193` |
| Current flow executable | `df9b6bc4b80f48745c98fc5af93850666576bfa9b1381d23e9f1622ec17613bc` |
| Current resource executable | `6dd06ece470204e58ca297fbb6cb37a6c536497f21e7681776c02a85db98cf55` |
| Minimum recovery observations | `9e8619b744a18609d99b6b5587d46bc0aeb22f6a99ec0f6fc6bcd292a2b454fa` |
| Minimum recovery test log | `58654bfdccfa6f3fadd36fc3622908f4cb279a61472f18ce1c3491c9f5a45859` |
| Minimum SDK regression log | `372d0e48a0bd963c4c3e9faafa5331523cfc0e9616eda77f5d1ecde34308994d` |
| Minimum controller executable | `4888b7dc42ba19fe626a622543c9c8844df3b35953d08cd4ed2206d0b1e439b0` |
| Minimum flow executable | `fb0cae6e4f9a076f3939cd145bc0f6e76feb41857cb047690223653e3dcf5f3d` |
| Minimum resource executable | `2675700274c7e6966bc909a98c74c4a8b4672b9b74ae3abbf046ccbe60a32a05` |
| Controller source | `243cbd174c38939af5c5971db97eed8c63b0ee83854671531b6710005f6011d9` |
| Recovery resource case | `f7a9f66c8eeeaa19c3c4a3372f5bf7f1abef61648ea12206d889b9a3b44fea0e` |
| Required inventory | `7dc6c1583a764323491d6af3456e8a94b462a39944a4618aadc63e01f99c499c` |
| Retained-timer regression | `11015d41300535a0008bfbd796a4b798cea7c2951a12d26e406e5dd4250cdf02` |
| Rejected long-lived-peer SDK run | `69899a643fb76c2102cc5863a7b337f04a107483be4a2a99cc3bb73a204fa527` |
| SDK shutdown guard regression | `e7ee72acafd8cacecbed25c9bbdc3e8c8f4e3bcbd9ac18d8a2da7e88387f42b7` |
| Native build and both CTest gates | `ea4cf59b3ce262d6cb7e3d31492bc832a492c963090103702fdf61b3ffa57d18` |
| Default gate | `b5603b7e39e3b4acc778ecafcebecc2eb01f8c95f5e8aa442cce9e76a0741ef9` |
| Minimum harness | `055c1a928046bd34d7d840356ec810d6bf91bb734451c67c1462178c63e26af3` |
| Minimum formatter | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Advisory gate | `cc75ced8da953cb5668bd93328c38861095e87c8c491bd8e683902a67a76e2fc` |

## Native owner process-call capability boundary

The WMA-C02/C03 regression begins with all 64 ordinary admission slots reserved
and sends a valid raw request directly to the connection process. Before this
change, that call bypasses admission and writes a native read. An unknown direct
call terminates the owner, and a close message with an unrecognized control kind
is accepted. The three pre-change cases pass zero assertions and retain their
observed native write and returned values.

The connection callback now admits only an exact bounded-call envelope, an exact
reserved close capability and the creating caller's startup identity
request. Ordinary operations dispatch through a private path after the owner has
matched the reservation's token, caller and absolute deadline. Close control
also binds its token, caller, deadline, generation and finite control kind.
Unknown, malformed and legacy raw calls return `invalid_handle`, keep the owner
alive and do not log or transmit their payload. The receive loop applies the
same rules while native I/O is pending.

The final serialization boundary revalidates operations and subscriptions even
inside an admitted envelope. Subscription path counting is a bounded proper-list
traversal, so an improper or over-limit list returns `invalid_subscription`
without enumerating unbounded input or terminating the owner. A foreign
generation returns `invalid_handle` before subscription parsing. The shared
validator keeps the public and owner-side paths aligned.

All five focused cases pass in 3.5 seconds on Erlang/OTP 29 with Elixir 1.20.2
and in 3.3 seconds on Erlang/OTP 27 with Elixir 1.18.4. The broader persistent,
request, subscription and recovery set passes 79 cases on each toolchain. The
default gate passes 226 checks with 37 excluded in 74.2 seconds. A serial full
coverage run passes the same 226 checks and raises measured coverage from 90.7%
to 91.1%; the unchanged 95% requirement remains open. This packet changes no
native source, executable or software-peer result.

| Native owner boundary artifact | SHA-256 |
| --- | --- |
| Pre-change regression | `d2a6bafb8ec723e5797386331c0929e7a695a89a37f5e82d02efb79ea339185c` |
| Current focused gate | `7c5a6c81dfdfad2a6a797ba6ded986d8472cf62871a2f8736647bc66a23a99cf` |
| Minimum focused gate | `705c86b63a0b130fd36ecc52bdce18c9d3c2c0da6aa3d61e013de2f52f10a688` |
| Default gate | `a2770d3638d339d0370af4d5999ac09c5f9075454985c43af68b2df389077870` |
| Coverage gate | `e0379fc367694381d6abcacbc5c04721347bcadabc7466988f580c007aed87b2` |
| Native API source | `6b94962281f34b105a172590d79949ec19883de71068408a4130ffb9caf35d49` |
| Admission source | `ac488cd87249e6a808b770dfb806124ac948ce55c737ad740b91b395d657ab85` |
| Connection source | `73235b90c0f843625aed168827a02a3c8858eff0235f6ad318de2535d7a4d616` |
| Request validator source | `8c8366da679c6346f08ae4e99ef65df06019f2e64c9a1cebfc34836029b0db2d` |
| Boundary regression source | `7cdc531339cee650dee5d8d17b7b038b42cbb4cbcdbd0f6e9270b19f8ad9a039` |

## Default coverage acceptance and defensive process transitions

The default coverage gate now passes the unchanged 95% floor. It executes 242
checks with 37 explicit software/hardware exclusions and reports 95.0% across
2475 relevant lines. The immediately preceding complete measurement passed 239
checks at 94.1%, so the accepted result comes from new executable assertions,
with no threshold, ignore-list or production coverage configuration change.

WMA-B02/C04 assertions enumerate every fixed native error identifier and verify
its bounded public atom, default effect and empty diagnostics. WMA-C03 assertions
exercise admission identity, close ownership, submission state and table death;
an ordinary reservation racing with its reserved close is released without I/O.
Exhausted uint64 request identity cannot wrap or dispatch. Forged stale monitor
and maintenance messages leave the live owner usable. Synthetic terminal Port
notifications exercise the same exact-child cleanup path as native no-EOL,
exit-status and linked-exit events.

WMA-C02/C05/C08 assertions verify direct stream-owner and Runtime-relay status
redaction, malformed delivery rejection, subscription and teardown error
propagation, bounded opening reports, terminal-status classification and a full
final-owner mailbox. Attribute/event schema and timestamp failures publish no
Runtime frame. The transport charges time spent connecting to both baseline and
controller request deadlines. Public batch, SDK, TLV and one-shot fallbacks
return their documented structured errors. These cases exercise existing
production behavior; this packet changes only tests and their explicit fake
client controls.

The complete affected set passes 136 tests on Erlang/OTP 27 with Elixir 1.18.4.
The accepted coverage run uses Erlang/OTP 29 with Elixir 1.20.2. No native source,
binary, peer fixture or previous software receipt changes in this cohort.

| Coverage acceptance artifact | SHA-256 |
| --- | --- |
| Enforcing 95.0% coverage gate | `6e2cc19f53091115961de3975b57f989416cbb043f4e822b7ed7d4c7fa06e84c` |
| Minimum-toolchain affected gate | `ee81afb7dfaaad374de6224187a85186c9c9de6c443df270e2b8329894ca6671` |
| Admission capability cases | `d67e6a1aa9d691fe7c4fb3e0e0012a5c3ef43ac43c901cb56ab80776d20ee31f` |
| Native wire vocabulary cases | `6022944d1cf7e09f25556e4862e79c3f7c499d3efa57c42bee28bd0c4fb886db` |
| Native owner transition cases | `72d2839e128fb88ca934d886b5c7266cbafca30829e022321198c24091ed6066` |
| Stream owner cases | `2f34758b27c917e68bd7b66be8f6f5afdd1dd78756e383a809a5d5ab3e8ddb58` |
| Runtime relay cases | `6dedf6085ae997b631b7d83bff436ef1ebbb981514d70085bbf1ffccfdcff016` |
| Runtime transport cases | `e83601671f61b07f290b5267b4926983d44551e484f344c28b35d618dd90211f` |
| Explicit fake-client controls | `89ad7e2d582d7911e2f22011053325aafa7b7832611fc7dc192f365518f78024` |

## Immutable dependency bootstrap and isolated one-shot responders

The public software runner now resolves the exact checked-in lock from a private
lane directory while loading the project through `MIX_EXS`. It compares the
resulting lock byte for byte with the read-only source lock before compiling.
Dependency, build and Mix/Hex state remain under `/run`; the mounted repository
remains read-only. This removes Hex's attempt to create its temporary tarball
directory in the source root without weakening the immutable-source check.

A fresh public workspace from frozen `5f2bf0f` source builds successfully and
reproduces the previously accepted normal and sanitizer native binaries. Its
current-toolchain run completes dependency bootstrap, source compilation and
953.7 seconds of the required suite. The receipt is rejected: 275 of 278
executed checks pass, all 36 required software cases execute, three tests fail,
one hardware case is excluded and the minimum lane is withheld. The source
digest remains `a7384f8bbfea594bc450df364254e78a3df21a4dcee79ee4e2c9b1698d397473`
before and after the run. All owned containers, peers and the private network
are reaped.

The first failure exposes a race in the baseline SDK adapter after it has
already detected an oversized response. The child can close between
`Port.info/1` and `Port.close/1`; the resulting `ArgumentError` was caught by
the outer request rescue and replaced the precise `response_limit` result with
`transport_unavailable`. Cleanup now tolerates only the already-closed exact
Port and reraises an error for a still-live Port. The two SDK adapter cases pass
200 consecutive randomized repetitions after the correction.

The remaining failures share one all-clusters responder. The one-shot stress
case completes 896 successful generations, then its initiator does not receive
any of five Sigma2Resume transmissions. The responder retains that handshake
until its own timeout and reports busy to the next controller. The unchanged
10,000-ms operation budget therefore fails without retry, as required. The
functional one-shot case subsequently reaches the same busy responder and also
fails. Scenario preparation now commissions a separate all-clusters peer and
controller store for the 1,133-generation stress case. Functional and load
evidence can no longer contaminate each other's responder state; deadlines,
operation counts and no-retry behavior are unchanged. Six focused SDK and
scenario-ownership tests pass, including cleanup of all five preparation peers.
A fresh final-source two-lane public run remains required.

| Immutable-run correction artifact | SHA-256 |
| --- | --- |
| Successful public build log | `7bf9c3b20fc13672e0d1f438580c4ec558756ce9548dbc30435febd72ad1ba0d` |
| Rejected public run log | `d659789d25974eeba54248113f9750e5c9c0291b03684b6925588ab1d34fc606` |
| Rejected current-lane receipt | `0bb970e89389e906eeb5358ada78ce46a763b5d9d50c4bbb1e7dde6aa7cacba8` |
| Rejected current-lane test log | `a94a87ae009041521363dc0268b36e23509317bc59e2dbb7228676be3d84452a` |
| Stalled responder log | `f2cabeaf0f6d4719e1c0ddd789f7746e9267fb8b0120648ade120d4db136552d` |
| Focused gate | `fcf3d7240052c9319a5fa4b1baab2f675e9cca992ffe9400c406a95bbe6ca19b` |
| SDK adapter source | `cd81a365c1bb8237662a1509e7f203356ba08ca82dbc71bdddc95f08242b6cac` |
| Scenario preparation source | `f2323a023f5bea79099a388bca082f06dfcf1899475046c79e724779e56efca7` |
| Scenario ownership assertions | `1a9370c7cff6bb576298178159a95328c2bff6f6d35b742cbbcd8901a3274dab` |

## Accepted software profile and clean package

On 2026-09-15, frozen revision
`90e8a479284f0df792feea71a695cc5e65dbc085` completes a fresh public software
build and two-lane run. The build verifies connectedhomeip
`250a9e6c50ee2068107f3c4808b680f5f2925415`, reproduces the accepted normal and
sanitizer host/flow/resource binaries, passes all six CTest executables in both
modes, passes 15 OSV queries and builds the lighting, all-clusters and bridge
peers. The immutable source digest is
`e1d5d0e634a44b05b5ebe8ed8ad0b67a3a824a49e75e3502936086cc23219839`
before and after execution.

The current lane uses Elixir 1.20.2/OTP 29.0.4 with seed 826333. All 278
executed checks pass, all 36 required software cases execute, and the one
hardware case remains explicitly excluded. The minimum sanitizer lane uses
Elixir 1.18.4/OTP 27.3.4.15 with seed 239117 and has the same 278-pass,
36-required, one-hardware-excluded result. Both lanes independently pass real
commissioning/CASE, good and bad PIN, failed attestation, real window expiry,
peer-enforced ACL denial, finite interactions, attribute/event subscriptions,
persistent restart, 1,133-generation one-shot stress, forced failure and native
resource-census cases. Each lane reports zero failed, duplicate, unexpected or
hardware-executed cases. All owned peers, containers and networks are absent
after the run.

A separate clean checkout created only from Git archives passes locked
dependency acquisition, the mandatory 242-check developer gate with 37 explicit
exclusions, the 95.0% coverage floor, ExDoc with warnings as errors and
dependency-load side-effect inspection. A normal Hex archive preserves released
dependency declarations, passes content inspection and compiles out of tree
with a fresh development build directory. These checks establish source and
package readiness; they do not assert that this development version or its
upstream package requirements have been published.

| Accepted software artifact | SHA-256 |
| --- | --- |
| Workspace source manifest | `9b25a0730eb2280edd0d6de9325fb17ef3e1e45e71ad3cd8d3e1b1f46a143af6` |
| Public software build log | `2a5bbb98251b51cee2a3c2c09629a044fc66bef34ccc408e2b4aa4f65f1da20a` |
| Public two-lane run log | `5e5a2ba09ea795e9f05803f7c3bf6b595726b3c02dfbfec951889270cf13a09b` |
| Outer software result | `52c5d2aa573bf990e32f2938054d4024bdc9a193bdf7baf110ccba43c55f5167` |
| Current-lane receipt | `639bf3967ddc863a7914cb9ef72a8085b3a64d84b3c732f2ad27e1a4d24c5efa` |
| Current-lane raw test log | `ff24c80bea6525583087e21db502475ea28b899c2434cd7ee28a2cdd22943912` |
| Current-lane outer log | `737a14ba008a32f7e03d2fce83340a1102c148db51eec08545b2e50523e1585c` |
| Minimum sanitizer-lane receipt | `28c21e8effd7f24a08943b214a51ee9f1c185c427c947dba967345102ff4b7fa` |
| Minimum sanitizer-lane raw test log | `1c2c82f5175271810bb478a80ca26912e5f8cf96527d08e200be4e1c3bc3a15f` |
| Minimum sanitizer-lane outer log | `a35f19cd33e861f4e9798e1e1015a7fec3ec944d75b90dbb29db1d8c211c81be` |
| Clean developer gate | `e6e3036197192e11a0ede8984d26d32e6c8bd7f1074da076d7ada675e2b4e446` |
| Clean coverage gate | `04a36b93cebde1c6fd4cb00070bb648c3fedf63bf88683c47a71cdd31973c6b4` |
| Clean documentation gate | `c52984c1b5255318f6bb82d5f6ba6e4273631b6ccc12c6587db2e3754e151ccb` |
| Dependency-load output | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Hex archive build log | `1759e7c5aaf6468e3cb3fc269c574298c06afb50fca2cf775545d00b2ba013ec` |
| Final archive inspection log | `8dfb3f36f33f71bfb34f7f123e009f63aab3ea38178991b1c43ae86b0befcfbe` |
| `wotex_matter-0.1.0.tar` | `6d1937c8ca4c8397eb030552e6f94edb336adbef17ecd71d517b555a71355ed0` |

## One-shot peer session-capacity correction

A fresh build from claim-recording revision
`83c583f32c04bc2d698c4f2ca24720bc0862bfdc` passes, but its current-lane run is
rejected after 950.2 seconds: 277 of 278 checks pass and the minimum lane is
withheld. The only failure is the read-only one-shot stress case. Its dedicated
peer accepts 881 CASE handshakes and performs 832 secure-session LRU evictions.
On attempt 882 the peer receives Sigma1 and transmits Sigma2Resume, but the
controller receives none of the bounded retransmissions and returns the required
timeout. The fixed 10,000-ms deadline and lack of retry are correct.

The stress peer now compiles with a test-only 2,048-entry heap-backed secure
session pool. All 1,133 fresh controller generations fit without unrelated peer
session eviction, so the case measures controller process/storage/resource
cleanup directly. The production controller configuration, operation count,
deadline, result assertions and native generation census are unchanged.

The mandatory gate also exposed a stale test-only release marker when a later
BEAM reused the same temporary filename. The joined-cancellation test now removes
that marker before opening its native gate and again during teardown, so its
intermediate `:closing` assertion is synchronized by the current test process
rather than filesystem state from an earlier run.

| Session-capacity correction artifact | SHA-256 |
| --- | --- |
| Successful exact-source build log | `58ccf4939491c8879e33b3994c102b2a43cafd2d895764dcd186ea774e5f483f` |
| Exact-source workspace manifest | `f84b85c34f33584b54e1b93f7402a459b926ac11aad656d3a5eb7ecfc86ee344` |
| Rejected outer software result | `bf1229a9f3367f4b8184104c22d7b793ea5acafef67f609ac76a8fca4828aff1` |
| Rejected current-lane receipt | `af3d4ba98637af7fe301655e6f97530edc7f0b943b714d2bb6cb8487df74fd5e` |
| Rejected current-lane acceptance log | `b2c6726927f1328ea2012be869c93bbd51384da5165dc4f693bddf709c9fb36a` |
| Rejected current-lane raw test log | `bff9eb702a32c8369983595e18138d55756522e1c1a0cf6f69b3afeda5337be8` |
| Dedicated one-shot peer log | `5ae46208ddcd81030cf9a9e83d98ef565eda8dd0d8bc2d2daa1ecf98a64d20fc` |

## Lifecycle stress peer separation

The first run from correction revision
`656b7194e3e5ea916e8baa25db838611c5b9f493` is rejected after 998.8 seconds on
the current lane: 277 of 278 checks pass, one hardware case is excluded and the
minimum lane is withheld. The one-shot stress peer performs 1,103 CASE Sigma1
receives with zero secure-session evictions, confirming the session-capacity
correction. The only failure instead occurs at the boundary between the
lifecycle stress case's receiver-death and open/close phases.

After the subscription-heavy controller closes, four server-side subscription
reports remain in Matter retransmission teardown on its peer. A new controller's
read request is acknowledged immediately, but the peer's report engine waits
10.24 seconds for those reports to clear before sending the read result. That
misses the unchanged 10,000-ms operation deadline. The stress fixture now uses
separate commissioned lighting peers for the receiver-death and read-only
open/close phases. This removes responder-state coupling while preserving 1,000
sequential reads, 32 concurrent callers, 100 receiver-death cycles, 100
open/close cycles, resource assertions and no-retry behavior.

| Rejected lifecycle-boundary artifact | SHA-256 |
| --- | --- |
| Build log | `ac6890030ce4a9b49da849301972e12a8c6d2d8ff22d6f8a1d75994fe4d36aa4` |
| Workspace manifest | `726b35e2e99dcece0f8922b6b845a78d5f30db1f3bfbdc64433dd3d4316bf21c` |
| Outer software result | `53f3676b47ae97a5741bfac1034fb20afc8ccd03ca4598e2dec57dd570b40a0d` |
| Current-lane receipt | `5f15e12dde25fd0f685c3e9eb8b3a8511ccb3a6158c0a0c1b9466ad1580a1567` |
| Current-lane acceptance log | `f17c6320d3c8ed06e1d4fe82e792ad62da2658e63adada5936b1721ee1f4c77c` |
| Current-lane raw test log | `672781dd51c8c6e85935fc929249502bebafbf8fcf600c6be6701afb4571181d` |
| Zero-eviction one-shot peer log | `7db79191a4bd8380d2a09244bb375837da04c6b1f6776e92d297266c3587f378` |

## Final separated-peer software acceptance

A fresh build and unretried two-lane run from lifecycle-isolation revision
`93e110004ed9cd8a56b28568b7e9f5fabc765ff3` pass. The build verifies the pinned
connectedhomeip revision and all 15 advisory queries, passes both six-case CTest
gates, and reproduces all 16 executable and certificate artifacts from the
previous build byte for byte. Only the source-bound native manifest changes.
The immutable software source digest is
`7420c107e27e6a42db7631818714f8be6d0d87c5b57c735e4a9d09c71a8057e0`
before and after both lanes.

The current Elixir 1.20.2/OTP 29.0.4 lane passes 278 executed checks with seed
961164 in 1,023.1 seconds. The minimum Elixir 1.18.4/OTP 27.3.4.15 sanitizer
lane passes the same 278 executed checks with seed 66006 in 1,274.7 seconds.
Each receipt passes all 36 required software cases, records one explicit hardware
exclusion, and reports zero failed, duplicate, unexpected or hardware-executed
cases. ASan/UBSan report no failure. Both lane records contain zero owned
containers and networks after cleanup, and both acceptance logs confirm that all
owned peers were reaped.

Each one-shot stress peer receives 1,103 load CASE Sigma1 messages and performs
zero secure-session evictions. The dedicated lifecycle read-only peers contain
zero subscription requests and zero report-response timeouts while completing
their 100 open/close generations. Subscription teardown remains confined to the
separate lifecycle peers used for the receiver-death phase.

| Final separated-peer artifact | SHA-256 |
| --- | --- |
| Build log | `58fc097264ccee1561276bc9d62e09d4f0e48ee207c9cac7316709f10be86970` |
| Workspace manifest | `b47d27157d53574a23f704d568e8a6d0ae077dc7a7120f6a32b13f02ad955fa1` |
| Public run log | `1b88f4a5d35a7b6358a2c0fd262f921624dc0a9652bf639a8ffbbac7b682f7cf` |
| Outer software result | `27ecaf3332fc618a59f87b4a4b55f9542b8138dedee6b9f2c988ee123345c3cc` |
| Current receipt | `4a537a14896fcd12a026520010f7441f8210efda8a47b2094e310ca34de53c51` |
| Current acceptance log | `6560e56100a3669d6314b5fd165fb6cdfbc8fb2cfb8725540c0dc9fe585c6e48` |
| Current raw test log | `ba6f04b33e7975e5876c2822d94d7cda49f7ef6d077668d856e0f7c767e47d34` |
| Current one-shot stress peer | `86b9a91fbc082f932ba01118e4a09f4e578981aa5f22eb8e781e2fcd49fec800` |
| Current lifecycle stress peer | `5e1e2f61a73a46f8decc4de82d4c6c7f59df1891ad36a12167cbbc0b8e5cd529` |
| Current lifecycle open/close peer | `41e8d232cdc6823e59e1d92af343fa1c06abbe5f85d63b3be8ac4ac5afee981a` |
| Minimum receipt | `4f8bfb9a1e7a5511dd04087922bccd71f35e1d97bdd6438631c71e449dd32fed` |
| Minimum acceptance log | `891ef131f3576457a96e0eb918b4a63aa988ff5f51de6b560e0281001323932e` |
| Minimum raw test log | `e99de3f4d39700a0ff237c49f3c87eb8f14a6a3c6190b6bf2f54f9098283e2a3` |
| Minimum one-shot stress peer | `fa9edec379b2a83684f6cd1bc270403572e0a790478c5c877deea50321cea44d` |
| Minimum lifecycle stress peer | `87bd14fdd8b36f7da4bc44fe0d1240fe642fb6729048be70de07de56386be3e6` |
| Minimum lifecycle open/close peer | `b3f52dcaf541cd8af9e28cd522c9fb0d3a7dd4ae54be23774a942a6a44cff9ec` |
