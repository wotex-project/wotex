# WOP software implementation sequence

This is the self-contained build handoff for the defined software profile, not
a statement that these tasks have already passed. The verified starting point
is commit `35a9137`; read [current executable evidence](../provenance/executable-evidence.md)
for the tests and limitations at that baseline. Existing passing code is the
starting implementation, not something to replace with fresh scaffolding.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WOP.00 — shared software rules](../specs/WOP.00-library-contract.md).
3. Read [WOP.10 — exact target profile](../specs/WOP.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
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

### WOP-P01: Preserve typed arrays data values and namespace identity

- Requirements: WOP-S01; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V01, WOP-V02, WOP-V03, WOP-V04.
- Change surface: Address, Binary, Frame, Value and typed bridge schemas.
- Test destinations: `test/wotex/opcua/typed_values_test.exs`.
- Done when: Define all new envelope fields/types in code; roundtrip null/empty/arrays/opaque values, enforce the SDK DateTime precision/range policy and retain status/timestamp metadata with bounded allocation.
- Suggested local commit: `feat: preserve typed arrays data values and namespace identity`.

### WOP-P02: Add persistent secure sdk session ownership

- Requirements: WOP-S02; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V05, WOP-V06.
- Change surface: Asyncua persistent mode, Connection owner and Python bridge loop.
- Test destinations: `test/wotex/opcua/persistent_bridge_test.exs`, `test/native/test_session.py`.
- Done when: Versioned open requires activated Session and namespace map; EOF/partial-open/timeout cleanup works and auto reconnect stays disabled.
- Suggested local commit: `feat: add persistent secure sdk session ownership`.

### WOP-P03: Add explicit security policies and user tokens

- Requirements: WOP-S03; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V07, WOP-V08.
- Change surface: Security configuration and Python trust/token validation.
- Test destinations: `test/native/test_security.py`, `test/interop/asyncua_test.exs`.
- Done when: All three allowed policies and three explicit token modes work; exact pin/SAN/URI/CRL validation and no downgrade remain enforced.
- Suggested local commit: `feat: add explicit security policies and user tokens`.

### WOP-P04: Create monitored items and preserve report metadata

- Requirements: WOP-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V10, WOP-V11.
- Change surface: new Subscription owner, asyncua CreateSubscription/MonitoredItem adapter.
- Test destinations: `test/wotex/opcua/subscription_test.exs`, `test/native/test_subscription.py`.
- Done when: Validate server revisions/item status, expose DataValue and overflow metadata, suppress protocol duplicates and fail unrecoverable sequence gaps.
- Suggested local commit: `feat: create monitored items and preserve report metadata`.

### WOP-P05: Close subscriptions on receiver or session loss

- Requirements: WOP-S02, WOP-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V06, WOP-V12, WOP-V15.
- Change surface: Subscription, bridge task cancellation and Session shutdown.
- Test destinations: `test/wotex/opcua/subscription_lifecycle_test.exs`.
- Done when: Cancel deletes server resources or closes Session; terminal once, no silent reconnect and no stale native callbacks.
- Suggested local commit: `feat: close subscriptions on receiver or session loss`.

### WOP-P06: Map persistent property observations and read probes

- Requirements: WOP-S05; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V13.
- Change surface: Mapping, Transport and OPCUA.health_check/2.
- Test destinations: `test/wotex/opcua/runtime_stream_test.exs`.
- Done when: Maintain one-shot successful return shapes; select persistent mode explicitly for Property observation and reject unsupported Event filters.
- Suggested local commit: `feat: map persistent property observations and read probes`.

### WOP-P07: Add an independent encrypted open62541 peer

- Requirements: WOP-S03, WOP-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V07, WOP-V08, WOP-V09, WOP-V14.
- Change surface: new pinned OpenSSL open62541 fixture with typed method/users/variables.
- Test destinations: `test/interop/open62541_test.exs`, `test/interop/security_fault_test.exs`.
- Done when: All secure policies/tokens, read/write/Call/monitoring, denial and replay/correlation failures have actual peer evidence and server resource counters.
- Suggested local commit: `test: add an independent encrypted open62541 peer`.

### WOP-P08: Prove the complete secure software profile

- Requirements: WOP-S01, WOP-S02, WOP-S03, WOP-S04, WOP-S05; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WOP-V15.
- Change surface: native audit, concurrency/stress and reproducible fixture runner.
- Test destinations: `test/software/lifecycle_stress_test.exs`.
- Done when: Complete version matrix, native cleanup, current vector hashes, clean-source gate and package assets; label same-stack evidence accurately.
- Suggested local commit: `test: prove the complete secure software profile`.

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
