# WMB software implementation sequence

This is the self-contained build handoff for the defined software profile, not
a statement that these tasks have already passed. The verified starting point
is commit `0c2a7f4`; read [current executable evidence](../provenance/executable-evidence.md)
for the tests and limitations at that baseline. Existing passing code is the
starting implementation, not something to replace with fresh scaffolding.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WMB.00 — shared software rules](../specs/WMB.00-library-contract.md).
3. Read [WMB.10 — exact target profile](../specs/WMB.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
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

### WMB-P01: Harden public command and conversion boundaries

- Requirements: WMB-S01; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMB-V01, WMB-V02, WMB-V06.
- Change surface: Address, Command, Value and root callbacks.
- Test destinations: `test/wotex/modbus/boundary_test.exs`.
- Done when: Revalidate forged structs; table-test every quantity, width, order and null/error boundary without opening a socket.
- Suggested local commit: `feat: harden public command and conversion boundaries`.

### WMB-P02: Enforce strict response and stream correlation

- Requirements: WMB-S02; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMB-V03, WMB-V04, WMB-V05.
- Change surface: Codec and Connection response handling.
- Test destinations: `test/wotex/modbus/stream_fault_test.exs`.
- Done when: Every ADU split and malformed echo has an exact result; framing/correlation failure closes the session before any later request.
- Suggested local commit: `feat: enforce strict response and stream correlation`.

### WMB-P03: Bound connection admission and owner cleanup

- Requirements: WMB-S03; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMB-V07, WMB-V08.
- Change surface: Connection request queue, caller/owner monitors and deadline propagation.
- Test destinations: `test/wotex/modbus/lifecycle_test.exs`.
- Done when: A 65th admitted operation returns busy; expired/dead queued writes send nothing; owner death is handled during receive; cleanup meets C03.
- Suggested local commit: `feat: bound connection admission and owner cleanup`.

### WMB-P04: Add explicit health probes and precise capabilities

- Requirements: WMB-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMB-V09, WMB-V10.
- Change surface: Modbus.health_check/2, Mapping, Transport and capabilities.
- Test destinations: `test/wotex/modbus/compatibility_test.exs`.
- Done when: Preserve existing valid helper results, document register-zero probe, reject write probes/security mismatch and retain Form extensions.
- Suggested local commit: `feat: add explicit health probes and precise capabilities`.

### WMB-P05: Prove the complete tcp software profile

- Requirements: WMB-S01, WMB-S02, WMB-S03, WMB-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WMB-V11, WMB-V12.
- Change surface: existing libmodbus fixture plus required software runner.
- Test destinations: `test/interop/libmodbus_test.exs`, `test/software/lifecycle_stress_test.exs`.
- Done when: Exercise all eight functions, readback and remote exceptions; run required stress/matrix and final archive/package gates.
- Suggested local commit: `test: prove the complete tcp software profile`.

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
