# WMB software implementation sequence

The eight-function BEAM TCP client, standalone helpers, Runtime integration and
software peer assertions are implemented. Mix build/run orchestration is
implemented with acceptance still incomplete. [Executable evidence](../provenance/executable-evidence.md) binds the
accepted protocol assertions to exact source and toolchains; it does not validate
later task revisions. The ordered packages define acceptance, not a mutable tracker.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WMB.00 — shared software rules](../specs/WMB.00-library-contract.md).
3. Read [WMB.10 — exact target profile](../specs/WMB.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
4. Read [WMB.11 — standalone APIs, preservation and exact fixtures](../specs/WMB.11-standalone-client-and-preservation.md).
5. Read [primary source pins and access limits](../provenance/primary-sources.md).
6. Select the first work package below whose acceptance evidence is absent.

Read the [versioned catalogue](../specs/catalogue.yaml) and
[WMB.12 — Wotex integration](../specs/WMB.12-wotex-integration.md) before choosing
implementation work. The catalogue lists dependencies and distinguishes planned
contracts from narrow implemented profiles. Source presence, fixture presence,
passing tests and accepted work packages are separate facts.

The numbered sequence is dependency order: each package depends on all preceding
packages. Each is one bounded behavior plus its tests/documentation. A large
package may be split into consecutive local commits along its stated sub-behaviors;
never commit knowingly failing tests. Do not reimplement a satisfied requirement
merely to produce a commit. A named module, API or test below may already satisfy its requirement.
Source and exact assertions determine acceptance; a placeholder proves nothing.

For each requirement, record its ID in an ExUnit/native test name or a fixture
manifest. Scenario families specify required outcomes in .10; .11 defines
concrete fixtures and their executable oracle. The implementation chooses
ordinary internal function names and data structures, while the public behavior,
state transitions, limits, failure policy and transport choices are fixed there.
If an upstream API cannot meet a requirement, add the smallest adapter needed
or document a precise source-backed contract correction with regression evidence;
do not silently skip, simulate or weaken the requirement.

The concrete fixture file is `docs/specs/fixtures/contract-v1.json`. Its cases
are input data, not passing test evidence. Implement fixed operation adapters and
assert actual outputs against the expected projections described in .11; never
accept an identifier-presence or JSON-load assertion as requirement closure.

## Ordered work packages

### WMB-P01: Harden public command and conversion boundaries

- Requirements: WMB-S01, WMB-D01, WMB-D02, WMB-D04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMB-V01, WMB-V02, WMB-V06.
- Change surface: Address, Command, Value and root callbacks.
- Test destinations: `test/wotex/modbus/boundary_test.exs`.
- Done when: Revalidate forged structs; table-test every quantity, width, order and null/error boundary without opening a socket; preserve all eight helpers and floats, reject conflicting compatibility input fields, and execute the pure .11 cases through real APIs.
- Suggested local commit: `feat: harden public command and conversion boundaries`.

### WMB-P02: Enforce strict response and stream correlation

- Requirements: WMB-S02, WMB-D02, WMB-D04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMB-V03, WMB-V04, WMB-V05.
- Change surface: Codec and Connection response handling.
- Test destinations: `test/wotex/modbus/stream_fault_test.exs`.
- Done when: Every ADU split and malformed echo has an exact result; framing/correlation failure closes the session before any later request; bind wire corpus IDs to actual encoded bytes and decoded outcomes.
- Suggested local commit: `feat: enforce strict response and stream correlation`.

### WMB-P03: Bound connection admission and owner cleanup

- Requirements: WMB-S03, WMB-D03, WMB-D04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMB-V07, WMB-V08.
- Change surface: Connection request queue, caller/owner monitors and deadline propagation.
- Test destinations: `test/wotex/modbus/lifecycle_test.exs`.
- Done when: A 65th admitted operation returns busy; expired/dead queued writes send nothing; owner death is handled during receive; cleanup meets C03; execute the uncertain-write trace without a second transmission.
- Suggested local commit: `feat: bound connection admission and owner cleanup`.

### WMB-P04: Add explicit health probes and precise capabilities

- Requirements: WMB-S04, WMB-D01, WMB-D02, WMB-D03; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMB-V09, WMB-V10.
- Change surface: Modbus.health_check/2, Mapping, Transport and capabilities.
- Test destinations: `test/wotex/modbus/compatibility_test.exs`.
- Done when: Preserve existing valid helper results, document register-zero probe, reject write probes/security mismatch and retain Form extensions; run the standalone float write/readback/probe workflow through the public helpers.
- Suggested local commit: `feat: add explicit health probes and precise capabilities`.

### WMB-P04a: Prove the Wotex consumer boundary

- Requirements: WMB-I01, WMB-I02, WMB-I03, WMB-I04, WMB-I05, WMB-I06; all previous native/profile packages are dependencies.
- Concrete cases: every `WMB-I-Fxx` case in `docs/specs/fixtures/wotex-integration-v1.json`, expanded with the I06 negative/context/stream matrix.
- Change surface: root profile/0 and profile/1, Error.class, Mapping, Transport and their public core/Runtime integration; no sibling implementation changes.
- Test destinations: `test/wotex/modbus/runtime_integration_test.exs` and explicit test-only credential/client ports.
- Done when: every admitted mode constructs the exact BindingProfile, real ConsumedThing calls preserve route/value/metadata/identity, unsupported cells acquire nothing, unknown-effect mutations remain non-retryable through Runtime, and every declared stream closes through the real Runtime owner. Native-only operations remain native; test fixtures are runner-owned assertions, never adapter answers.
- Suggested local commit: `feat: integrate explicit runtime profiles and failure classes`.

### WMB-P05: Prove the complete tcp software profile

- Requirements: WMB-S01, WMB-S02, WMB-S03, WMB-S04, WMB-D01–D04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WMB-V11, WMB-V12.
- Change surface: existing libmodbus fixture plus required software runner.
- Test destinations: `test/interop/modbus_test.exs`, `test/software/lifecycle_stress_test.exs`.
- Done when: Exercise all eight functions, readback and remote exceptions; run required stress/matrix and final archive/package gates; execute the complete .11 corpus and all remaining scenario expansions, not only its representative cases.
- Suggested local commit: `test: prove the complete tcp software profile`.

### WMB-P06: Native Mix orchestration

- Requirements: WMB-N01–N03 and C09; protocol behavior and accepted peer fixtures remain prerequisites.
- Change surface: root aliases to unique `Mix.Tasks.Wotex.Modbus.Software.Build` and `Mix.Tasks.Wotex.Modbus.Software.Run`, test-only owned Port/process helpers, manifest/result projection.
- Acceptance: every .13 build/reuse/failure/cleanup case has an actual assertion, both runtime lanes run against native peers, and no generic Python orchestration remains necessary. Existing results retain their original command and source identities.
- Tests: `test/software/fixture_tasks_test.exs` plus the retained protocol/stress suites.
- Commit scope: validated native fixture orchestration and its tests.

## Reproducible software fixture contract

[WMB.13](../specs/WMB.13-native-build-and-software-evidence.md) is authoritative for the
Mix tasks, native source pins, manifests, deadlines, cleanup and result schemas.
The command contract is:

```sh
mix wotex.software.build --workspace /absolute/disposable/fixture-workspace
WOTEX_PATH_DEPS=1 mix wotex.software.run --workspace /absolute/disposable/fixture-workspace
```

These commands execute the checked-in Mix implementation. Passing task fixtures
do not close an unexecuted toolchain or whole-VM opening cell. Existing shell/Python harnesses are identified only by the executed
provenance they support. The native peer and protocol assertions remain the
same independent software obligations. No build or peer starts implicitly.

## Verification and commit procedure

Run focused tests while implementing a package, then run `mix check --no-retry` before its
local commit. The ordinary Hex dependency path is authoritative. For the existing
explicit sibling-development setup, `WOTEX_PATH_DEPS=1 mix check --no-retry` selects local
dependency sources; record which mode was used. Do not lower coverage, disable
warnings, waive audits or exclude newly failing code to make the gate pass.
Native changes additionally run their required native tests and dependency audit;
C/C++ adapters run ASan/UBSan in the Linux fault lane.

After each package, update the current-profile/README capability claims only for
behavior supported by the recorded assertions, and refresh [executable evidence](../provenance/executable-evidence.md)
with command, versions, vector paths/digests and result. Keep unexecuted requirements
explicit. Use the author and committer required by `CLAUDE.md`; never configure
remotes, push, tag, publish, change visibility or edit a consumer.

The final package also accepts every .11 standalone and .12 integration requirement,
then runs the full .00 C09 matrix, all .10 scenarios, .11
fixture cases and software peers, then a clean committed-source archive with the lockfile through `mix check`
and out-of-tree Hex package compilation. Confirm no Application callback or
dependency-load I/O, no missing packaged bridge assets, no downloaded SDK/build/
credential artifacts and no consumer-specific names/history. A passing coverage
number or stub adapter cannot substitute for a required protocol assertion.

## Completion checklist

- Every .11 and .12 requirement is linked to a concrete asserting test/result;
  no new target requirement is closed merely by an identifier or valid JSON.
- Every S and D requirement has its required scenario expansions and concrete
  fixture assertions passing, with current digests; each existing native helper
  also has an end-to-end behavioral assertion.
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

Physical-device validation, certification, consumer migration and publication
remain separate activities. They are not reasons to leave defined software
requirements unimplemented or to claim unexecuted software tests passed.
