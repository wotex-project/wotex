---
spec:
  id: WOP.01
  title: "OPC UA protocol and graduation contract"
  status: accepted
  version: 1.0.0
  owner: wotex-opcua
  updated: 2026-09-09
---

# WOP.01 OPC UA protocol and graduation contract

OPC Foundation Part 4 and Part 6 revision 1.05.07 (2026-04-15), Part 2
revision 1.05.06 (2025-10-22), Part 7 revision 1.05.02 (2022-11-01), and OPC
10101 WoT Binding 1.00 (2026-01-08) govern the relevant behavior. No profile
certification is claimed. Secure channels and sessions require independent
negative-security interoperability evidence before graduation.

NodeId distinguishes numeric, string, GUID and opaque identifiers with a
16-bit namespace index. Namespace URI identities must resolve afresh for each
Session; never assume an index remains stable after reconnect. Preserve StatusCode,
DataValue status/timestamps, null versus absent values, array dimensions and
unknown ExtensionObjects. Binary decoding must return unconsumed tail, reject
illegal signed lengths, truncated fields and excessive nested allocations.

UA TCP has an eight-byte header. Bound message/chunk counts and negotiated
buffers; match RequestId, requestHandle, expected service, channel and token.
Sequence numbers advance across token renewal. Incomplete frames, abort chunks,
wrong identifiers and replayed sequence numbers cannot return success.

CreateSession is followed by ActivateSession before normal services. Distinguish
sessionId from authenticationToken. Disconnect closes Session with subscription
deletion and then the channel; partial startup unwinds sockets and owned
processes. Channel renewal, Session expiry and subscription lifetime are separate
states. A timeout after a Write or Call has unknown effect; no silent replay.

Security None is disabled unless explicitly selected for an isolated fixture.
Reject policy downgrade and unsupported modes before network access. For secure
modes validate signature, chain, trust, time, hostname, application URI, usage,
revocation and nonce requirements. Credentials/trust material are consumer-owned
and omitted from inspect/errors/telemetry. No trust-on-first-use fallback.

OPC 10101 Forms use opc.tcp endpoint hrefs with percent-encoded id query values;
NodeId identity must survive reserved characters. Credentials stay outside TD.
Read/write Properties and monitored observations map to actual OPC UA services.

Acceptance: NodeId and scalar/array roundtrips, malformed lengths, frame splits,
correlation and replay rejection, wrong service/status, owner cleanup, namespace
remapping, expired/untrusted/wrong-host/wrong-URI/revoked certificates and a
pinned independent open62541 or asyncua peer. A parser alone is not a secure
client; a generic external port alone is not interoperability proof.

## Common library rules

Use structured credential-free Error values, explicit finite budgets, immutable
address/value maps, no Application callback and no implicit runtime selection.
Compatibility callbacks are capabilities/connect/send/receive/disconnect/health_check/
subscribe/unsubscribe. A consumer port failure, malformed return or missing
transport is an error; never select simulation. Telemetry event prefixes are
[:wotex, :opcua, ...] with bounded non-secret measurements. Consumer migration
requires differential scenarios against both implementations before replacement.
