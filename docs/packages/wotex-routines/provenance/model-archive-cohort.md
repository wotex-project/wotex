# Proposal model native archive evidence

Executed 2026-10-13 against WoTEx runtime/source commit `4efe6ecd`, package
`packages/wotex-routines` and its core/Continuum archive closure. This is the
first proposal-prefix@1 profile, not a composed execution model or admission.

The fresh model consumer selects exact Hex ExMaude `== 0.5.0` and uses its
documented public `ExMaude.Verification.SearchRun.run/3`. Its changelog/API were
reviewed for absolute deadlines, decoded paths and worker/snapshot retirement.
The consumer explicitly supplies the separately provisioned Maude 3.5.1
interpreter and a 2000 ms VM-monotonic absolute deadline, 2000 ms per-command
timeout and 65536-byte response bound for each search. EX_MAUDE_BUILD_CNODE=0
selects Port-only compilation; the library is passive and no global pool starts.

Command from the repository root:

```sh
mix pkg wotex-routines run --no-start bin/check_archive.exs \
  --model-consumer --maude-path /absolute/provisioned/maude
```

Three archive consumer tests pass with warnings-as-errors: exact loaded archive
identities/passive library metadata; both generated Boolean literals and their
three-state bounded native prefixes; and a deliberate repeated-proposal model
mutation that produces a native counter-state while actual public Witness
replay refuses to reproduce that incident. Original bounded absence remains
inconclusive. No forged model artifact or abstract witness supplies admission.

| Artifact | SHA-256 |
| --- | --- |
| wotex archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| wotex_continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| wotex_routines archive | `1d4b9d9fbe4fe5693a44a1f725add52d495d7774552d9ae1469b77679c039c56` |
| bin/check_archive.exs | `df68395b2a721d60ee826b4fa6bc67eb54c76b233aae21ab5165a74cabb704e8` |
| model consumer mix.lock | `5fd2d033262026c71ad5312bfef24e5ee45faa72dba4b4bf9964825b0da9c764` |
| test/support/archive/model_consumer.exs | `ace90a9be54ff94754407852a5d65f268133b456d1019d66a58933ac48118489` |
| test/support/archive/identity_consumer.exs | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| Maude 3.5.1 executable | `266eed04679fde6029a18e5e2b1828223d4a7169ac55503aa15d67e126792fbf` |

Toolchain: Elixir 1.20.2, OTP 29, ERTS 17.0.4. Hex closure includes ExMaude 0.5.0, Decimal 3.2.0, elixir_make 0.10.0, ex_json_schema 0.11.5, hpax 1.1.0, Jason 1.4.5, Mint 1.11.0, Poolboy 1.5.2, rustler_precompiled 0.10.0 and Telemetry 1.4.2. The fresh project extracted its
producer archives with WOTEX_PATH_DEPS unset and dependency env=prod. No producer
checkout path entered the consumer. This is a new model-bearing routines archive;
the earlier composition/calendar and Home-shadow archive remains historical.

The first attempted conditional query `state(P:Phase, N:Nat)` with condition
`N > 1` or `N:Nat > 1` returned parser_error/missing_command_echo from the
released facade. This refusal is not a counterexample or completed query. The
declared finite profile uses an exact `state(P:Phase, 2)` pattern, which is
sufficient for its one-site count1-to-count2 mutation and passed. General
conditional-query correspondence needs producer diagnosis/evidence before
adoption; this record makes no claim for that seam.

This lane exercises public native query/retirement and scoped model/replay
correspondence. It does not establish full analysis queue/preparation/result
budgets, OS memory/process/file containment, receipt/clock/composition models,
complete-set policy, production consumer transactions, physical qualification
or publication. Those owning obligations remain open.
