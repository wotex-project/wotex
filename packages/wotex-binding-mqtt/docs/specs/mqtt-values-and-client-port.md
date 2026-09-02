# MQTT values and client port

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
