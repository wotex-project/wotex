# WoTEx

**W3C Web of Things for Elixir: values, runtime, directory, bindings, protocol
adapters, conformance and a consumer laboratory, in one repository.**

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

## Layout

```text
packages/<name>/        one Mix project per package: lib, test, priv, bin, mix.exs, README, CHANGELOG
docs/packages/<name>/   that package's specifications, plans, decisions and provenance
docs/architecture/      family-level architecture and the import record
docs/tasks/local/       ignored; the only place for machine-local execution state
tooling/                repository-level scripts (import, checks)
.claude/                shared agent rules and skills; package CLAUDE.md files stay package contracts
```

`docs/` is for people. Code never reads from `docs/`: fixtures, schemas and
machine-read provenance live in each package's `priv/`.

## Working on a package

Every package is verified from its own directory:

```sh
cd packages/wotex-runtime
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check --no-retry
```

`WOTEX_PATH_DEPS=1` resolves sibling packages from `packages/` and is allowed
only in the `dev`, `test` and `docs` environments. Unset, every package
declares Hex requirements, which is what a published package will use. The
root `.tool-versions` pins the current toolchain; the declared minimum
(`elixir ~> 1.18`) is verified in CI.

Run the checks of the package you changed and of the packages that depend on
it. A change in `wotex` or `wotex-runtime` affects every dependent package; a
change in a protocol adapter affects only that package.

The root Mix project (`:wotex_workspace`, not an umbrella, depending on no
package) reads `tooling/packages.yaml` and drives the packages from the
repository root through `mix wotex.*` tasks. Run `mix deps.get` once at the
root; each task runs the package's own Mix project in a separate OS process.

| Task | What it does |
| --- | --- |
| `mix wotex.affected [--base REF] [--docs] [--all] [--json]` | Packages affected by the changes since `REF` (default `origin/main`, `main`, then the root commit), in topological order; `--all` lists every package. |
| `mix wotex.check [--all\|--package NAME...] [--base REF] [--lane minimum\|current] [--env ENV]` | `mix deps.get --check-locked` and `mix check --no-retry` in each selected package with `WOTEX_PATH_DEPS=1`; stops at the first failure and prints a summary. |
| `mix wotex.boundary [--all\|--package NAME...]` | Sibling-API gate: reports references to a sibling's `@moduledoc false` module or `@doc false` function. |
| `mix wotex.archive [--all\|--package NAME...]` | Builds each package's Hex archive without path dependencies and runs its `bin/check_archive.exs` or `bin/check_package.exs`. |
| `mix wotex.catalogue [--check]` | Renders `docs/catalogue.yaml` from every package catalogue, or checks that it is current. |
| `mix wotex.native.sources` | Lists pinned native sources and verifies the digests of files present locally. |
| `mix wotex.native.advisories [--offline]` | Queries OSV for the pinned native sources. |
| `mix wotex.native.build --package NAME --workspace /abs/dir` | Runs a package's native build task in a disposable absolute workspace. |
| `mix wotex.new NAME [--depends-on a,b]` | Scaffolds `packages/NAME`, `docs/packages/NAME/` and the manifest entry. |

The default selection of `check`, `boundary` and `archive` is the affected
set. See [tooling/README.md](tooling/README.md) for the manifest format.

## Documentation

- `docs/packages/<name>/specs/` holds the normative specifications and the
  package catalogue (`catalogue.yaml`), which records each specification's
  implementation status.
- `docs/packages/<name>/plans/` holds the versioned completion contract.
- `docs/packages/<name>/provenance/` holds standards provenance and recorded
  evidence.
- Generated HexDocs for a package include its specifications; run
  `WOTEX_PATH_DEPS=1 MIX_ENV=docs mix docs` inside the package.

## Governance

[Contributing](CONTRIBUTING.md) · [Governance](GOVERNANCE.md) ·
[Security](SECURITY.md) · [Code of Conduct](CODE_OF_CONDUCT.md) ·
[License](LICENSE)
