---
name: implementation-custody
description: Change or review Runtime implementation admission, codec execution or caller-supervised task custody when current policy, deadlines, owner loss or returned output can change. Excludes pure value construction and protocol subscription transport.
user-invocable: false
---

# Admitted implementation and codec custody

Input: the affected descriptor/contract/policy basis, execution plan, owner and
observed output or cleanup. Output: an admission-to-retirement trace, concrete
regressions and explicit unresolved execution/cleanup evidence.

Read the Runtime package's [instructions](../../../packages/wotex-runtime/AGENTS.md),
its `Implementation` declarations and the selected codec adapter.
[BEAM execution](../../../packages/wotex-runtime/lib/wotex/runtime/codec/beam/execution.ex)
has a consumer-owned Task.Supervisor and custodian. Trace descriptor identity,
contract/policy revision, verification/registration, instance key, current-input
and clock checks, task startup, output admission and retirement. An earlier
admission or matching digest does not imply the current policy still permits
this subject, instance or output.

Use [admission tests](../../../packages/wotex-runtime/test/wotex/runtime/implementation_admission_test.exs),
[lifecycle tests](../../../packages/wotex-runtime/test/wotex/runtime/implementation_lifecycle_test.exs)
and [BEAM codec tests](../../../packages/wotex-runtime/test/wotex/runtime/codec_beam_test.exs)
for the affected seam. Test revocation/changed basis before execution and output,
one deadline across startup through admission, equality/backward clock refusal,
separate instance identities, overload, malformed/oversized output and redaction.
Construct independent expected values; a plan constructor accepting input is not
proof that an admitted execution observes current authority.

For process changes, coordinate the contested point: suspended supervisor/late
startup, caller death, hung task, startup failure and task retirement. Assert
child supervisor state and the actual observed retirement. `:cleanup_unconfirmed`
means cleanup is unconfirmed, not a successful close; a returned timeout cannot
alone prove the task never entered or that it has stopped. Preserve the current
owner's bounded cleanup ceiling and reject output arriving after its basis/deadline.

These BEAM codecs execute trusted consumer code. A task timeout/kill is not an
untrusted-code sandbox or proof that a stuck native function terminates. Native
bridge custody belongs to its binding/adapter owner. Returned numerical/decoded
values remain inert; no codec can create consumer control or physical authority.
Use [transport lifecycle](../transport-lifecycle/SKILL.md) when the changed seam
is a protocol stream rather than codec execution.

A focused selection is `mix pkg wotex-runtime test test/wotex/runtime/codec_beam_test.exs`;
add the affected admission/lifecycle assertions and actual consumers through
[monorepo workflow](../monorepo-workflow/SKILL.md). Record the selected package,
source/lock/toolchain, runtime instance and exact assertions. Package gates may
fetch/build; guidance-only work uses installed source/metadata checks instead.
