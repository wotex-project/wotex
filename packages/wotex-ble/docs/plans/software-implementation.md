# WBL software implementation sequence

This is the self-contained build handoff for the defined software profile, not
a statement that these tasks have already passed. The verified starting point
is commit `cb56121`; read [current executable evidence](../provenance/executable-evidence.md)
for the tests and limitations at that baseline. Existing passing code is the
starting implementation, not something to replace with fresh scaffolding.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WBL.00 — shared software rules](../specs/WBL.00-library-contract.md).
3. Read [WBL.10 — exact target profile](../specs/WBL.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
4. Read [primary source pins and access limits](../provenance/primary-sources.md).
5. Select the first work package below whose acceptance evidence is absent.

The numbered sequence is dependency order: each package depends on all preceding
packages. Each is one bounded behavior plus its tests/documentation. A large
package may be split into consecutive local commits along its stated sub-behaviors;
never commit knowingly failing tests. Do not reimplement a satisfied requirement
merely to produce a commit. Every proposed module, API and test path below is a
target addition unless it already exists; no placeholder file implies completion.

For each requirement, record its ID in an ExUnit/native test name or a fixture
manifest. Vectors specify expected outcomes in .10. The implementation chooses
ordinary internal function names and data structures, while the public behavior,
state transitions, limits, failure policy and transport choices are fixed there.
If an upstream API cannot meet a requirement, add the smallest adapter needed
or document a precise source-backed contract correction with regression evidence;
do not silently skip, simulate or weaken the requirement.

## Ordered work packages

### WBL-P01: Validate peer identity and explicit value codecs

- Requirements: WBL-S01; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V01, WBL-V02.
- Change surface: new Peer and Value, Address and UUID.
- Test destinations: `test/wotex/ble/identity_value_test.exs`.
- Done when: Types/limits/byte order and forged-struct boundaries are explicit; no characteristic name or UUID guesses its application encoding.
- Suggested local commit: `feat: validate peer identity and explicit value codecs`.

### WBL-P02: Add persistent dbus ownership and gatt discovery

- Requirements: WBL-S01, WBL-S02; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V03, WBL-V04.
- Change surface: BlueZ persistent mode, Connection and dbus-next bridge.
- Test destinations: `test/wotex/ble/dbus_bridge_test.exs`, `test/native/test_bluez.py`.
- Done when: Own one unique bus sender, reconcile listeners/snapshot and verify live Service/Device/UUID/Flags; bound paged discovery and preserve borrowed links.
- Suggested local commit: `feat: add persistent dbus ownership and gatt discovery`.

### WBL-P03: Implement explicit pairing agent decisions

- Requirements: WBL-S02; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V06.
- Change surface: Agent1 challenge/reply schema and pairing lifecycle.
- Test destinations: `test/native/test_agent.py`, `test/wotex/ble/pairing_test.exs`.
- Done when: Only an explicit exact-peer callback decision can accept; timeout/cancel/foreign reply reject and release Agent state without removing bonds.
- Suggested local commit: `feat: implement explicit pairing agent decisions`.

### WBL-P04: Enforce acknowledged gatt procedures and failures

- Requirements: WBL-S03; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V05.
- Change surface: persistent ReadValue/WriteValue request dispatch and error mapping.
- Test destinations: `test/wotex/ble/procedure_test.exs`.
- Done when: Never fall back to write command or retry a partial write; expiry closes generation and preserves unknown mutation effect.
- Suggested local commit: `feat: enforce acknowledged gatt procedures and failures`.

### WBL-P05: Own notification and indication sessions

- Requirements: WBL-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V07, WBL-V08, WBL-V09.
- Change surface: Subscription owner and persistent StartNotify/StopNotify signals.
- Test destinations: `test/wotex/ble/notification_test.exs`, `test/native/test_notify.py`.
- Done when: Same D-Bus sender owns start/stop; ambiguous explicit procedure fails; reports bind sender/path/generation and cleanup releases native sessions.
- Suggested local commit: `feat: own notification and indication sessions`.

### WBL-P06: Map gatt streams and native health precisely

- Requirements: WBL-S05; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V10.
- Change surface: Transport, Mapping and health/capability reporting.
- Test destinations: `test/wotex/ble/runtime_stream_test.exs`.
- Done when: Property/Event context and mode are explicit; Paired is not misrepresented as proof of a requested security level.
- Suggested local commit: `feat: map gatt streams and native health precisely`.

### WBL-P07: Build an isolated virtual controller gatt fixture

- Requirements: WBL-S01, WBL-S02, WBL-S03, WBL-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V03, WBL-V04, WBL-V05, WBL-V06, WBL-V07, WBL-V08, WBL-V09, WBL-V11.
- Change surface: pinned BlueZ btvirt/bluetoothd, private bus and fixture GATT server.
- Test destinations: `test/interop/bluez_test.exs`.
- Done when: Required Linux VM uses only two virtual LE controllers and asserts wire read/write/notify/indicate plus native cleanup; missing kernel support fails.
- Suggested local commit: `test: build an isolated virtual controller gatt fixture`.

### WBL-P08: Prove bluez software lifecycle and compatibility

- Requirements: WBL-S01, WBL-S02, WBL-S03, WBL-S04, WBL-S05; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WBL-V12.
- Change surface: native audit, bridge faults and full software runner.
- Test destinations: `test/software/lifecycle_stress_test.exs`.
- Done when: Run required stress/version/archive/package gates and distinguish D-Bus policy tests from virtual-controller wire evidence.
- Suggested local commit: `test: prove bluez software lifecycle and compatibility`.

## Reproducible software fixture contract

Add or extend `test/interop/build_software.sh` and `test/interop/run_software.sh`
as explicit maintainer-invoked entry points. They take exactly one absolute
workspace argument. Build requires a disposable empty workspace or a matching
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

Use this command contract once the runner is implemented:

```sh
./test/interop/build_software.sh /absolute/disposable/fixture-workspace
./test/interop/run_software.sh /absolute/disposable/fixture-workspace
```

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
behavior that now passed, and refresh [executable evidence](../provenance/executable-evidence.md)
with command, versions, vector paths/digests and result. Keep unexecuted requirements
explicit. Use the author and committer required by `CLAUDE.md`; never configure
remotes, push, tag, publish, change visibility or edit a consumer.

The final package also runs the full .00 C09 matrix, all .10 vectors and software
peers, then a clean committed-source archive with the lockfile through `mix check`
and out-of-tree Hex package compilation. Confirm no Application callback or
dependency-load I/O, no missing packaged bridge assets, no downloaded SDK/build/
credential artifacts and no consumer-specific names/history. A passing coverage
number or stub adapter cannot substitute for a required protocol assertion.

## Completion checklist

- Every S requirement has its listed V assertions passing, with current digests.
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
