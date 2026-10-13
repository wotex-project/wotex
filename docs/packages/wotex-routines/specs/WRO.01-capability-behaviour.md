# WRO.01 — Capability and behaviour basis

Version: 0.2.2. Updated: 2026-10-13. Status: accepted target.
Implementation: closed basis and fact foundation implemented; execution joins partial.

## Scope and ownership

This optional package defines consumer-neutral behaviour semantics
over installed WoT capabilities. Core retains TD/TM interpretation; Runtime
retains interaction planning; Continuum retains compatible exchange values.
The consumer owns instance identity, canonical observations, policy, credentials,
storage, clocks, supervision and effects. No new device-description parser,
global controller or mandatory runtime is introduced.

A capability is an installed typed interaction contract. A behaviour defines
its preconditions, transitions, effect domains and outcome evidence. A mapping
selects installed semantics. A concrete enrolled instance and its qualification
remain consumer decisions. All four identities remain distinct.

## Required basis

**WRO01-01.** Each installed behaviour basis supplies these immutable values:

| Area | Required semantics |
| --- | --- |
| Identity | Exact contract/version, byte and semantic identities, implementation/compiler basis |
| Interaction | TD/TM affordance reference, supported operation/input/output types and required security/lifecycle contract |
| Value | Dimension, exact unit/scale, valid domain, invalid/missing policy and conversion/error rules |
| Evidence | Accepted report source/quality, required freshness and source continuity, completion threshold |
| Effects | All touched resource domains, possible partial/unknown outcomes and repeat/stop/supersession rules |
| Timing | Deadline, duration/dwell/cooldown and supported uncertainty policy |
| Analysis | Model profile/property scope or explicit unsupported classification |

A required missing field/contract rejects admission. Optional annotations remain
inert. Data may narrow installed operations/ranges, never add privileged
semantics. No profile includes executable expressions, raw routes/bytes,
credentials, module names or automatic timers. Limits are explicit constructor
inputs and validated before allocation; no environment-derived registry exists.

**WRO01-02.** TD/TM affordances and Forms come from WTX.01/02/04. Behaviour fields
are package extensions, never W3C vocabulary. Required model/import closure is
immutable and supplied offline by the consumer; unknown/cyclic/missing closure
rejects without a network fetch. A Form or valid schema does not authenticate
an instance, select an implementation or authorize an operation.

**WRO01-03.** Reconcile observation/intent/result/evidence values against
WCT.01–03 before adding a wire kind. Retain source identity/epoch/sequence and
time/trust when available, consumer receipt epoch/time, declaration/profile
basis, replay/continuity classification, value/unit and derivation provenance.
Unrepresented required semantics reject a proposed adapter; never silently
drop them into a generic context string. Package and wire versions are separate.

Freshness of receipt is distinct from source age. Retained/replayed data cannot
renew source freshness or fabricate an event. Unknown, invalid, stale and usable
qualities remain distinguishable; unknown values never become zero/false.
Derived occupancy/presence retains contributors and expiry, not raw sensor truth.

**WRO01-04.** Exact integer/rational conversion rejects overflow, incompatible
dimensions and required inexact rounding. A separately installed error policy
may permit named approximation; portable data cannot choose one. Temperature,
fraction, illuminance, power, energy and time are distinct dimensions.
Battery voltage is not battery fraction. Counter resets/wrap bind a source
epoch. Device-specific validation stays below generic routine evaluation.

**WRO01-05.** Effect domains conservatively cover a complete resource until
independent evidence justifies narrower concurrency. Different properties
can touch the same actuator or packet. Requested state, local queue acceptance,
protocol response, correlated report and reported equality are different facts.
A report match does not prove physical cause. An absolute operation is not
automatically safe to repeat after uncertain delivery.

## Compatibility and acceptance

### Closed first representation

The optional `wotex_routines` package exposes `Limits`, `Registry`, `Unit`,
`Basis`, `Fact` and `Continuum` under `Wotex.Routines`. Constructors accept
string-keyed JSON maps (or revalidate their own structs), explicit `Limits`
and, for a basis, an explicit offline `Registry`. Results are `{:ok, value}`
or `{:error, %Error{code: atom, path: JSON_pointer}}`. Errors contain no input
payload. Unknown keys, missing required members, invalid UTF-8, malformed
structs, unsupported values and exceeded bounds return errors; public
boundaries do not raise. Repeated construction is deterministic and inert.

`Limits.new/1` requires every field; there are no ambient or inferred defaults:

| Member | Allowed positive ceiling |
| --- | --- |
| `max_bytes` | 1048576 |
| `max_depth` | 32 |
| `max_nodes` | 100000 |
| `max_string_bytes` | 65536 |
| `max_collection_size` | 1024 |
| `max_integer` | 9223372036854775807 |

The caller chooses each positive value at or below its ceiling. Core's public
bounded JSON validation/decoder runs before schema construction. Encoded
results are also limited to `max_bytes`. Every constructor revalidates limits.
Checked projections return `{:ok, data}` or the same structured error:
`Limits.to_map/1`, `Unit.to_map/2`, `Wotex.Routines.Registry.to_map/2`, `Fact.to_map/2` and
`Basis.to_map/3` take the constructor's explicit remaining arguments. A forged
struct cannot bypass construction through a projection.
Collections and strings have those explicit bounds; semantic identifiers are
nonempty UTF-8 strings, digests are lowercase `sha256:` plus 64 hexadecimal
digits, and all numerical coordinates/coefficient magnitudes fit `max_integer`.

`Wotex.Routines.Registry.new/2` accepts a finite array of closed records:
`{id, version, semantic_digest, requires}`. Each `requires` member is a closed
`{id, version, semantic_digest}` reference. IDs are unique within a registry;
multiple revisions of the same ID are not simultaneously installed. All
references match exact installed values. Missing/unknown revisions and cycles
reject, including cycles not reachable from the requested basis. There is no
fetch, module lookup or implicit contract registry.

`Unit.new/2` requires `dimension`, `name`, `scale_n`, `scale_d`, `offset_n`,
`offset_d`, `min` and `max`. Dimensions are exactly `temperature`, `fraction`,
`illuminance`, `power`, `energy`, `time` and `electric_potential`. Scale numerator
and both denominators are positive; offset numerator is signed; `min <= max`.
The canonical coordinate of integer `x` is
`x * scale_n / scale_d + offset_n / offset_d`. `Unit.convert/4` requires equal
dimensions, validates both units and the source domain, computes the exact
rational target coordinate, and accepts only an integer inside the target
domain and caller's magnitude bound. It returns `incompatible_dimension`,
`out_of_domain`, `inexact_conversion` or `integer_overflow` as appropriate.
No rounding policy is installed in this first representation. Intermediate
products are bounded by the validated coefficients; there is no scale-driven
iteration or floating-point conversion. Voltage cannot convert to fraction.

`Basis.new(input, registry, limits)` requires all fields in the executable basis
schema. `Basis.semantic_digest/2` calculates the stated projection digest for
installing a proposal; calculation alone does not admit a basis:

| Member | Closed meaning |
| --- | --- |
| `format` | Exactly `wotex.routines.basis@1` |
| `id`, `version` | Installed semantic contract identity |
| `byte_digest`, `implementation_digest`, `compiler_digest` | Explicit separate caller-owned artifact identities |
| `semantic_digest` | SHA-256 of core's sorted-key JSON encoding after excluding these four digest fields |
| `affordance` | `type`, `name`, `operation`; Property admits readproperty/writeproperty/observeproperty, Action invokeaction, Event subscribeevent |
| `value` | `type`, `unit`, `enum`; boolean has null unit/empty enum, integer has a Unit/empty enum, enum has null unit/nonempty distinct string alternatives |
| `security_contract`, `lifecycle_contract`, `required_contracts` | Exact installed references; closure checked offline |
| `evidence` | `sources`, `freshness_ms`, `require_source_time`, `continuity`, `completion`; sources are device_report/derived_report/protocol_response, continuity is continuous/snapshot, completion is local_queue/protocol_response/correlated_report/reported_match |
| `effects` | `resource_roles`, `repeat`, `stop`, `supersession`, `partial_possible`, `unknown_possible`; repeat is never/after_known_failure/after_reported_safe, stop is unsupported/separate_effect, supersession is block_until_known |
| `timing` | Positive deadline_ms; nonnegative duration_ms/dwell_ms/cooldown_ms; uncertainty exactly block |
| `analysis` | classification supported/unsupported, profile and properties; unsupported requires null profile/empty properties, supported requires an installed profile reference and nonempty distinct properties |
| `annotations` | Only optional title, description and distinct string tags; all inert |

The registry must contain the basis's computed semantic identity and every
required/security/lifecycle/model reference. A caller-declared digest that does
not equal the complete projection rejects. This establishes integrity against
the supplied installed registry, not authenticity or device qualification.
Data cannot change the installed table. `Basis.domains(basis, bindings, registry,
limits)` revalidates that basis and resolves every
resource role through an explicit closed role-to-resource map, returning sorted
unique whole-resource identities; absent or extra bindings reject. No narrower
concurrency scope is installed yet. Effect-bearing bases must admit unknown
outcomes; absolute input alone never changes the installed repeat rule.

`Fact.new/2` requires `id`, `thing_id`, `affordance_type`, `affordance_name`,
`value`, `unit`, `quality`, `source_class`, `source_id`, `source_epoch`, `sequence`,
`source_time`, `source_time_trust`, `source_time_basis`, `source_uncertainty_ms`,
`received_at`, `receipt_epoch`, `receipt_ms`, `profile_digest`,
`replay`, `continuity`, `expires_ms`, `derivation_digest` and `contributors`.
Thing identity is an absolute IRI; affordance_type is property/event. Quality
is usable/stale/invalid/unknown. Sequence and receipt/expiry coordinates are
nonnegative integers; expiry cannot precede receipt. Source time is a
normalized UTC RFC3339 value or explicit null; receipt UTC time is mandatory.
Source class is device_report/derived_report/protocol_response and must later
match the installed basis's accepted sources. The class is explicit data,
never inferred from a source ID or timestamp. Replay is fresh/retained/replayed;
continuity is continuous/baseline/lost.
Source time trust is trusted/untrusted/unknown. Trusted requires a non-null
source_time, a source_time_basis digest and nonnegative source_uncertainty_ms.
Other classifications preserve a null or known basis/uncertainty explicitly.
The source clock's interval is source_time plus/minus its stated uncertainty;
kernel freshness must use that interval and its selected trust basis, rather
than treating a timestamp's presence as clock qualification. Receipt UTC time
cannot renew the source clock's age. Source trust fields are data supplied by
the consumer; construction cannot establish their truth.
Unit is null or a validated Unit. Usable unit-bearing values must be exact
in-domain integers; invalid/stale/unknown values retain bounded raw sentinels
without making them usable. Value is bounded JSON; null is an explicit
unknown/invalid value and is never transformed into zero or false.

Raw facts have null derivation_digest and no contributors; derived_report
requires the derived form. Derived facts have source_class derived_report and require
a digest and a nonempty list of closed contributors `{fact_id, source_id,
source_epoch, sequence, receipt_epoch, expires_ms}`; every contributor uses the
same receipt epoch as the derived fact, and expiry is no later than any
contributor's expiry. Contributor identities are distinct; the selected bound applies before
traversal. Fact construction does not qualify source trust or renew freshness.
The kernel must separately compare current profile, receipt epoch, source
continuity and time against the basis before using a fact.

### Continuum reconciliation

No new top-level WCT wire kind is added. The public adapter uses WCT.02's
ObservationProposal and its existing absolute-IRI extension mechanism. The
extension key is `https://wotex.io/contracts/routines/fact/v1`; its complete
closed object carries the Fact members absent from WCT.02. The consumer supplies
a separately validated WCT.01 execution scope and optional existing evidence
references. They convey no credentials or authority.

| Fact member | WCT.02 member |
| --- | --- |
| id | proposal_id |
| thing_id, affordance_type, affordance_name, value | Same members |
| source_time | observed_at, normalized UTC; null refuses conversion as missing_source_time |
| source_time_trust, source_time_basis, source_uncertainty_ms | Closed extension members; all required even when explicitly null/unknown |
| sequence | sequence, mandatory for this adapter |
| quality | quality.routine_quality; exactly the four Fact classifications |
| unit, source_class, source_id/epoch, received_at, receipt_epoch/ms, profile_digest | Closed extension members with the same names |
| replay, continuity, expires_ms, derivation_digest, contributors | Closed extension members with the same names |

`Continuum.to_observation(fact, scope_map, evidence_maps, limits)` returns the
public Continuum observation struct. `Continuum.from_observation(wire_map,
limits)` accepts bounded JSON data; callers use Continuum's public projection
for native values before this boundary. Native foreign structs return a typed
refusal. Reverse conversion validates the entire Continuum value through its public
constructor, requires the extension and exact mapped quality, and reconstructs
the complete Fact through `Fact.new/2`. Unknown/missing required extension
fields, an unsupported quality object, absent sequence or conflicting data
reject. There is no receipt-time substitution for missing source time.
ActionIntent, ActionResult, Delivery, EvidenceReference and ExecutionScope keep
their existing meanings; protocol acceptance remains transport evidence, not
step completion or physical causation. They do not yet represent run/root
accounting; WRO.02/03 must supply that contract before an adapter can claim it.

Existing WTX/WRT/WCT meanings, limits and codecs remain unchanged. Before code,
freeze a closed native/schema representation, public constructor/error contract,
field-by-field Continuum mapping and independent vectors. Unknown executable
semantics and malformed caller-built structs must return structured errors.
No arbitrary scripts or downloaded implementation are admitted by this basis.

| Case | Requirements | Expected observation / falsifier |
| --- | --- | --- |
| WRO01-T1 | 01–02 | Independent scalar, event, fast/slow actuator and media producers share capability semantics without vendor branches; missing required contracts reject |
| WRO01-T2 | 02–03 | Offline closure/Continuum conversion round trips retain every required identity/quality; unknown required semantics never become permissive defaults |
| WRO01-T3 | 03–04 | Stale/replayed/derived values, battery dimensions, invalid sentinel, overflow and counter reset stay distinct under independent vectors |
| WRO01-T4 | 05 | Coupled properties conflict; ACK alone never satisfies reported-match completion; uncertain absolute effect is not repeated |

The constructor, schema, field-preservation and exact-conversion cases execute
in the package's basis/schema tests. Runtime completion and repeat decisions
join WRO.02 and remain separate obligations. Installed-host and physical qualification
are separate consumer evidence. Standards vocabulary source:
[TD 1.1 Recommendation, 5 December 2023](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/).
