# Native/source JSON depth evidence

Recorded: 2026-10-21. Repository commit:
`06b0118978198acdefc5f50aa2412e3d7407b7ac`.
Package paths: `packages/wotex` and `packages/wotex-routines`.
Scope: the existing nested-container bound in WTX.01–04 and WTX-C02,
plus the independent Routines resource-bound oracle that consumes this boundary.

## Defect and correction

Native admission counted a container only when visiting its children. It
therefore accepted a final empty object or array one level beyond the selected
depth, while source decoding rejected the equivalent JSON. At the default
limit of 64, a chain of 65 arrays ending in an empty array was accepted by
native validation and encoding. The same gap reached aggregate and value
constructors through extensions.

Container entry now enforces the bound. Every object/array, including an empty
one, adds one level; a root container counts as one and scalars add no level.
Native refusal identifies the overflowing container, rather than its first
child. Source preflight is unchanged. The error/result shapes, signatures and
canonical bytes for values admitted by both versions are unchanged. Previously
admitted native values outside the selected bound are now refused. This is a
pre-release admission correction, with no new standards or stable-API claim.

The admission-safety test helper and independent Routines size oracle also
undercounted empty containers. Both are corrected. Literal expectations for an
empty root object and an object containing an empty array protect the Routines
oracle independently of production JSON code. Routines library code is unchanged.

## Exact inputs

Paths below are relative to the repository. The commit above pins the complete
source cohort, including unchanged Profiles and Continuum implementations and
the four consumer test files. The executed local lane is Elixir 1.20.2 /
OTP 29.0.4 on macOS ARM64, using the explicit WOTEX_PATH_DEPS=1 package runner.
Dependency locks are unchanged.

| Input | SHA-256 of complete bytes |
| --- | --- |
| `packages/wotex/lib/wotex/json.ex` | `257403e75564e10e196f10e9ec228df4308a3633aca8a71256b98c119b7f4b44` |
| `packages/wotex/lib/wotex/json/limits.ex` | `a12ec9b836c1835d0785983d2093212fd391e0b62143312cea6fc1940c0efb87` |
| `packages/wotex/test/wotex/json_depth_test.exs` | `5991b1e3c8e03d573af25dbcb226b81645513bc4c1234ad63707cb3a0fe9ed37` |
| `packages/wotex/test/wotex/admission_safety_test.exs` | `d2499ce562a1abcae4ef7abfbd5a7564eb02cdd4aa452e67af8c11ef7bf8c400` |
| `packages/wotex/mix.lock` | `34595fc91c1a5d58b8c2f70e215e02993f57244e1e5b9af07c1efe12228ce50f` |
| `packages/wotex-routines/test/support/decision_bound_reference.exs` | `e2ed1c8a249945bb98408ed19509554add49b359e2b246b2241dc4d60648d8dc` |
| `packages/wotex-routines/test/wotex/routines/decision_bounds_test.exs` | `a1dd431ba073a39a3f5c2e75a22d5f165c880ab4bd2d6b5c0228c145551a3b57` |
| `packages/wotex-routines/bin/check_decision_corpus.exs` | `df4276dd1978433bfa2edf82172419837a4323e66232e0dd8e92613227ccd778` |
| `packages/wotex-routines/mix.lock` | `13d7c931881badf031fd0baaaea2d783565e291845e14e3050546b178e269b22` |

## Executed checks

From the repository root:

```text
mix pkg wotex deps.get --check-locked
mix pkg wotex test test/wotex/json_depth_test.exs
mix pkg wotex test
mix pkg wotex-routines run --no-start bin/check_decision_corpus.exs --bounds-only
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-only
mix pkg wotex format --check-formatted lib/wotex/json.ex lib/wotex/json/limits.ex test/wotex/json_depth_test.exs test/wotex/admission_safety_test.exs
mix pkg wotex-routines format --check-formatted test/support/decision_bound_reference.exs test/wotex/routines/decision_bounds_test.exs
mix pkg wotex credo --strict --files-included lib/wotex/json.ex,lib/wotex/json/limits.ex,test/wotex/json_depth_test.exs,test/wotex/admission_safety_test.exs
mix pkg wotex-routines credo --strict --files-included test/support/decision_bound_reference.exs,test/wotex/routines/decision_bounds_test.exs
mix affected --base 7c2f5312 --detail
```

Core dependencies were fetched under the existing lock. The initial focused
run failed four of five cases against the old code. After the fix and final
fixture corrections, the complete core suite passed: six doctests, two
properties and ninety-two tests, with no failures. The five new cases include
108 object/array/mixed chain fixtures, empty and scalar leaves, exact/one-under
depths, escaped paths, siblings, the default 64/65 boundary and an explicit
raised limit. Both aggregates and all six value constructors exercise extension
depth, including `validate: false`; aggregate parsing and identifier mutation
also enforce the selected bound.

The final Routines bounds-only run passed eight cases in 15.7 seconds, with
zero errors, skips or exclusions and all nine prohibited forward seams guarded.
Formatting passed; strict Credo reported no issues in 31 core and 142 Routines
source files. The affected set contains core and Routines as changed packages
and fifteen dependents; this selection is not evidence that their gates ran.

Two isolated counterfactual VMs compiled the old module bytes from repository
commit `7c2f5312` in memory, then executed the final current tests. Old core
JSON produced four assertion failures among five cases. The old Routines
reference helper produced one assertion failure among eight cases. Both had
zero harness errors, skips and exclusions. No tracked source or BEAM was
overwritten. The temporary invocation/formatter files remain ignored local
execution state.

### Prepared-cohort consumer checks

Initial direct Profiles and Continuum package test invocations stopped at
missing package-local dependencies before executing tests. Their own package
gates are not claimed. The prepared Routines development cohort already
contained core, Profiles and Continuum. It executed the following unchanged
source files, after requiring the Profiles fixture module:

- `packages/wotex-profiles/test/wotex/reader_test.exs`;
- `packages/wotex-profiles/test/wotex/compiler_test.exs`;
- `packages/wotex-continuum/test/wotex_continuum/codec_test.exs`; and
- `packages/wotex-continuum/test/wotex_continuum/admission_parity_test.exs`.

The actual command was:

```text
mix pkg wotex-routines run --no-start --no-compile ../../docs/tasks/local/wotex/json-depth-consumers.exs
```

Its ExUnit harness loads those four source files without stubs and runs with
seed zero. All 43 tests passed in 0.07 seconds, with zero failures, skips or
exclusions. This is a prepared-cohort source consumer check, not extracted
archive adoption or either owning package's full gate.

### Current resource-bound fault checks

Each command below runs eight cases in a fresh VM against the current corrected
core and reference helper. Mutations are compiled in memory. At most two VMs
ran concurrently; every VM completed before the results were recorded.

```text
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant argument_envelope
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant certificate_output
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant encoded_bytes
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant depth_selection
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant node_selection
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant string_selection
mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs --bounds-mutant collection_selection
```

| Fault | Assertion failures |
| --- | --- |
| Ignore the complete argument envelope | 4 |
| Admit only the certificate format instead of its complete output | 2 |
| Ignore encoded byte length | 2 |
| Replace selected depth with the default | 1 |
| Replace selected node count with the default | 2 |
| Replace selected string size with the default | 2 |
| Replace selected collection width with the default | 1 |

All seven faults were caught through 14 assertion failures, with zero harness
errors, skips or exclusions. A successful fault-run exit means the expected
assertion failure was detected; it is not an ordinary green test suite.

### Documentation checks

```text
mix wotex.catalogue
mix test test/wotex/workspace/catalogue_test.exs test/mix/tasks/wotex.catalogue_test.exs
mix docs.pkg wotex
mix docs.check
```

The generator rendered 103 specifications; all seven catalogue tests passed.
Core ExDoc generation passed, and all 559 repository Markdown files passed link
checks with the generated catalogue current. Locked Yamerl dependency
compilation emitted deprecated-`catch` warnings on OTP 29; ExDoc reported no
documentation warnings.

## Limits of this evidence

The full package/dependent gates, Dialyzer, Dexter indexing/reference checks,
archive consumers, native qualification, benchmarks, interoperability and
containment lanes were not run. Core test tooling compiled its locked file
watcher dependency; that compilation is not native qualification evidence.
No maximal-resource latency or peak-memory claim follows from structural bounds.

The earlier Routines resource-bound receipt remains historical at its recorded
commit; its depth oracle was incomplete for empty containers. The current
eight-case baseline and seven fault checks above renew only this bounded
resource slice. The full 58-case verifier corpus, time faults, archive adoption
and wider verifier milestone are not requalified by this record. Consumer
authority, installed clocks, host transactions and physical effects remain
separate obligations.
