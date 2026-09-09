# Wotex Modbus

**Consumer-neutral Modbus interactions for W3C Web of Things consumers.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_modbus.svg)](https://hex.pm/packages/wotex_modbus)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_modbus)
[![CI](https://github.com/wotex-project/wotex-modbus/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-modbus/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-modbus/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-modbus)
[![License](https://img.shields.io/hexpm/l/wotex_modbus.svg)](https://github.com/wotex-project/wotex-modbus/blob/main/LICENSE)

[Installation](#installation) ·
[Ownership](#ownership) ·
[Development](#development) ·
[Implemented profile](#implemented-profile) ·
[Quick start](#quick-start) ·
[Software contract](#software-implementation-contract)

---

This is a development checkout. The public API remains unstable; software
interoperability does not establish certification or a published release.

## Installation

This development checkout is prepared as the `wotex_modbus` Hex package but
does not assert that a release has been published. A sibling-checkout consumer
can select it explicitly:

```elixir
def deps do
  [{:wotex_modbus, path: "../wotex-modbus"}]
end
```

Set `WOTEX_PATH_DEPS=1` while developing this package itself so its Wotex core
and Runtime dependencies resolve from sibling checkouts. Published consumers
should replace the path with the constraint of an available Hex release.

## Ownership

Values, validation and Form mapping belong here. The consumer owns credentials,
policy, supervision and the interpretation of protocol acknowledgements.
Loading the package does not start a transport. No simulator is selected implicitly.

Each connection is linked to its caller and serializes requests over one
numeric Internet Protocol endpoint. The library validates Modbus Application
Protocol headers, transaction correlation, Unit Identifiers, function-specific
limits, and response shapes. It does not silently retry writes; a transport
failure can therefore leave the physical effect unknown to the caller.

## Development

Use Elixir 1.18 or newer and an appropriate OTP release. To use local Wotex core
and Runtime checkouts, run `WOTEX_PATH_DEPS=1 mix deps.get` then
`WOTEX_PATH_DEPS=1 mix check`. Normal dependency resolution uses Hex versions.
Optional interoperability suites run only on explicit invocation and must fail
when their configured peer is missing or returns no response.

See [delivery contract](docs/plans/wotex-modbus-completion.md).

## Implemented profile

Classic Modbus TCP functions 1, 2, 3, 4, 5, 6, 15 and 16; strict MBAP/response
validation; integer/float register conversion; explicit socket ownership;
WoT Forms and Runtime requests; neutral compatibility callbacks.

`Wotex.Modbus.profile/0` supplies the native TCP Runtime profile. Admission is
bounded to 64 requests per connection, with one active exchange and a deadline
that includes queue time. An unsent rejected request has no write effect;
a transmitted write with an uncertain outcome reports `effect: :unknown` and
cannot be classified as retryable.

## Quick start

```elixir
{:ok, session} = Wotex.Modbus.connect(host: "127.0.0.1", port: 1502, unit_id: 1)
try do
  Wotex.Modbus.read_holding_registers(session, 0, 2)
after
  Wotex.Modbus.disconnect(session)
end
```

No RTU/serial, Modbus Security, built-in polling or physical certification is
claimed. See [protocol contract](docs/specs/WMB.01-protocol.md),
[Form profile](docs/specs/WMB.02-form-profile.md) and
[independent interoperability](test/interop/README.md).

## Software implementation contract

The [ordered implementation sequence](docs/plans/software-implementation.md)
and [specification index](docs/specs/WMB-index.md) define the software profile's
behavior, limits, failure transitions, acceptance scenarios and concrete fixtures.
Executable tests cover the contract corpus, real Runtime interactions, strict
stream correlation, bounded admission, and owner cleanup. The software fixture
builds a pinned libmodbus peer and records commands, hashes, failures, cleanup,
and the active toolchain. It requires Docker and runs once per selected toolchain:

```sh
mix wotex.software.build --workspace /absolute/disposable/workspace
WOTEX_PATH_DEPS=1 mix wotex.software.run --workspace /absolute/disposable/workspace
```

Required software peers are separate from physical-device tests. A specification
or catalogue status alone is not execution evidence.

The [standalone client contract](docs/specs/WMB.11-standalone-client-and-preservation.md)
defines native workflows and feature-preservation obligations. Its concrete
fixture corpus contains specified cases; execution results remain in provenance.

The [specification catalogue](docs/specs/catalogue.yaml) distinguishes implemented
profiles from planned contracts. The [Wotex integration contract](docs/specs/WMB.12-wotex-integration.md)
defines explicit Runtime profiles, route/value/error boundaries and real
ConsumedThing acceptance tests. Re-run the checked-in software harness for the
source revision under review; earlier results do not validate later changes.

## Native build and software orchestration

[WMB.13](docs/specs/WMB.13-native-build-and-software-evidence.md) defines
the explicit `mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS` interfaces. Protocol execution remains
BEAM TCP with a C libmodbus test peer.
The Mix tasks build and verify manifests, run the independent peer and record
actual ExUnit outcomes and cleanup results. Full task acceptance requires fresh
results on both supported toolchains; whole-VM loss during Docker opening is
not yet accepted. Shell compatibility entry points execute the Mix tasks; no
Python build/test orchestrator is required.
