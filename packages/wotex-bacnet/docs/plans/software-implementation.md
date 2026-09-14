# BACnet software implementation and acceptance plan

The production architecture is Elixir/OTP with pinned BACstack codecs and an
explicitly owned or borrowed BACnet/IP stack. Independent native C peers are
software fixtures. No Python process, native executable or NIF supplies the
production client. WBA.02 defines the implemented profile and
[executable evidence](../provenance/executable-evidence.md) identifies the exact
tested source, toolchains and cohorts.

Read `CLAUDE.md`, the matching rules and skills, WBA.00, WBA.10, WBA.11,
WBA.12, the source register and the catalogue before changing this profile.
The packages below follow their dependency order. A changed package requires
focused assertions, the complete local gate and every affected native or peer
cohort.

## Accepted software packages

| Package | Required behavior | Executable boundary | Status |
| --- | --- | --- | --- |
| WBA-P01 | S01/S02 and V01–V04: typed values, CharacterString identity, exact ACK/error classification and segmentation limits | `service_boundary_test.exs`, `character_string_test.exs`, malformed and segmentation cases in the four software lanes | Accepted |
| WBA-P02 | S03/S03a and V05/V14: reverse acquisition cleanup, 64-operation admission, caller/deadline checks, borrowed-stack retention and bounded UDP ingress | `stack_lifecycle_test.exs`, `stack_cov_test.exs`, `invoke_ids_test.exs`, IG01–IG06 and sustained local UDP cases | Accepted |
| WBA-P03 | S04 and V06–V08: typed object/Property COV, initiator/selector correlation, confirmed receipt ACK and early-report buffering | local COV suites plus independent CP03/CP04 and CP11–CP16 peer cases | Accepted |
| WBA-P04 | S04 and V09–V11: finite leases, renewal, encoded cancellation, receiver death, overflow and terminal-once cleanup | local lifecycle suites, CP05–CP09, CP14/CP18–CP21 and ST03 | Accepted |
| WBA-P05 | S05 and V12: Runtime Property COV and explicit read probe | Runtime stream/frame/integration suites, CP17 and opening-state CP22–CP24 | Accepted |
| WBA-P05a | N01–N05: native helpers, bounded Who-Is/I-Am and sequential Property reads | F01–F11 corpus, standalone/discovery lifecycle suites and CP02 | Accepted |
| WBA-P05b | I01–I06: exact profiles, route/value/error/Retry projection and consumer ownership | I-F01 plus I-F02–I-F07 through the protocol and Runtime boundaries | Accepted |
| WBA-P06 | S01–S05, S03a, N01–N05, I01–I06, C09 and V13/V14: complete independent software acceptance | source-bound normal/sanitizer shared and terminal cohorts on both supported runtimes, plus WBA-A01–WBA-A04 through exact archives | Accepted |

Test filenames without a directory are under `test/wotex/bacnet/`. Independent
peer tests are under `test/interop/` and stress tests are under
`test/software/`. The status column applies to the software profile identified
in the evidence document. Hardware, certification, publication and downstream
consumer parity use separate evidence scopes.

## Implementation boundaries

### Owned ingress

S03a uses BACstack's public `TransportBehaviour` and reviewed pinned packet
codecs. `IngressTransport`, `StackOwner` and `StackClient` preserve receipt
identity and grant credits only after consumption. IG01–IG06 cover starvation,
socket loss, counter saturation, borrowed receive policy and sustained UDP
input. A suspended owner or client admits at most eight outstanding receipts;
terminal slow-consumer handling releases owned processes and sockets.

### Reproducible peer fixture

`mix wotex.software.build --workspace ABS` builds or verifies pinned normal and
instrumented peers and writes their source, toolchain and binary manifest.
`mix wotex.software.run --workspace ABS` owns four lanes:

- normal/shared
- normal/terminal
- sanitizer/shared
- sanitizer/terminal

The POSIX `build_software.sh` and `run_software.sh` files delegate directly to
those Mix tasks. The command guardian owns process groups, bounded output,
deadlines, cleanup and workspace leases without interpreting command text.
Native cases cover inherited signal state, short-lived startup races, group
setup failure, owner loss and descendant cleanup. Runner fault cases RF01–RF05
cover exact container identity, readiness, output limits, deadlines and cleanup
failures.

The shared lane excludes `peer_shutdown`. The terminal lane owns a separate
peer and runs CP25, where an explicit peer exit occurs with live COV and Invoke
ID state. Acceptance requires the peer's cleanup receipt and exact absence of
all labelled containers.

### Independent BACnet behavior

The pinned C peer supplies read/write/release, Who-Is/I-Am and confirmed or
unconfirmed object/Property COV controls. Its observation surface reports
subscriber, Invoke ID, ACK, renewal, cancellation, object-value, socket and
process state.

CP02–CP09 cover discovery, batch access, write/readback/release and object COV.
CP10–CP21 cover native Property boundaries, Property COV, increments,
Status_Flags, capacity, selector rejection, Runtime mapping and lost ACK paths.
CP22–CP24 cover Runtime owner, receiver and callback-worker death during an
accepted registration whose ACK is withheld. CP25 covers peer loss with live
state.

ST01 executes 1000 sequential reads and 32 concurrent callers. ST02 executes
100 stack ownership cycles. ST03 executes 100 receiver-death cycles across
object/Property and confirmed/unconfirmed modes while preserving a separate
live association. Every stress receipt separates local resource cleanup from
finite remote lease expiry.

## Fixture contract

Both Mix tasks require exactly one `--workspace ABS` option. `ABS` is absolute
and is either empty and disposable or contains a matching verified manifest.
Unknown options, an unrelated nonempty directory and mismatched identities fail
without changing unrelated contents. Tools are invoked as executable and
argument vectors.

The build task verifies the locked BACstack Hex source and the C-stack archive
listed in
[software-sources-v1.json](../specs/fixtures/software-sources-v1.json) before
extraction. Archive members cannot escape the workspace. Downloads have a
120-second and 100-MiB per-archive ceiling. BACstack and C-stack source checks
apply their narrower compressed limits and a 4096-member, 64-MiB expanded
limit. Every installed BACstack package file is compared with the verified Hex
archive.

The manifest records source URL and commit, archive SHA-256, fixture and patch
hashes, compiler/linker/libc/CMake/OS/CPU versions, executable hashes, build
options, binary hashes, base image identity, package versions, lockfile and
project source identity. Reuse rechecks these values. A changed source, tool or
option requires a new workspace build.

The instrumented Linux build applies ASan and UBSan to fixture and linked SDK
code. A diagnostic fails its lane. Normal and instrumented binaries and options
have separate manifest entries. CP01 and CP10 execute inside the built image;
the shared and terminal suites execute against the corresponding peer binary.

The run task allocates disposable local ports, requires readiness within ten
seconds and bounds each captured stdout/stderr stream to one MiB. Locally owned
resources have a 1000-ms cleanup budget. Missing tools, responses, counters,
case receipts or cleanup evidence fail acceptance. A remote subscription whose
cancellation cannot reach the peer is measured through its requested finite
lease rather than treated as local cleanup.

The runner selects `mix test --include interop --include software --exclude
hardware` with `WOTEX_REQUIRE_SOFTWARE=1`. Missing fixture configuration is an
assertion failure. Pure and injected-boundary tests remain in the local
`mix check --no-retry` gate. Supported cohorts are Elixir 1.18.4/OTP 27.3.4.15
and Elixir 1.20.2/OTP 29.0.4.

## Verification contract

Each logical implementation commit requires focused tests and
`WOTEX_PATH_DEPS=1 mix check --no-retry`. The gate includes compilation,
formatting, strict Credo, unit/property/doctest execution once through the
coverage pass, at least 95% coverage, Dialyzer, Doctor, ExDoc, dependency checks,
Hex packaging, clean archive contents, an isolated archive-only reference
consumer and the Application-free structural check.

Native fixture changes also require CP01/CP10, ordinary and instrumented peer
lanes, source identity checks and cleanup receipts. Evidence records commands,
exit status, source/archive/fixture/binary hashes, case and requirement IDs,
corpus digests, protocol observations and resource counts before and after
cleanup. Heap/RSS observations are reported separately from owned resource
counts.

Archive contents include declared runtime and documentation sources. They
exclude downloaded SDKs, fixture binaries, secrets, sockets, state, logs and
PLTs. Repository visibility, remote operations, tags, publication, hardware and
certification are outside this plan.
