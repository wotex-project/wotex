# Source decision oracle preflight

Recorded: 2026-10-16. Scope: local native preflight only, before archive extraction.
Source parent: `6333e748`. The byte identities below bind the three new sources
before their owning commit. The [frozen archive profile](../decisions/verified-decision-archive-profile.md)
retains both complete archive families, cohort identity and mutation obligations.

| File | SHA-256 of complete bytes |
| --- | --- |
| `packages/wotex-routines/test/support/archive/decision_inputs.exs` | `290d1492e7ab82e599badbe44d764e629f2bf021fa1b2ee68b0c4fe2a3629109` |
| `packages/wotex-routines/test/support/archive/decision_source_oracle.exs` | `2a40fe283bcf1cea0d6b13fc63123254ec9af565bb768cb1350e2972ed339e3e` |
| `packages/wotex-routines/test/support/archive/decision_source_consumer.exs` | `cba46bf172b55b586e0427991f297d211943a8182f0fb79031cd0177266d3fb8` |

Executed from the repository root through `mise exec --` on Elixir 1.20.2 and
OTP 29.0.4 with the existing package lock and explicit WOTEX_PATH_DEPS=1:

```text
mix pkg wotex-routines format test/support/archive/decision_inputs.exs test/support/archive/decision_source_oracle.exs test/support/archive/decision_source_consumer.exs
WOTEX_ROUTINES_COMPILER_BASIS=sha256:7777777777777777777777777777777777777777777777777777777777777777 mix pkg wotex-routines test test/support/archive/decision_source_consumer.exs
mix pkg wotex-routines credo --strict --files-included test/support/archive/decision_inputs.exs --files-included test/support/archive/decision_source_oracle.exs --files-included test/support/archive/decision_source_consumer.exs
```

All seven source-family cases pass in 35.8 seconds with no skipped/excluded
cases. Strict Credo finds no issues across 134 source files. The compiler basis
above is an explicit synthetic preflight input; it is not a built archive hash,
release identity or selected consumer dependency. Tests run against the current
native development cohort, not an extracted archive.

## Independent expected behavior

DecisionArchiveInputs supplies synthetic declarations and prepares public
Kernel/Collection/Arbitration claims. It contains no expected eligibility, cell,
conflict or charge algorithm. DecisionSourceOracle derives complete expected
initial and ordinary retained transitions from raw source/definition trees and
oracle-owned previous records, including full basis, paths, original identities,
starts/deadlines, branches, unchanged fields, receipt slots and ordered proposals.
Its ordinary source evaluator explicitly refuses unsupported terminal, expired,
changed-basis and retained-window traces; receipt/stop traces have separate
explicit owned expectations rather than a silent approximation.

The source oracle imports no production execution, qualification, tree, pending,
transition, cell or arbitration helper. Public canonical JSON and SHA-256 supply
only representation identities. It independently compares every conflict pair
using full equality signatures. It never uses a production result to decide its
expected motion, clock boundary, no-repeat history, contributor or conflict count.
The seven cases map to the frozen profile as follows:

- VDA-T1: sixteen complete fresh relations across both Time grammars, covering
  noop, effect, sequence, wait, parallel, fixed/unknown conditional and invoked
  conditions; a delayed resume retains its original start. Full-record equality
  and altered basis/motion refusal are explicit.
- VDA-T2: exact held/duplicate/handoff/failure/unknown/satisfaction records,
  terminal restoration, cancellation and a constructor-valid coherent refund
  forgery. A late completion preserves its charge while expiry stops the dependent
  path. A separate unstarted child isolates the earlier invocation deadline.
- VDA-T3: full independent Edge@1/@2 baseline and qualified rising fields,
  replacement/unqualified reset and a shape-valid false baseline refusal.
- VDA-T4: complete negative delay, wait, Fact expiry and UTC-window cuts, inside/
  at-boundary checks, rehashed cell narrowing/widening and member omission.
  Fresh calculation retains the original short delay start and then conflicts.
- VDA-T5: independently derived complete proposals and retained reserved
  contributors; twelve policy/batch combinations use the all-pairs oracle.
  The 64-member/1,024-pending matrix includes the final supplied contradiction:
  32 conflicts, sixteen selected groups and 736 deferred contributors. A separately
  compiled 1,023 cohort of valid direct points refuses at the aggregate bound.
- VDA-T6: source-time cuts from raw timestamp/uncertainty/freshness declarations,
  both confidence endpoints moving in both directions, relevant presence/basis
  changes and irrelevant UTC replacement/loss. Current input and both Times
  remain explicit and historical transitions unchanged.
- VDA-T7: closed/native wrappers, omitted fields, extra authority labels,
  Collection@1 and frozen complete-pending Model scope refuse. All four public
  Decision argument envelopes have exact/one-under byte cases with fresh Programs
  for each selected Limits value; the larger constructor output is also counted.

A newly added window trace initially exposed an extra kind field in the oracle's
expected retained window. The owning closed window contract excludes it; the
oracle was corrected and the complete seven-case preflight rerun. This was an
oracle correction, not a producer behavior change or archived mutation catch.

## Limits and cleanup

No extracted consumer, archive, cohort identity check or semantic mutation was
executed for this scope. The separate journal oracle, opt-in archive runner,
both eight-case extracted projects, all twelve mutation runs and the owning
verifier milestone remain required. No full VD-T1–T14 case is closed by this
native preflight. Current consumer admission, installed clocks/source custody,
Model/Analysis scope and physical authority remain separate.

No Docker resource, disposable filesystem workspace, generated documentation or
archive was created. ExUnit loads these helper modules in memory; reusable
locked dependencies/build/PLT caches are retained. No release, dependency pin,
remote ref or repository visibility changes.
