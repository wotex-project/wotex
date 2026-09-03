# Wotex Repository Contract

Wotex owns consumer-neutral W3C Web of Things terminology and core Thing
Description semantics. Consumers inherit these public values and must not cause
this repository to import their product models or redefine the standard terms.

## Invariants

- Use W3C terms exactly: Thing, Thing Description, Property, Action, Event,
  DataSchema, Form, Interaction Affordance, security scheme, ConsumedThing, and
  ExposedThing.
- No consumer product, company, sibling-engine, repository, or filesystem path
  names appear in source, tests, docs, fixtures, history, or metadata.
- Say `consumer` or `consumer host` at integration boundaries.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, endpoint, queue,
  PubSub, entitlement, provider implementation, or application callback.
- Loading the dependency starts no process and performs no network or runtime
  filesystem access.
- Remote JSON-LD contexts are never fetched.
- Every standards claim pins the exact revision and executable evidence.
- One module per `.ex` file. Tests use `@moduledoc false` followed by a blank
  line. Public functions have types and documentation.
- Preserve unknown extension terms. Never validate consumer-specific extension
  meaning as W3C behavior.
- Keep maps immutable, errors structured, limits explicit, and output
  deterministic where claimed.

## Gates

Run `mix check` before a local commit. The single gate includes the boundary
scan and unpacked Hex-package inspection.

## Git authority

Automated agents must never configure, add, change, or remove a Git remote and
must never run `git push` or any equivalent publication command. Only the human
owner publishes repository history.

Every local commit must use the repository-configured human owner identity from
`git config user.name` and `git config user.email`. Never substitute an agent,
tool, bot, or shared contributor identity.
