# WRO.03 — Temporal calculation and consumer host

Version: 0.1.0. Updated: 2026-10-13. Status: accepted target; implementation planned.

## Calculation seam

**WRO03-01.** Use ExBooking's public original-occurrence API (SP.08) directly
for its supported recurrence subset. Preserve original nominal local start,
UTC due instant, ordinal, resolution and exact time-zone basis. Never derive
an original from a duration-bearing clipped availability interval. Recurrence,
availability/reservation decisions and monotonic delay are different operations.
No fake booking resource or meeting type is needed for an event or cooldown.

The provider accepts explicit finite horizon, work/page bounds, installed
database/basis and continuation. COUNT is global from DTSTART, recurring gaps
skip without consuming COUNT, later folds use the first instant and query
until is exclusive. The adapter rejects unsupported recurrence/policy rather
than approximating it. Calendar one-shots, UTC intervals and elapsed countdowns
retain their separately declared semantics.

**WRO03-02.** A consumer supplies authoritative clock confidence, generation
and occurrence eligibility policy. Libraries supply no trusted now. Calendar
zone/tzdata is bound to a definition; OS zone changes do not edit it. An admitted
effect requires the whole confidence interval within its occurrence window,
including final unsent handoff. A generation/correction invalidates old UTC
projections. Backward correction cannot repeat considered work; forward
correction skips elapsed windows. Elapsed countdown/delay coordinates are
boot-scoped and cannot silently survive restart.

## Consumer transaction contract

**WRO03-03.** Host calls use immutable revisioned snapshots and pure transition
proposals. The host must atomically revalidate:

- Current original author, input/target grants and authority generation.
- Complete active-set membership, program/profile/behaviour/proof identities.
- Resource/fact revisions, continuity, current constraints and overrides.
- Current time generation/window, capacity and causal/no-repeat accounting.

The host reserves original occurrence/run/step identities and root spend in
the same transaction as held work or a terminal blocked/missed outcome.
Logical retry recovers the original record. Claim/final handoff repeat mutable
guards; transport starts only after the durable handoff marker commits.
No database handle, credential or unrestricted driver enters the kernel.
A host returning unconditional success is not a conforming integration.

**WRO03-04.** An optional wakeup driver is an explicit consumer-supervised child
with finite queue/batch/work bounds and owned cancellation/retirement. Loading
the package starts nothing. Client/verifier loss does not stop valid owner work.
Default missed policy is skip, with bounded considered-through/missed-range
summaries; compaction preserves the no-repeat boundary. Saturation cannot
produce a delayed catch-up burst. Higher-risk response capacity is a separate
consumer lane, never consumed implicitly by ordinary routines.

**WRO03-05.** Restart, transfer and restore remain consumer transitions.
Same-owner restart resumes only a still-valid admitted profile/basis; boot-local
waits expire. Restored/copied definitions grant no authority. Unknown handed-off
effects remain retained and are reconciled without repetition. Device/external
schedulers have separately attributed ownership: rejecting a kernel proposal
does not disable them. Timer migration requires a recoverable staged consumer
operation, not an atomic transaction claimed across a remote device.

## Compatibility, entry and acceptance

Existing core/Runtime dependencies and ExBooking availability policies remain
unchanged. Before delivery freeze public driver/host callbacks, exact
proposal/snapshot/result types and ExBooking adapter vectors. Select coherent
producer releases explicitly; no hidden sibling calls or dependency update
is implied by this target. The package has no storage engine or application.

| Case | Requirements | Expected observation / falsifier |
| --- | --- | --- |
| WRO03-T1 | 01–02 | Independent SP.08/adapter vectors preserve original times across clipping, pages, folds/gaps, COUNT and tzdata change |
| WRO03-T2 | 02–04 | Duplicate ticks, correction, sleep/wake, restart and saturated queue produce no repeat or out-of-window handoff |
| WRO03-T3 | 03, 05 | Real host transactions race grants, active membership, resources and cancellation; stale work sends nothing and unknown remains history |
| WRO03-T4 | 03–05 | Archive consumer owns its store/driver and performs fault-injected reserve/claim/handoff/settle; package load and pure evaluation perform no I/O |

Software clock fixtures do not qualify a host oscillator, sleep behavior or
physical response. Every consumer records those evidence layers separately.
