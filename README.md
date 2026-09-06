# Wotex

**W3C Web of Things values and Thing Description mechanics for Elixir.**

[![Hex.pm](https://img.shields.io/hexpm/v/wotex.svg)](https://hex.pm/packages/wotex)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wotex)
[![CI](https://github.com/wotex-project/wotex/actions/workflows/ci.yml/badge.svg)](https://github.com/wotex-project/wotex/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/wotex-project/wotex/branch/main/graph/badge.svg)](https://codecov.io/gh/wotex-project/wotex)
[![License](https://img.shields.io/hexpm/l/wotex.svg)](LICENSE)

[Installation](#installation) ·
[Quick start](#quick-start) ·
[Value model](#value-model) ·
[Validation and limits](#validation-and-limits) ·
[Boundary](#boundary) ·
[Development](#development)

---

Wotex is the storage-neutral value layer for W3C Web of Things applications.
It parses, validates, preserves, and encodes W3C WoT Thing Description 1.1 and
Thing Model 1.1 documents without deciding where a Thing lives, who may
interact with it, or how a Form is executed.

The package is deliberately passive. Loading it starts no process, reads no
application configuration, and performs no network request. A consumer can use
the same values in a small embedded node, a disconnected release, or a
distributed service without changing their meaning.

## Capabilities

| Capability | Contract |
| --- | --- |
| Thing Description parsing | Decodes `application/td+json` and returns structured errors for expected input failures. |
| Thing Model parsing | Decodes `application/tm+json` reusable model templates without treating them as operational Things. |
| TD 1.1 validation | Applies the pinned informative W3C schema plus the package's documented semantic checks. |
| Extension preservation | Retains unknown JSON object members and native JSON values without interpreting consumer extensions. |
| Deterministic encoding | Produces key-sorted canonical JSON for package-local comparison and digest inputs. |
| Typed values | Exposes immutable DataSchema, Form, Property, Action, Event, and security-scheme values. |
| Bounded input | Enforces caller-configurable byte, nesting-depth, and node-count limits. |

## Installation

Wotex 0.1 requires Elixir 1.18 or later.

```elixir
def deps do
  [
    {:wotex, "~> 0.1.0"}
  ]
end
```

## Quick start

Parse a complete Thing Description and preserve its source bytes:

```elixir
json = ~S({
  "@context":"https://www.w3.org/2022/wot/td/v1.1",
  "title":"Weather station",
  "security":["nosec_sc"],
  "securityDefinitions":{"nosec_sc":{"scheme":"nosec"}},
  "properties":{
    "temperature":{
      "type":"number",
      "forms":[{"href":"https://example.test/temperature","op":"readproperty"}]
    }
  }
})

{:ok, td} = Wotex.ThingDescription.parse(json)
"Weather station" = Wotex.ThingDescription.to_map(td)["title"]
{:ok, ^json} = Wotex.ThingDescription.encode(td, :source)
{:ok, canonical} = Wotex.ThingDescription.encode(td, :canonical)
```

Build from a decoded JSON map when source-byte identity is not needed:

```elixir
{:ok, td} =
  Wotex.ThingDescription.from_map(%{
    "@context" => Wotex.td_context_1_1(),
    "title" => "Motor",
    "security" => ["nosec_sc"],
    "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
  })

{:ok, changed} = Wotex.ThingDescription.put_id(td, "urn:example:motor:1")
"urn:example:motor:1" = Wotex.ThingDescription.id(changed)
```

Parse a reusable Thing Model separately from an operational Thing Description:

```elixir
model_json = ~S({
  "@context":"https://www.w3.org/2022/wot/td/v1.1",
  "@type":"tm:ThingModel",
  "title":"Thermostat model",
  "properties":{"temperature":{"type":"number","unit":"Cel"}},
  "tm:optional":["/properties/temperature"]
})

{:ok, model} = Wotex.ThingModel.parse(model_json)
"Thermostat model" = Wotex.ThingModel.to_map(model)["title"]
```

Expected input failures are data. Match the stable `code`, `phase`, and JSON
Pointer `path`; do not couple logic to the human-readable message:

```elixir
{:error, %Wotex.Error{code: :object_required, phase: :value, path: "/"}} =
  Wotex.ThingDescription.from_map([])
```

## Value model

`Wotex.ThingDescription` and `Wotex.ThingModel` are separate aggregate
boundaries. Use their `to_map/1`, `id/1`, and `encode/2` operations instead of
coupling consumer code to struct fields, so compatible releases can evolve the
representation without changing the value contract.

The smaller value modules apply the same rule:

```elixir
{:ok, form} =
  Wotex.Form.new(%{
    "href" => "/properties/temperature",
    "op" => ["readproperty"],
    "x-vendor-hint" => %{"quality" => "high"}
  })

"/properties/temperature" = Wotex.Form.href(form)
["readproperty"] = Wotex.Form.operations(form)
%{"x-vendor-hint" => %{"quality" => "high"}} =
  Map.take(Wotex.Form.to_map(form), ["x-vendor-hint"])
```

Wotex preserves extension values but does not validate their private meaning.
That keeps the W3C vocabulary stable while allowing consumers and future
specifications to carry data the package does not yet understand.

## Validation and limits

Parsing validates by default. The defaults accept at most 1 MiB of source, 64
levels of JSON nesting, and 100,000 JSON nodes. Consumers handling constrained
or untrusted inputs can set smaller positive limits:

```elixir
Wotex.ThingDescription.parse(json,
  max_bytes: 64_000,
  max_depth: 24,
  max_nodes: 10_000
)
```

`validate: false` skips the TD schema and semantic pass when constructing from
a map, but it never disables JSON-value and resource-limit checks. Treat that
option as a staged-ingestion tool, not as a conformance result.

Canonical encoding is deterministic within the Wotex contract: object keys are
ordered and native JSON value semantics are retained. It is not advertised as
RFC 8785 JSON Canonicalization Scheme output.

## Standards baseline

The Thing Description and Thing Model production baseline is the
[W3C Web of Things Thing Description 1.1 Recommendation](https://www.w3.org/TR/wot-thing-description11/)
dated 5 December 2023. The bundled informative validation schema is pinned to
the upstream `REC1.1` tag. Exact commits, digests, licenses, and local
modifications are recorded in the TD and Thing Model provenance documents.

Only `application/td+json` and `application/tm+json` are claimed. Turtle,
RDF/XML, remote JSON-LD context retrieval, Thing Description 2.0 drafts,
protocol execution, authorization, and WoT Scripting API conformance are
outside this package.

## Boundary

Wotex owns W3C WoT values and TD 1.1 interpretation. A consumer owns:

- persistence, identifiers outside the Thing Description, and migrations;
- authentication, authorization, tenancy, and policy;
- credential custody and protocol transports;
- process supervision, retries, queues, and delivery guarantees; and
- canonical observations and evidence of physical Action effects.

Use a runtime or protocol-binding package to execute Forms. Keeping those
concerns outside the value layer makes a parsed Thing Description portable and
keeps dependency loading free of hidden work.

## Development

The [specification catalogue](docs/specs/catalogue.yaml) and completion contract
at `docs/plans/wotex-completion.md` define independently
implementable work, acceptance gates and remaining claim obligations. Local
execution tracking is not part of the published contract.

```bash
mix setup
mix test
mix test.cover
mix lint
mix check
mix docs
```

`mix check` is the completion gate. It compiles with warnings as errors, checks
formatting and strict Credo, requires at least 95% line coverage, audits
dependencies, runs Doctor and Dialyzer, builds HexDocs, scans the consumer
boundary, and inspects the unpacked Hex package. CI repeats the locked graph at
the supported floor and current toolchain and tests the latest allowed
dependency graph separately.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
widening a standards claim or public value contract.

## License

Wotex is released under Apache-2.0. Bundled W3C material retains the W3C
Software and Document License described in [NOTICE](NOTICE) and `priv/w3c/`.
