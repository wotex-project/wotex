---
name: spec-authoring
description: Define or review new WoTEx package contracts, prospective package boundaries and acceptance obligations before implementation. Use for promoting research or resolving public semantics; exclude routine prose edits and unchanged internal refactors.
user-invocable: false
---

# Author package contracts

Read root/package instructions, owning catalogue and relevant producer contracts.
Use [the template](../../../docs/templates/spec-base.md) for new contracts.
Define observable behavior, closed inputs/types/units/defaults/bounds, errors,
ordering, lifecycle, retry/cancellation and compatibility without relying on chat.
Summarize the exact inherited behavior and link its owner; do not duplicate a
producer's semantic definition or invent a consumer-specific substitute.

Keep TD/TM, Runtime interaction, Continuum values, protocol custody and consumer
authority distinct. Generic specs contain no product/customer names, credentials,
private identities or consumer schemas. Primary sources establish facts;
inspection at a newer source revision does not select that dependency.

Map stable requirements to independent reproducible acceptance cases and
concrete falsifiers. Mark target, implementation and executed evidence separately.
Walk normal/adverse traces to find missing defaults, conflicting ownership,
unsupported semantics, unbounded work and stale-basis reuse before writing code.

A prospective package may own a target-only documentation tree/catalogue before
scaffolding. Explicitly state that it is outside the current generated family
catalogue; register it in the tooling/package graph before runtime delivery.
Never fake modules/test evidence or manually edit the generated catalogue.

Update owning versions/catalogues, index and completion plan together. Use
technical-writing for final prose review and existing documentation checks for
references/metadata. Once implementation is authorized, apply spec-delivery and
the mechanism-specific workflow; report actual checks, not planned proof.
