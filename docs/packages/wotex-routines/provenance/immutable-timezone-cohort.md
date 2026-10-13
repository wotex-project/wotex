# Immutable timezone provider archive renewal

Executed 2026-10-13 against WoTEx runtime/harness `f0e68746`, package
`packages/wotex-routines`, and ExBooking source `fb9082f`. The command was:

```sh
EX_MAUDE_BUILD_CNODE=0 mix pkg wotex-routines run --no-start bin/check_archive.exs \
  --occurrence-archive /absolute/inspected/ex_booking-provider.tar
```

Nine extracted-archive calendar cases pass with warnings-as-errors. The added
provider case compares explicit immutable provider and ordinary database module
pages in both DST zones, checks unchanged originals/nominal/UTC/ordinal values,
revalidates a complete retained page and refuses changed-context continuations,
extra native fields and contexts beyond the selected Limits. The eight prior
original-occurrence cases remain passing. The ordinary fast gate passes 120 tests,
strict Credo, format and warnings-as-errors compilation; its released ExBooking
0.2.3 absence case remains intact. ExDoc and references/catalogue checks pass.

| Artifact | SHA-256 |
| --- | --- |
| wotex_routines archive | `9efd2ccb4963c28719506a965838c138e9a109105ba94e0861275d05b6eb4e58` |
| wotex archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| wotex_continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| ex_booking archive | `420dc97c440256276b0f37e75d44430750b23e063ace7d3a7f5ae63363c3d319` |
| consumer lock | `79bb3746c94f2f858f6586eacccfe22eb7ebd51f6d574320b6ec25956a2b439b` |
| bin/check_archive.exs | `49c97c7e93002bc1d1e8c2faa24656af0a63375674c9c71adf822fd781864c68` |
| test/support/archive/calendar_consumer.exs | `fd2f5fa62ac2ed8d9190afa8dedc4df206273c466bf4b61e619857169476d688` |

Toolchain: Elixir 1.20.2, OTP 29, ERTS 17.0.4. The fresh dependency closure retains
Decimal 3.2.0, ExJsonSchema 0.11.5, Jason 1.4.5, NimbleOptions 1.1.1 and Tz 0.28.4.
All four producers are extracted exact artifacts, with WOTEX_PATH_DEPS unset
and dependency env=prod. Development version labels 0.1.0/0.2.3 do not imply
published capabilities; the producer additions remain unreleased.

The provider owns no timezone parser, registry, clock confidence, authority or
transaction. Immutable context and installed callback custody remain consumer
obligations. This renewal establishes the declared adapter seam only; real
consumer Store races, installed clocks, OS containment, physical effects and
wider quality/completion milestones remain open. Earlier temporal cohorts stay
historical evidence, rather than acquiring new capabilities by changing a digest.

## Producer refusal hardening renewal

The same nine calendar cases pass against ExBooking `28dadca`, whose helpers
normalize all foreign callback refusal payloads to time_zone_provider_refused.
The producer archive SHA-256 is
`8e6ffb60050e0ecf77cb68720b62eeef36ba568036a80fb6dfa0f6db38870b65`.
WoTEx source/harness `2bb4c455` and the same routines archive
`9efd2ccb4963c28719506a965838c138e9a109105ba94e0861275d05b6eb4e58`
were exercised, with unchanged other artifacts, fixture/harness digests, native
calendar toolchain and lock. This historical renewal predates the receipt-model
addition; it does not promote its routines artifact to the newer model cohort.
ExBooking's complete local gate passes 411 tests, 97.0% coverage and all required
components; the privacy canary failed before the fix and passes afterward.
