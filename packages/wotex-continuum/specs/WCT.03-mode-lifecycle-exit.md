# WCT.03 — Deployment mode, lifecycle, degradation, and exit values

Status: Accepted

Specification version: 1.0.0

Wire schema version: 1.0.0

Owner: `wotex-continuum`

## 1. Purpose

WCT.03 makes continuum placement and failure behavior explicit without owning
a deployment controller. It separates deployment mode from current
connectivity so intermittent operation is observable rather than hidden in a
mode label.

BCP 14 key words have the meaning declared by WCT.01.

## 2. `mode`

| Member | Type | Rules |
|---|---|---|
| `deployment` | enum | REQUIRED: `saas`, `hybrid`, `connected_onprem`, or `air_gapped` |
| `connectivity` | enum | REQUIRED: `connected`, `intermittent`, or `disconnected` |
| `extensions` | object | OPTIONAL |

`deployment` describes admitted placement. `connectivity` describes current
upstream reachability. An `air_gapped` deployment MUST report `disconnected`
upstream connectivity; local networking remains possible and is outside this
field. No deployment value implies that a capability is available.

The four modes have these minimum meanings:

| Deployment | External dependency rule |
|---|---|
| `saas` | external services MAY be required when declared by capability |
| `hybrid` | local and remote execution MAY be composed explicitly |
| `connected_onprem` | execution is on premises; declared external dependencies MAY be reachable |
| `air_gapped` | required behavior MUST operate without external network reachability |

An intermittent or disconnected state MUST NOT silently route to an undeclared
provider. Queue, read-only, fail-closed, or unavailable behavior comes from the
capability declaration and a `degradation` value.

## 3. `lifecycle`

| Member | Type | Rules |
|---|---|---|
| `subject_id` | string | REQUIRED |
| `state` | enum | REQUIRED: `staged`, `ready`, `active`, `degraded`, `draining`, `stopped`, or `removed` |
| `generation` | non-negative integer | REQUIRED and monotonically increasing |
| `changed_at` | RFC 3339 timestamp | REQUIRED |
| `reason` | string | OPTIONAL |
| `extensions` | object | OPTIONAL |

Allowed state transitions are:

```text
staged -> ready | removed
ready -> active | stopped | removed
active -> degraded | draining | stopped
degraded -> active | draining | stopped
draining -> stopped
stopped -> ready | removed
removed -> (none)
```

A transition MUST increment generation by one and supply its timestamp. The
pure transition function validates the graph; it performs no activation,
draining, stopping, or removal effect.

## 4. `degradation`

| Member | Type | Rules |
|---|---|---|
| `degradation_id` | string | REQUIRED |
| `subject_id` | string | REQUIRED |
| `level` | enum | REQUIRED: `none`, `reduced`, or `unavailable` |
| `capabilities` | array of strings | REQUIRED, unique, may be empty only for `none` |
| `reason_codes` | array of strings | REQUIRED, unique, may be empty only for `none` |
| `since` | RFC 3339 timestamp | REQUIRED |
| `recoverable` | boolean | REQUIRED |
| `evidence` | array of WCT.02 evidence references | OPTIONAL |
| `extensions` | object | OPTIONAL |

`none` MUST have empty capability and reason lists. `reduced` and `unavailable`
MUST name at least one affected capability and reason. The value reports state;
it neither probes health nor selects fallback behavior.

## 5. `exit_receipt`

| Member | Type | Rules |
|---|---|---|
| `receipt_id` | string | REQUIRED |
| `subject_id` | string | REQUIRED |
| `operation` | enum | REQUIRED: `export` or `remove` |
| `status` | enum | REQUIRED: `requested`, `running`, `completed`, `failed`, or `partial` |
| `requested_at` | RFC 3339 timestamp | REQUIRED |
| `completed_at` | RFC 3339 timestamp | REQUIRED for terminal status |
| `artifacts` | array of evidence references | OPTIONAL |
| `residuals` | array of strings | OPTIONAL; MUST be non-empty for `partial` |
| `error` | typed error object | REQUIRED for `failed` |
| `extensions` | object | OPTIONAL |

Terminal statuses are `completed`, `failed`, and `partial`. For `remove`, a
`completed` receipt MUST have no residuals. A receipt describes consumer-host
evidence; the library never exports, deletes, or verifies state.

## 6. Compatibility and evidence

Compatibility follows WCT.01 section 8. Normative JSON Schema is
`priv/schemas/wct-03.schema.json`; executable vectors use the `wct-03-` prefix
under `test/vectors/`.
