# WoTEx

**W3C Web of Things building blocks for Elixir.**

[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

WoTEx represents W3C Web of Things descriptions as Elixir values and connects
their Properties, Actions and Events to protocol-specific code. The repository
contains sixteen independent Mix projects: the value model, a runtime,
bindings, protocol packages, conformance tools and a consumer laboratory.

This is a development monorepo, not an umbrella application. Each package has
its own version, dependencies, tests and release archive. No package from this
repository has been published to Hex yet. Until that changes, use a pinned
repository commit as described under [Using WoTEx](#using-wotex).

## From a description to an exchange

A Thing Description says what a Thing exposes and which Forms can reach it.
WoTEx keeps that description separate from the code that performs an exchange:

1. `wotex` parses and validates the Thing Description.
2. `wotex_runtime` selects a Form for the requested interaction.
3. A binding or protocol package performs the exchange through a transport
   supplied by the application.

The same application-facing interaction can therefore use HTTP, MQTT, CoAP,
OPC UA, Matter, BACnet, Modbus or Bluetooth Low Energy without putting protocol
details in the Thing Description model. Thread support covers network
inspection and OpenThread SDK management.

## Package family

### [`wotex`](packages/wotex/README.md)

Parses, validates and encodes Thing Descriptions 1.1 and Thing Models 1.1.

### [`wotex-runtime`](packages/wotex-runtime/README.md)

Provides ConsumedThing and ExposedThing runtimes, Form selection, transports
and credentials.

### [`wotex-directory`](packages/wotex-directory/README.md)

Implements Thing Description Directory mechanics over consumer-owned storage.

### [`wotex-continuum`](packages/wotex-continuum/README.md)

Defines exchange and lifecycle values shared between edge and cloud systems.

### [`wotex-nx`](packages/wotex-nx/README.md)

Builds deterministic Nx batches from typed observations.

### [`wotex-binding-http`](packages/wotex-binding-http/README.md)

Maps Forms to HTTP exchanges and Server-Sent Events.

### [`wotex-binding-mqtt`](packages/wotex-binding-mqtt/README.md)

Maps Forms to MQTT topics, messages and transport operations.

### [`wotex-bacnet`](packages/wotex-bacnet/README.md)

Connects Web of Things interactions to BACnet.

### [`wotex-ble`](packages/wotex-ble/README.md)

Connects Web of Things interactions to Bluetooth Low Energy through BlueZ.

### [`wotex-coap`](packages/wotex-coap/README.md)

Connects Web of Things interactions to CoAP, with DTLS and OSCORE support.

### [`wotex-matter`](packages/wotex-matter/README.md)

Connects Web of Things interactions to Matter through connectedhomeip.

### [`wotex-modbus`](packages/wotex-modbus/README.md)

Connects Web of Things interactions to Modbus TCP.

### [`wotex-opcua`](packages/wotex-opcua/README.md)

Connects Web of Things interactions to OPC UA through open62541.

### [`wotex-thread`](packages/wotex-thread/README.md)

Inspects Thread networks and manages the OpenThread SDK.

### [`wotex-conformance`](packages/wotex-conformance/README.md)

Runs conformance vectors and produces evidence reports for Web of Things
libraries.

### [`wotex-lab`](packages/wotex-lab/README.md)

Hosts scenarios, evidence records, Workbench, Nerves hosts and Nx experiments.

The [package graph](docs/architecture/package-graph.md) records dependencies
and ownership boundaries. Consumers install only the packages they use.

## Ownership stays with the application

Loading a WoTEx package starts no process, reads no application environment and
performs no I/O. Packages return child specifications when they need supervised
work. The application remains responsible for Thing state, identifiers,
credentials, policy, persistence, supervision and retries.

Protocol packages accept transports and credential providers explicitly.
Failures use structured errors with stable codes, and documented limits bound
untrusted input and long-lived work. Native stacks such as open62541, BlueZ and
connectedhomeip run outside the BEAM in owned operating-system processes.

## Using WoTEx

Set up the repository and run one package's tests from the root:

```bash
git clone https://github.com/wotex-project/wotex.git
cd wotex
mix setup
mix pkg wotex test
```

Before the packages are published, an application can depend on a package at a
specific repository commit:

```elixir
@wotex_ref "<commit>"

def deps do
  [
    {:wotex,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex",
     override: true}
  ]
end
```

Pin every WoTEx dependency to the same commit. The
[consumer guide](docs/guides/consumer.md) shows how to add packages with
transitive WoTEx dependencies, use a local checkout and sync the concise
`usage-rules.md` for each installed package's completed specification.

All packages are below 1.0, so a minor version may change a public API. Package
READMEs contain package-specific examples and toolchain requirements.

## Specifications and evidence

WoTEx does not treat a package name as a claim of complete protocol support.
Each specification names its standards revision, acceptance cases and
executable evidence. Its catalogue records whether the implementation is
planned, partial or complete. Native and interoperability evidence uses pinned
source identities and records the limits of each result; no package claims
certification.

Start with the [documentation index](docs/README.md) for specifications, plans,
provenance and guides. The package catalogue is also available as a single
generated [family catalogue](docs/catalogue.yaml).

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers repository setup, package-scoped
commands and validation. Changes to behavior begin with the owning package's
specification and finish with evidence for the affected boundary.

[Governance](GOVERNANCE.md) · [Security](SECURITY.md) ·
[Code of Conduct](CODE_OF_CONDUCT.md) · [License](LICENSE)
