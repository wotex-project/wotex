# Wotex Directory

`wotex_directory` is a storage-neutral Elixir library for the W3C Web of Things
Discovery Thing Description Directory contract. It provides immutable request
and result values plus deterministic mechanics for registration, retrieval,
replacement, JSON Merge Patch, deletion, bounded listing, expiry, and
well-known Introduction.

The consumer supplies repository, authorization, clock, and identifier ports.
The library starts no process, owns no database or filesystem, serves no HTTP
endpoint, stores no credential, and reads no application-global configuration.

## Maturity

The package is pre-release. Its target is the W3C WoT Discovery Recommendation
dated 2023-12-05 and Thing Description 1.1. Implemented behavior is limited to
the capability matrix in `docs/specs/WTD.01-directory-contract.md`. The package
does not claim W3C certification and does not implement JSONPath, XPath, or
SPARQL search profiles.

## Dependency direction

The only production dependency is `wotex`, which owns Thing Description values,
validation, identifiers, extension preservation, and serialization. This
package never accesses the core struct internals.

For a local development checkout, select a path explicitly:

```sh
WOTEX_PATH_DEPS=1 mix deps.get
WOTEX_PATH_DEPS=1 mix test
```

The switch selects the sibling core checkout explicitly. It never checks
whether a neighboring directory exists. With the switch absent, Mix resolves
the published `wotex` package.

## Consumer composition

```elixir
{:ok, directory} =
  Wotex.Directory.Service.new(
    repository: {ConsumerRepository, repository_state},
    authorization: {ConsumerAuthorization, authorization_state},
    clock: {ConsumerClock, clock_state},
    identifier: {ConsumerIdentifier, identifier_state},
    introduction: directory_thing_description
  )

context = Wotex.Directory.Context.new!(principal, repository: request_scope)

{:ok, mutation} = Wotex.Directory.register(directory, thing_description, context)
{:ok, entry} = Wotex.Directory.get(directory, mutation.entry.identifier, context)
```

The consumer owns supervision, adapter lifetime, persistence transactions,
scheduling of `expire/3`, HTTP route mapping, authentication, and authorization
policy.

## License

Apache-2.0. See `NOTICE` for source attribution.
