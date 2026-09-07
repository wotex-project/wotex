# WLB.06: Evidence, conformance and observability

Specification version: 0.1.0. Contract: accepted.

## Evidence record and maturity

Every run record MUST have a schema version, scenario/revision/attempt IDs,
source-tree and lock digests, exact dependency versions/archive digests,
fixture/model/dataset digests as applicable, seed, toolchain/backend/platform,
budgets, input references, assertions, outcomes, durations and cleanup results.
Source revisions alone cannot identify dirty inputs. Missing archive evidence
MUST be explicit, not synthesized from a source checkout. No secrets, arbitrary
callbacks or executable paths appear in public evidence.

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
Claims/vectors/expected results remain runner-owned. A Lab target wrapping
WoTEx is independent consumer evidence, **not an independent WoT parser**.
Core interoperability additionally requires a named independent implementation
or published corpus with pinned revision/license and counterexamples.

Required outcomes are observed/pass, mismatch/fail, unsupported, timeout,
malformed/partial/oversized response, target crash and changed archive refusal.
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

Metadata is allowlisted: scenario/attempt/spec/seam IDs, safe Thing reference,
operation, profile and outcome. TDs, tensor contents, credentials, headers,
arbitrary callback reasons and unbounded IDs MUST NOT become metric labels.
Tests attach capture handlers and inject credential/payload sentinels. Logs,
traces, reports and dashboards must contain neither. The concrete PromEx,
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
