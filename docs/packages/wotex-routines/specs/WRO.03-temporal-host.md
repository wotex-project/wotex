# WRO.03 — Temporal calculation and consumer host

Version: 0.2.0. Updated: 2026-10-13. Status: accepted target; implementation partial.

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

## Closed schedule and scalar temporal calculation

`Schedule.new/2` requires a closed JSON record with format
wotex.routines.schedule@1, kind, schedule_id, definition_digest and
late_window_ms. Kind one_shot adds due_ms and time_basis; interval adds
first_due_ms, period_ms and time_basis; countdown adds due_elapsed_ms, epoch,
clock_generation and time_basis; calendar adds rule, dtstart, time_zone,
time_zone_basis and producer_basis. Identities/bases are nonempty strings or
SHA-256 digests respectively. UTC coordinates may be signed; elapsed coordinates
are nonnegative. Period/window are positive integers. Calendar rule is at most
4096 bytes; DTSTART is an explicit offset-bearing ISO DateTime. Calendar semantic
validation additionally requires the explicit database and producer operation.
No schedule reads now or infers an operating-system time zone.

`Temporal.page(schedule, query, time, cursor, limits)` handles one_shot, interval
and countdown. Query has exactly from_ms, until_ms and limit (1–1024); horizon
is increasing and half-open. Limit/work and JSON integer/byte bounds all apply.
Time is the complete explicit WRO.02 Time. UTC candidates do not require trusted
now for calculation; the emitted due event still requires the entire UTC
confidence interval at execution. Countdown instead requires the schedule's
exact epoch/clock_generation and emits elapsed_due for a countdown source
trigger. Its window is [due_elapsed_ms, due_elapsed_ms + late_window_ms), checked
against elapsed time with the same epoch/generation, never fabricated UTC.

Interval ordinals are global, beginning at 1 for first_due_ms. Candidate n is
first_due_ms + (n - 1) * period_ms. Closed-form index bounds precede the bounded
page loop; a far-future horizon does not scan preceding ticks. One-shot/countdown
have ordinal 1 only. A cursor is null or exactly format
wotex.routines.temporal.cursor@1, schedule_digest, query_digest and next_ordinal.
It binds the full schedule, horizon, time generation and countdown epoch; page
limit may change. Altered cursor basis/position refuses. A cursor is an inert
calculation continuation and provides no considered-through or no-repeat proof.

Result has occurrences and next_cursor. Each occurrence has original, ordinal,
due_ms and event. Original hashes schedule_digest, ordinal and exact due
coordinate, excluding the mutable clock projection generation for UTC sources.
Clock correction cannot manufacture a new original for the same scheduled tick.
Due event binds the selected program separately at the consumer's explicit
projection seam; calculation alone returns a candidate with no program grant.
Candidates outside the horizon are never clipped into it. Overflow refuses;
empty pages and elapsed windows do not establish admission or a missed ledger.

The countdown Event has kind elapsed_due, original, program_digest, schedule_id,
due_elapsed_ms, late_window_ms, epoch, clock_generation and time_basis. Source
trigger countdown has kind and schedule_id. Retained windows are disjoint closed
UTC due or elapsed_due descriptors selected by the current program trigger.
Elapsed generation replacement expires pending work; restart is not a timer
restart instruction. Calendar cursors remain the producer's native continuation,
wrapped with the adapter's exact schedule/query basis; no undocumented producer
serialization or private recurrence access is permitted.

Definition digest is the canonical SHA-256 of every schedule member except
its definition_digest field; Schedule.semantic_digest/2 supplies only that
bounded projection, and Schedule.new/2 checks it. Source due/countdown triggers
and complete due/elapsed_due Events require schedule_basis equal to that digest.
Changing cadence, zone, producer basis or window cannot retain the old compiled
trigger correspondence. This hash binds data, not authority or installed
producer authenticity.

An occurrence's event member is an inert descriptor lacking program_digest.
`Temporal.event(schedule, occurrence, program, time, profile, limits)` regenerates
the full occurrence, matches the current program's schedule_id/schedule_basis
and trigger kind, and returns a checked complete Event. A changed clock
projection refuses reuse; a fresh page may project the same original under the
new generation. Cursor positions outside the query's candidate-index range
refuse; an internally consistent cursor is still no proof of prior processing.

Implemented evidence: `temporal_test.exs` covers an independent finite UTC tick oracle, global ordinal paging, far-future closed-form calculation, immutable schedule binding, cursor/clock replacement, exact elapsed windows and overflow. The calendar producer adapter, owned driver and real host transaction/archive adoption remain obligations.
