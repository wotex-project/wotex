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

Run `WOTEX_PATH_DEPS=1 mix check` and the boundary scan before local commits.
Never push unless a human explicitly requests it.
