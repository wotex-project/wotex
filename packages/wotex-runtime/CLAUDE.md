# Wotex Runtime Contract

Wotex core owns W3C Web of Things values and terminology. This package inherits
those types and owns only consumer-neutral interaction mechanics.

- Never mention or import a consumer product, company, sibling engine,
  repository, or filesystem path. Say `consumer` or `consumer host`.
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

Run `WOTEX_PATH_DEPS=1 mix check` before local commits. The single gate includes
structural boundary checks and unpacked Hex-package inspection.
Consumer-neutrality is a review obligation governed by this contract and the
runtime-proof skill; do not create a public denylist of private consumers.

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-repository
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral repository contract.

## Release metadata

`CHANGELOG.md` is maintained only by GitOps. Never edit it directly. Once GitOps is configured and
release prerequisites pass, the human maintainer prepares the first release with `mix git_ops.release --override 0.1.0` and later releases with
`mix git_ops.release`. Automated agents must not invoke either release task.

## Git authority

Mutable completion/audit trackers belong only under ignored `docs/tasks/local/`
and must never enter Git, package archives or generated documentation. Durable
specifications, dependency contracts and completion plans remain tracked.
Follow `docs/plans/wotex-runtime-completion.md`; do not create optional local files
outside its declared ignored tracker path. Package/archive checks must prove the
tracker remains excluded.

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package; or create equivalent remote state. Only
the human maintainer performs publication. Never change repository visibility.

Local commits use the identity already configured by the contributor running
Git. Automated agents must never set or override Git identity; record an agent,
tool, or bot as an author, committer, or co-author; invent a contributor
identity; or remove attribution supplied by a human contributor.
