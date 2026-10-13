# Staged receipt model archive evidence

Executed 2026-10-13 against runtime/harness `69c51f44`, package
`packages/wotex-routines`. Exact released Hex ExMaude 0.5.0 and separately
provisioned Maude 3.5.1 execute both proposal-prefix@1 and receipt-prefix@1.

```sh
EX_MAUDE_BUILD_CNODE=0 mix pkg wotex-routines run --no-start bin/check_archive.exs \
  --model-consumer --maude-path /absolute/provisioned/maude
```

Five archive cases pass with warnings-as-errors, including passive code identity,
the original Boolean proposal models, abstract mutation/concrete replay separation,
public deadline/binding runner and the new native receipt-prefix enumeration.
The latter retains held spend and ACK/cancel/complete distinctions. A deliberate
ACK-to-completed rule mutation reaches completed-with-ACK; it has a different
model identity and is an abstract model counter-state, not runtime evidence.
The current public runner explicitly refuses this new scope rather than using
its proposal-only query or fixed counts.

The package fast gate passes 122 tests, compile warnings, format and strict Credo.
Eighteen finite receipt-model traces compare every modeled state component against
both the public Kernel and independent source AST. The two Boolean values, held/
handoff/ACK/report, skipped ACK, refusal, failure/unknown, before/after-handoff
cancel and manual/cancel duplicates are exercised. Native model forgery with
recomputed digest and unsupported installed thresholds refuse. ExDoc and
repository references/catalogue checks pass.

| Artifact | SHA-256 |
| --- | --- |
| wotex_routines archive | `c90b70579732a26134e71f5c4178a28c432b708e78cf5bad7107c376ab718909` |
| wotex archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| wotex_continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| test/support/archive/model_consumer.exs consumer source | `e56503a82892277057e02ddda5547478b97df1eb156601c2688180fe0b27db34` |
| test/support/archive/identity_consumer.exs consumer source | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| model consumer lock | `5fd2d033262026c71ad5312bfef24e5ee45faa72dba4b4bf9964825b0da9c764` |
| bin/check_archive.exs | `49c97c7e93002bc1d1e8c2faa24656af0a63375674c9c71adf822fd781864c68` |
| test/support/archive/model_consumer.exs | `e56503a82892277057e02ddda5547478b97df1eb156601c2688180fe0b27db34` |

Toolchain: Elixir 1.20.2, OTP 29, ERTS 17.0.4. Interpreter digest remains
`266eed04679fde6029a18e5e2b1828223d4a7169ac55503aa15d67e126792fbf`.
The fresh consumer selects extracted exact producers with WOTEX_PATH_DEPS unset
and env=prod; the ExMaude closure/lock remains the prior exact released cohort.
No C-Node build, global pool or physical effect occurs.

Receipt-prefix fixes one original, program and clock before all deadlines.
It models qualified software receipt assertions, without author/grant validity,
time/fact changes, multiple originals, complete-set arbitration, historical
post-terminal receipts or device behavior. Those omissions, OS containment and
wider native runner scopes retain their own gates. Bounded absence is always
inconclusive for admission. Earlier archive records remain historical.
