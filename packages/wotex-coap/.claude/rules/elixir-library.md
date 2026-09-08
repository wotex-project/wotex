---
paths:
  - "lib/**/*.ex"
  - "test/**/*.exs"
  - "mix.exs"
---
# Elixir protocol library

Build a normal Mix library without an Application callback. Pure operations run
in the caller. Long-lived connections require explicit consumer-owned startup,
configuration and cleanup. No global names, application-environment lookup,
implicit retries or simulator fallback. Use immutable values and structured
errors at every public input boundary.
