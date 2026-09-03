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

Run `WOTEX_PATH_DEPS=1 mix check` and `bin/check-boundary` before local commits.
Automated agents never push repository history.

## Git authority

Automated agents must never configure, add, change, or remove a Git remote and
must never run `git push` or any equivalent publication command. Only the human
owner publishes repository history.

Every local commit must use the repository-configured human owner identity from
`git config user.name` and `git config user.email`. Never substitute an agent,
tool, bot, or shared contributor identity.
