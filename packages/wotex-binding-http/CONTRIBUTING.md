# Contributing

Open an issue before broad API changes. Keep commits lowercase, conventional,
and logically scoped. Add executable evidence for every behavior change.

Run `WOTEX_PATH_DEPS=1 mix check` and `bin/check-boundary` before submitting a
change. Do not add a concrete HTTP client, connection pool, credential source,
application callback, or framework dependency.
