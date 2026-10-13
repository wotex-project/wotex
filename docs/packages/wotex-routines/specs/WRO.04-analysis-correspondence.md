# WRO.04 — Analysis scope and semantic correspondence

Version: 0.1.0. Updated: 2026-10-13. Status: accepted target; implementation planned.

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
