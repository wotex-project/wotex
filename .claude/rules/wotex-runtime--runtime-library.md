---
paths:
  - "packages/wotex-runtime/**"
---

# Runtime library rule (wotex-runtime)

No application callback or implicit singleton. Synchronous planning and
requests execute in the caller. A genuine subscription may expose `child_spec/1`
and `start_link/1`; every name, id, port configuration, receiver, and restart
policy is explicit. Never read application environment or discover modules.
