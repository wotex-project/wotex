# Routines quality and exact-archive milestone

Executed 2026-10-13 against runtime/test commit `27ee0bd4`, package
`packages/wotex-routines`, on Elixir 1.20.2/OTP 29/ERTS 17.0.4.

```sh
EX_MAUDE_BUILD_CNODE=0 mix pkg wotex-routines check --no-retry
```

The complete configured package gate passes 133 tests, 95.1% coverage against
the unchanged 95% floor, warnings-as-errors compilation, format, strict Credo,
Dialyzer (zero warnings/skips), Doctor, ExDoc, both dependency audits, locked/
unused dependencies, archive contents, application-free and boundary checks,
and Git whitespace. Initial milestone failures were six type warnings and
90.0% coverage. The private DAG traversals now use typed immutable key maps;
cycle/duplicate/closure refusals remain covered. Driver status has an accurate
redacted-return type. A real missing-executable test exposed wrong analysis
classification; missing interpreters now return unavailable evidence.

Added checks cover closed compiler contexts, enum/integer parameter refusal,
source parallel/wait/argument limits, forged run subjects/paths/times/spend,
foreign events/receipt paths, malformed facts and composite Witness completion
checks. Calendar adapter tests simulate producer responses only for preservation,
regeneration, output ordering/cardinality, precision, malformed cursor/result
and private-error redaction. They run synchronously and restore the exact selected
producer module. They explicitly capture/assert the sole intentional fixture
redefinition diagnostic; no production compiler warning or gate is excluded.
The published-producer absence case still passes. Those tests do not substitute
for the real producer archive lane below.

The combined exact-archive command also passes:

```sh
EX_MAUDE_BUILD_CNODE=0 mix pkg wotex-routines run --no-start bin/check_archive.exs \
  --composition-consumers --model-consumer --maude-path /absolute/provisioned/maude \
  --occurrence-archive /absolute/inspected/ex_booking-provider-redacted.tar
```

One freshly extracted cohort passes 9 calendar, 11 source-trace, 6 private-journal
and 5 native-model consumer cases, with warnings-as-errors and passive code
identity. ExBooking source is `28dadca`; its complete separate gate passes
411 tests and 97.0% coverage. The combined consumer explicitly includes this
producer, so composition/model dependency locks differ from their earlier
producer-absent historical lanes. Every current lock is listed below.

| Input | SHA-256 |
| --- | --- |
| wotex_routines archive | `4e6ee854f7a11c99aa44e2ab259692f9caf0c2f4899365f4dd69b1f36815818f` |
| wotex archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| wotex_continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| ex_booking archive | `8e6ffb60050e0ecf77cb68720b62eeef36ba568036a80fb6dfa0f6db38870b65` |
| consumer lock | `79bb3746c94f2f858f6586eacccfe22eb7ebd51f6d574320b6ec25956a2b439b` |
| test/support/source_truth_oracle.exs consumer source | `75fe0bc3e5eeaa88afb3077e20bcd02047cdf2600472d8604e3ce4c7b44d3f2b` |
| test/support/source_transition_oracle.exs consumer source | `5edc45db12cc628829ebc4abbc6a7bca5d531edb2b257aafb51a844c65902c4c` |
| test/wotex/routines/correspondence_test.exs consumer source | `5681dc253a1bb9cbcde03eb3766c6507721bd8409c1ad0b79f2b62b74dc60b2a` |
| test/support/archive/identity_consumer.exs consumer source | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| source-trace consumer lock | `79bb3746c94f2f858f6586eacccfe22eb7ebd51f6d574320b6ec25956a2b439b` |
| test/support/archive/journal_consumer.exs consumer source | `c219a52936b953d0eafd38bbb2d5897e5efd7c6b72eec36ed239e0b0412013a1` |
| test/support/archive/identity_consumer.exs consumer source | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| private-journal consumer lock | `79bb3746c94f2f858f6586eacccfe22eb7ebd51f6d574320b6ec25956a2b439b` |
| test/support/archive/model_consumer.exs consumer source | `e56503a82892277057e02ddda5547478b97df1eb156601c2688180fe0b27db34` |
| test/support/archive/identity_consumer.exs consumer source | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| model consumer lock | `9e6ef2be9e022256af0187370f612f614566ef6550b7b128aa7e2165e50d2798` |
| bin/check_archive.exs | `49c97c7e93002bc1d1e8c2faa24656af0a63375674c9c71adf822fd781864c68` |
| test/support/archive/calendar_consumer.exs | `fd2f5fa62ac2ed8d9190afa8dedc4df206273c466bf4b61e619857169476d688` |
| test/support/archive/model_consumer.exs | `e56503a82892277057e02ddda5547478b97df1eb156601c2688180fe0b27db34` |
| test/support/archive/identity_consumer.exs | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |

Maude is 3.5.1 with executable digest
`266eed04679fde6029a18e5e2b1828223d4a7169ac55503aa15d67e126792fbf`;
ExMaude is exact released Hex 0.5.0 through its public SearchRun facade. Native
Port execution is explicit; no C-Node build, global pool or interpreter is shipped.
The archives remain development artifacts with 0.1.0/0.2.3 labels, not publication.

This is a green software/package milestone for the implemented profiles. It
cannot complete wider temporal/composition/complete-set models, a production
consumer's durable transactions/admission or physical/installed-host evidence.
Those scopes stay partial. Earlier cohorts remain attributed to their own source
and bytes; the new archive identity cannot replace their historical subjects.
