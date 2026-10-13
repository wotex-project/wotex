# WPF.02 — Bounded profile compilation and interpretation

Version: 0.2.7. Updated: 2026-10-14. Status: accepted target.
Implementation: bounded v1 compiler, capture and report interpretation.
Evidence: independent identity/math/domain vectors and focused tests;
archive correspondence is retained in owning provenance.

## Scope and required inputs

Compile an explicitly selected external profile into an inert interpretation
plan and project supplied decoded reports into typed proposals. No library
discovers/enrolls hardware, allocates instance identity, stores canonical state,
supplies credentials or dispatches an Action.

[WPF.01](WPF.01-external-profile-language.md) owns the closed profile/definition
grammar, IDs/digests, exact rational units and caller-supplied bounds.
Core retains TD/TM/DataSchema meaning. Runtime's public
[WRT.06](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-runtime/specs/WRT.06-bounded-codec.md)
Value.validate/1 and Value.encode/1 own the C02 typed algebra: null, Boolean,
text, bytes, signed/unsigned integer, normalized decimal, ordered list and
sorted-key object. Its current bounds are 65536 output bytes, depth 8,
1024 typed nodes, collection 256 and text/bytes 4096. Those ceilings narrow any
larger profile-reader budget; unsupported binary-float/inexact representations
do not acquire a conversion by being wrapped in a descriptor.

Runtime admission/lifecycle/codec remain distinct from this pure reader.
No profile text selects a module or makes WRT.04/05 descriptors mandatory.
The external definition can be read without routines, media or a transport host.

## Explicit binding registration and compiler

**WPF02-01 — Registration.** Binding.new/2 accepts exactly id, version,
sha256, selector_schema, operations, capture_fields, raw_value_contract,
raw_value_schema and codec_contracts.
References and DataSchema constraints use WPF.01. Capture_fields is a sorted
unique list of ≤64 local field keys; operations use TD 1.1 vocabulary; codec
contracts are exact immutable references. Raw_value_contract is the installed
exact decoder/output-contract reference selected by this binding/selector;
Raw_value_schema is supplied inline and validated under WPF.01's supported
DataSchema subset; it checks decoded logical C02 values before normalization.
Registration sha256 is recomputed from UTF-8 wotex.profile.binding@1 plus
newline and core deterministic JSON of the complete normalized registration
excluding sha256. A changed schema/selector/operation cannot reuse that digest.
The consumer independently qualifies this registration's correspondence to its
raw_value_contract; constructor integrity cannot establish that qualification.
This is explicit trusted consumer input, never registration obtained from the
profile. The binding owner supplies
closed selector semantics and independent input/output/error vectors.

A selector can name a protocol register/object/attribute or payload field within
that installed grammar. It cannot contain a target IP, account, credential,
process selector, filesystem path, command/module name or executable template.
The consumer resolves instance routes/allowed resources separately. A genuinely
new selector/operator/API needs binding code and an owning producer contract.

The compiler closure is exactly definitions, bindings and contracts. Definitions
and bindings are arrays of revalidated WPF values within max_definitions/
max_bindings; contracts is a sorted unique array of exact consumer-supplied
installed behavior/codec/raw-value contract references, ≤max_dependencies.
No contract reference loads its implementation. The consumer freezes/validates
its owner-provided schema/compatibility and supplied registration before use.
Required contract references not in this explicit installed set refuse.
Profile/definition references match recomputed semantic identity; custody/approval
retain their raw-byte identity separately. Native-map constructors cannot claim
original byte identity, and cannot satisfy a consumer raw-artifact pin.

**WPF02-02 — Check and compile.** Compiler.check/3 takes Profile,
explicit Definition/Binding/Contract closure and Limits. It revalidates the
profile and supplied values, exact reference/closure identities, installed
required mechanics, selectors, operations, raw/normalized schema and unit/
quantity-kind correspondence without capture or transport I/O. It returns
{:ok, checked} or the same WPF.01 Error. Checked contains exactly profile_sha256,
closure_sha256, compiler_ref, binding, channel_plans and limits_sha256; the first
five use the projection meanings below. Limits_sha256 is SHA-256 of UTF-8
wotex.profile.limits@1 plus newline and core deterministic JSON of Limits.
Checked is inert; it cannot establish model truth, approval or physical support.
[WPF.03](WPF.03-profile-authoring-contract.md) consumes this same checker.
Required unsupported channels/closure refuse; optional exclusions remain explicit.

Compiler.compile/4 always revalidates the same static checks and takes Profile, explicit
Definition/Binding closure, current immutable capture and Limits, returning
{:ok, Projection} or WPF.01 Error. Capture is exactly binding reference,
capture_epoch (32 lowercase hex), fields (bounded object over capture_fields)
and digest (SHA-256 of the consumer-supplied capture projection).
Each fields value is a revalidated bounded text/Boolean/signed/unsigned C02
scalar matching WPF.01 fingerprint comparison; no primitive/node coercion.
Capture digest uses core deterministic JSON of binding/capture_epoch/fields,
excluding the digest field, and is independently recomputed before matching.
Fingerprint matches only these supplied fields. No network or source-authenticity
claim follows from compilation.

Projection contains exactly profile_sha256 (WPF semantic identity), closure_sha256, capture_digest,
capture_epoch, binding reference, compiler_ref and sorted channel_plans.
Closure_sha256 is SHA-256 of UTF-8 wotex.profile.closure@1 followed by newline
and core deterministic JSON of sorted exact selected references, including the
profile, definitions, binding and installed required contracts. Compiler identity
is separate, not silently folded into raw profile identity.
Compiler_ref is the installed exact compiler-contract identity. Consumer
producer-release/archive pins remain separate; this contract digest is not
the digest of executable code or a Hex archive. Channel plans retain
original channel/affordance IDs, descriptor/reference/selector/conversion,
supported operations and unsupported optional interpretation reasons.
A required unsupported channel/closure refuses the whole compilation. Optional
channels are explicitly excluded; no unknown action becomes an empty success.
Projection emits no automatically registered TD, control route or timer.

Compile only reachable selected definitions; unrelated catalogue entries are
not a dependency. Expand at most max_dependencies references and max_nodes
nodes, memoizing each exact reference once; conflicting identities/cycles refuse.
The consumer supplies immutable offline bytes/values; no URL fetch or solver.

## Reports, normalization and outputs

**WPF02-03 — Report.** Interpreter.project/3 takes Projection, one
decoded Report and Limits. Report has exactly channel_id, profile_sha256,
binding reference, capture_epoch, source_ref, source_epoch, sequence, source_time,
receipt_time, continuity, quality, quality_reason and value. Ref/epoch/digest use WPF.01/02.
Source_ref is opaque ≤128 bytes; source_epoch is 32 lowercase hex; sequence is
canonical uint64 or null. Source_time is null or exactly utc (RFC3339 UTC),
trust (trusted/untrusted/unknown), uncertainty_us (nonnegative uint64 or null).
Receipt_time is exactly epoch (32 lowercase hex) and monotonic_us (signed-64
canonical string). Continuity is unknown/baseline/continuous/gap/retained/replayed;
quality is usable/invalid/unknown/stale. Quality_reason is null or
missing/device_invalid/profile_sentinel/source_gap/stale/unsupported; no foreign
text. Trusted source time requires nonnull uncertainty; absent/untrusted time
never becomes trusted. Value is a revalidated C02 node.

These are supplied facts, not facts made authentic by a constructor. Absent
sequence/time remains null; the reader never reads now, repairs a source clock
or makes receipt time refresh retained/replayed source data. Changed
profile/binding/capture basis refuses stale_basis before projection.

**WPF02-04 — Mechanical interpretation.** The selected profile owns the raw
mapping assertion; an installed codec owns binary framing/type decoding.
The reader first revalidates C02 syntax and the installed binding raw-value
contract. It checks explicit quality/missingness and invalid_values before
conversion; matching a raw sentinel yields null/invalid and profile_sentinel.
For a usable value, apply the selected table/affine root mapping, then validate
the normalized result against the semantic target schema and range. Never test
raw ADC counts against a Celsius target range before conversion. Table matching
uses exact canonical C02 nodes, with no coercion/unmatched default. Affine/table
conversion targets only a root scalar in this first profile; lists/records remain
structured unconverted values unless separate channels supply scalar projections.
No automatic calibration, occupancy inference, smoothing, threshold, alarm,
range clipping, missing-to-zero conversion or action occurs.

Arithmetic admits numeric integer/decimal input only. Decimal exponent must be
-18..18 for affine arithmetic; exact intermediate numerator/denominator magnitude
has at most max_numeric_digits decimal digits. Numeric schema constraints are
subject to the same exponent/digit bound before arithmetic. Enforce each multiplication and
addition before allocation, with at most eight rational operations per leaf.
The output must fit the C02 coefficient/exponent grammar exactly; otherwise
inexact_conversion/numeric_limit. Compare against supplied domain constraints
using exact arithmetic, never a binary-float tolerance. Unsupported schema/shape
refuses; an explicit invalid/missing report becomes a null value with its original
quality/reason, never usable zero/false. No library-defined sensor-name rules exist.

Unit.convert/4 takes value, supplied source Unit, target Unit and Limits.
It requires equal supplied quantity kind/dimension, applies their exact rational
coordinate maps and obeys the same budgets. Unknown quantity IDs do not imply
unknown mathematical operators; the installed operator set stays finite.

C02 bytes stay opaque inspection data unless an exact separately supported
semantic projection exists; do not call them ordinary DataSchema text or decode
base64 as a domain value implicitly. Invalid/unknown quality bypasses target
value validation while retaining its original quality/reason and a null normalized
value. That is a missing observation, not a valid numeric sample.

**WPF02-05 — Proposal.** Output contains exactly channel_id, affordance,
semantic reference, unit, normalized_value, quality, quality_reason, continuity, source_ref,
source_epoch, sequence, source_time, receipt_time, profile_sha256, closure_sha256,
capture_digest, compiler_ref and interpretation. Interpretation is profile_declared
or unconverted, never authenticated/qualified. Preserve source/quality provenance;
normalization does not establish physical truth or freshness. The proposal is
inert. A consumer rechecks current definition/profile/enrollment before accepting
it into canonical state or authorizing dependent work.

`Proposal.new/2` and `Proposal.to_map/2` revalidate this exact 18-member
string-keyed map or a native Proposal containing only `data`, under complete
WPF Limits. They check references, digests, Unit, C02 syntax and the same source,
receipt, quality and continuity grammar as Interpreter. Affordance contains
exactly kind (property/action/event) and name (the WPF local-key grammar).
Non-usable quality requires normalized_value null and interpretation unconverted;
usable quality requires a non-null value and null quality_reason. No schema or
custody claim is reconstructed from these fields: this constructor verifies
representation only. It cannot establish that Interpreter produced the map.

`Proposal.identity/0` returns the installed representation reference with ID
urn:wotex:profiles:proposal, version 1.0.0 and lower-hex SHA-256 of
`wotex.profile.proposal-contract@1`, newline and core deterministic JSON of the shipped
priv/contracts/proposal.json manifest. This is a contract identity, separate from
the consumer's selected source/archive digest. Interpreter continues returning
the same map and validates it through Proposal before returning success.
Unknown fields, malformed/foreign structs and inconsistent quality refuse
invalid_input; selected envelope/numeric limits retain input_limit/numeric_limit.

## Changes and implementation entry

Replacing profile, definition, binding/codec/compiler, source/capture epoch or
required closure invalidates its Projection. There is no implicit replacement,
fallback, guessed alias or old-plan continuation. A consumer may retain old
history and compute a new projection from explicitly selected current inputs.
Same input/limits produces the same result; private routes are not part of its
public output. Trust approval, selection and physical qualification remain
separate consumer operations.

Freeze all public schemas/signatures and independent byte/math vectors before
code. A selector requiring I/O belongs to its installed adapter; this reader
can only plan it. Codec modules are explicitly passed to Runtime by the consumer,
not loaded by Compiler. Bulk waveform/media data uses a separately selected
stream profile; the 64-KiB C02 output is not an unbounded blob escape.

| Case | Requirements | Stimulus and falsifier | Evidence |
| --- | --- | --- | --- |
| WPF02-T1 | 01–05 | External multi-channel industrial profile and another consumer's unseen quantity; same decoder/operator set | Independent archive, no model branches |
| WPF02-T2 | 01–02 | Ambiguous/changed capture, unregistered selector/codec, missing closure and optional/required unsupported channel | Exact refusal/exclusion; no route/callback |
| WPF02-T3 | 03–05 | Retained/replayed/stale/invalid reports, null source time and changed epoch | Provenance preserved; no fabricated freshness/truth |
| WPF02-T4 | 04 | Independent rational vectors, dimensions versus quantity kinds, extrema/inexact/overflow and nested schemas | Exact value or bounded error, no rounding/clipping |
| WPF02-T5 | 01–05 | Replace/revoke basis between compile/project/use; large selected closure and unrelated catalogue | No stale acceptance, no catalogue scan/hidden fetch |

The [completion plan](../plans/wotex-profiles-completion.md) keeps these obligations
separate from software, installed and actual device evidence.

Numeric DataSchema literals use WPF.01's lossless normalized-decimal admission.
Mechanical comparison converts their checked canonical decimal spelling to an
exact rational, under the selected exponent/digit budget, before comparison.
It does not compare a C02 decimal with an approximate IEEE float threshold.


## Exact unit-arithmetic freeze

`Unit.convert/4` revalidates its complete Limits, source/target Units and C02
value. The selected byte/depth/node envelope covers the two coordinate maps
and value together. Quantity URI and dimension must both match, or conversion
refuses `unsupported_semantics` at `/unit`. A valid nonnumeric C02 node refuses
`unsupported_semantics` at `/value`; malformed C02/native inputs refuse
`invalid_input`. Numeric decimal input exponent outside -18..18 refuses
`numeric_limit`. There is no primitive/float coercion.

Calculations use reduced integer fractions. At every operation, numerator
absolute magnitude and positive denominator must be at most
10^max_numeric_digits-1. Multiplication cross-cancels reduced fractions before
checking either integer product. Addition uses the denominator gcd and checks
each cross product, common denominator and signed sum before allocation, then
reduces. A refused intermediate is not retried in a different operation order.
The fixed coordinate calculation uses multiplication, addition, subtraction
and division: at most eight rational operations including representation work.
No Decimal precision context, float tolerance or ambient rounding policy applies.

Output has a deterministic representation: an integral result in signed-64 is
`sint`; an integral positive result above signed-64 but within uint64 is `uint`.
Other exactly representable results are normalized C02 decimals, including
integers beyond uint64 whose normalized signed-64 coefficient fits. A denominator
with a prime factor other than 2 or 5 refuses `inexact_conversion`. Work or
C02 coefficient overflow refuses `numeric_limit`; zero is normalized as sint 0.
Finite decimal conversion factors denominator powers using bounded integer work,
and output is revalidated through public C02 validation. This representation
rule applies to converted values; unconverted interpretation preserves its
original C02 type. No field is a physical calibration claim.

Independent exact Fraction vectors in `priv/vectors/unit-conversion.json`
freeze identity, fractional scales, positive/negative offsets, temperature
coordinate changes, incompatible quantity/dimension, repeating fractions,
coefficient overflow and caller-selected arithmetic limits before code.


Executed exact-unit and two-consumer evidence is retained in
[the arithmetic milestone](../provenance/exact-units-2026-10.md). This establishes
Unit.convert/4, not compiler, report interpretation or admission completion.


## Compiler and interpreter value freeze

The following is implemented bounded v1 behavior. The native
backing values are explicit immutable input, never a private registry or
claim of source/device authenticity.

| Public value | Exact native fields besides struct tag | Checked data |
| --- | --- | --- |
| Binding | data | WPF02-01 registration, including its verified sha256 |
| Capture | data | binding, capture_epoch, fields, digest |
| Checked | data, inputs | WPF02-02 six checked fields |
| Projection | data, inputs | WPF02-02 seven projection fields |

Checked inputs contain exactly profile, closure and limits. Projection inputs
contain exactly profile, closure, capture and limits. These retain normalized
WPF input maps, not paths/callbacks or original-byte custody claims. Limits are
the complete selected WPF.01 map. `Checked.to_map/2` and `Projection.to_map/2`
require those exact native shapes, revalidate retained input and regenerate
through Compiler using the same limits. A changed limit selection or mismatch
between supplied data and regenerated data refuses stale_basis. Unknown/native
fields refuse invalid_input. Serialization returns only data; a serialized
projection alone is inert inspection data and cannot replace the native inputs
needed by Interpreter. The consumer must recompile from its current inputs.

`Binding.digest/2` accepts the exact WPF02-01 registration minus sha256 and
returns its computed digest, enabling an installer to prepare a registration
without bypassing its checker. `Binding.new/2` requires the complete registration
and refuses reference_conflict for a syntactically valid but different digest.
`Binding.to_map/2` and reference/2 revalidate; native fields are never trusted.
Binding operations are sorted unique TD 1.1 strings, including Thing-level
strings if declared; a channel still selects only operations of its own kind.

`Capture.digest/3` accepts exactly binding, capture_epoch and fields, plus the
selected Binding and Limits, and computes the WPF02-02 capture digest.
`Capture.new/3` accepts the complete four-field capture and verifies that digest.
`Capture.to_map/3` revalidates the native one-data-field value. Fields are a
subset of the selected binding's capture_fields, with no unknown keys and only
fingerprint-compatible C02 scalar nodes. A missing fingerprint operand yields
fingerprint_mismatch, never an inferred value. A supplied binding mismatch is
stale_basis; malformed capture/foreign field errors point at the known parent.

`Compiler.identity/0` returns the exact reference for the frozen compiler ABI
manifest in priv/contracts/compiler.json. Its id is urn:wotex:profiles:compiler,
version 1.0.0, and digest is SHA-256 of wotex.profile.compiler@1 plus newline
and core deterministic JSON of that manifest. This compile-time literal
contract identity starts no process and reads no runtime file. It is separate
from the consumer's actual installed artifact/source identity and qualification.
Changing these semantic mechanics requires an explicit ABI manifest successor.

The closure is exactly definitions, bindings and contracts. All explicitly
supplied entries receive bounded structural/native validation before use; the
caller selects that array outside the compiler. Only reachable references enter
the compiled closure identity and dependency traversal, so adding unrelated
valid entries does not change a projection. Duplicate id/version keys, including
cross-kind aliases, refuse reference_conflict. An existing key with a different
exact digest also refuses reference_conflict; an absent key refuses
missing_reference. Requires may select definitions or installed contracts;
profile.binding separately selects its one Binding. Binding raw_value_contract
and codec_contracts, and nonnull definition behaviour, must be exact references
in the explicit installed contracts. No reference selects or loads code.

Reference traversal includes profile, selected binding, reachable definitions
and installed contracts within max_dependencies, memoizing an exact reference
once. Reachable definition cycles always refuse cyclic_reference, including
optional channels; they are malformed closure, not an unsupported mechanic.
The common input budget applies to the whole normalized input envelope. It
bounds admitted nodes, not a claim that each public validator visits a node
only once. Output construction stops before exceeding the same selected
byte/node/depth envelope; channel plans cannot expand one repeated definition
into an unbounded result.

Each channel plan contains exactly channel_id, affordance, semantic, definition,
operations, selector, conversion, invalid_values, required, disposition and
reason. Definition is the normalized descriptor without annotations, or null
when an optional semantic reference is missing. Disposition is supported or
excluded. Supported has reason=null and its declared operations. Excluded has
operations=[] and one installed error-code string explaining why. No raw
foreign key/value enters reason. Plans are sorted by channel_id. Global bounds,
identity conflicts and cycles refuse before optional exclusion. Profile requires
are always required. A missing optional descriptor or unsupported optional
channel may be excluded; an equivalent required channel refuses the whole call.
An excluded report channel returns unsupported_semantics, never empty success.

Static checks validate selector instances against the selected closed binding
schema. Affine maps require numeric root raw/target schemas; tables validate
both their source literals against the raw schema and targets against the
semantic schema. Invalid sentinels must belong to the installed raw schema.
A nonnull semantic unit requires an integer/number target schema. Unconverted
schemas must have compatible root types; number/integer are compatible and
structured values are validated at report time, without subsumption guessing.
C02 byte operands are inspectable reader data but not an executable v1
DataSchema byte-domain projection: a selected channel requiring them refuses
codec_required (or is explicitly excluded when optional).

Interpreter.project/3 accepts a revalidated native Projection, one closed
WPF02-03 report map and the same selected Limits. It returns {:ok, proposal_map}
or Error; proposal_map has exactly WPF02-05 fields. It regenerates projection
before checking report identity, then validates the report's closed fields and
C02 syntax. Usable quality requires quality_reason=null. Other declared quality
states retain their original reason and produce null normalized_value, bypassing
raw/target instance-domain validation; their interpretation is unconverted.
No invalid sample is relabeled usable because it happens to fit a schema.

For usable samples, validate raw domain, test exact raw sentinels, convert when
declared, then validate target domain. A sentinel produces null/invalid with
profile_sentinel and unconverted interpretation. Domain failure is out_of_domain;
a missing table source is unsupported_semantics. Schema integer/number compares
C02 integer/decimal values as exact fractions; const/enum numbers use the same
logical equality. Strings require C02 text, never bytes. Arrays/objects retain
order, closed properties and required fields; no coercion, default or clipping.
Absent sequence/source_time remains null. Source time is a UTC RFC3339 string
at most 35 bytes, ISO year 0..9999, at most six fractional digits and explicit
Z or +00:00 offset. The parsed offset must be zero. No current-time comparison
or source-clock trust upgrade occurs. Report quality/continuity is retained;
usable plus retained/replayed/gap does not imply fresh consumer state.

Compile/check regenerate the selected closure, binding, schema and operation
checks on every call. compile additionally revalidates capture and all literal
fingerprint predicates; failure yields fingerprint_mismatch. The library
observes no current external registry or device. A replaced installed basis can
only become current through explicit new consumer input and recompilation;
old projections/proposals remain historical, inert values.


Capture identity mismatch returns stale_basis at /capture/digest; it is never
silently repaired by a constructor. Matching a newly computed digest checks
internal correspondence only. String length constraints use Unicode code points,
not UTF-8 byte count or grapheme count; the separate C02/input byte limits remain.
Instance numeric constraints and numeric const/enum equality use bounded reduced
fractions, checking cross-products before allocation. Numeric observations outside
-18..18 decimal exponent are inspectable C02 values, but a required mechanical
comparison or conversion returns numeric_limit rather than approximate comparison.


Reachable definition cycles are detected in the declared id/version graph
before verifying edge digests. Content-addressed cyclic definitions cannot be
finalized as a finite DAG; a fabricated edge hash must not hide that cycle behind
optional exclusion. Missing keys terminate that cycle inspection and are handled
by the subsequent exact-reference checks. Global cross-kind key conflicts still
refuse before graph inspection; both graph passes remain memoized and bounded.


UTC parsing supports ordinary ISO seconds 0..59; leap-second spellings refuse
invalid_input. A mechanically unsupported optional channel whose semantic
closure resolves successfully retains that closure in closure_sha256. An
optional channel with an incomplete semantic closure remains excluded; its
requested reference stays bound by profile identity, without installing an
incomplete dependency set. Supplied descriptor data may remain inert inspection
information in that excluded plan. Required equivalents refuse.


Executed compiler, report and independent archive evidence is retained in
[the compilation milestone](../provenance/compilation-2026-10.md). The installed
ABI remains distinct from the exact archive/source identity in that record.
