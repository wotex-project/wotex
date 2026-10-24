# Independent archive verification resource bounds

Recorded: 2026-10-24. Repository commit: `816d417d676700a13f8d266a5bea03d255ccfe5b`.
Package path: `packages/wotex-routines`. Scope: VDA-T8 in the
[independent archive profile](../decisions/verified-decision-archive-profile.md#vda-t8--resource-bound-renewal)
and VD-T10/VD-T12/VD-T13 in the [verified-decision contract](../specs/verified-decision-v1.md).

## Exact inputs

Both independent consumers use one extracted core/Continuum/Routines cohort.
Archives are built with the source switch unset; consumers clear inherited
sibling, build and dependency paths. The Routines archive hash is the explicit
compiler basis. All source paths below are relative to the package.

| Artifact | SHA-256 |
| --- | --- |
| `wotex_routines` archive | `8d16d4cccf5f7c2e4260bd0b13d97fdf171b6c95cb52bbd80116fd13e55758cf` |
| `wotex` archive | `315801c6dd2b48527cca10f3d6e6a3d333cadf58db2a03ef2088b05490b5c58b` |
| `wotex_continuum` archive | `775bc6a6a965f3bae80016a9da216f9ac3b593e3e9a58c08fec246a1d692e721` |
| `source` consumer lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |
| `journal` consumer lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |

| Source input | SHA-256 |
| --- | --- |
| `bin/check_archive.exs` | `c1ae695c02a71d0099e9c2b3982e35aa4aa6b4030836d7d6e0c3205b7b35142d` |
| `bin/decision_consumers.exs` | `58c79bbcdfd332b89f2bf8bcdfb1acb823619582842317c37ae1872390c4810c` |
| `test/support/archive/decision_inputs.exs` | `290d1492e7ab82e599badbe44d764e629f2bf021fa1b2ee68b0c4fe2a3629109` |
| `test/support/archive/decision_identity_consumer.exs` | `b54caf87379412ddaa2c4e02c93ef6f627bdfed5315985318f839d5147305248` |
| `test/support/archive/decision_mutation_consumer.exs` | `69160a8d17d271cf695743a72fa68b6511e81640502a174cf3cf673ecbf98c8f` |
| `test/support/archive/decision_source_consumer.exs` | `cba46bf172b55b586e0427991f297d211943a8182f0fb79031cd0177266d3fb8` |
| `test/support/archive/decision_source_oracle.exs` | `2a40fe283bcf1cea0d6b13fc63123254ec9af565bb768cb1350e2972ed339e3e` |
| `test/support/archive/decision_source_bounds_consumer.exs` | `229957b03655cd93e80ab899f6aac09dead1c615cd296837b0c49197d1b192aa` |
| `test/support/archive/decision_journal_consumer.exs` | `6ea2c462acc390bcaec1c1838d89bcea5754d2908f01c59a7d155e782c1a2cb2` |
| `test/support/archive/decision_journal_oracle.exs` | `132d1caa08b8a35037e1fb881e5026fab8ed03aa23775165fd818113bb5a5f70` |
| `test/support/archive/decision_journal_bounds_consumer.exs` | `b15a29e0f718476f1f79e3d5f88d41b0fc4df26994f7cecdb1a64900681fba02` |
| `test/wotex/routines/decision_archive_runner_test.exs` | `ce89ff8195a4f4b42b3815135460d18a0927ccb1ab15b788ba836cc9111866cc` |
| `mix.lock` | `bb744c6383ce7c98b725e8e34781f9105fdecc60e25e7927331ebfd687faca8c` |

## Executed checks

Commands ran from the repository root on Elixir 1.20.2 / OTP 29.0.4, macOS ARM64,
with `ERL_FLAGS='+S 4:4'`:

```text
mix pkg wotex-routines test test/wotex/routines/decision_archive_runner_test.exs
mix check.fast --package wotex-routines
mix check --base 80a1daea
mix wotex.workspace --base 80a1daea
mix pkg wotex-routines run --no-start bin/check_archive.exs --decision-consumers
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs
```

The focused runner refusal test passes. The fast gate passes 309 tests; the
full owning gate passes all fifteen tools, 309 tests, 95.3% coverage and Dialyzer.
The root gate passes 439 tests with one intentional exclusion, plus formatting,
strict Credo, catalogue, Markdown links and package boundaries. The final
workspace repeat follows prose-only review.

The guarded Decision corpus passes 58 cases: fifteen public, nine time, eight
bounds and twenty-six retained pending/clock cases. All nine prohibited forward
seams refuse before proof; seventy complete collection and seven arbitration
relations retain their exact expected counts. Six actual outputs pass frozen schemas.

Each extracted consumer passes forty-one cases: seven retained semantic cases,
thirty-three new bounds cases and its passive cohort identity/query check.
The thirty metric/clock cases cover both Time grammars, relevant-present,
relevant-absent and irrelevant UTC, all five JSON resource axes, five public
operations and native/plain arguments: 300 exact/one-under pairs per family.
Three additional cases check aggregate argument overflow while each argument
fits, complete certificate output after its input fits, and 100-byte strings
with eighty characters and 162 encoded bytes. Every repeated embedded value
and empty container contributes; object keys affect string width, not value count.

The source oracle visits an explicit stack and measures full JSON encoding.
The journal oracle composes subtree counts, heights and encoded lengths.
Neither imports the native bound reference or production validation/size helper.
Expected source motion and literal journal rows remain independently derived.

Each of thirteen isolated mutations executes all forty behavioral cases per
family in a fresh VM. The table gives assertion failures; every row has zero
harness errors, skipped tests and excluded tests. The runner rejects malformed,
duplicate or incomplete counts and process/loader errors.

| Mutation | Source assertions | Journal assertions | Cases per family |
| --- | --- | --- | --- |
| `expiry_before_receipt` | 1 | 1 | 40 |
| `false_edge` | 1 | 1 | 40 |
| `refunded_spend` | 1 | 1 | 40 |
| `negative_member` | 1 | 1 | 40 |
| `widened_cell` | 1 | 1 | 40 |
| `cutoff_omission` | 2 | 2 | 40 |
| `argument_envelope` | 20 | 20 | 40 |
| `certificate_output` | 3 | 3 | 40 |
| `encoded_bytes` | 8 | 8 | 40 |
| `depth_selection` | 6 | 6 | 40 |
| `nodes_selection` | 7 | 7 | 40 |
| `string_bytes_selection` | 7 | 7 | 40 |
| `collection_size_selection` | 6 | 6 | 40 |

## Cleanup and scope

The parent joins its two concurrent mutation VMs before removing the entire
owned archive, consumer, dependency-build and replacement workspace. It reports
`decision workspace cleanup: removed` and `archive check passed`; the workspace
absence was independently checked. No Docker resources were created and reusable
dependency/build caches remain intact.

This renews the archive resource-bound slice, including the current empty-container
depth convention. The [earlier archive receipt](decision-archives-2026-10.md) and
[native bounds receipt](decision-resource-bounds-2026-10.md) remain historical.
The complete newer time matrix, combined VD-T1–T14 acceptance, maximal-work
qualification and wider consumer-host adoption remain open. These checks supply
software correspondence evidence, without qualifying current authority, installed
clocks, transactions or physical effects.
