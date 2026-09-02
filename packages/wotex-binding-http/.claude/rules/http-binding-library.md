---
paths:
  - "lib/**/*.ex"
  - "test/**/*.exs"
  - "mix.exs"
---

# HTTP binding library rule

Keep networking behind the client behavior. Do not select or start a concrete
HTTP stack. Do not read application environment. Static Form and configured
headers are untrusted input: validate names and values, reject credential and
message-framing fields, and pass credentials separately for the immediate call.

HTTP method names are case-sensitive tokens. Apply the TD 1.1 HTTP defaults only
where defined. The draft Profiles mappings used for action-status and SSE
operations are package behavior, not a conformance claim.
