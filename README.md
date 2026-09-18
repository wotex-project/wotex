# WoTEx

**W3C Web of Things for Elixir: values, runtime, directory, bindings, protocol
adapters, conformance and a consumer laboratory, in one repository.**

[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

This repository holds the WoTEx package family as independent Mix projects
under `packages/`. It is not an umbrella project: every package has its own
`mix.exs`, lock file, version and Hex package name, and is verified on its
own. Documentation for every package lives under `docs/packages/<name>/`.

All packages are development checkouts with unstable public APIs. Nothing is
published on Hex yet; publication and release readiness are verified
separately per package.

## Packages

| Package | Hex name | What it owns | Depends on |
| --- | --- | --- | --- |
| [`wotex`](packages/wotex) | `wotex` | Thing Description 1.1 and Thing Model 1.1 values, validation, encoding | — |
| [`wotex-runtime`](packages/wotex-runtime) | `wotex_runtime` | ConsumedThing and ExposedThing mechanics, transport and credential behaviours | `wotex` |
| [`wotex-directory`](packages/wotex-directory) | `wotex_directory` | Thing Description Directory mechanics | `wotex` |
| [`wotex-nx`](packages/wotex-nx) | `wotex_nx` | Nx batches from typed observations | `wotex` |
| [`wotex-continuum`](packages/wotex-continuum) | `wotex_continuum` | Continuum manifest, exchange and lifecycle values | `wotex` |
| [`wotex-conformance`](packages/wotex-conformance) | `wotex_conformance` | Conformance runner and vectors for any implementation | — |
| [`wotex-binding-http`](packages/wotex-binding-http) | `wotex_binding_http` | HTTP and Server-Sent Events transport | `wotex`, `wotex_runtime` |
| [`wotex-binding-mqtt`](packages/wotex-binding-mqtt) | `wotex_binding_mqtt` | MQTT Form mapping and transport | `wotex`, `wotex_runtime` |
| [`wotex-bacnet`](packages/wotex-bacnet) | `wotex_bacnet` | BACnet interactions | `wotex`, `wotex_runtime` |
| [`wotex-ble`](packages/wotex-ble) | `wotex_ble` | Bluetooth Low Energy interactions | `wotex`, `wotex_runtime` |
| [`wotex-coap`](packages/wotex-coap) | `wotex_coap` | CoAP, DTLS and OSCORE interactions | `wotex`, `wotex_runtime` |
| [`wotex-matter`](packages/wotex-matter) | `wotex_matter` | Matter interactions with a native controller | `wotex`, `wotex_runtime` |
| [`wotex-modbus`](packages/wotex-modbus) | `wotex_modbus` | Modbus TCP interactions | `wotex`, `wotex_runtime` |
| [`wotex-opcua`](packages/wotex-opcua) | `wotex_opcua` | OPC UA interactions | `wotex`, `wotex_runtime` |
| [`wotex-thread`](packages/wotex-thread) | `wotex_thread` | Thread network inspection and management | `wotex`, `wotex_runtime` |
| [`wotex-lab`](packages/wotex-lab) | `wotex_lab` | Consumer laboratory: scenarios, evidence, workbench and Nerves hosts | eight packages above |

No package depends on a protocol adapter. Consumers outside this repository
(products, third-party adapters) depend on published packages, or on one
commit of this repository with `sparse: "packages/<name>"` until publication.

## Governance

[Contributing](CONTRIBUTING.md) · [Governance](GOVERNANCE.md) ·
[Security](SECURITY.md) · [Code of Conduct](CODE_OF_CONDUCT.md) ·
[License](LICENSE)
