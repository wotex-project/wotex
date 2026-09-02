# Wotex

Wotex is a storage-neutral Elixir implementation of core W3C Web of Things
values and Thing Description mechanics. It gives a consumer one precise TD 1.1
value boundary without taking ownership of persistence, authorization,
credentials, supervision, transport connections, or physical-device truth.

The initial contract supports:

- W3C Thing Description 1.1 JSON parsing and validation;
- lossless preservation of JSON values and extension terms;
- deterministic canonical JSON for package-local comparison and digests;
- typed DataSchema, Form, Property, Action, Event, and security-scheme values;
- bounded parsing with explicit byte, depth, and node limits; and
- structured errors with stable codes and JSON paths.

Only `application/td+json` is claimed. Turtle, RDF/XML, remote JSON-LD context
retrieval, Thing Description 2.0, protocol execution, and Scripting API
conformance are outside the initial support surface.

## Use

```elixir
{:ok, td} = Wotex.ThingDescription.parse(json)
{:ok, canonical_json} = Wotex.ThingDescription.encode(td, :canonical)
map = Wotex.ThingDescription.to_map(td)
```

The dependency has no application callback. Loading it starts no process. A
consumer chooses its own lifecycle and composes runtime and binding libraries
separately.

## Standards baseline

The production baseline is the W3C Thing Description 1.1 Recommendation dated
5 December 2023. The bundled informative validation schema is pinned to the
`REC1.1` repository tag and documented in
[`docs/provenance/w3c-td-schema-1.1.md`](docs/provenance/w3c-td-schema-1.1.md).

## Status

The package version is pre-release. Public API, compatibility, and standards
claims advance only with the evidence gates in the normative specifications.

## License

Wotex source is licensed under Apache-2.0. Bundled W3C material retains its
W3C Software and Document License notice; see `NOTICE` and `priv/w3c/`.
