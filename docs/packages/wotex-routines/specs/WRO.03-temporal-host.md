# WRO.03 — Temporal calculation and consumer host

Version: 0.2.6. Updated: 2026-10-15. Status: accepted target; implementation partial.

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

Implemented evidence: `temporal_test.exs` covers an independent finite UTC tick oracle, global ordinal paging, far-future closed-form calculation, immutable schedule binding, cursor/clock replacement, exact elapsed windows and overflow. The direct optional calendar adapter is implemented with exact request/page regeneration and published-producer unavailability tests. The exact development producer archive was adopted in one isolated calendar consumer with eight passing cases; see the temporal archive provenance. Owned driver, real host transactions and independent composition consumers remain obligations.

## Calendar adapter and native continuation

`CalendarRequest.new(schedule, query, database, cursor, limits)` accepts a
calendar Schedule, closed query (from/until offset-bearing ISO timestamps,
limit 1–1024, work_limit 1–100000), an explicit existing TimeZoneDatabase module or checked ExBooking.TimeZoneProvider
and null or the returned CalendarCursor. Query bounds normalize to UTC and are
increasing. The request has exactly schedule, query, database and cursor;
caller-built native requests are revalidated. No string becomes a module/atom.
CalendarCursor has exactly basis_digest, clock_generation and producer_cursor.
The final member is the native SP.08 continuation, never an invented wire token.
Its producer validates its position/prefix within work_limit. Adapter basis
binds the full schedule, canonical horizon and explicit database module/provider identity; limit
and work_limit may change between pages. Changed clock/basis refuses reuse.

`Calendar.page(request, time, limits)` reconstructs DTSTART in the explicit zone,
checks its supplied offset against the database, and calls only the public
ExBooking.occurrences/3 facade with every bound/option explicit. It returns a
CalendarPage with request, time, occurrences and next_cursor. Projection retains
original nominal/UTC time, ordinal, unique/first_fold/second_fold resolution,
producer and zone bases. Kernel time coordinates are integral milliseconds;
submillisecond starts explicitly refuse unsupported_temporal_precision rather
than round or change an original. Native producer errors map to payload-free
recurrence_refused, recurrence_work_bound, stale_calendar_cursor,
recurrence_unavailable or producer_contract_error. No availability fallback or
replacement recurrence implementation is permitted.

Each projected occurrence has original, ordinal, due_ms, nominal, starts_at,
resolution, schedule_digest, time_zone_basis, producer_basis and event. Original
hashes the immutable schedule digest and all original coordinate/resolution
members, excluding mutable clock projection generation. Event is an inert UTC
due descriptor with schedule_basis and no program_digest.

`Calendar.to_map(page, limits)` regenerates the full native page from retained
request/time before projecting occurrences and has_more. It does not serialize
or authenticate the opaque cursor. `Calendar.event(page, occurrence, program,
time, profile, limits)` also regenerates the page, requires an exact member,
current clock projection and matching compiled schedule_id/schedule_basis, then
returns a complete checked Event. Whole output bounds apply before delivery.
A native cursor is only reusable under its exact producer/database cohort;
portable restore must recompute bounded pages and preserve host original ledgers.

ExBooking is an optional exact `== 0.2.3` dependency, the latest published release
reviewed on 2026-10-13. That archive lacks SP.08 and returns unavailable at this
seam. Integration evidence must select the unreleased producer implementation
through an explicitly built and inspected exact archive cohort. Publishing a
successor and selecting its version are human release steps. This conditional
adapter does not claim that the existing Hex release implements occurrence
enumeration; ordinary scalar temporal calculation works without that capability.

## Explicit bounded wakeup driver

`Driver.specification/1` validates a closed native option map with id, host,
context, capacity, poll_ms and work_timeout_ms, returning an OTP worker child
specification or Error. id is a nonempty UTF-8 string of at most 256 bytes; host
is an existing consumer module implementing DriverHost.wakeup/3; context is
opaque trusted consumer data, never forwarded to Kernel. Capacity is 1–64
accepted wakeups including active work. poll_ms is explicit null (no polling)
or 1–604800000; work_timeout_ms is 1–60000. Loading the library starts nothing,
registers no global name and creates no timer. The returned child uses transient restart so normal retirement does not restart it. The consumer starts it and owns any explicit supervision/restart override.

Driver.start_link/1 is the child start seam. Driver.handle/2 takes its PID and
an explicit positive call timeout, returning an opaque DriverHandle containing
pid, token, counter and capacity. Driver.notify/2 admits only the closed causes
manual, basis_changed or poll. Atomic capacity admission precedes mailbox
submission; saturation returns an Error and creates no accepted queued work.
The capacity bounds accepted work through this API; arbitrary direct messages
and OS process/memory containment remain consumer host obligations. No cause
carries a calendar original, clock confidence, grant, credential or transport
handle. The consumer obtains a fresh complete snapshot/time and accounts missed
ranges when it handles a wakeup; notification is not occurrence admission.

The host callback receives context, cause and the explicit work budget, returning
:ok or a payload-free failure. :ok means wakeup processing finished, not that a
transaction or physical effect succeeded. DriverHost documents all WRO03-03
atomic reserve/claim/handoff/settle and current-basis obligations; an unconditional
success host does not meet them. Host exceptions are caught without logging
private context. Runtime status formatting also redacts it.

One monitored worker runs at a time. Queued manual notifications retain FIFO
order but do not retain semantic proposals. Polling coalesces while busy and
never catches up elapsed timer ticks. Poll/watchdog timers schedule lifecycle
work only; they never supply trusted UTC/elapsed eligibility. A timeout kills
the callback worker, drops pending notifications and waits for its DOWN before
reuse; originals/committed or uncertain effects remain in the host ledger.
Failures likewise drop pending work. No failed notification is automatically
replayed. A fresh wakeup must recompute current eligibility and recover originals.

Driver.status/2 reports bounded operational counts without exposing context.
Driver.retire/2 closes admission, cancels polling, drops pending work, retires an
active worker and acknowledges only after its DOWN; it creates no stop effect,
compensation or root refund. A later explicit supervised restart receives a new
handle, while the host retains original/no-repeat history. Driver restart never
reactivates restored definitions. Higher-risk response capacity is a separate
host lane; this driver does not borrow it.

Driver lifecycle evidence is `driver_test.exs`: bounded concurrent admission, FIFO wakeups, timeout/exception retirement, polling coalescence, parent death, private-state redaction and a result/retirement race. These instrumented callbacks do not establish the host transaction contract; real consumer store-race and composition/archive evidence remain separate obligations.

## Immutable provider join

The optional producer successor also accepts SP.08's public TimeZoneProvider.
Its exact native module/context is revalidated through the public provider API;
context bytes obey both the producer's 1 MiB ceiling and Limits.max_bytes.
No data string becomes a module. CalendarRequest stores that native immutable
value, never a wrapper process or an application-environment database. DTSTART
localization uses the producer's public shift_zone/3 helper for provider input;
ordinary module input retains DateTime's existing explicit database call.
A published producer lacking this additive provider seam remains unavailable.

Calendar cursor basis identifies provider kind, installed callback module and
SHA-256 of the exact opaque context, alongside the full schedule and query.
Changing context rejects old continuations even if a consumer reuses its
zone-basis name. Provider context is not included in the projected occurrence,
event or JSON cursor identity. ExBooking independently retains/checks its full
native provider in the inner cursor. This identity is attribution, not code/data
authentication; the consumer owns immutable custody and installed callbacks.

The adapter never parses timezone data or supplies default DST policy. Invalid
provider shape/code/seam returns invalid_calendar_request; malformed provider
results fail the existing start/producer-contract checks. Producer gaps/folds,
COUNT, work bounds and millisecond precision retain their prior semantics.
Ordinary scalar calculations do not require a provider. The original released
0.2.3 absence test and existing module-based calendar corpus remain acceptance
requirements. The native archive consumer additionally compares explicit
provider and module pages, retained original coordinates and changed-context
cursor refusal through only the public producer API.

Implemented immutable-provider evidence is the ninth case in the extracted
calendar consumer: both DST zones preserve exact module/provider coordinates;
changed context and native over-bound/extra fields refuse. The ordinary package
calendar tests retain the released 0.2.3 unavailable behavior.

The [immutable-provider cohort](../provenance/immutable-timezone-cohort.md) binds
the executed ninth archive case to its exact producer/runtime/harness source.

The [quality milestone](../provenance/quality-milestone-2026-10.md) also exercises
malformed producer adapter outcomes, with real recurrence semantics checked by
the separate nine-case extracted calendar lane.

## Bounded civil calendar adapter

**WRO03-06 — Distinct finite calculation.** `CivilRequest.new(schedule, query,
database, limits)` accepts the additive `civil` Schedule kind. Its complete
schedule has the common format/kind/schedule_id/definition_digest/late_window_ms
members and exactly time, weekdays, time_zone, time_zone_basis, producer_basis,
gap_policy and fold_policy. Time is exactly `HH:MM:SS` (00:00:00–23:59:59);
weekdays is a nonempty ascending unique list of ISO integers 1–7; zone is valid
UTF-8, 1–256 bytes. Policies are explicit strings skip/reject and
first/second/both/reject respectively. Bases are SHA-256 digests. The canonical
schedule digest includes every policy/pattern member. No DTSTART, RRULE, COUNT,
ordinal, cursor or defaults are invented for this operation.

The query has exactly first_date (`YYYY-MM-DD`, ISO years 0000–9999), days
(integer 1–366), from and until (explicit offset-bearing ISO DateTimes). The
whole inclusive local span must fit that year range. Normalize UTC boundaries
while retaining fractional precision, require from < until and reject normalized
UTC coordinates outside those years. The local span and UTC horizon are
independent. JSON Limits apply to all inputs. A selected database is an existing
Calendar.TimeZoneDatabase module with both callbacks, or a valid immutable
ExBooking.TimeZoneProvider with 0–1048576 binary context bytes, also bounded by
Limits.max_bytes. Provider
shape and callback availability are checked through the public producer seam;
no string becomes an atom, module or ambient database. CivilRequest has exactly
schedule, query and database; `CivilRequest.current/2` reconstructs caller-built
native requests. It supplies no authorization or host clock.

**WRO03-07 — Direct producer and original coordinates.** `Civil.page(request,
time, limits)` validates the complete explicit Time and retained request, then
calls only public ExBooking.civil_occurrences/3 with all eight options explicit.
This consumes ExBooking SP.09's civil contract: at most 366 selected-date
resolutions and 732 localizations; gaps skip or reject; every ordered fold
alternative round-trips before policy/filter; policy precedes half-open UTC
filtering; no snapping, clipping, alternate-fold substitution or partial list.
This profile supports timezone offset components within ±93599 seconds and
totals [-89999, 93599], independently of the older provider helper bounds.
The adapter must not localize via those narrower helpers or implement recurrence
itself. Callback work/runtime and immutable data custody remain consumer-owned.
The producer's complete maximum is 732 points, not a pagination instruction.

The native CivilPage has exactly request, time and occurrences. Its strictly
UTC-ordered occurrences each have exactly original, due_ms, nominal, starts_at,
resolution, schedule_digest, time_zone_basis, producer_basis, database_basis and
event. There is no ordinal. Each point must have the exact public
CivilOccurrence native shape and valid ISO original nominal/UTC coordinates,
match the requested civil span, time, weekday and fold policy, and satisfy the
original UTC horizon. Duplicate or unordered UTC points refuse. Millisecond
coordinates/window endpoints must fit Limits.max_integer; submillisecond
instants refuse rather than round. Every output and the complete result must
fit the caller's Limits, including max_collection_size/bytes; overflow refuses
the entire result. Empty means only no matching point in this explicit span.

The original is the canonical SHA-256 of all coordinate members listed above
except original and event. Database_basis hashes the Atom.to_string module name for a
database module; for a provider it hashes exactly the JSON map with kind
`ExBooking.TimeZoneProvider`, module (Atom.to_string) and context_digest
(SHA-256 of the exact context bytes, with the `sha256:` prefix). Context bytes never enter projected
output. Query boundaries/span and Time generation are excluded from original.
Overlapping queries and clock reprojection preserve the same original;
changing schedule, declared bases or actual provider identity changes it. These
hashes identify supplied data, not installed callback code authenticity, immutable
custody or any permission. Consumers retain and revalidate those obligations.

**WRO03-08 — Regeneration and event binding.** `Civil.to_map(page, limits)`
recomputes the complete page from retained request/time and requires exact native
page equality before returning the closed JSON map with only occurrences.
There is no continuation or global-exhaustion flag. `Civil.event(page,
occurrence, program, time, profile, limits)` additionally requires an exact page
member, the same current clock_generation and a regenerated compiled due trigger
with the schedule's exact schedule_id/schedule_basis. It returns a checked Event
by binding program_digest to the inert descriptor. The descriptor has the same
UTC due fields as the calendar adapter: kind, original, schedule_id,
schedule_basis, due_ms, late_window_ms, clock_generation and time_zone_basis.
Calculation works with null UTC confidence; execution still requires the complete
current time/window and transaction obligations of WRO03-02–05.

Missing public civil API returns payload-free civil_unavailable, any producer
refusal returns civil_refused except the fixed work-limit result described below;
malformed producer values or implementation
exceptions return producer_contract_error. Other fixed refusals include
invalid_civil_request/query/page, stale_civil_page, stale_temporal_projection,
schedule_program_mismatch and unsupported_temporal_precision. Existing bounded
validation errors retain their code/path. No native callback error/exception
payload enters output or logs. Retry regenerates from the same immutable inputs;
changed retained request/time/points cannot pass checked page projection.

The pure civil adapter is implemented. Its eight-case extracted consumer and
the retained nine-case SP.08 corpus pass against one exact producer cohort.
Existing Calendar/SP.08
semantics and native cursors, scalar Temporal pages and Driver lifecycle remain
unchanged. The optional exact released ExBooking 0.2.3 still lacks this public
operation and must refuse unavailable, with no fallback. Development evidence
must supply an inspected exact SP.09 producer archive through the existing
explicit archive lane with `--civil-consumer`; omitting that flag preserves
the SP.08-only lane. No publication or dependency selection is implied.

## Complete bounded civil ambiguity

**WRO03-09 — Lossless local fold positions and work refusal.** A producer
implementing SP.09 CIV-06 may select an immutable provider's optional
`resolve_civil/3` callback. It returns every alternative, with at most 732
candidates per label and at most 732 total round-trip localizations per query.
The adapter still calls only the public civil facade; it never selects callbacks,
truncates an ambiguity, retries the legacy resolver or splits a refused query.
The producer validates the whole candidate set before policy/UTC filtering.
The explicit first/second policies retain local positions 1/2; both retains all
alternatives; reject refuses any ambiguity, including outside the UTC window.
Consumers own explicit smaller-query composition and wider ordering/identity.

Existing native resolution atoms `:unique`, `:first_fold` and `:second_fold`
keep their JSON strings. Native `{:fold, index}`, with integer index 3–732,
projects exactly to the two-member JSON array `["fold", index]`. The index is
its position in the complete UTC-ordered resolution of one nominal label,
never a DTSTART ordinal or the position in a filtered page. A surviving third
alternative keeps `["fold", 3]` after earlier alternatives are filtered out.
Additional folds are valid only under both policy. Unsupported tuple shapes,
indices or wire arrays supplied as native resolutions refuse with
producer_contract_error. For each nominal label, retained fold positions must
strictly increase and unique cannot coexist with any other occurrence of that
label. Missing positions after filtering are valid. This check retains at most
732 nominal-label entries. Whole UTC ordering and all previous output Limits
continue to apply. The exact projected resolution participates in original
hashing; existing atom-resolution originals retain the same hash algorithm.
Regeneration and checked event binding apply equally to every local position.

Exactly `{:error, {:limit, :civil_occurrences, :work}}` from the producer maps
to payload-free civil_work_bound. This refuses the entire page; no continuation,
partial result or implicit retry is returned. Every other producer error retains
civil_refused. Producer faults remain producer_contract_error. Repeating the
same immutable request repeats the same result; callers may explicitly split
its local span while retaining the producer's policies and original identities.
Legacy Calendar/SP.08 and ordinary scalar temporal behavior are unchanged.

This extension is accepted; implementation and renewed archive evidence are
pending. Its producer contract is ExBooking SP.09 CIV-06, implemented at source
`16a9d0d`; the earlier civil cohort below remains evidence for its recorded inputs.

| Case | Requirements | Setup/stimulus | Expected observation / falsifier | Evidence level |
| --- | --- | --- | --- | --- |
| WRO03-T5 | 06–08 | Closed civil schedule/query, invalid native shapes, day/year/weekday/byte/Limit boundaries, released producer | Independent schema vectors and constructors agree on closed shapes; invalid preflight sends no producer call; missing API refuses | Pure |
| WRO03-T6 | 07–08 | Exact extracted producer/core/Continuum/Routines archives; literal Stockholm/New York folds/gaps, fractional horizons, wide signed offsets | Original UTC/nominal/resolution preserved without ordinals; policy before filtering; no narrower-helper fallback; old calendar corpus still passes | Archive |
| WRO03-T7 | 07–08 | Independent Gregorian finite weekday oracle, overlapping/partitioned queries, clock change, provider context change, forged page/member/program | Same point keeps original across query/clock; provider/pattern change changes original; stale generation/member/program refuses; regeneration defeats tampering | Pure/archive |
| WRO03-T8 | 07–08 | 366-date/732-point maximum, reduced output Limits, malformed/duplicate/unordered/late producer refusal and private-canary faults | Finite complete result or fixed error only; no partial output/private payload; scalar and SP.08 regressions unchanged | Pure/archive |

| WRO03-T9 | 07–09 | Exact extracted complete-ambiguity producer; threefold and maximum 732 alternatives, filtered third fold, every policy, forged positions and 732/733 work boundaries | Literal UTC/tag projection and schema agree; no ordinal or renumbering; query-independent originals and checked regeneration/events persist; fixed work refusal has no partial result or fallback; old calendar corpus passes | Pure/archive |

The executable temporal schema and a civil vector freeze this additive shape
before implementation. The producer contract is ExBooking
`docs/specs/SP.09-civil-occurrences.md`, implemented at its separately owned
source commit `dd82677`. Source review establishes the intended seam; only the
cases above establish this adapter's executed evidence.

The [civil archive cohort](../provenance/civil-time-cohort-2026-10.md) records the
exact producer/runtime archives, eight civil plus nine retained calendar cases,
quality-component results and cleanup boundaries. Consumer-host transaction,
clock and physical obligations remain open.
