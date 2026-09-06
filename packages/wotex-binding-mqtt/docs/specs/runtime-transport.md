# WBM.03: Runtime transport

Specification `WBM.03@1.0.0`; package baseline `wotex_binding_mqtt 0.1.0`.
Requires `WBM.01`, `WBM.02`, `wotex_runtime:WRT.01`.

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

## Lifecycle and concurrency matrix

| Stage | Binding obligation | Consumer-owned remainder |
|---|---|---|
| Construct | Seven-operation profile/config; no process/session | Select trusted broker client |
| PUBLISH | Map/encode then call client once | QoS handshake, retry and physical-effect uncertainty |
| Retained read | Finite timeout, topic match, retained flag, size/JSON admission | Network deadline and temporary subscription cleanup |
| Subscribe | Credential-free delivery closure and opaque handle | Session resources and receiver lifetime |
| Delivery | Filter match before decode; one Runtime message per valid callback | Duplicate/loss/ordering and mailbox overload |
| Bad delivery | Stable error; no Runtime payload | Drop/close/recovery policy |
| Unsubscribe | Pass handle and mapped command to client | Handle/session authority and resource release |
| Crash/forced stop | No recovery process | Reconcile subscriptions and possible effects |

There is no `queryaction`, `cancelaction` or Thing-level aggregate support in
this profile. PUBLISH success is not canonical Property truth, Action
completion or physical-effect certainty, including QoS 2. A retained read is
not a request/response correlation protocol.

The binding tracks no open-handle registry, receiver monitor or once-only close
state. The consumer must define concurrency, duplicate close, session ownership
and recovery. Handles/configuration must be credential-free. The Runtime
supervision proof in WBM-C04 must cover stop and restart, not merely direct
fake-client calls. No package-global connection manager closes these gaps.

## Error and compatibility evidence

Mapping/client/codec failures return stable `Wotex.Binding.MQTT.Error` values.
Rejection before callback has no MQTT effect; failure after possible PUBLISH
does not establish no effect. `transport_test.exs` and
`library_contract_test.exs` under `test/wotex/binding/mqtt/` are current adapter
evidence. WBM-C02/03/04 add malformed returns, client exceptions, deadline,
capture, concurrent-close and archive/reference-consumer proof. Callback tuple,
notification envelope, operation/default/limit and error changes require
compatibility review; a newer draft cannot silently change behavior.
