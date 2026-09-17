# Wotex Nx Package Contract

Wotex core owns W3C Web of Things values and terminology. This package inherits
those values and owns only explicit numerical conversion semantics.
Repository-wide rules are in the root `CLAUDE.md`.

- Consumer, company and customer names stay out of source, tests, docs,
  fixtures, history and metadata; say `consumer` or `consumer host`. Sibling
  packages are referenced by package name; relative paths inside the
  repository are allowed, absolute machine paths are not.
- No model fetching, training, selection, serving, agent routing, Action
  execution, authorization, canonical state, database, Repo, migration, Ash,
  Phoenix, Ecto, Oban, endpoint, application callback, or global registry.
- Loading starts no process. Every operation is deterministic and caller-driven.
- All time, identity, window, unit, missing-value, dtype, shape, quality, and
  output interpretations are explicit inputs.
- Numerical output and Action proposals are inert values, never authority.
- One module per `.ex`. Tests use `@moduledoc false` followed by a blank line.
- `WOTEX_PATH_DEPS=1` is the sole local workspace dependency switch.

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-nx` before
a local commit, then the gate of every dependent package. It compiles with
warnings as errors, checks formatting, dependencies, Credo, Doctor, ex_doc,
coverage, Dialyzer and the package archive.

## Documentation and local state

Specifications, the completion plan, decisions and provenance live under
`docs/packages/wotex-nx/`; `docs/packages/wotex-nx/specs/catalogue.yaml` owns
normative status. Machine-local execution records live only in the ignored
root `docs/tasks/local/wotex-nx/`.

## External automation boundary

This package exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-package
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral package contract.
