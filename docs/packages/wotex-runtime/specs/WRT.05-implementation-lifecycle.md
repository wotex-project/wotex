# WRT.05: Admitted instance lifecycle and replacement

Specification `WRT.05@1.1.0`. Package owner: `wotex_runtime`.
Contract: accepted optional specification; implementation status: `partial`.
This optional contract applies to instances admitted under WRT.04. It adds
immutable lifecycle decisions and binding obligations, not a Runtime process
manager. WoTEx is unreleased; current callbacks, messages and defaults are not
frozen. An implementation-driven change to an owning public contract must revise
that contract and its catalogue together. Domain ownership remains explicit.
MUST/MUST NOT obligations apply when a binding opts into this profile.

## L01 — Identity and execution boundaries

A consumer explicitly supplies `instance_id` (1–128 ASCII token bytes),
`generation` (positive integer at most 9007199254740991), scope, registration,
configuration identity, admission and deadlines. A generation is unique and
strictly increasing within that consumer's instance lifetime. On host restart
the consumer MUST allocate a new instance id or recover a durable generation
high-water mark. Runtime generates neither clocks nor identities.

An instance key is `{consumer_scope, instance_id, generation}`. Native handles,
requests, report sequence state and routing decisions MUST remain bound to it.
No cross-instance handle reuse, implicit global connection, module discovery,
ambient credentials or descriptor-selected store is allowed. The consumer owns
the state transition serialization and route table; no shared coordination
service or durable orchestration engine is required.

The binding receives the explicit WRT.01 Request and ephemeral ExecutionContext
for each interaction. Credentials remain resolved immediately before each
exchange. A native binding may use its already specified dedicated SDK store
under explicit consumer authority; that custody cannot be described as a
stateless credential-free codec. New IPC credential transfer requires the
owning package to specify lifetime, scope, redaction and teardown. Neither
generic lifecycle metadata nor manifest health calls receive credentials.

## L02 — State machine

The lifecycle value has exactly a validated instance key, admission identity,
one state below, a fixed non-secret reason or `null` and `cleanup_outcome`
(null before cleanup, otherwise one of the outcomes below). Transition functions
take an event and supplied time/budget. They are pure and reject an illegal
transition; a declaration that an event occurred is not execution evidence.

| State | Event and next state | Binding/consumer obligation |
|---|---|---|
| `admitted` | explicit valid start -> `starting`; revoke/expiry/failed revalidation -> `rejected` | Revalidate WRT.04 before any effect; construction alone starts nothing |
| `starting` | validated ready -> `ready`; cancel/revoke -> `draining`; failure/expiry -> `failed` | Owner/guardian attached before acquiring partial resources; no interaction routed before ready |
| `ready` | explicit drain/revoke/expiry -> `draining`; owner/transport/binding failure -> `failed` | Admit only current generation and valid policy; report terminal loss |
| `draining` | verified local cleanup -> `stopped`; cleanup deadline/failure -> `failed` | Reject new requests; settle admitted calls under original deadlines; close streams and child resources |
| `failed` | verified cleanup -> `stopped`; cleanup failure -> `failed` | Remain unavailable; no automatic transition to starting or ready |
| `stopped` | none | Terminal for this generation; restart requires new generation and fresh admission |
| `rejected` | none | Terminal refusal before spawn; no acquired resources |

`failed` carries a separate cleanup outcome: `pending`, `confirmed_local` or
`unconfirmed`. Only confirmed local cleanup permits `stopped`. Remote cleanup
and external operation effect are separate outcomes and may remain unknown.
Caller timeout and descendant death are not proof of remote unsubscription.
Owner death during starting/ready/draining triggers custody cleanup even if no
successful handle reached the consumer. Forced death does not depend on a BEAM
`terminate/2` callback executing.

Admission of new requests and route changes MUST use the same serialized
consumer decision boundary. The point at which a request becomes admitted pins
its generation. Drain rejects later arrivals `instance_draining` and never
redirects an already admitted call to the candidate generation.

## Public target API

`Wotex.Runtime.Implementation.Lifecycle.new/1` takes a validated WRT.04 Plan
and returns `{:ok, %Lifecycle{}}` in `:admitted`, or
`{:error, %Wotex.Runtime.Implementation.Error{}}`. The struct has exactly
`instance_key`, `admission_sha256`, `state`, `reason`, `cleanup_outcome`.
State and cleanup outcomes are the fixed atoms corresponding to L02's labels;
reason is nil or a fixed WRT.04/05 error code. Construction starts nothing.

`Lifecycle.transition/2` takes a Lifecycle and a closed atom-keyed event map
with exactly `type`, `instance_key`, `reason`, `cleanup_outcome`. Event type
is one of `:start`, `:ready`, `:drain`, `:cancel`, `:revoke`, `:expire`,
`:failure`, `:owner_lost`, `:transport_lost`, `:cleanup_confirmed`,
`:cleanup_failed`. The key must exactly equal the lifecycle instance key;
mismatched generation is `stale_generation`; other malformed identity is
`invalid_instance`. The result is `{:ok, %Lifecycle{}}` or a structured error.
Receiving functions revalidate forged structs; no public input raises.

Events map to L02 as follows: start/ready/drain/cancel/revoke/expire are their
named transitions; failure, owner_lost and transport_lost enter failed from
starting/ready/draining. Cleanup_confirmed enters stopped from draining/failed
only with `:confirmed_local`; cleanup_failed enters failed from draining/failed
with `:unconfirmed`. Failure events require a non-null fixed reason and
`:pending` or `:unconfirmed` cleanup outcome. Other events have null cleanup
unless they establish a cleanup result. Ready requires a null reason; illegal
state/event/field combinations return `invalid_transition`. A transition into
failed without an explicit cleanup result sets cleanup outcome to `:pending`;
starting/ready keep null until cleanup begins. Stopped requires
`:confirmed_local`; rejected before spawn has null cleanup outcome.

`Lifecycle.to_map/1` returns these five fields as a string-keyed JSON-compatible
map, using labels rather than atom conversion of external input. This API is
pure: clocks, readiness and cleanup are explicit consumer/binding observations.
The value never authenticates an observation or proves that a child stopped.
Binding acceptance verifies the real process/resource event as well as its
corresponding transition. Implementation follows this API now; required changes
revise the specification rather than silently choosing a different interface.

## L03 — Startup and package process protocols

BEAM registrations use existing public callbacks; they do not dynamically load
modules. Native hosts use a package-specified process protocol, not a generic
function catalogue. The local binding registration MUST bind exact protocol
id/revision, allowed operations, parser rules, executable/guardian cohort,
startup message, limits and error mapping. Missing protocol qualification
fails `incompatible_binding`. WRT.06 defines a separate closed codec protocol.

Before `ready`, the binding MUST verify the full admitted deployment, attach
consumer owner custody, enforce environment/argv/working-directory allowlists
and validate its package's startup identity and version. A child claiming an
artifact digest is not evidence that those bytes were executed. Wrong version,
duplicate ready, early result/report, malformed output or unexpected EOF fails
startup and releases partial local resources. No implicit alternative backend
or source build follows a refusal.

Explicit native start returns promptly to the consumer's supervisor using the
owning package's startup pattern. Opening, cancellation and owner monitoring
remain responsive under slow verification or protocol establishment. No
process-local monotonic timestamp is meaningful in another runtime: retain the
local absolute deadline, translate remaining milliseconds at dispatch and send
only the package's declared relative budget. Check the local deadline again at
reply admission; equality is expired. A child timeout is not sufficient to
enforce host acceptance of a late result.

The binding registration MUST declare bounds for startup, active requests,
queued requests/bytes, control/reply/report lanes, frame/decode sizes, stderr,
stream counts, report credit, pending partial handles and shutdown. They must
fit WRT.04 or a separately versioned owning profile. Queue counts alone do not
bound memory. Control/reply capacity MUST allow cancellation and retirement
under a saturated data lane. Unsupported enforcement fails before spawn.

## L04 — Requests, effect and cancellation

Each request binds its Runtime request id (at most 256 bytes), operation,
instance key and original deadline. IPC ids are unique for the process lifetime
and are not reused after completion/cancel. The binding maps IPC correlation to
the pinned Runtime request; a substituted operation/id is `correlation_failed`.
Duplicate final replies or unsolicited replies are protocol faults. A valid
late reply for an expired/cancelled request is discarded using bounded retired
correlation state; once that state cannot be retained, terminate the generation
rather than reuse identifiers unsafely.

| Completion / failure | Required outcome |
|---|---|
| Successful protocol reply before deadline | Validated Result tied to the original request; no physical/canonical assertion |
| Rejection before binding dispatch | Typed refusal; package may establish `not_dispatched` |
| Timeout, cancel or loss after a mutating dispatch may have occurred | `effect_unknown`; no automatic retry or replay |
| Owner loss during establishment | Cancel worker, release partial local resources; close a returned handle at most once through handoff |
| Cancel acknowledged | Local work/resources released as declared; remote cancellation and device effect remain separately qualified |

Bindings MUST retain uncertainty rather than turn it into a retryable transport
error. WRT.01's pure retry classifier remains authoritative and cannot override
an unknown mutating effect merely because the host restarted. Querying an
existing Action result is a new authorized interaction; reissuing the Action
is not recovery by default. Commissioning, pairing and store migration need
their explicit owning-package operations and consumer policy.

## L05 — Streams, loss and isolation

The binding binds every stream to an owner, generation, opaque handle and
package sequence/correlation state. Delivery admits only the current generation
and live handle. Retired-generation reports are discarded before decoding or
consumer delivery. Same-stream order and duplicate/gap behavior remain the
package protocol contract. Credit acknowledgement releases bounded buffers;
it is neither durable consumer receipt nor proof of canonical truth.

Drain, restart, transport loss and replacement terminate old handles once and
report continuity loss. Existing WRT.01 transports use `:session_lost` or
`:transport_down`; `:reconnected` is reserved for a package-proven retained
session and is never used to hide replacement loss. The old Runtime owner
notifies its receiver and stops through its existing terminal path. A later
consumer-selected new subscription uses fresh credentials and a new identity.
No automatic resubscription, event replay or duplicate suppression across
generations is provided by this contract.

Two independently configured instances MUST keep policy, sessions, handles,
custody, deadlines and lifecycle separate. A shared physical daemon may have
shared device effects; the profile MUST name that scope and MUST NOT promise
tenant isolation. Closing one consumer's borrowed connection/notification
session must not tear down another consumer's resources. Shared mutable native
stores are outside v1; the consumer must provide exclusive store custody.

## L06 — Replacement and rollback

Stateless replacement is allowed only at a complete message boundary. Admit
and verify the candidate, exercise its registered bounded codec vectors without authority,
then atomically change the consumer's route for new admissions. Already admitted
messages finish under the old generation. Candidate failure before route switch
leaves old routing intact. After switch, rollback is a new explicit route
decision using a still valid prior admission; no completed message is replayed.

Stateful replacement uses `stop_reopen`:

1. Admit and verify candidate metadata and deployment without opening the
   active store, device or connection. A metadata probe is not session health.
2. Stop new old-generation admissions and drain requests/streams within bounds.
   Preserve uncertain effect records; report stream loss.
3. Confirm local process-tree cleanup and exclusive store-lock release. If
   cleanup is unconfirmed, keep the route unavailable and do not open a second
   owner. Remote device state may still require reconciliation.
4. Explicitly authorize candidate open under a new generation. Validate existing
   store format and identity; incompatible stores fail before mutation.
5. Route new requests only after ready. If candidate open fails, remain
   unavailable until the consumer explicitly reopens an admitted implementation.

State migration is outside v1: no automatic downgrade, concurrent candidate
store access, copy of reusable authority into public artifacts or hidden restore.
A future migration profile must specify exclusive locks, original-format
snapshot, confidentiality, crash-safe durable commit, compatible rollback,
schema versions and recovery vectors in the protocol owner's contract. A
filesystem route switch cannot be called atomic with respect to device effects.

## L07 — Cleanup, restart and failure values

The consumer selects explicit supervision/restart policy and a finite restart
budget; v1 never schedules retries. A binding's guardian MUST own/reap all native
descendants under normal shutdown, owner kill, stalled output, descendant
escape attempts and deadline expiration. When this guarantee is unavailable,
the declared profile is refused. Local cleanup evidence records actual child
termination and resource release, never just sending a signal. A deadline
overrun returns unconfirmed cleanup and makes the instance unavailable.

Lifecycle errors use fixed code, phase and instance/generation identity; no
paths, payloads, credentials, raw stderr or foreign exception text. Codes are
`invalid_transition`, `invalid_instance`, `instance_not_ready`,
`instance_draining`, `stale_generation`, `incompatible_binding`,
`startup_failed`, `deadline_exceeded`, `overloaded`, `protocol_fault`,
`correlation_failed`, `owner_lost`, `session_lost`, `effect_unknown`,
`cleanup_unconfirmed` and `state_incompatible`, plus WRT.04 admission failures.
Phase is `construction`, `startup`, `request`, `delivery`, `drain` or `cleanup`.
Uncertain mutating effects map to permanent Runtime retry classification.
Diagnostic counters and process exit status may be separately consumer-owned;
arbitrary native text never reaches public telemetry or errors.

## L08 — Acceptance obligations

`test/wotex/runtime/implementation_lifecycle_test.exs` exercises the public
constructor, complete state/event matrix, generation correlation, malformed
values and preservation of uncertain effects through cleanup. Actual binding
ownership, process cleanup and replacement acceptance remain open. Those tests
must traverse the public Runtime and actual binding owner; pure transitions
do not establish resource release. No conformance or hardware result is asserted.

| Requirement | Required cases |
|---|---|
| L01–02 | Every legal/illegal transition; zero/one/two instances; admission/revoke/drain races; new generation after host restart |
| L03 | No load/start effects until explicit start; slow verification; wrong ready identity; duplicate/early frames; deadline boundary; no backend fallback |
| L04 | Request substitution, duplicate/late reply, cancel before/after dispatch, owner kill during handoff; uncertain write/invoke/commission never replayed |
| L05 | Saturated data/control lanes; owner-specific stream close; retired generation reports; sequence gaps; two consumers against one borrowed daemon |
| L06 | Failure before stateless switch preserves old routing; concurrent old inflight completion; stateful store conflict; stop/open failures; incompatible store; no implicit rollback |
| L07 | Forced BEAM death, child/guardian failure, blocked I/O, escaped descendants, cleanup expiry, restart budget exhaustion; inspect actual process/resource release |
| Security | Secret canaries absent from requests/results/errors/telemetry; denied device/store cannot be opened; immutable-deployment substitution attempts |

[WRT.04](WRT.04-implementation-admission.md) owns admission and
[WRT.06](WRT.06-bounded-codec.md) owns the codec protocol. The
[completion contract](../plans/wotex-runtime-completion.md) keeps these optional
requirements and their actual execution evidence separately; no prior release
or frozen API is presumed.
