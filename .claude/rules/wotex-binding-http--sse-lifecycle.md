---
paths:
  - "packages/wotex-binding-http/**"
---

# SSE lifecycle rule (wotex-binding-http)

Applies to the SSE and transport modules and their tests
(`lib/**/sse/*.ex`, `lib/**/subscription.ex`, `lib/**/notification.ex`,
`lib/**/transport.ex` and `test/**/transport_test.exs` inside the package).

Only `observeproperty` and `subscribeevent` Forms with `subprotocol: sse` open
streams. The supplied client owns the connection and framing. The binding owns
JSON decoding and notification construction. `unobserveproperty` and
`unsubscribeevent` close the exact opaque handle and make no hidden request.
