# WRT.04: Optional implementation admission

Specification `WRT.04@1.1.0`. Package owner: `wotex_runtime`.
Contract: accepted optional specification; implementation status: `partial`.
The uppercase MUST, MUST NOT, SHOULD and MAY state obligations of this optional
profile. The A07 pure values are implemented; binding qualification remains open. WRT.01–03 consumers remain
usable without this profile or a descriptor. This is a WoTEx extension contract,
not a W3C Thing Description field or standards-conformance claim.

## A01 — Ownership and inputs

Runtime owns pure descriptor parsing, compatibility comparison and admission
values. A binding owns executable verification at startup, protocol mapping,
resource custody and enforcement. Root native tooling owns build/payload
verification during provisioning. The consumer supplies registrations, verified
local artifact receipts, trust decisions, policy grants, configuration, clocks,
instance identity and supervision. Runtime MUST NOT depend on root tooling,
fetch metadata, resolve a module, inspect an executable or launch a process.

The public target API is defined in A07, including constructors, return shapes
and receipt formats. WoTEx is unreleased. Existing exports and struct layouts
are implementation inputs, not compatibility constraints on this design.
Implementation MUST follow the specified target API; a needed design change
revises the specification and its catalogue before changing that target.

`inputs` MUST contain an explicit installed-registration map, local artifact
receipt or `nil`, trust decision, policy decision, target, host API/binding
versions, policy revision, supplied UTC time and consumer scope. These decisions
are trusted consumer values, never fields accepted from artifact bytes. A
serialized descriptor cannot manufacture a verified receipt. Revalidating
constructors and the execution boundary MUST reject forged or stale values.
Malformed/missing decision inputs return `invalid_admission_inputs`, never an
exception or a permissive default. Consumer scope is a 1–128 byte contract
token. Registration maps contain at most 64 entries; all policy/trust/receipt
values obey A05's generic data bounds or a stricter locally specified format.

## A02 — Descriptor grammar

The v1 descriptor is one UTF-8 JSON object with exactly the fields below.
Unknown top-level or nested fields are rejected except inside `extensions`.
All fields are required; explicit `null` is allowed only where listed.
Duplicate JSON keys at any depth, invalid Unicode, non-integer numbers,
trailing data and a byte-order mark fail. Integers lie in `0..9007199254740991`.
Number tokens use JSON integer syntax without a fraction or exponent.
No input string becomes an atom or module name.

| Field | Closed value and meaning |
|---|---|
| `schema` | Exactly `wotex.implementation@1` |
| `id` | 1–128 ASCII bytes matching `[a-z0-9][a-z0-9._-]*`; scoped by installed registration, not globally discovered |
| `version` | SemVer `major.minor.patch`, optionally prerelease/build identifiers; 1–64 ASCII bytes; no leading zero in numeric core or numeric prerelease identifiers |
| `kind` | `data_mapping`, `beam_adapter`, `codec` or `native_host` |
| `api` | Object with exactly `id` and `version`; id is a 1–128 byte ASCII contract token, version follows the rule above |
| `binding` | Object with exactly `id` and `version`, same token/version rules; a consumer registration supplies the binding implementation |
| `artifact` | `null` for data and registered BEAM bindings (including BEAM codecs); otherwise exact object with `package`, `profile`, `target`, `build_identity`, `payload_identity` |
| `entrypoint` | `null` when artifact is null; otherwise normalized payload-relative UTF-8 path, 1–256 bytes, at most 16 components |
| `support` | At most 64 distinct support-cell objects, in declared order; zero cells allowed only for data/codec |
| `requires` | At most 32 distinct 1–128 byte ASCII requirement tokens; each must be understood and satisfied locally |
| `configuration_schema` | Object with exactly `id` and `sha256`; locally registered schema token and full digest; no URI fetching |
| `permissions` | At most 32 distinct request objects with exactly `kind`, `resource`, `operations` |
| `state` | Object with exactly `scope`, `continuity`, `update_mode`, `format` |
| `limits` | Object with exactly the nine limit keys in A05 |
| `extensions` | Object with at most 16 namespaced keys and bounded JSON values; optional information only, cannot alter execution |

Contract tokens match `[a-z0-9][a-z0-9._:/-]*`. Token/id patterns match the entire
string. Extension keys are contract tokens of at most 128 bytes containing a
colon that separates nonempty namespace and name. Version syntax follows
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html), including
nonempty dot-separated ASCII alphanumeric/hyphen prerelease/build identifiers.
Digests are full lowercase 64-character SHA-256 hexadecimal strings.
`package`, `profile` and `target` are contract tokens naming an admitted
native inventory cell. No local path,
URL, publisher display name, signature algorithm or trust root belongs here.
Artifact identities MUST follow native artifact foundation 0.7.0 and its
descriptor/payload formats; they are not recomputed from this descriptor.

A support cell has exactly `direction`, `scheme`, `operation`, `media_type`
and `security_scheme`. Direction is `consumed` or `exposed`; operation is an
exact lowercase operation from this closed TD 1.1 vocabulary:
`readproperty`, `writeproperty`, `observeproperty`, `unobserveproperty`,
`invokeaction`, `queryaction`, `cancelaction`, `subscribeevent`,
`unsubscribeevent`, `readallproperties`, `writeallproperties`,
`readmultipleproperties`, `writemultipleproperties`, `observeallproperties`,
`unobserveallproperties`, `queryallactions`, `subscribeallevents` and
`unsubscribeallevents`. Scheme is a lowercase URI
scheme, 1–32 ASCII bytes. Media type is a lowercase `type/subtype` without
parameters or wildcards, 3–128 ASCII bytes. Security scheme is a 1–128 byte
locally registered TD security-scheme token, including `nosec` where applicable.
All cells MUST be nonempty and a subset of the registration's qualified cells;
a generic BindingProfile's broad media matching is not qualification evidence.
Unsupported cells fail explicitly. These cells describe capability only.

A permission request has `kind` equal to `network`, `device`, `service`,
`store` or `credential`; `resource` is a 1–128 byte consumer-assigned opaque
token, not an address/path chosen by the publisher; `operations` is 1–16
distinct locally registered operation tokens. The consumer resolves resource
tokens to exact device/address/service/store boundaries. A grant MUST bind
resource, operations, consumer scope and policy revision. Wildcard grants are
outside v1. Descriptors request access; they cannot grant it.
Immediately before dispatch, the binding MUST match the actual target and
operation to the consumer's exact granted resource/operation set and current
policy. Inbound operations retain the consumer's listener authorization.
Descriptor admission, a qualified support cell and Form selection each confer
no authorization to invoke an Action or establish canonical Property truth.

State scope is `stateless` or `consumer_instance`; continuity is `none` or
`explicit_loss`; update mode is `message_boundary` or `stop_reopen`; format is
`null` or a locally registered versioned store-format token. Data and codec
require `stateless`, `none`, `message_boundary`, `null`. Native hosts require
`consumer_instance`, `explicit_loss`, `stop_reopen`; store-using hosts also
require a format. Transparent live-session migration is outside v1.
BEAM adapters declare the state mode of their installed registration; v1
cannot replace their code in the running VM.

Data mappings and codecs require empty `permissions`; data mappings also require
empty `support`. Process codecs receive only WRT.06 C01 inputs and the explicit
bounded process environment, never descriptor privileges. Data mappings are
consumer-validated data under their existing owning format;
v1 does not introduce another archive or data identity. Their registration
binds the exact data identity outside this descriptor. BEAM implementations
bind to an exact deployed release/module registration. Native host and process
codec entrypoints MUST name a verified executable regular payload file;
absolute paths, empty/dot/dot-dot components, backslashes and symlinks fail.
Paths containing NUL, C0 control characters or DEL also fail before file access.
An implementation's arguments and environment come only from its registered
binding and explicit consumer configuration, never the descriptor.

## A03 — Compatibility and deterministic identity

Readers accept only schema major 1. There is no best-effort interpretation of
new required fields. Ignorable optional additions go under `extensions`; a
semantic requirement needs a recognized `requires` token or a new schema.
Rewriters preserve extensions within admission bounds.

The host explicitly supplies supported API and binding tuples. Admission
requires exact API/binding id and major/minor version equality; patch versions
are compatible within that tuple when major is nonzero. Major-zero and
prerelease versions require exact full version equality. Build metadata never
changes compatibility but remains
part of descriptor identity. Extension version is informational and cannot
authorize update/rollback. Semantic API, binding, manifest, package, native
format and protocol revisions are independent axes.

Descriptor identity is SHA-256 over its complete RFC 8785 JCS representation.
Arrays preserve order; objects are canonicalized; extensions are included.
Two semantically equivalent reordered JSON objects have the same identity;
reordered arrays need not. This identity binds descriptor metadata, not the
artifact payload or Thing identity. Configuration identity covers the locally
validated non-secret configuration in RFC 8785 JCS form, as defined in A07.
Secret references belong to consumer custody and are never hashed into public
evidence; a non-secret custody revision can bind the policy decision.

## A04 — Trust, admission and freshness

Admission evaluates these steps in order and returns the first refusal:

1. Validate descriptor grammar, limits and kind consistency.
2. Find exactly one installed registration by id; compare descriptor identity,
   API, binding, schema, support cells and understood requirements.
3. For executable artifacts, match package/profile/target/build/payload identity
   to a successful local verification receipt, target closure and immutable
   deployment evidence. Match BEAM/data to their registered deployment identity.
4. Validate one of the two consumer trust modes below.
5. Require all requested privileges and limit enforcement from current policy.
6. Produce an admission bound to scope, all identities, target, policy/trust
   revision and validity horizon. No denied permission is silently omitted.

Every installed registration binds id, kind, descriptor identity, exact deployed
BEAM/data or native identity, allowed API/binding tuples, qualified support cells,
recognized requirements and admitted permission requests, configuration schema id/digest, state
mode, enforcement profile and limit ceilings. A registration is supplied by the
consumer, never inferred from an artifact or a loaded module. Duplicate keys
or registrations for the same id fail; multiple versions require distinct
explicit registrations and a new selected admission, never version sorting.

Supplied time and non-null expiry instants are nonnegative UTC Unix milliseconds
at most 9007199254740991. The consumer's trust and policy decisions bind their
own revisions, scope, descriptor/deployment identities and optional validity
horizons. Revision tokens obey the contract-token grammar. Admission horizon
is the earliest non-null trust/policy expiry, or null if both are explicitly
unbounded. A verification receipt also binds native descriptor/manifest format,
all dependency closure identities, target and immutable-deployment evidence.
It also records the native foundation's legal/SBOM inputs and security advisory
disposition, including exact reviewed exception scope/expiry where applicable.
Expired security exceptions or a current blocking advisory fail policy admission
with `security_denied`; missing legal/SBOM evidence fails `artifact_unverified`.
An old successful hash receipt cannot override the current security decision.
Trusted decision objects can be constructed only from the explicit consumer
integration; parsing publisher metadata never creates one.

`local_pin` requires an explicit consumer approval of exact descriptor and
deployment identities. It makes no publisher/freshness claim and starts no
registry lookup. A received artifact cannot approve itself. Optional approval
expiry is compared with supplied UTC time; equality is expired.

`verified_update` requires a receipt from the consumer's update verifier that
binds exact descriptor/artifact identities, trusted root revision, signer
threshold decision, metadata versions, expiry, revocation disposition and
rollback high-water state. The verifier owns signature algorithms, bootstrap,
root rotation, delegated trust and nonvolatile high-water persistence. Expired,
revoked, replayed, incomplete or unverifiable receipts fail before start. No
WoTEx TUF implementation or conformance is asserted by this receipt shape.

Offline operation may continue using an already approved local pin subject to
current consumer policy. It MUST NOT admit a new update using expired metadata,
lower the persisted high-water state or automatically convert update trust into
pin trust. If trustworthy UTC time or root state is unavailable, new
`verified_update` admission fails `trust_unavailable`. A separate explicit
consumer pin is a new trust decision, recorded as such.

Immediately before execution the binding MUST recheck admission against the
current policy/trust revision, expiry and exact deployment identity. A policy
revision mismatch fails and requires fresh admission. A running instance loses
new-work eligibility on explicit revocation; its consumer requests bounded
drain/stop. Pure values cannot observe revocation or operate a hidden watcher.

Verified path-based execution requires immutable deployment against every actor
in the declared threat model, including another process of the same UID.
Repeated hashing alone does not close a verify/execute race. A mutable tree
fails `deployment_mutable`; descriptor claims of immutability are insufficient.
OS-specific descriptor-based execution may later satisfy this with independent
evidence. v1 supplies no generic such implementation.

## A05 — Limits, enforcement and failures

Parsing admits at most 65,536 bytes, collection depth 12 (root object is depth
1), 4,096 total JSON nodes (each value/container is one node), 1,024 entries per
collection and 4,096 UTF-8 bytes per string. More specific field limits take
precedence. Bounds apply during parsing and before allocating oversized values.
Configuration is admitted by its registered local schema under these same
generic ceilings unless the binding has stricter ones. Remote schema references
and evaluating code in schemas are forbidden. Stored secrets are not descriptor
or configuration values.

| Limit key | v1 maximum | Enforcement owner |
|---|---:|---|
| `startup_ms` | 60,000 | Binding owner |
| `request_ms` | 60,000 | Binding owner; caller's earlier deadline wins |
| `shutdown_ms` | 10,000 | Binding/guardian; consumer supervisor allows the budget |
| `inflight` | 32 | Binding admission |
| `queued` | 64 | Binding admission |
| `frame_bytes` | 131,072 | Reader/writer before full allocation |
| `queue_bytes` | 1,048,576 | Binding across both queued control and data |
| `stderr_bytes` | 8,192 | Custody owner; excess terminates the child |
| `memory_bytes` | 1,073,741,824 | Declared OS confinement or trusted deployment profile |

Zero means the resource is unused and forbidden. Executable bindings require
positive startup/request/shutdown/inflight/frame/queue/memory limits; queued
and stderr may be zero. Effective limits are the minimum of the descriptor,
binding ceiling and consumer grant. A required enforcement mechanism unavailable
on the target fails `enforcement_unavailable`. Trusted BEAM execution cannot
promise per-extension hard memory isolation; such a required promise is refused.
Trusted native execution may use a separately evidenced consumer resource
profile; no process creation alone supplies an OS sandbox. Untrusted BEAM and
unconfined untrusted native execution are outside v1 and MUST be refused.

A refusal has `code`, `phase`, `field` and non-secret descriptor/instance
identity where already validated. It has no raw parser/OS/exception text,
paths, credentials or arbitrary publisher-controlled message. Codes are:
`invalid_descriptor`, `limit_exceeded`, `unsupported_schema`,
`registration_missing`, `duplicate_registration`, `incompatible_api`,
`incompatible_binding`, `unsupported_requirement`, `unsupported_cell`,
`artifact_unverified`, `target_mismatch`, `identity_mismatch`,
`deployment_mutable`, `trust_unavailable`, `trust_expired`, `trust_revoked`,
`rollback_denied`, `permission_denied`, `security_denied`, `enforcement_unavailable`,
`invalid_configuration`, `invalid_admission_inputs` and `stale_admission`. Phases are `parse`,
`compatibility`, `verification`, `trust`, `policy` and `execution`.
Field is a fixed known token or `null`; Runtime error wrapping retains only
the admitted code/phase/class, following WRT.01.

## Non-normative descriptor example

This complete example describes a trusted BEAM codec registration, not an
installed implementation. The schema digest is illustrative and grants no
trust. Its consumer must supply the matching registration, schema and explicit
pin/policy decisions. BEAM has no isolated process-memory claim here.

```json
{
  "schema": "wotex.implementation@1",
  "id": "example.codec",
  "version": "1.0.0",
  "kind": "codec",
  "api": {"id": "wotex.codec", "version": "1.0.0"},
  "binding": {"id": "beam-codec", "version": "1.0.0"},
  "artifact": null,
  "entrypoint": null,
  "support": [],
  "requires": [],
  "configuration_schema": {
    "id": "example.codec.config",
    "sha256": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
  },
  "permissions": [],
  "state": {
    "scope": "stateless",
    "continuity": "none",
    "update_mode": "message_boundary",
    "format": null
  },
  "limits": {
    "startup_ms": 0,
    "request_ms": 1000,
    "shutdown_ms": 1000,
    "inflight": 1,
    "queued": 0,
    "frame_bytes": 0,
    "queue_bytes": 0,
    "stderr_bytes": 0,
    "memory_bytes": 0
  },
  "extensions": {}
}
```

## A06 — Acceptance obligations

The pure value cases execute in `test/wotex/runtime/implementation_admission_test.exs`
and `test/wotex/runtime/implementation_boundary_test.exs`. Binding pre-spawn,
immutable-deployment and target enforcement qualification remain required.
Fixtures/schema belong in `priv/` or `test/support/`, never
runtime-readable `docs/`. One public-value test alone cannot prove safe spawn.

| Requirement | Positive cases | Negative / boundary cases |
|---|---|---|
| A01 passive ownership | Zero/one/two explicit registrations; parse/admit without process or I/O | Descriptor attempts module discovery, environment access or a trust receipt; no callback invoked |
| A02 grammar | Every kind, exact thresholds, empty legal collections, valid SemVer | Duplicate nested keys, Unicode errors, unsafe path, forged structs, wrong kind, unknown keys, one over every limit |
| A03 compatibility/identity | Object order invariance; API patch compatibility; preserved extensions | Wrong major/minor, unknown required feature, duplicate ids, prerelease mismatch; each semantic change moves descriptor identity |
| A04 artifact/trust | Exact local pin; valid consumer update receipt; clean offline pinned start | Tampered payload/guardian/dependency, wrong target, expired/revoked receipt, rollback, blocking advisory/expired security exception, missing legal/SBOM evidence, clock/root absence, same-UID path substitution |
| A04 freshness | Re-admit under current policy; explicit revoke prevents new work | Reuse admission after scope/policy/trust/expiry changes; failed update never downgrades to pin |
| A05 policy/bounds | Least-privilege grants and exact budget equality | Undeclared/denied resource, unavailable enforcement, untrusted same-VM code; error and telemetry secret canaries |

Implementation promotion requires these Runtime value tests plus a real
binding integration proving the pre-spawn checks. Signature, artifact integrity,
standard support and physical qualification remain separate evidence dimensions.

## A07 — Public target API and receipt formats

All modules in this section are under `Wotex.Runtime.Implementation`.
The pure value exports are implemented. Value constructors
return `{:ok, value}` or `{:error, %Error{}}`, never raise for public input.
`Error.new/3` returns the error struct directly under its row's fallback rule:
`invalid_admission_inputs`, phase `:construction`, class `:permanent`, with
field/descriptor/instance details all nil when construction input is malformed.
Receipt constructors validate shape and bounds; they do not perform signature,
artifact or OS verification. Consumers populate receipts from their explicit
trusted verifier/policy integrations. Receipt syntax or an Elixir struct alone
is never proof of trust. Execution revalidates against current trusted inputs.

| Public function | Exact input and output obligation |
|---|---|
| `Descriptor.decode/1` | UTF-8 JSON binary -> validated descriptor under A02/A05 |
| `Descriptor.to_map/1` | Validated descriptor -> complete string-keyed descriptor map |
| `Registration.new/1`, `Verification.new/1`, `Trust.new/1`, `Policy.new/1` | A closed string-keyed map below -> the corresponding validated record |
| `Inputs.new/1` | Closed atom-keyed map with exactly `registrations`, `verification`, `trust`, `policy`, `target`, `apis`, `bindings`, `now_ms`, `scope` -> validated inputs |
| `Admission.new/2` | Descriptor and Inputs -> admitted value after A04 in order |
| `Admission.revalidate/2` | Admission and current Inputs -> `:ok` or structured error; rerun A04 and compare all bound identities, scope, target, permissions, limits and horizon, excluding only the new observation time |
| `Plan.new/4` | Admission, non-secret JSON-compatible configuration map, InstanceKey, explicit pure schema-validator function -> validated plan |
| `InstanceKey.new/1` | Closed atom-keyed map `consumer_scope`, `instance_id`, `generation` under WRT.05 L01 -> validated instance key |
| `Error.new/3` | Fixed code, fixed phase, closed atom-keyed details map `field`, `descriptor_sha256`, `instance_key` -> error; unknown/malformed construction input returns `invalid_admission_inputs` with null details |

`Descriptor`, `Registration`, `Verification`, `Trust` and `Policy` structs have
exactly `value` and `sha256`; value is their validated string-keyed map. The
digest is SHA-256 of the complete RFC 8785 JCS value. This digest identifies
receipt metadata; it does not replace native identity or verify a signature.
Every receiving public function revalidates maps and recomputes digests rather
than trusting forged struct fields. Receipt maps have no optional or extra
keys; null is admitted only where stated. All obey A05's generic data ceilings.

Shared shapes used in the tables:

- `deployment` is exactly `{"kind": ..., "identity": ...}`; kind is
  `beam_release`, `data` or `native_payload`. Native identity is the existing
  full payload digest. BEAM identity is the consumer's full release digest.
  Data identity is the owning data format's exact identity token, at most 256
  UTF-8 bytes; this introduces no new Thing Description semantic identity.
- `schema_ref` is exactly `{"id": token, "sha256": digest}`. API/binding
  tuples and permission requests use A02's existing closed shapes.
- `enforcement` is exactly `{"id": token, "trust": "trusted" | "untrusted",
  "guarantees": [...]}`; guarantees are distinct members of `memory`,
  `deadline`, `descendants`, `privileges`, `immutable_deployment`, at most five.
  Actual enforcement evidence is required by A04/A05, not supplied by labels.
- Times are UTC Unix milliseconds under A04; horizon is a time or null.
  Revisions, role names and receipt ids are contract tokens of 1–128 bytes.

| Record | Exact `value` keys and field rules |
|---|---|
| Registration | `schema` = `wotex.implementation-registration@1`; `id`, `kind`, `descriptor_sha256`, `deployment`, `apis`, `bindings`, `support`, `requires`, `permissions`, `configuration_schema`, `state`, `enforcement`, `limits`, `codec_contract`. Id/kind/descriptor/state/schema follow A02; API/binding lists contain 1–8 distinct tuples each; support/requires/permissions and limits obey A02/A05. `codec_contract` is null outside codecs, otherwise exactly `id`, `version`, `sha256` under C01. The registration defines maximum allowed cells/requests and understood requirements. |
| Verification | `schema` = `wotex.implementation-verification@1`; `descriptor_sha256`, `artifact`, `native_descriptor_schema`, `payload_manifest_schema`, `artifact_format`, `closure_sha256`, `deployment_evidence_sha256`, `legal_sha256`, `sbom_sha256`, `advisory_receipt_sha256`, `security_exception`, `verified_at_ms`, `verifier_id`, `verifier_revision`. Artifact matches A02 exactly. Format strings are `wotex.native-artifact-descriptor@2`, `wotex.native-payload-manifest@1`, `wotex.native-artifact@1`. All hash fields are full digests. Exception is null or the exact object described below. |
| Trust | `schema` = `wotex.implementation-trust@1`; `mode`, `approval_id`, `scope`, `descriptor_sha256`, `deployment`, `revision`, `valid_until_ms`, `update`. Mode is `local_pin` or `verified_update`. Update is null for pin and the exact update object below otherwise. Update mode requires a non-null horizon no later than update expiry. |
| Policy | `schema` = `wotex.implementation-policy@1`; `scope`, `target`, `descriptor_sha256`, `deployment`, `revision`, `valid_until_ms`, `grants`, `limits`, `enforcement`, `security_status`, `security_revision`. Grants are at most 32 A02 permission objects; security status is `allowed` or `denied`; limits and enforcement are explicit current consumer policy. |

A security exception object has exactly `id`, `payload_identity`, `scope`,
`expires_at_ms`, `decision_sha256`. Its payload identity must match the artifact.
The decision digest links the actual maintainer decision required by the native
foundation, including source identities and compensating controls. A hash
without that successful decision verification cannot establish an exception.

The update object has exactly `verifier_profile`, `verifier_revision`,
`root_revision`, `signature_receipt_sha256`, `metadata_versions`,
`high_water_versions`, `threshold_required`, `verified_signers`, `expires_at_ms`,
`revocation_revision`, `rollback_checked`. Verifier profile names the consumer's
installed update verification contract. Version maps contain at most 32 role
tokens with positive safe JSON integers; their required role set comes from
that explicitly selected verifier profile. No role required by that profile
may be omitted. Each received version must be at least its persisted high-water
version. Threshold is `1..32`; signers are 1–32 distinct installed key tokens;
verified signer count must meet the threshold; rollback_checked is true.
These fields report completed verification, not self-assertions accepted from
downloaded metadata. Cryptographic algorithms/root rotation remain with the
named update verifier; no implicit TUF implementation is introduced.

`Inputs` has exactly the nine atom-keyed fields in its constructor row.
Registrations is a map of at most 64 descriptor ids to Registration values;
keys must match record ids. Verification is a Verification or nil; trust and
policy are their validated records. Target/scope are tokens; APIs/bindings have
the registration-list grammar; now_ms is the supplied UTC time. For one
admission, select exactly one version per descriptor id. Replacement may supply
a separate explicitly selected registration snapshot for the candidate.

`Admission` has exactly `value`, `sha256`, `descriptor`, `registration`.
Its derived value has exactly `schema` = `wotex.implementation-admission@1`,
`scope`, `target`, `descriptor_sha256`, `registration_sha256`, `deployment`,
`verification_sha256` (null only without executable artifact), `trust_sha256`,
`policy_sha256`, `permissions`, `limits`, `valid_until_ms`, `admitted_at_ms`.
Permissions equal the descriptor's completely granted requests; limits are the
effective minima. The retained Descriptor/Registration must match their digest
references. An admission never retains consumer credentials or verifier code.

`InstanceKey` has exactly `consumer_scope`, `instance_id`, `generation`.
`Plan` has exactly `admission`, `configuration`, `configuration_sha256`,
`instance_key`, `sha256`. Instance scope must equal admission scope.
Plan identity is JCS SHA-256 of exactly `admission_sha256`,
`configuration_sha256`, `consumer_scope`, `instance_id`, `generation`.
Configuration uses A05 bounds, admits only safe signed JSON integers as numbers,
rejects floats, and is hashed with JCS.
The supplied schema validator has arity two: `(configuration, schema_ref)` ->
`:ok | {:error, :schema_mismatch}`. It receives only immutable non-secret data
and MUST be pure: no I/O, clocks, ambient state or code discovery. Malformed
returns and raised/exited/thrown callbacks become `invalid_configuration`
without the foreign reason. Plan construction invokes it once after generic
bounds and exact schema-reference checks, before producing a plan.

`Error` has exactly `code`, `phase`, `class`, `field`, `descriptor_sha256`,
`instance_key`. Identity/details may be null until validated. No general-purpose
details map, raw exception or publisher text is retained. `Inputs` and
`InstanceKey` are consumer values, not publisher JSON formats; module/atom names
are compile-time constants, never derived from descriptor strings.

Class is derived from code, never supplied by publisher or callback text:
`deadline_exceeded` -> `:timeout`; `codec_unavailable`, `startup_failed`,
`owner_lost`, `session_lost` -> `:unavailable`; `overloaded` -> `:rate_limited`;
`protocol_fault`, `correlation_failed` -> `:protocol`; all other codes ->
`:permanent`. A binding with uncertain mutating dispatch MUST return
`effect_unknown` rather than an availability code. None of these classes
schedules retries. Fixed atom values use compile-time mappings only.

A06 acceptance includes every constructor's wrong/missing/extra fields,
forged/stale digests, every nullable branch, version-map rollback and signer
thresholds, exact successful return shapes, and schema-validator exceptions.
These named API and record obligations are part of the specification now.

## Related authority

[WRT.01](WRT.01-consumed-thing-runtime.md) remains the interaction/credential
port contract. [WRT.05](WRT.05-implementation-lifecycle.md) governs admitted
instance use. [WRT.06](WRT.06-bounded-codec.md) narrows pure codecs.
The [native artifact foundation](https://github.com/wotex-project/wotex/blob/main/docs/architecture/native-artifact-contract.md)
owns archive identities and provisioning verification. The
[decision and source register](https://github.com/wotex-project/wotex/blob/main/docs/architecture/portable-delivery-decision.md)
explain the external research; no optional carrier or signature protocol is
silently incorporated into this v1 grammar.
