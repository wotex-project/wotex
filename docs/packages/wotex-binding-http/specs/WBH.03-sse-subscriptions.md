# WBH.03: Server-Sent Events subscriptions

Specification `WBH.03@1.2.0`; package baseline `wotex_binding_http 0.1.0`.
Requires `WBH.01`, `WBH.02`, `wotex_runtime:WRT.01`.

## Open

Only `observeproperty` and `subscribeevent` requests whose selected Form has
`"subprotocol": "sse"` may call the client `subscribe/4` callback. The request
defaults to `GET`, carries `accept: text/event-stream`, has no body, and
publishes the configured `max_event_bytes` so the client can abort an oversized
event while reading it.

The callback receives the Runtime subscription process as its `owner`. That
process is the only destination for stream messages, and it is where decoding
runs.

The callback must return one opaque handle and a credential-free handshake
response with status 200, `content-type: text/event-stream`, and an empty body
value. The body is empty because stream bytes are delivered incrementally, not
buffered into the handshake value. A failed handshake triggers an immediate
best-effort close of the newly returned handle.

## Events

The supplied client parses wire framing and sends the owner one message per
dispatched event:

```elixir
{:wotex_transport_frame, %Wotex.Binding.HTTP.SSE.Event{}}
```

The event value holds data, optional event type, optional id, and optional
non-negative retry delay. The client performs no decoding, so its connection
process never runs the JSON codec and never allocates a decoded term.

Runtime calls `Wotex.Binding.HTTP.Transport.decode_frame/3` inside the owner
process for every frame. It checks the event byte limit, decodes data as one
JSON value through the bounded core admission limits, and returns
`{:ok, data, meta}`. The `meta` map carries `event`, `id`, `retry`,
`request_id`, and the opening WoT operation. A frame with empty data is a
comment or keep-alive and returns `:ignore`. An invalid frame value, an
oversized event, and invalid JSON return a `:protocol` binding error, which
Runtime reports to the receiver as an `:undecodable_frame` error whose
`details.cause` retains this package's `code`, `phase`, and `class`.

The consumer receiver therefore observes:

```elixir
{:wotex_runtime, subscription_id, {:ok, data, meta}}
{:wotex_runtime, subscription_id, {:error, %Wotex.Runtime.Error{}}}
{:wotex_runtime, subscription_id, {:status, status}}
```

## Session status

A client that observes a stream-level condition sends the owner
`{:wotex_transport_status, status}` with `:reconnected` when the session
survived a reopen, `:session_lost` when the server-side subscription is gone, or
`:transport_down` when the client can no longer serve the subscription. Runtime
forwards `:reconnected` to the receiver and keeps the subscription; the other
two notify the receiver, attempt the close, and stop the process with a
`:shutdown` reason so the consumer's supervisor decides on resubscription. A
client that links its connection process to the owner produces the same result
through the exit signal.

This package sends no status of its own, retries nothing, and installs no
timer. Deciding that a session was lost is client knowledge.

## Close

`unobserveproperty` must match an `observeproperty` handle;
`unsubscribeevent` must match a `subscribeevent` handle. Request identity and
client module and opening configuration instance reference must also match.
Each validated configuration construction creates a fresh non-secret reference;
the consumer reuses that immutable configuration throughout the stream lifecycle.
Another configuration, even with equal client options, fails before calling
`close/2`. No registry, process owner restriction, or credential hash is involved.
The reference prevents accidental cross-instance routing among trusted callers;
it is not an isolation boundary against code forging internal values.
A valid close calls the supplied client's
`close/2` exactly once and makes no hidden HTTP exchange.

The opaque handle stores no credential or client configuration. Stop-time
credentials are not passed to `close/2` because terminating an SSE connection
is local connection lifecycle, not a second authenticated request.

## Lifecycle, concurrency and recovery matrix

| Stage | Binding contract | Consumer contract / evidence |
|---|---|---|
| Configure | No stream or process; fresh nonsecret instance ref | Reuse exact configuration for open/close |
| Open | Validate Form then pass callback to client | Client owns socket, TLS, framing and deadline |
| Handshake invalid after handle returned | Attempt immediate close, return failure | Close failure cannot prove remote cleanup |
| Active event | Client sends a raw frame to the owner; the owner decodes it under the event byte limit | Runtime can bound receiver delivery; client owns socket/parser and owner-send backpressure |
| Keep-alive frame | Empty data is ignored without a delivery | Client decides what a heartbeat looks like on the wire |
| Bad event | Classified `:protocol` error becomes an `:undecodable_frame` delivery; no invented payload | Consumer chooses whether stream continues |
| Session status | `:reconnected` notifies only; `:session_lost` and `:transport_down` notify, close and stop with `:shutdown` | Consumer supervisor owns restart and resubscription |
| Owner exit | Client may monitor or link the owner and release its connection | No package process cleans up a client connection |
| Stop | Check request identity, paired operation, module/config instance; call close once per valid invocation | Runtime owns logical once-only stop and supervision |
| Duplicate concurrent raw close | No package registry or idempotency state | Consumer client must tolerate duplicate handle close; no global exactly-once claim |
| Receiver dies | Runtime owner invokes the normal close path; no binding process is started | Consumer supervisor owns any restart |
| Forced kill | No new binding process performs cleanup | Consumer transport/session recovery |
| Reconnect | No hidden reopen or replay | Client owns retry, Last-Event-ID and duplicate/loss handling |

The SSE client supplies already-framed events. This binding does not implement
the HTML event-stream parser, browser reconnection algorithm, heartbeat timer,
cursor persistence, event deduplication or bounded process mailbox; Runtime owns
the optional receiver mailbox bound. The Living
Standard is a client framing reference; draft WoT Profile use is not conformance.

The [client lifecycle inventory](../client-lifecycle-inventory.md), the
[limits and security inventory](../limits-security-inventory.md),
`client_lifecycle_inventory_test.exs`, `limits_security_test.exs`,
`transport_test.exs` and `integration_test.exs` cover the open/event/close
boundary, including exact event-byte thresholds, malformed handshakes, cleanup
callback failures, configuration transplant, duplicate raw close, concurrent
Runtime stop, receiver death, session loss, linked-client failure, sustained
delivery against a configured Runtime receiver bound, and connection-exit
redaction. These vectors do not transfer connection ownership into the package.
Pending-establishment owner monitoring, socket/parser backpressure, connection
mailbox bounds, and hostile concurrent-send behavior remain consumer evidence
prerequisites for any hard bounded-memory or recovery guarantee.
