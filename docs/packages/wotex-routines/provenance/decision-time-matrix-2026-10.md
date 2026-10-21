# Public Decision time-matrix evidence

Recorded: 2026-10-21. Scope: native software evidence for VD-04–06 and parts
of VD-T5/T7. Repository commit:
`ce9ccb8320dd878314aced1902fec6398eb05277`.
Package path: `packages/wotex-routines`.

The [accepted decision contract](../specs/verified-decision-v1.md) still owns
the full matrix. This addition changes tests and the opt-in corpus runner;
library behavior, public schemas, Profile/Limits and dependency pins do not
change. It does not renew the separate extracted-archive evidence or close
the broader verifier milestone.

## Inputs and independent expectations

The test prepares collections through the public Compiler/Collection APIs,
then exercises Decision.verify_point/4, new/3, to_map/3 and check/4. All expected
cuts are declared from raw fixture constants. The scalar reference partitions
those cuts independently; it neither extracts them from returned Runs nor
imports DecisionCell, production qualification or execution-tree helpers.
Current arbitration comes from the separate all-pairs DecisionReference.
This is independent arithmetic/current-time evidence, not a new independent
oracle for every prepared forward transition.

Nine ExUnit cases cover:

- Fact receipt, inclusive freshness and exclusive expiry at each adjacent
  integer, including an unused binding in a member that emits no proposal;
  its cut invalidates the entire decision despite another selected member.
- Both uncertain source-time endpoints on both sides of both cuts, six literal
  signed/fractional timestamp expectations, relevant UTC presence/generation
  and irrelevant UTC loss/replacement under both Time grammars.
- Retained delay/wait/invocation starts, elapsed and UTC occurrence windows,
  prior debounce and after cooldown including zero debounce, terminal original
  and busy histories, and effect deadlines shorter than the root deadline.
- Zero and maximum elapsed coordinates, 65-bit intermediate sums, and UTC cuts
  outside the selected signed integer domain. Out-of-domain cuts are discarded,
  rather than wrapped or clamped into a new boundary.

Successful current checks retain the exact point Time, transitions and
arbitration, alongside the supplied checked Time. Changed grammar, elapsed
basis, regression or relevant endpoint/cell crossing refuses the entire result
with stale_decision_time.

| Input | SHA-256 of complete bytes |
| --- | --- |
| `bin/check_decision_corpus.exs` | `5f8e3792264df4225573d8d90751d78046d213097be09a574da1103b4dca3954` |
| `test/wotex/routines/decision_time_matrix_test.exs` | `c1b29f21a00d420e23362902ed7a1a3359ec510ff16db92b239ee86c05a82769` |
| `lib/wotex/routines/decision_cell.ex` | `0b2531c95e53410f02eeb3b3e87c2a80d41a1635f8e19771f2978e6717a0bdb4` |
| `test/support/decision_fixtures.exs` | `06e55d2211e8274455d135acd8d37c8e2a05e51cd832eb75a78aac5b21f35ea0` |
| `test/support/continuation_fixtures.exs` | `d3bd09153ffa8679d2bd093226fadd23e42148e3826c96affe26901edd35d694` |
| `test/support/decision_reference.exs` | `c4584efab2491fe09414516c6ba01deb154ac1047ce11800d0157f4ea7ddcb4b` |
| `priv/vectors/wro-01.json` | `ccdb1037baf90790a9f691aa9216a92abd41ad27c6561faedc65042ae3c7881f` |
| `priv/vectors/wro-02-continuation.json` | `524ba1ce16666e0877d2213d2a8203aece4357b79980fc1d45876666628ad86e` |
| `mix.lock` | `13d7c931881badf031fd0baaaea2d783565e291845e14e3050546b178e269b22` |

Paths in the table are relative to the package. The selected local lane is
Elixir 1.20.2 / OTP 29.0.4 on macOS ARM64. The root package runner explicitly
selects WOTEX_PATH_DEPS=1; this is workspace software evidence.

## Executed checks

Commands ran from the repository root:

```text
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs
mix pkg wotex-routines run --no-start bin/check_decision_corpus.exs --time-only
mix pkg wotex-routines format --check-formatted test/wotex/routines/decision_time_matrix_test.exs bin/check_decision_corpus.exs
mix pkg wotex-routines credo --strict --files-included test/wotex/routines/decision_time_matrix_test.exs --files-included bin/check_decision_corpus.exs
mix affected --base 2278f33a --detail
mix wotex.catalogue
mix test test/wotex/workspace/catalogue_test.exs test/mix/tasks/wotex.catalogue_test.exs
mix docs.pkg wotex-routines
mix docs.check
```

The final full corpus passes fifty tests: fifteen existing public Decision
cases, the nine new matrix cases and twenty-six existing complete-pending/clock
cases. All nine prohibited forward seams refuse before execution whenever a
proof is active. The final phase additionally verifies seventy prepared
complete-collection and seven arbitration relations. Six actual public
decision/context/checked outputs pass the frozen schemas across both Time
grammars. Every phase reports zero failures, errors, skips and exclusions.
The final phase times are 26.8, 23.0 and 38.8 seconds. The separate time-only
baseline passes all nine cases in 23.9 seconds.

Formatting passes. Strict Credo checks 140 source files with no issues. The
affected set contains only wotex-routines. Seven root catalogue tests pass;
all links in 558 Markdown files resolve and the generated catalogue is current.
ExDoc generation passes with no ExDoc link warnings. Its dependency compilation
emits yamerl's OTP catch-deprecation warnings and reuses the cached precompiled
ExMaude NIF; no interpreter or native build runs. All nine recorded input hashes
were checked against both the working tree and the named repository commit.
The initial ordinary nine-case test
run exposed an incorrect test expectation for a wide UTC interval; the probe
was corrected to cross the low-endpoint cut, then the final guarded cases and
all mutation runs below passed. No library correction was needed.

## Isolated mutation evidence

For each name below, a fresh package VM executed:

```text
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --time-mutant NAME
```

Each VM installs all nine forward-call guards, applies one exact single-site
in-memory DecisionCell mutation and runs all nine matrix cases. Missing or
ambiguous replacement sites refuse. The runner succeeds only when at least
one ExUnit assertion catches the mutation, every reported failure is such an
assertion, and there are zero harness errors, skips or exclusions. A compile,
loader or runtime error does not count as a catch. No source or BEAM is
overwritten.

| Executed name | Deliberate defect | Assertion failures | Harness errors | Tests executed |
| --- | --- | --- | --- | --- |
| negative_members | Ignore nil/no-proposal members when extracting cuts | 9 | 0 | 9 |
| freshness_inclusive | Remove the freshness comparison's +1 cut | 2 | 0 | 9 |
| expiry_exclusive | Move exclusive Fact expiry to expires_ms + 1 | 3 | 0 | 9 |
| fractional_floor | Truncate signed microseconds toward zero | 3 | 0 | 9 |
| prior_history | Drop original and busy Run cuts | 1 | 0 | 9 |
| utc_high_endpoint | Skip the current UTC high-endpoint comparison | 3 | 0 | 9 |
| elapsed_generation | Skip elapsed generation equality | 1 | 0 | 9 |
| clamp_cuts | Clamp out-of-domain cuts instead of discarding them | 1 | 0 | 9 |

All eight commands return success under those catch criteria. Together they
execute seventy-two mutant test cases with twenty-three assertion failures
and zero harness errors, skips or exclusions. These native arithmetic mutants
are distinct from VD-T13's two archive families and their six complete-verifier
mutations; neither lane substitutes for the other.

## Limits and cleanup

The broader combined VD-T1–T14 matrix, aggregate non-byte/output boundaries,
wider source/receipt/model cases and owning verifier milestone remain open.
Consumer transactions, actual membership/source authenticity, installed clock
qualification and physical effects require their own evidence. No successful
checked decision supplies authorization.

No dependency installation, archive, native build, hardware operation,
benchmark or release task ran. Mutation modules lived only in fresh VMs;
existing dependency/build caches remain. Full package gates and Dialyzer were
not run under the requested focused-check workflow. Existing archive records
retain their original source/artifact identities. This record's inputs must be
rerun, rather than relabelled, if their executable bytes change.
