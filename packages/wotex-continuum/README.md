# Wotex Continuum

`wotex_continuum` provides immutable, host-neutral exchange values for carrying
Thing observations, Action intent and results, evidence, delivery state, and
deployment-mode lifecycle across an edge/cloud continuum.

The library is deliberately inert. Loading it starts no process, performs no
I/O, selects no provider, evaluates no policy, and owns no database. A consumer
host validates values, decides authority, supplies transport and persistence,
and supervises every runtime component.

## Status

The package is pre-1.0. Its initial public contract is defined by WCT.01,
WCT.02, and WCT.03. Wire values carry an independent `schema_version`; package
version and wire-schema version are not interchangeable.

## Installation

Add the package to a Mix project after its first Hex release:

```elixir
{:wotex_continuum, "~> 0.1.0"}
```

## Example

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

## W3C Web of Things relationship

The library uses the W3C Web of Things terms Thing, Property, Action, Event,
Thing Description, Consumer, and Exposer with their standard meanings from
[Thing Description 1.1](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
and the
[WoT Architecture 1.1](https://www.w3.org/TR/2023/REC-wot-architecture11-20231205/).

Continuum envelopes are project-defined exchange values. They are not fields
from a W3C Recommendation and do not imply certification or conformance.

## Scope

This package owns:

- manifest, compatibility, execution-context, and capability values;
- observation proposal, Action intent/result, evidence, and delivery values;
- four deployment modes plus explicit connectivity state;
- lifecycle transitions, typed degradation, and exit receipts;
- bounded JSON decoding and deterministic project-canonical JSON encoding; and
- valid, invalid, and compatibility vectors.

It does not own:

- canonical Thing, observation, Action-effect, identity, or policy state;
- activation, entitlement, provider selection, credentials, or dispatch;
- persistence, migrations, jobs, network clients, UI, or telemetry exporters;
- a supervisor tree or application callback; or
- Thing Description parsing or validation, which belongs to the Wotex core.

## Verification

```sh
mix deps.get
mix check
./scripts/check_public_boundary.sh
```

See `specs/` for the normative contracts and `test/vectors/` for executable
examples.

During coordinated local development, set `WOTEX_PATH_DEPS=1` before dependency
fetch and verification. That explicit switch resolves the sibling Wotex core
checkout at `../wotex`. Without the switch, dependency selection uses the
published package version; it never changes merely because a directory exists.
