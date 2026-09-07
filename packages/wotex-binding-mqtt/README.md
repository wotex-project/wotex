# Wotex MQTT Binding

**Process-free W3C WoT MQTT Form mapping for Elixir consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_binding_mqtt.svg)](https://hex.pm/packages/wotex_binding_mqtt)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_binding_mqtt)
[![CI](https://github.com/wotex-project/wotex-binding-mqtt/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-binding-mqtt/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-binding-mqtt/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-binding-mqtt)
[![License](https://img.shields.io/github/license/wotex-project/wotex-binding-mqtt.svg)](LICENSE)

[Installation](#installation) · [Quick Start](#quick-start) ·
[Form Mapping](#form-mapping) · [Client Port](#client-port) ·
[Errors and Delivery](#errors-and-delivery) · [Boundary](#boundary) ·
[Development](#development)

---

`wotex_binding_mqtt` maps W3C Web of Things MQTT Forms to immutable commands
and implements `Wotex.Runtime.Transport`. It deliberately does not choose an
MQTT client. A consumer adapts its existing connection owner through
`Wotex.Binding.MQTT.Client`, preserving supervision, reconnect, session, TLS,
and credential authority in one place.

## Installation

```elixir
def deps do
  [{:wotex_binding_mqtt, "~> 0.1.0"}]
end
```

Published builds resolve `wotex ~> 0.1` and `wotex_runtime ~> 0.1`. For
coordinated source development, `WOTEX_PATH_DEPS=1 mix deps.get` selects the
sibling checkouts explicitly; no adjacent path is discovered implicitly.

## Quick Start

```elixir
alias Wotex.Binding.MQTT
alias Wotex.Binding.MQTT.{Transport, TransportConfig}

{:ok, mqtt_config} =
  TransportConfig.new(ConsumerMQTTClient, client_reference,
    read_timeout: 2_000,
    max_payload_bytes: 262_144
  )

profiles = [MQTT.profile()]
transports = %{mqtt: {Transport, mqtt_config}}
```

Loading the dependency starts nothing. The consumer starts and supervises its
MQTT connection, then gives the transport an opaque reference in
`client_config`.

## Form Mapping

Only `mqtt` and `mqtts` broker hrefs are accepted. Broker hrefs may contain a
port and trailing slash, but never user information, a topic path, query, or
fragment. Targets use the MQTT vocabulary terms:

```json
{
  "href": "mqtts://broker.example:8883",
  "op": ["readproperty", "observeproperty"],
  "contentType": "application/json",
  "mqv:retain": true,
  "mqv:qos": "1",
  "mqv:filter": "things/properties/temperature"
}
```

| WoT operation | MQTT Control Packet | Target term |
|---------------|---------------------|-------------|
| `readproperty`, `observeproperty`, `subscribeevent` | `subscribe` | `mqv:filter` |
| `writeproperty`, `invokeaction` | `publish` | `mqv:topic` |
| `unobserveproperty`, `unsubscribeevent` | `unsubscribe` | `mqv:filter` |

An explicit `mqv:controlPacket` must agree with this table. QoS accepts integer
or string values `0`, `1`, and `2`. Topic Names reject wildcards; Topic Filters
support valid `+`, `#`, and MQTT 5 shared-subscription syntax.

## Client Port

Implement four callbacks around the consumer's chosen client:

| Callback | Expected result |
|----------|-----------------|
| `publish/3` | `:ok` after accepting the immutable publish command. |
| `read/4` | One retained delivery within the supplied finite timeout. |
| `subscribe/4` | `{:ok, handle}`; deliveries are sent to the owner process. |
| `unsubscribe/4` | `:ok` after releasing the opaque subscription handle. |

`subscribe/4` receives the subscription owner pid, not a callback. The client
sends raw deliveries and connection statuses to that process and decodes
nothing on its connection:

```elixir
defmodule ConsumerMQTTClient do
  @behaviour Wotex.Binding.MQTT.Client

  alias Wotex.Binding.MQTT.{Command, Delivery}

  @impl true
  def subscribe(command, owner, _execution_context, config) do
    deliver = fn topic, bytes, qos, retained? ->
      case Delivery.new(bytes, topic: topic, qos: qos, retain: retained?) do
        {:ok, delivery} -> send(owner, {:wotex_transport_frame, delivery})
        {:error, _rejected} -> :ok
      end
    end

    # Returns {:ok, handle}; the handle comes back to unsubscribe/4.
    ConsumerConnection.subscribe(config.connection, Command.filters(command), deliver)
  end

  # After a reconnect the client tells the owner what happened to the Session:
  # send(owner, {:wotex_transport_status, :reconnected})   # Session resumed
  # send(owner, {:wotex_transport_status, :session_lost})  # Clean Start or expiry
end
```

A client MUST send `:session_lost` when it reconnects with Clean Start or after
session expiry, because the broker then holds no subscription for the owner;
`:reconnected` means the Session and its subscription survived. The owner
reports both to its receiver and stops on `:session_lost`, leaving restart and
resubscription to the consumer's supervisor.

Commands contain broker, packet, topic/filter, QoS, retain, content type, the
payload byte limit, and a bounded payload. The `Wotex.Runtime.ExecutionContext`
is a separate ephemeral argument: adapters must not retain it, place credentials
in configuration, or embed credentials in handles.

## Errors and Delivery

`Wotex.Binding.MQTT.Error` identifies the failing stage (`:broker`, `:command`,
`:topic`, `:codec`, `:mapping`, `:configuration`, or `:client`) and a retry
`class` (`:timeout`, `:unavailable`, `:protocol`, or `:permanent`) without
leaking arbitrary client exceptions or return terms. Invalid callback results,
raises, throws, oversized payloads, malformed JSON, unexpected topic names, and
packet/operation mismatches all fail as structured, classified transport errors.

`readproperty` requires `mqv:retain: true` and is bounded by
`min(read_timeout, remaining request deadline)`; an exhausted deadline fails as
`:deadline_exceeded` without calling the client. A publish acknowledgement is an
`:accepted` result, a retained read an `:ok` result, with control packet, QoS,
retain flag, and Topic Name in the metadata.

The subscription owner decodes each frame with
`c:Wotex.Runtime.Transport.decode_frame/3`: a Topic Name outside the Form's
Topic Filters is ignored, an oversized or malformed payload becomes a classified
error, and a valid delivery reaches the Runtime receiver as

```elixir
{:wotex_runtime, subscription_id,
 {:ok, payload, %{topic: topic, qos: qos, retained: retained?, operation: operation}}}
```

## Boundary

The 0.1 series implements the bounded mapping recorded in the
[MQTT contract](docs/specs/WBM.01-values-and-client-port.md) and
[Runtime contract](docs/specs/WBM.03-runtime-transport.md). Draft provenance is dated
in the [dated draft provenance](docs/provenance/mqtt-binding-draft-2026-07-01.md).
This is not a W3C certification claim.

The package defines no application callback, supervision tree, connection
manager, MQTT client, database, filesystem authority, credential store, or
global configuration. Connection sharing, reconnect policy, durable sessions,
back-pressure, TLS material, and broker observability remain consumer concerns.

## Development

```console
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check
```

`mix check` runs warnings-as-errors compilation, formatting, strict Credo, 95%
coverage, dependency audits, Doctor, Dialyzer, HexDocs, boundary checks, Hex
archive construction, out-of-tree archive compilation, and the application-free
assertion.

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), and
[SECURITY.md](SECURITY.md). Licensed under Apache-2.0; see [LICENSE](LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex-binding-mqtt/blob/main/NOTICE).
