# Bounded run continuation v1

Version: 0.1.8. Updated: 2026-10-16. Status: implemented bounded successor; software evidence only.
Owner: WRO.01 explicit limits; WRO.02 execution, collection and arbitration;
WRO.03 UTC/elapsed correspondence. BRC-01–07 are implemented. The full owning
package gate passes 241 tests at 95.5% coverage, including Dialyzer and all 15
configured checks. Two independent extracted consumers pass five cases each;
all five isolated mutations are caught through assertions in each family with
zero harness errors. Real calendar/civil archives pass 21 cases, including
Time@2 grammar/UTC binding and passive civil query. The
[bounded continuation milestone](../provenance/bounded-continuation-2026-10.md) records exact commits, cohort,
locks, source hashes, commands, counts and cleanup. Broader WRO.01–04 and
consumer-host/physical obligations remain separate.

## Result and ownership

A caller can reevaluate an existing run without inventing a trigger, retain
an already-satisfied absolute Property step without pretending to send it, and
arbitrate every currently eligible unsent step across its complete provided
membership. One collection can use stable elapsed time while UTC qualification
changes independently. Larger aggregate limits are explicitly selected; no
constructor silently expands a caller's bound.

[WRO.01](WRO.01-capability-behaviour.md) continues to own installed Basis, Fact,
exact units, payload-free errors and JSON bounds. [WRO.02](WRO.02-source-kernel.md)
continues to own source/IR regeneration, path originals, qualified snapshots,
three-valued predicates, receipt stages, finite composition and arbitration.
[WRO.03](WRO.03-temporal-host.md) owns immutable original due coordinates.
[The external input join](external-input-execution-v1.md) keeps its exact Mapping,
external profile identity and receipt-clock semantics. This successor changes
none of those identities or qualification rules.

All operations remain pure. The consumer owns actual active membership, the
original/current-run indexes, current observations and clock qualification,
durable transactions, nonrefundable root accounting, overrides, held resource
claims and physical handoff. Reconstructed proposals and matching facts confer
no authority. A pure library cannot certify a host's complete active set or
prove that a reported state was physically caused by a particular request.

## Inputs, bounds and compatibility

**BRC-01 — Explicit aggregate capacity.** Keep the six required members and
representation of `Wotex.Routines.Limits` unchanged. Increase only these allowed
positive ceilings:

| Member | Previous ceiling | Successor ceiling |
| --- | --- | --- |
| max_bytes | 1048576 | 67108864 |
| max_depth | 32 | 64 |
| max_nodes | 100000 | 2000000 |
| max_collection_size | 1024 | 8192 |

max_string_bytes remains 65536 and max_integer remains 9223372036854775807.
There are no defaults. Existing selections retain their exact meaning and
encoding. A caller choosing 1048576 bytes still refuses a larger input or
output. Profile bounds remain independent and unchanged; a larger JSON limit
cannot admit more expanded nodes, active definitions, runs or pending work than
the supplied Profile. Revalidate both native limits and every full nested input
and output. Embedded copies count at each occurrence, including retained prior,
transition basis and collection regeneration. Exceeding a bound returns the
existing structured limit error without partial collections or truncated lists.

A consumer selects a member and aggregate envelope before activation and
refuses configurations it cannot collect in full. The package promises no
Cartesian product of maximum-sized members fits the aggregate ceiling.
`Profile.pending_work` bounds all eligible step proposals before equivalence,
conflict checks or the caller's arbitration batch limit. For example, 64 runs
with 16 simultaneously eligible effects require pending_work at least 1024;
a batch limit of 16 cannot substitute for that complete proposal bound.

**BRC-02 — Neutral resume.** Extend `Wotex.Routines.Event.new/2` and `Wotex.Routines.Event.to_map/2` with the
closed event `{kind: resume, original, program_digest}`. All keys are strings;
identities retain WRO.02's nonempty text/digest bounds. No path, Fact, receipt,
source or trigger coordinate is accepted. `Wotex.Routines.Kernel.advance/7` requires the exact
retained Run in prior.original. A matching prior.busy cannot substitute for
missing original history. Missing prior.original returns missing_original;
foreign program/original and malformed prior retain their existing refusals.

Resume cannot create a run or a new original, consume a reported-edge sample,
change its baseline/debounce/cooldown, replace an immutable due descriptor or
reinterpret a manual run as a calendar run. The returned edge is the complete
unchanged retained edge. Revalidate program, snapshot, prior, time and bounds
as usual. For a live run, apply current membership, root/invocation conditions,
selected branches, wait/delay progress, step/run deadlines and the retained
window exactly as ordinary continuation. Previously proposed/reserved steps do
not become newly emitted Kernel proposals. Only a newly reached unsent effect
emits one. Resume of a terminal run returns that exact run and no proposals,
after input validation; elapsed time alone does not rewrite terminal history.

The existing repeated manual/due/elapsed_due/fact events retain their meaning.
In particular, a fact event is still a real edge input and cannot be used as a
resume surrogate. The consumer persists a newly rejected busy trigger separately
from reevaluating the older live run; it must not hide that run's pending work
by supplying the rejected trigger as its only collection entry.

## Independent elapsed and UTC bases

**BRC-03 — Explicit Time alternative.** `Wotex.Routines.Time.new/2` and `Wotex.Routines.Time.to_map/2` retain
the existing closed five-member grammar unchanged. Its descriptive identity is
wotex.routines.time@1; that label is not added to its map. Add a distinct closed
seven-member alternative:

| Member | Required value |
| --- | --- |
| format | wotex.routines.time@2 |
| epoch | Nonempty elapsed incarnation identity |
| elapsed_ms | Nonnegative integer within max_integer |
| clock_generation | Nonempty stable elapsed-clock generation identity |
| utc_generation | Nonempty qualified UTC-basis identity, or explicit null |
| utc_low_ms, utc_high_ms | Ordered signed integer milliseconds, or both null |

With null UTC bounds require null utc_generation. With integer bounds require
a nonempty utc_generation. Mixed/absent members, unknown formats, extra native
fields, invalid UTF-8 and out-of-bound coordinates refuse. Projection preserves
the selected grammar; neither constructor reads, qualifies or repairs a clock.

For Time@2, elapsed waits, delays, run/step deadlines, countdown windows, receipt
freshness and reported-edge elapsed qualification use epoch/clock_generation
and elapsed_ms. A UTC-basis correction or loss does not alone expire those
elapsed operations or reset an otherwise qualified elapsed edge. Facts requiring
source UTC age still need the current qualified full UTC interval; unavailable
confidence yields unknown and resets edge qualification where WRO.02 requires.

UTC due event/window.clock_generation retains its existing field name, but
compares with Time@2.utc_generation. It never compares with the elapsed
generation. The entire UTC interval must remain within the original half-open
window. Replacement of a non-null UTC generation expires a live UTC-window run
with clock_changed; absent UTC confidence or an interval outside the original
window expires it with window_closed. Epoch/elapsed-generation replacement or
elapsed regression retains its existing precedence and expiry reason. No clock
change creates a replacement due coordinate, catches up work or permits resend.
Time@1 retains its existing single-generation behavior in every API.

`Evaluation`, `Snapshot`, `Edge`, `Kernel`, `Collection`, `Arbitration`, temporal
binding and any retained model/witness inputs must preserve and revalidate the
selected complete Time. No adapter drops utc_generation or relabels a Time@2
as Time@1. An analysis profile without these semantics returns its existing
unsupported-scope error; it cannot certify a projection with fields omitted.

**BRC-03a — Retained clock correspondence.** Keep Edge@1 closed and unchanged.
An edge advanced with Time@2 returns wotex.routines.edge@2, whose exact members
are the Edge@1 members plus time_format = wotex.routines.time@2. Its retained
clock_generation is the elapsed generation; UTC generation/confidence is not
an elapsed baseline identity. Edge construction preserves the selected grammar.
On a fact advance, a different time grammar is a basis replacement: establish a
fresh baseline under the new grammar and emit no edge from the old candidate or
cooldown. Same-grammar UTC correction alone keeps elapsed qualification, while
current source-age requirements still apply. Kernel transition bases and Witness
frames retain the full Time; Edge retains only its declared elapsed basis.

Scalar UTC schedule pages and the Calendar/Civil adapters use Time@2's
utc_generation in their inert due descriptors, cursor binding and current event
checks. Countdown pages continue to use elapsed epoch/generation. A UTC page
with Time@2 and absent UTC basis returns missing_utc_basis before producer
callbacks or enumeration; it invents no generation. Time@1's existing inert
calculation with absent confidence remains unchanged. Event binding requires the
same selected time grammar and relevant generation as its retained projection;
elapsed-generation changes alone do not stale a Time@2 UTC projection.

Opaque scalar cursor digests add the selected time_format only for Time@2 and
bind the relevant elapsed/UTC generation. CalendarCursor's existing three-member
native envelope is unchanged: clock_generation retains the relevant UTC
generation, and basis_digest additionally binds time_format for Time@2. Thus a
cursor cannot cross grammars even when the supplied generation strings are
equal. Time@1 cursor digests, original identities and all existing wire shapes
remain unchanged. A scalar Time@2 occurrence has exactly the existing original, ordinal, due_ms
and event members plus time_format = wotex.routines.time@2. Its event descriptor
keeps the existing member set. This explicit occurrence marker lets event/6
reject a cross-grammar projection even when generation strings happen to match;
Time@1 scalar occurrences keep their exact four members. Native Calendar/Civil
pages instead retain their complete checked Time and need no new wire member. New grammar,
changed relevant generation and absent required basis follow existing stale
projection/cursor or missing_utc_basis refusals; no retry rebases a cursor.

**BRC-04 — Closed Run successor.** Keep Run@1's exact outer members and seven
receipt slots unchanged. `Wotex.Routines.Run.new/4` and `Wotex.Routines.Run.to_map/4` additionally accept
wotex.routines.run@2. It has every Run@1 outer member plus required time_format,
whose value is wotex.routines.time@1 or wotex.routines.time@2. Every step retains
its eight existing members, but receipts has exactly the old seven slots plus
satisfied. No other outer, step or receipt members are admitted. Each satisfied
slot is null or the closed `{ref, digest, outcome: matched}` record. Ref/digest
use the existing receipt text/hash grammar. All path, tree, time, stage and
spent-reference coherence checks still apply.

A new run started with Time@2 is Run@2 with time_format Time@2 and all satisfied
slots null. A new Time@1 run remains Run@1. Resume and ordinary receipts never
implicitly change an existing run's format. Run@1 accepts continuation only
with Time@1. Run@2 accepts only its retained time_format; any grammar switch
returns clock_format_mismatch before changing history. A changed generation
within the same grammar is ordinary expiry, not a format mismatch. Run@2 does
not rewrite original/path/program/source/compiler identities or due windows.

The only additional promotion is an accepted BRC-05 satisfaction on Run@1:
produce Run@2 with time_format Time@1 and add null satisfied slots to every
other step. Preserve every other identity, timestamp, receipt, branch and spent
reference except the actual step/ancestor transition and normal live last_ms
update. Plain construction or decoding never upgrades retained history. Older
libraries refuse Run@2 rather than misread a completed unsent step as a handoff.

## Completion without physical dispatch

**BRC-05 — Explicit current-state satisfaction.** Add a closed Event kind
satisfied with exactly kind, original, program_digest, path, ref, fact_id and
report_contract. Path/ref keep WRO.02 receipt bounds; fact_id is nonempty text;
report_contract is the complete installed `{id, version, semantic_digest}`
reference. This event is consumer-qualified data, not an authenticated receipt.
It does not declare local queue, protocol response, correlated cause or handoff.

The exact original must already exist. For a fresh satisfaction require all
of the following, using the same current snapshot/time as the transition:

1. The named compiled step is an absolute Property writeproperty effect with
   completion reported_match. Actions and other completion thresholds refuse
   invalid_satisfaction; an arbitrary action result cannot be inferred from
   a matching Property.
2. The step is proposed or reserved and the run is live. It has no handoff,
   queue, protocol, correlated_report, reported_match, terminal or satisfied
   receipt. Its current root/invocation conditions permit this selected path.
3. The complete report_contract equals the compiled evidence_contract; a
   mismatch refuses stale_report_contract.
4. The snapshot Fact in this step's binding has exactly fact_id and qualifies
   through the unchanged WRO.02 observation checks: Thing/affordance, installed
   profile/source/epoch, accepted source class, quality/replay/continuity,
   receipt incarnation/freshness, source-age policy and exact value/unit domain.
   Its known typed value, after existing exact unit conversion if required,
   equals the effect's already compiled literal input. Missing, stale, unknown,
   mismatched or differently valued evidence refuses invalid_satisfaction.

Apply current membership, window and run/step expiry before a fresh satisfaction.
A deactivated run is cancelled; an expired live run returns the ordinary expired
transition without recording satisfaction or emitting proposals. A terminal or
otherwise out-of-order fresh receipt refuses out_of_order_receipt. No failed
check changes the returned retained state or creates a new proposal.

On success retain satisfied = `{ref, digest, outcome: matched}`, with digest
binding the entire Event using the existing deterministic receipt hash. Complete
the step and advance its sequence/parallel ancestors under the normal current
conditions and limits. Newly reached later steps may emit their own proposals.
Do not fabricate admission, handoff or result-stage receipts. With no admission,
spent remains unchanged. With held admission, preserve it and its spent entry
exactly; satisfaction never refunds a prior reservation. The consumer likewise
retains its actual durable charges and releases resources according to its own
policy. This library performs no release, transport or storage operation.

An exact repeated satisfied event retains its first receipt even if that Fact
has since expired or disappeared; it is replay of history, not a new match.
For a live partially completed run, normal current expiry/conditions still gate
any later unsent work. A conflicting event at the occupied satisfied slot refuses
conflicting_receipt. A fresh satisfaction after handoff refuses; later matching
reports must use the existing qualified result-stage path. Retained Run validation
accepts completion without handoff only for an exact BRC-05 satisfied record and
its coherent admission/spend history. Mixed handoff/satisfaction, satisfaction on
non-effect nodes, forged status/slots, removed held spend and altered paths refuse.
A digest or valid Run still cannot prove the consumer committed the receipt.

## Complete continuation collection

**BRC-06 — Opt-in complete pending set.** Preserve Collection@1 and its existing
three-member input unchanged. Add a closed input with exactly format, membership,
entries and time, where format is wotex.routines.collection-input@2. Membership,
entry shapes, one entry per program, shared snapshot/time coherence, native
revalidation and profile limits retain WRO.02 semantics. The result is
wotex.routines.collection@2, with all Collection@1 fields plus proposal_states.
The full selected input, including its format, remains in input and the digest.

Each retained nonterminal current run must appear as prior.original and have a
real continuation/receipt event for that original. Resume is the neutral choice.
A nonterminal prior.busy must name the same current original and complete Run;
it cannot stand in for prior.original or a different incoming trigger. A nil
event with any nonterminal retained run, or a different new trigger displacing
that run, refuses incomplete_run_continuation. Terminal/absent history may use
nil and yields no transition. These checks prevent a provided entry from hiding
its own known live pending work; they do not discover omitted host membership.

After advancing every entry, regenerate the complete eligible unsent effect
set from the checked returned Runs and Programs. Include each proposed or
reserved effect on a currently permitted selected path exactly once, whether
newly reached in this call or retained from an earlier call. Reapply the current
root and invoked-child predicates, path selection, membership, immutable window
and all inherited/effect deadlines. False or unknown conditions keep the state
but exclude that step from this cut's eligible set. Include no terminal,
handed-off, cancelled, failed, unknown, already-satisfied or unselected step.

Each proposal keeps the exact existing WRO.02 proposal members and regenerated
original/path/installed basis/domain/input/completion identities. proposal_states
is a parallel ordered array of closed `{step_original, status}` records, status
exactly proposed or reserved, in one-to-one correspondence with proposals.
Order by program_digest and then compiled path order. Duplicate identities,
missing states, altered proposals/states or recalculated digests cannot bypass
full regeneration. Kernel's own proposals remain newly emitted work only;
Collection@2 explicitly supplies the wider eligible pending view.

Count this entire eligible set against pending_work before arbitration or
batching. `Wotex.Routines.Arbitration.decide/5` accepts either complete Collection format. Its result
keeps exactly collection_digest, dispositions, batch_limit, selected and
decisions; collection_digest binds the complete regenerated collection, which
the caller retains separately. Apply hard constraints/overrides and all
resource-domain pair checks to
the full set before the batch cutoff. Equivalent proposals preserve every
original contributor, including already-reserved contributors. A selected group
is inert: status reserved is not a second admission or handoff instruction.
The consumer must reconcile its existing held requests/claims atomically and
must not charge or dispatch a contributor twice. An unselected proposed step
remains retained and can participate in a later complete cut without a new
trigger, original, admission, handoff or proposal identity.

## Failure, lifecycle and entry order

**BRC-07.** Every public seam returns its existing `{:ok, value}` or payload-free
`{:error, %Wotex.Routines.Error{}}`. New semantic codes are
clock_format_mismatch, missing_utc_basis, invalid_satisfaction and
incomplete_run_continuation;
existing missing_original, foreign_event/foreign_original, stale_report_contract,
out_of_order_receipt, conflicting_receipt, coherence and bound refusals retain
their meanings. Validation precedes semantic progression; no malformed native
value acquires a positive outcome. No retry broadens limits, renews a deadline,
fetches data, changes a generation or drops a member. Cancellation, restart,
restore and replacement retain original no-repeat/spend and handoff uncertainty.
There are no processes, timers, resources or ambient caches to clean up.

Before implementation freeze the new alternatives and independent expected
traces in `priv/schemas/wro-02-continuation.schema.json` and
`priv/vectors/wro-02-continuation.json`. Reconcile embedded Event/Time/Run/
Collection alternatives in wro-01, wro-02 and wro-04 schemas where present.
Existing v1 vectors must remain byte/identity-stable. Schemas establish shape;
constructors establish correspondence and semantic coherence. Runtime code
never reads the documentation tree.

Implement and test in this dependency order: wider explicit Limits and resume;
Time@2, elapsed Edge@2 and Run@2 with temporal cursor binding; current-state satisfaction; Collection@2/arbitration; wider
supported model/witness joins or explicit unsupported-scope refusals; extracted
independent consumers and the owning package milestone. These are delivery
steps within this complete target, not independently sufficient completion.

## Independent archive entry

The owning executable entry is
`mix run --no-start bin/check_archive.exs --continuation-consumers`, invoked from
the package root with its pinned Elixir/OTP lane. It builds one exact Routines,
core and Continuum Hex archive cohort, extracts it into a disposable absolute
workspace and runs two separately compiled consumer projects. Neither project
uses sibling paths, producer test helpers, hidden modules or the documentation
tree. Each has four behavioural cases plus the existing extracted-cohort identity
check. Shared installed Basis/Fact corpus data may supply inputs; expected
progression and journal/policy decisions must be independently consumer-owned.

`test/support/archive/continuation_source_consumer.exs` derives eligible source
paths from finite source/elapsed inputs and an explicit completion ledger. It
checks delayed edge-origin resume without root creation or edge consumption,
manual/countdown/UTC-window separation under one Time@2, unsent Property
satisfaction with and without held admission, and deferred complete pending
arbitration. `test/support/archive/continuation_journal_consumer.exs` owns a
separate original/edge journal, revision checks, nonrefundable charge ledger and
held/handed-off distinction. It independently checks those four mechanisms,
including a 64-member cut above a 16-group cutoff and retained reservations.
A consumer journal is software evidence, not a qualified host transaction.

Both families run a fresh-process baseline and each of five isolated dependency
source mutations against the same extracted cohort: resume creates a root;
elapsed continuation reads the UTC generation; satisfaction fabricates staged
handoff evidence; satisfaction removes held admission/spend; and collection
retains newly emitted proposals only. A mutant is caught only when the complete
behavioural case count is unchanged, exit status is one, at least one executed
assertion fails and the formatter reports zero non-assertion errors. A compiler,
loader, setup or formatter failure is a harness failure. Identity checks run on
the unmodified cohort, not as a mutation oracle.

The runner reports archive, consumer-source and lock hashes, baseline/case counts
and assertion/error mutation counts. Every temporary archive, extracted source,
mutant and consumer build is removed after success or failure. Ordinary archive
checks and their existing options retain their previous scope; this explicit
lane does not fetch device data, start a host or authorize an effect.

## Acceptance evidence

BRC-T1 and native clock/continuation subsets of BRC-T2–T3 pass in
`test/wotex/routines/continuation_test.exs`,
`test/wotex/routines/time_basis_test.exs`, the calendar/civil adapter suites and
`test/wotex/routines/continuation_schema_test.exs`. Concrete Witness Time@2
retention also passes. BRC-T4–T5 native satisfaction coverage passes in
`test/wotex/routines/satisfaction_test.exs`: typed Boolean/integer/enum matches,
exact conversion, current conditions/fixed branches, sequence/all-required joins,
held spend, duplicate history, expiry, mixed-slot/native refusal and concrete
Witness/schema checks. `test/wotex/routines/receipt_deadline_test.exs` retains
late receipt/charge history while preventing expired-step continuation. These
native checks do not substitute for the independent source/archive oracles.
BRC-T6 native coverage passes in
`test/wotex/routines/pending_collection_test.exs`: 1,024 proposed effects survive
repeated cuts before a 16-group cutoff, a 1,023 pending bound refuses, reserved
equivalents preserve all originals/charges, last-member conflicts participate,
current conditions remove/restore pending work and complete regeneration rejects
rehashed forged proposal/state records. Idle/displaced live runs refuse, while
terminal idle entries remain inert. `test/wotex/routines/time_basis_test.exs`
checks shared Time@2 and repeated pending cuts across UTC correction/loss for
both Collection formats. A requested complete-pending model environment refuses
unsupported_model_scope. Independent source/journal archives and all ten
isolated mutation runs now pass with zero harness errors; real calendar/civil
Time@2 archives and the full owning gate pass. The milestone evidence linked
above records their exact scope. Wider analysis remains outside this bounded
successor.
Pure tests need an independent finite source/state
oracle rather than expected values copied from the implementation. Archive
consumers keep independent journals/policy and use only public documented APIs.

| Case | Requirements | Reproducible stimulus and required observation / falsifier | Level |
| --- | --- | --- | --- |
| BRC-T1 | 01 | Old and wider native Limits at exact ceilings and one past; complete 16/32/64-member collections with full encoded results; a 1 MiB selection still refuses its over-bound result, widened selection succeeds without truncation; profile/count limits still refuse | Pure/schema |
| BRC-T2 | 02/04 | Resume manual, edge-origin, calendar and countdown runs through wait/delay completion; no new original or edge sample; missing original/busy-only fails; terminal resume is exact; generation/regression/deadline/inactive cases halt unsent work and preserve handoffs/spend | Pure/schema |
| BRC-T3 | 03/04 | One shared Time@2 advances simultaneous manual/countdown/UTC-window entries; edge grammar replacement baselines, UTC pages require their own basis and cursors cannot cross grammars; UTC correction/loss preserves elapsed work but expires UTC-window work as specified; elapsed replacement expires both; grammar switches refuse; v1 bytes/results unchanged | Pure/schema |
| BRC-T4 | 04/05 | Already-matching qualified Boolean/integer/enum Property facts complete proposed and reserved steps, progress sequence/all-required joins and retain exact charge history; stale/missing/wrong Fact, contract, unit, source, condition and deadline cannot produce satisfaction | Pure/schema |
| BRC-T5 | 04/05/07 | Exact duplicate after Fact expiry is history; conflicting duplicate, action/ACK threshold, post-handoff and fabricated mixed slots refuse; Run@1 promotion preserves all unrelated identity/receipt/spend fields; cancellation/restart cannot refund or resend | Pure/mutation |
| BRC-T6 | 02/06 | Full provided membership with pending_work above batch cutoff; all-pair conflicts include the last member; repeat cut retains earlier unselected proposals/reserved contributors with identical originals; changed conditions exclude ineligible pending work; nil/displaced live entry refuses | Pure/mutation |
| BRC-T7 | 03–07 | Model/witness constructors and replay accept only explicitly supported semantics; unsupported new scope refuses instead of dropping fields or certifying absence; malformed embedded native values and altered digests refuse | Software |
| BRC-T8 | 01–07 | Two extracted-archive consumers run delayed edge continuation, shared Time@2, unsent satisfaction and deferred whole-set arbitration; isolated root-creation, UTC/elapsed confusion, fake-handoff/refund and pending-omission mutations cause assertion failures with zero harness errors | Archive software/mutation |

At the milestone record exact repository commit/package path, archive cohort,
locks, toolchain, commands/results and temporary-artifact cleanup. Renew affected
old source/execution/edge/arbitration/model/witness and passive-load coverage.
Do not promote WRO.01–04 to complete from this bounded successor: wider analysis,
real host transactions, clock/source qualification and physical effects retain
their own acceptance obligations. No dependency release/pin is selected here.
