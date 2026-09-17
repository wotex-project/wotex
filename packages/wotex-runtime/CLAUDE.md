# Wotex Runtime Package Contract

Wotex core owns W3C Web of Things values and terminology. This package inherits
those types and owns only consumer-neutral interaction mechanics.
Repository-wide rules are in the root `CLAUDE.md`.

- Consumer, company and customer names stay out of source, tests, docs,
  fixtures, history and metadata; say `consumer` or `consumer host`. Sibling
  packages are referenced by package name; relative paths inside the
  repository are allowed, absolute machine paths are not.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, endpoint, global
  registry, application callback, entitlement, or provider implementation.
- Loading starts no process. Short operations stay in the caller. A subscription
  starts only through an explicit caller-configured child specification.
- The caller supplies request identity, deadlines, credentials, transports,
  names, supervision, and policy decisions.
- A protocol result is not canonical Property truth or proof of an Action
  effect.
- One module per `.ex` file. Public functions have docs and types. Tests use
  `@moduledoc false` followed by a blank line.
- No mutable source selection. `WOTEX_PATH_DEPS=1` is the sole local workspace
  switch; normal dependency identity is a released core version.

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-runtime`
before a local commit, then the gate of every dependent package. It compiles
with warnings as errors, checks formatting, dependencies, Credo, Doctor,
ex_doc, coverage, Dialyzer and the package archive. Consumer-neutrality is a
review obligation governed by this contract; do not create a public denylist
of private consumers.

## Documentation and local state

Specifications, the completion plan and decisions live under
`docs/packages/wotex-runtime/`; `docs/packages/wotex-runtime/specs/catalogue.yaml`
owns normative status. Mutable completion and audit trackers belong only in
the ignored root `docs/tasks/local/wotex-runtime/` and never enter Git,
package archives or generated documentation. Follow
`docs/packages/wotex-runtime/plans/wotex-runtime-completion.md`; do not create
optional local files outside that ignored path. Package and archive checks
must prove the tracker remains excluded.

## External automation boundary

This package exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-package
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral package contract.
