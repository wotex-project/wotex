# WRO.02 — Bounded routine source and pure kernel

Version: 0.2.3. Updated: 2026-10-13. Status: accepted target; implementation partial.

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

Triggers are closed manual, due or reported-edge descriptors. Manual has only
kind. Due has kind and schedule_id; WRO.03 supplies its original coordinate.
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

Snapshot requires identity, membership generation, active program identities,
resource revisions, current binding/profile/source/clock identities and complete
Fact data for provided bindings. Time requires epoch, elapsed_ms, clock_generation
and explicit UTC low/high millisecond coordinates (or both null). UTC coordinates
are ordered; elapsed regression or epoch change expires unsent elapsed waits.
Trusted source age uses WRO.01's clock basis/uncertainty and the complete current
UTC interval. Missing trust/basis, future source intervals, incompatible units,
expired receipts, unusable quality or unaccepted source classes produce unknown.
Receipt freshness and source age remain separate checks. Replayed/retained or
baseline/lost continuity cannot create an edge.

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

Run state binds original, program/compiler identities, time epoch/generation,
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
