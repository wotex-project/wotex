# Wotex Nx

`wotex_nx` is a consumer-neutral boundary between W3C Web of Things values and
Elixir Nx. It converts explicitly typed Property and Event observations into
deterministic temporal rows, tensors, masks, quality vectors, and lazy
`Nx.Batch` containers. It can decode a numerical result into an inert
observation, prediction, anomaly, or Thing Action proposal.

The package is deliberately not a model framework. It does not fetch, select,
train, serve, or route models. It does not start processes, access persistence,
read a clock, establish canonical Thing state, authorize output, or invoke an
Action. The consumer owns all of those decisions.

## Contract

- `Wotex.Nx.Observation` is an input or inert output value, not canonical state.
- `Wotex.Nx.Feature` derives fixed numerical shape and default dtype from an
  exact `Wotex.DataSchema`.
- `Wotex.Nx.Schema` preserves feature order and bounds rows, features, and
  flattened width before allocation.
- `Wotex.Nx.Window` resamples caller-supplied observations without reading time.
- `Wotex.Nx.Encoder` validates DataSchema, unit, quality, missing, finite-value,
  shape, and dtype policy before building an `Nx.Batch`.
- `Wotex.Nx.OutputSchema` and `Wotex.Nx.Decoder` return inert values only.

Wotex observation, feature, prediction, anomaly, and Action-proposal values are
package extension terms. They are not presented as W3C-defined structures.

## Example

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

## Local verification

The exact released dependency path is used by default. A sibling checkout of
`wotex` may be selected only in development, test, or documentation environments:

```sh
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix check
```

The path switch is never valid in production and never changes package archive
metadata.

## Status

The package implements the development contract in
[`WNX.01`](docs/specs/WNX.01-observation-numerical-boundary.md). It does not
claim W3C certification or define a W3C numerical binding.
