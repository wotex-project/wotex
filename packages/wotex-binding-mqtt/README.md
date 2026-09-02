# Wotex MQTT Binding

`wotex_binding_mqtt` maps W3C Web of Things MQTT Forms to immutable MQTT
commands and adapts them to `Wotex.Runtime.Transport`. It does not provide an
MQTT client, connection manager, OTP Application, or supervision tree. The
consumer host owns those concerns through a small client port.

The implementation follows a deliberately bounded subset of the W3C Editor's
Draft observed on 2026-09-02. That document remains work in progress. Using
this library is not a declaration that a Thing Description, Consumer, or client
conforms to a W3C specification.

## Installation

Add the package to `mix.exs`:

```elixir
def deps do
  [
    {:wotex_binding_mqtt, "~> 0.1.0"}
  ]
end
```

Normal package resolution uses `wotex ~> 0.1.0` and
`wotex_runtime ~> 0.1.0`. The development-only `WOTEX_PATH_DEPS=1` switch
selects adjacent source checkouts for both dependencies.

## Runtime setup

Implement `Wotex.Binding.MQTT.Client` around a client whose connection is
already owned by the consumer host. Then configure the Runtime transport:

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

The client port receives an immutable command and an ephemeral
`Wotex.Runtime.ExecutionContext` as separate arguments. It must not retain the
execution context or place credentials in its configuration or handles.

## Form mapping

Only `mqtt` and `mqtts` broker href values are accepted. A broker href may have
an explicit port and a trailing slash, but no user information, topic path,
query, or fragment. Targets use the dedicated MQTT vocabulary terms:

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

The supported default mappings are:

| WoT operation | MQTT Control Packet |
| --- | --- |
| `readproperty`, `observeproperty`, `subscribeevent` | `subscribe` |
| `writeproperty`, `invokeaction` | `publish` |
| `unobserveproperty`, `unsubscribeevent` | `unsubscribe` |

An explicit `mqv:controlPacket` must match that mapping. `mqv:qos` accepts the
integers or strings `0`, `1`, and `2`. `mqv:topic` is a Topic Name and rejects
wildcards; `mqv:filter` accepts MQTT Topic Filter wildcards and may be a string
or non-empty list.

A `readproperty` request requires `mqv:retain` to be true. The client port is
called with a finite timeout and must return a retained delivery. Observations
and Event subscriptions use a delivery closure that bounds and decodes JSON,
then sends `{:wotex_transport, payload}` to the Runtime receiver. The closure
does not capture the execution context.

## Project contracts

- [MQTT values and client port](docs/specs/mqtt-values-and-client-port.md)
- [Runtime transport](docs/specs/runtime-transport.md)
- [Dated W3C MQTT draft provenance](docs/provenance/mqtt-binding-draft-2026-07-01.md)
- [OASIS MQTT sources](docs/provenance/mqtt-primary-sources.md)
- [WoT Binding Registry status](docs/provenance/wot-binding-registry-2025-11-04.md)

## Development

```console
WOTEX_PATH_DEPS=1 mix check
```

The check formats, compiles with warnings as errors, runs tests with at least
90 percent coverage, builds documentation, scans the library boundary, builds a
Hex archive with the path switch explicitly unset, and validates the archive.

Licensed under Apache-2.0.
