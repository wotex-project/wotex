# WRO.02 — Bounded routine source and pure kernel

Version: 0.2.10. Updated: 2026-10-13. Status: accepted target; implementation partial.

## Inputs, outputs and authority

A routine is an immutable source composition; a program is its complete
canonical IR; a run is consumer-retained transition state for one original
trigger and program revision. The pure kernel computes ordered proposals from
explicit program, event, snapshot, time basis, prior run and limits.
It performs no I/O, clock/configuration reads, process startup or persistence.
No proposal carries a grant or an unrestricted transport callback.

**WRO02-01.** Source contains a format/profile identity, routine/revision,
typed parameter/binding declarations, trigger, condition/unknown policy, steps,
overlap policy and finite limits. Every operation references WRO.01 semantics
and an explicit resolved participant set. Unknown fields, duplicate identities,
unsupported constructs, recursive invocation and forged native programs reject.
Child routine versions and parameters are bound before calculating expansion.
Source, canonical IR, compiler and behaviour basis identities are distinct.

**WRO02-02.** The initial semantic profiles are independently admitted:

| Form | Deterministic semantics |
| --- | --- |
| Manual trigger | One explicit original event; duplicate original is no new event |
| Calendar/UTC interval/countdown trigger | WRO.03 due coordinates; pure time calculation supplies no execution authority |
| Reported rising/falling edge | Qualified current source continuity and baseline; first/reconnect/restored/retained sample makes no edge |
| Predicate | Typed equality/exact threshold, not/and/or with true/false/unknown; unknown blocks effects |
| Absolute action | One installed semantic operation and declared evidence threshold; no toggle/raw command |
| Sequence | Advance only after preceding required completion threshold |
| Parallel all-required | Preserve each branch original/result; complete only when every required branch satisfies its threshold |
| Conditional branch | True/false select their declared path; unknown blocks that path |
| Wait | Explicit condition and finite deadline; unknown waits, deadline yields timeout |
| Delay | Explicit elapsed duration and boot/time generation; invalid generation expires unsent continuation |
| Version-pinned invocation | Acyclic finite expansion and prebound participants; no runtime discovery |

Notification providers, compensation, recursive/dynamic invocation, race/quorum
joins, catch-up and scripted conditions are unsupported in the initial profile.
Adding one requires a successor contract with runtime/model/failure semantics.
Syntax support, structural screening and execution admission remain separate.

**WRO02-03.** Limits are explicit positive integers for source bytes/depth,
expanded nodes, invocation depth, parallel width, effects, waits, active
definitions/runs, pending work and run duration. A consumer may narrow the
selected profile; the kernel cannot increase limits or infer universal defaults.
Count all expanded possible paths before admission. Each transition returns a
finite result with stable step/path ordering; map or timer arrival order cannot
choose an effect. The initial overlap policy is reject: a different original
while a run is nonterminal returns skipped-busy; the same original is retained.

## Evaluation, arbitration and outcomes

**WRO02-04.** Bind snapshot/declaration/source generations to evaluated facts.
Unknown remains unknown under negation and does not supply a false baseline.
Continuity loss or source/profile replacement resets reported-edge baselines.
Debounce requires a continuous qualified stable input over its interval;
hysteresis uses distinct typed enter/exit thresholds; cooldown prevents another
eligible root until its elapsed interval. These three mechanisms are distinct.
Their time basis is caller supplied and generation-bound.

**WRO02-05.** Collect the complete eligible proposal set before a batch cutoff.
Apply hard constraints, current consumer override policy and reviewed effect
domains. Equal-authority incompatible proposals conflict without a winner.
Equivalent proposals preserve all original contributors and root accounting.
A provided-set arbiter cannot establish that its consumer collected every
eligible active definition. The proposal retains the full collection basis
for host revalidation.

**WRO02-06.** Local/protocol acceptance does not advance a step requiring a
reported match. Failure prevents new dependent unsent work; started branches
retain their receipts and partial outcomes. Unknown handoff halts dependent
progression. Cancellation stops future unsent work, never reverses a handoff
or refunds consumed roots. Stop is a separately authorized fresh effect.
Aggregates retain per-step references and distinguish running, blocked,
skipped, partial, completed-under-declared-evidence, failed and unknown.

The consumer persists originals, transitions and no-repeat accounting. Kernel
replay is pure recomputation, never a physical repetition instruction. Source
or runtime changes require new correspondence/admission; historical identities
remain interpretable. Restore/transfer do not themselves activate definitions.

## Entry and acceptance

### Closed first source and compilation contract

The initial format is `wotex.routines.source@1`, profile
`bounded-composition@1`. There are no inferred parameters, bindings, limits,
deadlines, evidence thresholds or overlap policies. Public constructors/codecs
return `{:ok, value}` or WRO.01's payload-free Error. Unknown/missing fields,
unsupported profiles, altered native programs and bound failures refuse.

`Profile.new/1` requires the following positive integer selections. They are
ceilings for this executable profile, not defaults or universal product policy:

| Member | Maximum |
| --- | --- |
| source_bytes | 1048576 |
| source_depth | 32 |
| expanded_nodes, predicate_nodes | 4096 each |
| invocation_depth | 16 |
| parallel_width | 64 |
| effects, waits, active_definitions, active_runs, pending_work | 1024 each |
| run_ms | 604800000 |

WRO.01 JSON/number limits remain separately explicit. Both sets apply; neither
can widen the other. Whole closure bytes and every possible expanded path count
before execution. Invocation copies count again at each call site; both paths
of a conditional count. A consumer may select the narrower product bounds.

`Profile.to_map/1` revalidates before projection. `Truth.negate/1` accepts only
true, false or the string unknown. `Truth.combine/4` accepts all/any, a nonempty
array of those truths, explicit Profile and JSON Limits. False dominates all,
true dominates any, and unknown remains otherwise; unknown negates to unknown.
Malformed truth/operator/array and exceeded predicate_nodes refuse. These pure
primitives supply no fact qualification or execution admission.

`Source.new/3` and `Codec.decode_source/3` take source data/bytes, Profile and
JSON Limits. The closed root requires `format`, `profile`, `id`, `revision`,
`parameters`, `bindings`, `trigger`, `condition`, `steps`, `overlap`, `run_ms`.
Revision is a nonempty immutable consumer-owned string. Overlap is exactly
`reject`; condition and steps are mandatory even for an unconditional source.
Bindings are distinct names selecting the explicit compilation context.
Parameter declarations are named WRO.01 value contracts (boolean/integer/enum)
with no default. Effect arguments are literals or the closed object
`{parameter: name}`; there are no arithmetic expressions or interpolation.

Predicates are these closed forms, with no extra fields:

| Form | Members and semantics |
| --- | --- |
| Literal | `{op: literal, value: true/false/unknown}`; unknown is the string unknown |
| Comparison | `{op: eq/gt/lt, binding, value}`; exact value/parameter matching the installed contract; gt/lt require integer units |
| Negation | `{op: not, arg}` |
| Combination | `{op: all/any, args}`; nonempty finite predicate array |

Every node has a nonempty `id`, unique within its source. Path vectors identify
copies after invocation expansion; no string concatenation ambiguity is allowed.

| Step kind | Required members besides id/kind |
| --- | --- |
| noop | None; explicitly completes without an effect |
| effect | binding, input, completion; binding's operation must be writeproperty/invokeaction, completion must equal its installed threshold |
| sequence | steps, a nonempty ordered node array |
| parallel | branches, a nonempty ordered node array; join is all-required |
| if | condition, then, else; both complete node paths are declared |
| wait | condition, timeout_ms; positive finite elapsed budget |
| delay | duration_ms; positive finite elapsed budget |
| invoke | routine_id, revision, arguments; exact declared child parameters |

Root `steps` is one node, usually sequence/parallel. Explicit noop is a real
declared construct; unsupported syntax never becomes noop. Child triggers are
not started by invoke: only their bound step tree executes under the root's
original, duration and spend. The child's condition gates its invoked tree;
it is never omitted. Child run_ms narrows the inherited remaining duration.
All supplied child sources must pass structural
validation; the complete invocation graph must be acyclic, including unused
definitions. Missing/mismatched child versions and arguments refuse.

Triggers are closed manual, due, countdown or reported-edge descriptors. Manual has only
kind. Due/countdown have kind, schedule_id and schedule_basis (the exact immutable WRO.03 schedule digest); WRO.03 supplies original UTC or elapsed coordinates.
Edge has kind, binding, direction (rising/falling), debounce_ms, cooldown_ms and
hysteresis. Boolean edges require null hysteresis. Integer hysteresis is the
closed `{enter, exit}` pair in the installed unit; rising requires enter > exit,
falling enter < exit. Durations are explicit nonnegative integers. No trigger
starts a timer or expands a participant set at runtime.

`Compiler.compile(source, context, profile, limits)` takes a closed explicit
context: `registry`, `bases`, `bindings`, `definitions`, `arguments` and
`compiler_basis`. Registry and bases use WRO.01 values; no module/class name or
transport callback is data. Context bindings map each name to an exact installed
basis reference under `basis`, an absolute `thing_id` and every resource-role
binding under `resource_roles`. The
consumer supplies reviewed instance mappings and owns their trust. Definitions
are exact version-pinned child sources. Arguments bind every root parameter;
invoke binds child arguments from literals/parent parameters before expansion.
Extra, missing or widened bindings and arguments refuse.

The Program retains complete canonical source/context, normalized expanded
nodes/predicate instructions and distinct source, IR and compiler identities.
Source identity includes the complete supplied closure and bindings. IR identity
includes source identity and the whole normalized program. `Compiler.current/4`
regenerates from retained source/context under the selected profile/limits and
compares the entire result; a recomputed digest on modified IR is insufficient.
Compiler basis identifies the selected build/dependency cohort and remains a
consumer-verified artifact fact, rather than an authenticity assertion by a hash.

The first Program data has exactly `format`, `source`, `context`, `profile`,
`json_limits`, `compiler_profile`, `source_digest`, `ir`, `ir_digest`.
Format is wotex.routines.program@1 and compiler_profile is
wotex.routines.compiler@1. IR has exactly `condition`, `trigger`, `steps`,
`run_ms`, `overlap`. Compiled nodes retain source members plus a `path` integer
vector; effect input arguments are resolved literals and retain the exact
`evidence_contract`. Invoke additionally retains its bound `condition`, `run_ms`
and expanded `body`. Predicates compile to finite postfix arrays: literal/value,
eq/gt/lt with binding/value, not, and all/any with explicit positive operand count.
Every comparison is typed against an observable Property/Event basis; Action
input cannot stand in for an observation. Every invocation's argument names
and declared types are screened across the closure, then actual bound values
are validated before expansion. No incomplete provided IR is accepted as source.

### Explicit execution and receipt values

`Kernel.advance(program, event, snapshot, time, prior_run, profile, limits)`
returns a finite transition containing the next Run, ordered inert proposals,
and the full revalidation basis. Every supplied native value is revalidated.
The consumer retrieves the original's retained Run and also supplies any
nonterminal busy Run for overlap checks. Selecting, persisting and compacting
originals are host obligations; passing nil does not prove an original is new.
The kernel never expires a no-repeat ledger or authorizes physical replay.

Snapshot has exactly id, membership_generation, active_programs,
resource_revisions, binding_bases and facts. Active programs are distinct IR
digests. Resource revisions include every resolved Thing and resource domain;
values are nonnegative integers. binding_bases has exactly every compilation
binding name; each record has profile_digest, source_id, source_epoch and
source_time_basis. The profile must equal its compiled installed basis.
facts has those exact names and a complete WRO.01 Fact or explicit null for
absence. Extra/missing slots refuse. A supplied stale Fact remains data and
evaluates unknown; it does not update the expected binding basis.
Time has exactly epoch, elapsed_ms, clock_generation
and explicit UTC low/high millisecond coordinates (or both null). UTC coordinates
are ordered; elapsed regression or epoch change expires unsent elapsed waits.
Trusted source age uses WRO.01's clock basis/uncertainty and the complete current
UTC interval. Missing trust/basis, future source intervals, incompatible units,
expired receipts, unusable quality or unaccepted source classes produce unknown.
Fact identity must match the binding's Thing, observable affordance/name,
profile and expected source identity/epoch. Receipt epoch must match Time epoch;
elapsed age is nonnegative and no greater than the installed freshness bound,
with elapsed_ms strictly below expires_ms. Where source time is required,
trusted source basis must match the selected binding basis, source interval's
upper endpoint cannot exceed current UTC lower endpoint, and worst-case age
cannot exceed freshness_ms. Missing UTC confidence makes that test unknown.
Receipt freshness and source age remain separate checks. Replayed/retained or
baseline/lost continuity cannot create an edge.

`Evaluation.evaluate(program, snapshot, time, profile, limits)` revalidates all
inputs and returns the root condition's true/false/unknown result. It does not
match a trigger or authorize a proposal. The initial evaluation profile uses
only fresh reports. Lost continuity is unusable; continuous contracts also
require continuous facts, while snapshot contracts may use a baseline for a
condition. Edge generation separately always requires fresh continuous input.
Comparisons convert qualified integer facts exactly into the installed unit;
conversion/type errors yield unknown, and negation never converts unknown into
false. Boolean/enum values must match their installed domains. Malformed
postfix instructions or stack shape return a typed error rather than truth.

Events identify the exact program revision and original. Manual, due, fact,
admission, handoff, result and cancel are separate kinds. An admission receipt
records held/refused after the consumer's transaction. Held work changes a
proposed step to reserved and records its committed charge references; refusal
retains the original with a terminal refused outcome. Handoff is a distinct
consumer receipt after its durable handoff marker, rather than a protocol ACK.
A due event additionally retains original
due_ms, late_window_ms, schedule/clock identities; its whole UTC confidence
interval must fit `[due_ms, due_ms + late_window_ms)`. A result names the original
step/path and a retained result reference, with separate stage and outcome.
Stages are local_queue/protocol_response/correlated_report/reported_match;
outcomes are accepted/failed/unknown. Stages do not fabricate cause. A stale,
foreign, duplicate-conflicting or out-of-order result refuses; an exact duplicate
retains its original outcome. Report-stage input is consumer-qualified data,
not an arbitrary report authenticated by the kernel. Report-stage receipts
retain the exact installed WRO.01 report_contract reference; a missing or
mismatched reference refuses even if its stage says match.

Retained execution state binds original, program/compiler identities, time epoch/generation,
start/deadline, each expanded path's original/status/result reference, edge
baseline/stability/cooldown and consumed-root references. Step states distinguish
unsent, proposed, reserved, handed_off, waiting, completed, refused, failed,
unknown and cancelled.
Proposal generation changes unsent to proposed so retained-state recomputation
cannot emit it again. Handoff is an explicit host receipt after durable commit;
local queue and protocol responses remain below reported completion thresholds.
The kernel cannot know whether its returned state was durably retained.

Unknown halts dependent new work. Failure cancels unsent dependent work while
retaining started sibling originals/results. Cancellation retains consumed roots
and started receipts; it emits no compensating/stop effect. A stop requires a
new separately authorized original. All-required joins complete only when every
required branch completes. Aggregates preserve partial/unknown outcomes rather
than rewriting them as a single success/failure. Run deadline or invalid time
generation expires unsent continuation; already handed-off uncertainty remains.

### Closed retained execution representation

Prior input has exactly original, busy and edge. original/busy are explicit
null or a complete Run; edge is explicit null or the retained edge baseline.
No absent original is inferred from an empty cache. The host selects these
records from its durable original/current-run indexes.

Event requires kind, original and program_digest plus only its kind's members:
manual/cancel have no others; due has schedule_id, schedule_basis, due_ms, late_window_ms, clock_generation and time_zone_basis; elapsed_due has schedule_id, schedule_basis, due_elapsed_ms, late_window_ms, epoch, clock_generation and time_basis; fact has binding and fact_id; admission
has path, ref and outcome (held/refused); handoff has path and ref; result has
path, ref, stage, outcome and report_contract. Result report_contract is null
for queue/protocol stages and the exact installed reference for report stages.
Every path is a nonnegative integer vector of at most 32 members; compilation refuses a longer expanded path. No receipt sets a new program,
author, target, clock, grant or participant mapping.

Run has exactly format, original, program_digest, source_digest,
compiler_basis, epoch, clock_generation, start_ms, last_ms, deadline_ms,
status, steps, spent, window and reason. Format is wotex.routines.run@1.
Window is explicit null or the complete retained UTC due/elapsed_due descriptor selected by the compiled trigger. reason is
explicit null or a fixed bounded refusal code. Spent is the nonrefundable list
of held step originals and admission references, not a library-authenticated
claim about an external store. Each expanded node has one record in steps:
path, original, kind, status, started_ms, deadline_ms, branch and receipts.
The first three identify the exact compiled node. Optional coordinates and
branch are explicit null until established; branch is then/else for if.
Receipts is a closed seven-slot object: admission, handoff, local_queue,
protocol_response, correlated_report, reported_match and terminal. Each slot
is null or {ref, digest, outcome}; digest binds the complete input event.
First accepted stage receipts are retained. An exact duplicate keeps the slot;
a different event at an occupied stage refuses without replacing history.

Run construction regenerates all expected paths/originals from the complete
Program. Missing, extra, duplicated or altered records refuse. It checks all
status/receipt/spend/time coherence and selected bounds before transition.
Current input time cannot precede last_ms in the retained epoch; a changed
epoch/generation expires unsent work. Started/handed-off steps retain evidence
and uncertainty, with no physical retry. Source conditions gate a new run and
are rechecked before each new unsent effect. Selected if paths stay fixed;
no later condition change switches a partly executed branch. Wait is the only
condition construct that deliberately waits for future facts.

The transition is a closed object with run, proposals, basis, outcome and edge. Run
is a checked Run value, or null for skipped-busy; outcome is its status or
skipped-busy. Basis contains program_digest, source_digest, compiler_basis,
event, snapshot and time, preserving the
complete supplied collection, observation and clock data. Each inert proposal
has original (root), step_original, program_digest, path, binding,
installed_basis, thing_id, resource_roles, resource_domains, operation, input, completion and
evidence_contract. Domains are the sorted distinct resolved Thing and complete resource-role IDs. Data contains no priority, permission or transport handle. The host
must recheck this entire basis in its transaction before admitting work.
The host must persist skipped-busy against the event's original as well. A
busy Run from another program revision refuses correspondence; the host must
resolve revision replacement before supplying an executable current program.

For an existing original, repeating its original manual/due/elapsed_due event is an explicit
elapsed reevaluation, not another trigger. A UTC/elapsed due descriptor must remain exactly
the retained descriptor. Admission and handoff receipts refer to that original's
effect path; results require a retained handoff. Stage order is monotone:
local_queue, protocol_response, correlated_report, reported_match. A higher
stage may arrive without intermediate stages; lower new stages after a higher
one refuse, while exact duplicates retain their first receipts. Accepted stages
only complete at or above the installed threshold. After completion, a new stage refuses; exact duplicates still retain the completed outcome. Failed/unknown stages halt
the affected path. Cancellation and expiry may retain later qualified receipts
for already handed-off work, but never reactivate unsent paths. A changed clock
basis, regression, elapsed deadline or closed due window cancels unsent work;
uncertain handed-off work stays unknown. Effect deadlines are the minimum of the inherited run/child deadline and step start plus the installed deadline_ms. Installed duration/dwell/report qualification is part of the exact consumer-owned report contract; cooldown and repeat safety additionally remain host admission checks against retained whole-resource history. The kernel never treats an absolute input or elapsed delay as a report qualification. A false/unknown root or invocation
condition blocks new effects; a selected conditional branch stays selected.

### Collection and arbitration contract

Collection receives the complete bounded active Program list and a supplied
membership basis. It checks exact list identities before evaluating all eligible
definitions under one snapshot/time basis. The result still describes the
supplied membership; only the host's current transaction can establish that this
is the actual complete active set. A mismatched list refuses before proposals.

Arbitration takes all eligible proposals, explicit consumer constraint/override
dispositions and the same collection basis. Source data cannot assign authority
or priority. Hard refusal/unknown constraints filter first, current authorized
override dispositions next. Whole-resource domains then group compatible
effects: equivalence requires equal installed semantics, operation/input and
resolved participants. Equal-authority incompatible effects conflict without a
winner. Equivalent contributors and root references remain intact. Only after
this full-set result may the selected batch cutoff apply; discarded/suppressed
work never refunds roots or silently becomes a later catch-up burst.

Before implementation freeze the exact closed source/IR codecs, public types,
errors, selected profile limits and host transition values in executable schemas
and independent vectors. Every accepted construct must survive regeneration
from complete source and be represented in WRO.04 or explicitly unsupported.
Use one interpreter and a separate AST/transition oracle, not two copies of IR
execution. An old format never accepts a new operator by accident.

| Case | Requirements | Expected observation / falsifier |
| --- | --- | --- |
| WRO02-T1 | 01–03 | Closed/source-bound construction rejects altered IR, recursive or excessive expansion; identical inputs yield identical ordered decisions |
| WRO02-T2 | 02, 04 | Independent truth/edge/time traces preserve unknown, reset baseline, debounce/hysteresis/cooldown and generation expiry |
| WRO02-T3 | 03, 05 | Conflict beyond batch cutoff still conflicts; equivalent originals retain all accounting; membership mismatch refuses commit |
| WRO02-T4 | 02, 06 | ACK-only sequence, partial parallel failure, deadline and post-handoff cancellation never fabricate completion, compensation or resend |
| WRO02-T5 | 01–06 | Independent archive consumers execute the same scalar/event/slow-actuator procedure without shared private modules, schema or consumer terminology |

Implemented software evidence now includes `kernel_test.exs`: explicit receipt ordering, full due confidence, elapsed reevaluation, sticky branches, bound invocations, no-repeat spend, partial joins and post-handoff cancellation. Reported-edge qualification now has executable `edge_test.exs` traces. Complete-set collection/arbitration is exercised in `arbitration_test.exs`; independent transition/archive consumers remain unimplemented obligations.

### Closed reported-edge retention

`Edge.advance/7` takes the same Program/Event/Snapshot/Time/Profile/Limits as
Kernel and a null or retained Edge. It returns a closed object with edge,
eligible and reason. Reason is baseline, duplicate, unqualified, stable,
debouncing, cooldown or eligible. The event must be fact for the trigger's
binding and identify the complete snapshot Fact. No missing Fact is inferred.

Edge format is wotex.routines.edge@1. Its exact members are format,
program_digest, binding, binding_basis (the complete Snapshot binding-basis
record), epoch, clock_generation, last_elapsed_ms, last_receipt_ms,
last_sequence, last_fact_id, last_fact_digest, baseline, candidate_since_ms,
cooldown_until_ms and last_original. Baseline is true/false/null: true means
the trigger's active side, false its inactive side, null no qualified baseline.
Sequence/fact/digest/receipt coordinates and last_original are explicit null
until established. Candidate is a nullable elapsed coordinate; cooldown is a
nonnegative elapsed coordinate. Native values, identities, coordinate ordering
and coupled null members are revalidated before use.

A fresh continuous qualified sample establishes the first baseline and emits
no edge. Boolean active means true for rising and false for falling. Integer
active means value >= enter for rising, <= enter for falling; inactive means
value <= exit for rising, >= exit for falling. Between thresholds retains the
existing baseline, or null without a baseline. Thresholds use exact installed
units. Binding/source/clock replacement, elapsed or receipt regression,
non-increasing conflicting sequence, replay, expiry, unknown or lost continuity
resets qualification; none can create a transition. An exact repeated Fact is
idempotent and cannot advance debounce. A qualified sequence/fact identity reused with
changed content refuses rather than replaces the retained sample.

An inactive-to-active sample starts debounce. Eligibility requires another
qualified continuous active sample at or after the explicit interval, except
zero debounce is immediate. An inactive or unqualified sample clears the
candidate. Only caller-supplied new reports advance this interval. Eligibility
sets the active baseline and generation-bound cooldown. A transition during
cooldown is suppressed and sets the active baseline; it never becomes a delayed
catch-up edge. Durations and coordinates remain within selected number bounds.

Kernel transitions additionally retain edge (explicit null for other triggers).
A fact input advances the edge before overlap arbitration. No edge returns
run=null, no proposals and outcome no-edge; a busy eligible edge is retained as
skipped-busy and cannot be caught up later. Existing original runs may continue
on their fact event without a new edge. Original durability and complete report
continuity remain consumer obligations; this bounded retained value is not a
replacement for either.

### Closed collection and disposition seam

`Collection.evaluate(input, profile, limits)` takes the closed input membership,
entries and time. Membership has generation and programs (distinct complete IR
digests). Entries contains exactly one closed program, event, snapshot and prior
record per listed digest. Event is explicit null when the host has no trigger
or continuation for that definition; all other members remain mandatory. Every
Program, Snapshot and Prior is checked even for an idle entry. Entries are raw
JSON data; nested native objects refuse at this whole-set boundary. Snapshot
id, membership_generation and active_programs are identical across entries and
match membership; shared resource revisions and shared Thing/affordance/operation
observation slots must agree completely. Each local binding name remains scoped
to its program. Time is one complete common Time. This supplied membership and
these supplied events are host assertions; the library cannot prove omissions
against an external active-definition or event index.

The checked Collection has exactly format (wotex.routines.collection@1), input,
profile, json_limits, transitions, proposals and collection_digest. Transitions
are ordered program_digest/result records; idle result is null. Proposals are
ordered by program digest and integer path, after evaluating the entire set.
The total proposal count must fit pending_work before any batch limit. The distinct current nonterminal runs across retained and advanced records must fit active_runs; an advanced record replaces its retained identity for that count. Conflicting copies of one retained original refuse.
Collection.to_map/3 regenerates the entire result from retained inputs, rather
than trusting a digest or supplied proposal. Whole-set bytes/nodes/collections
obey JSON Limits in addition to Profile. Any malformed member or mismatched
basis refuses the whole collection without a partial admission result.

Proposals also retain exact resource_roles. Resource domains include the whole
resolved Thing ID and every distinct role resource ID. Role assignment is part
of equivalence; swapping role participants cannot be hidden by sorting domains.

`Arbitration.decide(collection, dispositions, batch_limit, profile, limits)`
requires one closed disposition per step_original: constraint allowed/refused/
unknown and override none/selected/suppressed. These are explicit current
consumer policy assertions, never source priorities or grants. batch_limit is
positive and no greater than pending_work. Constraints filter first, then
suppressed overrides. A selected override suppresses an incompatible ordinary
proposal sharing a whole-resource domain. Conflicting selected overrides remain
conflicts. Equivalent selected/ordinary proposals may share a dispatch while
retaining every contributor. No numerical authority rank is accepted.

Compatibility requires equality of installed_basis, operation, input, thing_id,
resource_roles, resource_domains, completion and evidence_contract. Any two
remaining incompatible effects sharing a domain mark their equivalence groups
conflicted; stable sorting never chooses a winner. After all pair comparisons,
nonconflicting equivalent groups are ordered by their earliest canonical
contributor and the batch limit applies. Each group retains full proposals as
contributors. Every step receives exactly one decision: constraint-refused,
constraint-unknown, override-suppressed, conflict, selected, coalesced or
batch-deferred. Result has collection_digest, dispositions, batch_limit,
selected and decisions. Selected contains contributor groups; decisions has
step_original and outcome. The complete Collection is retained by the host for
basis revalidation. The host persists every outcome against original ledgers
and supplies admission refusal for terminally rejected proposed steps; deferred
work follows explicit host bounded pending-work policy, never hidden catch-up.
Arbitration performs no charging, refund, override authentication or dispatch.

Countdown sources use a distinct elapsed_due event/window. The exact epoch and clock generation must match and elapsed_ms must be inside [due_elapsed_ms, due_elapsed_ms + late_window_ms); UTC confidence is never manufactured for countdowns. Both temporal trigger kinds require Event schedule_basis to match the complete compiled source. `temporal_test.exs` exercises these distinctions and schedule-basis replacement.

### Removed definitions and historical receipts

A program absent from Snapshot.active_programs cannot begin a new original.
For an already retained original, removal cancels all future unsent work with
reason inactive_program while preserving held spend and started uncertainty.
Exact duplicate or later qualified receipts may still be retained for the
original under its stored program/report contract. They cannot reactivate the
removed definition or advance a sequence into new effects. Historical terminal
outcomes remain interpretable; receipt retention supplies no current grant.
Collection still accepts only the current complete active set, so the host
reconciles removed originals through the direct Kernel seam and its durable
original indexes.

Unqualified input clears edge qualification before comparing retained identity. A caller reclassifying the same report as unknown/stale/lost never retains an old false baseline and never replaces the original sample digest. A conflicting qualified identity still refuses. On validation refusal that prevents a returned transition, the host must invalidate the affected edge baseline before future admission; an old baseline is not evidence that the rejected interval remained continuous.
