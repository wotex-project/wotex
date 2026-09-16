# WCO software implementation sequence

The BEAM UDP exchange, complete blockwise transfer, owned Observe, discovery,
Runtime UDP streams, OTP PSK/PKI DTLS native/Runtime operations and the injected
native OSCORE Runtime boundary are implemented. The native same-binary lifecycle
worker now owns durable open, bounded upload state and close. Its libcoap engine
executes unary requests and protected Observe registration, inline or streamed
reports, report credit, Max-Age renewal, stale cleanup and cancellation. The
production path also executes renewal failures and bounded Property/Event
overload. Native serial admission, protected wraparound, the in-flight
renewal/cancel deadline path and established-observation owner-EOF cleanup
execute. The protected worker also progresses under an actually full owner
output pipe and tears down within C03; BEAM Port-mailbox sampling remains.
Pending-registration owner loss, authenticated duplicate/stale injection,
successful race confirmation and intervening-response ordering, the independent
secure matrix, software-run orchestration and complete software closure remain
targets. Native and software build orchestration is implemented with bounded,
manifest-bound workspaces and native-vector probes.
[Executable evidence](../provenance/executable-evidence.md) identifies each
executed cohort and its limits. The ordered packages define acceptance.

## Read before changing code

1. Read `CLAUDE.md` and matching repository rules/skills.
2. Read [WCO.00 — shared software rules](../specs/WCO.00-library-contract.md).
3. Read [WCO.10 — exact target profile](../specs/WCO.10-software-contract.md), then the existing protocol/current-profile specifications linked there.
4. Read [WCO.11 — standalone APIs, preservation and exact fixtures](../specs/WCO.11-standalone-client-and-preservation.md).
5. Read [primary source pins and access limits](../provenance/primary-sources.md).
6. Select the first work package below whose acceptance evidence is absent.

Read the [versioned catalogue](../specs/catalogue.yaml) and
[WCO.12 — Wotex integration](../specs/WCO.12-wotex-integration.md) before choosing
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

### WCO-P01: Make datagram exchanges event driven and bounded

- Requirements: WCO-S01, WCO-D01, WCO-D02, WCO-D05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V01, WCO-V02, WCO-V15.
- Change surface: Connection, explicit Datagram behaviour and UDP adapter; root method wrappers/message admission and fixed pure fixture adapters.
- Test destinations: `test/wotex/coap/exchange_lifecycle_test.exs`.
- Done when: Preserve committed blockwise transfer behavior while owner/caller monitors, admission, retransmission and duplicate-response ACKs work during I/O; GET/POST/PUT/DELETE helpers preserve complete-body results; exact percent/query/Accept and negative input cases execute through public APIs.
- Suggested local commit: `feat: make datagram exchanges event driven and bounded`.

### WCO-P02: Support blockwise continuation from an initial report

- Requirements: WCO-S02, WCO-D01; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V03, WCO-V04, WCO-V10.
- Change surface: Blockwise pure state and Connection transfer dispatch.
- Test destinations: `test/wotex/coap/blockwise_test.exs`.
- Done when: Add validated first-Block2 continuation without restarting uploads; preserve ETag/status/format/limits and expose distinct body/datagram capabilities.
- Suggested local commit: `feat: support blockwise continuation from an initial report`.

### WCO-P03: Implement observe registration and report freshness

- Requirements: WCO-S03, WCO-D04, WCO-D05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V05, WCO-V06, WCO-V07.
- Change surface: new Subscription/Observation owner and existing Observe helper.
- Test destinations: `test/wotex/coap/observation_test.exs`.
- Done when: Return a handle only after successful Observe registration, ACK confirmed reports, apply exact 24-bit freshness and retain complete initial body.
- Suggested local commit: `feat: implement observe registration and report freshness`.

### WCO-P04: Complete observe renewal cancellation and blockwise delivery

- Requirements: WCO-S02, WCO-S03, WCO-D04, WCO-D05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V08, WCO-V09, WCO-V10, WCO-V15.
- Change surface: Observation timers, cancellation and Blockwise integration.
- Test destinations: `test/wotex/coap/observation_lifecycle_test.exs`.
- Done when: Use original route/token, bounded refresh and latest-Property coalescing; fail incomplete reports; no late delivery after cancel/receiver death; execute the byte-level cancellation-race trace, including repeated ACKs and final owned resource counts.
- Suggested local commit: `feat: complete observe renewal cancellation and blockwise delivery`.

### WCO-P05: Map streams and parse resource discovery

- Requirements: WCO-S04, WCO-D01, WCO-D03, WCO-D04, WCO-D05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V11, WCO-V15.
- Change surface: Mapping, Transport and new LinkFormat.
- Test destinations: `test/wotex/coap/link_format_test.exs`, `test/wotex/coap/runtime_stream_test.exs`.
- Done when: Actual discovery GET/Accept/status/content-format/body limits and RFC 6690 grammar/multiplicity pass the .11 corpus; native discover/get/observe/cancel workflow and Property/Event Runtime contexts have actual assertions. Correct discovery capability claims to match evidence.
- Suggested local commit: `feat: map streams and parse resource discovery`.

### WCO-P06: Add explicit dtls psk and pki sessions

- Requirements: WCO-S05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V12, WCO-V15.
- Change surface: new Security value, OTP ssl Datagram adapter and credential mapping.
- Test destinations: `test/wotex/coap/dtls_test.exs`, `test/interop/dtls_test.exs`.
- Done when: Both pinned cipher profiles work against libcoap; key/certificate/revocation failures and replay never fall back to UDP.
- Suggested local commit: `feat: add explicit dtls psk and pki sessions`.

### WCO-P07: Define and implement the optional oscore bridge boundary

- Requirements: WCO-S06; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V13, WCO-V15.
- Change surface: caller-selected C bridge, versioned framing, explicit libcoap adapter.
- Test destinations: `test/wotex/coap/oscore_bridge_test.exs`, `test/native/oscore_vectors.c`.
- Done when: Map request/Observe/blockwise through one libcoap exchange engine; RFC 8613 known-answer and authenticated-failure vectors pass.
- Suggested local commit: `feat: define and implement the optional oscore bridge boundary`.

### WCO-P08: Enforce durable oscore context and replay rules

- Requirements: WCO-S06; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V13, WCO-V14.
- Change surface: exclusive context registry and libcoap sequence-save callback.
- Test destinations: `test/native/oscore_store_test.c`, `test/interop/oscore_restart_test.exs`.
- Done when: Durable pre-use state, sequence bounds and single-process-generation context policy prevent unsafe reopen, nonce reuse and replay acceptance.
- Suggested local commit: `feat: enforce durable oscore context and replay rules`.

### WCO-P08a: Prove the Wotex consumer boundary

- Requirements: WCO-I01, WCO-I02, WCO-I03, WCO-I04, WCO-I05, WCO-I06; all previous native/profile packages are dependencies.
- Concrete cases: every `WCO-I-Fxx` case in `docs/specs/fixtures/wotex-integration-v1.json`, expanded with the I06 negative/context/stream matrix.
- Change surface: root profile/0 and profile/1, Error.class, Mapping, Transport and their public core/Runtime integration; no sibling implementation changes.
- Test destinations: `test/wotex/coap/runtime_integration_test.exs` and explicit test-only credential/client ports.
- Done when: every admitted mode constructs the exact BindingProfile, real ConsumedThing calls preserve route/value/metadata/identity, unsupported cells acquire nothing, unknown-effect mutations remain non-retryable through Runtime, and every declared stream closes through the real Runtime owner. Native-only operations remain native; test fixtures are runner-owned assertions, never adapter answers.
- Suggested local commit: `feat: integrate explicit runtime profiles and failure classes`.

### WCO-P08b: Native Mix orchestration

- Requirements: WCO-N01–N05 and C09; protocol behavior and accepted peer fixtures remain prerequisites.
- Change surface: unique `Mix.Tasks.Wotex.Coap.Software.Build` and `Mix.Tasks.Wotex.Coap.Software.Run` with root-project aliases `wotex.software.build` and `wotex.software.run`, test-only owned Port/process helpers, manifest/result projection. The native build uses `Mix.Tasks.Wotex.Coap.Native.Build` behind the `wotex.native.build` alias. Multiple protocol dependencies must not define duplicate task modules.
- Acceptance: every .13 build/reuse/failure/cleanup case has an actual assertion, both runtime lanes run against native peers, and no generic Python orchestration remains necessary. Existing results retain their original command and source identities.
- Tests: `test/software/fixture_tasks_test.exs` plus the retained protocol/stress suites.
- Commit scope: validated native fixture orchestration and its tests.

### WCO-P09: Prove all coap software transport profiles

- Requirements: WCO-S01, WCO-S02, WCO-S03, WCO-S04, WCO-S05, WCO-S06, WCO-D01–D05; shared C01–C10 apply wherever relevant.
- Acceptance scenarios: WCO-V01, WCO-V02, WCO-V03, WCO-V04, WCO-V05, WCO-V06, WCO-V07, WCO-V08, WCO-V09, WCO-V10, WCO-V11, WCO-V12, WCO-V13, WCO-V14, WCO-V15.
- Change surface: libcoap software fixtures and stress runner.
- Test destinations: `test/interop/libcoap_test.exs`, `test/software/lifecycle_stress_test.exs`.
- Done when: Plain UDP/Observe/blockwise, DTLS and explicitly labelled same-stack OSCORE lanes run; all required stress/matrix/archive checks pass; all .11 cases and remaining scenario expansions execute, with pure/injected/independent lanes labelled separately.
- Suggested local commit: `test: prove all coap software transport profiles`.

## Reproducible software fixture contract

[WCO.13](../specs/WCO.13-native-build-and-software-evidence.md) is authoritative
for the implemented build tasks, planned software-run task, native source pins,
manifests, deadlines, cleanup and result schemas.
The command contract is:

```sh
mix wotex.software.build --workspace /absolute/disposable/fixture-workspace
WOTEX_PATH_DEPS=1 mix wotex.software.run --workspace /absolute/disposable/fixture-workspace
```

The build command and its task tests pass on macOS arm64; the run command remains
a target interface until its implementation and task tests pass. Existing
shell/Python harnesses are identified only by the executed provenance they
support. The native peer and protocol assertions remain the same independent
software obligations. No build or peer starts implicitly.

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
