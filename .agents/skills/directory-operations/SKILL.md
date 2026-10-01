---
name: directory-operations
description: Change Directory mutations, repository or authorization ports, clocks, expiry, pagination or Introduction. Use for ordering and concurrency across consumer ports; exclude core Thing Description parsing.
user-invocable: false
---

# Test directory port ordering

Input: the changed operation, port contract, expected version and explicit clock.
Output: operation and adapter tests that demonstrate ordering, conflict and
failure behavior at public boundaries.

Read `docs/packages/wotex-directory/specs/WTD.01-directory-contract.md`
for the affected operation. Trace authorization, repository reads, validation
and writes with the existing probes or barrier repositories. A denial must
not reveal entry existence or reach storage.

For mutations and expiry, exercise optimistic conflicts and failure paths.
Check JSON Merge Patch admission followed by core validation before persistence;
a failed mutation must not return a successful mutation or Event.
Use the injected clock for registration and expiry edge cases.

For listing, test Unicode code-point identifier order, bounded cursors and
collection-revision conflicts. Introduction returns only the directory's own
Thing Description without reading entries. Keep unsupported search outcomes
explicit rather than emulating a profile.

When a port changes, run its reusable contract suite against the independent
test adapters in `test/support/wotex/directory/`, alongside the affected
public-operation tests. Report which adapters and failure paths ran. Archive
adoption needs the separate artifact checks.
