---
paths:
  - "lib/**/*.ex"
  - "test/**/*.exs"
---

# Elixir rules

- Prefer function-head pattern matching and tagged results.
- Keep one module per production file.
- Do not catch broad exceptions or convert external strings to atoms.
- Keep configuration in explicit structs passed by the consumer.
- A library module may return data or child specifications, but it must not
  start processes while loading.
- Use behaviours only for the required consumer-owned ports.
- Public types, errors, and compatibility behavior require executable tests.
- Module documentation describes the present contract without migration prose.
