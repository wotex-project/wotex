# WLB.05: Directory, Continuum and the smart-room consumer

Specification version: 1.3.0. Contract: accepted. Source status: both
repository algorithms are implemented. The ETS store, the SQLite store, the
explicit authorization/clock/identifier ports, the shared Directory contract
suite that runs the same public-API cases against both stores, and the
Continuum channel, host and wire conversions are source complete; the
canonical smart room remains planned.

## Directory references

Lab MUST implement two genuinely separate repository algorithms: an
instance-owned ETS store serialized by its owner process, and a SQLite store
using database transactions and conditional SQL. The SQLite implementation
uses Exqlite directly; Ecto is unnecessary for this narrow reference contract.
Sharing fixtures and the public contract suite is allowed; wrapping the same
store or transaction implementation twice is not independent evidence.

Both MUST implement `Wotex.Directory.Repository`: `fetch/3`, `insert/3`,
`replace/4`, `delete/4`, keyset `list/5`, `expire_due/5`. Public Authorization
`authorize/5`, Clock `now/1` and Identifier `generate/1` are supplied explicitly.
`Wotex.Lab.Adapters.Directory.EtsRepository` is the instance-owned store: a
private ordered ETS table serialized by its owner process, identifier keys in
Unicode code point order, a mutation-generation revision, and volatility by
design (a restarted owner starts empty). `Adapters.Directory.Clock` offers a
fixed or agent-advanced instant and `Wotex.Directory.Clock.System` supplies
host time; `Adapters.Directory.Identifier` is a deterministic counter.
`Adapters.Directory.Authorization` is `:allow_all` for disposable simulations
or a scoped policy that separates principal, tenant and operation and denies
before any repository call.

`Wotex.Lab.Adapters.Directory.SqliteRepository` is the second, genuinely
separate algorithm. It uses Exqlite directly, so each callback is one database
transaction over conditional SQL: `insert/3` is an `INSERT` against the
identifier primary key whose unique-constraint failure becomes
`already_exists`; `replace/4` and `delete/4` are one conditional
`UPDATE`/`DELETE` carrying `expected_version` in the `WHERE` clause, with
`changes()` separating an applied write from one that changed nothing and a
following existence check separating `not_found` from `conflict`; `list/5`
reads one snapshot inside a read transaction and continues the keyset with
`identifier > ?` ordered by `identifier` under the default `BINARY` collation,
which is code point order for UTF-8; and `expire_due/5` selects and mutates its
bounded batch inside a single transaction. The mutation-generation collection
revision is a table row, so it survives a reopen. Stored rows are canonical
JSON revalidated on read through `Wotex.ThingDescription.from_map/2`,
`Wotex.Directory.Registration` and `Wotex.Directory.Entry.new/4`; a row that
does not rebuild is reported, never trusted. One process owns the connection
and serializes the callbacks. The consumer names the instance data directory
with `path:`; `start_link/1` creates that directory and the schema, and
`retain: false` removes the database file when the owner terminates.

Required cases include register/get/replace/merge-patch/delete/list/expire,
introduction and returned event values; authorization before repository work;
context isolation; duplicate registration; competing expected-version writes
with one winner; interrupted transaction rollback (SQLite lane); stable bounded
keyset ordering; collection revision invalidation on mutation while an entry
that expires between pages is simply absent (WTD.01 1.1); repeated expiry;
purge/retain semantics; ETS restart volatility and SQLite persistent reopen.
`test/wotex/lab/directory_test.exs` runs every shared case against both stores
from one generated pair of describe blocks, and adds the store-specific cases:
ETS restart volatility, and for SQLite an aborted statement that rolls its
whole transaction back without a partial write, a reopened file that keeps its
entries and revision, revalidation of corrupted stored bytes, explicit data
directory validation and `retain: false` file teardown. No database migration
or production policy is installed by loading Lab. SQLite files live under an
explicit instance data directory and teardown follows retention configuration.

This suite supplies WTD-C01–C05 evidence. Package-content exclusion remains
WTD-C06. Discovery transport, search languages and a Discovery conformance
corpus are excluded from the baseline; their absence does not narrow the
required Directory operations above.

## Continuum consumer

The reference edge/cloud channel MUST use public `WotexContinuum` constructors
and codec; the actual namespace is not `Wotex.Continuum`.
`Wotex.Lab.Continuum.Channel` is that channel: a bounded, instance-owned
process that encodes every value canonically, records a `delivery` value per
send, applies a versioned `FaultSchedule` (drop, duplicate, hold-until for
reordering) keyed by send sequence, buffers while disconnected and replays
unacknowledged deliveries with a new attempt on reconnect.
`Wotex.Lab.Continuum.Host` is the simulated cloud host: it decodes with the
bounded codec, acknowledges, admits manifests through compatibility
evaluation, admits proposals only above the per-affordance sequence
watermark for a known Thing, dispatches each intent at most once per
idempotency key through a runtime `ConsumedThing` over the loopback lane,
returns an `action_result`, refuses intents without an accepted manifest or
while draining, and keeps a lifecycle value. `Wotex.Lab.Continuum.Wire`
implements the documented wire mapping from Nx observations and proposals
and runtime results. Manifest/context/
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
`test/wotex/lab/continuum_test.exs` covers all thirteen kinds round-tripping
as canonical bytes, manifest compatibility gating, stale authority, duplicate
intent delivery without a second dispatch, reordered and dropped proposals,
disconnection and replay, capacity exhaustion, lifecycle draining and the
wire conversions in both directions.

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
