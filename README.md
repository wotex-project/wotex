# WoTEx

**W3C Web of Things for Elixir: one Thing Description model and runtime across
HTTP, MQTT, CoAP, OPC UA, Matter, BACnet, Modbus, BLE and Thread.**

[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

The [W3C Web of Things](https://www.w3.org/WoT/) (WoT) describes a device or
service as a Thing. Its Thing Description lists the Thing's Properties, Actions
and Events, and each Form in it states which protocol operation reaches an
interaction. WoTEx implements this model in Elixir as a family of packages:
Thing Description values, a runtime that turns them into interactions, protocol
packages that carry those interactions, and tools that produce evidence of
their behavior.

## One model across protocols

Factories use OPC UA and Modbus, buildings use BACnet, homes use Matter and
Thread, and devices and services exchange data over CoAP, MQTT and HTTP. A
WoTEx application reads a Property, invokes an Action or observes an Event
through the Thing Description. The runtime selects a compatible Form and hands
the exchange to the transport the application supplies for that protocol.
Interaction code does not depend on the protocol, and support for another
protocol is another package behind the same runtime.

## How the packages are built

- The consumer owns the system. Loading a package starts no process, reads
  no application environment and performs no I/O. Long-lived work is returned
  as child specifications for the consumer's supervision tree. Thing state,
  identifiers, credentials, persistence, policy and retries stay with the
  consumer.
- Limits and failures are explicit. Each package admits input within
  documented limits and reports failure as a structured error with a stable
  code. Transports and credential providers are passed in by the consumer,
  never discovered from configuration or a registry.
- Native stacks run outside the BEAM. Where a protocol needs a native
  stack (libcoap for OSCORE, open62541 for OPC UA, connectedhomeip for Matter,
  BlueZ for Bluetooth Low Energy, the OpenThread SDK for Thread), it runs in a
  separate operating-system process that one BEAM process owns through a
  bounded framed protocol.
- Claims are tied to evidence. A standards claim names the exact revision
  it follows and the executable evidence behind it. Specifications are
  versioned contracts, and each package's catalogue records how much of every
  specification is implemented. No package claims certification.
- Packages are independent. Each package has its own version, lock file,
  Hex name and gate, and a consumer depends only on the packages it uses. The
  packages share one repository so that a change is verified together with
  every package it reaches.

## Packages

| Area | Package | Provides |
| --- | --- | --- |
| Core | [`wotex`](packages/wotex) | Thing Description 1.1 and Thing Model 1.1 values: parsing, validation and encoding |
| Runtime | [`wotex-runtime`](packages/wotex-runtime) | ConsumedThing and ExposedThing, Form selection, transport and credential behaviours |
| Services | [`wotex-directory`](packages/wotex-directory) | Thing Description Directory mechanics over consumer-supplied storage |
| | [`wotex-continuum`](packages/wotex-continuum) | Exchange values for observations, Action intent, results and lifecycle between edge devices and cloud services |
| | [`wotex-nx`](packages/wotex-nx) | Typed observations as deterministic Nx batches |
| Bindings | [`wotex-binding-http`](packages/wotex-binding-http) | HTTP and Server-Sent Events transport |
| | [`wotex-binding-mqtt`](packages/wotex-binding-mqtt) | MQTT Form mapping and transport |
| Protocols | [`wotex-bacnet`](packages/wotex-bacnet) | BACnet |
| | [`wotex-ble`](packages/wotex-ble) | Bluetooth Low Energy through BlueZ |
| | [`wotex-coap`](packages/wotex-coap) | CoAP with DTLS and OSCORE |
| | [`wotex-matter`](packages/wotex-matter) | Matter through connectedhomeip |
| | [`wotex-modbus`](packages/wotex-modbus) | Modbus TCP |
| | [`wotex-opcua`](packages/wotex-opcua) | OPC UA through open62541 |
| | [`wotex-thread`](packages/wotex-thread) | Thread inspection and OpenThread SDK management |
| Evidence | [`wotex-conformance`](packages/wotex-conformance) | Conformance runner, vectors and evidence reports for any WoT library |
| | [`wotex-lab`](packages/wotex-lab) | Laboratory that composes the packages into scenarios, evidence records, a Workbench, Nerves hosts and Nx experiments |

The [package graph](docs/architecture/package-graph.md) shows how the packages
depend on each other and where the boundaries between them lie.

## Versions

Each package is versioned and released on its own. All packages are below 1.0,
so a minor version may change a public API. A package's specifications under
`docs/packages/<name>/specs/` define its behavior, and its catalogue records the
implementation status of each specification.

## Using WoTEx

Depend on the packages you use. Hex resolves each package's WoTEx
dependencies, so an application that talks to Things over HTTP needs only the
binding:

```elixir
def deps do
  [
    {:wotex_binding_http, "~> 0.1"}
  ]
end
```

Each package README shows a usage example, and the
[consumer guide](docs/guides/consumer.md) describes what a consumer owns.

## Documentation and contributing

The [documentation index](docs/README.md) lists every package's
specifications, plans and provenance, the family architecture and the guides.
[Contributing](CONTRIBUTING.md) explains the repository layout, setup and
validation.

[Governance](GOVERNANCE.md) · [Security](SECURITY.md) ·
[Code of Conduct](CODE_OF_CONDUCT.md) · [License](LICENSE)
