---
paths:
  - "test/**/*.exs"
  - "test/support/**/*.ex"
  - "priv/vectors/**/*.json"
---

# Test and evidence rules

- Tests prove outcomes at public boundaries, including malformed, timeout,
  oversized-output, wrong-vector, and artifact-digest failures.
- Build archive fixtures in temporary directories and remove them on exit.
- Never load a tested subject module into the conformance application.
- Keep expected values in the corpus and assert that target requests omit them.
- Fix timestamps and environment values in digest tests.
- Verify corpus manifests before running any target.
- Classify outcomes as `pass`, `fail`, `unsupported`, `not_run`, or
  `infrastructure_error`; do not collapse categories.
- A report assertion uses its canonical encoding and digest, not map iteration
  order.
