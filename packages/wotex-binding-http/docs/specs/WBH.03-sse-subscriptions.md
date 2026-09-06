# Server-Sent Events subscription specification

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
