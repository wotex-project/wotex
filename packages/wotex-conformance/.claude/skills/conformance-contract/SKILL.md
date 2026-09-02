---
name: conformance-contract
description: Apply when changing claims, vectors, target protocol, runner evaluation, result classification, report schemas, or corpus provenance.
---

# Conformance contract workflow

1. Read `docs/specs/WCF.01-conformance-runner.md` completely.
2. Identify the exact claim, standards revision, vector revision, and affected
   JSON schema.
3. Keep expected values exclusively on the runner side.
4. Add or update canonical positive and negative vectors with provenance.
5. Test direct observation, mismatch, unsupported, not-run, and infrastructure
   failure as applicable.
6. Verify canonical bytes and digests twice from independently loaded values.
7. Confirm reports retain only bounded codes and digests from target output.
8. Update the specification, schemas, implementation, and tests atomically.
