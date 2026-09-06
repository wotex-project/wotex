# WBM.01: MQTT values and client port

Specification `WBM.01@1.0.0`; package baseline `wotex_binding_mqtt 0.1.0`.
Requires `wotex:WTX.02`, `wotex_runtime:WRT.01`. The existing document path
is retained for link compatibility. See
the repository completion plan at `docs/plans/wotex-binding-mqtt-completion.md` for gates and remaining claims.

## Scope

This package owns immutable broker, command, delivery, topic-validation, QoS,
and JSON-boundary values. It owns no MQTT session, socket, client process,
reconnection policy, supervision, or credential lifecycle.

## Broker

`Wotex.Binding.MQTT.Broker` accepts only an absolute `mqtt` or `mqtts` href with
a host, optional valid port, and optional trailing slash. It rejects user
information, non-root paths, queries, and fragments. The resulting value is
credential-free.

The Form must carry the target separately:

- `mqv:topic` identifies one MQTT Topic Name for a PUBLISH command.
- `mqv:filter` identifies one or more MQTT Topic Filters for SUBSCRIBE and
  UNSUBSCRIBE commands.

A Form containing both terms is rejected. A required term cannot be inferred
from the href.

## Commands and deliveries

`Wotex.Binding.MQTT.Command` is the complete, credential-free instruction sent
to a client port. PUBLISH values contain JSON bytes, a Topic Name, QoS, and
retain flag. SUBSCRIBE values contain Topic Filters, QoS, and the Form's retain
semantics. UNSUBSCRIBE values contain Topic Filters.

`Wotex.Binding.MQTT.Delivery` carries encoded bytes, the actual Topic Name, the
delivery QoS, and retained-message semantics. Inspection omits payload bytes.
Topic matching is checked before JSON decoding.

Both values are immutable. Neither value accepts credentials, an execution
context, or a mutable connection owner.

## QoS and topics

QoS input accepts `0`, `1`, and `2` as integers or strings and normalizes them
to integers. Other values are rejected before a client callback.

Topic Names and Topic Filters must be non-empty valid UTF-8 strings of at most
65,535 bytes and cannot contain a null character. Topic Names reject `+` and
`#`. Filters accept `+` only as a complete topic level and `#` only as the final
complete level. MQTT 5 shared filters use `$share/{group}/{filter}` with a
non-empty group.

## JSON boundary

The binding publishes and receives `application/json`. Parameters such as a
charset are accepted and normalized. Encoded and received payloads are checked
against the configured positive byte limit. Codec errors do not copy a payload
or external codec term into the returned error.

## Client port

The consumer implements `Wotex.Binding.MQTT.Client`:

```elixir
publish(command, execution_context, client_config)
read(command, timeout, execution_context, client_config)
subscribe(command, delivery_callback, execution_context, client_config)
unsubscribe(handle, command, execution_context, client_config)
```

The client configuration identifies caller-owned state and must be
credential-free. Credentials are available only from the execution context
during the immediate callback. The client must not retain that context or copy
credential material into a subscription handle, error, command, or delivery.

The finite `read/4` timeout bounds Property reads even when the Runtime request
has no deadline. The client also receives the execution context and remains
responsible for observing an earlier consumer-supplied deadline.

## Public value and failure matrix

Modules below are under `Wotex.Binding.MQTT`. Constructor validation owns shape,
not broker admission or authorization to operate on a Thing.

| Surface | Contract | Effect boundary |
|---|---|---|
| `Broker.new/1` | Broker-only mqtt/mqtts URI | No DNS, TLS or authentication |
| `Command.publish/5` | Broker, operation, Topic Name, input, options | JSON/packet value, not a send |
| `Command.subscribe/4`, `unsubscribe/4` | Broker, operation, filter(s), options | No broker session |
| `Delivery` | Topic, QoS, retained flag, bytes | Protocol delivery, not canonical Event/Property |
| `QoS.normalize/1` | Integer/string 0, 1, 2 | No negotiated-QoS guarantee |
| `Topic` validators/matcher | Named topic/filter grammar and matching | No ACL lookup |
| `JSON` codec functions | JSON and positive byte limit | Stable error excludes payload/codec reason |
| `TransportConfig.new/3` | Explicit client/configuration and limits | Callback validation, not connection startup |

Module docs/typespecs own exact constructor/accessor signatures. Invalid
protocol values must fail before the client callback, not be coerced into a
different packet. Tests must separately prove each error code/phase and that
no callback ran on rejected input.

## Bounds, allocation and security

Defaults are `read_timeout: 5_000` ms and `max_payload_bytes: 1_048_576`;
overrides are positive integers. Topic/filter strings have a 65,535-byte limit.
The payload bound applies to accepted encoded/received bytes, not allocations
inside encoding or the client/broker. Filter-list cardinality, JSON nesting and
sustained delivery require WBM-C03 evidence before a whole-process bound.

Client code is trusted. TLS, broker identity, ACLs, authentication, credential
refresh, session limits and negotiated protocol version belong to the consumer.
Inspect redaction is not memory erasure. Test nested client errors, exception
messages, invalid callback tuples and credential-free closure captures. A
syntactically valid Delivery does not establish authenticated source authority.

## Standards, evidence and compatibility

OASIS MQTT 5.0 (2019-03-07) and 3.1.1 (2014-10-29) are the dated value baseline
in `docs/provenance/mqtt-primary-sources.md`. This package implements no wire
parser, QoS handshake, session expiry or acknowledgement/retransmission state.
MQTT 5 shared-subscription grammar is not MQTT 3.1.1 interoperability proof;
the client must admit negotiated broker capabilities.

`broker_test.exs`, `command_test.exs`, `delivery_test.exs`, `qos_test.exs`,
`topic_test.exs`, `json_test.exs`, `transport_config_test.exs` under
`test/wotex/binding/mqtt/` are current value evidence. Changed fields, defaults,
limits or errors require versioned compatibility vectors. Accepting QoS `2`
does not claim exactly-once delivery or physical execution.
