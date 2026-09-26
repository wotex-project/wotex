# WUD.01 — Bounded datagram transport

Version: 0.2.0-target. Planned package; no source or interoperability claim.

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

## Evidence

WUD-T1: pure constructors have no I/O. WUD-T2: real IPv4/IPv6 loopback preserves message boundaries, including empty datagrams. WUD-T3: oversized/truncated packets never reach an application as valid. WUD-T4: active-credit exhaustion, slow receiver and flood remain bounded. WUD-T5: owner crash, stale handle, cancellation and port reuse. WUD-T6: broadcast/multicast permission, membership cleanup, scope and interface churn. WUD-T7: independent binary-protocol consumer on macOS and Linux/ARM, with source identity and byte traces. Loopback evidence is not proof of physical WLAN behavior.
