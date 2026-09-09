# Wotex HTTP Binding Contract

Wotex core owns W3C Web of Things values and terminology. Wotex Runtime owns
consumer-neutral interaction mechanics. This package owns only HTTP message
mapping and Server-Sent Events adaptation through a consumer-supplied client.

- Never mention or import a consumer product, company, sibling engine,
  repository, or filesystem path. Say `consumer` or `consumer host`.
- No database, Repo, migration, web framework, job framework, endpoint, global
  registry, application callback, built-in client, connection pool, credential
  store, or provider implementation.
- Loading starts no process. A stream opens only through the explicit Runtime
  subscription lifecycle and a supplied client port.
- HTTP request and response values never contain credentials. Credential
  material crosses only the immediate client-port call and must not be retained.
- Treat the current Profiles and Binding Registry documents as drafts. Never
  claim W3C Profile or registry conformance.
- One module per `.ex` file. Public functions have docs and types. Tests use
  `@moduledoc false` followed by a blank line.
- No mutable source selection. `WOTEX_PATH_DEPS=1` is the sole local workspace
  switch; normal dependency identities are released package versions.

Run `WOTEX_PATH_DEPS=1 mix check` and `elixir bin/check_boundary.exs` before
local commits.

## External automation boundary

This repository exposes source, specifications, dependency contracts, vectors,
and deterministic verification commands to external engineering automation. It
does not own worker coordination, claims, leases, attempts, cross-repository
programme state, accepted outcomes, or remote publication policy. Do not add a
coordination daemon, graph database, shared-workspace application, or
tool-specific project metadata. External automation must adapt to this
consumer-neutral repository contract.

## Release metadata

`CHANGELOG.md` is reserved for GitOps release metadata; never edit it directly.
Once GitOps tooling and configuration are installed, the human maintainer
prepares the first release with `mix git_ops.release --override 0.1.0` because
the initial changelog already exists. Later releases use `mix git_ops.release`.
These are future human release steps, not a claim that tooling is configured
or a release is ready. Automated agents must not invoke either release task.

## Git authority

Mutable completion/audit trackers belong only under ignored `docs/tasks/local/`
and must never enter Git, package archives or generated documentation. Durable
specifications and completion plans remain tracked. Follow
`docs/plans/wotex-binding-http-completion.md`; create no optional tracker beneath exported
documentation outside its declared ignored path. Package/archive checks must
prove the tracker remains excluded.

Automated agents must never configure, add, change, or remove a Git remote;
push; create a tag; publish a package or release; or create equivalent remote
state. Only the human maintainer performs publication. Never change repository
visibility.

Local commits use the identity already configured by the contributor running
Git. Automated agents must never set or override Git identity; record an agent,
tool, or bot as an author, committer, or co-author; invent a contributor
identity; or remove attribution supplied by a human contributor.
