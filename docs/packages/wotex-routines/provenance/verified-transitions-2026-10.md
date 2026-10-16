# Verified direct point transitions

Recorded: 2026-10-16. Scope: bounded native point-relation evidence only.
Source parent: `9896eb2d`; the complete byte identities below bind the new
implementation and checks before their owning commit. The accepted
[contract](../specs/verified-decision-v1.md) retains the complete Collection,
Decision, independent-oracle and archive obligations.

| File | SHA-256 of complete bytes |
| --- | --- |
| `packages/wotex-routines/lib/wotex/routines/transition.ex` | `f486104bf36df714e507969c2112d7436d044dde010a478cffb90299ab7aaf4c` |
| `packages/wotex-routines/lib/wotex/routines/transition_checks.ex` | `b528b64580ca1c2a3e3897e64d9afcf6ab2cc51fb785743fc6b7cb446fa9c502` |
| `packages/wotex-routines/lib/wotex/routines/transition_edge.ex` | `13678cac59d5a89dfe7d5c3eb54c16e316b64028b3c5a2707c7b50457bc8a95c` |
| `packages/wotex-routines/lib/wotex/routines/transition_observation.ex` | `838b0086bff439c10ed0c6ae83cce070d2f55135a1f642908047a23ab307718c` |
| `packages/wotex-routines/lib/wotex/routines/transition_receipts.ex` | `82befd7574af9392bfbf4eabeac0c92f329ed58e75ae4f2a2547d4947d9efafa` |
| `packages/wotex-routines/lib/wotex/routines/transition_run.ex` | `f45d26d0fea35452f4e160a232ca8113feef908e6baafdeffbd86fb61891d19e` |
| `packages/wotex-routines/lib/wotex/routines/transition_tree.ex` | `44115d1184e18815fad423ba3725e5a17903665a8958d11b79c1db65bcd4d925` |
| `packages/wotex-routines/test/wotex/routines/transition_test.exs` | `661bbb578f884136cae5ac28e298b0d4f7c4aa01cc881519a68ab7f383f9d4c9` |
| `packages/wotex-routines/bin/check_transition_corpus.exs` | `1e3def22a517aaa6ddb54994e4618ce5a272c50445563bf0b0eb74c67649bf08` |

The selected local lane is Elixir 1.20.2 and OTP 29.0.4 from mise.toml.
The root runner explicitly selects WOTEX_PATH_DEPS=1 with the existing package
lock. No dependency pin, release or consumer selection changed.

## Executed native checks

Run from the repository root through `mise exec --`:

```text
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs --mutant receipt_relation
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs --mutant tree_motion
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs --mutant point_basis
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs --mutant proposal_set
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs --mutant edge_fields
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs --mutant old_step_expiry
mix pkg wotex-routines format --check-formatted 'lib/wotex/routines/transition*.ex' test/wotex/routines/transition_test.exs bin/check_transition_corpus.exs
mix pkg wotex-routines compile --warnings-as-errors
mix pkg wotex-routines credo --strict --files-included 'lib/wotex/routines/transition*.ex' --files-included test/wotex/routines/transition_test.exs --files-included bin/check_transition_corpus.exs
mix dialyzer.pkg wotex-routines
mix pkg wotex-routines run --no-start --no-compile bin/check_boundary.exs
mix docs.pkg wotex-routines --warnings-as-errors
```

The isolated corpus passes 113 tests in 17.4 seconds. Its ten owning files are
kernel, edge, satisfaction, receipt_deadline, continuation, pending_collection,
time_basis, input_execution, correspondence and transition tests. Twelve new
Transition cases cover both Time grammars, instruction forms, retained starts,
removal/expiry/cancellation, ordered receipt and duplicate history, failed or
unknown results, parallel stopping, busy/no-hidden-original refusal, edge
baseline/qualification forgery, forged native values, every scalar result leaf,
rehashed receipts, plausible changed motion and exact aggregate byte bounds.

All eight forbidden-call guards are first explicitly probed and must refuse
before execution: Kernel.advance/7, Execution.advance/6, Edge.advance/7,
Receipt.apply/4, Satisfaction.apply/7, Pending.paths/5, Collection.evaluate/3
and Collection.to_map/3. Fixture preparation may run the forward code outside
proof. Every successful prepared Kernel result is then passed through the
public Transition checker with all guards enabled; every successful direct
Edge result also checks its independent relation and eligibility under them.
This is differential native evidence against the existing forward corpus;
it does not replace the required independent raw-source/archive oracles.

| Checked point coordinate | Actual count |
| --- | --- |
| Complete point relations | 1,152 |
| Run@1 / Run@2 / nil Run | 1,052 / 87 / 13 |
| Time@1 / Time@2 | 1,087 / 65 |
| Admission / handoff / result / satisfied events | 51 / 35 / 43 / 30 |
| Manual / resume / cancel / fact / due / elapsed_due | 604 / 352 / 9 / 15 / 9 / 4 |
| Running / blocked / completed / expired | 958 / 26 / 39 / 67 |
| Cancelled / failed / unknown / partial / refused | 25 / 9 / 7 / 7 / 1 |
| No-edge / skipped-busy | 10 / 3 |
| Direct Edge@1 / Edge@2 relations | 66 / 6 |
| Explicit combined-envelope bound refusal | 1 |

The one envelope refusal is counted separately from successful proofs and is
independently checked against all eight complete arguments, including repeated
embedded input/result copies. It is not a skipped test or silent limit increase.
The full suite requires zero assertion, runtime, setup or invalid-test failures,
zero skipped/excluded tests and a received formatter result.

Strict Credo reports no issues across 124 source files; format, compilation and
consumer-boundary checks pass. Cached package Dialyzer passes with zero errors,
skips or unnecessary skips. ExDoc builds with warnings treated as errors;
generated documentation is removed in a finally block, while preexisting
incremental docs build caches are retained. The first type pass exposed two overly broad
helper return ranges; an explicitly error-only refusal helper resolves them
without widening the public result or changing behavior. The corpus/mutation
harness was also corrected to count a forged-basis rejection as an assertion
rather than a bare match error; only the final results below are evidence.

## Isolated mutation results

Each command above recompiles exactly one selected AST expression in one
checker module in memory, preserving every source and built BEAM file. A fresh
VM runs the actual twelve Transition tests with the same eight guards. Only
ExUnit.AssertionError failures count as catches; all other failures, setup or
compiler/loader failures invalidate the probe. The selected expression count
must be exactly one. Results are:

| Mutant | Assertion failures | Harness errors | Executed tests |
| --- | --- | --- | --- |
| receipt_relation: bypass exact receipt-map relation | 1 | 0 | 12 |
| tree_motion: bypass retained start/deadline/selection motion | 1 | 0 | 12 |
| point_basis: bypass full normalized point basis | 1 | 0 | 12 |
| proposal_set: bypass complete ordered new proposals | 2 | 0 | 12 |
| edge_fields: bypass changed edge-state conclusion | 1 | 0 | 12 |
| old_step_expiry: omit prior effect/invoke deadline expiry | 1 | 0 | 12 |

These direct native mutants are distinct from VD-T13's required complete-decision
mutations in two extracted consumers. No full VD-T case is closed by this record.

## Limits and cleanup

The public API certifies supplied historical point correspondence. It supplies
no current membership, source/clock authenticity, transaction, admission or
physical permission. Complete Collection@2 verification, public Decision APIs,
independent full arbitration, raw-source/all-pairs oracles and extracted-archive
verification remain open. Frozen Model/Analysis profiles remain unchanged.
The broad package gate, coverage floor and new archive consumers are reserved
for the complete verifier milestone.

The corpus and mutants produce no archive, extracted dependency, Docker object,
mutation directory or overwritten BEAM/source. Instrumentation, ETS and mutated
modules exist only in short-lived VMs; the ETS table is deleted on completion.
Existing locked dependencies, incremental builds and cached PLTs are retained.
