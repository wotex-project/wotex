# WMA software implementation sequence

This is the self-contained build handoff for the defined software profile, not
a statement that these tasks have already passed. The verified starting point
is commit `e546603`; read [current executable evidence](../provenance/executable-evidence.md)
for the tests and limitations at that baseline. Existing passing code is the
starting implementation, not something to replace with fresh scaffolding.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WMA.00 — shared software rules](../specs/WMA.00-library-contract.md).
3. Read [WMA.10 — exact target profile](../specs/WMA.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
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

### WMA-P01: Preserve typed batch paths tlv and per path status

- Requirements: WMA-S01, WMA-S03; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V01, WMA-V02, WMA-V05.
- Change surface: new ReadPath, Address, TLV, descriptor-based value/result conversion.
- Test destinations: `test/wotex/matter/path_value_test.exs`, `test/native/test_values.py`.
- Done when: Concrete compatibility stays intact; read-only wildcards, unknown tags, explicit descriptor allowlist and deterministic per-path results are bounded.
- Suggested local commit: `feat: preserve typed batch paths tlv and per path status`.

### WMA-P02: Implement durable exclusive controller storage

- Requirements: WMA-S02; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V03.
- Change surface: new PersistentStorage implementation and explicit open/create schema.
- Test destinations: `test/native/test_storage.py`.
- Done when: Correct pinned storage-object API, fatal Commit failures, exclusive lock, atomic/fsynced state and crash-safe identity retention are proved.
- Suggested local commit: `feat: implement durable exclusive controller storage`.

### WMA-P03: Own a persistent first party sdk controller

- Requirements: WMA-S02; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V04.
- Change surface: SDK persistent mode, bridge event loop and concrete CA/controller factory.
- Test destinations: `test/wotex/matter/persistent_bridge_test.exs`, `test/native/test_controller.py`.
- Done when: Explicit PAA/fabric/node configuration produces a controller; partial start/EOF/death unwind all SDK objects and storage locks.
- Suggested local commit: `feat: own a persistent first party sdk controller`.

### WMA-P04: Complete timed interactions and event reads

- Requirements: WMA-S03; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V05, WMA-V06.
- Change surface: SDK read/write/SendCommand/ReadEvent translation.
- Test destinations: `test/native/test_interactions.py`.
- Done when: Timed/DataVersion/partial-status semantics are exact, native event identity is preserved and mutation timeouts never replay.
- Suggested local commit: `feat: complete timed interactions and event reads`.

### WMA-P05: Deliver attribute and event subscriptions

- Requirements: WMA-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V07, WMA-V09.
- Change surface: Subscription owner and SDK report callbacks.
- Test destinations: `test/wotex/matter/subscription_test.exs`, `test/native/test_subscription.py`.
- Done when: Initial snapshot/callback race, interval revisions, paths and generations are validated; cancel/death removes native callbacks and transactions.
- Suggested local commit: `feat: deliver attribute and event subscriptions`.

### WMA-P06: Bound explicit subscription recovery

- Requirements: WMA-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V08, WMA-V09.
- Change surface: resubscription callbacks, budgets and stream statuses.
- Test destinations: `test/wotex/matter/subscription_recovery_test.exs`.
- Done when: Default loss is terminal; opted-in recovery emits continuity loss, obeys five-attempt/60-second bounds and cannot replay mutations.
- Suggested local commit: `feat: bound explicit subscription recovery`.

### WMA-P07: Commission on network with verified attestation

- Requirements: WMA-S05; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V10.
- Change surface: CommissionOnNetwork, OpenCommissioningWindow and typed ACL operations.
- Test destinations: `test/native/test_commissioning.py`, `test/interop/commissioning_test.exs`.
- Done when: Explicit new-node/window inputs, final SDK outcome, PAA/attestation failure and denied operational ACL are exercised without bypass flags.
- Suggested local commit: `feat: commission on network with verified attestation`.

### WMA-P08: Map matter property action and event results

- Requirements: WMA-S06; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V11.
- Change surface: Mapping, Transport and explicit read health probe.
- Test destinations: `test/wotex/matter/runtime_stream_test.exs`.
- Done when: Each Interaction Affordance maps to its real service and retains status/version/event metadata and original cancellation route.
- Suggested local commit: `feat: map matter property action and event results`.

### WMA-P09: Prove the controller against pinned sdk example peers

- Requirements: WMA-S01, WMA-S02, WMA-S03, WMA-S04, WMA-S05, WMA-S06; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMA-V12, WMA-V13.
- Change surface: Linux no-BLE SDK controller/all-clusters/lighting fixture and native audit.
- Test destinations: `test/interop/sdk_test.exs`, `test/software/lifecycle_stress_test.exs`.
- Done when: Actual on-network commissioning, CASE, ACL denial, reports, cancellation, persistent restart and required stress/matrix/archive gates all pass.
- Suggested local commit: `test: prove the controller against pinned sdk example peers`.

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
