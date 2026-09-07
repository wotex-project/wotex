# WLB.05: Directory, Continuum and the smart-room consumer

Specification version: 0.1.0. Contract: accepted.

## Directory references

Lab MUST implement two genuinely separate repository algorithms: an
instance-owned ETS store serialized by its owner process, and a SQLite store
using database transactions and conditional SQL. The SQLite implementation
uses Exqlite directly; Ecto is unnecessary for this narrow reference contract.
Sharing fixtures and the public contract suite is allowed; wrapping the same
store or transaction implementation twice is not independent evidence.

Both MUST implement `Wotex.Directory.Repository`: `fetch/3`, `insert/3`,
`replace/4`, `delete/4`, `list/4`, `expire_due/5`. Public Authorization
`authorize/5`, Clock `now/1` and Identifier `generate/1` are supplied explicitly.
Fixed/system clocks and fixed/UUID identifiers teach deterministic versus
host-provided time/identity. AllowAll is confined to disposable simulations;
scoped authorization separates principal, tenant and operation context.

Required cases include register/get/replace/merge-patch/delete/list/expire,
introduction and returned event values; authorization before repository work;
context isolation; duplicate registration; competing expected-version writes
with one winner; interrupted transaction rollback; stable bounded ordering;
collection revision invalidation on mutation **and expiry**; repeated expiry;
purge/retain semantics; restart and persistent reopen. No database migration
or production policy is installed by loading Lab. SQLite files live under an
explicit instance data directory and teardown follows retention configuration.

This suite supplies WTD-C01–C05 evidence. Package-content exclusion remains
WTD-C06. Discovery transport, search languages and a Discovery conformance
corpus are excluded from the baseline; their absence does not narrow the
required Directory operations above.

## Continuum consumer

The reference edge/cloud channel MUST use public `WotexContinuum` constructors
and codec; the actual namespace is not `Wotex.Continuum`. Manifest/context/
capability compatibility, TD references, all registered value kinds, observation
and Action roundtrips and lifecycle transitions need positive/negative vectors.
Transport is a bounded, instance-owned in-memory channel with explicit delay,
drop, duplication, reorder and disconnect faults; network interaction already
has real transports under WLB.04.

The host owns artifact admission, authentication, policy, deduplication,
persistence and dispatch. It MUST correlate intent, attempt, result, delivery
and evidence without treating any received value as authorization or proof
of effects. A duplicate delivery cannot cause a second simulated mutation.
Invalid compatibility or stale authority cannot fall through to execution.
Replay after disconnection distinguishes message receipt from observed state.
Native-map, JSON, schema and constructor disagreement is recorded against
WCT-C01–C03; exact artifact consumer proof supports WCT-C04/C05.

## Canonical smart room

The integrated scenario MUST compose an HTTP/SSE thermostat, MQTT energy meter
and HTTP actuator, discover their TDs through the explicit Directory service,
consume through Runtime, carry observation/intent/result values through the
Continuum channel and execute the WLB.03 Nx pipeline. Every Thing identity and
affordance comes from its admitted TD, never a name-only join.

A decision record binds proposal digest, Thing/Action, input, principal,
observation watermark, state revision and expiry. Dispatch uses that record
once within the simulated host. Concurrent policy attempts, stale data,
conflicting proposals, revoked decision and duplicate delivery MUST be tested.
Decision, dispatch acknowledgement and observed simulated effect are separately
inspectable. Restart erases in-memory grants; no grant is implicitly restored.

All channels expose telemetry and evidence under WLB.06. The same scenario
definition powers notebooks, CLI, web and MCP. An optional WLB.09 formal
profile compares control-rule conflicts and replays its counterexample into
this simulator; the base smart room requires no Maude executable.
