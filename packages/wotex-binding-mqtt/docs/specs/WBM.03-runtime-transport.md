# WBM.03: Runtime transport

Specification `WBM.03@1.1.0`; package baseline `wotex_binding_mqtt 0.1.0`.
Requires `WBM.01`, `WBM.02`, `wotex_runtime:WRT.01`.

## Callback compatibility

`Wotex.Binding.MQTT.Transport` implements the Runtime callback surface:

```elixir
request(request, execution_context, config)
subscribe(request, owner, execution_context, config)
unsubscribe(handle, request, execution_context, config)
decode_frame(frame, request, config)
```

The adapter has no package process. `request/3` and `unsubscribe/4` run in the
caller, `subscribe/4` runs in the subscription owner that opens the
subscription, and `decode_frame/3` runs in that owner for each raw delivery.
The remaining work runs in the consumer-owned client implementation.

## Request execution

`writeproperty` and `invokeaction` JSON-encode the request input, build a
PUBLISH command, and invoke `Client.publish/3`. A broker acknowledgement is an
`:accepted` result with no response payload: the Application Message was
accepted, which is not proof that any subscriber received it, that Property
truth was accepted, or that an Action effect occurred.

`readproperty` builds a SUBSCRIBE command only when `mqv:retain` is true. It
invokes `Client.read/4` with `min(read_timeout, remaining deadline)`. The
remaining budget comes from `Wotex.Runtime.Context.remaining_ms/2` with a clock
reading taken at call time: `System.monotonic_time(:millisecond)` for an integer
deadline and `DateTime.utc_now/0` for a `DateTime` deadline. An exhausted
deadline returns `deadline_exceeded` without calling the client, and a deadline
that matches neither clock returns `invalid_deadline_clock`. The returned
delivery must be retained and its Topic Name must match a Form filter before its
JSON payload becomes an `:ok` result. Control packet, QoS, retain flag, and the
delivery Topic Name stay in the result metadata.

External client error values and exceptions are replaced with stable,
credential-free binding errors.

## Subscription execution

`observeproperty` and `subscribeevent` build SUBSCRIBE commands and pass the
client the immutable command and the subscription owner pid. There is no
delivery closure: the only values that outlive the call are the command, which
carries the Topic Filters and `max_payload_bytes`, and the owner pid.

The client sends each raw delivery to the owner as
`{:wotex_transport_frame, delivery}` and connection changes as
`{:wotex_transport_status, status}`, as specified in WBM.01. Decoding therefore
never runs on the client's connection process. The owner invokes
`decode_frame/3`, which:

1. normalizes the value into a `Wotex.Binding.MQTT.Delivery`;
2. returns `:ignore` when the Topic Name matches no command Topic Filter,
   because a shared connection may deliver unrelated topics;
3. enforces `max_payload_bytes` and decodes JSON under the WBM.01 limits;
4. returns `{:ok, payload, meta}` with `meta` carrying `:topic`, `:qos`,
   `:retained`, `:request_id`, `:operation`, `:control_packet`, and `:binding`.

The Topic Name in `meta` is what lets an aggregate receiver tell which Property
or Event a value belongs to. A frame that cannot be decoded returns a stable
binding error, which the Runtime reports to the receiver as an
`undecodable_frame` error carrying this error's code, phase, and class.

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
| Subscribe | Owner pid and credential-free command; opaque handle | Session resources, owner supervision and receiver lifetime |
| Delivery | Filter match before decode; decode in the owner; ignore unrelated topics; WBM-C03 proves sustained delivery and Runtime overflow cleanup | Duplicate/loss/ordering, BEAM allocation and client/broker queues |
| Bad delivery | Stable classified error; no Runtime payload | Drop/close/recovery policy |
| Session change | Client-sent status; owner stops on `:session_lost` and `:transport_down` | Detecting Clean Start/expiry and deciding restart |
| Unsubscribe | Pass handle and mapped command to client | Handle/session authority and resource release |
| Crash/forced stop | No recovery process | Reconcile subscriptions and possible effects |

There is no `queryaction`, `cancelaction` or Thing-level aggregate support in
this profile. PUBLISH success is not canonical Property truth, Action
completion or physical-effect certainty, including QoS 2. A retained read is
not a request/response correlation protocol.

The binding tracks no open-handle registry, receiver monitor or once-only close
state. The consumer must define concurrency, duplicate close, session ownership
and recovery. Handles/configuration must be credential-free. Explicit stop and
session loss under real Runtime supervision are proven by
`runtime_subscription_test.exs`. The WBM-C02 lifecycle proof adds concurrent
handles, complete callback-failure normalization, failed open/close behavior,
and supervisor-driven restart against a supplied client. A real broker/client
cohort remains WBM-C04 work. No package-global connection manager closes these
gaps.

## Error classification

Every `Wotex.Binding.MQTT.Error` carries a `class` that the Runtime copies into
its own error cause for `Wotex.Runtime.Retry`. Classification states how a
failure arose; it never asserts that repeating an Action is safe.

| Cause | Representative codes | Phase | Class |
|---|---|---|---|
| Exhausted request deadline before a read | `deadline_exceeded` | `client` | `timeout` |
| Client port returned an error, raised, exited or threw | `client_publish_failed`, `client_read_failed`, `client_subscribe_failed`, `client_unsubscribe_failed` | `client` | `unavailable` |
| Rejected broker, topic, QoS, command, mapping or codec value | `unsupported_broker_scheme`, `invalid_topic_filter`, `invalid_qos`, `control_packet_mismatch`, `json_decode_failed`, `received_payload_too_large` | `broker`, `topic`, `command`, `mapping`, `codec` | `protocol` |
| Delivery that violates the MQTT contract of the operation | `non_retained_property_read`, `delivery_topic_mismatch`, `invalid_delivery`, `invalid_client_return` | `client` | `protocol` |
| Consumer configuration no retry repairs | `invalid_transport_configuration`, `invalid_client_port`, `invalid_transport_option`, `invalid_transport_input`, `invalid_payload_limit`, `invalid_deadline_clock` | `configuration`, `codec`, `command` | `permanent` |

This package never returns `rate_limited`; MQTT back-pressure and broker quota
policy belong to the consumer's client.

## Error and compatibility evidence

Mapping/client/codec failures return stable `Wotex.Binding.MQTT.Error` values.
Rejection before callback has no MQTT effect; failure after possible PUBLISH
does not establish no effect. `transport_test.exs`,
`runtime_subscription_test.exs`, `client_lifecycle_test.exs`,
`limits_security_test.exs`, and
`library_contract_test.exs` under
`test/wotex/binding/mqtt/` are current adapter evidence;
`runtime_subscription_test.exs` starts a real `Wotex.Runtime.ConsumedThing`
observation child under a test supervisor and covers owner decoding, ignored
topics, an oversized frame, session loss, and an explicit stop observed by a
monitoring client. `client_lifecycle_test.exs` proves finite supplied-client
reads, all invalid and exceptional callback paths, open/close failures,
concurrent handles, and consumer-supervised restart. `limits_security_test.exs`
proves exact value/structural thresholds, bounded filter cardinality, sustained
delivery, Runtime overflow cleanup, redaction, and the trusted-client authority
boundary. WBM-C04 adds archive/reference-consumer proof against a named
broker/client cohort. Callback
tuple, owner message contract, metadata keys, result status, error class,
operation/default/limit changes require compatibility review; a newer draft
cannot silently change behavior.
