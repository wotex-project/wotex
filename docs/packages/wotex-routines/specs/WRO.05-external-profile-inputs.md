# WRO.05 — Explicit joins from externally defined sensor capabilities

Version: 0.2.0. Updated: 2026-10-15. Status: accepted target.
Implementation: scalar representation join implemented; external execution successor planned.
Evidence: focused tests and three extracted-archive representation consumers;
consumer admission/physical qualification remain separate.

## Scope and current representation

Consume an independently supplied profile reader's inert interpretation without
making that reader depend on routines or importing a sensor catalogue here.
WRO.01 owns installed behavior, current Unit/Basis/Fact constructors and quality/
freshness/effect semantics. WRO.02 owns finite source/IR and transition proposals.
WPF.01–02 own external definitions, mechanical units and profile
interpretation; their absence is explicit unavailable producer, never a local
copy of the reader or a loosened legacy constructor.

The implemented WRO.01 first representation has seven named dimensions and
Boolean/integer/enum bases. It is one execution profile, not every possible
sensor meaning. It remains exact and narrow. Parsing an external pressure,
vector, waveform or unfamiliar semantic descriptor must not coerce it into one
of those dimensions or zero/false. Reading it outside routines remains valid
when the profile reader supports it.

## Inputs, outputs and requirements

**WRO05-01 — Registration.** Wotex.Routines.InputMapping.new/3 takes a
closed Mapping, explicit WRO.01 Registry and Limits. Mapping contains exactly the following members; every member is required:

| Members | Meaning |
| --- | --- |
| id, version, sha256 | Mapping identity; digest verifies the complete mapping except sha256 |
| semantic_ref, reader_contract_ref, compiler_ref | Exact external meaning, Proposal representation and compiler references |
| legacy_basis_ref, basis | Exact installed WRO.01 reference and complete Basis map |
| correspondence_ref | Separately installed qualification/correspondence contract reference |
| projection, enum_table | exact_integer/boolean/enum; null table except enum |
| channel_id, affordance | Exact WPF local key and closed kind/name object; property/event only |
| profile_sha256, closure_sha256, capture_digest | Exact selected reader basis digests |
| external_unit | Complete WPF Unit for integer; explicit null for boolean/enum |
| observation | Exactly source_ref, source_epoch, source_class, source_time_basis |
| receipt_clock | Exactly source_epoch, source_origin_us, target_epoch, target_origin_ms |

External references have id/version/sha256; IDs are absolute URIs ≤256 bytes,
version x.y.z with each component 0..65535 and no leading zero, digest lower
hex64. Legacy_basis_ref uses WRO.01 id/version/semantic_digest with sha256:
prefix; no invented alias changes an installed basis ID. correspondence_ref
uses the external reference shape; its exact ID/version/sha256: prefixed digest
must be installed in Registry. Registry must also contain legacy_basis_ref and
the mapping's own ID/version/sha256: prefixed digest. Computing a digest is not
installation. Mapping identity hashes UTF-8 wotex.routines.input-mapping@1,
newline and core sorted-key JSON of all members except sha256.
InputMapping.digest/3 computes that identity from an unsigned map after syntax,
Basis and correspondence validation, but without requiring its own installation.
InputMapping.to_map/3 and reference/3 revalidate exact native one-data-field
values; reference returns id/version/sha256. new/3 requires the claimed digest
and current installation. Same input/Registry/Limits is deterministic.

The selected closure contains at most 256 mappings. InputMapping.new_all/3
revalidates every selected mapping under one aggregate Limits envelope before
traversal and sorts by ID/version; duplicate IDs (including other revisions)
refuse. There is no global catalogue scan. enum_table has 1..256 closed
source/target string pairs, each nonempty UTF-8 ≤128 bytes, sorted by source,
unique source and target, and target set exactly the Basis enum alternatives.
Unknown fields/projections reject. Basis.value.type must match projection;
Basis affordance kind/name must match, its operation must be readproperty,
observeproperty or subscribeevent, and it must have no effect resource roles.
It must accept the supplied source_class. An input mapping cannot install a write.

Reader_contract_ref must equal public WPF Proposal.identity/0. Compiler_ref is
an exact supplied compiler reference, separately installed through this qualified
mapping. WPF Limits are explicit in the projection context. Optional dependency
absence or lack of these public APIs returns missing_producer; ordinary routine
construction and ordinary profile reading remain independent.

observation.source_ref uses the reader's ≤128-byte string grammar;
source_epoch and receipt_clock.source_epoch are lower hex32. source_class is
one of the WRO.01 source classes. source_time_basis is null or a WRO digest;
trusted proposal time requires a non-null installed correspondence here.
receipt_clock.source_origin_us is a canonical signed-64 decimal string,
target_epoch is a nonempty WRO string and target_origin_ms a nonnegative WRO
integer. This explicit clock correspondence is consumer qualification data.

Integer units must have the SI dimension vector corresponding to the selected
legacy dimension: temperature [0,0,0,0,1,0,0]; fraction all zero; illuminance
[-2,0,0,0,0,0,1]; power [2,1,-3,0,0,0,0]; energy [2,1,-2,0,0,0,0]; time
[0,0,1,0,0,0,0]; electric_potential [2,1,-3,-1,0,0,0]. This checks dimension,
not quantity equivalence: the qualified installed mapping must additionally pin
the exact quantity URI, semantic reference and scope. No quantity-name catalogue
is added. External units/meaning cannot substitute after installation.

The consumer installs a separately qualified exact semantic correspondence:
quantity kind, unit/dimension, operation/report/effect scope and profile/compiler
basis must agree with the legacy basis. Same numeric type/dimension or a name
match alone is insufficient. No mapping supplies a route, module, policy grant,
new operation or decoder. Digest equality is not qualification.

**WRO05-02 — Input bridge.** Input.project/4 takes the WPF.02 Proposal,
InputMapping, explicit observation metadata and selected Limits/Registry.
The fourth argument is a closed string-keyed context with exactly registry, limits and reader_limits,
revalidated WRO.01 values and complete WPF Limits. Observation metadata contains exactly the WRO.01 Fact members other than value,
unit and quality; all are required and their types/bounds are inherited unchanged. In particular the
consumer supplies enrolled thing/affordance identity, source class/epoch/sequence,
receipt UTC/epoch/monotonic coordinates, source-clock trust/basis/uncertainty,
profile identity, replay/continuity, expiry and derivation/contributors. The bridge
does not invent clocks, trust, timestamps or receipt freshness.

Revalidate Proposal through its public constructor before deriving anything.
Require exact matching channel/affordance/semantic/profile/closure/capture/compiler,
source_ref/epoch/class, profile_digest (sha256: plus profile_sha256), and source
sequence. Null sequence is unsupported_representation; an unsigned counter above
WRO max_integer is unsupported_representation. Source time compares UTC instants
and exact trust; metadata source_time_basis equals the mapping. Null source_time
requires null metadata time, unknown trust and null basis/uncertainty. A supplied
uncertainty string u is preserved as ceil(u/1000) milliseconds, checked against
WRO bounds; null stays null. No other rounding is allowed.

Receipt epoch must equal receipt_clock.source_epoch. Compute delta as supplied
monotonic_us minus source_origin_us; delta must be an exact multiple of 1000.
metadata receipt_epoch must equal target_epoch and receipt_ms must equal
target_origin_ms + delta/1000, nonnegative and bounded. Inexact conversion
refuses inexact_conversion; different coordinates refuse stale_basis. received_at
and expires_ms remain explicit consumer data validated by Fact, with expiry not
before receipt; this bridge does not relate UTC to monotonic time implicitly.

Map continuity exactly: continuous -> continuous/fresh; baseline -> baseline/fresh;
gap -> lost/fresh; retained -> lost/retained; replayed -> lost/replayed.
unknown continuity refuses unsupported_representation. Metadata must match that
continuity/replay pair. Retained/replayed data cannot become fresh. Metadata
thing identity, fact ID, receipt UTC, expiry and derivation/contributors are
consumer-owned; Fact validates them, and the result retains the complete reader
proposal digest so fields without a WRO counterpart remain inspectable.
quality_reason and interpretation remain in that witnessed proposal; a Fact does
not invent fields for them. Differences refuse stale_basis. Current enrollment,
source trust, active-set and dispatch checks remain consumer-owned transactions.

For exact_integer, C02 numeric input must have exact in-range integer projection
under the mapped WRO.01 Unit; no rounding or dimension relabeling.
Use WPF Unit.convert/4 with source external_unit and a target Unit retaining
its quantity/dimension and the reduced affine coordinates of Basis.value.unit.
Accept only exact in-domain integers within WRO max_integer. Booleans require
C02 boolean; enum requires C02 text with an exact table match. Other C02 types
refuse unsupported_representation. Non-usable quality returns null without value
conversion, retaining that quality and the validated mapped Unit. Boolean and
enum obey their installed exact correspondence. Unknown/stale/invalid quality
retains that classification under WRO.01; it cannot become usable zero/false.
Invoke the public Fact/Basis constructors and revalidate forged values.

**WRO05-03 — Honest result.** Success returns exactly fact, source_proposal_sha256,
mapping_ref and correspondence_ref, all inert; the Fact is a WRO.01 value.
Failure returns a structured Error with code invalid_input, input_limit,
unsupported_mapping, unsupported_representation, missing_producer, stale_basis,
inexact_conversion or incompatible_dimension, with redacted known-field path.
No physical qualification, Store acceptance or dispatch follows.

Source_proposal_sha256 is SHA-256 of UTF-8 wotex.routines.input-proposal@1,
newline and core deterministic JSON of the complete revalidated WPF proposal.
Correspondence_ref comes from the explicit qualified Mapping, never inference.

A parsed external definition without executable correspondence can be inspected
but cannot enter a predicate/control model as a supported fact. Unsupported cases
remain observable to authoring UI rather than compiling into no-ops. No routine
kernel dependency is imposed on ordinary telemetry/profile reading.

**WRO05-04 — Evolution and replacement.** New quantity/data shape support using
different routine representations requires a new explicitly versioned source/
basis/analysis contract, schemas and independent correspondence vectors before
implementation. External data alone cannot extend an executable operator or
model profile. That extension must permit caller-supplied semantic identities
instead of an ever-growing built-in device/sensor enum.

Until those execution profiles exist, WRO.01 retains its published target
grammar and returns unsupported. Replacing semantic/profile/compiler/mapping,
observation basis or registry invalidates the join; author/activation and final
handoff checks remain consumer-owned current transactions. No old digest/history
is edited to preserve a new correspondence claim.

## Entry and acceptance

The mapping/result schema is priv/schemas/wro-05-input.schema.json; independent
joining vectors are priv/vectors/wro-05-input.json. Freeze both before code. First prove a current scalar join and an industrial unsupported
shape; then specify a richer execution profile only when its actual operation/
analysis needs justify it. Do not move implemented types or widen dependencies
as a documentation side effect.

| Case | Requirements | Stimulus and falsifier | Evidence |
| --- | --- | --- | --- |
| WRO05-T1 | 01–03 | Independent external scalar definition/proposal plus complete metadata and qualified exact mapping | Public archive, exact WRO Fact/witness |
| WRO05-T2 | 01–04 | Pressure to power, different quantity kind, vector/binary-float and unsupported operator/profile | Explicit unsupported, no relabel/zero/no-op |
| WRO05-T3 | 01–03 | Source epoch/profile/compiler/receipt-clock mismatch, retained source and conservative uncertainty | Correct provenance/refusal, no renewed freshness |
| WRO05-T4 | 01–04 | Changed definition/mapping before evaluation/handoff, over-budget closure and missing reader | Bounded refusal; current consumer guards still required |
| WRO05-T5 | 01–04 | Industrial and independent second consumer, reader used with routines absent | Separate catalogues/policy; no package catalogue/mandatory engine |

The two scalar archive consumers and optional-producer-absent consumer establish
software representation and join behavior. Focused suites exercise exact
conversion, forged values, aggregate limits, replacement, replay and clock
refusals. They do not establish consumer installation or device qualification.
Exact commits, archives, locks and executed checks are retained in
[the software evidence](../provenance/profile-inputs-2026-10.md).
The
[completion contract](../plans/wotex-routines-completion.md) owns the join stage.

## Reader-to-execution successor

**WRO05-05 — Complete execution join.** The
[external input execution contract](external-input-execution-v1.md) defines
explicit missing receipt UTC, a separately selected conservative receipt-clock
projection and a qualified external binding for Snapshot/Edge. These additions
are planned. Existing scalar representation/archive evidence does not establish
that a joined Fact is usable by the public evaluator or kernel.

| Case | Requirements | Stimulus and falsifier | Evidence |
| --- | --- | --- | --- |
| WRO05-T6 | 01–05 | Complete public reader/Input/binding/Compiler/Snapshot/Kernel and edge traces, unaligned receipt, missing UTC and changed mapping | EIX-T1–T6; planned, no identity rewrite or fabricated clock/edge |
