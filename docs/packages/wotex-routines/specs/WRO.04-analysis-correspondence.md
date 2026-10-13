# WRO.04 — Analysis scope and semantic correspondence

Version: 0.2.0. Updated: 2026-10-13. Status: accepted target; implementation partial.

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

Implemented result-boundary evidence is `analysis_result_test.exs`: completed bounded/empty search cannot authorize, abstract witnesses remain inconclusive, every correspondence subject invalidates reuse, and budget/axis/native-value inconsistencies refuse. Projection, concrete replay, scoped model/mutation corpus and optional backend execution remain obligations.
