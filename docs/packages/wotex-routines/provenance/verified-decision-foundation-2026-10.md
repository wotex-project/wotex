# Verified decision time-cell foundation

Recorded: 2026-10-16. Scope: internal native software foundation only.
Source parent: `187175c8`; the following complete file identities bind the
component and test additions before their owning commit. The accepted
[contract](../specs/verified-decision-v1.md) retains all broader VD obligations.

| File | SHA-256 of complete bytes |
| --- | --- |
| `packages/wotex-routines/lib/wotex/routines/decision_cell.ex` | `0b2531c95e53410f02eeb3b3e87c2a80d41a1635f8e19771f2978e6717a0bdb4` |
| `packages/wotex-routines/test/wotex/routines/decision_cell_test.exs` | `5b9b05fea25a9da298fd132834f8ab5a887ce599001d61c0c9c805bd78c4be17` |
| `packages/wotex-routines/test/wotex/routines/decision_schema_test.exs` | `4c2112b71a606dd460c0aa0a2ee55368864fc8a5424dbcb4f3edb84898b1395d` |

The selected local lane is Elixir 1.20.2 with OTP 29.0.4 from mise.toml.
Dependencies use the package lock and explicit WOTEX_PATH_DEPS=1 selected by
the root package runner. No producer/consumer dependency pin or release changes.

Executed from the repository root through `mise exec --`:

```text
mix pkg wotex-routines test test/wotex/routines/decision_cell_test.exs test/wotex/routines/decision_schema_test.exs test/wotex/routines/continuation_schema_test.exs test/wotex/routines/time_basis_test.exs
mix pkg wotex-routines format --check-formatted lib/wotex/routines/decision_cell.ex test/wotex/routines/decision_cell_test.exs
mix pkg wotex-routines compile --warnings-as-errors
mix pkg wotex-routines credo --strict --files-included lib/wotex/routines/decision_cell.ex --files-included test/wotex/routines/decision_cell_test.exs --files-included test/wotex/routines/decision_schema_test.exs
mix dialyzer.pkg wotex-routines
```

All 35 focused tests pass in 2.1 seconds: seventeen new component cases, five
entry-schema cases and thirteen retained schema/clock cases. The component
tests prepare complete data through public Compiler/Collection APIs and assert
literal independently selected cuts, confidence bounds and no-repeat delay
starts. They do not independently verify those prepared point transitions.
Strict Credo inspected 116 source files and found no issues. Compilation and
format checks pass; cached package Dialyzer finishes in under two seconds with
zero errors/skips. The broad package gate, coverage floor and archive consumers
are reserved for the complete verifier milestone.

## Isolated native mutation probes

For each row, a fresh MIX_ENV=test package VM runs `mix run --no-start
--no-compile -e CODE`. CODE compiles only one mutated DecisionCell from an
in-memory source string with ignore_module_conflict selected, starts ExUnit
with autorun false, loads the actual decision_cell_test.exs and runs all
seventeen cases. A formatter counts failed test events: only
`{:error, %ExUnit.AssertionError{}, stack}` is a catch; any other failure is a
harness error. Compilation/loader/process failures also fail the probe.
The original source and built BEAM files are not overwritten.

| Isolated mutation | Assertion failures | Harness errors | Executed tests |
| --- | --- | --- | --- |
| Skip cut extraction for every member whose result is nil or has no newly emitted proposals | 11 | 0 | 17 |
| Use Fact expires_ms + 1 as the expiry cut | 3 | 0 | 17 |
| Omit the current UTC high-endpoint cell comparison | 2 | 0 | 17 |
| Accept every elapsed clock_generation comparison | 1 | 0 | 17 |

These manual native probes are distinct from VD-T13's required two extracted
archive families and six complete-verifier mutations; that obligation remains
unexecuted. They prove that these concrete regressions fail assertions in this
component corpus, not that every possible boundary or forged proof is covered.

## Ownership and cleanup

DecisionCell is hidden and accepts prevalidated complete point data/Time. It
performs no forward transition, arbitration, clock/source read, persistence or
consumer authority check. No public Decision/Transition verification API is
claimed, and no complete VD case is closed by these tests.

No archive, extracted package, mutation source/build directory, Docker resource
or native packaging artifact was produced. Mutation modules existed only in
short-lived VMs. Reusable locked dependencies, build outputs and existing PLTs
remain. Physical qualification, installed clocks, consumer transactions and
Model/Analysis scope retain their separate obligations.
