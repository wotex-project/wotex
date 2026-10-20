# Independent verified-decision archives

Recorded: 2026-10-20. Package: `packages/wotex-routines`.
Source parent: `aad5808d51718e33ec414eed5b6113e386a09134`; library sources and
shipped package inputs are unchanged from that commit. The new runner and
consumer identities below bind the uncommitted check inputs at execution.
Owner: [verified decisions](../specs/verified-decision-v1.md) and its
[archive profile](../decisions/verified-decision-archive-profile.md).

## Exact inputs

| Artifact | SHA-256 |
| --- | --- |
| core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| Routines archive and explicit compiler basis | `d2ca8a166766978165c67a07d9bb179fa23c83e3b770517a28c50e4621199c2f` |
| each independent consumer lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |
| package `mix.lock` | `13d7c931881badf031fd0baaaea2d783565e291845e14e3050546b178e269b22` |

All file paths below are relative to `packages/wotex-routines`.

| File | SHA-256 |
| --- | --- |
| `bin/check_archive.exs` | `c1ae695c02a71d0099e9c2b3982e35aa4aa6b4030836d7d6e0c3205b7b35142d` |
| `bin/decision_consumers.exs` | `aeded1bb6d1892700e70e6d6275c12ade301d827f2eb98daa192659665451a50` |
| `test/support/archive/decision_inputs.exs` | `290d1492e7ab82e599badbe44d764e629f2bf021fa1b2ee68b0c4fe2a3629109` |
| `test/support/archive/decision_source_consumer.exs` | `cba46bf172b55b586e0427991f297d211943a8182f0fb79031cd0177266d3fb8` |
| `test/support/archive/decision_source_oracle.exs` | `2a40fe283bcf1cea0d6b13fc63123254ec9af565bb768cb1350e2972ed339e3e` |
| `test/support/archive/decision_journal_consumer.exs` | `6ea2c462acc390bcaec1c1838d89bcea5754d2908f01c59a7d155e782c1a2cb2` |
| `test/support/archive/decision_journal_oracle.exs` | `132d1caa08b8a35037e1fb881e5026fab8ed03aa23775165fd818113bb5a5f70` |
| `test/support/archive/decision_identity_consumer.exs` | `b54caf87379412ddaa2c4e02c93ef6f627bdfed5315985318f839d5147305248` |
| `test/support/archive/decision_mutation_consumer.exs` | `2ec2341c4cc12aa9e530bac1473f306492712f93a1393b9637356ae0e5fd3d6a` |
| `test/wotex/routines/decision_archive_runner_test.exs` | `91a2d02785837d5ea5145aab4a0241fdd675aaeae9a39044fd01f7409d78dd05` |

## Executed results

Commands ran from the repository root on Elixir 1.20.2 and OTP 29.0.4:

```text
mix pkg wotex-routines test test/wotex/routines/decision_archive_runner_test.exs
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_archive.exs --decision-consumers
MIX_ENV=test mix pkg wotex-routines run --no-start --no-compile bin/check_decision_corpus.exs
mix check.fast --package wotex-routines
mix workspace
```

The parser refusal matrix passes its single test. The package fast gate passes
compilation, formatting, strict Credo and all 292 tests. The root workspace gate
passes compilation, formatting, strict Credo, root tests, catalogue, links and
package boundaries. The guarded Decision corpus passes 15 public cases and 26
complete-pending/clock cases, verifying 70 collections and seven arbitration
relations with all nine prohibited forward calls disabled during proof. Six
actual outputs pass the frozen schemas across both Time grammars.

Each extracted project has eight passing cases: seven independent behavioral
cases and one cohort identity/passive query case. Every used public dependency
loads from that project's extracted build. Each library's application callback
is absent, and the public query succeeds without library application startup.
Both projects use only extracted core/Continuum/Routines dependencies, with
`env: :prod, override: true`; inherited sibling/build/dependency paths are cleared.
The shared lock resolves Decimal 3.2.0, ex_json_schema 0.11.5 and Jason 1.4.5.

Each mutation executes all seven behavioral cases in a fresh VM. The counts
below are assertion failures; every row has zero harness errors, skipped tests
and excluded tests. A mutation process exits 1 only for the expected failures;
missing/duplicate/malformed markers or any other error fail the lane.

| Mutation | Source failures / assertions | Journal failures / assertions | Cases per family |
| --- | --- | --- | --- |
| expiry_before_receipt | 1 / 1 | 1 / 1 | 7 |
| false_edge | 1 / 1 | 1 / 1 | 7 |
| refunded_spend | 1 / 1 | 1 / 1 | 7 |
| negative_member | 1 / 1 | 1 / 1 | 7 |
| widened_cell | 1 / 1 | 1 / 1 | 7 |
| cutoff_omission | 2 / 2 | 2 / 2 | 7 |

The capacity traces retain 64 members and all 1,024 pending originals before the
sixteen-group cut; separately compiled 1,023 selections refuse. The two oracles
retain their independently implemented source-path and journal-ledger semantics.
Mutation code replaces only its selected in-memory module, never the installed
BEAMs or archive. The ordinary archive gate is unchanged without the flag.

## Cleanup and limits

The parent joined all mutation VMs, removed its entire owned workspace and
reported `decision workspace cleanup: removed` followed by `archive check passed`.
The workspace's absence was independently checked after the run. No Docker
resources were created; reusable dependency/build caches were retained.

This closes the accepted archive profile for these exact inputs. The complete
VD-T1–T14 matrix and owning verifier milestone remain open. No full package
coverage, Dialyzer, native hardware, calendar producer or containment lane was
run for this tooling-only change. Consumer adoption, actual clock/source
qualification, durable transactions, wider Model/Analysis support and physical
authority remain separate obligations. No release or dependency pin changed.
