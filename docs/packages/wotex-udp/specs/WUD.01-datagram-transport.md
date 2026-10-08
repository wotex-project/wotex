# WUD.01 — Bounded datagram transport

Version: 0.6.0-target. The catalogue records implementation status and
physical interoperability evidence separately.

## Boundary

**WUD-01.** UDP is a transport, not a WoT interaction binding. This package owns endpoint/configuration values, explicit socket ownership, bounded send/receive and lifecycle errors. It does not own application packet codecs, discovery matching, request correlation, retry semantics, canonical observations or authorization. It needs no home/device vocabulary or dependency on a consumer.

The implementation should use existing OTP socket facilities behind a small explicit port. Do not implement a second IP stack or force another protocol package to replace its native transport. Extraction requires demonstrated reuse and lifecycle benefits, not just two protocols using UDP.

## Values and lifecycle

**WUD-02.** Endpoint values carry address family, literal address, port and IPv6 scope when required. Configuration names local address/interface, broadcast permission, multicast groups/interfaces, hop limits, buffer ceilings, receive credits and deadlines. Pure constructors read no environment, clock, DNS or network state.

An explicitly started owner opens a socket and supplies an opaque handle with an owner epoch. Calls on a stopped/replaced owner fail as stale; operating-system descriptor reuse cannot reactivate an old handle. Shutdown cancels delivery and releases memberships exactly once. A consumer chooses its supervision tree and any naming.

**WUD-03.** Resolve names outside pure values under the caller's deadline/network policy. Unicast, IPv4 broadcast and IPv4/IPv6 multicast are distinct capabilities; IPv6 has no broadcast. Unsupported socket/interface options fail visibly, never fall back to a broader route. Broadcast/multicast is disabled unless selected. Interface changes terminate or explicitly rebind the owner; they do not silently widen its egress scope.

## Bounds and truncation

**WUD-04.** Bound datagram bytes, queued bytes, mailbox deliveries, receive credits, concurrent sends and elapsed operation time. Use passive reads or finite active credits, not unconstrained active delivery. The consumer gets explicit overflow/loss information; a drop is not a successful reply. Defaults must be documented and tested in the eventual package, not inherited accidentally from the OS.

[OTP gen_udp](https://www.erlang.org/doc/apps/kernel/gen_udp.html) documents finite active modes and potential silent truncation when buffers are too small. Therefore the backend must either detect/report truncation using a qualified API or allocate a sufficient bounded receive buffer for the admitted datagram envelope and reject over-limit data before protocol delivery. Never feed a truncated message to a decoder as if it were a complete valid packet. OS kernel drops remain observable only to the extent supported; do not fabricate a complete loss count.

## Delivery and security

**WUD-05.** Send success means the local stack accepted bytes, not remote delivery or physical action. No retries, acknowledgements, encryption or packet deduplication are invented at this layer. Source addresses are untrusted metadata. Consumers apply protocol correlation and identity policy. Rate budgets and reflection/amplification prevention apply to broadcast/multicast use; unsolicited packets cannot trigger unbounded responses.

## Error and compatibility contract

Typed errors distinguish invalid endpoint/configuration, unsupported feature, permission failure, owner loss, deadline, oversize/truncation, overload and OS error class without leaking payloads. Future public callback names and values must be versioned before implementation. A generic transport is not automatically a `Wotex.Runtime.Transport`; the protocol mapping supplies that adapter where needed.

## Development API 0.1.0

The first public seam has `Wotex.UDP.Endpoint.bind/3`, `unicast/3`,
`broadcast/2` and `multicast/3`; `Wotex.UDP.Config.new/1`; and
`Wotex.UDP.open/1`, `child_spec/2`, `handle/1`, `local/1`, `send/4`, `recv/2`,
`recv_batch/3`, `join/3`, `leave/3` and `close/1`. Constructors return
`{:ok, value}` or a typed error. Socket calls return `:ok`, `{:ok, value}` or
`{:error, %Wotex.UDP.Error{}}`. `Wotex.UDP.Handle` is opaque; the epoch is
validated by the owner. This API is a development contract, not an
interoperability or release claim.

`multicast: true` requires `multicast_interface:` in `Wotex.UDP.Config.new/1`.
An IPv4 socket takes a concrete unicast interface address; an IPv6 socket takes
an integer interface index from 1 to 2,147,483,647. A missing value, wildcard
address, index zero, wrong family or interface option without multicast
permission returns `invalid_config`. The owner sets the corresponding OTP
[`multicast_if` socket option](https://www.erlang.org/docs/27/apps/kernel/socket.html#socket_option/0)
before binding. An unavailable or unsupported option fails
open with a typed OS error and closes the new socket; no default-route fallback
is attempted. This is explicit multicast egress selection, not an operating-system
network sandbox or proof of physical network delivery.

Receive membership remains a separate explicit `join/3` or `leave/3` operation.
IPv4 memberships reject wildcard, multicast and broadcast interface addresses;
IPv6 memberships reject index zero and out-of-range indices. A scoped IPv6 group
must match the membership index, and a scoped IPv6 send destination must match
the configured egress index. Mismatches return `invalid_endpoint` before I/O.
Membership changes do not change the configured egress interface. A consumer
reopens the owner to select another egress interface. OTP rejection of an
unavailable socket option returns `unsupported_feature`; it does not substitute
another API or interface. IPv6 egress selection and IPv6 receive membership
are independently supported cells and require their own host evidence.

The passive receive mode has no unsolicited mailbox deliveries.
`max_batch_datagrams` is the per-call receive credit. The kernel receive
buffer is requested in bytes and may be adjusted by the OS. Operation calls
atomically publish their complete request and reserve both the call slot and
binary send bytes in one owner-owned ETS record. Defaults admit 32 pending
operations and 65,536 send bytes; a full budget returns `overload`. There is no
separate reservation-before-message interval. The owner retains each published
request until it completes, is canceled or is rejected under its original
absolute deadline. Owner death automatically deletes the queue; a stale handle
cannot publish into a replacement owner.

Only one coalesced wakeup is admitted for the current owner notification alias.
The owner also sweeps the queue every ten milliseconds, so death or suspension
after publication and before notification cannot strand a call or byte budget.
Each sweep retires the previous alias before publishing the next one and drops
its already queued wakeup. Delayed old notifications cannot accumulate across
sweeps or replay work. No request payload enters the owner mailbox. Claims and
releases operate on complete request identities; duplicate release is inert.
The queue is an internal per-owner resource, with no global name or registry.

Handle retrieval reads a single immutable process-local metadata record on a
local owner; it queues no owner call and remains available while operation
admission is saturated. An arbitrary process or malformed selector returns
`invalid_handle`; a dead owner returns `owner_lost`. Receiving boundaries compare
all opaque handle fields with that record before reserving admission. A changed
epoch returns `stale_handle`; substituted limits/queue identity or extra fields return
`invalid_handle` and cannot modify the live queue.

Socket waits use OTP's asynchronous select API with one active operation.
The owner monitors each caller when it claims the published request. Caller
loss cancels an active select or removes queued work, releasing its exact call
and byte reservation. Queued deadlines continue to expire while another
operation waits. Positive deadline equality is expired at dispatch and delivery;
a zero-timeout operation polls the socket without starting an asynchronous wait.
It is refused with `timeout` when another request is pending (or `overload`
when an admission ceiling is full). An idle poll receives a handoff allowance
of at most 100 milliseconds, capped by `max_timeout_ms`, with the same deadline
checks before I/O and delivery. This bounds scheduler handoff without waiting
for socket readiness. The caller's reply alias is retired on completion,
owner loss or timeout, so late replies do not enter its mailbox. An expired
batch returns only datagrams already accepted within its original deadline.
Oversize or socket failures discard the partial batch.

An admitted close cancels the active select, rejects admitted pending calls
with `closed`, and closes the socket before replying. Close shares the finite
call budget and may return `overload` when that budget is full. Supervisor stop
or owner death also closes the owned socket. Admitted close keeps its admission
fence until owner exit deletes the queue; it does not reopen the queue between
socket closure and shutdown. The caller confirms owner exit under its original
bounded handoff deadline before returning an executed close result. An expired
close request releases its fence and leaves the owner available. A canceled or
retired socket notification cannot resume another request or owner. Canceling a send never
replays bytes or proves remote nondelivery. Windows completion-based asynchronous
backends are explicitly refused by this implementation.

The local suite exercises a 100-cycle active receive cancellation workload,
queued caller loss, live queued expiry, close during a batch, two-owner
isolation, owner death and port reuse. It also covers atomic publication without
notification, dead publishers, duplicate identities, repeated release, zero-timeout
admission and retired reply aliases in a live caller. Exact kernel drop accounting
and physical multi-platform qualification remain open; the catalogue retains
`partial` status.

## Evidence

WUD-T1: pure constructors have no I/O. WUD-T2: real IPv4/IPv6 loopback preserves message boundaries, including empty datagrams. WUD-T3: oversized/truncated packets never reach an application as valid. WUD-T4: active-credit exhaustion, slow receiver and flood remain bounded. WUD-T5: owner crash, stale handle, cancellation and port reuse. WUD-T6: broadcast/multicast permission, membership cleanup, scope and interface churn. WUD-T7: independent binary-protocol consumer on macOS and Linux/ARM, with source identity and byte traces. Loopback evidence is not proof of physical WLAN behavior.

| Case | Local executable evidence | Remaining evidence |
| --- | --- | --- |
| WUD-T1 to WUD-T3 | `packages/wotex-udp/test/wotex/udp/transport_test.exs`, `boundary_test.exs` | Host and malformed/truncation matrix |
| WUD-T4 | Finite passive receive, batch and 100-caller atomic publication/byte overload flood in `transport_test.exs` | Kernel drop census |
| WUD-T5 | Supervised owner, owner crash, stale epoch, caller-loss and close cancellation, expired queued work, publication-before-wake caller/owner loss and port reuse in `transport_test.exs` | Physical/platform cohort |
| WUD-T6 | Opt-in, explicit IPv4/IPv6 egress options, wildcard/scope negatives, membership tests and independent loopback multicast peer in `transport_test.exs`, `boundary_test.exs` | Physical interface churn and permission cohort |
| WUD-T7 | Independent Erlang UDP peer with complete byte packets in `transport_test.exs`; exact archive consumer in `packages/wotex-udp/bin/check_archive.exs` | Physical macOS/Linux ARM binary-protocol consumer |
