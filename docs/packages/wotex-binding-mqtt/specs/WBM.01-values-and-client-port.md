# WBM.01: MQTT values and client port

Specification `WBM.01@1.1.0`; package baseline `wotex_binding_mqtt 0.1.0`.
Requires `wotex:WTX.02`, `wotex_runtime:WRT.01`. The document is named by its
identifier; the 0.1.0 series is unreleased, so the former path carries no link
debt. See the package [completion plan](../plans/wotex-binding-mqtt-completion.md)
for gates and remaining claims.

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
semantics. UNSUBSCRIBE values contain Topic Filters. Every command also carries
`max_payload_bytes`, the positive JSON byte limit that applies to it, so a
client can abort an oversized Application Message before it reaches a
subscription owner.

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
charset are accepted and normalized. Encoding and decoding run through
`Wotex.JSON`, so the MQTT payload limit supplies `:max_bytes` and the core
defaults of `Wotex.JSON.Limits` bound nesting depth, node count, string size,
and collection size; duplicate object members are rejected. Encoding is the
canonical Wotex form with recursively sorted object keys, and the encoded
payload is checked against the same byte limit. A codec error carries only the
core failure's atom code; payload bytes, member names, and external codec terms
are never copied into the returned error.

## Client port

The consumer implements `Wotex.Binding.MQTT.Client`:

```elixir
publish(command, execution_context, client_config)
read(command, timeout, execution_context, client_config)
subscribe(command, owner, execution_context, client_config)
unsubscribe(handle, command, execution_context, client_config)
```

The client configuration identifies caller-owned state and must be
credential-free. Credentials are available only from the execution context
during the immediate callback. The client must not retain that context or copy
credential material into a subscription handle, error, command, or delivery.
`subscribe/4` receives no closure: the only values that outlive the call are the
immutable command and the owner pid.

The finite `read/4` timeout bounds Property reads. The transport already
narrows it to the remaining Runtime deadline; the client remains responsible
for enforcing the timeout it receives and any earlier consumer policy.

## Subscription owner messages

`owner` is the caller-supervised `Wotex.Runtime.Subscription` process. The
client sends messages to it and decodes no Application Message on its own
connection process.

| Message | Meaning |
|---|---|
| `{:wotex_transport_frame, delivery}` | One received `Wotex.Binding.MQTT.Delivery` for a Topic Filter of the subscribe command |
| `{:wotex_transport_status, :reconnected}` | The connection was re-established and the MQTT Session, including this subscription, was resumed |
| `{:wotex_transport_status, :session_lost}` | The broker holds no subscription for this owner any more |
| `{:wotex_transport_status, :transport_down}` | The connection is gone and the client will not restore it |

A client MUST send `:session_lost` when it reconnects with Clean Start (MQTT 5)
or a clean session (MQTT 3.1.1), or after the Session Expiry Interval elapsed,
because the broker then holds no subscription for the owner. It MUST send
`:reconnected` only when the Session was resumed and the subscription survived.
A client that links its connection process to the owner produces the
`:transport_down` outcome through the exit signal instead. The owner reports
these statuses to its receiver; the consumer's supervisor owns restart and
resubscription.

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
| `Error` values | `code`, `phase`, `class`, message, nonsecret details | Classification states how a failure arose, never that repeating an Action is safe |

Module docs/typespecs own exact constructor/accessor signatures. Invalid
protocol values must fail before the client callback, not be coerced into a
different packet. Tests must separately prove each error code/phase and that
no callback ran on rejected input.

## Bounds, allocation and security

Defaults are `read_timeout: 5_000` ms and `max_payload_bytes: 1_048_576`;
overrides are positive integers. Topic/filter strings have a 65,535-byte limit,
and one command admits at most 256 Topic Filters. JSON defaults bound depth at
64, nodes at 100,000, a string at 262,144 bytes, and one collection at 10,000
members. WBM-C03 exercises each exact threshold and sustained delivery plus the
Runtime receiver-overflow path. The payload and cardinality bounds apply to
admitted values and validation work, not allocations inside encoding, the BEAM,
or the client/broker.

Client code is trusted. TLS, broker identity, ACLs, authentication, credential
refresh, session limits and negotiated protocol version belong to the consumer.
Inspect redaction is not memory erasure. Test nested client errors, exception
messages, invalid callback tuples and that the values a client can retain from
`subscribe/4` hold no credential. A syntactically valid Delivery does not
establish authenticated source authority.

## Standards, evidence and compatibility

OASIS MQTT 5.0 (2019-03-07) and 3.1.1 (2014-10-29) are the dated value baseline
in the [MQTT primary sources](../provenance/mqtt-primary-sources.md). This
package implements no wire parser, QoS handshake, session expiry or
acknowledgement/retransmission state.
MQTT 5 shared-subscription grammar is not MQTT 3.1.1 interoperability proof;
the client must admit negotiated broker capabilities.

`broker_test.exs`, `command_test.exs`, `delivery_test.exs`, `qos_test.exs`,
`topic_test.exs`, `json_test.exs`, `transport_config_test.exs`, and
`limits_security_test.exs` under
`test/wotex/binding/mqtt/` are current value evidence. Changed fields, defaults,
limits or errors require versioned compatibility vectors. Accepting QoS `2`
does not claim exactly-once delivery or physical execution.
