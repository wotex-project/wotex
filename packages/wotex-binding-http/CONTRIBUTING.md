# Contributing

Open an issue before broad API changes. Keep commits lowercase, conventional,
and logically scoped. Add executable evidence for every behavior change.

Run `WOTEX_PATH_DEPS=1 mix check` and `elixir bin/check_boundary.exs` before
submitting a change. Do not add a concrete HTTP client, connection pool,
credential source, application callback, or framework dependency.
