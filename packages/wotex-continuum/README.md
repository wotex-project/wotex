# Wotex Continuum

**Portable continuum values without persistence, dispatch, or hidden runtime authority.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_continuum.svg)](https://hex.pm/packages/wotex_continuum)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_continuum)
[![CI](https://github.com/wotex-project/wotex-continuum/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-continuum/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-continuum/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-continuum)
[![License](https://img.shields.io/github/license/wotex-project/wotex-continuum.svg)](https://github.com/wotex-project/wotex-continuum/blob/main/LICENSE)

[Installation](#installation) ·
[Quick Start](#quick-start) ·
[Scope](#scope) ·
[Wire Contract](#wire-contract) ·
[Errors](#errors) ·
[Development](#development)

---

Wotex Continuum provides immutable, host-neutral exchange values for carrying
Thing observations, Action intent and results, evidence, delivery state, and
deployment-mode lifecycle across an edge/cloud continuum.

Loading the library starts no process, performs no I/O, selects no provider,
evaluates no policy, and owns no database. A consumer host validates values,
decides authority, supplies transport and persistence, and supervises every
runtime component. The values make continuum boundaries explicit and replayable
without forcing a database, transport, scheduler, framework, or provider on the
consumer.

## Installation

Wotex Continuum 0.1 requires Elixir 1.18 or later.

```elixir
def deps do
  [
    {:wotex_continuum, "~> 0.1"}
  ]
end
```

## Quick Start

```elixir
alias WotexContinuum.{ActionIntent, Codec, ExecutionContext, Mode}

{:ok, mode} = Mode.new(%{deployment: :air_gapped, connectivity: :disconnected})

{:ok, context} =
  ExecutionContext.new(%{
    execution_id: "exec-018",
    node_id: "edge-a",
    mode: mode,
    observed_at: "2026-09-02T10:00:00Z"
  })

{:ok, intent} =
  ActionIntent.new(%{
    intent_id: "intent-018",
    thing_id: "urn:example:thing:pump-7",
    action_name: "setLevel",
    input: %{"level" => 42},
    requested_at: "2026-09-02T10:00:01Z",
    idempotency_key: "set-level-018",
    context: context
  })

{:ok, canonical_json} = Codec.encode(intent, canonical: true)
```

`ActionIntent` represents a request. Constructing or decoding it never invokes
the Action. Dispatch, authorization, deduplication, retries, and effect
recording belong to the consumer host.

## Scope

| Owned here | Owned by the consumer |
|------------|-----------------------|
| Manifest, compatibility, execution-context, and capability values | Canonical Thing, observation, Action-effect, identity, and policy state |
| Observation proposal, Action intent/result, evidence, and delivery values | Activation, entitlement, provider selection, credentials, and dispatch |
| Deployment mode, connectivity, lifecycle, degradation, and exit values | Persistence, migrations, jobs, network clients, UI, and telemetry exporters |
| Bounded decoding, canonical encoding, schemas, and executable vectors | Supervision, retries, reconciliation, and final authority |

Thing Description parsing and validation belongs to Wotex core.

## Wire Contract

WCT.01, WCT.02, and WCT.03 define the initial public contract. Every encoded
value carries its independent `schema_version`; package version and wire-schema
version are deliberately not interchangeable. `WotexContinuum.Codec` performs
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
a stable code, wire path, message, and structured details. Expected input
failures do not raise. Constructors validate identity, time, limits, modes,
capabilities, lifecycle relationships, and nested values before returning an
accepted struct.

## Development

```sh
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check
```

The explicit switch also applies when Mix evaluates this library as a
dependency under the `prod` dependency environment. Package construction
unsets it and records the released `wotex` version requirement instead of a
local path.

The completion gate covers formatting, warnings-as-errors compilation, strict
Credo, dependency audits, Dialyzer, complete public documentation, at least 95%
line coverage, the public-boundary scan, and compilation from the unpacked Hex
archive.

The explicit path switch resolves the sibling Wotex core checkout only in
development, test, or documentation environments. Without it, dependency
selection uses the published package requirement; a sibling directory never
changes dependency selection implicitly.

See `specs/` for the normative contracts and `test/vectors/` for executable
examples.

## License

Wotex Continuum is released under the [Apache License 2.0](https://github.com/wotex-project/wotex-continuum/blob/main/LICENSE).
