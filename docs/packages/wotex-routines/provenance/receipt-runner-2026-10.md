# Staged receipt analysis runner evidence

Repository commit `5682b6ab`, package `packages/wotex-routines`, adds the
explicit receipt-prefix Analysis runner. It keeps the proposal-prefix runner
and all admission semantics unchanged. Historical model/runner cohorts retain
their own recorded artifacts.

On 2026-10-14, Elixir 1.20.2 / Erlang OTP 29.0.4 executed the focused analysis
and receipt-model suites: 13 tests passed. They include both requested Boolean
values, complete independent tuple enumeration, separate module/depth/solution
selection, low state/transition/depth budgets, expired queued work and mutations
for ACK completion, lost held spend, a cleared stopped root and duplicate/missing
states. Existing cases retain runtime identity, shared deadline, loss/truncation
and every expected binding guard.

`mix pkg wotex-routines check --no-retry` passed all 15 configured checks:
150 tests, 95.2% coverage at the unchanged 95% floor, zero Dialyzer warnings
or skips, locked dependencies, both audits, compiler, format, Credo, Doctor,
documentation, unused dependencies, boundary, archive, passive loading and Git
whitespace. This was the affected package milestone, without a native build or
repository-wide Dialyzer.

`EX_MAUDE_BUILD_CNODE=0 mix pkg wotex-routines run --no-start bin/check_archive.exs --model-consumer --maude-path /absolute/interpreter`
passed six freshly extracted archive cases. The actual interpreter is Maude
3.5.1; the consumer selects exact released ExMaude 0.5.0. Both literal values
complete the receipt runner's fixed depth-five query with twelve exact states
and its separately checked literal. Counts 12/37 describe the installed finite
alphabet's reachable states and labelled edges, not native backend statistics.
Successful bounded results remain inconclusive with no findings. Expiry and
stale runtime bindings refuse reuse. The independent native ACK-completion
mutation remains an abstract counter-state, without a concrete incident claim.

| Selected artifact | SHA-256 |
| --- | --- |
| Core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| Routines archive | `cf4f0017cf64f115b84c670d2613c824b6be421e985dc7993f0bfac2ffa0cdbb` |
| Native consumer lock | `5fd2d033262026c71ad5312bfef24e5ee45faa72dba4b4bf9964825b0da9c764` |
| Native consumer source | `7e937e4c2afb6f2b4747a352ccb2ed0e0351c4fc6e3c3eda73889f9c26d0067d` |
| Source-identity consumer | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| Interpreter executable | `266eed04679fde6029a18e5e2b1828223d4a7169ac55503aa15d67e126792fbf` |

Archives are built with WOTEX_PATH_DEPS unset and loaded from their disposable
extracted paths in env=prod. The interpreter is explicitly supplied; no C-Node,
automatic discovery or persistent worker is started by the library. Wider
receipt history, advancing time, composition, complete-set arbitration, model
witness translation, OS containment and consumer admission retain their separate
obligations. None of these checks qualifies a host clock or physical device.
