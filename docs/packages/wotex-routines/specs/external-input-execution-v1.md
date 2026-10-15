# External input execution join v1

Version: 0.1.1. Updated: 2026-10-15. Status: accepted successor target.
Owner: WRO.01 observation metadata; WRO.02 snapshots/edges; WRO.05 input joins.
Implementation: entry schemas/vectors frozen; runtime changes planned. Evidence: three
[public-API gaps reproduced](../provenance/external-input-execution-2026-10.md);
the successor's positive/runtime/archive acceptance has not executed.

## Result and boundaries

An exact WPF input join must be usable by the public routine evaluator and
kernel without changing its external profile identity, inventing a UTC receive
timestamp or requiring the original receive instant to align to milliseconds.
This successor closes those representation gaps. It introduces no source trust,
clock discovery, device catalogue, authority, persistence or effects.

[WRO.05](WRO.05-external-profile-inputs.md) already owns exact scalar conversion,
qualified Mapping installation, original Proposal witnesses and missing-reader
refusal. [WRO.01](WRO.01-capability-behaviour.md) owns Fact fields, explicit Limits,
source trust, units and quality. [WRO.02](WRO.02-source-kernel.md) owns regeneration,
three-valued predicates, snapshot identity, elapsed time and retained edges.
Keep external profile identity distinct from installed Basis semantic identity.
A caller still supplies the current Registry, source qualification, captured
clocks, current snapshot and state; a constructor cannot establish their truth.

## Exact additions and compatibility

**EIX-01 — Missing receipt UTC.** Fact's received_at member remains required.
Accept either its existing ISO-8601 timestamp or explicit null when receipt UTC
is unavailable. Preserve null through new/2, to_map/2, Input.project/4, snapshots,
retained state and exchange extensions. Never fill it from source_time, a
constant epoch, evaluation time, environment or a clock read. Missing member,
malformed timestamp or extra native fields still refuse. Existing non-null
normalization, field ordering and digests remain unchanged.

Receipt freshness still uses receipt_epoch/receipt_ms/expires_ms exclusively;
null UTC supplies no confidence and cannot make a stale fact current. Source
time/trust/basis/uncertainty keep their existing independent requirements.
Continuum.to_observation/4 continues to require source_time for observed_at;
null received_at is preserved in its routine extension. A fact with null
source_time still refuses missing_source_time rather than substituting receipt
UTC. No Continuum public wire grammar is widened.

**EIX-02 — Explicit conservative precision.** Preserve the existing exact
four-member receipt_clock grammar and conversion unchanged: source_epoch,
source_origin_us, target_epoch, target_origin_ms. An unaligned delta still
refuses inexact_conversion. Add one separately discriminated alternative with
exactly these six members:

| Member | Required value / bound |
| --- | --- |
| format | wotex.routines.receipt-clock@1 |
| projection | floor_millisecond |
| source_epoch | Exact WPF receipt incarnation, lower hex32 |
| source_origin_us | Canonical signed-64 decimal string; no plus, leading zero or negative zero |
| target_epoch | Nonempty UTF-8 under selected WRO Limits; no NUL |
| target_origin_ms | Integer 0..Limits.max_integer |

The host qualifies a stable correspondence between the actual source receipt
clock and target elapsed clock. Mapping construction only checks representation
and installation. Pairing an old report with current processing time is not a
qualified clock correspondence. No inferred default chooses this alternative.
Unknown format/projection, mixed grammar or extra/missing keys refuse.

Let s be the original Proposal receipt_time.monotonic_us integer and o be
source_origin_us. Require the original Proposal receipt epoch to equal
source_epoch. The only accepted metadata receipt coordinate is

`target_origin_ms + floor((s - o) / 1000)`.

Floor is mathematical division toward negative infinity, including negative
delta. Intermediate subtraction can require 65 signed bits; it must be exact.
Final coordinates must be nonnegative and within selected max_integer. There
is no float, rounding toward zero, saturation, source timestamp rewrite or
change to source_proposal_sha256. Wrong supplied coordinate/epoch refuses
stale_basis; range/overflow refuses input_limit.

For this alternative only, require metadata.expires_ms at most
projected_receipt_ms + Basis.evidence.freshness_ms, with checked bounded addition.
Its lower bound remains receipt_ms. Expiry is exclusive under ObservationView.
This prevents floor projection from extending the original receipt's lifetime;
an earlier explicit expiry is allowed. The caller must still qualify the actual
clock relation and age at collection/commit. Numeric equality is not that proof.
WRO05's Mapping member set, identity prefix and existing exact mappings remain
unchanged. The new nested clock record participates in the same full mapping
digest and installation checks; a projection change requires a new digest.

**EIX-03 — Qualified external binding.** Add public
Wotex.Routines.Input.binding_basis/3, taking Mapping, Registry and Limits and
returning {:ok, map} or WRO05's payload-free structured Error. Revalidate the
complete mapping using InputMapping.to_map/3, including its own installation,
Basis and correspondence contracts. Return exactly:

| Member | Value |
| --- | --- |
| format | wotex.routines.external-binding@1 |
| profile_digest | sha256: followed by Mapping.profile_sha256 |
| source_id | Mapping.observation.source_ref |
| source_epoch | Mapping.observation.source_epoch |
| source_time_basis | Mapping.observation.source_time_basis, including explicit null |
| input_mapping | The complete revalidated Mapping map |

Snapshot's binding_bases accepts either its unchanged four-member legacy record
or this exact six-member record. For legacy, profile_digest must still equal
the selected program binding's Basis semantic_digest. It cannot accept a random
digest or an unqualified external record merely because the Fact matches it.

For the external variant, revalidate the embedded Mapping against the regenerated
program.context.registry and selected Limits. Its legacy_basis_ref must equal
the selected program binding.basis, and its complete Basis must equal the
selected context.bases entry. All outer profile/source/clock fields must equal
binding_basis/3's reconstruction. Mapping's installed correspondence, read-only
affordance and source-class requirements remain WRO05's exact checks. Unknown
fields, digest substitution, missing installation, source drift or a different
Basis refuse; no alternate registry is taken from the snapshot.

ObservationView must compare an external Fact with this external profile/source
basis and the Mapping's source_class. Preserve the Fact's profile_digest;
rewriting it to a Basis digest is forbidden. Keep the existing Thing, affordance,
quality, replay, continuity, unit, freshness and source-age checks. A matching
representation still does not authenticate the Fact value or establish that the
caller used Input.project/4; current consumer admission owns those decisions.

**EIX-04 — Edges, history and bounded work.** Edge's retained binding_basis
accepts and fully validates the same two grammars against the current regenerated
program. Preserve the entire external record in its retained identity. A changed
binding or clock follows existing baseline-reset behavior; a stale program or
invalid old mapping follows existing typed refusal and requires the caller to
start with null prior state. Neither path may reuse an earlier positive edge.
First/baseline/reconnected/restored/retained/replayed samples never invent an
edge. Duplicate sequence and changed payload retain their existing meanings.

All constructors revalidate native structs and their full aggregate JSON limits.
Existing Limits ceilings, collection bounds and no-I/O rules remain unchanged.
An embedded mapping is charged at every occurrence; no unchecked pointer,
ambient registry lookup or unbounded memo replaces it. Deterministic retries
return equal values; there are no leases, cancellation resources or startup.
Producer absence remains missing_producer. Snapshot/edge refusals retain their
existing stale_binding_basis/stale_edge or structured validation errors.

**EIX-05 — Scope of analysis and adoption.** New representation does not certify
an existing model projection or current consumer. Analysis profiles unable to
represent an external binding must explicitly refuse their unsupported scope;
they cannot erase input_mapping or relabel unknown as false. Existing legacy
model/archive vectors retain their previous behavior. Full program/snapshot/
mapping/runtime and source/clock correspondence remains caller-owned at commit
and later handoff. No stored record is implicitly upgraded.

For a normal trace, an installed scalar Mapping has distinct external profile
and Basis digests, receipt origin 0 us/10000 ms and original receipt -1001 us.
The explicit floor record projects receipt_ms to 9998. With freshness 1000 ms,
expires_ms may be 10998; elapsed 10998 is already expired. Null received_at is
retained. A fresh, otherwise qualified source with the matching external binding
can satisfy its declared threshold, while the legacy binding cannot substitute
its Basis digest. If the clock epoch changes or the Mapping is removed from the
program Registry, refuse that join and retain no positive edge. A new qualified
source starts a new baseline; neither current processing time nor an old edge
can repair the stale input.

## Entry artifacts and acceptance

Before code, freeze the new clock/binding definitions in
priv/schemas/wro-05-input-execution.schema.json and independent vectors in
priv/vectors/wro-05-input-execution.json. Update the embedded Fact, snapshot and
edge definitions in wro-01, wro-02-program/evaluation/execution/collection,
wro-04-model/witness and wro-05-input schemas where they occur. Schemas validate
shape; public constructors additionally validate digest, installation, complete
Basis, clock arithmetic and equality. No runtime reads documentation.

| Case | Requirements | Required observation / falsifier | Level |
| --- | --- | --- | --- |
| EIX-T1 | 01 | Null receive UTC survives Fact/Input and a Continuum round trip with known source UTC; absent source UTC still refuses exchange; no fabricated timestamp | Pure/schema |
| EIX-T2 | 02 | Independent signed integer oracle at deltas -1001/-1000/-1/0/1/999/1000/1001, bounds and overflow; wrong coordinate/epoch and widened expiry refuse; old exact inexact behavior unchanged | Pure/schema |
| EIX-T3 | 03 | Actual public WPF compiler/interpreter -> Input -> binding_basis -> routine Compiler/Snapshot/Evaluation/Kernel uses known integer/Boolean/enum values and exact external identity; unchanged old snapshot grammar still works | Software |
| EIX-T4 | 03/04 | Remove installation, replace mapping/Basis/profile/source/class/clock or forge native fields; refuse or become unknown as owned, never acquire a known value from a mismatched Fact | Software/mutation |
| EIX-T5 | 02–04 | Actual public edge baseline, new continuous transition, duplicate, gap, expiry and source/clock replacement traces; no positive edge from first/restored/retained data | Software/mutation |
| EIX-T6 | 01–05 | Independent extracted-archive consumers run the complete reader-to-evaluation/kernel path with unaligned receipts and no receipt UTC; behavioral mutations to identity and rounding are detected; ordinary routines work with reader absent | Archive software |

An independent rational/integer oracle supplies expected conversion, timestamp
missingness, external identity and predicate/edge outcome. Repeating only the
adapter's own output does not establish execution correspondence. Record actual
sources, archives, locks, toolchain, commands/results and exclusions; packaging,
software vectors and a generic constructor never qualify an installed clock,
source, actuator or current consumer transaction.
