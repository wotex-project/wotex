# WCO software implementation sequence

This is the self-contained build handoff for the defined software profile, not
a statement that these tasks have already passed. The verified starting point
is commit `1ff4320`; read [current executable evidence](../provenance/executable-evidence.md)
for the tests and limitations at that baseline. Existing passing code is the
starting implementation, not something to replace with fresh scaffolding.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WCO.00 — shared software rules](../specs/WCO.00-library-contract.md).
3. Read [WCO.10 — exact target profile](../specs/WCO.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
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

### WCO-P01: Make datagram exchanges event driven and bounded

- Requirements: WCO-S01; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V01, WCO-V02, WCO-V15.
- Change surface: Connection, explicit Datagram behaviour and UDP adapter.
- Test destinations: `test/wotex/coap/exchange_lifecycle_test.exs`.
- Done when: Preserve committed blockwise transfer behavior while owner/caller monitors, admission, retransmission and duplicate-response ACKs work during I/O.
- Suggested local commit: `feat: make datagram exchanges event driven and bounded`.

### WCO-P02: Support blockwise continuation from an initial report

- Requirements: WCO-S02; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V03, WCO-V04, WCO-V10.
- Change surface: Blockwise pure state and Connection transfer dispatch.
- Test destinations: `test/wotex/coap/blockwise_test.exs`.
- Done when: Add validated first-Block2 continuation without restarting uploads; preserve ETag/status/format/limits and expose distinct body/datagram capabilities.
- Suggested local commit: `feat: support blockwise continuation from an initial report`.

### WCO-P03: Implement observe registration and report freshness

- Requirements: WCO-S03; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V05, WCO-V06, WCO-V07.
- Change surface: new Subscription/Observation owner and existing Observe helper.
- Test destinations: `test/wotex/coap/observation_test.exs`.
- Done when: Return a handle only after successful Observe registration, ACK confirmed reports, apply exact 24-bit freshness and retain complete initial body.
- Suggested local commit: `feat: implement observe registration and report freshness`.

### WCO-P04: Complete observe renewal cancellation and blockwise delivery

- Requirements: WCO-S02, WCO-S03; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V08, WCO-V09, WCO-V10, WCO-V15.
- Change surface: Observation timers, cancellation and Blockwise integration.
- Test destinations: `test/wotex/coap/observation_lifecycle_test.exs`.
- Done when: Use original route/token, bounded refresh and latest-Property coalescing; fail incomplete reports; no late delivery after cancel/receiver death.
- Suggested local commit: `feat: complete observe renewal cancellation and blockwise delivery`.

### WCO-P05: Map streams and parse resource discovery

- Requirements: WCO-S04; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V11, WCO-V15.
- Change surface: Mapping, Transport and new LinkFormat.
- Test destinations: `test/wotex/coap/link_format_test.exs`, `test/wotex/coap/runtime_stream_test.exs`.
- Done when: RFC 6690 quoted/repeated/unknown fields parse with limits; Property/Event contexts and Runtime terminal statuses are correct.
- Suggested local commit: `feat: map streams and parse resource discovery`.

### WCO-P06: Add explicit dtls psk and pki sessions

- Requirements: WCO-S05; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V12, WCO-V15.
- Change surface: new Security value, OTP ssl Datagram adapter and credential mapping.
- Test destinations: `test/wotex/coap/dtls_test.exs`, `test/interop/dtls_test.exs`.
- Done when: Both pinned cipher profiles work against libcoap; key/certificate/revocation failures and replay never fall back to UDP.
- Suggested local commit: `feat: add explicit dtls psk and pki sessions`.

### WCO-P07: Define and implement the optional oscore bridge boundary

- Requirements: WCO-S06; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V13, WCO-V15.
- Change surface: caller-selected C bridge, versioned framing, explicit libcoap adapter.
- Test destinations: `test/wotex/coap/oscore_bridge_test.exs`, `test/native/oscore_vectors.c`.
- Done when: Map request/Observe/blockwise through one libcoap exchange engine; RFC 8613 known-answer and authenticated-failure vectors pass.
- Suggested local commit: `feat: define and implement the optional oscore bridge boundary`.

### WCO-P08: Enforce durable oscore context and replay rules

- Requirements: WCO-S06; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V13, WCO-V14.
- Change surface: exclusive context registry and libcoap sequence-save callback.
- Test destinations: `test/native/oscore_store_test.c`, `test/interop/oscore_restart_test.exs`.
- Done when: Durable pre-use state, sequence bounds and single-process-generation context policy prevent unsafe reopen, nonce reuse and replay acceptance.
- Suggested local commit: `feat: enforce durable oscore context and replay rules`.

### WCO-P09: Prove all coap software transport profiles

- Requirements: WCO-S01, WCO-S02, WCO-S03, WCO-S04, WCO-S05, WCO-S06; shared C01–C10 apply wherever relevant.
- Acceptance vectors: WCO-V01, WCO-V02, WCO-V03, WCO-V04, WCO-V05, WCO-V06, WCO-V07, WCO-V08, WCO-V09, WCO-V10, WCO-V11, WCO-V12, WCO-V13, WCO-V14, WCO-V15.
- Change surface: libcoap software fixtures and stress runner.
- Test destinations: `test/interop/libcoap_test.exs`, `test/software/lifecycle_stress_test.exs`.
- Done when: Plain UDP/Observe/blockwise, DTLS and explicitly labelled same-stack OSCORE lanes run; all required stress/matrix/archive checks pass.
- Suggested local commit: `test: prove all coap software transport profiles`.

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
