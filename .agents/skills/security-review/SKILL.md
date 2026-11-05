---
name: security-review
description: "Assess requested security reviews or audits and cross-package changes involving untrusted protocol/profile inputs, credential ports, Runtime admission, Directory authorization or native execution. Reuse owning mechanism skills; exclude ordinary pure-value or numerical changes without a trust-boundary effect."
---

# Security review

Read [AGENTS.md](../../../AGENTS.md), the affected package contract and public
consumer. Identify the protocol peer or supplied document, caller principal,
credential source, execution owner and protected resource. WoTEx supplies generic
protocol mechanics; consumers retain product policy and physical authority.

Follow the selected TD/profile/frame through decoding, canonical values,
credential selection, transport or implementation admission and returned output.
Compare parser/collection/work limits and normalization at actual handoffs.
A security scheme declaration is not authentication, and a valid value cannot
grant an operation or physical command.

For [Directory authorization](../../../packages/wotex-directory/lib/wotex/directory/authorization.ex),
check admission before repository access, including reads, expiry and errors.
For Runtime credentials, subscriptions or admitted implementations, load the
existing transport-lifecycle, implementation-custody or directory-operations
skill as relevant. Review async revocation, deadline/cancellation, redaction and
owner retirement through the actual port implementation.

Inspect the affected public refusal and malformed-input tests. Use
[monorepo-workflow](../monorepo-workflow/SKILL.md) to select package checks;
archive-validation applies only when artifact compatibility is in scope.
Do not run every package, native containment lane or live protocol/device merely
because this skill was selected. Physical and standards qualification remain
their own evidence tiers.

## Scope, evidence and execution

For the requested review, record the revision and relevant working-tree changes,
checked entry/control/effect paths and deferred or excluded areas. A focused
review does not require a whole-repository audit.

Establish each claim against the strongest current control and owning contract.
Confirmed findings need a complete reachable boundary trace and evidence for
the stated consequence. Keep decisive unobserved facts as `needs_validation`,
with the exact missing check and no severity; reject disproved claims.
Distinguish source inspection, inspected tests, executed local tests and live
evidence. Group duplicate root causes and recheck previous findings against
current source and conditions.

Use the existing validation owner for authorized dummy-data regressions.
Executing untrusted code or hostile native/availability checks requires verified
OS isolation, no external networking, a sanitized environment and resource/time
limits. If unavailable, leave that execution unverified and continue source
review. A review grants no live/provider operations or agent-permission changes.
Independent verification is conditional on authorized, available delegation;
otherwise state the single-reviewer limit. Return findings in chat unless the
requested deliverable and repository contract permit a report.

Audit-method background: [Cloudflare's source-first workflow](https://github.com/cloudflare/security-audit-skill/tree/c1c8a8c1471069fb0e188eeaff69b8e8db6564a8/skills/security-audit).
