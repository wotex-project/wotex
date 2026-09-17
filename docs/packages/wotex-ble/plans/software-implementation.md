# WBL software implementation sequence

This sequence defines acceptance of the native BlueZ GATT central profile.
[Current implementation evidence](../provenance/executable-evidence.md) identifies
implemented cells; [WBL.13](../specs/WBL.13-native-backend.md) owns native
build, IPC and tooling requirements. Source presence alone is not acceptance.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WBL.00 — shared software rules](../specs/WBL.00-library-contract.md).
3. Read [WBL.10 — exact target profile](../specs/WBL.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
4. Read [WBL.11 — standalone API, preservation and concrete corpus](../specs/WBL.11-standalone-client-and-preservation.md).
5. Read [primary source pins and access limits](../provenance/primary-sources.md).
6. Select the first work package below whose acceptance evidence is absent.

Read the [versioned catalogue](../specs/catalogue.yaml) and
[WBL.12 — Wotex integration](../specs/WBL.12-wotex-integration.md) before choosing
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

### WBL-P00: Own the native BlueZ Port

- Requirements: WBL-B01, WBL-B02, WBL-B03, WBL-B04; C01–C10 apply.
- Concrete cases: every WBL-B-Fxx case in `native-port-v1.json`.
- Change surface: first-party native build/host, BEAM Port and Mix/ExUnit fixture ownership.
- Test destinations: `test/wotex/ble/native_contract_test.exs`, `test/native/flow_test.cpp`, `test/software/lifecycle_stress_test.exs`.
- Done when: Implement the .13 C++17/libdbus helper and Mix native/software tasks, preserve domain APIs, run the shared production parser/credit corpus and D-Bus Agent/procedure/stream regressions under ASan/UBSan. All subsequent accepted SDK evidence identifies this exact C++ binary.
- Suggested local commit: `feat: own native ble build and bounded IPC`.

### WBL-P01: Validate peer identity and explicit value codecs

- Requirements: WBL-S01, WBL-N01, WBL-N02, WBL-N04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V01, WBL-V02.
- Change surface: new Peer and Value, Address and UUID.
- Test destinations: `test/wotex/ble/identity_value_test.exs`.
- Done when: Types/limits/byte order and forged-struct boundaries are explicit; no characteristic name or UUID guesses its application encoding.
- Suggested local commit: `feat: validate peer identity and explicit value codecs`.

- Concrete cases: WBL-F01, WBL-F02, WBL-F03, WBL-F04, WBL-F05, WBL-F09, WBL-F10.
- Standalone closure: Add the .11 named pure APIs including strict Address.from_topic/1 and the fixture runner; no malformed topic fallback.

### WBL-P02: Add persistent dbus ownership and gatt discovery

- Requirements: WBL-S01, WBL-S02, WBL-N01; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V03, WBL-V04.
- Change surface: BlueZ persistent mode, Connection and native libdbus Port.
- Test destinations: `test/wotex/ble/dbus_bridge_test.exs`, `test/native/dbus_test.cpp`.
- Done when: Own one unique bus sender, reconcile listeners/snapshot and verify live Service/Device/UUID/Flags; bound paged discovery and preserve borrowed links.
- Suggested local commit: `feat: add persistent dbus ownership and gatt discovery`.
- Standalone closure: Implement the .11 typed Characteristic pages, exact peer association and generation-bound cursor errors.

### WBL-P03: Implement explicit pairing agent decisions

- Requirements: WBL-S02; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V06.
- Change surface: Agent1 challenge/reply schema and pairing lifecycle.
- Test destinations: `test/native/agent_test.cpp`, `test/wotex/ble/pairing_test.exs`.
- Done when: Only an explicit exact-peer callback decision can accept; timeout/cancel/foreign reply reject and release Agent state without removing bonds.
- Suggested local commit: `feat: implement explicit pairing agent decisions`.

### WBL-P04: Enforce acknowledged gatt procedures and failures

- Requirements: WBL-S03, WBL-N01; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V05.
- Change surface: persistent ReadValue/WriteValue request dispatch and error mapping.
- Test destinations: `test/wotex/ble/procedure_test.exs`.
- Done when: Never fall back to write command or retry a partial write; expiry closes generation and preserves unknown mutation effect.
- Suggested local commit: `feat: enforce acknowledged gatt procedures and failures`.
- Standalone closure: Implement named read/3 and write/4 helpers with identical admission/conversion behavior to send/2.

### WBL-P05: Own notification and indication sessions

- Requirements: WBL-S04, WBL-N01, WBL-N02; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V07, WBL-V08, WBL-V09.
- Change surface: Subscription owner and persistent StartNotify/StopNotify signals.
- Test destinations: `test/wotex/ble/notification_test.exs`, `test/native/notification_test.cpp`.
- Done when: Same D-Bus sender owns start/stop; ambiguous explicit procedure fails; reports bind sender/path/generation and cleanup releases native sessions.
- Suggested local commit: `feat: own notification and indication sessions`.

- Concrete cases: WBL-F06, WBL-F07, WBL-F08.
- Standalone closure: Preserve source :bluez_value_change, including read-caused and equal changes, without inventing notification provenance.

### WBL-P06: Map gatt streams and native health precisely

- Requirements: WBL-S05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V10.
- Change surface: Transport, Mapping and health/capability reporting.
- Test destinations: `test/wotex/ble/runtime_stream_test.exs`.
- Done when: Property/Event context and mode are explicit; Paired is not misrepresented as proof of a requested security level.
- Suggested local commit: `feat: map gatt streams and native health precisely`.

### WBL-P07: Build an isolated virtual controller gatt fixture

- Requirements: WBL-S01, WBL-S02, WBL-S03, WBL-S04, WBL-N02, WBL-N03; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V03, WBL-V04, WBL-V05, WBL-V06, WBL-V07, WBL-V08, WBL-V09, WBL-V11.
- Change surface: pinned BlueZ btvirt/bluetoothd, private bus and fixture GATT server.
- Test destinations: `test/interop/bluez_test.exs`.
- Done when: Required Linux VM uses only two virtual LE controllers and asserts wire read/write/notify/indicate plus native cleanup; missing kernel support fails.
- Suggested local commit: `test: build an isolated virtual controller gatt fixture`.
- Standalone closure: Run every .11 native discovery/read/write/pair/notify/indicate workflow and assert the independent sender survives cleanup.

### WBL-P07a: Prove the Wotex consumer boundary

- Requirements: WBL-I01, WBL-I02, WBL-I03, WBL-I04, WBL-I05, WBL-I06; all previous native/profile packages are dependencies.
- Concrete cases: every `WBL-I-Fxx` case in `docs/specs/fixtures/wotex-integration-v1.json`, expanded with the I06 negative/context/stream matrix.
- Change surface: root profile/0 and profile/1, Error.class, Mapping, Transport and their public core/Runtime integration; no sibling implementation changes.
- Test destinations: `test/wotex/ble/runtime_integration_test.exs` and explicit test-only credential/client ports.
- Done when: every admitted mode constructs the exact BindingProfile, real ConsumedThing calls preserve route/value/metadata/identity, unsupported cells acquire nothing, unknown-effect mutations remain non-retryable through Runtime, and every declared stream closes through the real Runtime owner. Native-only operations remain native; test fixtures are runner-owned assertions, never adapter answers.
- Suggested local commit: `feat: integrate explicit runtime profiles and failure classes`.

### WBL-P08: Prove bluez software lifecycle and compatibility

- Requirements: WBL-S01, WBL-S02, WBL-S03, WBL-S04, WBL-S05, WBL-N01, WBL-N02, WBL-N03, WBL-N04; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WBL-V12.
- Change surface: native audit, bridge faults and full software runner.
- Test destinations: `test/software/lifecycle_stress_test.exs`.
- Done when: Run required stress/version/archive/package gates and distinguish D-Bus policy tests from virtual-controller wire evidence.
- Suggested local commit: `test: prove bluez software lifecycle and compatibility`.
- Standalone closure: Require all concrete corpus cases and the complete first-party native client workflow, with actual virtual GATT evidence.

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

The implemented command contract is:

```sh
mix wotex.software.build --workspace /absolute/disposable/fixture-workspace
mix wotex.software.run --workspace /absolute/disposable/fixture-workspace
```

[WBL.13](../specs/WBL.13-native-backend.md) defines the implemented fixture
layers, per-lane guest boots and result criteria; the retired Python guest
runner is not part of this contract.

The runner executes `mix test --include interop --include software --exclude hardware`
and all required native tests/audits from .10. Add `@tag :software` only to tests
needing this software fixture/stress setup; normal deterministic contract tests
remain in `mix check`. The explicit runner sets `WOTEX_REQUIRE_SOFTWARE=1` and
the test helper must make missing fixture configuration fail under that setting.
Label same-stack, independent-stack, malformed-peer and injected-contract evidence
separately in the results. Hardware absence is not a software test result.

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
