# Runtime transport

## Callback compatibility

`Wotex.Binding.MQTT.Transport` implements the Runtime callback surface:

```elixir
request(request, execution_context, config)
subscribe(request, receiver, execution_context, config)
unsubscribe(handle, request, execution_context, config)
```

The adapter has no package process. All calls run in the caller or in the
consumer-owned client implementation.

## Request execution

`writeproperty` and `invokeaction` JSON-encode the request input, build a
PUBLISH command, and invoke `Client.publish/3`. A successful protocol send
returns a Runtime result with no response payload. It does not assert accepted
Property truth or proof of an Action effect.

`readproperty` builds a SUBSCRIBE command only when `mqv:retain` is true. It
invokes `Client.read/4` with the configured finite timeout. The returned
delivery must be retained and its Topic Name must match a Form filter before
its JSON payload becomes the Runtime result.

External client error values and exceptions are replaced with stable,
credential-free binding errors.

## Subscription execution

`observeproperty` and `subscribeevent` build SUBSCRIBE commands. The transport
passes the client a closure that captures only:

- the Runtime receiver PID;
- the immutable command and its Topic Filters;
- the positive payload byte limit.

For a matching valid delivery the closure decodes JSON and sends exactly:

```elixir
{:wotex_transport, payload}
```

Invalid deliveries return a stable error to the client callback and send no
Runtime message. The closure does not capture the execution context.

`unobserveproperty` and `unsubscribeevent` map to UNSUBSCRIBE and pass the
Runtime-owned handle back to `Client.unsubscribe/4`. The package does not store
the handle.

## Configuration

`Wotex.Binding.MQTT.TransportConfig` validates all four client callbacks and two
positive bounds: `read_timeout` and `max_payload_bytes`. Inspection omits the
client configuration. Configuration never contains a credential added by this
package.
