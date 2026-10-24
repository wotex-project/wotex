# Current direct-transition verifier qualification

Recorded: 2026-10-24. Repository commit: `608bbe309a8cf4e875e5c3e460b06f934776637d`.
Package path: `packages/wotex-routines`. Scope: current direct point corpus,
forward-call isolation and the six native verifier faults toward VD-T1–T4.
The [verified-decision contract](../specs/verified-decision-v1.md) retains the
combined milestone and its remaining field-mutation/complexity obligations.

## Runner correction

The mutation entry still required twelve tests after the direct transition
corpus grew to thirteen. A genuine assertion-only catch was rejected because
of that stale count. The runner now requires the complete current thirteen-case
corpus, positive integer failures equal to assertion counts, zero harness errors,
skips and exclusions, and complete count-key sets. Its new Elixir subprocess
regression runs the actual mutation entry against the current tests, so adding
or dropping a direct case without reviewing the count fails ordinary CI.
A separate refusal matrix checks stale/incomplete/malformed counts and errors.

This changes qualification tooling only. Library behavior, public schemas,
dependency pins and source/Run/Time grammars remain unchanged. The original
[direct-transition receipt](verified-transitions-2026-10.md) remains historical.

## Exact inputs

Source paths below are relative to the package. The complete commit also pins
all unchanged sibling and test inputs. The selected lane is Elixir 1.20.2 /
OTP 29.0.4 on macOS ARM64 with the root runner selecting WOTEX_PATH_DEPS=1.

| Input | SHA-256 |
| --- | --- |
| `bin/check_transition_corpus.exs` | `0778e3510529d93f5d142f1520fdad6c71951b7ee958cae71f8a264092006748` |
| `test/wotex/routines/transition_corpus_runner_test.exs` | `c81d6ee73e5e5159742e81fbd9bdd17576d4b7b9723ad8c4ab21b93dc136ccce` |
| `test/wotex/routines/transition_test.exs` | `cd12bf059cb3c0b89b331c531dcc97acad60ee75841bf1ab452d8891e1e8b332` |
| `test/support/source_truth_oracle.exs` | `75fe0bc3e5eeaa88afb3077e20bcd02047cdf2600472d8604e3ce4c7b44d3f2b` |
| `test/support/source_transition_oracle.exs` | `5edc45db12cc628829ebc4abbc6a7bca5d531edb2b257aafb51a844c65902c4c` |
| `mix.lock` | `bb744c6383ce7c98b725e8e34781f9105fdecc60e25e7927331ebfd687faca8c` |

## Executed checks

Commands ran from the repository root with `ERL_FLAGS='+S 4:4'`:

```text
mix pkg wotex-routines test test/wotex/routines/transition_corpus_runner_test.exs
mix check.fast --package wotex-routines
mix check --base 1d17db82
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs
```

The last command also ran separately with each `--mutant` name below.
The two regression tests pass. Fast and full package gates pass 312 tests;
the full gate passes all fifteen tools, 95.3% coverage and Dialyzer. Root
checks pass 439 tests with one intentional exclusion, formatting, strict Credo,
catalogue, links and package boundaries.

The clean-commit unmodified guard corpus passes 114 tests, 1,233 successful
point transitions, 72 direct Edge relations and one combined-envelope bounded
refusal. All eight prohibited forward seams refuse before proof. Explicit
event, outcome, Time and Run cells are counted; no library application or device
is started to obtain this pure Elixir correspondence evidence.

| Fault | Executed direct cases | Assertion failures | Harness errors |
| --- | --- | --- | --- |
| `receipt_relation` | 13 | 1 | 0 |
| `tree_motion` | 13 | 1 | 0 |
| `point_basis` | 13 | 1 | 0 |
| `proposal_set` | 13 | 2 | 0 |
| `edge_fields` | 13 | 1 | 0 |
| `old_step_expiry` | 13 | 1 | 0 |

All six isolated mutation entries exit successfully only after qualifying their
expected assertion failures. There are no skipped/excluded tests or compiler/
loader failures. Deliberate replacements change loaded modules only; no source
or BEAM files, archives, containers or dependency builds are modified.

This renews these direct software cells and fixes their runner. It does not
close the complete shape-preserving/rehashed field-mutation matrix, maximal-work
qualification, wider Model projections or consumer-host adoption. No current
authority or physical-effect claim follows from a verified point.
