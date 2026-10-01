---
name: spec-delivery
description: Implement an accepted specification or change public behavior, errors, compatibility or standards claims. Use to connect obligations to implementation and evidence; exclude internal refactors with unchanged contracts.
user-invocable: false
---

# Deliver a public contract

Input: the requested behavior and owning package requirement.
Output: a coherent implementation, tests and contract updates, with actual
evidence for the claimed behavior.

Read the owning specification under `docs/packages/<name>/specs/`.
Load its cited decisions and source revisions only where they affect the
change. Identify the obligation, public seam, supported cells and compatibility
impact before editing. If the requested behavior has no accepted owner, state
that gap in chat rather than inventing a standards claim.

Define the relevant values, errors, limits, deterministic behavior and ownership
boundaries. Add tests for valid input, malformed and boundary input, unsupported
cells and preserved extensions as applicable. Implement the complete requested
slice without silently adding optional profiles or transport ownership.

When obligations change, update the owning specification version, package
catalogue and affected schema or vector alongside the code. Preserve useful
requirement-to-test links in existing evidence tables; do not add task reports.

Select mechanism-specific skills by their descriptions and validate the
affected code through `monorepo-workflow`. Compare implementation, docs and
vectors before claiming completion. Report source review separately from
executed tests; planned cases and schema validity do not prove support.
