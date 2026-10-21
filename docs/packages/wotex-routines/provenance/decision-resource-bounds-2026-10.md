# Public verification resource-bound evidence

Recorded: 2026-10-21. Repository commit:
`0cf2c1e7a02585851dc2c1447a89d238003d359b`.
Package path: `packages/wotex-routines`. Scope: native JSON-bound evidence
toward VD-01/08 and VD-T10 in the
[verified-decision contract](../specs/verified-decision-v1.md).

Historical scope: a later core admission and reference-oracle correction for
empty-container depth is recorded in the
[native/source depth evidence](https://github.com/wotex-project/wotex/blob/main/docs/packages/wotex/provenance/json-depth-parity-2026-10.md).
This receipt's original source identities and results remain unchanged. Its
oracle was incomplete for empty containers; the later receipt renews the
eight-case bounds slice and seven faults, not this full historical corpus.

Tests and the opt-in corpus runner change. Library behavior, public schemas,
Profile/Limits, dependency pins and archive consumers do not change. No
production defect was found in these executed cases. The full combined verifier
milestone, complexity/resource qualification and consumer authority remain open.

## Independent oracle and complete envelopes

DecisionBoundReference measures bytes, nesting depth, value count, per-string
UTF-8 bytes and maximum object/array width from complete native JSON trees.
Its compact sorted-key writer uses Elixir JSON for scalar encoding; it does
not call Wotex.JSON, Validation or production size/decision helpers. Object
keys contribute string bytes and width, while every JSON value, including each
container and repeated embedded copy, contributes a node. There is no subtree
deduplication. Original fixture preparation uses public Compiler/Collection
APIs and the existing independent all-pairs arbitration oracle.

The test rebinds the explicit selected Limits in every retained copy and
independently refreshes only the enclosing collection/decision digests. Source,
IR, proposal identities, Run/Edge states and time cells remain fixed; explicit
Limits in the retained program/basis copies are rebound. Exact public
success verifies that this preparation preserves correspondence. Undersized
fixtures require no production constructor to accept the undersized result.

Eight ExUnit cases exercise:

- All five JSON limit axes through Transition.verify/8 and Decision's
  verify_point/4, new/3, to_map/3 and check/4. Each checks exact and one-under
  selections for native and plain arguments, across both Time grammars and
  relevant-present, relevant-absent and irrelevant UTC cells: 300 exact/under
  pairs in the five matrix cases. Success retains the complete expected output;
  an exceeded selection returns a payload-free limit_or_json_error.
- Combined node overflow through every operation while each separately supplied
  argument fits. Repeated source/program/input/prior copies all count.
- A certificate whose encoded output exceeds its independently fitting input.
  Decision.new/3 refuses the one-under output budget after point verification;
  no partial certificate is returned.
- A synthetic source identity with 80 characters, 100 UTF-8 bytes and 162 bytes
  in its escaped JSON string. All operations accept 100 and refuse 99 for the
  string limit. The width matrix includes nineteen complete members before a
  one-group arbitration cutoff and both array and object maxima.

These are bounded JSON/correspondence cases, not an independent oracle for
every source transition or a benchmark of maximal Cartesian input products.

## Exact inputs

All table paths are relative to the package. The complete repository revision
above also pins the unchanged sibling source cohort. The selected local lane
is Elixir 1.20.2 / OTP 29.0.4 on macOS ARM64, with WOTEX_PATH_DEPS=1 explicitly
selected by the root package runner.

| Input | SHA-256 of complete bytes |
| --- | --- |
| `bin/check_decision_corpus.exs` | `df4276dd1978433bfa2edf82172419837a4323e66232e0dd8e92613227ccd778` |
| `test/wotex/routines/decision_bounds_test.exs` | `ede7d687e79e5ade6d06455351f8845705420ed99d36ebe7948f5633029b8ae6` |
| `test/support/decision_bound_reference.exs` | `0c8495186a1f68773ce4e85353325c229a1e41fb96948d9cc4438368bcbaf1a7` |
| `lib/wotex/routines/decision.ex` | `ab061f2bd46a7934a72c7784921349e716d22cd8515b81202f648fcb15256dbc` |
| `lib/wotex/routines/validation.ex` | `419a35d945d3267aa7e158a29a41beba147f066f87089fce6d2fc72d13b153c1` |
| `lib/wotex/routines/limits.ex` | `f76e169623a26b7c8dbae771f3b97901a11caa174dc4d69639daedc32f2e96a6` |
| `test/support/decision_fixtures.exs` | `06e55d2211e8274455d135acd8d37c8e2a05e51cd832eb75a78aac5b21f35ea0` |
| `test/support/continuation_fixtures.exs` | `d3bd09153ffa8679d2bd093226fadd23e42148e3826c96affe26901edd35d694` |
| `test/support/decision_reference.exs` | `c4584efab2491fe09414516c6ba01deb154ac1047ce11800d0157f4ea7ddcb4b` |
| `test/wotex/routines/decision_time_matrix_test.exs` | `c1b29f21a00d420e23362902ed7a1a3359ec510ff16db92b239ee86c05a82769` |
| `priv/vectors/wro-01.json` | `ccdb1037baf90790a9f691aa9216a92abd41ad27c6561faedc65042ae3c7881f` |
| `priv/vectors/wro-02-continuation.json` | `524ba1ce16666e0877d2213d2a8203aece4357b79980fc1d45876666628ad86e` |
| `mix.lock` | `13d7c931881badf031fd0baaaea2d783565e291845e14e3050546b178e269b22` |

## Executed checks

From the repository root:

```text
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-only
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs
mix pkg wotex-routines format --check-formatted test/support/decision_bound_reference.exs test/wotex/routines/decision_bounds_test.exs bin/check_decision_corpus.exs
mix pkg wotex-routines credo --strict --files-included test/wotex/routines/decision_bounds_test.exs --files-included test/support/decision_bound_reference.exs --files-included bin/check_decision_corpus.exs
mix affected --base 2ba55c2b --detail
mix wotex.catalogue
mix test test/wotex/workspace/catalogue_test.exs test/mix/tasks/wotex.catalogue_test.exs
mix docs.pkg wotex-routines
mix docs.check
```

The final eight-case bounds-only run passes in 15.3 seconds. The final complete
corpus passes 58 tests: fifteen existing public Decision, nine independent time,
eight bounds and twenty-six existing complete-pending/clock cases. Every phase
has zero failures, harness errors, skips and exclusions. Their times are 26.0,
27.0, 16.3 and 39.0 seconds. All nine prohibited forward seams refuse before
execution during proof. The last phase additionally checks seventy prepared
complete collections and seven arbitration relations; six actual public
decision/context/checked outputs pass the frozen schemas across both Time
grammars. The earlier eight-case single-cell baseline also passed before the
matrix was expanded to all six clock-cell alternatives.

Formatting and strict Credo pass, with 142 source files checked and no issues.
The affected set contains only wotex-routines. Earlier readability findings in
the new test/reference were corrected before final execution. Seven root
catalogue tests pass; all links in 559 Markdown files resolve and the generated
catalogue is current. ExDoc generation passes with no link warnings. All
thirteen input hashes above match both the working tree and recorded commit.

## Assertion-only fault probes

Each name below ran in its own fresh VM with all nine forward-call guards:

```text
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant NAME
```

The runner requires one exact source replacement, compiles only the mutated
Decision or Validation module in memory, and executes all eight bounds cases.
It succeeds only if an ExUnit assertion catches the defect, every failure is
an assertion and no harness error, skip or exclusion occurs. Compiler, loader
and runtime failures are not catches. Source and stored BEAM files are unchanged.

| Executed name | Deliberate defect | Assertion failures | Harness errors | Tests executed |
| --- | --- | --- | --- | --- |
| argument_envelope | Omit actual arguments from the Decision envelope budget | 4 | 0 | 8 |
| certificate_output | Check only the certificate format, omitting its full output | 2 | 0 | 8 |
| encoded_bytes | Ignore complete encoded byte size after native string-payload admission | 2 | 0 | 8 |
| depth_selection | Replace selected depth with the ceiling | 1 | 0 | 8 |
| node_selection | Replace selected node count with the ceiling | 2 | 0 | 8 |
| string_selection | Replace selected string size with the ceiling | 2 | 0 | 8 |
| collection_selection | Replace selected container width with the ceiling | 1 | 0 | 8 |

All seven commands succeed under those catch criteria: 56 mutant test cases,
fourteen assertion failures and zero harness errors, skips or exclusions.
The separate time and extracted-archive mutation records retain their own
source/runner identities; these bounds probes do not renew those fault runs.

## Remaining scope

The complete VD-T1–T14 matrix and verifier milestone remain open. No claim of
linear worst-case work, memory isolation, arbitrary maximal-document products,
consumer transaction safety, current source/clock authenticity, wider Model
scope or physical authority follows. The selected limits can reject an
aggregate even when its constituents separately fit; no bound is increased,
document truncated or smaller certificate substituted.

No dependency installation, archive, native build, hardware operation,
benchmark or release task ran. Mutation modules existed only in their fresh
VMs. Existing build/dependency caches remain. Full package gates and Dialyzer
were not run under the requested focused-check workflow. Changed executable
inputs require new owning runs, not edited hashes or relabelled old evidence.
