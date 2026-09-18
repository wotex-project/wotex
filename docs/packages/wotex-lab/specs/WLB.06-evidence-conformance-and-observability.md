# WLB.06: Evidence, conformance and observability

Specification version: 1.7.1. Contract: accepted. Source status: implemented.
The external core conformance target and its host containment profile, the
content-addressed evidence record, Lab telemetry, the versioned Continuum fault
schedule, bounded benchmark records and the machine evidence overlay all have
executable positive, negative, lifecycle and resource evidence for reviewed
local targets. The native helper's sampled limits are not kernel enforcement;
the separate kernel-isolated OCI profile carries the hostile whole-tree
isolation obligation. A pinned Linux lane executes the reviewed-local profile's
Bubblewrap path.
The repository gate runs the locked Rust unit and lifecycle cohort with its
feature-gated probes in a private, cleaned OS-temporary Cargo target. A passing
repository gate includes those native results. Generated binaries and probe
artifacts remain outside the package archive.

## Evidence record and maturity

Every run record MUST have a schema version, scenario/revision/attempt IDs,
source-tree and lock digests, exact dependency versions/archive digests,
fixture/model/dataset digests as applicable, seed, toolchain/backend/platform,
budgets, input references, assertions, outcomes, durations and cleanup results.
Source revisions alone cannot identify dirty inputs. Missing archive evidence
MUST be explicit, not synthesized from a source checkout. No secrets, arbitrary
callbacks or executable paths appear in public evidence.
`Wotex.Lab.Evidence.Record` is that record: `new/1` validates every field
with a typed error and a pointer path, a dependency states `archive: :missing`
or a `sha256:` digest and is refused when it omits the field, and a deep scan
refuses functions, process identities, structs, filesystem paths and
credential-looking strings anywhere in the record. `to_map/1`, `encode/1`
and `digest/1` give a canonical string-keyed form, canonical bytes and their
SHA-256; `from_map/1` reads a record back under the same validation and
refuses other schema versions. `Wotex.Lab.Evidence.Digest` supplies file,
tree and in-memory content digests and the toolchain strings; it never reads
a source revision.

Lab uses three separate axes in the catalogue:

| Axis | Allowed values | Admission |
| --- | --- | --- |
| implementation | implemented / partial / planned | Coverage of the entire accepted spec, not just exported modules |
| evidence | missing / partial / complete | All positive, applicable negative, lifecycle, resource and independent proof obligations |
| adoption | no_reference / reference_available / artifact_verified | Inspectable consumer source; then independent use of exact artifacts |

`planned` means fully specified but no source. `complete` evidence requires
identified passing records for every obligation. `artifact_verified` requires
the strict artifact mode from WLB.08. A green unit suite cannot promote either.
Stale evidence remains attributable to its recorded cohort and MUST NOT be
silently applied to a new dependency or spec revision.

The machine graph MUST preserve upstream catalogue status verbatim, with source
revision/digest and retrieval date. Upstream evidence/adoption axes absent in
source are `not_reported`, not guessed from Lab opinion. Lab's evidence overlay
is separately namespaced and references exact completion IDs; only the package
owner can accept closure. It is an evidence index, not cross-repository worker
coordination, lease state, a scheduler or an execution tracker.
`Wotex.Lab.Graph` exposes this as `evidence_overlays`: Lab specification and
cookbook evidence has `wotex_lab`-namespaced IDs, its producer and source are
explicit, and `indexes` edges resolve to exact Lab or upstream completion
nodes. The upstream catalogue nodes remain untouched and every overlay states
that closure authority belongs to the package owner.

## Conformance independence

The Lab target MUST be a separate executable/project built against the exact
subject archive, implementing the WCF.01 external protocol from public docs.
The runner project MUST NOT import the subject. The target MUST NOT import
runner internals, inspect expectation files or receive expected values.
`Wotex.Lab.Conformance.Target` is that target: `respond/1` derives one
normalized observation from the declared document and projection by running
the core package, and `main/1` is the process entry the runner starts through
a port (an `erl` invocation with explicit code paths, no shell, a private
`HOME`). `main/1` reads and writes in the encoding standard input and output
already have: Latin-1 passes bytes through unchanged and Unicode decodes valid
UTF-8 without loss, so the exchanged bytes do not depend on the host locale or
the OTP release. A request that is not valid UTF-8 exits 14 (undecodable)
instead of being answered;
`test/wotex/lab/conformance_target_process_test.exs` runs the process entry
under the C and UTF-8 locales. The subject archive is a tar of the loaded core
`ebin` directory, so
the evidence names the compiled subject that actually answered; it is source
mode evidence, not a Hex artifact claim.
Claims/vectors/expected results remain runner-owned. A Lab target wrapping
WoTEx is independent consumer evidence, **not an independent WoT parser**.
Core interoperability additionally requires a named independent implementation
or published corpus with pinned revision/license and counterexamples.

Required outcomes are observed/pass, mismatch/fail, unsupported, timeout,
malformed/partial/oversized response, target crash and changed archive refusal.
`test/wotex/lab/conformance_test.exs` runs the core package through both
bundled corpora (pass on every vector), refuses a changed archive before any
vector runs, and checks the pure derivation for projections, rejections,
non-object documents and unsupported operations.
These are scenarios, not new WCF status values. Preserve the runner's canonical
`pass`, `fail`, `unsupported`, `not_run` and `infrastructure_error` statuses;
timeout/crash/malformed output are reasons under the runner's actual outcome.
Concurrent runs cannot exchange output; late bytes cannot satisfy another run.
OS containment belongs to the host: bounded CPU/memory/process count, no network
by default, private temporary directory and whole-process-tree termination.
Port timeout alone is not descendant cleanup. This supports WCF-C01–C04/C06;
WCF-C05 Discovery corpus is an explicit excluded corpus decision, not a TD/TM
pass. WCF-C07 is package hygiene. Reports MUST state covered assertions and
exclusions; no certification is implied.
`Wotex.Lab.Conformance.Containment` refuses a host without an admitted network
sandbox. On Darwin it combines `sandbox-exec` with an explicitly provisioned
no-shell Rust executable; on Linux it requires Bubblewrap with a private `/proc`
and a minimal `/dev`. The launcher applies inherited CPU,
open-file, output-file and core limits, accounts resident memory and process
count over the target tree, gives the target its own process group, and enforces
an inner deadline before the runner deadline so it can kill descendants. The
sandbox denies network access and writes outside the private temporary tree.
Its public descriptor contains limits, mechanism names, profile/helper versions
and the exact native executable SHA-256 but no paths. The target environment
selects the `C.UTF-8` locale. Profile 2.0.2 requires
`:launcher` as `%{executable: absolute_path, digest: "sha256:..."}`; absent,
symlinked, oversized or changed launchers are refused. No Rust toolchain,
interpreter, download, compiler or NIF is invoked by this runtime API.

The Rust helper also cleans up after normal target exit, keeps the root's PID
reserved until group cleanup, tracks observed descendants by start identity,
and fails on accounting/cleanup errors. It samples every ten milliseconds and
caps process-table/identity work at 65,536 entries. Profile 2.0.2 reserves one
second between the inner launcher deadline and the outer runner deadline; the
helper's 150 ms cleanup ceiling is explicit evidence inside that margin, leaving
the remainder for sandbox/launcher startup, scheduler delay and port exit-status
delivery. When a caller supplies a runner deadline of one second or less, the
inner wall limit is one millisecond and the exact smaller effective margin is
reported; such a deadline is useful only for prompt refusal, not target work.
CPU/open-file/output/core limits are
inherited OS limits; RSS/process counts are sampled, not hard cgroup limits.
Transient root-accounting gaps during `exec` get at most two retries with
one-millisecond pauses; persistent absence fails instead of becoming zero RSS.
The [native containment decision](../decisions/0006-native-containment-executable.md)
records that rapid unobserved daemonization, between-sample peaks, hostile
filesystem reads and the deprecated Darwin sandbox are not proven isolated.
The reviewed-local source cohort therefore cannot close the whole-tree
hostile-target contract, and no untrusted hosted target is admitted by this
helper.

Profile 2.0.2 corrects two Linux defects found by its first Linux execution.
Bubblewrap previously bound the host `/dev` read-only; inside the unprivileged
user namespace those device nodes cannot be opened and a BEAM target spun at
startup until its CPU limit killed it. The profile now mounts a minimal `/dev`.
The previous `C` locale made a BEAM target on Linux select Latin-1 file name
encoding and print a warning into its protocol output; the profile now selects
`C.UTF-8`. The output file-size limit also bounds the memory file of the default
dual-mapped BEAM JIT, so BEAM targets pass `+JMsingle true`.
`elixir bin/check_linux_containment.exs` builds
`test/containers/linux-containment/Dockerfile` from the pinned Rust and
`hexpm/elixir` images with Debian Bubblewrap, copies the Lab's tracked files
and each clean source owner's `HEAD` into a private workspace, and runs
`conformance_target_process_test.exs` and `conformance_test.exs` as the calling
user. Only seccomp and masked system paths are relaxed, so Bubblewrap can create
its unprivileged namespaces. It prints the image identity, package versions and
the log digest, then removes the container and workspace.

`Wotex.Lab.Conformance.KernelContainment` profile 1.1.0 is the kernel-isolated
profile, recorded in the
[kernel-isolated profile decision](../decisions/0009-kernel-isolated-conformance-profile.md).
`external_map/6` takes an operator-provisioned OCI runtime command line admitted
by SHA-256 after link resolution, a digest-pinned image that is never pulled,
the in-image command with one `{subject_archive}` argument, the archive, at most
sixteen read-only code directories and a private home directory. The container
has no network, a read-only root, one bounded `tmpfs`, user `65534:65534`, no
capabilities, no privilege escalation, hard cgroup memory (no swap) and process
limits, a CPU quota and CPU-time, open-file, file-size and core limits. Its
entrypoint `/usr/bin/timeout --signal=KILL` is PID 1 with an inner deadline three
seconds before the runner deadline; when it exits the kernel kills every process
left in the PID namespace. The evidence descriptor carries limits, mechanism,
runtime digest and image reference but no path or label. Each map has a random
label; `residue/3` counts and `release/3` force-removes containers carrying it,
both through one bounded runtime command.

`run_map/5` contains work that has no subject archive: it takes the same runtime,
command and home, and at most sixteen absolute host files and directories that
are bound read-only at their own paths. Every other flag, limit, deadline and
evidence field is the one above, so a contained notebook is contained exactly
like a contained target. Its `:network` option is `:none` by default. The
`{:internal, name}` variant instead joins a network that the caller created
without egress, and the evidence then reads `internal:<name>` rather than
`none`, so a run that could reach a peer container is never counted as
no-network evidence. WLB.07 owns what that variant executes.

`test/wotex/lab/kernel_containment_test.exs` covers admission without a
process. `test/wotex/lab/kernel_containment_lane_test.exs`, selected with
`WOTEX_LAB_CONTAINER=1`, runs both core corpora through the pinned
`hexpm/elixir` image and hostile probes: loopback-only networking and a refused
outbound connection, an unreadable host canary, read-only root and code mounts,
an effective UID of 65534 with no effective capabilities and `NoNewPrivs`, a
kernel OOM kill at the memory ceiling, process creation stopped by the cgroup
limit, a `setsid` descendant that does not outlive its container, a hung target
killed at its inner deadline, concurrent targets with separate output and zero
labelled containers after release. The 15-second runner deadline is the
profile's fixed hostile-target budget, not a measured performance bound: the
inner `timeout` kill and the deadline case prove it bounds a hung target,
while normal cases finish far below it. The lane prints the wall time of each
contained case and the WLB.06 record keeps those observed values under
`durations`, so a slow run on a loaded machine is read as load rather than as
a reason to change a limit. The runtime daemon, its kernel and the image
are trusted; kernel or runtime escape and shared-kernel denial of service are
outside this profile, and hosted admission remains a WLB.08 deployment
obligation.

## Telemetry and faults

Lab emits under `[:wotex, :lab, component, operation, event]` so measurements do
not pretend to originate inside passive upstream libraries. Start/stop/
exception spans cover parse, request, subscription, directory, codec, conformance,
encode, inference, decode, verification and dispatch. Durations use monotonic
native units with an explicit exporter conversion. Counts/bytes are measurements.
`Wotex.Lab.Telemetry.span/4` and `event/4` implement this with a closed
component and operation vocabulary; the loopback and HTTP adapters, the SSE
session, both Directory stores, the Continuum channel codec, the conformance
target, the Nx steps of the examples and the smart room, and the policy
dispatch emit through them. Verification spans arrive with WLB.09.

Metadata is allowlisted: scenario/attempt/spec/seam IDs, safe Thing reference,
operation, profile and outcome. TDs, tensor contents, credentials, headers,
arbitrary callback reasons and unbounded IDs MUST NOT become metric labels.
Tests attach capture handlers and inject credential/payload sentinels. Logs,
traces, reports and dashboards must contain neither.
`Telemetry.metadata/1` enforces this before emission: only allowlisted keys
survive, values must be atoms, integers or binaries of at most 128 bytes, an
exception closes a span with its kind and `outcome: :exception` only, and
`thing_ref/1` replaces a Thing id with a short non-reversible reference.
`test/wotex/lab/telemetry_test.exs` attaches capture handlers, injects
credential and payload sentinels through real runtime requests, and shows a
raising handler is detached without changing the span result. The concrete PromEx,
bounded ETS, GreptimeDB, OTel and BeamLens contracts are in
[WLB.10](WLB.10-metrics-storage-and-ai-inspection.md); the lean native workbench
and design system are in [WLB.11](WLB.11-workbench-and-design-system.md).
Host-scoped dependency processes must not be mislabeled per-instance plugins.
Exporter failure cannot authorize an effect or block cleanup indefinitely.

Fault profiles include callbacks raising/throwing/exiting, wrong returns,
identity mismatch, receiver death, partial startup, network/broker loss,
duplicate/out-of-order/late deliveries, capacity exhaustion and oversized data.
Fault schedules are versioned inputs with expected outcomes. Benchmarks use
Benchee where suitable and record bytes/nodes/depth/forms/rows/width/window/
queue/session counts, memory and percentile latency on a pinned machine.
Absolute shared-runner timings are informational; thresholds require an explicit
runner/backend/cohort and baseline. A benchmark result is not a correctness test.
`Wotex.Lab.Benchmark` implements the bounded data record and native short-run
sampler used by package evidence. It admits only the declared dimensions,
requires runner/backend/cohort/baseline/machine identity, records process memory
and nanosecond min/p50/p95/p99/max/mean latency, and marks correctness as
`not_evaluated`. Shared runs cannot carry thresholds; dedicated thresholds are
observations inside the record and never turn a benchmark into a correctness
test. Longer host investigations may use Benchee and normalize its results into
the same record, while the deterministic package gate remains dependency-free.
