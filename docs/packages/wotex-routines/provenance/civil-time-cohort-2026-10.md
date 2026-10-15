# Bounded civil calendar archive cohort

Updated: 2026-10-15. This is local pure/archive software evidence for WRO.03's
civil addition, not publication, a consumer transaction, trusted clock or
physical qualification. The package remains partially implemented overall.

## Exact inputs

Runtime and harness source: repository commit `c6d5b2f9`, package
`packages/wotex-routines/`. ExBooking producer source: its separate repository
commit `dd82677`. Both were built as source archives; no neighboring producer
checkout was loaded by the isolated consumer. The dependency still declares
optional exact released ExBooking 0.2.3. The supplied development archive uses
that version label but has unreleased public additions; its exact digest below
identifies it. This does not select a release or update any consumer's pin.

The source/consumer lane uses Elixir 1.20.2/OTP 29.0.4; producer archive creation
uses its pinned Elixir 1.20.4/OTP 29.0.4. The fresh consumer resolves Decimal
3.2.0, ExJsonSchema 0.11.5, Jason 1.4.5, NimbleOptions 1.1.1 and Tz 0.28.4.
Minimum-toolchain and broader dependency matrices were not run for this slice.

| Exact artifact | SHA-256 |
| --- | --- |
| Routines archive | `5fe5a0b907a12ce49b542042516e6e14f7d6c2ef098e689aa26d12efd6e94e20` |
| Core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| ExBooking archive | `f9af95f9d87a6195f30bc882cfd7bd78106a4bfcdd0ad376a62ed4551494add4` |
| Fresh consumer lock | `79bb3746c94f2f858f6586eacccfe22eb7ebd51f6d574320b6ec25956a2b439b` |
| Civil archive fixture | `d1a161eab065bb2cf403bec6fcfde7c56309dcfd80d49680d07b62cee059a82a` |
| Shared civil fixture | `58ee1dc575588ed336a41d605615a62ed23d80e5640b9ad28c38685273f4f886` |

## Executed boundaries

From the repository root, `mix check.fast --package wotex-routines` passed
157 tests (seed 975894), compiler warnings-as-errors, formatter and strict Credo.
The focused civil plus existing scalar/calendar files passed 20 tests; isolated
adapter checks separately distinguish producer refusals, malformed native
values, fixed errors and regeneration from actual producer semantics.

`mix pkg wotex-routines check --no-retry` executed the package milestone.
157 tests passed with 95.2% coverage (seed 820727); compiler, formatter, Credo,
locked dependencies, audits, Dialyzer, Doctor, boundary, application-free and
whitespace checks passed. Doctor reports 100% docs/moduledocs/public specs.
That invocation failed ExDoc's link to the unreleased producer API and the
archive harness's omitted-option guard. The link and guard were corrected;
`mix pkg wotex-routines check --retry` passed compiler/ExDoc, and
`mix pkg wotex-routines run --no-start bin/check_archive.exs` passed the final
default archive check. This records component outcomes rather than claiming
the first aggregate invocation succeeded. The 95% coverage floor and all
existing exclusions/configuration were unchanged.

The actual source-archive lane is:

```sh
mix pkg wotex-routines run --no-start bin/check_archive.exs \
  --occurrence-archive /absolute/archive/ex_booking.tar --civil-consumer
```

It builds/extracts the exact four-archive cohort, compiles a fresh consumer
with warnings-as-errors and passes 17 cases (seed 971532): the unchanged nine-case original
calendar corpus plus eight civil cases. A separate process also performs a civil
query with Routines, ExBooking and Tz unstarted before and afterward. Omitting
`--civil-consumer` retains the original SP.08-only producer requirement.

| Acceptance | Executed evidence |
| --- | --- |
| WRO03-T5 | Closed schema/vector, exact options/fields and native request/page shapes, explicit database, malformed dates/policies/limits and released missing-capability refusal |
| WRO03-T6 | Literal Stockholm/New York gap/fold results through module and immutable providers; first/second/both/reject and policy-before-filter; offsets -89999/-86400/86400/93599 through actual callbacks while legacy helpers retain their narrower bounds |
| WRO03-T7 | Independent Gregorian weekday arithmetic across 24 start/mask/span configurations, partition/retry equality, original stability under query/clock changes, provider-context/basis change, regenerated pages and compiled-event binding |
| WRO03-T8 | Real 366-resolution/732-localization/732-point maximum; complete output refusal at lower Limits; actual late refusal after one valid point; independent malformed/duplicate/unordered/native/precision/private-canary adapter cases |

The archive also exercises years 0000 and 9999, empty immutable provider context
(which SP.08 explicitly permits), extra/invalid/oversized provider fields,
unknown UTC confidence during pure calculation and strict millisecond windows.
Synthetic control-flow fixtures are not evidence of real timezone semantics;
the separate extracted producer cases supply that evidence.

## Limits and cleanup

The broader root gate was not run: unrelated research changes select all twenty
packages, whereas this slice changes only Routines code. Native, firmware,
containment, model-runner and physical lanes were not selected. Existing scalar
and SP.08 semantics remain separately tested; current consumer Store/clock/
authorization joins remain obligations under WRO03-02–05.

Archive/consumer/producer scratch directories are removed in `after`/`finally`
paths, including failed attempts. Local PLTs are excluded from the Routines
archive and the archive check refuses them. Generated documentation/coverage
reports are disposable; locked dependency and small build/type caches remain
local. No Docker image, container or volume was created by these checks.
