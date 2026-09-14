# Contributing

Open an issue before broad API changes. Keep commits lowercase, conventional,
and logically scoped. Add executable evidence for every behavior change.

Use `mix test` for the fast loop. Run
`WOTEX_PATH_DEPS=1 mix check --no-retry` as the authoritative repository gate
before submitting a change. Run the applicable explicit release-evidence
commands in the README for documentation, dependency, numerical coverage, or
packaging changes. Do not add a concrete HTTP client, connection pool,
credential source, application callback, or framework dependency.
