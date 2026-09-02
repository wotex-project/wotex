---
name: quality-gates
description: Apply before committing or handing off changes in this repository.
---

# Quality gates

1. Run `mix format --check-formatted`.
2. Run `mix compile --warnings-as-errors` from a clean build directory.
3. Run `mix test`.
4. Run `mix docs`.
5. Run `mix hex.build` and inspect the packaged file list.
6. Confirm `Application.spec(:wotex_conformance, :mod)` is empty.
7. Confirm production dependencies match the reviewed allowlist.
8. Scan tracked text for consumer names, consumer namespaces, private paths,
   credentials, and copied non-public prose.
9. Record the exact commit and archive digest in the handoff.
