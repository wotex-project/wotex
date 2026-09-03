# Wotex Nx

**Typed Thing observations in. Deterministic Nx batches and inert results out.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_nx.svg)](https://hex.pm/packages/wotex_nx)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_nx)
[![CI](https://github.com/wotex-project/wotex-nx/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex-nx/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex-nx/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex-nx)
[![License](https://img.shields.io/github/license/wotex-project/wotex-nx.svg)](https://github.com/wotex-project/wotex-nx/blob/main/LICENSE)

[Installation](#installation) ·
[Quick Start](#quick-start) ·
[Contract](#contract) ·
[Errors](#errors) ·
[Compatibility](#compatibility) ·
[Development](#development)

---

Wotex Nx is the consumer-neutral numerical boundary between W3C Web of Things
values and Elixir Nx. It converts explicitly typed Property and Event
observations into deterministic temporal rows, tensors, masks, quality vectors,
and lazy `Nx.Batch` containers. It can decode numerical output into an inert
observation, prediction, anomaly, or Thing Action proposal.

The package is deliberately not a model framework. It does not fetch, select,
train, serve, or route models. It does not start processes, access persistence,
read a clock, establish canonical Thing state, authorize output, or invoke an
Action. The consumer owns those decisions. This split keeps numerical
preparation reproducible while allowing any consumer-selected Nx backend.

## Installation

Wotex Nx 0.1 requires Elixir 1.18 or later.

```elixir
def deps do
  [
    {:wotex_nx, "~> 0.1"}
  ]
end
```

## Contract

| Contract | Responsibility |
|----------|----------------|
| `Wotex.Nx.Observation` | Carries caller-supplied identity, time, value, unit, and quality without becoming canonical state. |
| `Wotex.Nx.Feature` | Derives fixed numerical shape and default dtype from an exact `Wotex.DataSchema`. |
| `Wotex.Nx.Schema` | Preserves feature order and bounds rows, features, and flattened width before allocation. |
| `Wotex.Nx.Window` | Resamples caller-supplied observations without reading time. |
| `Wotex.Nx.Encoder` | Validates DataSchema, unit, quality, missing, finite-value, shape, and dtype policy before building a batch. |
| `Wotex.Nx.OutputSchema` | Defines the exact shape, bounds, and meaning accepted from numerical output. |
| `Wotex.Nx.Decoder` | Returns inert values only; it never writes state or invokes an Action. |

Wotex observation, feature, prediction, anomaly, and Action-proposal values are
package extension terms. They are not presented as W3C-defined structures.

## Quick Start

```elixir
alias Wotex.DataSchema
alias Wotex.Nx.{Encoded, Encoder, Feature, Observation, Row, Schema}

{:ok, data_schema} = DataSchema.new(%{"type" => "number", "unit" => "Cel"})

{:ok, temperature} =
  Feature.new(
    name: "temperature",
    thing_id: "urn:example:thing:1",
    affordance_type: :property,
    affordance_name: "temperature",
    data_schema: data_schema,
    accepted_quality: [:good],
    missing: :error
  )

{:ok, schema} = Schema.new(features: [temperature], max_rows: 128)

{:ok, observation} =
  Observation.new(
    id: "observation-42",
    thing_id: "urn:example:thing:1",
    affordance_type: :property,
    affordance_name: "temperature",
    observed_at: 1_725_196_800_000,
    value: 21.5,
    unit: "Cel"
  )

{:ok, row} = Row.new(observation.observed_at, %{"temperature" => observation})
{:ok, encoded} = Encoder.encode([row], schema)
batch = Encoded.batch(encoded)
```

`Nx.Batch` is lazy. The consumer chooses when and where to realize it and which
backend or model receives it.

## Errors

Constructors, encoding, resampling, and decoding return
`{:error, %Wotex.Nx.Error{}}` for expected validation failures. The error
identifies the processing phase, stable code, message, and structured details.
Invalid shape, dtype, units, quality, missing values, non-finite values, or
output bounds are rejected before a tensor or inert output is admitted.

## Compatibility

Wotex Nx 0.1 accepts Wotex 0.1 Thing Description and DataSchema values and Nx
0.13. Feature order, shape, dtype, missing-value behavior, and output
interpretation are explicit public inputs. Changes to those meanings require a
documented contract change; an Nx backend change alone does not.

The package implements
[`WNX.01`](docs/specs/WNX.01-observation-numerical-boundary.md). It uses W3C
Web of Things vocabulary from Wotex core, but its numerical contracts do not
claim W3C certification or define a W3C numerical binding.

## Development

A sibling checkout of `wotex` may be selected only in development, test, or
documentation environments:

```sh
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check
```

The completion gate covers formatting, warnings-as-errors compilation, strict
Credo, dependency audits, Dialyzer, public documentation, at least 95% line
coverage, boundary checks, and compilation from the unpacked Hex archive. The
path switch is never valid in production and never changes package metadata.

## License

Wotex Nx is released under the [Apache License 2.0](https://github.com/wotex-project/wotex-nx/blob/main/LICENSE).
