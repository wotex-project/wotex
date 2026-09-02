---
paths:
  - "mix.exs"
  - "lib/**/*.ex"
---

# Elixir library rules

- Keep this a normal library project with no application callback.
- Do not start a process, perform I/O, read application configuration, or
  discover sibling directories during module loading.
- Receive clocks, target configuration, environment, and artifact identity as
  explicit input.
- Use direct `Port` executable invocation for external targets; never pass a
  command through a shell.
- Validate executable paths, arguments, environment keys, timeouts, and output
  bounds before spawning.
- Preserve deterministic result order by vector ID.
- Never convert untrusted strings to atoms.
- Production dependencies remain on the reviewed allowlist and may not include
  a subject package.
