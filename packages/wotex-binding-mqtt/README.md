# Wotex MQTT Binding

**Process-free W3C WoT MQTT Form mapping for Elixir consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_binding_mqtt.svg)](https://hex.pm/packages/wotex_binding_mqtt)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_binding_mqtt)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_binding_mqtt.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-mqtt/LICENSE)

[Installation](#installation) · [Quick Start](#quick-start) ·
[Form Mapping](#form-mapping) · [Client Port](#client-port) ·
[Errors and Delivery](#errors-and-delivery) · [Boundary](#boundary) ·
[Development](#development)

---

This is a development checkout with no published release. The reviewed 0.1 API
is a stable candidate; no package availability or W3C certification is implied.

`wotex_binding_mqtt` maps W3C Web of Things MQTT Forms to immutable commands
and implements `Wotex.Runtime.Transport`. It deliberately does not choose an
MQTT client. A consumer adapts its existing connection owner through
`Wotex.Binding.MQTT.Client`, preserving supervision, reconnect, session, TLS,
and credential authority in one place.

## Installation

Wotex MQTT Binding 0.1 requires Elixir 1.18 or later. No version is published
on Hex yet. Once one is, depend on it as usual; Hex resolves `wotex` and
`wotex_runtime` from the package's own requirements:

```elixir
def deps do
  [{:wotex_binding_mqtt, "~> 0.1"}]
end
```

Until then, depend on one commit of the
[WoTEx repository](https://github.com/wotex-project/wotex) and select each
package directory with `sparse:`. The binding's `mix.exs` declares Hex
requirements for `wotex ~> 0.1.0` and `wotex_runtime ~> 0.1.0`, so declare all
three packages at the same `ref` with `override: true`, as the
[consumer guide](https://github.com/wotex-project/wotex/blob/main/docs/guides/consumer.md)
describes:

```elixir
@wotex_ref "<commit>"

def deps do
  [
    {:wotex,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex",
     override: true},
    {:wotex_runtime,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-runtime",
     override: true},
    {:wotex_binding_mqtt,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-binding-mqtt",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_runtime, path: "../wotex/packages/wotex-runtime", override: true},
{:wotex_binding_mqtt, path: "../wotex/packages/wotex-binding-mqtt", override: true}
```

Path dependencies prove nothing about a released artifact; no adjacent path is
discovered implicitly.

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
[MQTT contract](../../docs/packages/wotex-binding-mqtt/specs/WBM.01-values-and-client-port.md) and
[Runtime contract](../../docs/packages/wotex-binding-mqtt/specs/WBM.03-runtime-transport.md). Draft provenance is dated
in the [dated draft provenance](../../docs/packages/wotex-binding-mqtt/provenance/mqtt-binding-draft-2026-07-01.md).
The [client lifecycle proof](../../docs/packages/wotex-binding-mqtt/specs/WBM-C02-client-lifecycle.md) records the
consumer-owned timeout, handle, close-failure, concurrency, and restart boundary.
The [limits and security proof](../../docs/packages/wotex-binding-mqtt/specs/WBM-C03-limits-security.md) records
exact value thresholds, filter cardinality, receiver overload, redaction, and
the trusted-client authority boundary.
The [exact archive consumer](../../docs/packages/wotex-binding-mqtt/reference-consumer-inventory.md) compiles one
core/Runtime/MQTT archive cohort in an isolated OS-temp project and exercises
PUBLISH, retained read, paired subscription, limits, and redacted failures.
This is not a W3C certification claim.

The package defines no application callback, supervision tree, connection
manager, MQTT client, database, filesystem authority, credential store, or
global configuration. Connection sharing, reconnect policy, durable sessions,
back-pressure, TLS material, and broker observability remain consumer concerns.

## Development

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```console
mix pkg wotex-binding-mqtt test test/wotex/binding/mqtt/mapping_test.exs  # one test file
mix check.fast --package wotex-binding-mqtt                               # compile, format, Credo, tests
mix pkg wotex-binding-mqtt check --no-retry                               # full gate
```

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-binding-mqtt`. It compiles with warnings as errors, checks the
lock and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
Credo, Doctor, `mix docs --warnings-as-errors` (in the `docs` environment),
tests with the coverage floor (`mix coveralls`), Dialyzer, the public
boundary scan (`elixir bin/check_boundary.exs`) and `git diff --check`. It then
runs the exact-archive check
(`mix run --no-start bin/check_archive.exs`), which builds the `wotex`,
`wotex_runtime` and `wotex_binding_mqtt` archives from `packages/` without
path dependencies and runs an isolated reference consumer against them, and the
application-free check (`mix run --no-start bin/check_application_free.exs`).

This package has no native build, software profile, interop or container lane;
no test needs a broker. These commands do not invoke a release task, publish a
package, or mutate a remote.

See [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](https://github.com/wotex-project/wotex/blob/main/CONTRIBUTING.md), and
[SECURITY.md](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex-binding-mqtt/security.md). Licensed under Apache-2.0; see
[LICENSE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-mqtt/LICENSE) and
[NOTICE](https://github.com/wotex-project/wotex/blob/main/packages/wotex-binding-mqtt/NOTICE).
