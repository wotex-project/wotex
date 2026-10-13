# WPF.01 — External device profiles and semantic descriptors

Version: 0.2.3. Updated: 2026-10-13. Status: accepted target.
Implementation: bounded v1 reader. Evidence: reader/structural-schema suites
and two isolated archive consumers; WPF.02 closes selected-closure/selector
checks separately.

## Scope and ownership

The optional `wotex_profiles` library reads explicitly supplied
device-profile and semantic-definition data. It owns their grammar, bounded
validation and deterministic identity, not the definitions of all sensor types.
Consumers own profiles/model templates by default, in their own release or
private custody. Optional publisher exports are explicitly imported data, not
a required shared catalogue/repository. Consumers own model/firmware data,
quantity meanings, compatible notices and physical evidence. WoTEx ships the reader,
standard protocol vocabulary and minimal conformance vectors. No global model
catalogue, sensor enum, lookup service or automatic registration is introduced.

Core owns TD/TM/DataSchema/Form values; Runtime owns interaction ports and its
WRT.06 inert typed-value algebra. [WPF.02](WPF.02-profile-interpretation.md)
owns explicit closure joins, mechanical interpretation and neutral proposals.
[WPF.03](WPF.03-profile-authoring-contract.md) owns installed-contract export,
draft identity finalization and shared diagnostics for manual/AI authoring,
CI and import. Generation and consumer approval remain outside.
External names never resolve to a module, network destination or executable.
The family [allocation decision](https://github.com/wotex-project/wotex/blob/main/docs/architecture/profile-and-stream-boundary.md)
keeps consumer policy, identity, credentials and storage outside the reader.

The independent optional package is registered in the source/tooling catalogue.
Its reader constructors are implemented; compiler/authoring evidence is
separate. No installed profile gains support merely because a document parses.

## Representations and limits

All constructors revalidate native structs and return tagged values/errors.
Unknown/duplicate fields, invalid UTF-8/NUL, cyclic native input, nonfinite
numbers and unsupported discriminators reject before interpretation. Objects
are closed except the explicitly bounded inert annotations map. No constructor
reads a clock, environment, file, network, catalogue or random source.

| Value | Exact representation |
| --- | --- |
| Identifier | Nonempty absolute URI, ≤256 UTF-8 bytes; opaque supplied identity, never an atom or fetched URL |
| Version | ASCII SemVer major.minor.patch, each component 0–65535, no prefix/leading zero/prerelease; label alone is not integrity |
| Reference | Exactly `id`, `version`, `sha256`; digest 64 lowercase hex; profile/definition references use WPF01-04 semantic identity, installed binding/behavior/codec references use their owner's exact contract identity |
| Local channel/role key | ASCII `[a-zA-Z0-9._-]{1,128}`, unique within its owning object |
| Integer coefficient/counter | Canonical decimal string; signed/unsigned 64-bit as stated, no +, leading zero or -0 |
| Annotations | Optional flat string map, ≤16 keys/8192 encoded bytes, each value ≤1024 bytes; display/provenance only |
| Limits | Explicit positive integers for max_bytes, max_depth, max_nodes, max_channels, max_definitions, max_bindings, max_dependencies and max_numeric_digits |
| Limit ceilings | Respectively 1048576, 16, 100000, 1024, 1024, 64, 1024 and 128; no omitted/ambient defaults |
| Closure | Only definitions/bindings reachable from the selected profile; every reachable reference exact and present; cycles reject |

A limit is a per-call selected-closure budget, not a worldwide sensor count.
A consumer pages/selects external data before calling the reader. Large catalogues
are never implicitly scanned, downloaded, installed or retained.

**WPF01-01 — Profile.** `Profile.parse/2` and `Profile.new/2` under
`Wotex.Profiles` accept exactly format, id, version, binding, fingerprint,
channels, requires and optional annotations. Format is `wotex.profile@1`;
binding/requires are References. Requires are unique and sorted by id/version;
profile uses one installed binding. Channels are 1..max_channels and sorted by
local id. Duplicate references with changed bytes reject reference_conflict.

Fingerprint is 1..32 closed predicates, each field, operator, values. Field is
an installed binding's declared capture-field key; operator eq has one value,
one_of has 1..32 unique values. Values are bounded text/Boolean/signed/unsigned
C02 nodes. All predicates must match supplied current capture. There is no regex,
range guessing, executable match function or profile-authored instance evidence.
A match constrains a candidate; it does not authenticate/enroll it.

Each channel has exactly id, affordance, semantic, operations, selector,
conversion, invalid_values, required. Affordance is exactly kind (property/action/event) and
name (nonempty ≤128 bytes); semantic is a Reference. Operations are sorted unique
TD 1.1 operation strings compatible with that kind. Selector is an object
validated against the explicitly installed binding's closed selector schema.
Required is Boolean, no default. Conversion is null or one of the closed maps below. Invalid_values is an
explicit array of 0..32 unique bounded C02 scalar nodes compared before conversion;
it contains no default, expression or inferred zero.
Unknown optional metadata cannot add an operation or channel.

**WPF01-02 — Definition.** `Definitions.new/2` validates an explicitly supplied
array of closed semantic descriptors: format, id, version, value_schema, unit,
behaviour, requires and optional annotations. Format is `wotex.semantic@1`;
value_schema is a bounded core DataSchema value, unit is null or WPF01-03,
behaviour is null or an exact separately installed behaviour Reference.
No library table assigns meaning from id/title. A new supplied quantity URI
requires no reader edit; accepting it in an application is a consumer decision.

Mechanical v1 validation supports type, enum, const, numeric lower/upper/multiple
bounds, string lengths, array items/lengths, object properties/required and closed
additionalProperties. Type is one core scalar/object/array type; additionalProperties
is false for an interpreted object. Schema title/description and read/write/observe
annotations are inert. Pattern, format execution, recursive/remote references,
conditional schemas and unknown required validation operators reject
unsupported_schema. Optional extensions belong in annotations, never silently
ignored as validation. A later mechanical operator requires its own version,
vectors and implementation; data does not enable it.

A descriptor's read interpretation can be structurally supported while its
behaviour is unsupported. An unsupported required behaviour refuses executable
use; inspection may retain it as an inert definition. A shape does not authorize
a write, infer a safety class or establish the descriptor's physical truth.

**WPF01-03 — Units and quantities.** A nonnull unit contains exactly
quantity_kind, dimension, scale_n, scale_d, offset_n, offset_d. Quantity_kind
is an explicit URI, never a built-in sensor enum. Dimension is seven integer
exponents -32..32 in order metre, kilogram, second, ampere, kelvin, mole, candela.
Scale_n and both denominators are positive canonical signed-64 strings; offset_n
is signed-64. Reduced rational pairs are canonical; denominators positive.
Canonical coordinate of x is x*scale_n/scale_d + offset_n/offset_d.

Conversion requires equal quantity_kind and dimension, not dimension alone.
Absolute/gauge/differential pressure or temperature/difference remain distinct
when their supplied quantity kinds differ. Dimensionless quantities likewise
retain their meaning. No sensor calibration or battery-charge curve is inferred.
Non-SI/custom/nonlinear representations may be retained as unconverted typed
data; an executable conversion needs a separately installed exact contract.

Affine channel conversion contains exactly kind (affine), scale_n, scale_d,
offset_n, offset_d using those rational rules. It maps decoded raw numeric value into the semantic descriptor's
declared coordinate. It is a publisher assertion whose physical correctness
needs independent consumer qualification, not a unit-derived proof.
No scripts, expressions, lookup URLs or arbitrary byte-write templates exist.

Table channel conversion contains exactly kind (table) and entries, 1..256
objects each exactly source/target bounded C02 scalar nodes. Sources are unique
by C02 canonical encoding and sorted by that encoding; unmatched input returns
unsupported_semantics, never identity/zero. This finite literal mapping performs
no script, callback, unit inference or new operation. Numeric schema constraints
used by mechanical arithmetic obey WPF.02's exponent/magnitude bounds before
comparison; a syntactically valid giant exponent cannot force unbounded work.

**WPF01-04 — Identity and provenance.** Raw identity is SHA-256 of original
bytes. Semantic identity is SHA-256 of UTF-8 `wotex.profile.semantic@1\n`
or `wotex.definition.semantic@1\n` followed by the core's deterministic
sorted-key JSON encoding of the normalized value excluding annotations.
This is not an RFC 8785 claim. Ordered arrays preserve their declared order;
sets are validated sorted before hashing. Store/compiler/codec/qualification
identities stay separate. A provenance string or matching hash proves no trust.

## Public results and failure

Reader constructors return {:ok, value} or
{:error, %Wotex.Profiles.Error{code, path}}. Codes are invalid_input,
input_limit, unsupported_format, unsupported_schema, reference_conflict,
missing_reference, cyclic_reference, unsupported_binding, unsupported_selector,
unsupported_semantics, fingerprint_mismatch, inexact_conversion, numeric_limit,
out_of_domain, stale_basis, codec_required, invalid_contract and report_limit.
The last two belong to WPF.03 authoring artifacts/results. Paths contain installed field
names/numeric indexes only; unknown supplied keys report their known parent.
No raw value, device identity, path/URL or foreign exception appears in errors.

Parsing is stateless. Repeated identical input/limits yields identical output.
No schema-only success changes trust, active selection or physical qualification.

## Entry and acceptance

Before implementation, freeze schemas, canonical vectors and examples under
the new package's priv/schemas and priv/vectors. Reference public core APIs,
not internal validators. No global registry/consumer source is an archive input.

| Case | Requirements | Stimulus and falsifier | Evidence |
| --- | --- | --- | --- |
| WPF01-T1 | 01–04 | Independent unseen quantity/model definitions and reordered objects; exact identities/units, no sensor-name switch | Independent fixtures and reader/schema tests; archive provenance below |
| WPF01-T2 | 01–02 | Unknown selector/operator/required schema, duplicate/cyclic/missing closure and forged native structs | Bounded typed refusal before callback |
| WPF01-T3 | 02–03 | Same-dimensional different-kind values, invalid rational pairs and nonlinear claim | No implicit conversion or control support |
| WPF01-T4 | 01–04 | At/above every limit, giant unrelated catalogue supplied externally, secret annotations and reference URLs | Selected closure only, no fetch/load/logging |
| WPF01-T5 | 01–04 | Two independent consumers build values from their own profiles without a shared repository, routines or runtime host | Two isolated archive consumers; provenance below |

All cases are obligations. The [completion plan](../plans/wotex-profiles-completion.md)
owns order; no example establishes actual device support.

## Executable reader freeze

Profile and Definition native values contain exactly data, raw_sha256 and
semantic_sha256. Parse retains SHA-256 of the original bytes; new(map, limits)
has explicit null raw identity. Neither native field is trusted on reuse:
revalidate data and recompute semantic identity, and never accept a native
constructor as evidence of original bytes. Definitions.new/2 returns sorted
Definition values and refuses duplicate id/version or conflicting identities.
Definition.new/2 and parse/2 are the corresponding single-descriptor seams.
Profile/Definition.to_map/2 return checked data; reference/2 returns the exact
id/version/semantic digest without annotations. Unit.new/2 and to_map/2 are
checked pure value constructors; conversion is separately owned by WPF.02.

No input string or key contains NUL. A common source parser applies byte/depth/
node admission and duplicate-member checks through public core JSON. Before
materialization, numeric tokens outside strings have at most max_numeric_digits
coefficient digits and six exponent digits. Numbers outside those lexical bounds
refuse numeric_limit. JSON numeric schema literals must survive normalization to
the core encoder's decimal spelling with exactly the same mathematical decimal
value. For example 1.1 is admissible while a longer decimal that rounds to 1.1
is refused, rather than weakening its threshold. Decimal literals used by the
mechanical subset have normalized exponent -18..18 and bounded coefficient
magnitude. All nonintegral source/native literals obey that normalized decimal admission.
Native float schema literals denote the exact decimal in their core
canonical JSON spelling, not a measured binary-float sample or tolerance.
C02 observations remain integer/decimal nodes; no floating sample coercion exists.

The first reader freezes the schemas as offline draft-07 documents, with no
remote references, and independent fixtures for an unseen industrial quantity
and a second consumer-owned quantity. Constructors establish structure/integrity
only. Selector membership, installed closure, capture and report interpretation
remain WPF.02 obligations; a syntactically valid selector never selects code.
Structural schema success cannot replace URI/version/order/identity/numeric and
mechanical checks. All errors retain only fixed code and installed pointer path.


### Frozen mechanical schema details

The first subset uses `minimum`, `maximum`, numeric `exclusiveMinimum` and
`exclusiveMaximum`, and positive `multipleOf` for integer/number schemas;
`minLength`/`maxLength` for strings and `minItems`/`maxItems` for arrays.
Length constraints are nonnegative integers at most 1048576, with minimum
not exceeding maximum when both are supplied. An array requires one inline
`items` schema; tuples are unsupported. An object requires an inline
`properties` map and `additionalProperties=false`; omitted `required` is an
empty set, and supplied names are sorted, unique and present in properties.
Property names are nonempty UTF-8 strings at most 128 bytes. Unknown property
names never enter an error pointer. `enum` is a unique array of 1..256 native
JSON literals; `const` is one bounded JSON literal. Numeric literals nested
within either obey the same mechanical numeric limits. Schema construction
checks operators; instance satisfaction belongs to WPF.02.

The common JSON envelope additionally caps a container at 1024 members and a
string/key at 8192 bytes (or the smaller selected byte budget). An annotation
key is 1..128 bytes; its value may be empty. Explicit null annotations reject.
Definition-array admission applies the selected byte/node/depth budgets to the
whole array before validating its members. Native reconstruction clears raw
identity even when supplied hash strings are syntactically valid; only parse
establishes the association with the exact bytes passed in that call.


Executed reader and two-consumer evidence is retained in
[the archive milestone](../provenance/reader-2026-10.md). Closure, selector and
mechanical interpretation evidence is retained in the successor
[compilation milestone](../provenance/compilation-2026-10.md), rather than
attributed to the historical reader milestone.


The WPF.01 scalar literal subset includes C02 null, Boolean, text, bytes,
signed/unsigned integer and normalized decimal. Fingerprint operands remain
only text/Boolean/signed/unsigned. Byte sentinels and finite table operands are
inert literal data; reading them does not establish a DataSchema byte-domain
projection, decode base64 into ordinary text, or make a channel executable.
Required unsupported interpretation still refuses under WPF.02.
