# WMA software implementation sequence

This sequence defines acceptance of the native Matter controller profile.
[Current implementation evidence](../provenance/executable-evidence.md) identifies
implemented cells; [WMA.13](../specs/WMA.13-native-backend.md) owns native
build, IPC and tooling requirements. Source presence alone is not acceptance.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WMA.00 — shared software rules](../specs/WMA.00-library-contract.md).
3. Read [WMA.10 — exact target profile](../specs/WMA.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
4. Read [WMA.11 — standalone API, preservation and concrete corpus](../specs/WMA.11-standalone-client-and-preservation.md).
5. Read [primary source pins and access limits](../provenance/primary-sources.md).
6. Select the first work package below whose acceptance evidence is absent.

Read the [versioned catalogue](../specs/catalogue.yaml) and
[WMA.12 — Wotex integration](../specs/WMA.12-wotex-integration.md) before choosing
implementation work. The catalogue lists dependencies and records implementation
status. Source presence, fixture presence, passing baseline tests and accepted
work packages are separate facts.

The numbered sequence is dependency order: each package depends on all preceding
packages. Each is one bounded behavior plus its tests/documentation. A large
package may be split into consecutive local commits along its stated sub-behaviors;
never commit knowingly failing tests. Do not reimplement a satisfied requirement
merely to produce a commit. Every proposed module, API and test path below is a
target addition unless it already exists; no placeholder file implies completion.

All P01-P09 work packages have accepted implementation evidence as of
2026-09-15. Later changes must rerun the affected package gates and the complete
source-bound software/package acceptance before retaining that status.

For each requirement, record its ID in an ExUnit/native test name or a fixture
manifest. Scenario families specify required outcomes in .10; concrete inputs and exact
expectations are in .11 and its fixture corpus. The implementation chooses
ordinary internal function names and data structures, while the public behavior,
state transitions, limits, failure policy and transport choices are fixed there.
If an upstream API cannot meet a requirement, add the smallest adapter needed
or document a precise source-backed contract correction with regression evidence;
do not silently skip, simulate or weaken the requirement.

## Ordered work packages

### WMA-P01: Preserve typed batch paths tlv and per path status

- Requirements: WMA-S01, WMA-S03, WMA-N01, WMA-N02, WMA-N04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V01, WMA-V02, WMA-V05.
- Change surface: new ReadPath, Address, TLV, descriptor-based value/result conversion.
- Test destinations: `test/wotex/matter/path_value_test.exs`, `test/native/value_test.cpp`.
- Done when: Concrete compatibility stays intact; read-only wildcards, unknown tags, explicit descriptor allowlist and deterministic per-path results are bounded.
- Suggested local commit: `feat: preserve typed batch paths tlv and per path status`.

- Concrete cases: WMA-F01, WMA-F02, WMA-F03, WMA-F04, WMA-F05, WMA-F06, WMA-F10, WMA-F12.
- Standalone closure: Add the exact report/catalogue types and pinned recipe descriptors; bind pure cases in the fixture runner. Native SDK calls are completed in P04.

### WMA-P02: Implement durable exclusive controller storage

- Requirements: WMA-S02, WMA-B01, WMA-B04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V03.
- Change surface: C++ PersistentStorageDelegate, operational keystore/certificate store and explicit authority/open/create schema.
- Test destinations: `test/native/storage_test.cpp`.
- Done when: Exact synchronous storage delegate, fatal durable-write failures, exclusive lock, atomic/fsynced state and crash-safe identity retention are proved.
- Suggested local commit: `feat: implement durable exclusive controller storage`.

### WMA-P03: Own a persistent first party sdk controller

- Requirements: WMA-S02, WMA-N01, WMA-N02, WMA-B01, WMA-B02, WMA-B03, WMA-B04, WMA-B05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V04.
- Change surface: C++ GN host, framed Port, SDK event loop, first-party credentials delegate and controller factory.
- Test destinations: `test/wotex/matter/persistent_bridge_test.exs`, `test/native/controller_test.cpp`.
- Done when: Explicit PAA/fabric/node configuration produces a controller; partial start/EOF/death unwind all SDK objects and storage locks.
- Suggested local commit: `feat: own a persistent first party sdk controller`.

- Concrete cases: WMA-F07.
- Standalone closure: The first-party persistent controller must enforce fabric equality before SDK entry; a custom factory does not complete this package.

### WMA-P04: Complete timed interactions and event reads

- Requirements: WMA-S03, WMA-N01, WMA-N02; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V05, WMA-V06.
- Change surface: C++ ReadClient/WriteClient/CommandSender translation.
- Test destinations: `test/native/interaction_test.cpp`.
- Done when: Timed/DataVersion/partial-status semantics are exact, native event identity is preserved and mutation timeouts never replay.
- Suggested local commit: `feat: complete timed interactions and event reads`.

- Concrete cases: WMA-F11.
- Standalone closure: Implement named attribute/command APIs and bounded Descriptor endpoint catalogue; enforce OnOff read-only and temperature/null/enum descriptors.

### WMA-P05: Deliver attribute and event subscriptions

- Requirements: WMA-S04, WMA-N01, WMA-N02; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V07, WMA-V09.
- Change surface: Subscription owner and SDK report callbacks.
- Test destinations: `test/wotex/matter/subscription_test.exs`, `test/native/subscription_test.cpp`.
- Done when: Initial snapshot/callback race, interval revisions, paths and generations are validated; cancel/death removes native callbacks and transactions.
- Suggested local commit: `feat: deliver attribute and event subscriptions`.

- Concrete cases: WMA-F08.
- Standalone closure: Preserve equal values with distinct report identity, native metadata and zero callbacks after cancellation.

### WMA-P06: Bound explicit subscription recovery

- Requirements: WMA-S04, WMA-N01; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V08, WMA-V09.
- Change surface: resubscription callbacks, budgets and stream statuses.
- Test destinations: `test/wotex/matter/subscription_recovery_test.exs`.
- Done when: Default loss is terminal; opted-in recovery emits continuity loss, obeys five-attempt/60-second bounds and cannot replay mutations.
- Suggested local commit: `feat: bound explicit subscription recovery`.

- Concrete cases: WMA-F09.
- Standalone closure: Prove default terminal loss and explicitly selected recovery without mutation replay.

### WMA-P07: Commission on network with verified attestation

- Requirements: WMA-S05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V10.
- Change surface: DeviceCommissioner/AutoCommissioner, CommissioningWindowOpener and typed ACL operations.
- Test destinations: `test/native/commissioning_test.cpp`, `test/interop/commissioning_test.exs`.
- Done when: Explicit new-node/window inputs, final SDK outcome, PAA/attestation failure and denied operational ACL are exercised without bypass flags.
- Suggested local commit: `feat: commission on network with verified attestation`.

### WMA-P08: Map matter property action and event results

- Requirements: WMA-S06; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V11.
- Change surface: Mapping, Transport and explicit read health probe.
- Test destinations: `test/wotex/matter/runtime_stream_test.exs`.
- Done when: Each Interaction Affordance maps to its real service and retains status/version/event metadata and original cancellation route.
- Suggested local commit: `feat: map matter property action and event results`.

### WMA-P08a: Prove the Wotex consumer boundary

- Requirements: WMA-I01, WMA-I02, WMA-I03, WMA-I04, WMA-I05, WMA-I06; all previous native/profile packages are dependencies.
- Concrete cases: every `WMA-I-Fxx` case in `docs/specs/fixtures/wotex-integration-v1.json`, expanded with the I06 negative/context/stream matrix.
- Change surface: root profile/0 and profile/1, Error.class, Mapping, Transport and their public core/Runtime integration; no sibling implementation changes.
- Test destinations: `test/wotex/matter/runtime_integration_test.exs` and explicit test-only credential/client ports.
- Done when: every admitted mode constructs the exact BindingProfile, real ConsumedThing calls preserve route/value/metadata/identity, unsupported cells acquire nothing, unknown-effect mutations remain non-retryable through Runtime, and every declared stream closes through the real Runtime owner. Native-only operations remain native; test fixtures are runner-owned assertions, never adapter answers.
- Suggested local commit: `feat: integrate explicit runtime profiles and failure classes`.

### WMA-P09: Prove the controller against pinned sdk example peers

- Requirements: WMA-S01, WMA-S02, WMA-S03, WMA-S04, WMA-S05, WMA-S06, WMA-N01, WMA-N02, WMA-N03, WMA-N04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMA-V12, WMA-V13.
- Change surface: Linux no-BLE SDK controller/all-clusters/lighting fixture and native audit.
- Test destinations: `test/interop/controller_test.exs`, the `test/interop/native_*`
  peers and `test/software/*stress*_test.exs`.
- Done when: Actual on-network commissioning, CASE, ACL denial, reports, cancellation, persistent restart and required stress/matrix/archive gates all pass.
- Suggested local commit: `test: prove the controller against pinned sdk example peers`.
- Standalone closure: Execute .11 lighting/thermostat/bridge catalogue and event recipes, durable restart and native API workflow with no consumer factory.

## Reproducible software fixture contract

The native and software build tasks are implemented with Mix-owned download,
advisory, hash, compiler and cleanup operations. Workspace admission and reuse
have deterministic tests; executed build identities are recorded in
[executable evidence](../provenance/executable-evidence.md). The software run
task verifies that workspace and executes the required scenario inventory on
the pinned current and minimum BEAM images. The accepted P09 candidate passes the
complete peer, stress, resource-census and matrix gates in both images, plus the
clean-source package and archive gates. Building the peer executables alone does
not execute their workflows.
The software build also produces normal and sanitizer `wotex-matter-flow-host`
test executables. Their source and binary hashes belong to the software receipt;
the native-only build does not require these process-flow fixtures.
These test executables count actual controller-context and SDK-client acquisition
and destruction, reply publication, cancellation and recovery-timer ownership.
Their before/after SDK resource snapshots require compiled SDK statistics and
run before startup and after event-loop shutdown. Callback cases reject retained
objects or changed SDK resource counts. Production targets use ordinary pointer
ownership and do not link the observation implementation.
The software build also exports the normal and sanitizer controller-test
executables used to exercise native output failure. Their executable hashes,
architecture and runtime libraries belong to the software receipt. Reuse fails
when either required harness is absent or changed. The source package includes
the ExUnit helper, all acceptance tests and their support files, native test
sources and the named native verification scripts.
The source identity also binds check, coverage, formatting and Mix configuration
and the archive/application verification scripts. Changing acceptance criteria
invalidates workspace reuse even when native source files remain unchanged.
Three public attestation roots are exported from the pinned SDK test credentials
and hashed in the software workspace receipt. Test-only trust directories are
copied into the private run directory; production execution requires caller-supplied
trust. Source identity includes embedded JSON schemas used by development
dependencies.

The entry points are `mix wotex.native.build --workspace ABS`,
`mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS`. Each requires exactly one absolute
workspace argument. Generic orchestration and assertions use Mix and ExUnit.
The native build contract is .13; production binaries never require Python.
Build requires a disposable empty workspace or a matching
manifest; refuses an unrelated nonempty directory; downloads upstream source
archives at the .10 pins without configuring any Git remote. Record archive
SHA-256, source commit, compiler/SDK/library versions, build flags, binary hashes
and fixture configuration in that workspace. Check hashes on reuse. Keep SDKs,
native builds, keys, certificates, sockets and logs out of the source package.

The run script owns only processes/containers created from that manifest, assigns
disposable local ports/state, waits for explicit readiness with a finite timeout,
exports the fixture configuration to tests, and traps all exits to release owned
resources. It must return nonzero for missing tools, unavailable required kernel
facilities, missing responses, failed assertions or cleanup failure. Do not
convert a failed setup to an ExUnit skip. Existing hardware tests require separate
explicit target configuration and are never selected by this runner.

Build and run the software fixture explicitly:

```sh
mix wotex.software.build --workspace /absolute/disposable/fixture-workspace
mix wotex.software.run --workspace /absolute/disposable/fixture-workspace
```

The runner executes `mix test --include interop --include software --exclude hardware`
and all required native tests/audits from .10. Add `@tag :software` only to tests
needing this software fixture/stress setup; normal deterministic contract tests
remain in `mix check`. The explicit runner sets `WOTEX_REQUIRE_SOFTWARE=1` and
the test helper must make missing fixture configuration fail under that setting.
Label same-stack, independent-stack, malformed-peer and injected-contract evidence
separately in the results. Hardware absence is not a software test result.

The required-mode ExUnit harness uses the explicit inventory in
`test/support/software/acceptance.json`. With `WOTEX_REQUIRE_SOFTWARE=1`, every
listed fixture and executable must pass preflight, and
`WOTEX_SOFTWARE_RESULT_PATH` must name a new result file in an existing absolute
directory. The harness records each required case, its evidence category, the
source and inventory digests, exact BEAM versions and the ExUnit seed. Changed
source during execution fails acceptance. Missing,
excluded, skipped, failed, duplicate or unexpected software cases fail acceptance.
Executing a hardware case also fails acceptance. Fixture and exception contents
do not enter the structured receipt. This harness records case execution;
the software run task owns peer setup and the enclosing container lifetime.

`SoftwarePeer` starts an explicitly configured peer through an asynchronous
`SoftwareCommand` owner. Readiness uses a bounded marker from the pinned peer's
output; connectedhomeip emits `Server Listening...` after successful server
initialization. The marker may span output chunks and produces one readiness
notification. Startup and lifetime budgets are explicit. Cancellation preserves
the child identity through delayed startup and checks that its Port and OS
process have been reaped. Early exit fails setup or teardown. The command owner
also observes normal and abnormal caller exit. Peer logs are owner-only files
bounded to 16 MiB, including an explicit truncation marker. Further peer output
is consumed without retaining it or terminating the peer. Cancellation, caller
loss and the absolute lifetime remain enforceable during continuous output.
Other fixture commands fail at their output limit. Readiness notifications
contain no output bytes.

`SoftwareScenarios.with_fixtures/3` prepares sixteen peer configurations and
controller stores for the required scenario inventory. Five peers start during
preparation: the common interaction peer, functional one-shot peer,
one-shot-stress peer, expired-window peer and ACL-denial peer. Each of the other
eleven peers starts through `with_peer/2` when
its commissioning case begins and is reaped before that case returns. Its basic
pairing window therefore starts with its own case. The helper assigns distinct
ports and discriminators within its runner-owned network namespace, creates
owner-only fixture files and invokes the suite only after commissioning and
failure fixtures are ready. The expired-window fixture waits for the real
180-second window and verifies its closed status. The untrusted-attestation
fixture selects a different public SDK test root. ACL denial is established by
an acknowledged typed ACL write. Any setup or callback failure unwinds the
owned peers in reverse order. Fixtures without a peer descriptor retain external
peer ownership. This helper requires the caller to supply the
pinned executables, public test roots and an isolated network namespace; it
does not implement workspace verification or the complete software run task.

`SoftwareFixture` holds the workspace lock while `SoftwareRun` rechecks source,
artifacts and development dependencies after execution. Each BEAM lane uses its own generated
Docker container and bridge network, read-only source/artifact mounts, private
state and a 90-minute absolute deadline. Command admission reserves 30 seconds
for cleanup; individual command timeouts cannot extend the lane budget.
A separate cleanup owner monitors the initiating process
and removes only that lane's container and network, including after caller
death. Cleanup verifies absence before the enclosing run can pass. Successful
command exit alone is insufficient: the lane must produce a passing receipt
with the expected source digest and exact BEAM versions. The final receipt
records both lane results, hashes and the dependency mode. Explicit development
path dependencies are identified separately from released Hex dependencies.

## Verification and commit procedure

Run focused tests while implementing a package, then run `mix check` before its
local commit. The ordinary Hex dependency path is authoritative. For the existing
explicit sibling-development setup, `WOTEX_PATH_DEPS=1 mix check` selects local
dependency sources; record which mode was used. Do not lower coverage, disable
warnings, waive audits or exclude newly failing code to make the gate pass.
Native changes additionally run their required native tests and dependency audit;
C/C++ adapters run ASan/UBSan in the Linux fault lane.

After each package, update the current-profile/README capability claims only for
behavior covered by passing evidence, and refresh [executable evidence](../provenance/executable-evidence.md)
with command, versions, vector paths/digests and result. Keep unexecuted requirements
explicit. Use the author and committer required by `CLAUDE.md`; never configure
remotes, push, tag, publish, change visibility or edit a consumer.

The final package accepts every .11 standalone, .12 integration and .13 native requirement,
then runs the full .00 C09 matrix, all .10 scenarios, .11/.13 concrete cases and software
peers, then a clean committed-source archive with the lockfile through `mix check`
and out-of-tree Hex package compilation. Confirm no Application callback or
dependency-load I/O, no missing packaged bridge assets, no downloaded SDK/build/
credential artifacts and no consumer-specific names/history. A passing coverage
number or stub adapter cannot substitute for a required protocol assertion.

## Completion checklist

- Every .11 and .12 requirement is linked to a concrete asserting test/result;
  no new target requirement is closed merely by an identifier or valid JSON.
- Every S/N requirement has its listed V scenario assertions and F concrete cases
  passing, with current digests. The .11 native workflow must pass without a
  Thing Description or consumer-authored backend.
- C01 compatibility, C02 malformed boundaries, C03 ownership, C04 errors/effects,
  applicable C05/C06 streams, C07 native framing, C08 redaction/telemetry and
  C09 stress/matrix each have executable evidence or an explicit scope-based
  inapplicable entry. No missing SDK/software facility is inapplicable.
- All required software lanes actually ran, including negative security and
  cancellation/resource assertions where the profile defines them.
- Current capabilities/docs agree with the implementation; target requirements
  have not been presented as baseline achievements.
- The clean-source/package gates pass, intended commits are local and the
  working tree contains no uncommitted tracked implementation change.

Physical-device validation, certification and publication
remain separate activities. They are not reasons to leave defined software
requirements unimplemented or to claim unexecuted software tests passed.
