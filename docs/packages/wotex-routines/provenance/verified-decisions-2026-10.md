# Complete native decision verification

Recorded: 2026-10-16. Scope: native correspondence for provided membership only.
Source parent: `83055631`; the complete byte identities below bind the new
implementation/tests/lane and its reused assertion/runtime formatter before the
owning commit. The accepted [decision contract](../specs/verified-decision-v1.md)
retains the full independent archive/mutation and milestone obligations.

| File | SHA-256 of complete bytes |
| --- | --- |
| `packages/wotex-routines/lib/wotex/routines/decision.ex` | `ab061f2bd46a7934a72c7784921349e716d22cd8515b81202f648fcb15256dbc` |
| `packages/wotex-routines/lib/wotex/routines/decision_arbitration.ex` | `5fa8924078fd3fe381df998407db2a0d5648f19d448447a6c048bcd2b1676d7f` |
| `packages/wotex-routines/lib/wotex/routines/decision_collection.ex` | `15dd0644e3df5813c72e663ec9805a252bbc65005b2471e217cc534f55401ac9` |
| `packages/wotex-routines/lib/wotex/routines/decision_pending.ex` | `239dd2d478f655602340467de18de7785b6355bc7877f6f5b9118e5e9f75c6ec` |
| `packages/wotex-routines/test/wotex/routines/decision_test.exs` | `a1f763f2faee0b8c22d6853839c220b9685c7c54e723a4d1d379da1db23d8540` |
| `packages/wotex-routines/test/support/decision_fixtures.exs` | `06e55d2211e8274455d135acd8d37c8e2a05e51cd832eb75a78aac5b21f35ea0` |
| `packages/wotex-routines/test/support/decision_reference.exs` | `c4584efab2491fe09414516c6ba01deb154ac1047ce11800d0157f4ea7ddcb4b` |
| `packages/wotex-routines/bin/check_decision_corpus.exs` | `507c0524f4cc2d3a6a3b10e8af9b1c9f0fdf0bfc1de40af65459de6ca3277d69` |
| `packages/wotex-routines/bin/check_transition_corpus.exs` | `1e3def22a517aaa6ddb54994e4618ce5a272c50445563bf0b0eb74c67649bf08` |

The selected local lane is Elixir 1.20.2 and OTP 29.0.4 from mise.toml.
The root runner explicitly selects WOTEX_PATH_DEPS=1 and existing package locks.
No dependency selection or release changes. Historical direct point and internal
cell evidence retain their own source-bound records.

## Executed native lane

Run from the repository root through `mise exec --`:

```text
MIX_ENV=test mix pkg wotex-routines compile --warnings-as-errors
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs
mix pkg wotex-routines format --check-formatted 'lib/wotex/routines/decision*.ex' test/support/decision_fixtures.exs test/support/decision_reference.exs test/wotex/routines/decision_test.exs bin/check_decision_corpus.exs
mix pkg wotex-routines credo --strict --files-included 'lib/wotex/routines/decision*.ex' --files-included test/wotex/routines/decision_test.exs --files-included test/support/decision_fixtures.exs --files-included test/support/decision_reference.exs --files-included bin/check_decision_corpus.exs
mix dialyzer.pkg wotex-routines
mix pkg wotex-routines run --no-start --no-compile bin/check_boundary.exs
mix docs.pkg wotex-routines --warnings-as-errors
```

The final isolated lane passes fifteen new Decision cases in 21.7 seconds and
26 existing pending_collection/time_basis cases in 35.2 seconds. Both phases
require their exact test count, zero failures/skips/exclusions, a received
formatter result and zero assertion/runtime/setup/invalid-test errors. Every
proof disables these nine forward seams: Kernel.advance/7, Execution.advance/6,
Edge.advance/7, Receipt.apply/4, Satisfaction.apply/7, Pending.paths/5,
Collection.evaluate/3, Collection.to_map/3 and Arbitration.decide/5. All guards
are explicitly probed and must raise before entering the forward function.

The first phase calls all four public Decision APIs under the guards, including
malformed, rehashed, stale and exact-bound inputs. The second phase instruments
existing successful v2 Collection evaluation and Arbitration results: fixture
preparation runs outside proof, then verify_point/new/to_map or new/check runs
under all guards. It checks exactly 70 complete collections and seven full
arbitration relations; those counts are enforced, not inferred from test names.
All source instrumentation is compiled in memory, grouped by source file so
both Collection functions retain their guards. No production BEAM is overwritten.

The lane also validates six actual public decision/current-context/checked maps
against the frozen offline schema across both Time grammars. This is separate
representation evidence; these shapes do not establish authority or completeness
of actual host membership. The native scope covers:

- Exact independently supplied point input, membership/ordering, shared snapshot
  identity/resources/observations, and aggregate active/pending bounds.
- Every supplied transition, full eligible proposed/reserved set and one-to-one
  states, including retained originals and nil/displaced-live-history refusal.
- Canonical cell/digest regeneration, rehashed narrowing/widening and omitted
  members/records/proposals/states; no repaired result.
- Complete current non-time equality, including integer versus numerically equal
  floating Fact changes; first-stage point/input/time/arbitration refusals.
- Negative delayed membership crossing the whole cell, fresh retained starts,
  elapsed regression/epoch/generation/grammar changes, relevant UTC endpoints,
  generation/loss, and irrelevant UTC loss/replacement.
- Reserved equivalents retain every contributor and their unchanged charged
  transitions; full selection confers no new admission or repeated handoff.
- Exact/one-under bytes for all four public argument envelopes, plus the new
  decision output where it is the larger bound. Each changed Limits selection
  recompiles its actual Program; no mismatched compiler basis or widened bound
  can masquerade as a JSON-bound check.

## Independent all-pairs arbitration oracle

`test/support/decision_reference.exs` imports no production checker, grouping,
qualification, pending or arbitration helper. It evaluates policy on raw proposal
fields, groups by full tuple equality through list scans, compares every group
against every other group, and labels contributors before applying the cutoff.
The production checker instead uses full-signature/resource indexes and consumes
claimed groups/decisions. No hash shortcut stands in for full equality.

The native policy matrix exercises 81 deterministic four-contributor policy
assignments at batch limits one and three: 162 oracle comparisons, including
constraint refusal/unknown, explicit/selected/suppressed overrides, equivalent
contributors and contradictory selected overrides. Eighteen of those combinations
also traverse the full public current-decision check; forged selected/decision
lists are checked through the public seam for every combination.

The capacity case supplies 64 sixteen-effect members and all 1,024 pending
originals/states. Its final supplied member contradicts the first member's
resource domain. An independently computed all-pairs result is checked by the
public API: 32 contributors conflict, sixteen groups are selected and 736
contributors are deferred. A separately recompiled pending_work=1,023 cohort
contains independently valid direct points but refuses at the aggregate bound.
A similarly prepared two-live-run cohort under active_runs=1 refuses its bound.
This native oracle does not replace the required raw-source or journal-style
extracted consumers and their isolated semantic mutations.

## Evidence limits and cleanup

The full VD-T1–T14 obligations remain open. Independent raw-source/journal archive
consumers, complete-verifier mutations, broader integer/depth/node/string/collection
boundary matrices, full package gate and coverage milestone are not claimed by
this record. Earlier point/cell native mutations retain their narrower scope.
No new archive, host/native packaging or physical lane was executed here.
Frozen Model/Analysis profiles and consumer authority remain unchanged.

Formatting and compilation with warnings treated as errors pass. Strict Credo
reports no issues across 131 source files; cached package Dialyzer passes in
1.55 seconds with zero errors/skips. The consumer-boundary check and ExDoc with
warnings treated as errors pass. Broader package gates remain at the milestone.

The lane produces no temporary source/build directory, archive, extracted
package, Docker resource or overwritten BEAM. Its ETS table is deleted and
instrumented modules disappear with the VM. Existing locks, incremental builds
and cached PLTs are retained. Generated documentation from the owning check is
removed after verification; no general cache or Docker-volume pruning occurs.
