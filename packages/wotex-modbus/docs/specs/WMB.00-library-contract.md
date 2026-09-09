---
spec:
  id: WMB.00
  title: "Software implementation rules"
  status: accepted
  version: 1.1.0
  owner: wotex-modbus
  updated: 2026-09-09
---

# WMB.00 Software implementation rules

This is a target contract for the library's software completion milestone.
Requirements below are not claims that the current code already implements them.
Read this file with [WMB.10](WMB.10-software-contract.md),
[standalone client preservation](WMB.11-standalone-client-and-preservation.md),
[Wotex integration](WMB.12-wotex-integration.md), and the existing
protocol specifications, and [the implementation sequence](../plans/software-implementation.md).
`CLAUDE.md` governs repository boundaries. Exact protocol requirements come from
the revisions in [primary sources](../provenance/primary-sources.md); limits and
API choices labelled **library policy** are deliberate local constraints.

## WMB-C01 — Scope, API and compatibility

Build the explicitly enumerated client profile in WMB.10. A protocol's
entire standards family is not an implied implementation requirement. Physical
radios/devices, certification, consumer migration and publication are outside
this milestone. Native SDKs and operating-system services may own lower layers;
the adapter still needs executable software evidence for its own obligations.

Preserve existing valid inputs and documented successful return shapes unless a
protocol-specific requirement explicitly describes a migration. Keep the public
callbacks `capabilities/0`, `connect/1`, `send/2`, `receive/2`, `disconnect/1`,
`health_check/1`, `subscribe/2`, and `unsubscribe/2`. Callback names alone do not
prove compatibility. Add table-driven contract fixtures covering every accepted
operation and its output, false/zero/null, rejected input and intentional stricter
failure. Do not add a fictitious receive queue to synchronous `send/2`.

The existing `Client` behaviour, where present, has `connect/1`, `request/3` and
`disconnect/1`. Subscription work adds explicitly documented `subscribe/4`
and `unsubscribe/3` callbacks to concrete clients: arguments are client handle,
validated subscription request, receiver pid, timeout; cancellation arguments
are client handle, subscription handle, timeout. Mark these new callbacks optional in the behaviour so existing custom
clients still compile. A missing optional callback on the explicitly selected
client returns the documented unsupported error. This check cannot select or
switch backends, and must not swallow an undefined-function error raised inside
a callback that exists. First-party clients without a feature implement a
deliberate unsupported stub. An arbitrary driver exception
must not be converted into an unsupported-feature success. Never choose a
backend because a module happens to be loaded or an executable happens to exist.

## WMB-C02 — Input validation and bounds

Every public boundary returns a library Error for malformed configuration,
messages, addresses, subscription handles and forged structs. Programmer-supplied
callback exceptions may propagate only where explicitly documented, such as the
function passed to `with_connection/2`. Keyword options must be proper lists,
have unique atom keys and contain only the selected adapter's allowlist.
Validate before spawning, opening a socket, reading credentials or sending bytes.
Revalidate public structs at the final serialization boundary.

Unknown Form extensions survive roundtrip unchanged. A preserved extension is
not implemented behavior. Known security/transport selectors cannot be ignored.
Never create atoms from external input; use finite mapping tables. Bound lengths
before allocation and multiplication, including decoded arrays, nested values,
decompressed output and aggregate transfers. Byte and element limits are separate.
The protocol-specific table supplies exact wire and value limits.

## WMB-C03 — Session ownership and deadlines

Each explicit connection owns exactly the processes, ports, sockets, subscriptions
and timers it starts. Borrowed SDK clients, system daemons, buses and consumer
supervisors remain consumer-owned. Startup records acquisitions in order and
unwinds them in reverse order on every failure. No Application callback or
dependency-load transport startup is permitted. Long-lived work exposes a
caller-started `start_link/1` and child specification.

**Library policy:** interaction timeout defaults to 5000 ms, range 1..60000 ms.
Compute one monotonic absolute deadline on API entry. Admission, queue time,
connect/authentication, all protocol exchanges, conversion and cleanup are charged
to that deadline. Expired queued work sends no request. Use a finite cleanup
grace of at most 1000 ms after a failed interaction; report timeout without
claiming an unacknowledged mutation did not happen. A live stream has separate
establishment and per-renewal deadlines; its overall lifetime is owner-controlled.

One session generation has at most 64 admitted pending requests, including the
active request. Reject excess admission with `:busy`; do not grow an unbounded
work list or start one process per rejected request. Monitor each admitted caller
and remove queued work when it dies. No guarantee is made against arbitrary
external processes flooding a BEAM mailbox outside the API admission protocol.

Owner death must be noticed during blocked I/O, not only when a long receive
times out. Software tests allow 100 ms for the owner to enter cleanup and at most
1000 ms to release owned resources. Graceful disconnect is idempotent. Closing
and failed sessions reject new operations and late responses cannot reopen them.
Failed connection startup must return an error without unexpectedly killing the
caller through a link. Create links only after successful initialization, or
handle startup exits with equivalent caller-safe semantics.

## WMB-C04 — Errors, effects and retry

Keep `%Wotex.Modbus.Error{}` with fields `code`, `field`, `details`,
`retryable`, `effect` and the additive Runtime retry `class` defined in .12 I04.
Unknown-effect mutations must be non-retryable through both native and Runtime APIs.
`code` and `field` use library-owned atoms; details contain bounded counts,
status numbers and non-secret path identity. Never include credentials, raw
bridge settings, protocol payloads, stack traces or arbitrary exception strings.
Retain remote numeric status even when unknown. A parse failure, absent response,
negative acknowledgment or wrong identity can never become a successful value.

| Failure point | Effect | Required behavior |
| --- | --- | --- |
| Validation, admission or queue expiry before transmission | `:none` | No I/O; structured failure |
| Read failure | `:none` | No value fabricated from stale/default state |
| Mutation transmitted and acknowledgment missing/malformed | `:unknown` | Never replay automatically |
| Explicit remote rejection | Conservatively `:unknown` after transmission | Preserve remote status; do not infer rollback |
| Cleanup failure after an acknowledged mutation | `:unknown` on the cleanup error | Preserve the acknowledged result separately where the API supports it |

Protocol-defined retransmission of the same correlated exchange is distinct from
restarting an operation. Only the protocol-specific retransmission state machine
may retransmit. Connection recovery never resends writes/actions. Subscription
re-registration is an explicit idempotent control operation, not write replay.

## WMB-C05 — Subscription contract

Applies only to subscriptions listed in WMB.10. Native `subscribe/2` takes a
validated request map with `receiver: pid` (default caller) and returns
`{:ok, %Wotex.Modbus.Subscription{pid: pid, reference: ref, generation: gen}}` only after
the protocol-specific establishment condition succeeds (a wire acknowledgment
or successful SDK/listener registration, as specified in .10). The handle is
opaque, generation-bound and redacted by Inspect. Validate handle field types
and session/generation identity before protocol I/O.
A live owner rejects unknown references and foreign handles. Repeated cancellation
of its recorded closed handle returns `:ok`. Once the recorded owning generation
has terminated, cancellation of a well-formed handle for that generation returns
`:ok` without I/O; reference membership is no longer asserted. Do not keep an
immortal owner/global tombstone registry merely to acknowledge cancellation.

Native deliveries are `{:wotex_modbus, reference, {:ok, value, metadata}}` or
`{:wotex_modbus, reference, {:error, error}}`. An initial value is
delivered once only if the protocol-specific contract provides an initial report;
establishment acknowledgment alone never invents one. Identical scalar values
in distinct fresh protocol reports are not duplicates by themselves; suppress only protocol-defined duplicates. A
terminal failure emits at most one native error and starts cleanup. Frames from
an old generation, canceled handle or unrelated target never become deliveries.

The receiver is monitored. **Library policy:** `max_queue_length` defaults to
1000, range 1..10000. Check the receiver queue before delivery. Overflow terminates
the subscription with `:receiver_overflow`; do not silently drop an arbitrary
number of ordered Events. Retain at most one additional latest Property report
only where the protocol-specific contract explicitly permits coalescing.
Wire duplicate tracking has its own bounded cache and expiry, not an unbounded
set of observed payloads. Timers carry a generation or reference so canceled
timer messages have no effect.

## WMB-C06 — Runtime and Form mapping

Use `Wotex.Form` and the explicit resolved href on `Wotex.Runtime.Request`.
Honor operation applicability, Property/Action/Event context, content type and
selected security. Resolve no remote JSON-LD context. Convert only once a full,
validated protocol result exists. False, zero, empty bytes and explicit null
are values; absent input/response is a separate condition. Preserve unknown
native tags or return a documented unsupported-type error; do not stringify them.

`Transport.request/3` returns an identity-bound `Wotex.Runtime.Result` and closes
scoped resources in `after`. `subscribe/4` establishes a connection owned by its
receiver, returns its opaque handle and sends `{:wotex_transport_frame, frame}`.
Implement `decode_frame/3` to produce `{:ok, value, metadata}`, `:ignore` only for
documented control frames, or an Error. Terminal stream loss sends
`{:wotex_transport_status, :session_lost}` or `:transport_down` as appropriate.
`unsubscribe/4` releases the handle. No callback invents a canonical device state.

Do not retain the immediate ExecutionContext or its credential after the
callback requiring it. Native session configuration is a separate explicit
consumer-owned custody boundary; protocol-specific .10 rules decide which
Runtime credential inputs are accepted. Credentials come from the explicit
execution context or native adapter options,
never from the Form or global application configuration. Accept only credential
types specified in WMB.10. A credential/profile mismatch fails before I/O.
When an original route is bound to a handle, cancellation uses that route rather
than allowing an unrelated stop Form to redirect the cancellation.

## WMB-C07 — Optional native executable contract

The eight-function BEAM TCP profile has no native runtime executable. Its C
libmodbus peer is test-only and follows WMB.13. The following rules apply only
to a separately specified future native-runtime profile.

Applies only to explicitly specified native SDK executables through Erlang Ports. The executable is an
absolute caller-selected path; arguments are separate values, never shell text.
Owned bridges use a persistent process only when the profile requires sessions
or signals. One-shot profiles retain their existing documented lifecycle.
Use protocol version 1 JSON lines with UTF-8 encoding and a 128 KiB limit per
line including the newline. Request IDs are opaque strings, unique within the
bridge generation. A startup `ready` response identifies bridge protocol and
backend revision; an unsupported version/revision fails before application I/O.

| Envelope | Required fields |
| --- | --- |
| Ready | `version: 1`, `event: "ready"`, `backend`, exact `revision` |
| Request | `version: 1`, `id`, `operation`, `parameters`, finite `timeout_ms` |
| Success | `version: 1`, matching `id`, `ok: true`, `result` (explicit null allowed) |
| Failure | `version: 1`, matching `id`, `ok: false`, bounded library `error.code` and optional numeric `error.status` |
| Stream report | `version: 1`, `subscription_id`, `generation`, `event`, `value`, bounded `metadata` |

Protocol-specific parameters and value envelopes are defined in WMB.10 and
[WMB.13](WMB.13-native-build-and-software-evidence.md). Native protocols execute in BEAM/OTP or
the named SDK; Mix/ExUnit owns build and fixture orchestration.
Reject duplicate JSON keys, fields outside the selected envelope/operation
allowlist, extra responses for one ID,
malformed JSON, non-finite numbers, wrong IDs and incomplete lines at EOF.
Depth is at most eight, each array/map at most 1024 entries, and total value nodes
at most 4096 unless a narrower protocol limit applies. Base64 bytes use the
literal envelope `{"type":"bytes","base64":"..."}`; decoding must enforce
the decoded-byte limit before use. Do not confuse dictionaries with native bytes
unless this exact envelope is selected by the typed schema.

Reserve a dedicated output channel for framed messages; native stdout/stderr logs
cannot share it or leak through error text. Startup, shutdown and descendants
must be bounded. EOF from the owner cancels active operations, releases native
subscriptions/sessions and exits. The BEAM owner escalates from graceful shutdown
to termination after its 1000 ms cleanup grace. Test actual process EOF, killed
children, truncated output, large logs and cleanup failures. A trusted arbitrary
consumer callback cannot be made resource-safe by return-shape validation alone;
first-party bridges must enforce these obligations themselves.

## WMB-C08 — Telemetry and diagnostics

Retain request event `[:wotex, :modbus, :request, :stop]`, duration in native
monotonic units and finite operation/result/status metadata. Add stream events
`[:wotex, :modbus, :subscription, :open | :deliver | :close]` with counts and a
finite result code. No credential, raw value, hostname, URI, user-provided
subscription name or unbounded exception string enters telemetry. Test telemetry
with canary credentials and payloads, including exception and startup failure.
Avoid a global registry for sessions, receivers or protocol IDs.

## WMB-C09 — Mandatory software evidence

[WMB.13](WMB.13-native-build-and-software-evidence.md) fixes the explicit Mix task, native
manifest, resource ownership and evidence contract. Its task acceptance requires
actual executions; results from a different harness remain separately identified.

Each requirement ID in WMB.10/.11/.12 requires concrete acceptance cases with
exact inputs and expected output. The V tables are scenario families, not
executed vectors. Bind concrete fixture IDs to actual assertions before accepting
a requirement; fixture presence alone is insufficient. Add valid, invalid, boundary, forged-struct,
extension-preservation, lifecycle and late-message cases. Generate bounded random
frames/values and retain the seed for failures. Test every split of representative
stream frames plus coalescing, replay and truncation. Use local software peers;
an explicitly selected fake driver proves only the driver contract.

Run at least 1000 sequential operations and 100 open/close cycles against a
software fixture. For profiles with subscriptions, also run 100 receiver
termination cycles; unsupported subscription profiles explicitly mark that cell
inapplicable instead of adding a fake subscription. With 32 concurrent callers, prove
correlation and bounded admission. At every completed lifecycle cycle, assert
that tracked owner processes, ports, sockets, timers and native subscriptions
return to baseline after the cleanup grace. Report heap/RSS trends separately;
allocator caching alone is not a leak and a flat process count alone is not proof
that native resources were released. Force deadline, peer-close and malformed
response failures during the stress lane. Never loop writes against user devices.

The mandatory matrix is Elixir 1.18 / OTP 27 and Elixir 1.20 / OTP 29, with exact
patch versions recorded in results. Use a Linux runner for Linux-only/native
fixtures. Select `:interop`/`:software` explicitly and fail when a required peer,
SDK, executable, kernel facility or response is missing. Physical `:hardware`
tests are independent and do not block software completion. No skipped required
software lane can be reported as a pass.

## WMB-C10 — Commits and completion

Implement one work package from the plan, its tests, docs and provenance as one
reviewable change. Run `mix check` before every local commit. Preserve the 95%
coverage floor; neither coverage alone nor an injected mock is interoperability
proof. Native dependency audits are additional to the Elixir gate. Keep exact
source pins and review any changed dependency/advisory instead of ignoring it.

Before calling the software profile complete: all requirement vectors pass; all
required software lanes run; public capability claims match implementations;
README/current-profile documents match behavior; vector SHA-256 identities are
current; the declared minimum-version matrix passes; and a clean committed-source
archive passes `mix check` and out-of-tree package compilation. Include native
bridge assets explicitly in the package allowlist, excluding build caches,
credentials, sockets, PLTs, fixture state and downloaded SDKs.

Use the required author and committer identity from `CLAUDE.md`. Do not configure
remotes, push, tag, publish, change repository visibility or edit consumers.
Keep transient run logs and exploratory patches in ignored local work files.
The checked-in plan is an acceptance contract, not a worker coordinator.
