# WTH software implementation sequence

This sequence defines acceptance of the native OpenThread host profile.
[Current implementation evidence](../provenance/executable-evidence.md) identifies
implemented cells; [WTH.13](../specs/WTH.13-native-backend.md) owns native
build, IPC and tooling requirements. Source presence alone is not acceptance.

## Read before changing code

1. Read the root and `packages/wotex-thread` `CLAUDE.md` and matching repository rules/skills.
2. Read [WTH.00 — shared software rules](../specs/WTH.00-library-contract.md).
3. Read [WTH.10 — exact target profile](../specs/WTH.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
4. Read [WTH.11 — standalone API, preservation and concrete corpus](../specs/WTH.11-standalone-client-and-preservation.md).
5. Read [primary source pins and access limits](../provenance/primary-sources.md).
6. Select the first work package below whose acceptance evidence is absent.

Read the [versioned catalogue](../specs/catalogue.yaml) and
[WTH.12 — Wotex integration](../specs/WTH.12-wotex-integration.md) before choosing
implementation work. The catalogue lists dependencies and distinguishes planned
contracts from narrow implemented profiles. Source presence, fixture presence,
passing baseline tests and accepted work packages are separate facts.

The numbered sequence is dependency order: each package depends on all preceding
packages. Each is one bounded behavior plus its tests/documentation. A large
package may be split into consecutive local commits along its stated sub-behaviors;
never commit knowingly failing tests. Do not reimplement a satisfied requirement
merely to produce a commit. Every proposed module, API and test path below is a
target addition unless it already exists; no placeholder file implies completion.

For each requirement, record its ID in an ExUnit/native test name or a fixture
manifest. Scenario families specify required outcomes in .10; concrete inputs and exact
expectations are in .11 and its fixture corpus. The implementation chooses
ordinary internal function names and data structures, while the public behavior,
state transitions, limits, failure policy and transport choices are fixed there.
If an upstream API cannot meet a requirement, add the smallest adapter needed
or document a precise source-backed contract correction with regression evidence;
do not silently skip, simulate or weaken the requirement.

## Ordered work packages

### WTH-P00: Own reproducible native build and fixture tooling

- Requirements: WTH-B01, WTH-B02, WTH-B03, WTH-B04; C01–C10 apply.
- Concrete cases: every WTH-B-Fxx case in `native-port-v1.json`.
- Change surface: first-party native build/host, BEAM Port and Mix/ExUnit fixture ownership.
- Test destinations: `test/wotex/thread/native_contract_test.exs`, `test/native/flow_test.cpp`, `test/software/lifecycle_stress_test.exs`.
- Done when: Implement the .13 Mix native/software tasks around the existing C++ host, pinned fixes and SDK build. ExUnit owns generic fixture assertions; native C++ tests share production parser/storage/credit code. Preserve existing host behavior and complete flow credits before accepting state streams.
- Suggested local commit: `feat: own native thread build and bounded IPC`.

The bounded source download, archive admission, exact SDK fixes and content-bound
workspace now feed `mix wotex.native.build`. A Debian 12 arm64 SDK host build and
ready-frame smoke passed without Python. The shared native report-flow owner,
its BEAM ledger and the parser/flow corpus cases WTH-B-F01–F05, F07–F10, F14 and
F15 execute through a native contract driver. The host accepts `flow_open` and
`report_ack` under separate reply, control and report output reservations, and
WTH-B-F06 executes against the real host. `mix wotex.software.build` and
`mix wotex.software.run` pass on Linux arm64 and emulated Linux x86_64 for both
BEAM lanes, including real-host process ownership cases. Native State
subscriptions provide the report source, and F11–F13 execute on all four
lanes. `test/software/lifecycle_stress_test.exs` executes the C09 operation,
open/close, receiver-death, concurrent-caller, forced-deadline, peer-loss and
malformed-reply cycles on all four lanes. `bin/check_native_advisories.exs`
requires a checked-in review for every advisory reported against the native
source pins; it currently fails on the unreviewed OpenThread advisory
CVE-2025-36939, whose fix is not identified. That maintainer review and clean
archive validation remain open, so P00 is unaccepted.

### WTH-P01: Harden dataset syntax and daemon parsing

- Requirements: WTH-S01, WTH-S02, WTH-N01, WTH-N02, WTH-N04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V01, WTH-V03.
- Change surface: Dataset and read-only Daemon request/response boundary.
- Test destinations: `test/wotex/thread/dataset_boundary_test.exs`, `test/wotex/thread/daemon_fault_test.exs`.
- Done when: Preserve unknown TLVs and exact typed daemon results; invalid/missing/extra output closes the socket and never becomes success.
- Suggested local commit: `feat: harden dataset syntax and daemon parsing`.

- Concrete cases: WTH-F01, WTH-F02, WTH-F03, WTH-F04, WTH-F05, WTH-F06, WTH-F10.
- Standalone closure: Add the concrete corpus runner and exact Dataset/daemon fixtures; do not mistake presence completeness for semantic validity.

`contract_fixture_test.exs` validates the corpus format, operation kinds and exact
expectations and binds each case to its executing test. WTH-F01–F05 and F10 run
in `dataset_boundary_test.exs` and WTH-F06 in `daemon_fault_test.exs`; F07 and F08
remain explicitly unexecuted under P04; F09 executes in `native_contract_test.exs`.

### WTH-P02: Own an explicit openthread host sdk instance

- Requirements: WTH-S03, WTH-N01; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V04.
- Change surface: OpenThread adapter, C++ host and POSIX event-loop integration.
- Test destinations: `test/wotex/thread/sdk_bridge_test.exs`, `test/native/owner_test.cpp`.
- Done when: Explicit RCP/interface/store ownership, versioned framing, nonblocking input and reverse EOF/startup cleanup are enforced.
- Suggested local commit: `feat: own an explicit openthread host sdk instance`.
- Standalone closure: Supply the native management API and typed State boundary; Daemon management rejection must happen before socket writes.

### WTH-P03: Validate datasets through the pinned sdk

- Requirements: WTH-S01, WTH-S03; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V02.
- Change surface: validate_dataset/get_dataset bridge operations.
- Test destinations: `test/native/dataset_test.cpp`, `test/wotex/thread/sdk_dataset_test.exs`.
- Done when: Call otDatasetIsValid with TLVs and active/pending flag; presence-complete invalid combinations fail before mutation and raw secrets stay redacted.
- Suggested local commit: `feat: validate datasets through the pinned sdk`.

### WTH-P04: Implement explicit formation and management callbacks

- Requirements: WTH-S04, WTH-N01, WTH-N02; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V05, WTH-V06, WTH-V07.
- Change surface: form_network, set_enabled and management Active/Pending Set operations.
- Test destinations: `test/native/management_test.c`, `test/wotex/thread/management_test.exs`.
- Done when: Formation requires empty owned state and explicit authorization; management completes on callback, reports acceptance separately from effectiveness and safely retires late contexts.
- Suggested local commit: `feat: implement explicit formation and management callbacks`.

- Concrete cases: WTH-F07, WTH-F08.
- Standalone closure: Implement exact callback/unknown-effect results and retain timed-out callback context safely until SDK completion.

### WTH-P05: Implement commissioner and joiner ownership

- Requirements: WTH-S05, WTH-N01, WTH-N02; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V08, WTH-V09.
- Change surface: SDK commissioner/joiner state callbacks and admission records.
- Test destinations: `test/native/commissioning_test.c`.
- Done when: Finite exact-identity admission, PSKd validation, final role/completion states and timeout/stop cleanup work without wildcard admission or retries.
- Suggested local commit: `feat: implement commissioner and joiner ownership`.
- Standalone closure: Expose exact identity types and final commissioning results; Joiner completion does not silently enable Thread or promise attachment.

### WTH-P06: Deliver bounded non secret state reports

- Requirements: WTH-S06, WTH-N01, WTH-N02; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V10, WTH-V11.
- Change surface: native Subscription owner, state flag conversion and capability documentation.
- Test destinations: `test/wotex/thread/state_subscription_test.exs`.
- Done when: Initial snapshot and permitted state coalescing are generation-bound; Forms remain read-only inspection and unsupported Runtime streams are explicit.
- Suggested local commit: `feat: deliver bounded non secret state reports`.

- Concrete cases: WTH-F09.
- Standalone closure: Keep native State subscriptions separate from Runtime application streams and eliminate inherited QoS/payload guesses.

Native State subscriptions, the host stream owner, WTH-F09 and real SDK role
reports execute on Linux software lanes; V11 Form cases rely on the existing
mapping tests. P06 is not accepted before P00, P04 and P05.

### WTH-P07: Build a real openthread software network fixture

- Requirements: WTH-S01, WTH-S02, WTH-S03, WTH-S04, WTH-S05, WTH-S06, WTH-N01, WTH-N02, WTH-N03; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V02, WTH-V03, WTH-V05, WTH-V06, WTH-V07, WTH-V08, WTH-V09, WTH-V12.
- Change surface: pinned simulation RCP/FTD, separate POSIX daemon and SDK-host instances.
- Test destinations: `test/interop/openthread_test.exs`.
- Done when: Unique simulated node IDs, isolated state and actual management/commissioning callbacks prove the profile; no two owners share a radio.
- Suggested local commit: `test: build a real openthread software network fixture`.
- Standalone closure: Execute .11 network formation/joining/pending activation and layered sensor/light CoAP workflow with explicit test routing and software peer.

### WTH-P07a: Prove the Wotex consumer boundary

- Requirements: WTH-I01, WTH-I02, WTH-I03, WTH-I04, WTH-I05, WTH-I06; all previous native/profile packages are dependencies.
- Concrete cases: every `WTH-I-Fxx` case in `priv/fixtures/wotex-integration-v1.json`, expanded with the I06 negative/context/stream matrix.
- Change surface: root profile/0 and profile/1, Error.class, Mapping, Transport and their public core/Runtime integration; no sibling implementation changes.
- Test destinations: `test/wotex/thread/runtime_integration_test.exs` and explicit test-only credential/client ports.
- Done when: every admitted mode constructs the exact BindingProfile, real ConsumedThing calls preserve route/value/metadata/identity, unsupported cells acquire nothing, unknown-effect mutations remain non-retryable through Runtime, and every declared stream closes through the real Runtime owner. Native-only operations remain native; test fixtures are runner-owned assertions, never adapter answers.
- Suggested local commit: `feat: integrate explicit runtime profiles and failure classes`.

### WTH-P08: Prove host management cleanup and reproducibility

- Requirements: WTH-S01, WTH-S02, WTH-S03, WTH-S04, WTH-S05, WTH-S06, WTH-N01, WTH-N02, WTH-N03, WTH-N04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WTH-V13.
- Change surface: native sanitizers, stress and complete software runner.
- Test destinations: `test/software/lifecycle_stress_test.exs`.
- Done when: Exercise callback lifetime/use-after-free faults plus required concurrency/version/archive/package gates; hardware remains a separate optional lane.
- Suggested local commit: `test: prove host management cleanup and reproducibility`.
- Standalone closure: Require all concrete cases, native SDK workflows and software network resource counters before accepting the target.

## Reproducible software fixture contract

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

The build and run tasks are implemented for Linux; the recorded arm64 lanes are
identified in executable evidence. Use this command contract inside
`packages/wotex-thread`:

```sh
mix wotex.software.build --workspace /absolute/disposable/fixture-workspace
mix wotex.software.run --workspace /absolute/disposable/fixture-workspace
```

From the repository root the same tasks run as
`mix pkg wotex-thread wotex.software.build --workspace ...` and
`mix pkg wotex-thread wotex.software.run --workspace ...`; the root
`mix wotex.native.build --package wotex-thread --workspace ...` dispatches the
native build.

The runner executes `mix test --include interop --include software --exclude hardware`
and all required native tests/audits from .10. Add `@tag :software` only to tests
needing this software fixture/stress setup; normal deterministic contract tests
remain in `mix check`. The explicit runner sets `WOTEX_REQUIRE_SOFTWARE=1` and
the test helper must make missing fixture configuration fail under that setting.
Label same-stack, independent-stack, malformed-peer and injected-contract evidence
separately in the results. Hardware absence is not a software test result.

## Verification and commit procedure

Run focused tests while implementing a package (`mix pkg wotex-thread test
<files>` from the repository root), then run the package gate
(`mix pkg wotex-thread check --no-retry`) before its local commit. The ordinary
Hex dependency path is authoritative. Inside this repository,
`WOTEX_PATH_DEPS=1 mix check --no-retry` selects the `wotex` and
`wotex-runtime` packages under `packages/`; record which mode was used. Do not lower coverage, disable
warnings, waive audits or exclude newly failing code to make the gate pass.
Native changes additionally run their required native tests and dependency audit;
C/C++ adapters run ASan/UBSan in the Linux fault lane.

After each package, update the current-profile/README capability claims only for
behavior covered by passing evidence, and refresh [executable evidence](../provenance/executable-evidence.md)
with command, versions, vector paths/digests and result. Keep unexecuted requirements
explicit. Commit with the identity already configured by the contributor, as the
root `CLAUDE.md` requires; never configure remotes, push, tag, publish, change
visibility or edit a consumer.

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
