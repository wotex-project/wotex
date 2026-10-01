---
name: conformance-testing
description: Change conformance claims, target messages, corpus provenance, canonical reports or result classification. Use for runner evidence and external target isolation; exclude protocol adapter implementation.
user-invocable: false
---

# Test conformance evidence

Input: the claim, standard revision, vector revision, target protocol and
affected JSON schema.
Output: consistent constructors, schemas, vectors and runner tests tied to the
exact subject and corpus identities.

Read `docs/packages/wotex-conformance/specs/WCF.01-conformance-runner.md`
for the changed boundary. Keep expected values and digests on the runner side;
assert that the actual target request omits them.

Add positive, negative and malformed vectors with their source provenance.
Exercise direct observation, mismatch, unsupported, not-run and infrastructure
failure without collapsing categories. Include wrong-vector, artifact-digest,
timeout and oversized-output cases when their mechanisms change.

Verify corpus manifests before target execution. Check canonical bytes and
digests from independently constructed equivalent values, with fixed timestamps
and environment. Reports retain bounded codes and observation digests rather
than raw target output.

Change the specification, schema mirrors, constructors and vectors together
when the public contract changes. Use the package guidance to select the
runner, lifecycle, schema and canonical tests that cover the changed mechanism.
Report results for the exact claim; unrelated passing vectors are not evidence.
