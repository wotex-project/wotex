# WST.01 — Neutral stream values, ports and delivery lifecycle

Version: 0.1.0. Updated: 2026-10-13. Status: accepted target.
Implementation: planned. Evidence: missing.

## Scope and ownership

The prospective optional `wotex_streams` producer describes and supervises
explicitly selected streaming-protocol sessions. It preserves payload, sequence,
clock and delivery facts with finite resource/lifecycle contracts. It is usable
for supported media/sensor stream profiles without a playback, DSP, recording,
surveillance, device catalogue or routine engine.

Core retains TD/TM/Form values; Runtime retains public interaction, credential
and implementation-admission ports. [WST.02](WST.02-protocol-profile-allocation.md)
owns exact protocol profile selection and conformance obligations. A consumer
supplies identity, permissions, private routes/credentials, immutable installed
bindings, supervision, current guards and any durable original history.
Processing/rendering and physical synchronization evidence belong to its
selected component, never to a successful packet exchange.

This documentation tree is prospective/unregistered, outside the tooling and
generated catalogue. No source/export/support claim exists. A missing required
binding/profile returns unsupported_profile; never discover another stack.

## Closed input and output

IDs/epochs are caller-issued 128-bit identities encoded as 32 lowercase hex.
Digests are SHA-256 lower hex64. Contract references contain exactly id
(absolute URI ≤256 UTF-8 bytes), version (SemVer x.y.z) and sha256. Counts/sequence/
ticks use canonical uint64 strings; signed time uses canonical int64 strings in
microseconds and a named clock epoch. Unknown/duplicate fields, invalid UTF-8/NUL,
nonfinite/cyclic input and forged structs refuse before callbacks.

**WST01-01 — Limits and descriptors.** Limits contains every positive integer
field below; no implicit defaults or ambient limits. Values can narrow ceilings.
Sessions/streams are per host; these are not global device-count limits.

| Field | Ceiling/unit |
| --- | --- |
| max_sessions / max_streams | 32 / 256 |
| max_control_bytes / max_depth / max_nodes | 65536 / 16 / 100000 |
| max_frame_bytes | 1048576 payload bytes |
| max_stream_queue_bytes / max_total_queue_bytes | 8388608 / 134217728 bytes, including pending copies/reservations |
| max_pending_controls / max_retained_originals / max_pending_events | 64 / 1024 / 256; retained_originals ≥ pending_controls |
| max_lease_ms | 86400000 ms per explicit authorization lease; renew is explicit, not a protocol replay |
| startup_ms / control_ms / cleanup_ms | 10000 / 5000 / 1000 ms |
| guard_poll_ms / guard_ttl_ms | 1000 / 10000 ms; poll ≤ ttl; consumer supplies narrower effective limits |

Descriptor contains exactly format (`wotex.stream@1`), id, revision
(canonical uint64), profile (Reference), direction (receive/send/duplex),
tracks, custody_ref (opaque ≤128 bytes) and requires (sorted unique References).
Tracks are 1..max_streams sorted unique objects with exactly id, role
(opaque URI), format_ref (Reference), clock and maximum_frame_bytes.
Clock is null or exactly epoch, rate_n, rate_d; rate is a reduced positive
rational ticks/second, numerator ≤1000000000 and denominator ≤1000000.
Declared formats/roles are inert references; no audio/video type enum chooses
a decoder or application. Custody resolves endpoints/session credentials privately.

Frame is exactly stream_id, stream_epoch, sequence, source_ticks, received_at,
flags and payload. Source_ticks is canonical uint64 or null; received_at is
exactly clock_epoch/monotonic_us. Payload is a binary bounded by both track and
host frame limits, never a public JSON/base64 media value. Flags are sorted
unique keyframe/configuration/discontinuity/end; their availability/meaning must
be declared by the profile. A profile cannot label guessed decoder facts.
Transport fragmentation is resolved according to that protocol before exposing
a Frame; the producer does not guess a frame boundary from payload content.

**WST01-02 — Status and truthful timing.** Status contains exactly session_id,
session_epoch, profile, state, streams, error. Stream entries are sorted and
contain exactly stream_id, stream_epoch, delivery, format_ref, source_clock,
clock_correlation_ref, continuity, queued_bytes, accepted_bytes, lost_frames,
duplicate_frames, last_sequence and remote_tail. Counters use uint64 encodings; last_sequence,
source_clock/correlation may be null. Queue bytes are bounded integers.
State is preparing/ready/active/draining/lost/closing/closed/failed. Delivery is
not_established/local_acceptance/protocol_acceptance/reported/unknown.
Continuity is unknown/baseline/continuous/gap/retired. Remote_tail is exactly
bound_us (nonnegative int64 microsecond duration or null) and ownership
(confirmed/taken_over/unknown). A null bound remains unknown, never zero.

A correlation reference is consumer-resolved exact evidence, not clock trust
created by timestamps. Preserve actual protocol wrap/clock epochs, source versus
receipt time, gaps and unsupported metadata. Status never contains a physical
rendered/audible/synchronized claim, source URL/key, raw payload or vendor exception.
A stream's delivery does not prove the whole group/camera/source succeeded.

## Explicit operations and transitions

**WST01-03 — Consumer port.** Planned Descriptor/Limits/Frame constructors and
Status validation live under Wotex.Streams. Planned Session.child_spec/1 requires
explicit descriptor, installed binding port, limits, receiver, supervisor policy,
clock and current-guard callbacks, and lease_ms (1..max_lease_ms).
No application callback/load effects occur.

The binding behaviour has prepare/3, open/3, send_frame/3, control/3, status/2 and
close/2. Calls take exact descriptor/session/stream epochs, retained deadline
and cancellation/current-guard context. Prepare may negotiate only admitted
capabilities; it cannot begin capture/play/record as an accidental side effect.
Unsupported direction/control refuses before dispatch. Concrete inputs/wire
grammar belong to the selected WST.02 profile, never a universal raw-command map.

Control input is exactly request_id (opaque ≤128 bytes), request_sequence
(canonical uint64), expected_session_epoch, operation, payload and deadline_us.
Operations are open, start, pause, resume, stop, status, close and host-local
renew. Renew payload is exactly lease_ms (positive integer ≤max_lease_ms);
current consumer authorization must cover that whole renewed lifetime. It
changes no stream epoch, route or protocol state, sends no binding control and
starts no source. Expiry withdraws delivery unless a fresh explicit original
renew succeeds beforehand; no keepalive implicitly renews authority. A binding
advertises its exact supported protocol subset and closed payload schema.
A missing schema refuses; renew uses the host-local schema above.
The deadline is in the supplied host clock epoch and includes queueing; no retry
extends it. Start/pause/resume/stop may be protocol or physical effects and require
current consumer permission immediately before handoff. Status is read-only.

Open: absent -> preparing -> ready or failed; start: ready -> active; pause
retires stream ingress and returns ready with a fresh stream epoch when supported;
resume needs explicit start/current source basis. Source EOF may drain only where
the selected profile defines bounded normal completion. Loss -> lost with gap/
unknown outcome; close from any owned state -> closing -> closed. No restart,
reconnect, default-device change or clock reset automatically starts a stream.

Control result contains exactly request_id, request_sequence, session_id,
session_epoch, disposition, status and error. Disposition is refused/staged/
admitted/handed_off/reported/partial/unknown/closed; status is a WST01-02 snapshot
or null before a session exists, error is null or the closed error below. Pending
originals can publish progress; terminal outcome is immutable. A scheduled/
accepted handoff never fabricates later delivery or a physical result.

Binding callbacks return {:ok, private_handle} for prepare/open,
{:ok, accepted_bytes} for send_frame (integer 0..payload bytes, partial acceptance
only if that profile declares it), {:ok, validated_status} for status,
{:ok, control_result} for control/close, or {:error, closed_error}. Handles are
opaque consumer-owned runtime objects, never serialized descriptor fields.
Epoch/correlation/limits are independently checked by the host; malformed callback
output is protocol_error. Ready/open admits no incoming payload until start and
its current source guard; early packets are bounded/discarded as the profile
declares, never exposed as an unauthorized captured stream.

**WST01-04 — Originals and authority.** Consumer-owned request sequences start
at one and strictly increase per session epoch. Retain at most max_retained_originals
including pending controls and one accepted high watermark. Identical retained
original returns its current/terminal outcome without a second control; changed
payload conflicts. An unseen sequence ≤watermark is original_retired, never new
work. Pending entries cannot be evicted; terminal results are immutable.
The consumer retains durable originals across process restart; all old host/session
epochs expire. The library does not reconstruct a grant from a receipt.

The guard callback reports current validity/basis/expiry in the selected host clock.
Check before handoff and at least each guard_poll_ms. Missing refresh/expiry or
owner loss withdraws new ingestion/delivery by the next check. Already buffered
remote effects stay bounded/unknown as the profile reports. Cleanup may stop an
owned remote source only while that exact ownership is confirmed; external
takeover closes this session's local connection without stopping another owner.

**WST01-05 — Pressure, gaps and isolation.** Reserve queue credit before accepted
ingress; exhausted credit blocks only a non-real-time sender or returns capacity.
It never grows queues or blocks a native callback. Release credit after buffers
are released. Protocol-defined packet reordering/retransmission has explicit
windows/budgets; it cannot conceal a continuity gap or renew retired epochs.
No control, alarm or state event is silently lost under telemetry coalescing;
if its receiver cannot keep up, retire its generation with a reported reason.

One slow stream cannot block another beyond its declared shared transport budget.
A shared daemon/bus is an explicit effect/resource domain, not independent ownership
inferred from distinct track IDs. Terminate/reap only owned children on loss;
local cleanup ≤cleanup_ms. Unconfirmed cleanup prohibits replacement access to an
exclusive resource. Body/framing faults retire the affected session/host according
to its specified isolation scope, not an invented universal containment guarantee.

## Errors, entry and acceptance

Errors are exactly code/path from invalid_input, capacity, unsupported_profile,
unsupported_operation, unsupported_format, stale_basis, stale_epoch, unauthorized,
deadline, request_conflict, original_retired, protocol_error, source_lost,
clock_lost, unknown_handoff, cleanup_unconfirmed. Redacted paths use known fields
and numeric indexes only. Native exceptions/payloads are not diagnostic strings.

Before implementation freeze schemas, public port vectors and per-profile
isolation/credit rules. This common contract specifies no universal native IPC
or payload codec and imposes no mandatory media dependencies. Claim support only
after the selected protocol's own contract and exact peer/resource evidence exist.

| Case | Requirements | Stimulus and falsifier | Evidence |
| --- | --- | --- | --- |
| WST01-T1 | 01–02 | Independent descriptors/frames/status, arbitrary track roles and clocks, malformed/over-bound inputs | Pure vectors, no media/sensor enums |
| WST01-T2 | 03–04 | Load without host; missing bindings; duplicate/retired originals; stale guards/epochs | Public archive/controlled port; zero hidden effect |
| WST01-T3 | 02–05 | Slow sender/receiver, full credit, loss/wrap/clock change, late reply and takeover | Exact gap/unknown/cleanup, bounded resources |
| WST01-T4 | 03–05 | Owner/child death and failed cleanup during pending start; explicit restart | Real process lifecycle; no automatic replay |
| WST01-T5 | 01–05 | Two independent stream consumers, different protocols/format roles, media engine absent | Archive/protocol evidence; physical separately |

All cases are obligations. The [completion plan](../plans/wotex-streams-completion.md)
keeps session mechanics separate from processing and installed-device evidence.
