# Independent archive verification time boundaries

Recorded: 2026-10-24. Repository commit: `22c8592852278ea70d5e27c68526bdb1dd9bd35d`.
Package path: `packages/wotex-routines`. Scope: VDA-T9 in the
[independent archive profile](../decisions/verified-decision-archive-profile.md#vda-t9--time-matrix-archive-renewal)
and the time/consumer obligations in [verified decisions](../specs/verified-decision-v1.md).

## Exact inputs

Both consumers use one extracted core/Continuum/Routines cohort with inherited
source, build and dependency paths cleared. The Routines archive hash is the
explicit compiler basis. These are the same three archive bytes as the
[resource-bound qualification](decision-archive-bounds-2026-10.md). Test and
qualification tooling change; library source, runtime grammar and public schemas
remain unchanged. All source paths below are relative to the package.

| Artifact | SHA-256 |
| --- | --- |
| `wotex_routines` archive | `8d16d4cccf5f7c2e4260bd0b13d97fdf171b6c95cb52bbd80116fd13e55758cf` |
| `wotex` archive | `315801c6dd2b48527cca10f3d6e6a3d333cadf58db2a03ef2088b05490b5c58b` |
| `wotex_continuum` archive | `775bc6a6a965f3bae80016a9da216f9ac3b593e3e9a58c08fec246a1d692e721` |
| `source/time` consumer lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |
| `journal/time` consumer lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |

| Source input | SHA-256 |
| --- | --- |
| `bin/check_archive.exs` | `98f8c8f6d11cef750d033f09acf6564abb0268dc6de06d4290ec13fbb6a265a4` |
| `bin/decision_consumers.exs` | `41cfbede69f1bd57ce4b34eebd780161afe79e2885283faf4521edab6edeb80f` |
| `test/support/archive/decision_inputs.exs` | `290d1492e7ab82e599badbe44d764e629f2bf021fa1b2ee68b0c4fe2a3629109` |
| `test/support/archive/decision_identity_consumer.exs` | `b54caf87379412ddaa2c4e02c93ef6f627bdfed5315985318f839d5147305248` |
| `test/support/archive/decision_mutation_consumer.exs` | `ed1c256161872e26d429e9c7252d3ab4ef10fa12cb047abd0f565e716cf15dd3` |
| `test/support/archive/decision_source_consumer.exs` | `cba46bf172b55b586e0427991f297d211943a8182f0fb79031cd0177266d3fb8` |
| `test/support/archive/decision_source_oracle.exs` | `2a40fe283bcf1cea0d6b13fc63123254ec9af565bb768cb1350e2972ed339e3e` |
| `test/support/archive/decision_source_bounds_consumer.exs` | `229957b03655cd93e80ab899f6aac09dead1c615cd296837b0c49197d1b192aa` |
| `test/support/archive/decision_journal_consumer.exs` | `6ea2c462acc390bcaec1c1838d89bcea5754d2908f01c59a7d155e782c1a2cb2` |
| `test/support/archive/decision_journal_oracle.exs` | `132d1caa08b8a35037e1fb881e5026fab8ed03aa23775165fd818113bb5a5f70` |
| `test/support/archive/decision_journal_bounds_consumer.exs` | `b15a29e0f718476f1f79e3d5f88d41b0fc4df26994f7cecdb1a64900681fba02` |
| `test/support/archive/decision_source_time_consumer.exs` | `fa959bcf6c34bbe7d8322f40674864ae968d4bc1cc461c341cb362c63a7534e5` |
| `test/support/archive/decision_journal_time_consumer.exs` | `626c5c8f286ec99fa4740132efded27ec811f0e04b4eea7c2ec9f356e48cc5dd` |
| `test/wotex/routines/decision_time_matrix_test.exs` | `c1b29f21a00d420e23362902ed7a1a3359ec510ff16db92b239ee86c05a82769` |
| `test/wotex/routines/decision_archive_runner_test.exs` | `f7df5cb90b9d59f371099d338c5a317278020cab4e1048e2e2c69ab6e149e34c` |
| `mix.lock` | `bb744c6383ce7c98b725e8e34781f9105fdecc60e25e7927331ebfd687faca8c` |

## Executed checks

Commands ran from the repository root on Elixir 1.20.2 / OTP 29.0.4, macOS ARM64,
with `ERL_FLAGS='+S 4:4'`:

```text
mix pkg wotex-routines test test/wotex/routines/decision_archive_runner_test.exs
mix check.fast --package wotex-routines
mix check --base 35516dfa
mix pkg wotex-routines run --no-start bin/check_archive.exs --decision-time-consumers
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_transition_corpus.exs
```

The two runner tests pass, including real fresh-VM selection of the complete
baseline and each fault corpus, unsupported-mode refusal and strict rejection
of incomplete/malformed counts, skips, exclusions and harness errors. The fast
gate passes 310 tests. The final owning gate passes all fifteen tools, 310 tests,
95.3% coverage and Dialyzer; root checks pass 439 tests with one intentional
exclusion, formatting, strict Credo, catalogue, links and package boundaries.

The separate direct-transition guard renewal passes 114 tests, 1,233 point
transitions, 72 direct Edge relations and one complete-envelope bounded refusal,
with all eight prohibited forward seams disabled during proof. This statement
covers the unmodified direct corpus; its separate native mutation-runner count
correction is outside this receipt.

Each extracted consumer passes all fifty-nine baseline cases: seven original
semantic cases, thirty-three resource-bound cases, eighteen time cases and
the independent cohort identity/passive query. New time cases retain all nine
declared native time traces, separately under Time@1 and Time@2. Their Fact
receipt epochs and semantic identities explicitly match the selected test clock
and binding declarations.

Expected cuts come from raw declared coordinates. The source oracle sorts a
finite interval catalogue; the journal oracle intersects the containing
half-lines of its boundary ledger. Neither imports the native reference,
production time-cell, tree or qualification helpers. Expected current elapsed
bounds are retained separately from production cells. The existing independent
source/journal arbitration oracles supply complete expected arbitration.

The cases cover adjacent receipt/freshness/expiry points, both uncertain UTC
endpoints, signed fractional instants, relevant absence and irrelevant UTC
replacement, clock/epoch/grammar changes, retained delay/wait/child starts,
occurrence windows with negative membership, edge debounce/cooldown including
zero debounce, shorter effect deadlines, terminal original/busy history and
65-bit/domain-edge arithmetic. Native and plain decisions retain exact point
data, proposal states, checked Time and arbitration or refuse stale reuse.

Every time fault executes all twenty-five original-plus-time semantic cases in
a fresh VM. Each table entry counts assertion failures; every row has zero
harness errors, skipped tests and excluded tests. The distinct bounds entry
retains its full 41-case baseline and thirteen faults across forty semantic
cases per family. There are no ExUnit test filters or exclusions.

| Time fault | Source assertions | Journal assertions | Cases per family |
| --- | --- | --- | --- |
| `negative_member` | 19 | 19 | 25 |
| `freshness_inclusive` | 4 | 4 | 25 |
| `expiry_exclusive` | 7 | 8 | 25 |
| `fractional_floor` | 6 | 6 | 25 |
| `prior_history` | 2 | 2 | 25 |
| `utc_high_endpoint` | 8 | 8 | 25 |
| `elapsed_generation` | 3 | 3 | 25 |
| `clamp_cuts` | 2 | 2 | 25 |

## Cleanup and remaining scope

The parent joins both concurrent mutation workers before removing the complete
owned archive/consumer/build/replacement workspace. It reports cleanup and
archive success; workspace absence was independently checked. No Docker objects
were created and reusable dependency/build caches remain intact.

This qualifies the independent archive time-matrix slice for these exact inputs.
The complete combined VD-T1–T14 milestone remains open. Remaining software work
includes the full shape-preserving, rehashed semantic-field mutation matrix and
maximal-work qualification. Wider model projections and consumer-host adoption
remain separately owned. This receipt supplies no current authority, installed
clock/store transaction or physical-effect claim.
