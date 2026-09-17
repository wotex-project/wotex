---
paths:
  - "packages/**/lib/**/*.ex"
  - "packages/**/test/**/*.exs"
  - "packages/**/mix.exs"
---

# Elixir library rule

Build a normal Mix library, never an umbrella or release root. Do not define
`Application.start/2` or any Application callback. Pure operations run in the
caller process.

Long-lived runtime work is never started implicitly. A package that owns a
long-lived connection or subscription returns it as caller-configured child
specifications and requires explicit consumer-owned startup, configuration and
cleanup. The `wotex` core package keeps long-lived runtime work out entirely;
it belongs in a separate package.
<!-- conflict: the `wotex` variant said "Long-lived runtime work belongs in a
separate package and is returned as caller-configured child specifications";
the protocol-library variant said "Long-lived connections require explicit
consumer-owned startup, configuration and cleanup". Both are kept above; the
first is read as scoped to the core package. -->

Use explicit dependencies and configuration arguments. No global names,
application-environment lookup, implicit retries or simulator fallback. Do not
inspect sibling directories, loaded modules, application environment, clocks,
random sources, or global registries to decide behavior. Sibling packages are
used only through their public, documented API and are selected by the explicit
`WOTEX_PATH_DEPS=1` switch, never by discovering a neighbouring directory.

Use immutable values and structured errors at every public input boundary.
