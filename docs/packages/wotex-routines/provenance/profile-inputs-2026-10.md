# Qualified profile input software evidence

The implementation at repository commit `3b912a3c` in
`packages/wotex-routines` implements the closed WRO.05 scalar correspondence.
The selected Profiles source at `32a8e7c5` provides the public Proposal boundary.
Both are passive libraries. The correspondence records in these tests are
synthetic consumer-installed fixtures; no device or production trust is qualified.

On 2026-10-14, Elixir 1.20.2 / Erlang OTP 29.0.4 executed:

- `mix pkg wotex-routines test test/wotex/routines/input_test.exs test/wotex/routines/input_mapping_test.exs`:
  14 focused cases passed, including independent Python canonical identities,
  rational expected values, the actual public reader, closed schema checks,
  mapping/native forgery, dimension/shape refusal, write/effect scope refusal,
  replay, conservative source uncertainty and explicit clock correspondence.
- `mix pkg wotex-routines check --no-retry`: all 15 configured checks passed;
  147 tests, 95.2% coverage with the unchanged 95% floor, zero Dialyzer warnings
  or skips. Compiler, formatter, Credo, Doctor, documentation, locked dependencies,
  unused dependency, both audits, boundary, archive, passive loading and Git checks
  passed. No native build or repository-wide Dialyzer was requested.
- `mix test test/wotex/workspace/manifest_test.exs`: 22 tests passed after the
  explicit optional Profiles dependency was added to the package graph.
- `EX_MAUDE_BUILD_CNODE=0 mix pkg wotex-routines run --no-start bin/check_archive.exs --profile-consumers`:
  two freshly extracted archive consumers passed three cases each. Industrial
  temperature and a separately supplied unseen research ratio use the same public
  mechanics. A third consumer passed one case with Profiles/Runtime absent;
  ordinary Basis construction succeeds and the input seam returns missing_producer.

The archive command builds with WOTEX_PATH_DEPS unset and consumers select
only the extracted cohort in env=prod; no sibling checkout is discovered.

| Exact artifact | SHA-256 |
| --- | --- |
| Core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| Runtime archive | `7c5412ea01dab311357a09276030ca005470c9bd8b0f471e0da3fb8ec5e4b1b4` |
| Profiles archive | `2f1f9bd853f26d3842d52d2ba36f5c8ee5a0be1f60d422266ff24bc47a269501` |
| Routines archive | `0f46631b49174c5729abd41c1a61d69b7420428e6cb717ce7b466d9639ff4b07` |
| Industrial/research consumer lock | `6ddb05e87f2872a12a244a022d666372d792510c8760188a3ac235ce53c258dd` |
| Producer-absent consumer lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |
| Profile consumer source | `8cd1e7f0e4f4233cb7a39f3c51d9e3d41a227646addb3fb237f00836c24ca244` |
| Producer-absent consumer source | `a7642e2e28f9787de08e509d8096b3fc616422a9642dde42cd63ed00d2b45b8c` |
| Independent joining vectors | `dbbb5a65af5f8a875174ebcd7ff547f3eb8c688cd31473a0314674bdf23ed6ed` |
| Joining schema | `94ee69bbe1cfb6fd530e282b69d69857145d3424481f2d017894c806fb9eb287` |
| Routines source lock | `13d7c931881badf031fd0baaaea2d783565e291845e14e3050546b178e269b22` |
| Profiles source lock | `b8791c15062f8a6394ab49c7d6a83eb5127509437d69852a4a0c0090c14a6627` |

The separate Profiles milestone passed 79 tests at 95.7% coverage, all 15
configured checks and both five-case archive consumers. Its archive
`1e3613eaa39d8e5c5be3b97b516c05b0a47e371e32102ad9ec20c2beb350ae07`
predates the final README/usage guidance in `32a8e7c5`; the join cohort above
selects the later complete source bytes. These are different recorded artifacts.

The result establishes bounded software correspondence, not semantic authenticity,
current enrollment, clock qualification, Store admission or physical effect.
The consumer must still revalidate current profile/mapping/author/grants and
complete active-set state at its transactions and final handoff. Larger execution
representations and analysis scopes retain their separate owning obligations.
