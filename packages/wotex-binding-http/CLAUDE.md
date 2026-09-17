# Wotex HTTP Binding Contract

Wotex core owns W3C Web of Things values and terminology. Wotex Runtime owns
consumer-neutral interaction mechanics. This package owns only HTTP message
mapping and Server-Sent Events adaptation through a consumer-supplied client.
Repository-wide rules are in the root `CLAUDE.md`.

- Consumer, company and customer names stay out of every file. Say `consumer`
  or `consumer host`. Sibling packages are referenced by package name;
  relative paths inside the repository are allowed, absolute machine paths are
  not.
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

Run `WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-binding-http`
before a local commit, then the gate of every dependent package. Run
`elixir bin/check_boundary.exs` for the public boundary.

## Local execution state

Mutable completion/audit trackers belong only under the ignored root
`docs/tasks/local/wotex-binding-http/` and must never enter Git, package
archives or generated documentation. Durable specifications and the completion
plan `docs/packages/wotex-binding-http/plans/wotex-binding-http-completion.md`
remain tracked; create no optional tracker beneath publishable documentation.
Package/archive checks must prove the tracker remains excluded.
