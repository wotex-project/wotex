# Deadline-bound analysis runner archive evidence

Executed 2026-10-13 against runtime and harness commit `ffc577cf`, package
`packages/wotex-routines`. This renews the native proposal-prefix seam for the
new public `Analysis.run/5`; earlier model evidence remains historical.

```sh
EX_MAUDE_BUILD_CNODE=0 mix pkg wotex-routines run --no-start bin/check_archive.exs \
  --model-consumer --maude-path /absolute/provisioned/maude
```

The fresh extracted-archive consumer selects exact released Hex ExMaude 0.5.0,
with WOTEX_PATH_DEPS unset and dependency env=prod. Four tests pass with
warnings-as-errors: passive archive/code identity, both native Boolean prefix
models, the abstract mutation/concrete replay distinction, and the public
runner with actual executable/parser identity, complete binding, expired queue
and changed-runtime refusals. The runner's two searches share one 5000 ms
VM-monotonic deadline, with 65536-byte native/result limits, three-state and
five-profile-edge budgets, and depth two. Successful bounded absence remains
inconclusive with no findings. No C-Node build or global pool is selected.

| Input | SHA-256 |
| --- | --- |
| wotex_routines archive | `895bb3e4c191dbee861fe4062c13359b6f8cace17bd7327350707bba41b1210c` |
| wotex archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| wotex_continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| test/support/archive/model_consumer.exs consumer source | `19bcbb825e7608266d518467055bfadb18af78a8302d37481e6797f823e1d6cf` |
| test/support/archive/identity_consumer.exs consumer source | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| model consumer lock | `5fd2d033262026c71ad5312bfef24e5ee45faa72dba4b4bf9964825b0da9c764` |
| archive | `895bb3e4c191dbee861fe4062c13359b6f8cace17bd7327350707bba41b1210c` |

Interpreter: Maude 3.5.1, executable SHA-256
`266eed04679fde6029a18e5e2b1828223d4a7169ac55503aa15d67e126792fbf`.
Toolchain: Elixir 1.20.2, OTP 29, ERTS 17.0.4. The selected Hex closure remains
ExMaude 0.5.0, Decimal 3.2.0, elixir_make 0.10.0, ex_json_schema 0.11.5,
hpax 1.1.0, Jason 1.4.5, Mint 1.11.0, Poolboy 1.5.2,
rustler_precompiled 0.10.0 and Telemetry 1.4.2.

The package fast gate passes 120 tests plus format, warnings-as-errors compilation
and strict Credo. Seven runner test groups additionally exercise all eleven
changed subjects, model regeneration, pre-search state/transition/depth/model
limits, final output refusal, shared deadlines, late results, unavailable/error/
truncated native outcomes and wrong state/literal correspondence. Fake backend
cases establish adapter decisions; native evidence is the separate four-test
lane above. ExDoc warnings and repository references/catalogue checks pass.

This profile omits admission, receipts, advancing clocks, multiple originals,
complete-set arbitration and physical effects. Queue capacity/concurrency and
caller supervision remain consumer-owned. Deadline checks do not establish hard
real-time cleanup, OS memory/process/file containment or production Store
transactions. Wider analysis projections and full quality milestone remain open.
