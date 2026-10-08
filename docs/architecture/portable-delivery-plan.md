# Portable implementation delivery programme

Plan `PD-P@1.1.0`, 2026-10-08. Target specifications: WRT.04–06 at 1.1.0.
Source-review baseline: `c8c727a7c8c18fec82d80cc5ba88d246af3c67fc`.
This is a dependency-ordered completion contract, not an execution tracker.
Runtime admission values are implemented. The package catalogue records
implementation status; native and independent-consumer qualification remains open.

## Target and stop conditions

Deliver one useful optional codec seam and one useful independently provisioned
native-host profile while retaining normal library consumption. Success means
an independent consumer can select an exact implementation under explicit
trust/policy without rebuilding its host, and receives honest refusal,
continuity and effect outcomes. No general installer, registry, marketplace,
application root or dynamic BEAM loader is needed.

The [decision](portable-delivery-decision.md) allocates ownership. The
[research gaps](../research/portable-delivery-gap-analysis.md) state the reviewed
facts and uncertainties. Runtime's [completion contract](../packages/wotex-runtime/plans/wotex-runtime-completion.md)
owns the package's optional work. WoTEx is unreleased; implementation may revise
existing APIs when required by the design, updating their contracts and callers.
The specifications define the intended APIs/receipts before implementation.
Source and execution evidence remain separate from publication or API stability.

| Stage | Dependencies and owner | Concrete deliverable | Acceptance / stop condition |
|---|---|---|---|
| PD-01 | Current source, package owners | Trace Runtime -> one HTTP adapter, Modbus byte mapping, and BLE persistent host; public entry points/callers, qualified cells and exact deployments | `mix def`, `mix refs`, `mix impact` when checkout is prepared; read owning guidance; name real replacement requirement and data-only counterexample; stop external-host expansion if no consumer value |
| PD-02 | PD-01, Runtime | WRT.04 specified public values/receipt formats and negative vectors | Implement A07 signatures/records; parser bounds, execution-version checks and current-policy checks pass; no I/O/start side effects; revise current APIs/callers where needed without making descriptors mandatory |
| PD-03 | PD-02, Runtime + protocol owner | WRT.06 codec algebra and trusted BEAM adapter for an explicitly chosen Modbus value mapping | Compare a data-only mapping update first; if data meets the requirement, retain data and do not add executable delivery for that case |
| PD-04 | PD-03, independent codec implementers + consumer | Exact `process-codec@1.0.0` host and two independently written language implementations of the same registered codec | Full success/refusal/canonical-byte vectors and process fault tests prove the already specified API/wire contract; exact closure, custody and resource limits pass; no same-VM fallback; any necessary design correction revises the specification |
| PD-05 | PD-02, WRT.05, BLE + independent consumer | Provision an exact existing BlueZ executable/guardian closure and optional lifecycle metadata; retain its package-specific IPC | Update WBL specification/catalogue before profile implementation; immutable deployment, denied privileges, two owners, uncertainty and stop/reopen gap tests pass; no active-device health probe before old custody is released |
| PD-06 | PD-04/05, consumer update verifier | Explicit local-pin and verified-update integration | Offline pinned start; expired/revoked/rollback metadata and missing trusted clock fail new update admission; signing/root policy is consumer-owned; no native hash relabelled a signature |
| PD-07 | Relevant prior stage, Lab/reference consumers | Clean offline consumer against exact package/executable artifacts, with no live workspace resolution | Zero/one/two instances, owner death, candidate failure, cleanup and changed implementation without host rebuild; record target/dependencies and unresolved physical cells |
| PD-08 | PD-07, maintainer | First-release API documentation, archive evidence, supported/unsupported profile matrix | Every advertised cell has current exact-input evidence; catalogue reflects source implementation, evidence/adoption separate; release/publication remains human-only |

PD-04 and PD-05 solve different problems. Completing either does not prove the
other. No protocol is added to the shared native inventory before its own
source/build/profile and target contract is accepted. Root tooling remains a
provisioning caller, not a runtime library dependency. Common custody code is
not extracted until two real protocol owners demonstrate equivalent needs.

## Preregistered experiments

Before implementation, the consumer records workload, target and go/stop
criteria in its own evidence inputs. The codec experiment compares data-only
mapping, trusted BEAM decode and process decode for the same bounded bytes,
success/refusal distribution and concurrency. Measure end-to-end latency,
throughput, peak memory, startup/cold cost, update effort and installed closure.
Numeric performance thresholds come from that consumer's requirement, never
from arbitrary scores in research. This plan does not execute benchmarks.

The native experiment compares source-bundled and pre-provisioned exact BlueZ
host closures on the same supported target. Prove clean offline installation,
explicit start, no device access before admission, immutable path deployment,
owner-specific notification custody, restart loss and unknown write effects.
Virtual/software evidence is labelled separately from physical Bluetooth
qualification. No Linux result establishes macOS or firmware support.

| Gate | Required proof | Failure disposition |
|---|---|---|
| `ENG-PASSIVE` | Loading library/data/descriptor starts no transport or child and reads no ambient configuration | Fix boundary before any promotion |
| `ENG-CODEC` | Independent identical outputs/refusals under concrete grammar/budgets; no I/O during decode | Refuse codec profile; retain existing decoder |
| `ENG-CLOSURE` | Verified exact executable, guardian, loader/dependencies and target from clean offline deployment | Refuse artifact; explicit source path remains independently qualified |
| `ACT-CREDENTIAL` | Per-interaction resolution, denied grant refusal, secret canaries across public surfaces | Refuse profile; redaction declarations alone fail |
| `ACT-SESSION` | Old generation fenced, owned cleanup, explicit stream gap, exclusive store handling | No replacement claim |
| `ACT-EFFECT` | Cancel/lost response never causes mutation replay or canonical-success inference | No admission regardless of convenience |
| `ACT-MULTI` | Two configured instances do not share handles, policy or lifecycle; shared daemon effects disclosed | Separate instances or refuse shared profile |
| `ACT-VALUE` | Named replacement avoids host rebuild/conflict and meets preregistered workload costs | Keep library/data/bundled host; stop loader expansion |

## Evidence and validation

Each future evidence receipt MUST name repository commit and dirty-input
digests if any, owning package path, specification/binding/protocol versions,
descriptor/configuration identity, package archive and executable build/payload
identities, target/system/loader closure, trust/policy revisions, commands,
vectors, result and limitations. Never record reusable credentials or private
consumer data. Evidence belongs to owning `priv/`/test fixtures and package
provenance, not a central mutable worker tracker. Changed inputs make old
evidence stale; rerun the owning check.

For implementation, use the monorepo workflow: focused package tests, fast
package gate, and Dialyzer when types/callbacks change. Before committing code,
`mix check` selects changed packages and their dependents. Native lint/full
native gates apply only when native source changes. Explicit software/native
builds, independent interoperability, containment, hardware and benchmarks
need their documented invocation and prerequisites; they are not implied by a
documentation update. Documentation changes require current catalogues,
resolving links and accurate ExDoc references, not all application suites.

Do not implement OCI or WASM during PD-01–08. An OCI carrier requires a later
versioned media-type/local-layout/import contract and must preserve native
identities/trust. A WASM experiment requires WRT.06's pinned binding obligations
and independent measured value. Neither is a dependency for the accepted local
artifact and trusted BEAM paths.
