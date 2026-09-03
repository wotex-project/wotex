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
| `subscribe/4` | `{:ok, handle}` and delivery through the supplied closure. |
| `unsubscribe/4` | `:ok` after releasing the opaque subscription handle. |

Commands contain broker, packet, topic/filter, QoS, retain, content type, and a
bounded payload. The `Wotex.Runtime.ExecutionContext` is a separate ephemeral
argument: adapters must not retain it, place credentials in configuration, or
embed credentials in handles.

## Errors and Delivery

`Wotex.Binding.MQTT.Error` identifies the failing stage (`:broker`, `:mapping`,
`:payload`, `:topic`, `:client`, or `:delivery`) without leaking arbitrary
client exceptions or return terms. Invalid callback results, raises, throws,
oversized payloads, malformed JSON, unexpected topic names, and packet/operation
mismatches all fail as structured transport errors.

`readproperty` requires `mqv:retain: true`. Observation and Event deliveries
are size-checked and JSON-decoded before the closure sends
`{:wotex_transport, payload}` to the Runtime receiver. The closure captures the
receiver, filters, and byte limit only—not the execution context.

## Boundary

The 0.1 series implements the bounded mapping recorded in the
[MQTT contract](docs/specs/mqtt-values-and-client-port.md) and
[Runtime contract](docs/specs/runtime-transport.md). Draft provenance is dated
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
