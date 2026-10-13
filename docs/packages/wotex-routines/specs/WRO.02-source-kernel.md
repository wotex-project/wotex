# WRO.02 — Bounded routine source and pure kernel

Version: 0.1.0. Updated: 2026-10-13. Status: accepted target; implementation planned.

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
