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

Run `WOTEX_PATH_DEPS=1 mix check` and `bin/check-boundary` before local commits.
Never push unless a human explicitly requests it.
