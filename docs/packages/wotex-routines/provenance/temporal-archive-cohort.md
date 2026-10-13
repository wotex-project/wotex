# Temporal adapter archive evidence

The isolated consumer executed the public calendar request/page/event seam on
2026-10-13 using Elixir 1.20.2 and OTP 29/ERTS 17.0.4. This is software artifact
adoption evidence for the named development cohort, not registry publication,
installed clock qualification, host transactions or physical operation.

| Archive | Source | SHA-256 |
| --- | --- | --- |
| wotex | WoTEx `9b4f0a9a`, `packages/wotex` | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| wotex_continuum | WoTEx `9b4f0a9a`, `packages/wotex-continuum` | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| wotex_routines | WoTEx `9b4f0a9a`, `packages/wotex-routines` | `29d4497dc6cfd928a36853d217a058df917268e71e05315e87d04ce23b680b04` |
| ex_booking | ExBooking `0418a06`, development source with SP.08 | `7fae7b9fe7a1804f37a6c7e4286c2c57318c0124454cc39f720e6516842a81f4` |

The source versions remain 0.1.0 for the WoTEx family and 0.2.3 for ExBooking.
The built ExBooking archive is **unreleased** and differs from the published
0.2.3 archive; identical version labels do not imply identical capabilities.
The ordinary optional Hex selection continues to refuse occurrence enumeration
as unavailable. A maintainer must release/select a successor before treating
that default dependency as calendar-capable.

All four runtime packages were built with development sibling selection unset,
then extracted into a disposable cohort. The fresh consumer selected only those
extracted artifacts, with no dependency on checkout source paths. Runtime BEAMs
were asserted inside its own build tree. The independently resolved Hex lock
selected Decimal 3.2.0, ExJsonSchema 0.11.5, Jason 1.4.5, NimbleOptions 1.1.1
and Tz 0.28.4; lock SHA-256 was
`79bb3746c94f2f858f6586eacccfe22eb7ebd51f6d574320b6ec25956a2b439b`.
Tz's bundled database is IANA 2026d; updater/watcher children were not selected.
Fixture clock/database labels are synthetic and make no authority claim.

The owning archive check's optional `--occurrence-archive` lane reproduced all
8 passing assertions in `test/support/archive/calendar_consumer.exs`:
global COUNT and ordinals across paging; unclipped query originals; Stockholm
and New York gap/fold coordinates; a supplied second-fold DTSTART; complete
page regeneration and clock/cursor replacement; explicit grammar/work limits;
and refusal of submillisecond execution coordinates. Compilation used
warnings-as-errors. The package's no-application-callback check also passed.

To reproduce, build the named producer source's archive with `mix hex.build
--output /absolute/archive/ex_booking.tar`, then run from the WoTEx root:

```sh
mix pkg wotex-routines run --no-start bin/check_archive.exs \
  --occurrence-archive /absolute/archive/ex_booking.tar
```

The lane prints current archive and lock digests and removes its owned temporary
consumer. Changed source, producer, dependencies or database data require a fresh
run; the historical digests above are retained as evidence for their cohort.
This one calendar consumer does not fulfill the two-consumer composition/host
milestone or the independent AST/transition oracle obligation.

## Renewed composition cohort

The same 8 calendar tests passed again on 2026-10-13 against WoTEx runtime
source `5bf61912` and the archive harness committed as `d7e2ef00` under
`packages/wotex-routines`. The routines archive SHA-256 is now
`a17ec97a464ca6b8edfbf615e32b6fd638803b8fdb839a8f33f3578c97b91ef5`.
Core, Continuum, ExBooking `0418a06`, toolchain and resolved lock retain the
identities listed above. This executed renewal covers the refactored archive
selection seam; the original cohort remains historical evidence. The paired
[composition consumers](composition-archive-cohort.md) passed in their separate
lane. Real host/clock/transaction qualification remains open.
