# WBH.03: Server-Sent Events subscriptions

Specification `WBH.03@1.0.0`; package baseline `wotex_binding_http 0.1.0`.
Requires `WBH.01`, `WBH.02`, `wotex_runtime:WRT.01`.

## Open

Only `observeproperty` and `subscribeevent` requests whose selected Form has
`"subprotocol": "sse"` may call the client `subscribe/4` callback. The request
defaults to `GET`, carries `accept: text/event-stream`, and has no body.

The callback must return one opaque handle and a credential-free handshake
response with status 200, `content-type: text/event-stream`, and an empty body
value. The body is empty because stream bytes are delivered incrementally, not
buffered into the handshake value. A failed handshake triggers an immediate
best-effort close of the newly returned handle.

## Events

The supplied client parses wire framing and invokes the handler once per
dispatched `Wotex.Binding.HTTP.SSE.Event`. The event value holds data, optional
event type, optional id, and optional non-negative retry delay.

The binding checks the event byte limit, decodes data as one JSON value, and
sends the Runtime subscription process:

```elixir
{:wotex_transport, {:ok, notification}}
```

The notification preserves event metadata and includes request identity and
the opening WoT operation. Invalid event values, invalid JSON, and oversized
data use `{:wotex_transport, {:error, error}}`.

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
| Active event | Validate byte limit, decode JSON, notify Runtime receiver | Receiver and transport own overload/backpressure |
| Bad event | Send typed error notification; no invented payload | Consumer chooses whether stream continues |
| Stop | Check request identity, paired operation, module/config instance; call close once per valid invocation | Runtime owns logical once-only stop and supervision |
| Duplicate concurrent raw close | No package registry or idempotency state | Consumer client must tolerate duplicate handle close; no global exactly-once claim |
| Receiver dies / forced kill | No new binding process performs cleanup | Consumer transport/session recovery |
| Reconnect | No hidden reopen or replay | Client owns retry, Last-Event-ID and duplicate/loss handling |

The SSE client supplies already-framed events. This binding does not implement
the HTML event-stream parser, browser reconnection algorithm, heartbeat timer,
cursor persistence, event deduplication or bounded process mailbox. The Living
Standard is a client framing reference; draft WoT Profile use is not conformance.

`transport_test.exs` and `integration_test.exs` under
`test/wotex/binding/http/` cover the current open/event/close boundary. WBH-C02
adds independently repeated close, failed cleanup and receiver/concurrency
vectors without transferring connection ownership into the package. WBH-C03
must measure sustained event delivery and prove the supplied-client overload
contract before claiming bounded streaming memory or recovery guarantees.
