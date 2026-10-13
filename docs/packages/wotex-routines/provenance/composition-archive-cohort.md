# Composition archive cohort

Executed 2026-10-13. Producer runtime/source: WoTEx commit `5bf61912`,
`packages/wotex-routines`, `packages/wotex` and `packages/wotex-continuum`.
The acceptance harness is identified independently by the exact source digests
below. Documentation and harness files do not enter the package archives.

Command from the repository root:

```sh
mix pkg wotex-routines run --no-start bin/check_archive.exs --composition-consumers
```

The builder unsets WOTEX_PATH_DEPS. Dependencies are extracted from these
archives into a disposable directory and compiled with dependency env=prod.
Two fresh consumer projects run separately with warnings treated as errors.
The source-trace consumer passes 11 tests; the private-journal consumer passes
6 tests. Both check loaded BEAM paths under their own builds and passive library
metadata. Source-AST comparisons cover finite manual composition transitions;
the private journal refuses stale prior-history/policy/snapshot/time commits,
retains held spend and historical reports after cancellation, and finds a
whole-provided-set conflict before a one-group cutoff.

| Artifact | SHA-256 |
| --- | --- |
| wotex archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| wotex_continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| wotex_routines archive | `a17ec97a464ca6b8edfbf615e32b6fd638803b8fdb839a8f33f3578c97b91ef5` |
| each consumer mix.lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |
| bin/check_archive.exs | `a7bfefe2f3d19660671ee783ad5e8153ac22a6a1d73b0bed70c71810ca4f465f` |
| test/support/source_truth_oracle.exs | `75fe0bc3e5eeaa88afb3077e20bcd02047cdf2600472d8604e3ce4c7b44d3f2b` |
| test/support/source_transition_oracle.exs | `5edc45db12cc628829ebc4abbc6a7bca5d531edb2b257aafb51a844c65902c4c` |
| test/wotex/routines/correspondence_test.exs | `5681dc253a1bb9cbcde03eb3766c6507721bd8409c1ad0b79f2b62b74dc60b2a` |
| test/support/archive/identity_consumer.exs | `6774e6653c550b7510010d53a7049394bc48d2870a79e780dc76f0e176f94345` |
| test/support/archive/journal_consumer.exs | `c219a52936b953d0eafd38bbb2d5897e5efd7c6b72eec36ed239e0b0412013a1` |

Toolchain: Elixir 1.20.2, OTP 29, ERTS 17.0.4. Fresh Hex closure:
Decimal 3.2.0, ex_json_schema 0.11.5 and Jason 1.4.5. The optional ExBooking
dependency is absent from this consumer closure; this lane makes no calendar
claim. The separately selected occurrence-archive lane owns that evidence.

This is extracted-artifact software evidence for the
[paired consumer profile](../decisions/paired-archive-consumers.md). It does not
establish a production consumer's authentication/transaction/restart/backup,
native containment, complete environmental collection, model projection,
physical qualification or publication. Changed runtime, archive or acceptance
source invalidates the affected cohort claim until its owning checks rerun.
