# Standards baseline — 2026-09-02

This package uses the following primary documents as a dated engineering
baseline. The maturity labels matter: implementation choices derived from a
draft are documented package behavior, not a conformance claim.

## Primary sources

- [Web of Things Thing Description 1.1, W3C Recommendation, 5 December 2023](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
  defines Form, `op`, `contentType`, response metadata, HTTP vocabulary use, and
  the HTTP method defaults for `readproperty`, `writeproperty`, and
  `invokeaction`.
- [Web of Things Binding Registry, Draft Registry, 4 November 2025](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/)
  says the registry is not finalized or stable and is in a pilot phase. The
  package does not assert that it is a registered entry.
- [Web of Things Profiles, W3C Working Draft, 4 November 2025](https://www.w3.org/TR/2025/WD-wot-profile-20251104/)
  describes HTTP action-status and SSE mappings. Publication as a Working Draft
  does not imply W3C endorsement. The package does not claim Profile
  conformance.
- [Web of Things Binding Templates, retired Group Note, 4 November 2025](https://www.w3.org/TR/2025/NOTE-wot-binding-templates-20251104/)
  is retired and is not treated as an active conformance target. Its status
  directs readers to the TD binding mechanism and the Binding Registry.
- [RFC 9110: HTTP Semantics, June 2022](https://www.rfc-editor.org/rfc/rfc9110)
  defines method tokens, field semantics, status semantics, and representation
  metadata independent of HTTP version.
- [RFC 9112: HTTP/1.1, June 2022](https://www.rfc-editor.org/rfc/rfc9112)
  defines HTTP/1.1 message framing. Framing belongs to the supplied client, not
  to Form or static header configuration.
- [RFC 8259: The JSON Data Interchange Format, December 2017](https://www.rfc-editor.org/rfc/rfc8259)
  is the wire representation baseline.
- [Server-Sent Events in the HTML Living Standard](https://html.spec.whatwg.org/multipage/server-sent-events.html)
  is the current event-stream framing and reconnection reference. The supplied
  client owns framing and connection policy; the binding owns JSON data
  decoding.

The current HTTP binding editor's material may aid implementation review, but
it is not used to claim Recommendation, Profile, or registry conformance.

## Applied decisions

TD 1.1 defaults a missing Form `contentType` to `application/json`. For an HTTP
Form with no `htv:methodName`, TD 1.1 defines `GET` for `readproperty`, `PUT` for
`writeproperty`, and `POST` for `invokeaction`. TD 1.1 also forbids one explicit
`htv:methodName` on a Form that has multiple `op` values. Those rules are
implemented directly.

The package additionally uses the Working Draft's concrete mappings of `GET`
for `queryaction`, `observeproperty`, and `subscribeevent`, and `DELETE` for
`cancelaction`. SSE stop operations close the open connection and perform no
second HTTP exchange. These are stable package API choices for version 0.1,
not W3C Profile conformance claims.

The pinned Runtime selects only Forms that explicitly declare the requested
operation. TD 1.1 `op` default expansion therefore belongs to the TD processor
before Runtime Form selection; the transport does not silently choose an
operation after selection.

HTTP versions, redirects, TLS verification, DNS policy, proxies, timeouts,
reconnection, backpressure, and connection reuse remain supplied-client or
consumer-host policy. The package provides no connection pool.
