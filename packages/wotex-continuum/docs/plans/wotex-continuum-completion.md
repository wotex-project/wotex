# Wotex Continuum completion contract

Plan version: 1.1.0. Package baseline: 0.1.0. Wire schema: 2.0.0.
The single [catalogue](../specs/catalogue.yaml) points to normative WCT owners
under `specs/`; it does not duplicate them.

This tracked document is a versioned acceptance baseline, not a mutable work
tracker. An accepted baseline is immutable in meaning; changed obligations need
a new plan version and compatibility classification. Store execution status,
attempts, machine-local handoffs and evidence only in ignored
`docs/tasks/local/wotex-continuum-tracker.yaml`. Package inputs allowlist
publishable documentation and structurally exclude `docs/tasks/local/`; every
candidate archive must still prove that boundary because Git ignore is not an
archive rule.
Catalogue implementation coverage and a successful local gate are distinct
from archive admission, independent interoperability and stable API readiness.

## Ownership and forbidden responsibilities

The package owns inert continuum exchange values, validation, deterministic
encoding, capability compatibility comparison and pure lifecycle transitions.
It imports Thing Description meaning through the declared core dependency;
it does not create a competing Thing Description model.

The consumer host owns canonical Thing state, identity, authorization, trusted
clocks, artifact admission, credential custody, provider selection, dispatch,
persistence, queues, worker coordination, retries and reconciliation. No
application callback, hidden process, database, migration, scheduler, ambient
configuration or remote fetch belongs here. Action intent, result, delivery and
exit records remain claims represented as data, not proof of effects.

## Exact public seam

| Owner | Public values/functions and required behavior |
| --- | --- |
| `WotexContinuum` | `schema_version/0`, `kinds/0`, `from_map/1`, `to_map/1`, `module_for_kind/1`; registered kinds and exact envelope version. Top-level `to_map/1` reconstructs values before returning success. |
| WCT.01 | Manifest, Compatibility, ExecutionScope, Capability; nested Artifact and CapabilityRequirement. `from_map/1` with the `new/1` alias, `to_map/1`; top-level values expose `kind/0`. Compatibility `evaluate/3` returns `:ok` or every mismatch. Manifest `compatible_with?/3` delegates the check; it does not admit an artifact. |
| WCT.02 | ObservationProposal, ActionIntent, ActionResult, EvidenceReference, Delivery; nested Failure. Constructors/maps preserve null-versus-absence rules and status coherence. `ThingReference.validate/2` checks a value's Thing identifier against a supplied validated Thing Description, not identity trust. |
| WCT.03 | Mode, Lifecycle, Degradation, ExitReceipt with `from_map/1` and its `new/1` alias, `to_map/1`, `kind/0`; Mode `deployments/0`, `connectivity_states/0`; Lifecycle `states/0`, `transition/4`. No deployment or teardown side effect. |
| Codec | `decode/2` admits bounded JSON iodata, `encode/2` validates registered values, `canonicalize/1` requests canonical encoding. Canonical bytes are project-defined, not RFC 8785. |
| Limits, Schema, Error | `Limits.defaults/0`, `new/1`; `Schema.ids/0`, `fetch/1`, `info/1`; errors expose stable `code`, `phase`, an RFC 6901 JSON Pointer `path` (or `nil`) and structured details. Schema identity/digest is not runtime schema-conformance proof. |

Constructors accept documented native maps and reconstruct their own structs;
unknown envelope fields, atom/string collisions and unknown or duplicate
keyword options must fail as typed errors. Expected failures are
`{:error, %WotexContinuum.Error{}}`, not exceptions. Compatibility mismatch
lists are the documented separate comparison result. Match codes and paths,
not messages. Low-level typed accessors are not substitutes for reconstruction
at an untrusted boundary.

Admission defaults are 1,048,576 bytes, depth 32, 100,000 nodes, 10,000 members
per collection and 262,144 bytes per string. `Limits.new/1` accepts positive
explicit overrides and `Codec.decode/2` delegates source admission to the core
`Wotex.JSON.decode/2` pipeline, which preflights binary content, scans depth and
string size before decoding, copies strings and then checks duplicate members,
collection size, node count and depth. Iodata is flattened before that byte
check; this is not a proof of bounded pre-allocation memory. Native JSON values
share the single depth bound, measured from the validated value; byte, node,
collection and string bounds remain source-admission controls. WCT-C02 keeps
that difference explicit rather than claiming a uniform envelope.

## Concurrency, lifecycle and recovery

Calls execute synchronously in the caller and share no mutable state. Lifecycle
transitions validate the WCT.03 graph and increment generation; they do not
serialize competing consumer updates or acquire a lock. The consumer must
compare generations atomically where it persists them. `removed` is terminal;
draining/stopped are reported values, not shutdown callbacks.

Recovery means decoding consumer-retained values under an explicit compatible
wire version. The package never recovers a queue, resubmits an Action, reads the
clock or elects a writer. An `unknown` Action effect remains unknown until the
consumer reconciles it; `delivered` is not exactly-once execution, and an exit
receipt does not delete data or verify retention obligations.

## Security and credentials

Contexts, timestamps, artifact digests, evidence URIs and opaque references are
untrusted. Constructors verify structure, not authenticity, signatures, access
rights, clock accuracy or current authority. Capabilities declare abilities,
not grants. Extension keys are absolute IRIs but are never dereferenced.
The consumer controls URI origin/scheme/media/size policy and credential
resolution. It must not place secrets in envelopes or assume the codec redacts
arbitrary extension data. See `docs/THREAT_MODEL.md` for the threat boundary.

## Standards-claim matrix

W3C meanings are pinned to [Thing Description 1.1](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
and [Architecture 1.1](https://www.w3.org/TR/2023/REC-wot-architecture11-20231205/),
Recommendations dated 5 December 2023. All WCT fields are project-defined.

| Claim | Value | Operation | Interoperability | Profile | Certification |
| --- | --- | --- | --- | --- | --- |
| WCT.01 manifest/context/capability | Project wire 2.0.0 | Construct, encode, compatibility compare | Local vectors; independent consumer proof requires WCT-C04 | Not a WoT Profile or admission standard | None |
| WCT.02 observations/Actions/delivery | Project wire 2.0.0, W3C vocabulary | Data conversion and supplied TD identity check | No transport or cross-vendor execution claim | Not WoT Scripting API | None |
| WCT.03 modes/lifecycle/exit | Project wire 2.0.0 | Pure graph transition only | Does not prove disconnected deployment or recovery | Not deployment-management conformance | None |
| JSON canonicalization | Package-canonical bytes | Deterministic encoding | Exact encoder/version cohort; not signature portability | Not RFC 8785 JCS | None |
| Bundled JSON Schemas | WCT schema documents | Fetch, digest and subset validation of every vector | Documented keyword subset only; `format` and `propertyNames` are not evaluated, so full-vocabulary agreement remains WCT-C03 | Not W3C conformance | None |

## Independent implementation work

| ID | Prerequisites | Deliverable | Acceptance |
| --- | --- | --- | --- |
| WCT-C01 | WCT.01–WCT.03 | Map every field, default, optional/null rule, error and transition to tests | All 13 registered kinds plus nested values have valid, invalid, canonical and struct-reconstruction evidence; no unknown field escapes via another constructor route. |
| WCT-C02 | WCT-C01 | Close native-input and codec safety gaps without adding host authority | Reject invalid UTF-8 native JSON object keys as well as values, including nested observation/input/output/failure data, with valid error paths; test malformed structs and options. Specify/test native versus decoder limits and preflight allocation boundaries; preserve valid bytes and canonical vectors. |
| WCT-C03 | WCT-C01, WCT-C02 | Schema/constructor/vector agreement matrix | Validate valid/invalid vectors against the relevant bundled schema and constructors; distinguish semantic checks that JSON Schema cannot express. Add exact mismatch regressions before correcting schemas or code. Syntax-only schema tests do not satisfy this item. |
| WCT-C04 | WCT-C02, WCT-C03 | Archive and independent minimal consumer proof | Build with declared package requirements and no development path selection; exercise manifest compatibility, a supplied TD reference, observation/Action round trips and lifecycle transitions from the exact archive. Consumer examples need no external service or privileged database. |
| WCT-C05 | WCT-C04 | Compatibility, supply-chain and release dossier | Pin source/archive/lock/schema/vector digests and toolchains; enumerate independent package/wire version compatibility, dependency floor/latest evidence, unsupported claims, API review and public artifact contents. No automated publication. |

Concurrent implementation may use those prerequisites without any tool-specific
harness. Each edit has one owner; pure contract tests define the seam. The
package must not grow a cross-repository coordinator, central outcome log or
remote-commit requirement to support parallel workers.

## Acceptance gates

| Gate | Required evidence |
| --- | --- |
| `repository_green` | Exact source/lock/toolchain plus all `mix check --no-retry` tools: warnings-as-errors, format, strict Credo, dependency audits, Doctor, Dialyzer, docs, >=95% coverage and existing boundary/archive checks. A run with explicit development dependency selection proves only that named cohort. |
| `archive_consumer_green` | WCT-C04 archive with released package requirements, no development override or pre-existing adjacent checkout, installed in a fresh minimal consumer; public examples pass. Current `bin/check_archive.exs` compiles an unpacked archive against a development core path and cannot alone satisfy this stronger gate. |
| `reference_consumer_green` | Same archive exercises all three WCT contracts and supplied TD checking in a consumer-neutral reference application; failures, unknown effects, lifecycle generation and extension round trips are asserted. This is consumer proof, not cross-vendor certification. |
| `public_release_candidate` | All preceding gates, WCT-C03 agreement, reviewed threat model, public content, licenses/provenance, accurate claims and immutable candidate evidence. The maintainer alone may later publish. |
| `stable_api_candidate` | WCT-C05 compatibility review of API and wire contracts independently, exact error/result/null/default/canonical-byte rules and upgrade/rejection vectors. A stable wire version does not automatically make package 0.1 APIs stable. |

Fresh checkout: read `CLAUDE.md`, this plan and the catalogue's owning specs;
resolve the declared dependencies with `mix deps.get`, then run `mix check --no-retry`.
If a required package is not available, record the dependency-admission gap;
do not silently convert fresh-checkout evidence to a local-path pass. The README
development switch remains useful for implementation, but its exact dependency
source must be recorded and must not be mistaken for archive-consumer proof.
Package construction unsets development path selection.

Evidence must name source-tree identity, archive SHA-256, package/wire versions,
dependency lock digest, exact core source or artifact identity, schemas and
vector digests, Elixir/OTP versions and command results. Re-run evidence after
source, dependency or schema changes; a commit ID does not identify a dirty tree.

## Remaining-claim ledger

| Claim not discharged by present test shape | Owner | Required closure |
| --- | --- | --- |
| Native UTF-8 admission equals JSON decoder admission | WCT-C02 | Native payload object keys are explicitly validated; malformed Unicode cannot enter accepted nested values or error paths. |
| Uniform resource bounds | WCT-C02 | Source admission is delegated to the core bounded decoder and one `max_depth` covers decoded and native values. The residual claim is the rest of the envelope: iodata flattening precedes the byte check, and byte, node, collection and string bounds still do not apply to a native map handed straight to a constructor. |
| Normative schema/implementation agreement | WCT-C03 | Canonical, valid and invalid vectors now execute against the embedded schemas through a documented keyword subset, and the invalid set separates schema-expressible from semantic rules. The residual claim is full-vocabulary agreement: `format` and `propertyNames` assertions are not evaluated, so absolute-IRI, media-type and RFC 3339 admission rests on the constructors. |
| Independent fresh consumer installation | WCT-C04 | Declared package cohort, no development path assumption, representative public API tests. |
| Local execution files excluded from public archives | WCT-C04 | Explicit package exclusion and archive-content regression; Git ignore is not a package boundary. |
| Stable API and canonical-byte compatibility | WCT-C05 | Explicit independent wire/package compatibility decisions and version-pinned vectors. |
| Authority, exactly-once delivery, actual air-gap execution or certified interoperability | Consumer-owned/non-claim | Remain non-claims; do not implement host authority to close a value-library checklist. |

This is a fixed acceptance ledger, not a progress report. Record actual work
states and receipts only in local execution tracking.
