---
paths:
  - "test/**/*.exs"
---

# Testing rules

- Start every test module with `@moduledoc false` followed by a blank line.
- Use isolated in-memory test doubles with no application-global state.
- Test success, denial, malformed input, conflict, expiry, pagination, and port
  failure paths.
- Assert the expression under test on the left.
- A fresh run against the final tree is required for completion evidence.
