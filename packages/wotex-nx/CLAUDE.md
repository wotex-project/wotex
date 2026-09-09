# Wotex Nx Contract

Wotex core owns W3C Web of Things values and terminology. This package inherits
those values and owns only explicit numerical conversion semantics.

- Never mention or import a consumer product, company, sibling engine,
  repository, or filesystem path. Say `consumer` or `consumer host`.
- No model fetching, training, selection, serving, agent routing, Action
  execution, authorization, canonical state, database, Repo, migration, Ash,
  Phoenix, Ecto, Oban, endpoint, application callback, or global registry.
- Loading starts no process. Every operation is deterministic and caller-driven.
- All time, identity, window, unit, missing-value, dtype, shape, quality, and
  output interpretations are explicit inputs.
- Numerical output and Action proposals are inert values, never authority.
- One module per `.ex`. Tests use `@moduledoc false` followed by a blank line.
- `WOTEX_PATH_DEPS=1` is the sole local workspace dependency switch.

Run `WOTEX_PATH_DEPS=1 mix check` before local commits.

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-repository
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral repository contract.

## Release metadata

`CHANGELOG.md` is maintained only by GitOps. Never edit it directly.
Once GitOps is configured for this repository, the human maintainer prepares
the first release from the existing changelog with
`mix git_ops.release --override 0.1.0` and later releases with `mix git_ops.release`. Automated agents must not invoke either release task.

## Git authority

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package; or create equivalent remote state. Only
the human maintainer performs publication. Never change repository visibility.

Local commits use the identity already configured by the contributor running
Git. Automated agents must never set or override Git identity; record an agent,
tool, or bot as an author, committer, or co-author; invent a contributor
identity; or remove attribution supplied by a human contributor.
