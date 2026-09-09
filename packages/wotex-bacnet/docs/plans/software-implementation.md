# WBA BEAM client software implementation sequence

The production architecture is Elixir/OTP with pinned BACstack codecs and an
explicitly owned or borrowed BACnet/IP stack. Independent native C peers belong
to the software fixture. No Python process, C executable or NIF supplies the
production client. WBA.02 inventories the implemented profile; the
[executed evidence](../provenance/executable-evidence.md) identifies the tested
source/cohorts. This sequence states acceptance obligations, not release status.

Read CLAUDE, matching rules/skills, WBA.00/.10/.11/.12, the source register and
catalogue before selecting work. Existing asserting implementation remains the
regression boundary. Do not reimplement a satisfied cell to create a commit.
Package order below follows dependencies. A package may contain several logical
commits, each with focused tests and a passing complete local gate.

## Ordered packages and implementation boundary

| Package | Required behavior | Existing local evidence | Remaining acceptance |
| --- | --- | --- | --- |
| WBA-P01 | S01/S02; V01–V04: typed values, original CharacterString identity, exact ACK/error classification, segmentation limits | service_boundary_test.exs, character_string_test.exs | Retain full malformed/segmentation regression; execute it in final exact-source cohort |
| WBA-P02 | S03; V05/V14: reverse acquisition cleanup, 64-operation admission, final caller/deadline check, borrowed stack retention | stack_lifecycle_test.exs, stack_cov_test.exs, invoke_ids_test.exs | S03a ingress has IG01–IG06 local bindings; retain these in the final supported software cohort |
| WBA-P03 | S04; V06–V08: typed object/Property COV, initiator/selector correlation, exact confirmed receipt ACK and early report buffering | cov_test.exs, cov_boundary_test.exs, stack_cov_test.exs, native_subscription_test.exs; independent object COV in CP03/CP04 and Property increments/flags/capacity/selection in CP11–CP16 | Retain the combined independent COV workflow in the final P06 cohorts |
| WBA-P04 | S04; V09–V11: finite leases, renewal, encoded cancellation, receiver death, overflow and terminal-once cleanup | cov_lifecycle_test.exs, cov_cache_test.exs, native_subscription_test.exs; independent object renewal/lost-ACK/expiry counters in CP05–CP09 and Property cases CP14/CP18–CP21 | Independent 100 receiver-death cycles and final P06 cohorts |
| WBA-P05 | S05; V12: Runtime Property COV and explicit read probe | runtime_stream_test.exs, runtime_frame_test.exs, runtime_integration_test.exs; CP17 executes public Runtime observation and original-association stop against the C peer | Re-run final-owner pending-open/worker-handoff boundary through public Runtime; verified ingress admission is exercised by ingress_lifecycle_test.exs |
| WBA-P05a | N01–N05: native helpers, bounded Who-Is/I-Am, sequential 1..64 Property reads | F01–F11 corpus bindings listed in WBA-N05; standalone_contract_test.exs, discovery_lifecycle_test.exs; independent discovery/batch/write/readback/release in CP02 | Retain helpers in the final combined workflow in P06 |
| WBA-P05b | I01–I06: exact profiles, route/value/error/Retry and consumer ownership | runtime_integration_test.exs binds I-F01; error_class_test.exs binds each I-F02–I-F07 through native Error, Runtime cause and Retry; runtime_stream_test.exs exercises public observations | Retain exact corpus projections and all I06 security/media/context/stream assertions in the final software and archive cohorts |
| WBA-P06 | S01–S05/S03a/N01–N05/I01–I06/C09; V13/V14: bounded owned UDP ingress and full independent software acceptance | cstack_test.exs and lifecycle_stress_test.exs cover read/write, 1000 sequential reads, 32 concurrent reads and 100 stack cycles; cstack_cov_test.exs and cstack_property_test.exs cover CP02–CP21 discovery, batch, release, object/Property COV and loss controls | Complete Mix tooling, receiver-death stress and final cohorts; the implemented cells do not accept the full profile |

Test filenames without a directory are under `test/wotex/bacnet/`; independent
peer tests are under `test/interop/` and stress tests under `test/software/`.
An existing test path is an implementation inventory, not a current pass result
for every requirement family. Evidence includes its exact source and corpus SHA.

## WBA-P06 implementation order

1. S03a uses BACstack's public TransportBehaviour and reviewed pinned packet
   codecs. IngressTransport, StackOwner and StackClient preserve receipt identity
   and grant credits only after consumption. Local tests cover starvation, socket
   loss, saturated counters and verified borrowed receive policy. Retain these
   assertions in the final supported cohort. Tests at `test/wotex/bacnet/ingress_lifecycle_test.exs` bind every
   [ingress-v1.json](../specs/fixtures/ingress-v1.json) trace and sustained software-UDP observations.
2. Implement `mix wotex.software.build --workspace ABS` and
   `mix wotex.software.run --workspace ABS` with the exact workspace/manifest
   contract below. Existing shell scripts remain read/write fixture entry points;
   their existence does not satisfy the Mix task contract.
3. Extend the pinned C peer with read/write/release, Who-Is/I-Am and confirmed/
   unconfirmed object/Property COV controls. Expose actual active subscriber count,
   ACK/renewal/cancel counters, object value and process identity. A second real
   client changes a disposable Analog Output. The test checks every ACK/value,
   requested selector plus Status_Flags companion, renewal, cancellation and
   subscriber return to baseline. CP02–CP09 in `test/interop/cstack_cov_test.exs`
   cover this workflow for object COV using the instrumented fixture's actual
   registry and wire counters. CP10–CP21 cover Property COV service boundaries,
   independent delivery and Runtime mapping. Lost registration/renewal/deletion ACK scenarios
   distinguish local resource release from server lifetime expiry. Discovery uses
   only explicit local destinations and never edits an existing route.
4. Execute full typed/malformed/lifecycle/Runtime coverage and the independent
   C workflow, C09 stress, minimum/current Elixir/OTP, native fixture sanitizers/
   audit, archive-only package checks and final clean-source evidence. Every
   required lane fails on unavailable setup or response. Hardware is separate.

No implementation substitutes an injected response for an independent peer.
Native C changes belong to fixtures, not production library transport.

## Reproducible software fixture contract

Both Mix tasks require exactly one `--workspace ABS` option. ABS is absolute
and either empty/disposable or contains a matching verified manifest. Unknown
options, an unrelated nonempty directory and mismatched hashes fail without
changing unrelated contents. Tasks configure no Git remote and execute tools
as executable/argument vectors, never interpolated shell text.

Build verifies BACstack's locked Hex source and the C-stack archive in the
[software-sources-v1.json](../specs/fixtures/software-sources-v1.json) before extraction. Archive members cannot
escape the workspace. Downloads have a 120-second/100-MiB per-archive ceiling.
Reuse rechecks source and binary hashes. The manifest records source URL/commit/
archive SHA-256, all fixture/patch source hashes, compiler/linker/libc/CMake/OS/CPU
versions and executable hashes, exact build options, binary SHA-256, container
base digest/package versions if used, and the project lockfile/source identity.
Changed tools/options require a fresh build. A pinned source alone does not imply
bit-identical container or compiler output.

The Linux native fault build uses `-fsanitize=address,undefined
-fno-omit-frame-pointer` for C fixture and linked C-stack code. Sanitizer findings
fail the lane. The manifest separates normal and sanitizer binaries/options;
native audit records SDK/source/patch identities and reviewed advisories. No
waiver silently suppresses an applicable finding.

Run owns only manifest-created processes/containers/ports/state. It allocates
disposable local ports, waits for explicit readiness within 10 seconds, and
bounds captured stdout/stderr to 1 MiB each; overflow fails the lane. Every exit
releases owned resources within 1000 ms locally. Remote subscriber expiry uses
the requested finite lease and is recorded separately when cancellation cannot
reach the peer. Missing tools, responses, counters or cleanup are failures.

The runner selects `mix test --include interop --include software --exclude
hardware`, the C peer tests, ASan/UBSan and dependency audits. It sets
`WOTEX_REQUIRE_SOFTWARE=1`; missing fixture configuration is then an assertion
failure, never an ExUnit skip. Pure and injected-boundary tests stay in the local
`mix check` gate. Required runtime cohorts are Elixir 1.18/OTP 27 and
Elixir 1.20/OTP 29 with exact patch versions. The independent C/fault lane runs
on Linux. No physical BACnet network, device or certification is required.

Evidence records every command/exit status, source/archive/fixture/binary hashes,
case IDs and corpus digests, actual service/callback/failure observations, and
resource counters before and after cleanup. C09 requires at least 1000 sequential
operations, 32 concurrent callers, 100 open/close cycles and 100 receiver-death
cycles with forced deadline, malformed reply and peer-loss cases. Heap/RSS and
owned process/port/timer/listener/Invoke-ID/subscriber counts are separate
measurements. Zero local delivery is not proof of zero server subscriptions.

## Verification and completion

Each logical implementation commit requires focused assertions and full
`WOTEX_PATH_DEPS=1 mix check --no-retry`. The ordinary Hex identity remains the
package contract; the path switch is explicit development evidence. Keep the
95% coverage floor, warnings and dependency audits intact. Native fixture edits
also require their sanitizer and source-audit lanes. Use configured Git identity;
no remote, push, tag, publication, visibility or consumer changes are permitted.

Completion requires every S/N/I/C requirement, exact corpus binding and required
software lane, plus a clean committed-source `mix check` and out-of-tree archive
consumer. Archive contents include declared runtime/test source assets and exclude
SDK downloads, native fixture binaries, secrets, state, sockets, PLTs and logs.
Documentation and capability claims name only executed cells. Independent peer
acceptance, certification and consumer parity are distinct evidence scopes.
