# Wotex Package Contract

Wotex owns consumer-neutral W3C Web of Things terminology and core Thing
Description semantics. Consumers inherit these public values and must not cause
this package to import their product models or redefine the standard terms.
Repository-wide rules are in the root `CLAUDE.md`.

## Invariants

- Use W3C terms exactly: Thing, Thing Description, Property, Action, Event,
  DataSchema, Form, Interaction Affordance, security scheme, ConsumedThing, and
  ExposedThing.
- Consumer, company and customer names stay out of source, tests, docs,
  fixtures, history and metadata. Sibling packages are referenced by package
  name; relative paths inside the repository are allowed, absolute machine
  paths are not.
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

## Documentation and local state

Specifications, the completion plan and provenance live under
`docs/packages/wotex/`; `docs/packages/wotex/specs/catalogue.yaml` owns
normative status. Machine-local execution state lives only in the ignored
root `docs/tasks/local/wotex/`.

## Gates

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex` before a
local commit, then the gate of every dependent package. It compiles with
warnings as errors, checks formatting, dependencies, Credo, Doctor, ex_doc,
coverage, Dialyzer and the package archive. Consumer-neutrality is a review
obligation governed by this contract; do not create a public denylist of
private consumers.

## External automation boundary

This package exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-package
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral package contract.
