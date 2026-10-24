# WRO.04 — Analysis scope and semantic correspondence

Version: 0.2.20. Updated: 2026-10-24. Status: accepted target; implementation partial.

## Required outcomes

**WRO04-01.** Compile the same complete WRO.02 source-bound IR into runtime
decisions and supported semantic model projections. Generic rewriting/search
belongs to ExMaude; behaviour model compilation belongs to the routines package.
Consumer policy/proof obligations and final activation remain consumer-owned.
No backend success, schema validation or empty conflict list supplies admission.

Keep four result axes: input/model validity; findings; execution completion;
and consumer admission. Completion distinguishes bounded completed search,
truncation, timeout, unavailable backend, unsupported semantics and error.
A counterexample is a witness under named assumptions. Bounded absence remains
inconclusive where positive evidence is required.

**WRO04-02.** Every projection declares supported semantics, properties,
environmental changes, input domains, finite abstraction/horizon, fairness,
queue/time bounds and omissions. Relevant unknown/stale facts, source epochs,
multiple writers, overrides, partial/unknown effects, deadlines and causal roots
cannot disappear. Unsupported constructs return explicit unsupported scope
rather than a no-op model. A cycle witness needs its fairness/environment
qualification; an abstract witness is checked concretely before incident claims.

**WRO04-03.** Evidence binds exact source, IR/compiler, installed behaviour and
mapping, model closure/runtime, time-zone/clock policy, constraints and
effective budgets. Identity checks precede reuse. Changed dependencies or
consumer assumptions invalidate affected admission, not historical receipts.
Structural arguments are permissible only for an explicitly bounded supported
profile with independent runtime/guard correspondence.

**WRO04-04.** Keep an independent AST evaluator, calendar-day oracle and
transition reference that do not call production IR/recurrence/arbitration.
Mutations must expose dropped unknowns, steps/effects, complete-set members,
temporal guards, manual precedence and root accounting. A compile/harness
failure is not evidence that a behavioral assertion caught a mutation.

**WRO04-05.** Analysis execution is opt-in and consumer-supervised. Trusted
digest-addressed model bytes enter bounded workers; devices/profiles/voice
never supply raw Maude source or include paths. End-to-end budgets include
queue/preparation/native execution/parsing/result construction. Uncertain
workers retire before reuse; OS memory/process/file containment is a distinct
host requirement. Analyze definition/composition/assumption changes, not every
sensor event. Backend loss blocks fresh proof-required admission while applicable
admitted work continues with current runtime guards.

## Entry, compatibility and acceptance

The current ExMaude public API and its limited models are not silently promoted
to composed/temporal proof. Before code freeze projection profiles, result/error
values, evidence identity and independent trace/mutation corpus. Select any
producer enhancement in ExMaude itself; no proprietary consumer model belongs
in its generic kernel. Optional analysis remains absent from ordinary package
load and pure decision evaluation.

| Case | Requirements | Expected observation / falsifier |
| --- | --- | --- |
| WRO04-T1 | 01–02 | Unsupported timer/unknown/invocation semantics reject; timeout/truncation/empty bounded search never become positive admission |
| WRO04-T2 | 02–04 | Independent finite traces agree on every declared runtime property; listed behavior-changing mutations produce asserting refusals |
| WRO04-T3 | 03 | Change source, model, compiler, behaviour, time basis or policy after cache warming; affected evidence refuses reuse |
| WRO04-T4 | 05 | Worker failure/replacement/output bound cannot reuse stale evidence or starve ordinary control; native retirement and containment proved separately |

## Closed evidence/result boundary

`AnalysisResult.new/2` takes a complete closed JSON result and explicit Limits.
Format is wotex.routines.analysis.result@1. Exact members are format, binding,
validity, findings, execution, admission, reason, counts and effective_limits.
Binding has exactly scope_digest, model_digest, source_digest, ir_digest,
compiler_basis, behaviour_digest, mapping_digest, runtime_digest, policy_digest,
time_basis_digest and budget_digest; every member is a SHA-256 identity. They
bind different subjects and cannot substitute for one another.

Validity is valid/invalid/unsupported. Execution is completed_bounded/truncated/
timeout/unavailable/unsupported/error. Admission is only inconclusive/blocked;
this generic result carries no positive authorization. Findings is a finite
array of closed kind/property/trace_digest/concrete records. Kind is
counterexample; property is a nonempty bounded name; concrete is validated or
unvalidated. A validated concrete counterexample requires blocked admission even if execution
was truncated, but an abstract witness alone remains inconclusive. Invalid or
unsupported validity has no findings and cannot claim completed search.
Unsupported validity requires unsupported execution. Validated-witness findings
require valid input/model and completed_bounded or truncated execution. No
absence, zero count or schema validation becomes a positive finding.

Counts has states and transitions, each explicit null or nonnegative bounded
integer. Completed bounded execution requires both counts; other completion
states may lack them. Effective limits has exactly total_ms, max_states,
max_transitions, max_depth, max_model_bytes and max_output_bytes. All are explicit
positive selections: total_ms <=60000, max_states <=100000,
max_transitions <=1000000, max_depth <=256; byte bounds are no greater than
Limits.max_bytes. Reported counts cannot exceed their selected bounds. budget_digest is the canonical SHA-256 of effective_limits; altered selections cannot retain the old budget binding.

Reason is explicit null or model_invalid, scope_unsupported, budget_exhausted,
backend_unavailable, counterexample, incomplete, correspondence_failed or
stale_evidence. Completed bounded absence has null reason/inconclusive admission;
blocked admission requires a validated concrete witness and counterexample
reason. Unknown fields/axes, unsupported combinations, duplicate property/trace
identities and exceeded bounds refuse with payload-free Error.

`AnalysisResult.to_map/2` revalidates. `AnalysisResult.current/3` additionally
requires the complete expected binding and compares every subject before reuse;
changing policy, time basis or budget invalidates cached correspondence just as
changing source or runtime does. Constructors verify bounded shape and declared
consistency, not authenticity of supplied evidence or a consumer's assertion
that a witness was concretely validated. The producer adapter/replay seam must
establish that validation; the host independently owns evidence custody and
final admission. A caller-built native result is not trusted merely by its type.

Implemented result-boundary evidence is `analysis_result_test.exs`: completed bounded/empty search cannot authorize, abstract witnesses remain inconclusive, every correspondence subject invalidates reuse, and budget/axis/native-value inconsistencies refuse. Projection, generic witness replay, additional scoped reference/mutation profiles and optional backend execution remain obligations.

## Independent transition reference profile

The first transition reference consumes original source AST, explicit pinned
child definitions, prequalified predicate values, binding effect deadlines and
a finite sequence of caller-supplied events/times. It never consumes compiled
IR or calls production compilation, truth, receipt, execution or arbitration
helpers. The test harness alone compiles the same source for the public Kernel
and compares the two results. Source/definition validation, exact unit
conversion, fact qualification and calendar expansion have their own acceptance
lanes; they are not inferred from prequalified oracle inputs.

The finite reference profile covers manual roots; literal/comparison and nested
three-valued predicates; absolute effects; sequence; all-required parallel;
sticky conditional choice; finite waits/delays; and parameter-free pinned child
invocation with its own condition/duration. Parameter unit conversion, temporal
trigger identity, edge qualification and collection arbitration remain separate
reference profiles. Unsupported reference input fails the harness explicitly;
it never supplies an expected no-op.

Compare every transition's aggregate outcome/reason, canonical step paths and
kinds, statuses, selected branches, start/deadline coordinates, retained receipt
references/outcomes, spent root references and ordered proposal binding/input/
completion. Check original identities for stability and uniqueness separately;
the reference does not call the production identity hash. Include duplicate,
out-of-order and conflicting receipts, admission refusal, below-threshold ACK,
unknown/failure, cancellation before/after handoff, later historical evidence,
deadline equality/regression/generation change, and definition removal.

Behavioral mutation checks run isolated production-module replacements against
the same assertions. A baseline run must pass first. Each declared single-site
mutation must compile and reach ExUnit, then fail an assertion; missing mutation
sites, compile errors, crashes or timeouts are harness errors. Initial mutations
drop unknown under comparison, advance on a protocol ACK below a reported-match
threshold, omit a parallel branch, ignore the root elapsed deadline, discard
held spend, and allow effects through a false/unknown root gate. These checks
establish sensitivity only to those mutations in the declared finite profile.
They do not complete model projection, calendar/reference-set mutations, native
containment, consumer transaction evidence or physical qualification.

Executed finite-reference evidence is `correspondence_test.exs` and the independent predicate cases in `evaluation_test.exs`. `bin/check_correspondence.exs` executes a passing baseline and six isolated replacements; its formatter distinguishes assertion failures from harness errors. These are software correspondence checks for this reference profile, not a completed analysis/admission gate.

## Bounded concrete witness replay

`Witness.replay(program, witness, profile, limits)` is an opt-in pure check of
one finite claimed runtime-property counterexample. It invokes the public
Kernel with the supplied frames and its own bounded mathematical original
ledger. It is not a model search, a calendar oracle or an authenticated Store.
All facts/time/receipts remain explicit caller assertions. Reproducing a
violation establishes that this trace violates the named software property
under those inputs; it does not establish that a device or host experienced it.

Witness is closed JSON with exactly format, property, program_digest,
source_digest, compiler_basis, max_steps, max_originals, initial and frames.
Format is wotex.routines.witness@1. The three program subjects must match the
complete current regenerated Program. max_steps is positive and <=256;
max_originals is positive and <=1024. Both also obey JSON Limits. frames is a
nonempty ordered array no longer than max_steps; each frame has exactly event,
snapshot and time, using WRO.02's complete values. There is no implicit clock,
empty snapshot, receipt, original or authority. initial has exactly runs and
edge: runs is a bounded array of fully checked Runs for distinct originals of
this Program, with at most one nonterminal run; edge is explicit null or its
fully checked Edge. Total retained originals never exceeds max_originals.
Unknown members, stale subjects, invalid retained values, incoherent histories,
unsupported properties and exceeded input/work/output bounds refuse.

Before each frame choose its retained original and the sole current busy run;
call Kernel once and retain its returned Run/Edge before the next frame. A
Kernel refusal ends replay with its typed refusal and no reproduced finding.
Only returned transitions are evidence; callers cannot supply claimed outputs.
Terminal originals stay in this replay ledger. It performs no compaction,
Store operation, admission callback or physical repetition.

The initial property vocabulary is finite, rather than executable caller text:

| Property | Concrete violation |
| --- | --- |
| proposal_once | A step original is proposed twice, including one already started in initial retained history |
| held_spend_retained | A previously held exact original/ref pair disappears or changes on that original's next transition |
| stopped_continuation | A previously completed/refused/failed/unknown/cancelled/expired/partial root produces a new proposal |
| completion_evidence | A completed effect lacks its handoff or accepted receipt at/above its installed completion threshold |

Property checks inspect returned public records independently of production
receipt/execution helpers. The effect paths/thresholds come from the complete
current IR; all possible paths, including invoked/conditional copies, count.
This vocabulary does not claim liveness, fairness, physical causation,
authority validity, completeness of environmental inputs or complete-set safety.
Those require independently declared projection/property profiles.

Successful output has exactly format (wotex.routines.replay@1), property,
trace_digest, program_digest, source_digest, compiler_basis, reproduced,
violation_step and transitions. The trace digest binds the complete checked
Witness; it is not authenticity. reproduced is Boolean; violation_step is the
first zero-based violating frame or explicit null when none. Continue the finite
trace after a violation so receipts/history remain reviewable; any later refusal
invalidates the complete claimed trace. transitions retains all complete Kernel
results in frame order. The whole output obeys JSON Limits. A valid finite trace
with reproduced=false is not positive admission or proof of universal safety.
An analysis adapter may mark a finding concretely validated only after matching
its complete model/assumption binding and reproduced=true for the named property.

Acceptance covers valid nonviolating staged/cancelled/history traces, a false
witness claim, stale program subjects, empty/extra/over-budget input, invalid or
foreign retained histories, complete output/digest stability, and deliberate
property-violating returned-record mutations caught by these checks. Public
replay integration and property-check sensitivity remain separate evidence;
an invalid forged Run is not a concrete counterexample.

Implemented replay evidence is `witness_test.exs`: public replay validates finite trace/history/subject bindings, rejects false or malformed claims, retains staged/cancelled history and enforces amplification bounds. Separate returned-record mutation tests exercise all four property checks; their forged records deliberately refuse public replay. The shipped `wro-04-witness.schema.json` reconciles WRO.02 execution definitions offline and describes both input and output. Wider model projection and analysis-adapter correspondence remain open.

## First inert proposal projection

`Model.compile(program, scope, profile, limits)` is pure compilation to an inert
model artifact, not a search or admission. The first projection profile is
proposal-prefix@1, purpose proposal_generation_only. It supports exactly one
manual, unconditional literal-true, parameter-free Boolean writeproperty effect
at root path []; overlap is reject. There is one declared/resolved binding and
no child definitions. Unsupported predicate/trigger/type/operation/step/closure
refuses explicitly; no effect or unknown predicate becomes a no-op model.

Scope is a closed required object: profile, purpose, initial_history,
time_policy, environment, claims, omissions and policy_digest. Required values
are proposal-prefix@1, proposal_generation_only, no_existing_run,
frozen_before_deadline, and manual_and_cancel_one_original, respectively.
claims is exactly [proposal_once, fixed_absolute_proposal]. omissions is exactly
[admission, handoff, receipts, time_progress, fact_changes, multi_original_overlap,
authority, complete_set_arbitration, physical_effects]. policy_digest is an
explicit consumer-verified SHA-256 assumption identity, not a grant.

The finite environment starts with no original history, one active current
program, unchanged source/mapping and a fixed valid elapsed/clock epoch before
the root/effect deadline. Its valid trace alphabet is manual submission/replay,
and cancellation once an original exists. No admission or handoff ever occurs.
Unknown/partial physical outcomes and device-behaviour analysis are outside
this pre-admission horizon; the installed basis's device model classification
is not promoted. No fairness, time progress or liveness property is claimed.
Any receipt, time/environment change or other-original trace needs another
declared supported projection; this artifact cannot evidence those obligations.

The transition model has fresh/count0, proposed/count1 and cancelled/count1
states. The first manual event emits the exact compiled absolute Boolean and
fixed target/basis. Duplicate manual events emit nothing and keep count1.
Cancellation emits nothing and preserves count1; manual/cancel replay after
cancellation cannot produce another effect. Cancel with no original is a
Kernel refusal and outside the valid alphabet. Model count denotes emitted
inert proposals, not held-root spend. The full effect descriptor and complete
current Program remain in the artifact; source/IR/compiler identities stay
distinct. Model symbols are installed static syntax; no source/profile/Thing
string becomes Maude code or an include path.

Artifact has exactly format (wotex.routines.model@1), program, scope,
scope_digest, model_bytes and model_digest. Digests bind canonical scope and
exact generated model bytes, respectively. Full regeneration in Model.to_map/3
and Model.current/5 rejects altered native artifacts even with recomputed
digests. The complete output/model bytes obey JSON Limits. Scope is not inferred
from a backend query or default. Optional execution budgets and full evidence
binding are supplied by the separately owned analysis runner; loading/compiling
this artifact starts no worker or filesystem operation.

Acceptance compares model prefix transitions/values against independent source
and public Kernel cases for both Boolean inputs, manual duplicates and
cancellation. Test unsupported unknown/timer/invocation/parallel/parameter
profiles, changed policy/source/compiler and recomputed forged model bytes.
Native checker execution, widened temporal/receipt/composition projections and
complete-set/physical properties remain separate obligations. A completed
bounded query with no counterexample remains inconclusive for admission.

Implemented prefix projection evidence is `model_test.exs`: both Boolean values and actual emitted model-transition syntax agree with public Kernel prefixes; unknown/timer/invocation/composition/parameter profiles refuse; changed subjects and recomputed forged bytes fail regeneration. Native prefix execution is separately exercised by the exact archive lane below; wider projections remain separate obligations.

The opt-in archive lane `bin/check_archive.exs --model-consumer --maude-path /absolute/maude` selects exact released ExMaude 0.5.0 in a fresh consumer and supplies explicit per-search absolute deadlines/response bounds. [Its cohort record](../provenance/model-archive-cohort.md) binds three passing native/code-identity tests and the abstract model mutation that actual Witness replay does not reproduce. This historical lane predates the package runner below and does not establish its complete budgets/containment. The initially refused abbreviated Boolean query was diagnosed and rerun successfully with explicit `= true`, preserving the producer exact-token echo guard. Only the recorded canonical form has executed evidence.

## Explicit proposal-prefix execution boundary

`Analysis.run(model, request, options, profile, limits)` is an explicitly invoked,
synchronous, opt-in operation. The consumer runs it in its own supervised task
and bounds its admission queue/concurrency. The package starts no persistent
worker, queue, registry or callback. Each public ExMaude search uses a separate
retired Port session. Loading routines does not select or start ExMaude.
The optional backend requirement is exact released ExMaude 0.5.0; absence returns
unavailable evidence. No consumer may supply raw model/query/include text here.

Request is closed JSON with exactly format, binding, effective_limits, runtime
and time_basis. Format is wotex.routines.analysis.request@1. binding and
effective_limits have the exact AnalysisResult vocabulary above. runtime is
closed: ex_maude_version (0.5.0), ex_maude_digest (consumer-retained exact package
closure SHA-256), executable_digest, executable_version, parser_version
(ex_maude.search-run.v3) and backend (port). The latter executable identities
are checked against every actual SearchRun receipt; package version is checked
against the selected loaded dependency. Package closure custody/authenticity
remains the consumer's responsibility. runtime_digest hashes this complete
record. time_basis is the complete WRO.02 Time supplied for the frozen prefix;
time_basis_digest hashes it. This operational analysis clock is distinct from
that semantic time assertion.

The runner regenerates the full Model before backend use. scope/model/source/IR/
compiler/policy bindings come from that artifact. behaviour_digest hashes all
retained installed bases; mapping_digest hashes the complete registry and
binding map; budget_digest hashes the selected effective_limits. Every expected
binding must match, including runtime/time. Unknown members, unsupported models,
stale subjects, malformed native inputs or impossible selections return a
payload-free refusal before search. No supplied result/native artifact is trusted
by struct type alone.

Options is a closed native map with maude_path (explicit absolute UTF-8 path)
and deadline_ms (signed timestamp from this VM's monotonic millisecond clock).
The consumer establishes this deadline before its queue using the selected
total_ms. At entry the runner also caps it at entry+total_ms; it never extends a
queued request's deadline. Queue expiry, regeneration, preparation, each native
query, parsing and construction share this deadline. Expiry clears findings and
counts and returns timeout/inconclusive/budget_exhausted. Checks before and after
each phase prevent late evidence reuse; filesystem/cleanup/scheduler latency
is not a hard real-time or OS containment guarantee. Caller loss is handled by
ExMaude's public per-search retirement contract; consumer supervision owns caller
lifecycle. A failed/uncertain session is never reused or automatically replayed.

The proposal-prefix scope has exactly three reachable prefix states and five declared rewrite
edges, including self-loops. These are model-profile counts, not undocumented
backend transition statistics. max_states<3, max_transitions<5 or max_depth<2
returns truncated/inconclusive/budget_exhausted before native work. The fixed
native query enumerates the three states at depth 2 with solution limit 4, so a
solution cutoff cannot masquerade as exhaustion. A second fixed query checks
the requested Boolean literal. Every query passes the shared absolute deadline,
remaining timeout and max_output_bytes to SearchRun. A completed result requires
both complete receipts, the exact three canonical states and the exact requested
literal. Changed executable/parser/model identity or mismatched correspondence
returns error/inconclusive/correspondence_failed, with no findings or counts.
Timeout, unavailable, worker/parser failure and truncation remain distinct.
Backend truncation or unsupported receipt shapes never become completion.

The runner emits only checked AnalysisResult values, with no positive admission.
This initial profile emits no concrete counterexample: unexpected native states
are correspondence failure, not a concretely validated runtime incident.
Completed bounded absence has null reason, counts 3/5 and inconclusive admission.
Generated model bytes obey max_model_bytes; oversize work returns truncated.
Complete returned JSON obeys both Limits and max_output_bytes; if even the
bounded result cannot fit, return analysis_output_bound without partial output.
No raw native stdout, private executable path or backend error payload is copied
into evidence. Unsupported wider receipt-history/time/composition/complete-set projections,
concrete model-witness translation and OS containment retain their own gates.

Acceptance includes expired queued requests with no backend invocation, shared
remaining deadlines, both Boolean values through the released native facade,
all eleven changed binding subjects, regenerated model forgery, low model/state/
transition/depth/output budgets, backend absence/loss/parser/output cutoff,
changed runtime identity and unexpected state/literal correspondence. Bounded
absence never becomes admission; adverse fake backend tests establish adapter
control flow, while extracted-archive native tests establish the selected public
producer seam. Neither establishes hard real-time or physical qualification.

Implemented runner evidence is `analysis_test.exs`: seven focused groups cover
all bindings, forgery, queue expiry, shared deadlines, selected work/output limits,
backend loss/truncation and changed native identities/correspondence. The shipped
`wro-04-request.schema.json` describes the complete offline request. Native
runner evidence is recorded in the [runner cohort](../provenance/analysis-runner-cohort.md)
through the extracted archive lane.

## Staged software-receipt projection

The additive `receipt-prefix@1` Model scope has purpose
software_receipt_transitions_only, initial_history no_existing_run,
time_policy frozen_before_deadline and environment
manual_staged_receipts_one_original. It retains the same closed eight scope
fields as proposal-prefix. Claims are exactly proposal_once, held_spend_retained,
completion_evidence and stopped_continuation. Omissions are exactly
[authority, time_progress, fact_changes, multi_original_overlap,
complete_set_arbitration, historical_receipts, physical_effects]. Policy digest
remains an explicit consumer assertion. Installed device-analysis support is
not promoted: this model describes the software kernel receiving qualified
host assertions, rather than a device producing them.

Source support is the same single manual unconditional parameter-free Boolean
writeproperty effect, additionally requiring completion reported_match. No
sequence, wait, invocation, other threshold or unknown predicate is approximated.
The environment has one unchanged active program/binding, a fixed valid clock
before every deadline and immutable references for each accepted receipt stage.
Its finite alphabet is manual (including duplicates), held/refused admission,
handoff, accepted protocol_response, accepted reported_match, failed/unknown
protocol_response, and cancellation. Result stages require held/handoff;
reported_match may skip protocol_response. Repeated receipts must be exact
logical duplicates. All post-terminal receipts (including duplicates), local_queue, correlated_report,
other stages/outcomes, grant checks and changed environmental inputs are outside
this declared profile, not inferred successful transitions.

A state records effect phase, emitted-proposal count, retained-held count,
handoff Boolean, evidence (none/ack/match) and stopped-root Boolean. Effect
phases are fresh/proposed/reserved/handed/completed/refused/failed/unknown/
cancelled; they are normalized step phases, not an aggregate physical outcome.
Manual creates one proposed effect; duplicates emit none. Held adds one retained
spend; refusal adds none. Handoff changes only a reserved effect. ACK leaves
handed status/evidence ack; reported_match completes it with evidence match.
Failed/unknown protocol_response outcomes before any accepted ACK stop the root
and retain held/handoff/evidence. An accepted ACK cannot be changed to a conflicting
outcome under the same immutable receipt slot. Cancel
changes proposed/reserved to cancelled and handed to unknown, preserving spend;
already terminal step records stay unchanged. Cancellation/manual duplicates
never emit a new proposal. Historical post-terminal receipt evolution remains
outside this scope, while its stopped-proposal claim covers manual/cancel input.

All model symbols and rules are installed syntax. Only the checked Boolean
literal enters code; receipt/Thing/author/ref strings never become executable
text. Model regeneration, size/identity and current-scope checks apply unchanged.
The additive receipt Analysis runner uses only ROUTINE-RECEIPT-PREFIX with
initial state(fresh, 0, 0, false, none, false), pattern S:State, depth 5 and
solution limit 13. A second fixed requested/B:Bool query retains the exact
source Boolean. Its independent finite alphabet in
priv/vectors/wro-04-receipt-prefix.json has 12 reachable states and 37 labelled
state-transition edges including self-loops; the longest shortest-state path is
five transitions. These are installed profile counts, separate from native
backend statistics and the 30 schematic rewrite rules. Every returned state
must match the complete canonical tuple set exactly, with no duplicate, missing
or foreign states. The native order is irrelevant. Completion requires both
checked receipts and the source literal. max_states<12, max_transitions<37 or
max_depth<5 refuses as truncated/inconclusive/budget_exhausted before search.

Successful bounded enumeration returns counts 12/37, null reason, no findings
and inconclusive admission. Changed runtime/binding, held-spend/evidence/root
state or Boolean literal returns correspondence_failed with cleared counts.
Shared queue-inclusive deadline, output/model bounds, timeout/truncation/backend
absence and redaction follow the runner contract above. Unknown scopes refuse before search; a receipt scope cannot select the proposal module,
query or counts. No counter-state is classified as a concrete incident until a
separately supported translation and actual Witness replay establish it.

Acceptance interprets the emitted literal rules, compares every modeled state
component to the public Kernel and independent source AST under the same explicit
valid finite alphabet, and covers held/handoff/ACK/report, skipped ACK, refusal,
failure/unknown, cancellation before/after handoff and manual/cancel duplicates.
Both Boolean values retain their exact proposal. Native scope execution and a
mutated ACK-completion counter-state require separate extracted-archive evidence;
abstract violations require actual Witness reproduction before incident claims.
Wider time/composition/complete-set projections and physical evidence remain open.

Implemented receipt-prefix evidence is `receipt_model_test.exs`: eighteen finite
traces (both Boolean values over nine staged/cancel/failure paths) compare every
emitted state component with both the public Kernel and independent source AST.
Unsupported installed completion thresholds and incomplete runner requests
refuse; regenerated native model forgery fails. The extracted native model
consumer additionally enumerates this scope, retains held/ACK/cancel distinctions,
and finds an ACK-completion mutation's abstract counter-state. Those native
counter-states are not concrete runtime incidents or admission.

The [receipt-model cohort](../provenance/receipt-model-cohort.md) binds native
execution and independent finite-prefix evidence to its exact source/archives.

The [quality milestone](../provenance/quality-milestone-2026-10.md) passes the
unchanged full gate and renews all four exact-archive consumer lanes together.

The receipt Analysis runner now passes three additional focused groups over both
Boolean literals, its independent 12-state/37-edge oracle, distinct query/budget
selection, queue expiry and state mutations for ACK completion, lost held spend,
stopped roots and duplicate/missing state sets. The renewed archive consumer
executes both literal values through Analysis.run/5; it keeps completed bounded
results inconclusive. Wider receipt history/time/composition/complete-set and
concrete witness translation obligations remain open.
The [receipt-runner cohort](../provenance/receipt-runner-2026-10.md) retains its
exact source, archives, interpreter, lock and executed checks.

## Continuation correspondence successor

The [bounded run continuation contract](bounded-run-continuation-v1.md) adds
explicit Time@2/Run@2, unsent satisfaction and complete pending Collection@2.
Model and Witness boundaries must either preserve the complete supported
semantics or return unsupported scope; omission, clock relabelling, a fabricated
handoff or loss of retained pending contributors cannot establish correspondence.
Concrete Witness replay now retains complete Time@2 frames and Run@2 results;
its native delay/resume case passes in the 137-case affected caller run.
Concrete satisfaction replay now checks all four runtime properties without
fabricating handoff evidence; actual accepted Runs and replay frames/results
validate against the frozen schemas. A requested satisfaction environment
explicitly refuses unsupported_model_scope in the existing frozen staged Model.
These are native cases in `test/wotex/routines/satisfaction_test.exs`.
A requested complete-pending arbitration environment also explicitly refuses
unsupported_model_scope, exercised in
`test/wotex/routines/pending_collection_test.exs`. Frozen model identities retain
their exact omissions. The [bounded continuation milestone](../provenance/bounded-continuation-2026-10.md) now passes
independent source/journal continuation consumers and all ten assertion-only
mutations with zero harness errors. The full owning gate passes 241 tests at
95.5% coverage, including package Dialyzer. This closes the bounded successor's
explicit concrete/unsupported-scope correspondence. Wider supported models,
model/witness translations, containment and current consumer admission retain
their broader obligations.

## Independent decision verification target

[The verified-decision successor](verified-decision-v1.md) owns independent
point transition/complete pending/arbitration checks and canonical time-cell
correspondence. It verifies supplied conclusions without calling the forward
transition engine. Isolated forbidden-call checks, independent source/receipt
and all-pairs oracles, two extracted consumers and assertion-only mutations
are required. Full VD-T1–T14 remain open; existing replay/archive evidence does
not prove this verification scope. Frozen Model/Analysis profiles retain their
explicit unsupported boundaries and supply no consumer admission.

The successor entry schema and vectors now pass five native representation
checks, including 52 malformed/missing-field cases and all six clock-cell
alternatives. This is representation evidence; it does not establish runtime
correspondence.

The public Transition.verify/8 point checker now validates complete normalized
arguments, qualified observations, edge state, receipts/spend, step motion,
terminal outcomes and ordered proposals independently of forward execution.
A 113-case affected corpus checks 1,152 complete point transitions and 72 direct
edge relations with all eight prohibited forward functions disabled during
proof. Six isolated point mutations fail through assertions with zero harness
errors. The [point record](../provenance/verified-transitions-2026-10.md) binds
source/test identities and exact direct scope; that record alone does not
establish the complete-decision layer or current consumer authority.

Public Decision.verify_point/4, new/3, to_map/3 and check/4 now independently
verify complete Collection@2 membership, retained pending state, canonical
cells/digests, exact current input and whole-set arbitration before cutoff.
The guarded native lane passes 41 tests with all nine forward seams disabled
during proof, including 70 prepared complete collections and seven arbitration
relations. Fifteen new cases include an independent all-pairs oracle over 162
policy/batch combinations, 1,024 contributors with a final supplied conflict,
a 1,023 refusal, both Time grammars and exact argument/output byte bounds.
The [complete-decision record](../provenance/verified-decisions-2026-10.md) binds
this native evidence. Independent raw-source/journal archive consumers,
complete-verifier mutations, full VD-T1–T14 and the owning milestone remain
open. No consumer authority, host/physical qualification or wider Model scope
is supplied.

The [verified-decision archive profile](../decisions/verified-decision-archive-profile.md)
now freezes distinct source/journal oracles, complete finite case counts, exact
cohort/lock/source identities, all six assertion-only semantic mutations in both
families and owned-workspace cleanup. This is accepted implementation entry;
the new archive lane and its evidence remain unimplemented.

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

## Accepted archive resource-bound renewal

The [VDA-T8 archive profile](../decisions/verified-decision-archive-profile.md#vda-t8--resource-bound-renewal-target)
requires independent argument/output accounting across both Time grammars and
all selected JSON resource axes. Its source preflight is implemented; extracted
archive execution remains pending. This qualification addition changes no runtime
grammar and does not close the combined verifier or consumer-host milestone.
