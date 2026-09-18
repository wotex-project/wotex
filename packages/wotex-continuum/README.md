# Wotex Continuum

**Portable continuum values without persistence, dispatch, or hidden runtime authority.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_continuum.svg)](https://hex.pm/packages/wotex_continuum)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_continuum)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_continuum.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-continuum/LICENSE)

[Installation](#installation) ·
[Quick Start](#quick-start) ·
[Scope](#scope) ·
[Wire Contract](#wire-contract) ·
[Errors](#errors) ·
[Development](#development)

---

This development checkout has package version `0.1.0`. The public API remains
unstable. Package metadata does not establish publication or acceptance of every
work package in the completion contract.

*Continuum* is a project term for the span from disconnected edge devices to
cloud services across which these inert values are exchanged. W3C Web of Things
does not standardize such exchange values; every member name defined here is a
Wotex Continuum field, never a Thing Description vocabulary term.

Wotex Continuum provides immutable, host-neutral exchange values for carrying
Thing observations, Action intent and results, evidence, delivery state, and
deployment-mode lifecycle across that continuum.

Loading the library starts no process, performs no I/O, selects no provider,
evaluates no policy, and owns no database. A consumer host validates values,
decides authority, supplies transport and persistence, and supervises every
runtime component. The values make continuum boundaries explicit and replayable
without forcing a database, transport, scheduler, framework, or provider on the
consumer.

## Installation

Wotex Continuum requires Elixir 1.18 or later. No version is published on Hex
yet. Once one is, depend on it as usual:

```elixir
def deps do
  [
    {:wotex_continuum, "~> 0.1"}
  ]
end
```

Until then, depend on one commit of the
[WoTEx repository](https://github.com/wotex-project/wotex) and select each
package directory with `sparse:`. Wotex Continuum needs the core `wotex`
package, so declare both at the same `ref` with `override: true`, as the
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
    {:wotex_continuum,
     git: "https://github.com/wotex-project/wotex.git",
     ref: @wotex_ref,
     sparse: "packages/wotex-continuum",
     override: true}
  ]
end
```

For local development with the repository checked out next to your project:

```elixir
{:wotex, path: "../wotex/packages/wotex", override: true},
{:wotex_continuum, path: "../wotex/packages/wotex-continuum", override: true}
```

## Quick Start

```elixir
alias WotexContinuum.{ActionIntent, Codec, ExecutionScope, Mode}

{:ok, mode} = Mode.from_map(%{deployment: :air_gapped, connectivity: :disconnected})

{:ok, scope} =
  ExecutionScope.from_map(%{
    execution_id: "exec-018",
    node_id: "edge-a",
    mode: mode,
    observed_at: "2026-09-02T10:00:00Z"
  })

{:ok, intent} =
  ActionIntent.from_map(%{
    intent_id: "intent-018",
    thing_id: "urn:example:thing:pump-7",
    action_name: "setLevel",
    input: %{"level" => 42},
    requested_at: "2026-09-02T10:00:01Z",
    idempotency_key: "set-level-018",
    context: scope
  })

{:ok, canonical_json} = Codec.encode(intent, canonical: true)
```

`ActionIntent` represents a request. Constructing or decoding it never invokes
the Action. Dispatch, authorization, deduplication, retries, and effect
recording belong to the consumer host.

## Scope

| Owned here | Owned by the consumer |
|------------|-----------------------|
| Manifest, compatibility, execution-scope, and capability values | Canonical Thing, observation, Action-effect, identity, and policy state |
| Observation proposal, Action intent/result, evidence, and delivery values | Activation, entitlement, provider selection, credentials, and dispatch |
| Deployment mode, connectivity, lifecycle, degradation, and exit values | Persistence, migrations, jobs, network clients, UI, and telemetry exporters |
| Bounded decoding, canonical encoding, schemas, and executable vectors | Supervision, retries, reconciliation, and final authority |

Thing Description parsing and validation belongs to Wotex core.

## Wire Contract

WCT.01, WCT.02, and WCT.03 define the public contract at wire schema 2.0.0.
Every encoded value carries its independent `schema_version`; package version
and wire-schema version are deliberately not interchangeable. Wire 2.0.0 renamed
the `execution_context` kind to `execution_scope`, so a value encoded under wire
1.0.0 is rejected rather than silently reinterpreted. `WotexContinuum.Codec` performs
bounded decoding and deterministic canonical encoding, while
`WotexContinuum.Compatibility` reports every capability mismatch instead of
hiding partial compatibility behind a boolean.

The library uses Thing, Property, Action, Event, Thing Description, Consumer,
and Exposer with their meanings from
[Thing Description 1.1](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
and
[WoT Architecture 1.1](https://www.w3.org/TR/2023/REC-wot-architecture11-20231205/).
Continuum envelopes are Wotex extension contracts, not fields from a W3C
Recommendation, and do not imply certification.

## Errors

Untrusted maps and JSON return `{:error, %WotexContinuum.Error{}}`. Errors carry
a stable code, a phase, an RFC 6901 JSON Pointer path such as
`"/extensions/urn:example:payload/0"` (or `nil` when no wire location applies),
a message, and structured details. Expected input
failures do not raise. Constructors validate identity, time, limits, modes,
capabilities, lifecycle relationships, and nested values before returning an
accepted struct.

## Development

The [specification catalogue](../../docs/packages/wotex-continuum/specs/catalogue.yaml)
and [completion contract](../../docs/packages/wotex-continuum/plans/wotex-continuum-completion.md)
separate package verification from independent consumer, release and
stable-API evidence. Normative WCT documents retain their single owners under
`docs/packages/wotex-continuum/specs/` in the repository.
The [WCT-C01 contract map](../../docs/packages/wotex-continuum/specs/WCT-C01-contract-map.md) indexes every
field, default, null rule, error family, and lifecycle edge to executable
evidence. The [WCT-C02 admission map](../../docs/packages/wotex-continuum/specs/WCT-C02-admission-map.md)
records native UTF-8 parity and the intentional native-versus-decoder resource
boundary. The [WCT-C03 schema agreement map](../../docs/packages/wotex-continuum/specs/WCT-C03-schema-agreement.md)
connects every registered kind and nested owner route to schemas,
constructors, reconstruction, codecs, and published vectors.
The [WCT-C04 archive-consumer proof](../../docs/packages/wotex-continuum/specs/WCT-C04-archive-consumer.md)
installs one exact candidate archive in two behavior-complete isolated Hex
consumers and exercises the three WCT contracts without path or Git
dependencies.
The [WCT-C05 release-candidate dossier](../../docs/packages/wotex-continuum/specs/WCT-C05-release-dossier.md)
separates package API from wire compatibility and records metadata, dependency,
toolchain, public-content, standards, and nonclaim boundaries.

Run commands from the repository root; the
[root README](https://github.com/wotex-project/wotex/blob/main/README.md)
describes the workflow and validation tiers.

```bash
mix pkg wotex-continuum test test/wotex_continuum/codec_test.exs  # one test file
mix check.fast --package wotex-continuum                          # compile, format, Credo, tests
mix pkg wotex-continuum check --no-retry                          # full gate
```

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-continuum`. It compiles with warnings as errors, checks locked
and unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`,
strict Credo, Doctor, documentation with warnings as errors, tests with the
coverage floor (`mix coveralls`), Dialyzer, the archive check and
`git diff --check`. The public boundary scan is not part of the gate; run it
from `packages/wotex-continuum` before a commit:

```sh
elixir bin/check_boundary.exs
```

The archive check (`mix run --no-start bin/check_archive.exs`) builds one
exact artifact and installs it through a signed temporary Hex registry in
independent contract and reference consumers plus a separately isolated
direct Jason-floor consumer. It asserts Hex-only exact locks, isolated BEAM
paths, public examples, lifecycle and failure recovery, and every packaged
vector. This package has no native build, software profile or container lane.

`WOTEX_PATH_DEPS=1` selects the core package from `packages/wotex`, including
when Mix evaluates this library as a dependency under the `prod` dependency
environment. Package construction unsets it and records the released `wotex`
version requirement instead of a local path. Without it, dependency selection
uses the published package requirement; a nearby directory never changes
dependency selection implicitly. A successful local-path check does not
establish independent consumer installation against released dependencies.

The normative contracts are the WCT specifications linked above; `test/vectors/`
holds the executable examples, which also ship in the package.

## License

Wotex Continuum is released under the [Apache License 2.0](https://github.com/wotex-project/wotex/blob/main/packages/wotex-continuum/LICENSE).
