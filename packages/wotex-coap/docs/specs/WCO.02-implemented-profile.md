---
spec:
  id: WCO.02
  title: "Implemented CoAP profile"
  status: accepted
  version: 1.0.0
  owner: wotex-coap
  updated: 2026-09-09
---

# WCO.02 Implemented CoAP profile

`coap://numeric-host:port/path?query` maps to a UDP endpoint and URI-Path/URI-Query
options. `readproperty` defaults to GET, `writeproperty` to PUT and `invokeaction`
to POST. Explicit `cov:method` may select GET/PUT/POST/DELETE. `cov:confirmable`
is Boolean; `cov:accept` is a 16-bit Content-Format ID; `cov:contentFormat` must
match the chosen content type. Supported content types are `application/json`,
`application/octet-stream`, and `text/plain;charset=utf-8`. Unknown extensions
are retained. Non-success response codes are errors. Runtime uses complete Block1/Block2 transfers before content conversion;
a raw partial response passed directly to Mapping.decode still fails closed.

Codec limits: 1152-byte datagrams, eight token bytes, 64 options; malformed
reserved option nibbles, length overflow and empty payload markers fail.
Options are ordered numerically and unknown elective options survive.
Critical option validation is separate from syntactic decode.

A Connection owns one UDP socket and serializes requests with queue time inside
the deadline. Empty ACK ends retransmission but does not finish a request.
Separate CON replies are acknowledged. IDs are held for the 247-second exchange
lifetime; exhaustion fails. The production initial ACK timeout is randomized
between two and three seconds, with exponential backoff and at most four
retransmissions. Tests may supply a shorter explicit `ack_timeout`.
Runtime transport configuration admits the overall `timeout`, bounded
`ack_timeout`, and the Blockwise size/body/exchange budgets; unknown, duplicate
or malformed keys fail before a socket is opened. The admitted ACK timeout is propagated to the owned Connection.

Observe serial comparison is a pure helper. Whole-body Block1/Block2
exchanges are implemented in [WCO.03](WCO.03-blockwise.md). Active observation
and renewal remain pending. Duplicate separate-response ACK caching across exchanges is not yet
implemented. Do not use this profile for long-lived Observe traffic.

## Evidence and compatibility

See [executable evidence](../provenance/executable-evidence.md) for specific tests,
commands and remaining gates, and [source revisions](../provenance/primary-sources.md).
Public callbacks provide a neutral compatibility surface, not drop-in semantic
parity. `send/2` completes synchronously; no fictitious receive queue exists.
The consumer must run differential scenarios before replacing its implementation.

Runtime adapters reject credential objects they cannot interpret. Native client
credentials/options are supplied explicitly by the consumer. A custom Client
implementation is trusted executable code and must honor the timeout and cleanup
contract; the wrapper cannot impose those guarantees on an arbitrary module.
Unknown Form extensions remain immutable but are not silently treated as
implemented protocol behavior. Finite deadlines, unsupported operations and
remote failures use structured Error values. Failed mutations report unknown
effect when execution may have started; a transport acknowledgment is not
canonical device state.
