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

Run `mix check` before a local commit. The single gate includes structural
boundary checks and unpacked Hex-package inspection. Consumer-neutrality is a
review obligation governed by this contract and the release-readiness skill;
do not create a public denylist of private consumers.

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-repository
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral repository contract.

## Git authority

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package; or create equivalent remote state. Only
the human maintainer performs publication.

Every local commit uses `Tobias Bohwalli <hi@futhr.io>` as both author and
committer. Never substitute an agent, tool, bot, or shared contributor identity.
