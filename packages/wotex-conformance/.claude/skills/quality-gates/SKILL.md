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
8. Review tracked text semantically for consumer-specific names, namespaces,
   private paths, credentials, and copied non-public prose. Do not encode
   private consumer names in a denylist.
9. Record the exact commit and archive digest in the handoff.
10. Stop after local evidence. Automated agents never configure or remove
    remotes, push, create tags, publish packages, or create releases.
