---
paths:
  - "lib/**/*sse*.ex"
  - "lib/**/transport.ex"
  - "test/**/*sse*.exs"
  - "test/**/transport_test.exs"
---

# SSE lifecycle rule

Only `observeproperty` and `subscribeevent` Forms with `subprotocol: sse` open
streams. The supplied client owns the connection and framing. The binding owns
JSON decoding and notification construction. `unobserveproperty` and
`unsubscribeevent` close the exact opaque handle and make no hidden request.
