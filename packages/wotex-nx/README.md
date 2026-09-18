# Wotex Nx

**Transforms typed Thing observations into deterministic Nx batches and inert result values.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex_nx.svg)](https://hex.pm/packages/wotex_nx)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex_nx)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/wotex_nx.svg)](https://github.com/wotex-project/wotex/blob/main/packages/wotex-nx/LICENSE)

[Installation](#installation) ·
[Quick start](#quick-start) ·
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

Wotex Nx 0.1 supports Elixir 1.18.4 with Erlang/OTP 27.3.4.15 through Elixir
1.20.2 with Erlang/OTP 29.0.4, the minimum and current toolchain lanes
in [`tooling/packages.yaml`](https://github.com/wotex-project/wotex/blob/main/tooling/packages.yaml).
Add it to your dependencies:

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

## Quick start

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

Value tensors are built on the backend that is the default at encode time and
only the stack is deferred; the consumer chooses which backend or model
receives the batch. Masks use `1` for observed and `0` for filled. Axis 0 of
the batch is the window row of one sample, so hand a whole window to an
`Nx.Serving` (`batch_size` at least `Encoded.row_count/1`) or reduce per row
explicitly. `Encoded.template/1` gives the container shapes for an `Axon.input`
or serving contract, and an `Encoded` value can be passed straight to
`Nx.Defn.jit_apply/3`.

## Errors

Constructors, encoding, resampling, and decoding return
`{:error, %Wotex.Nx.Error{}}` for expected validation failures. The error
identifies the processing phase, stable code, message, and structured details.
Invalid shape, dtype, units, quality, missing values, non-finite values, or
output bounds are rejected before a tensor or inert output is admitted.

## Compatibility

Wotex Nx 0.1 accepts Wotex 0.1 Thing Description and DataSchema values and
declares Nx 0.13.1. Feature order, shape, dtype, missing-value behavior, and
output interpretation are explicit public inputs. Changes to those meanings
require a documented contract change. The executable reference cohort is
two runtime lanes, Elixir 1.18.4 with Erlang/OTP 27.3.4.15 (minimum) and
Elixir 1.20.2 with Erlang/OTP 29.0.4 (current), each with Nx 0.13.1,
`Nx.BinaryBackend`, and `Nx.Defn.Evaluator`; its
[comparison policy](../../docs/packages/wotex-nx/provenance/runtime-backend-cohort.md)
does not claim byte or numerical equivalence for untested backends or runtimes.

The package implements
[`WNX.01`](../../docs/packages/wotex-nx/specs/WNX.01-observation-numerical-boundary.md).
It uses W3C Web of Things vocabulary from Wotex core, but its numerical
contracts do not claim W3C certification or define a W3C numerical binding.

## Development

The [specification](../../docs/packages/wotex-nx/specs/WNX.01-observation-numerical-boundary.md)
and [completion contract](../../docs/packages/wotex-nx/plans/wotex-nx-completion.md)
define the numerical contract, work packages and acceptance gates. Local
execution tracking is not part of the published contract.

Run commands from the repository root; the
[contributing guide](https://github.com/wotex-project/wotex/blob/main/CONTRIBUTING.md)
describes the workflow and validation tiers.

```bash
mix pkg wotex-nx test test/wotex/nx/window_encoder_test.exs  # one test file
mix check.fast --package wotex-nx                            # compile, format, Credo, tests
mix pkg wotex-nx check --no-retry                            # full gate
```

The full gate is the same as `WOTEX_PATH_DEPS=1 mix check --no-retry` inside
`packages/wotex-nx`. It compiles with warnings as errors, checks the lock and
unused dependencies, formatting, `mix deps.audit` and `mix hex.audit`, Credo,
Doctor, `mix docs --warnings-as-errors` (in the `docs` environment), tests
with the coverage floor (`mix coveralls`), Dialyzer, the numerical-boundary
scan (`elixir bin/check_boundary.exs`) and `git diff --check`, and then runs
the archive check. `WOTEX_PATH_DEPS=1` selects the core package
from `packages/wotex` only in development, test and documentation
environments; it is never valid in production and never changes package
metadata.

The archive check (`mix run --no-start bin/check_archive.exs`) runs on the
declared reference cohort. It compiles an isolated consumer from the exact
unpacked Wotex Nx and core archives. Generated work stays in the
operating-system temporary directory. The check builds the archive once from
an external temporary mirror containing local and harness sentinels;
source-byte identity and sentinel exclusion prove the package allowlist.

This package has no native build, software profile or container lane.

## License

Wotex Nx is released under the [Apache License 2.0](https://github.com/wotex-project/wotex/blob/main/packages/wotex-nx/LICENSE).
