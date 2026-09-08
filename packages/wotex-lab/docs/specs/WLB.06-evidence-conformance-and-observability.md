# WLB.06: Evidence, conformance and observability

Specification version: 1.4.0. Contract: accepted. Source status: partial.
The external core conformance target and its host containment profile, the
content-addressed evidence record, Lab telemetry, the versioned Continuum fault
schedule, bounded benchmark records and the machine evidence overlay all have
executable positive, negative, lifecycle and resource evidence for reviewed
local targets. The native replacement review identified an unclosed hostile
whole-tree isolation obligation; sampled limits are not kernel enforcement.

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
`HOME`). The subject archive is a tar of the loaded core `ebin` directory, so
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
no-shell Rust executable; on Linux it requires Bubblewrap. The launcher applies inherited CPU,
open-file, output-file and core limits, accounts resident memory and process
count over the target tree, gives the target its own process group, and enforces
an inner deadline before the runner deadline so it can kill descendants. The
sandbox denies network access and writes outside the private temporary tree.
Its public descriptor contains limits, mechanism names, helper version and
the exact native executable SHA-256 but no paths. Profile 2.0.0 requires
`:launcher` as `%{executable: absolute_path, digest: "sha256:..."}`; absent,
symlinked, oversized or changed launchers are refused. No Rust toolchain,
interpreter, download, compiler or NIF is invoked by this runtime API.

The Rust helper also cleans up after normal target exit, keeps the root's PID
reserved until group cleanup, tracks observed descendants by start identity,
and fails on accounting/cleanup errors. It samples every ten milliseconds,
caps process-table/identity work at 65,536 entries and reserves 150 ms for
cleanup inside the runner margin. CPU/open-file/output/core limits are
inherited OS limits; RSS/process counts are sampled, not hard cgroup limits.
Transient root-accounting gaps during `exec` get at most two retries with
one-millisecond pauses; persistent absence fails instead of becoming zero RSS.
The [native containment decision](../decisions/0006-native-containment-executable.md)
records that rapid unobserved daemonization, between-sample peaks, hostile
filesystem reads and the deprecated Darwin sandbox are not proven isolated.
The accepted whole-tree hostile-target contract therefore remains open for a
kernel-isolated worker/VM profile; the reviewed-local source cohort cannot
close it. No untrusted hosted target is admitted merely by this helper.

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
