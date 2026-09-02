---
paths:
  - "lib/**/*.ex"
  - "test/**/*.{ex,exs}"
---

# Elixir rules

- Use one public module per source file.
- Add `@moduledoc`, `@typedoc`, `@type`, and `@spec` for public contracts.
- Return `{:ok, value}` or `{:error, %WotexContinuum.Error{}}` for untrusted
  input. Do not raise for validation failures.
- Do not read application environment or the system clock.
- Keep constructors pure and normalize atom/string map keys explicitly.
- Tests use `async: true` unless they demonstrate process absence.
