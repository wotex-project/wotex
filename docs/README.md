# WoTEx documentation

Everything a person reads about the WoTEx package family lives here. Code
never reads from this tree; fixtures, schemas, vectors and machine-read
provenance live in each package's `priv/`. The one exception, recorded in the
root `CLAUDE.md`, is wotex-lab's documentation-backed development features
(the knowledge graph and its MCP resources), which read this tree as their
subject through `Wotex.Lab.Documentation`.

## Layout

| Path | Contents |
| --- | --- |
| `packages/<name>/specs/` | Normative specifications of one package and its `catalogue.yaml`, the owner of each specification's `implementation_status`. |
| `packages/<name>/plans/` | The package's versioned completion contract. |
| `packages/<name>/decisions/` | Package-level decision records. |
| `packages/<name>/provenance/` | Standards provenance, pinned sources and recorded evidence of the package. |
| `packages/<name>/security.md` | Package security posture. |
| `packages/<name>/*.md` | Other package-level documents that are neither specification nor plan, such as the HTTP and MQTT bindings' inventories and baselines and the Continuum threat model. |
| `catalogue.yaml` | The family catalogue, generated from every package catalogue by `mix wotex.catalogue`; never edited by hand. |
| `architecture/` | Family-level architecture: the package graph and the repository layout. |
| `decisions/` | Family-level decision records. |
| `guides/` | Cross-package guides (consumers, transport authors, releases). |
| `tasks/local/<name>/` | Ignored. Machine-local execution state only; never tracked or published. |

Relative links inside a package's documentation stay valid because
`specs/`, `plans/`, `decisions/` and `provenance/` remain siblings under
`packages/<name>/`.

## Packages and specification prefixes

| Package | Specification prefixes | Documentation |
| --- | --- | --- |
| `wotex` | `WTX` | [packages/wotex](packages/wotex) |
| `wotex-runtime` | `WRT`, `RT-C` | [packages/wotex-runtime](packages/wotex-runtime) |
| `wotex-directory` | `WTD` | [packages/wotex-directory](packages/wotex-directory) |
| `wotex-nx` | `WNX` | [packages/wotex-nx](packages/wotex-nx) |
| `wotex-continuum` | `WCT`, `WCT-C` | [packages/wotex-continuum](packages/wotex-continuum) |
| `wotex-conformance` | `WCF` | [packages/wotex-conformance](packages/wotex-conformance) |
| `wotex-binding-http` | `WBH` | [packages/wotex-binding-http](packages/wotex-binding-http) |
| `wotex-binding-mqtt` | `WBM`, `WBM-C` | [packages/wotex-binding-mqtt](packages/wotex-binding-mqtt) |
| `wotex-bacnet` | `WBA` | [packages/wotex-bacnet](packages/wotex-bacnet) |
| `wotex-ble` | `WBL` | [packages/wotex-ble](packages/wotex-ble) |
| `wotex-coap` | `WCO` | [packages/wotex-coap](packages/wotex-coap) |
| `wotex-matter` | `WMA` | [packages/wotex-matter](packages/wotex-matter) |
| `wotex-modbus` | `WMB` | [packages/wotex-modbus](packages/wotex-modbus) |
| `wotex-opcua` | `WOP` | [packages/wotex-opcua](packages/wotex-opcua) |
| `wotex-thread` | `WTH` | [packages/wotex-thread](packages/wotex-thread) |
| `wotex-lab` | `WLB` | [packages/wotex-lab](packages/wotex-lab) |

A specification identifier is unique across the family; the prefix names its
owning package.

## Catalogue paths

Inside `packages/<name>/specs/catalogue.yaml`, a path starting with `docs/`
(for example `docs/specs/WTX.01-thing-description.md`) is relative to that
package's documentation tree, `docs/packages/<name>/`. Any other path (for
example `priv/fixtures/contract-v1.json`) is relative to the package
directory, `packages/<name>/`. Tooling that reads a catalogue resolves the
two roots this way.

## Family documents

- [Development workflow](guides/development.md) — commands, validation tiers, Dexter, CI
- [Decision 0001: one repository of independent packages](decisions/0001-one-repository-of-independent-packages.md)
- [Package graph and boundaries](architecture/package-graph.md)
- [Consuming WoTEx packages](guides/consumer.md)
- [Releasing a package](guides/release.md)
