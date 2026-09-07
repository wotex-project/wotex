# WCT.02 — Observation proposal, Action, evidence, and delivery values

Status: Accepted

Specification version: 2.0.0

Wire schema version: 2.0.0

Owner: `wotex-continuum`

## 1. Purpose

WCT.02 defines data-only exchange values for proposing an observation,
requesting and reporting an Action, referring to immutable evidence, and
describing delivery progress. Construction, encoding, and decoding never write
canonical Thing state or dispatch an Action.

BCP 14 key words have the meaning declared by WCT.01.

## 2. W3C terminology and project boundary

Thing, Property, Action, and Event use the meanings in W3C Recommendation
*Web of Things (WoT) Thing Description 1.1*, 5 December 2023, sections 5.3.1–
5.3.4:
<https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/>.

The envelopes and their member names are Wotex Continuum fields. An
`action_intent` is not a W3C Scripting API object and does not prove that the
named Action exists, is safe, or is authorized. A consumer host MUST resolve
the current Thing Description and apply identity, policy, idempotency, and
effect-recording rules before dispatch.

## 3. `observation_proposal`

| Member | Type | Rules |
|---|---|---|
| `proposal_id` | string | REQUIRED |
| `thing_id` | absolute IRI | REQUIRED |
| `affordance_type` | enum | REQUIRED: `property` or `event` |
| `affordance_name` | string | REQUIRED |
| `value` | JSON value | REQUIRED; `null` is a value, not absence |
| `observed_at` | RFC 3339 timestamp | REQUIRED; normalized to UTC |
| `sequence` | non-negative integer | OPTIONAL |
| `quality` | object | OPTIONAL JSON object, defaults to `{}` |
| `evidence` | array of `evidence_reference` | OPTIONAL |
| `context` | `execution_scope` | REQUIRED |
| `extensions` | object | OPTIONAL |

The value is a proposal. Acceptance, conflict handling, ordering across sources,
and canonical observation persistence belong to the consumer host.

## 4. `action_intent`

| Member | Type | Rules |
|---|---|---|
| `intent_id` | string | REQUIRED |
| `thing_id` | absolute IRI | REQUIRED |
| `action_name` | string | REQUIRED |
| `input` | JSON value | REQUIRED; defaults to `null` only when explicitly supplied |
| `requested_at` | RFC 3339 timestamp | REQUIRED |
| `idempotency_key` | string | REQUIRED |
| `requested_by` | string | OPTIONAL opaque principal reference |
| `evidence` | array of `evidence_reference` | OPTIONAL |
| `context` | `execution_scope` | REQUIRED |
| `extensions` | object | OPTIONAL |

The pair of consumer-defined scope and `idempotency_key` is the deduplication
input. This library does not define scope, store keys, or decide replay.

## 5. `action_result`

| Member | Type | Rules |
|---|---|---|
| `result_id` | string | REQUIRED |
| `intent_id` | string | REQUIRED |
| `status` | enum | REQUIRED: `accepted`, `running`, `succeeded`, `failed`, `cancelled`, or `unknown` |
| `output` | JSON value | OPTIONAL; permitted only for `succeeded` |
| `error` | object | OPTIONAL; REQUIRED only for `failed` |
| `started_at` | RFC 3339 timestamp | OPTIONAL |
| `completed_at` | RFC 3339 timestamp | OPTIONAL; REQUIRED for terminal status |
| `evidence` | array of `evidence_reference` | OPTIONAL |
| `context` | `execution_scope` | REQUIRED |
| `extensions` | object | OPTIONAL |

Terminal statuses are `succeeded`, `failed`, and `cancelled`. If both times are
present, `completed_at` MUST NOT precede `started_at`. Error objects contain
non-empty `code` and `message` strings plus optional JSON `details`.

`unknown` records that the effect cannot yet be established. It MUST NOT be
silently converted to `failed` or retried without consumer-host reconciliation.

## 6. `evidence_reference`

| Member | Type | Rules |
|---|---|---|
| `evidence_id` | string | REQUIRED |
| `uri` | absolute IRI | REQUIRED |
| `digest` | string | REQUIRED lowercase `sha256:` digest |
| `media_type` | string | REQUIRED |
| `captured_at` | RFC 3339 timestamp | REQUIRED |
| `extensions` | object | OPTIONAL |

The value is a reference, not evidence verification. Dereferencing MUST be an
explicit consumer-host operation subject to scheme, origin, size, and media-
type controls.

## 7. `delivery`

| Member | Type | Rules |
|---|---|---|
| `delivery_id` | string | REQUIRED |
| `item_kind` | registered top-level kind | REQUIRED |
| `item_id` | string | REQUIRED |
| `source` | string | REQUIRED opaque endpoint reference |
| `destination` | string | REQUIRED opaque endpoint reference |
| `status` | enum | REQUIRED: `pending`, `in_flight`, `delivered`, `acknowledged`, `failed`, or `unknown` |
| `attempt` | positive integer | REQUIRED |
| `sequence` | non-negative integer | OPTIONAL |
| `emitted_at` | RFC 3339 timestamp | REQUIRED |
| `acknowledged_at` | RFC 3339 timestamp | REQUIRED only for `acknowledged` |
| `error` | typed error object | REQUIRED only for `failed` |
| `extensions` | object | OPTIONAL |

Delivery values do not create a queue, perform a retry, or establish exactly-
once semantics. A consumer host owns transport, backpressure, retry policy,
deduplication, and durable acknowledgement.

## 8. Wire mapping to in-memory sibling values

WCT.02 values are the wire form of in-memory values owned by sibling Wotex
packages. This section is documentation of an intended correspondence, not a
dependency: `wotex-continuum` depends only on the Wotex core and MUST NOT
import a sibling package. A consumer host performs the conversion and owns
every decision the conversion implies.

`observation_proposal` is the wire form of `Wotex.Nx.Observation`:

| WCT.02 member | `Wotex.Nx.Observation` field | Difference |
|---|---|---|
| `proposal_id` | `id` | identifier member names differ |
| `thing_id` | `thing_id` | same meaning |
| `affordance_type` | `affordance_type` | same enumeration |
| `affordance_name` | `affordance_name` | same meaning |
| `value` | `value` | same meaning |
| `observed_at` | `observed_at` | RFC 3339 string here, caller-owned integer coordinate there |
| `quality` | `quality` | free JSON object here, closed enumeration there |
| — | `unit`, `source` | not carried on the wire; place them in `extensions` |
| `extensions` | `metadata` | absolute-IRI keys here, free map there |
| `sequence`, `evidence`, `context` | — | continuum-only members |

`action_intent` is the wire form of `Wotex.Nx.ActionProposal`:

| WCT.02 member | `Wotex.Nx.ActionProposal` field | Difference |
|---|---|---|
| `intent_id` | `id` | identifier member names differ |
| `thing_id` | `thing_id` | same meaning |
| `action_name` | `action_name` | same meaning |
| `input` | `input` | same meaning |
| `requested_at` | `proposed_at` | RFC 3339 string here, integer coordinate there |
| `extensions` | `metadata` | absolute-IRI keys here, free map there |
| `idempotency_key`, `requested_by`, `evidence`, `context` | — | continuum-only members |

`action_result` is the wire form of `Wotex.Runtime.Result`:

| WCT.02 member | `Wotex.Runtime.Result` field | Difference |
|---|---|---|
| `intent_id` | `request_id` | the intent, not a transport request, is the correlation subject |
| `status` | `status` | six outcome values here; `:ok` and `:accepted` describe a protocol exchange there |
| `output` | `payload` | present only for `succeeded` here |
| `extensions` | `metadata` | absolute-IRI keys here, free map there |
| — | `operation` | protocol operation is not carried on the wire |
| `result_id`, `error`, `started_at`, `completed_at`, `evidence`, `context` | — | continuum-only members |

`context` carries a WCT.01 `execution_scope`. It is deliberately not
`Wotex.Runtime.ExecutionContext`: that in-memory value carries a credential,
and a continuum value MUST NOT carry credential material.

A conversion is lossy in both directions. A consumer host MUST supply the
missing members explicitly and MUST NOT infer authority, ordering, or effect
from a successful conversion.

## 9. Compatibility and evidence

Compatibility follows WCT.01 section 9. Normative JSON Schema is
`priv/schemas/wct-02.schema.json`; executable vectors use the `wct-02-` prefix
under `test/vectors/`.
