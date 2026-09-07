# WLB.06: Evidence, conformance and observability

Specification version: 1.2.0. Contract: accepted. Source status: the external
conformance target for the core package, the evidence record with its content
digests, Lab telemetry spans and measurements, and the versioned Continuum
fault schedule are implemented; benchmarks and the machine evidence graph
remain planned.

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
