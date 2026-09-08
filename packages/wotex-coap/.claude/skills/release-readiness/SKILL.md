---
name: wotex-release-readiness
description: Apply when preparing a Wotex archive, release candidate, tag, or public compatibility claim.
---

# Release readiness

1. Build from a clean checkout and lockfile.
2. Run formatting, warnings-as-errors compilation, tests, docs, and archive build.
3. Inspect archive contents and provenance.
4. Verify there is no application callback or dependency-load side effect.
5. Review source, docs, fixtures, metadata, and intended history for violations
   of the consumer-neutral repository contract. Never encode, fragment, or
   obfuscate a private consumer name in public source to perform this review.
6. Match every advertised standards claim to an exact vector digest and result.
7. Treat development versions as unstable even when all checks pass.
