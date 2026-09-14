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
