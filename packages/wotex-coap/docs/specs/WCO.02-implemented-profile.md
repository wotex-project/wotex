---
spec:
  id: WCO.02
  title: "Implemented CoAP profile"
  status: accepted
  version: 1.3.0
  owner: wotex-coap
  updated: 2026-09-09
---

# WCO.02 Implemented CoAP profile

`coap://numeric-host:port/path?query` selects UDP and default port 5683;
`coaps://numeric-host:port/path?query` selects DTLS and default port 5684. Both
map URI-Path/URI-Query options. `readproperty` defaults to GET, `writeproperty` to PUT and `invokeaction`
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

A Connection owns one UDP or explicitly selected OTP DTLS socket and serializes requests with queue time inside
the deadline. Empty ACK ends retransmission but does not finish a request.
Separate CON replies are acknowledged. IDs are held for the 247-second exchange
lifetime; exhaustion fails. The production initial ACK timeout is randomized
between two and three seconds, with exponential backoff and at most four
retransmissions. Tests may supply a shorter explicit `ack_timeout`.
Runtime transport configuration admits the overall `timeout`, bounded
`ack_timeout`, and the Blockwise size/body/exchange budgets; unknown, duplicate
or malformed keys fail before a socket is opened. The admitted ACK timeout is propagated to the owned Connection.

The owner checks the absolute interaction deadline before processing datagrams
and accepting worker completion. A delayed timer cannot admit an overdue result.
An expired unary interaction closes its generation and refuses queued work;
transmitted mutations retain unknown effect without automatic replay.

Whole-body Block1/Block2 exchanges follow [WCO.03](WCO.03-blockwise.md).
Observe registration, initial complete representation, serial freshness, renewal,
blockwise reports, cancellation and receiver-loss cleanup are implemented.
Valid stale reports are ignored before applying the report Content-Format policy;
their ETag, payload and Max-Age cannot change the accepted representation or its
expiry. A fresh Content-Format change remains a terminal representation error.
Concurrent cancellation callers share one exchange but retain individual
completion deadlines. A timely peer confirmation cannot make local completion
at or after a caller's deadline succeed; local closure does not resend cancellation.
Duplicate separate replies retain ACK behavior across completed exchanges.
`discover/2` validates status/Content-Format and parses bounded RFC 6690 links.

Native `coaps` uses DTLS 1.2 with explicit PSK or PKI credentials and no UDP
fallback. Runtime exposes credential-free UDP and authenticated DTLS cells.
`profile/0` and `profile(:udp)` expose the unary `:coap` profile;
`profile(:udp_observe)` exposes the seven-operation `:coap_observe` profile.
`profile(:dtls)` exposes the seven-operation `:coaps` profile. All use the
three documented media types. Other profile modes are unsupported.
Transport validates the exact profile and Runtime context before acquisition;
decode and cleanup cannot turn an expired request into success. Error.class
retains conservative retry decisions through Runtime. For DTLS unary requests,
exactly one typed Security value is supplied through either the immediate
ExecutionContext credential or the transport `security:` option. Configured
and immediate credentials together fail as ambiguous. Subscriptions require
configured `security:` and a nil immediate credential; the handle contains no
secret or execution context. UDP rejects either credential source. Security
validation and matching the Form scheme to the selected profile precede socket
acquisition. OSCORE remains planned under .10/.12/.13. OSCORE's C Port owns one libcoap engine; no native
helper is needed for the existing UDP or OTP DTLS paths.

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
