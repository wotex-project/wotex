---
paths:
  - "lib/**/*.ex"
  - "test/**/*.exs"
  - "mix.exs"
---

# Elixir library rule

Build a normal Mix library, never an umbrella or release root. Do not define
`Application.start/2`. Pure operations stay in the caller process. Long-lived
runtime work belongs in a separate package and is returned as caller-configured
child specifications.

Use explicit dependencies and configuration arguments. Do not inspect sibling
directories, loaded modules, application environment, clocks, random sources,
or global registries to decide behavior.
