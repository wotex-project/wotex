# Verified transitions and time-stable decisions v1

Version: 0.1.7. Updated: 2026-10-16. Status: accepted target; implementation partial.
Owner: WRO.02 retained transitions/complete collection; WRO.03 time correspondence;
WRO.04 independent validation scope.
Implementation: public direct-transition and complete-decision APIs, canonical
time cells and independent complete-set arbitration have native evidence.
Independent archive consumers, complete-verifier mutations and the owning
milestone remain open.
Complete VD-T1–T14 remain unexecuted obligations.

## Result and ownership

A consumer can check a supplied Kernel transition without running the transition
engine again, then check that a complete pending decision remains eligible at a
later explicit Time. A decision includes members that contributed no proposal.
Their delayed work, Fact qualification or window can change before another
member reaches admission. Equal clock-generation strings alone cannot prove
that the earlier cut is still current.

The package owns pure bounded verification and the canonical time cell below.
The consumer supplies actual membership, immutable original/prior indexes,
current observations, qualified clocks, dispositions and artifact identities.
It owns staging, transactions, authorization, reservations, queues and handoff.
A checked decision certifies correspondence relative to supplied inputs; it
does not discover omitted membership, authenticate those inputs or authorize
any physical effect. No Store, credential, callback, process, clock read or
runtime/source-file lookup enters these operations.

Existing Compiler/Kernel/Collection/Arbitration APIs retain their shapes and
behavior. [Bounded continuation](bounded-run-continuation-v1.md) owns resume,
Time@2/Run@2, current-state satisfaction and Collection@2. This successor does
not redefine those transitions, make Collection@1 a complete pending set or
broaden the frozen Model/Analysis profiles. Point verification and current
eligibility have separate scopes; neither supplies positive consumer admission.

## Public seams, inputs and bounds

**VD-01 — Explicit verification surfaces.** Add these public operations:

| Operation | Inputs and result |
| --- | --- |
| Wotex.Routines.Transition.verify/8 | program, event, snapshot, time, prior, claimed_result, Profile, Limits; returns :ok only for the complete prescribed point transition, otherwise {:error, Error} |
| Wotex.Routines.Decision.verify_point/4 | independently supplied complete Collection@2 input, claimed Collection@2/native Collection, Profile, Limits; returns :ok or {:error, Error}; no later-time claim |
| Wotex.Routines.Decision.new/3 | complete Collection@2/native Collection, Profile, Limits; verifies point correspondence and derives the canonical cell; returns {:ok, Decision} or {:error, Error} |
| Wotex.Routines.Decision.to_map/3 | Decision/plain decision, Profile, Limits; independently revalidates the complete point, cell and digest before returning {:ok, data} |
| Wotex.Routines.Decision.check/4 | Decision/plain decision, current context below, Profile, Limits; returns {:ok, checked} only after point, current-input/time-cell and full arbitration verification |

Transition.verify/8 consumes the same explicit program/event/snapshot/time/prior
as Kernel.advance/7 plus its claimed result. It covers every supported source,
event, prior and time grammar under WRO.02, including direct removed-original
reconciliation and skipped-busy transitions. It returns no repaired or alternate
result. A typed constructor accepts representation, not current consumer authority.

Decision requires format wotex.routines.collection@2 and its exact opt-in input
wotex.routines.collection-input@2. Collection@1 refuses unsupported_decision_scope;
it cannot certify retained complete pending work. Both existing Time grammars,
Run@1/Run@2 and Edge@1/Edge@2 remain supported where their original correspondence
rules permit them. No time-format switch or Run promotion is inferred.

Use exactly the supplied twelve-member Profile and six-member Limits; there
are no new defaults or automatic increases. Embedded collection.profile and
json_limits must equal those selections. Apply semantic bounds to every source,
expanded tree, active run and all pending proposals, before grouping/cutoff.
Every full argument envelope and output must obey the selected JSON bounds,
counting each embedded input/prior/program/transition occurrence. No promise
is made that a Cartesian product of maximal documents fits one aggregate bound.

All wire data uses plain string-key objects/lists, bounded integers and valid
UTF-8. Unknown fields, duplicate identities/JSON keys, improper lists, forged
native structs/extra native members and malformed embedded values refuse.
Decision's native representation has exactly __struct__ and data. Its plain
data has exactly format, collection, cell and decision_digest. format is
wotex.routines.decision@1; collection is the complete checked Collection@2.

## Point transition and collection verification

**VD-02 — Verify the entire claimed transition.** Revalidate full Program
regeneration, event, snapshot, selected Time and original/busy/edge data before
checking the result. The claimed result has the existing exact run, proposals,
outcome, edge and basis members. Its basis must equal the complete normalized
supplied arguments, including prior and full Time, not a caller-selected digest.

Check the prescribed transition by validating the supplied before/after relation
against every applicable WRO.02 rule. Cover all paths/records and unchanged
fields, not just the proposed leaves. The checker must verify:

- New, repeated, missing-original, busy and removed-program correspondence;
  deterministic root/step originals and full Run/Edge grammar and tree coherence.
- Baseline/reset, qualified report identity, duplicate/conflict, hysteresis,
  debounce and cooldown rules. First/reconnected/retained/unqualified input
  cannot create a false edge or retain a discarded candidate as authority.
- Exact three-valued qualified observations and predicate results, including
  integer/unit conversion, source/receipt ages and external Mapping identity.
  Unknown cannot become false, zero or a no-op.
- Every selected sequence prefix, parallel all-required join, fixed conditional
  path, invoked condition/deadline, wait, delay, noop and effect transition.
  Unvisited/unchosen records cannot be edited or hide a pending proposal.
- Every admission/handoff/result/satisfied slot and digest, allowed predecessor,
  threshold/report contract and duplicate/conflict outcome. Satisfied input must
  match its actual qualified Fact without fabricated handoff. Only the owning
  satisfaction rule permits the exact Run@1 promotion.
- The nonrefundable complete spent references. Expiry is assessed against prior
  run/step deadlines before a new receipt can complete that step. Late evidence
  cannot hide expiry and enable a later path. Cancellation, failed/unknown and
  partial results retain started uncertainty and stop dependent unsent work.
- Exact outcome/reason and complete ordered newly emitted proposals, including
  every proposal field and unchanged terminal/duplicate behavior as owned by
  WRO.02 and the continuation successor.

The verifier checks supplied conclusions; it never generates a replacement
transition or silently fills omitted records. It must not delegate verification
to Kernel.advance/7, Collection.evaluate/3 or Collection.to_map/3, or to their
forward execution helpers: Execution.advance, Edge.advance, Receipt.apply,
Satisfaction.apply and Pending.paths. It must not reuse Proposal.from_step as
its sole check of the claimed proposal's fields. Shared representation validators,
public exact-unit conversion, immutable tree traversal and compiler regeneration
remain allowed; they must not execute a transition indirectly.

Checking a finite predicate or comparing required step fields is verification;
running the forward engine and comparing its returned result is replay. Keep
that distinction executable. Instrument all prohibited forward calls in an
isolated VM: valid prepared cases must still verify and forged ones must fail
through assertions rather than loader/compiler errors. Independent oracles
below must not import the verifier or production execution/qualification helpers.

**VD-03 — Verify every member before any cutoff.** Decision.verify_point/4
compares the entire claimed input to the independently supplied expected input,
then verifies Collection@2 membership/ordering/shared-resource/shared-observation
coherence and all transitions through the point checker. A nil event permits
only the existing inert nil transition and must satisfy the no-hidden-live-run
rules. A live original requires its actual continuation; a different rejected
busy trigger cannot displace that run from the cut. Busy-trigger history remains
a separate direct-transition operation owned by the consumer.

Verify each currently eligible proposed/reserved path from the checked after
Run, current conditions/invocations, fixed paths, deadlines and original window.
Reconstruct no source or run from the proposal list. Check exact sorted proposals
and one-to-one proposal_states, including reserved originals, equivalent
contributors and members with no eligible work. Count the entire pending set
against pending_work before equivalence, conflict or batch limits.

Validate the complete collection_digest using its existing canonical definition.
Rehashing an altered transition, omitted member/proposal/state, receipt or spent
reference is not valid correspondence. Decision.new/3 makes this same check
against the collection's retained input, establishing internal correspondence
only; the consumer must still provide actual independent current input at use.

## Canonical time cell

**VD-04 — Derive a finite region from the complete point.** cell has exactly
format, time_format, epoch, clock_generation, utc_generation, utc_mode, elapsed,
utc_low and utc_high. format is wotex.routines.time-cell@1. time_format is the
descriptive wotex.routines.time@1 or explicit wotex.routines.time@2 selection;
Time@1 itself remains its unchanged five-member map. epoch and clock_generation
are the point Time's elapsed identity. elapsed is a closed {min, max} integer
interval. Let M be Limits.max_integer: elapsed domain is [0,M], UTC domains
are [-M,M]. No infinity, float, implicit upper bound or encoded M+1 exists.

Derive thresholds from every entry's complete input and checked result, including
original/busy Runs, after Runs, all binding Facts/Bases and before/after Edges.
Use the whole provided membership, not eligible proposals or the selected batch.
Static invalidity, an unchosen path or an unused binding does not justify dropping
a listed threshold. Each coordinate comparison has its first integer change at
b for x < b / x >= b, and b+1 for x <= b / x > b. Compute wide intermediates
exactly; discard cuts outside that axis's domain, rather than wrapping them.

The mandatory cut inventory is:

| Data | Coordinate and cuts |
| --- | --- |
| Every non-null binding Fact with its selected Basis | elapsed: receipt_ms; receipt_ms + evidence.freshness_ms + 1; expires_ms |
| Every required-source-time Fact with non-null source_time and uncertainty | utc_low: source center + uncertainty; utc_high: source center - uncertainty + freshness_ms + 1; center is ISO-8601 Unix milliseconds rounded toward negative infinity |
| Every prior/busy/after Run | elapsed: last_ms and deadline_ms; include window cuts below |
| Every non-null step deadline in those Runs | elapsed: deadline_ms, including the prior deadline before this event's receipt changes |
| Every started delay | elapsed: started_ms + its compiled duration_ms |
| Every started wait | elapsed: started_ms + compiled timeout_ms, in addition to its retained inherited deadline |
| Every started invoke | elapsed: started_ms + compiled child run_ms, in addition to its inherited deadline |
| Every elapsed due event or retained window | elapsed: due_elapsed_ms and due_elapsed_ms + late_window_ms |
| Every UTC due event or retained window | utc_low: due_ms; utc_high: due_ms + late_window_ms |
| Every before/after edge | elapsed: last_elapsed_ms, cooldown_until_ms and, when non-null, candidate_since_ms + compiled debounce_ms |

Missing optional coordinates contribute no cut. Do not invent a start for an
unstarted delay/wait/invoke or treat that absence as an elapsed completion.
All listed fields are already structurally validated. Unusable/retained data
may contribute conservative cuts, but cannot contribute a usable Fact/effect.
Keep cut extraction bounded and linear in the supplied records: update nearest
cuts per axis without enumerating future time, coordinate products or possible
event sequences. Check every intermediate/output selection; no partial cell
or reduced-member fallback follows capacity exhaustion.

For each used axis, take the greatest cut <= its point coordinate as lower
edge, or the domain minimum if none; take the smallest cut > the point coordinate
minus one as upper edge, or the domain maximum if none. elapsed.min is then
the point elapsed coordinate, so later checks cannot move backward. Its upper
edge is the derived upper edge. UTC cells permit movement in either direction
within the derived interval, additionally requiring low <= high under Time.
Duplicate cuts have no effect. This exact partition is canonical; a constructor
cannot return a point-only or arbitrarily narrower cell to avoid the required
temporal cases, or omit a cut to return a wider one.

UTC is relevant when any provided root trigger is due, any supplied event or
retained Run window is UTC due, or any installed binding requires source time.
This includes members with no current proposal. With no such dependency set
utc_mode ignored and utc_generation/utc_low/utc_high explicitly null. A current
Time@2 may then lose/replace UTC while retaining its elapsed basis; that alone
does not invalidate this decision. With relevant UTC but absent point bounds,
set utc_mode absent, utc_low/high null and utc_generation to the selected
grammar's relevant generation (Time@1's coupled generation or Time@2 null).
Current absence/relevant generation must match. With relevant present UTC set
utc_mode present, retain its relevant generation and the two derived intervals.
Current UTC must remain present with that generation and inside both cells.

Cell construction does not qualify clocks or infer a UTC trajectory. A current
full interval must fit the derived cells; comparing a midpoint, only one endpoint
or an elapsed estimate of UTC is insufficient. A new time grammar, elapsed epoch/
generation or backward elapsed coordinate always refuses current reuse. A change
to relevant UTC generation/presence refuses; irrelevant UTC change preserves
eligible elapsed-only work. A fresh calculation may still advance retained
elapsed originals without renewing their start/deadline.

**VD-05 — Bind the cell and immutable point.** decision_digest is the existing
`sha256:` plus lowercase SHA-256 of sorted-key compact JSON of the complete
decision body without decision_digest. The format participates in that hash.
The complete collection, including its full input and profile/limits, is covered.
No caller-supplied maximum, digest or point-valid flag substitutes for deriving
the cell. to_map/3 rechecks the point, rederives the entire canonical cell and
digest and compares every member; rehashed cell widening/narrowing refuses.

The cell preserves eligibility/control decisions at the verified point's
latched starts, receipts and branch choices. It does not claim that replaying a
new original at a later Time produces byte-identical Run timestamps. Never
rebase starts, deadlines, edge candidates, originals or receipt times to make
an old decision current. Point transitions retain their original full Time.

## Current decision and arbitration check

**VD-06 — Compare actual current inputs and every contributor.** Current
context has exactly input, dispositions, batch_limit and arbitration. input is
the complete current Collection@2 input with its current full Time. All input
members except time must equal the certificate's point input exactly, including
membership, Programs, events, snapshot identity/resources/facts/binding bases,
and full prior original/busy/edge. Do not compare only selected proposals or
resource revisions. The consumer obtains these actual current values; supplying
the certificate's own claims does not prove that they are current.

Check current Time grammar/elapsed identity, UTC mode and every axis against the
verified cell. A boundary crossing invalidates the entire decision, including
groups apparently unaffected by it. Do not return a filtered still-valid prefix.
The consumer performs a fresh outside-transaction calculation against actual
retained state. New host events, receipts, membership, overrides, source/clock
qualification or future occurrence availability remain consumer obligations;
this cell cannot discover a trigger omitted by that consumer. Its own temporal
source/queue validity must also hold at commit/claim/handoff.

dispositions has exactly one entry per complete proposal step_original, each
with constraint allowed/refused/unknown and override none/selected/suppressed.
batch_limit is an integer 1 through Profile.pending_work; the caller's narrower
product maximum remains external. arbitration is the existing exact five-member
result: collection_digest, dispositions, batch_limit, selected and decisions.
It must bind this complete point collection and the exact current supplied
dispositions/limit. Verify every constraint, override, equivalence/domain conflict,
group/contributor, deterministic order and selected/coalesced/conflict/blocked
outcome before the cutoff. An incompatible proposal beyond that cutoff must
still block its domain. Reserved equivalents remain contributors with unchanged
spend; selection is no new charge or repeated handoff instruction.

This check must not call the forward transition functions prohibited in VD-02,
including through Arbitration.decide/5's existing Collection regeneration.
Use a bounded independent arbitration check over the complete already verified
proposal set. A resource/signature index can verify all groups without generating
pairwise output or truncating the domain graph; compare full equality signatures,
not an unauthenticated hash shortcut. Contradictory selected overrides still
conflict. There is no arrival-order winner.

Success returns {:ok, checked}, a plain closed object with exactly format
wotex.routines.checked-decision@1, scope provided_membership_time_cell_only,
decision_digest, collection_digest, point_time, checked_time, transitions,
proposal_states and arbitration. transitions/proposal_states are the exact
verified point data, not time-rewritten results. Both full Time maps are retained.
No timestamp, permission, physical result, reservation or hidden member is added.
The whole output obeys selected Limits. This is a call result, not a reusable
authorization capability; every later mutable boundary requires fresh input/time
and external current authority checks.

## Failure, staging and compatibility

**VD-07 — Separate inert point history from current effects.** All operations
are pure and deterministic for equal complete inputs. There is no worker,
queue, retry timer, stored cache, filesystem access or cancellation lifecycle.
The consumer owns atomic persistence, revision comparisons and recovery.

verify_point/4 or Transition.verify/8 may establish a historical/inert point
transition while a later time cell has expired. Such a point result is not
current effect admission. The consumer must authenticate its original point
inputs/time and define whether/when it may retain that inert transition, then
obtain a fresh complete cut before effects. Retaining it cannot fabricate
admission/handoff, refund spend or bypass a changed current authority basis.
This distinction lets a consumer preserve a delay's original start while later
calculation is needed; repeatedly restarting the delay to obtain a fresh cell
would change semantics and can starve a short delay forever.

An original already known to the consumer must retain its actual prior and
no-repeat history. A point proof does not authorize replay of a physical effect,
prove that nil history is new or resolve an uncertain handoff. Changed runtime/
compiler/model or installed basis needs the consumer's current correspondence;
the library cannot measure those artifact identities. Unsupported/inconclusive
analysis remains unsupported/inconclusive. Frozen models do not gain this
verification scope through a new label or successful constructor.

**VD-08 — Refuse without repair.** Return payload-free Wotex.Routines.Error.
Existing representation/compiler/limit errors retain their codes/path.
New codes are:

| Code | Meaning |
| --- | --- |
| invalid_transition | Claimed before/after/result/basis does not satisfy the complete point rules |
| invalid_collection_decision | Incomplete/forged collection, canonical cell or decision digest |
| unsupported_decision_scope | A collection/format/profile outside the explicit supported seam, including Collection@1 |
| stale_decision_input | Any independently supplied current non-time input differs |
| stale_decision_time | Changed relevant clock basis, grammar, presence, regression or outside cell |
| stale_decision_arbitration | Changed current disposition/limit or forged/incomplete arbitration outcome |

Validate Profile/Limits and combined bounded JSON/native shape first; complete
point correspondence next; canonical cell/digest next; current non-time input,
Time cell and complete arbitration in that order. Refuse the first failing
stage with a structural path, never caller source text/exception/payload.
No fallback to Collection@1, forward replay inside a verifier, time pinning,
partial output, silent bound increase or inferred permission follows.

## Entry, examples and acceptance

The frozen entry artifacts are
`packages/wotex-routines/priv/schemas/wro-02-verified-decision.schema.json` and
`packages/wotex-routines/priv/vectors/wro-02-verified-decision.json`, including
closed current context, both Time/Run grammars, exact cell shapes and the six
semantic refusal codes. Five native schema checks pass: all six UTC/grammar
cell alternatives, 52 malformed/missing-field vectors, inherited definition
equality and offline resolution. Synthetic digests and schema acceptance do
not prove transition/cell/arbitration correspondence. The nine literal integer
partition vectors remain declarative entry data; the complete semantic refusal
obligations remain open, although all six codes have native API cases below.
Retain independent generators/reference inputs in test/support.

Normal example: a verified cut at elapsed 5 has no relevant UTC, a waiting delay
ready at 10 and a live effect deadline 100. Its elapsed cell ends at 9. Current
Time 9 with equal input/basis/dispositions verifies; Time 10 refuses the whole
cut. A new UTC generation alone is irrelevant for these elapsed-only members.

Adverse example: member A's delay gates false on a Property, while member B
already proposes true on that same installed Property/domain. At point 5 only
B contributes. At 10 A can join and conflict, so B cannot use the old decision
merely because its own deadline is 100. The complete cell includes A's cut at
10 before any batch limit. A satisfied/refused/handed-off path instead requires
its exact new prior/receipt input, not time-cell reuse of the old one.

For independent tests, use a source-AST/receipt relation and all-pairs arbitration
oracle, not production forward/checker/tree/qualification helpers. Generate
expected integer cell cuts directly from raw declared values. Two separately
implemented extracted-archive consumers must use distinct source/event and
retained-state/journal-style oracles without importing consumer product modules.
Mutations must fail through assertions; loader/compiler failures are not catches.

| Case | Requirements | Setup/stimulus and expected falsifier | Evidence level |
| --- | --- | --- | --- |
| VD-T1 | 01–03 | Full direct Kernel and Collection@2 corpus covers every source/event/Time/Run/Edge cell, nil/terminal/busy/removed histories and explicit unsupported v1 collection; no valid shape is silently projected to a narrower source | Independent native |
| VD-T2 | 02–03 | Mutate every transition/basis/path/receipt/contract/edge/spent/proposal/state field and rehash all claimed digests; each semantically wrong relation refuses, including omitted unchosen records and false unknown handling | Independent mutation |
| VD-T3 | 02 | Disable every prohibited forward function after preparing valid fixtures; direct and whole-set checks still succeed/refuse correctly, with zero hidden engine calls or harness errors | Isolated native |
| VD-T4 | 02–04 | Independent late receipt, satisfaction before/after expiry, duplicate satisfaction without old Fact, Run@1 promotion, conditional/invoked condition and parallel partial/unknown traces retain exact originals/spend and ordering | Native/source relation |
| VD-T5 | 04–05 | Every listed threshold at point-1/point/point+1, inclusive freshness +1, exclusive expiry/window, zero debounce, wait/delay/child deadline, 65-bit intermediate and domain edge yields the exact canonical cell | Independent arithmetic |
| VD-T6 | 04–06 | False/unknown/no-proposal member becomes time-eligible beyond the cutoff; entire old decision refuses at the boundary, even when selected leaves remain within their own deadlines | Complete-set native |
| VD-T7 | 04–06 | Trusted source-time future/age bounds and uncertain UTC low/high move both directions; full endpoints and relevant generation/presence are checked. Irrelevant UTC loss/replacement preserves elapsed-only reuse | Independent time matrix |
| VD-T8 | 03–06 | 64 sixteen-effect members retain all 1024 pending originals/reserved states before a sixteen-group cut; final member conflicts, lower pending bound and rehashed omission all refuse; exact complete group contributors survive | Native capacity/arbitration |
| VD-T9 | 05–06, 08 | Widen/narrow/re-hash a cell, change non-time current input, ownership/metadata, disposition, batch limit or complete decisions; correct first-stage refusal and no repaired/filtered success | Native/schema |
| VD-T10 | 01, 04, 08 | Exact/one-over combined argument/output bytes/depth/nodes/strings/collections count all embedded copies; no coordinate enumeration, Cartesian traversal, truncation or silent limit enlargement | Native boundary |
| VD-T11 | 06–07 | Two-phase inert point retention/fresh cut preserves a short delay's original start through delayed publication; current effects require a new valid complete cut, and cancelled/unknown originals never resend/refund | Independent consumer harness |
| VD-T12 | 01–08 | Two separate extracted archives implement independent raw-source and retained-state oracles, same decisions without private calls or ambient services; ordinary load starts no process/I/O | Independent archive |
| VD-T13 | 02–06 | Isolated expiry-before-receipt, false edge, spend refund, omitted negative member, widened cell and pre-cutoff omission mutants are caught in both archive families through assertions with zero harness errors | Archive mutation |
| VD-T14 | 05–08 | Frozen Model scope requests remain explicitly unsupported, forged current/authority labels cannot confer authorization, and existing source/Run/Collection@1 behavior and package boundaries remain unchanged | Native/archive compatibility |

All complete cases remain open; the implemented subsets below do not close a
combined native/archive obligation. Record exact source/build/profile/limits/fixtures,
archive hashes, commands, actual counts and environment for executed evidence.
Pure point/time-cell correspondence is not consumer transaction, installed clock,
source continuity, model containment or physical effect qualification.


## Implemented time-cell foundation

The internal DecisionCell component derives the canonical complete-record cuts
and compares already-validated current Time. It requires a previously verified
point collection; it does not establish that precondition, validate a decision
digest or verify arbitration. Public Decision now owns that verified-point
precondition. The nine literal partition vectors remain declarative entry data.

Seventeen native component cases pass within a 35-case affected run. They cover
negative delayed membership, waits/invocations/unstarted paths, every binding's
Fact freshness/expiry, signed fractional source-time endpoints, relevant/absent/
irrelevant UTC, event/retained windows, before/after edges, terminal original/
busy history, independent effect deadlines, 64 members with 1,024 pending effects,
wide intermediates and selected output bounds. Four isolated native mutations
are caught through assertions with zero harness errors. The
[foundation record](../provenance/verified-decision-foundation-2026-10.md) binds
source/test identities and actual checks. These checks partially exercise
VD-04/06; complete VD-T1–T14 and archive evidence remain open.

## Implemented direct point verification

The public Wotex.Routines.Transition.verify/8 operation independently checks the
complete supplied direct Kernel relation. It normalizes all arguments, applies
the combined envelope bound and checks exact basis, qualified observations,
before/after edge state, receipts and nonrefundable spend, every visited or
unchanged step, outcome/reason and complete ordered new proposals. It returns
no replacement Run or forward transition. Historical point correspondence
does not establish current input authenticity, membership or effect authority.

The isolated affected corpus passes 113 tests and verifies 1,152 full point
relations plus 72 direct edge relations with all eight prohibited forward
functions disabled during proof. One selected combined-envelope refusal is
counted separately and checked against the complete argument size. Twelve new
native tests cover accepted traces, forged native values, scalar result-leaf
changes, rehashed receipt forgery, plausible motion changes and exact byte
bounds. Six isolated in-memory mutations are caught through assertions with
zero harness errors. The [point record](../provenance/verified-transitions-2026-10.md)
binds complete source/test identities, commands, counts and limitations.

This supplies direct native evidence toward VD-01/02/08 and parts of
VD-T1–T4/T10. This direct record does not alone establish complete-decision
correspondence or independent raw-source/archive evidence. The existing
Model/Analysis scope, consumer adoption and physical qualification are unchanged.

## Implemented complete native decisions

Public Decision.verify_point/4 checks independently supplied complete input;
new/3 checks a Collection@2 against its retained input, derives the canonical
cell and binds the complete digest. to_map/3 repeats those checks rather than
trusting native construction or a rehashed claim. check/4 then compares all
actual non-time input exactly, verifies current Time against the complete cell
and independently checks full arbitration before the batch cutoff. It returns
the exact historical point transitions/states and both complete Times.

Pending verification traverses validated after Runs and installed trees once
per member, consuming every supplied proposed/reserved contributor in order.
Arbitration uses full equality signatures and resource indexes, checks every
override/conflict domain and consumes exact claimed groups and decisions. It
calls no forward Collection, Pending or Arbitration function. Its result still
certifies only supplied membership and input correspondence.

The guarded native lane passes fifteen new Decision cases and 26 existing
complete-pending/clock cases with zero skips, assertion or harness errors. All
nine prohibited forward seams, including Arbitration.decide/5, are explicitly
probed before execution and disabled during proof. The existing corpus checks
70 complete collections and seven full arbitration relations. An independent
all-pairs oracle exercises 162 policy/batch combinations and a 64-member,
1,024-contributor case whose final supplied member conflicts before a 16-group
cutoff; the 1,023 selection refuses. Native cases also cover retained charges,
negative-member timing, relevant/irrelevant UTC, rehashed omissions/cells,
strict numeric input equality and exact/one-under public byte envelopes.

The [complete-decision record](../provenance/verified-decisions-2026-10.md)
binds source/test/script identities and the executed checks. The independent
raw-source and journal archive oracles, both extracted consumers, complete-
verifier mutations, full VD-T1–T14 and owning milestone remain open. No current
consumer adoption or host/physical qualification is inferred from this lane.

## Sources and decisions

Reconciliation used package source 973fb32c: Kernel, Execution, Receipt, Edge,
ObservationView, Pending, Satisfaction, Collection and Arbitration; the owning
[source contract](WRO.02-source-kernel.md), [temporal contract](WRO.03-temporal-host.md),
[analysis contract](WRO.04-analysis-correspondence.md) and continuation successor.
The complete before/after collection supplies the witness; no second source/IR,
receipt store or consumer ontology is introduced. Exact canonical time cells
make time-only negative eligibility changes visible without a forward transition
inside a consumer writer. Actual input authenticity and authority stay external.

## Frozen archive entry

The [independent archive profile](../decisions/verified-decision-archive-profile.md)
fixes two distinct source/journal oracles, seven behavioral cases plus cohort
identity per family, the full 1,024-contributor case, six semantic defects caught
in both families and exact result/cleanup obligations. Its accepted entry does
not claim that the lane or archive evidence exists yet. Implement it without
reducing the full VD-T1–T14 requirements or promoting native evidence to archive
qualification.

The source-family oracle/consumer now passes all seven local native preflight
cases, including full raw-source relations, independent all-pairs arbitration,
1,024 contributors and negative delay/wait/Fact/window cuts. The
[source preflight record](../provenance/decision-source-preflight-2026-10.md)
binds its exact sources and checks. Journal archive execution, the opt-in runner,
cohort identity, both extracted projects, all twelve mutation runs and full
verifier milestone remain required; this is not archive evidence.

The separate journal family now passes seven local native preflight cases.
Its explicit row/receipt scripts and consumer-owned revision, original and charge
ledger are independent of the source oracle and production execution helpers.
Full-record, restore, negative-time, complete proposed/reserved, 1,024-contributor,
policy/cutoff and exact public byte-bound cases pass. The
[journal preflight record](../provenance/decision-journal-preflight-2026-10.md)
binds the sources and executed checks. Both families are still native preflight;
the opt-in archive runner, cohort identity, extracted projects, twelve semantic
mutation runs and owning verifier milestone remain required.
