# Bounded continuation software milestone

Runtime implementation at repository commit `a6de5861`, package
`packages/wotex-routines`, implements the bounded continuation successor.
Commit `b4f44c6f` adds the independent archive entry and consumers; `ed74a915`
adds real calendar/civil Time@2 archive cases. Runtime, schemas, vectors, package
manifest and source lock are unchanged between these commits. The producer is
the unmodified ExBooking checkout at `147203f`; no release or consumer pin is
selected by this evidence.

On 2026-10-16, Elixir 1.20.2 / Erlang OTP 29.0.4 (ERTS 17.0.4) executed:

- `mise exec -- mix pkg wotex-routines check --no-retry`: all 15 configured
  checks passed, with 241 tests and 95.5% coverage at the unchanged 95% floor.
  Compiler, locked dependencies, unused dependency, both audits, formatting,
  strict Credo, Doctor, ExDoc, package Dialyzer, consumer boundary, archive,
  application-free loading and Git whitespace checks passed. Doctor reported
  100% documentation, module documentation and typespec coverage. No
  repository-wide Dialyzer or native build was run.
- `mise exec -- mix pkg wotex-routines run --no-start bin/check_archive.exs --continuation-consumers`:
  the source and journal consumers each passed four behavioural cases and one
  extracted-cohort identity case. Each fresh mutation baseline passed four
  cases. Each of five isolated source mutations was caught in both families,
  with four cases executed and zero non-assertion errors in every run.
- `mise exec -- mix pkg wotex-routines run --no-start bin/check_archive.exs --occurrence-archive /absolute/archive/ex_booking.tar --civil-consumer`:
  21 real producer archive cases passed: ten calendar and eleven civil. The
  two new Time@2 cases retain original coordinates, use UTC generation for
  descriptors, allow elapsed-generation replacement and refuse cross-grammar
  reuse or absent UTC confidence. Existing fold/gap, complete ambiguity, work
  ceilings, immutable-provider and source-identity cases passed. Civil query
  without application startup passed separately. The supplied producer archive
  was built on its own pinned Elixir 1.20.4 / OTP 29.0.4 lane and removed afterward.

The full package gate ran on the bytes committed as `b4f44c6f`. The later two
temporal test-only additions received scoped formatting, strict Credo and the
complete 21-case archive run; no runtime or native-suite inputs changed.

## Independent expected behavior

The source consumer walks its finite effect/delay/sequence source and explicit
completion ledger to derive pending paths. Its temporal oracle reads original
and current elapsed/UTC coordinates rather than retained IR decisions. The
separate journal consumer owns revision checks, original/edge retention and a
monotonic charge ledger. It exercises 64 supplied members before a 16-group
cutoff, retains 16 reservations and includes the last member's conflict before
batching. Neither consumer calls hidden producer modules or reuses producer test
helpers. Shared installed Basis/Fact corpus data supplies inputs, not outcomes.

| Isolated mutation | Source assertion failures | Journal assertion failures | Non-assertion errors |
| --- | --- | --- | --- |
| Resume creates a new root | 1 | 1 | 0 |
| Elapsed continuation uses UTC generation | 4 | 4 | 0 |
| Satisfaction fabricates staged handoff | 1 | 1 | 0 |
| Satisfaction removes held admission/spend | 1 | 1 | 0 |
| Collection omits retained pending work | 2 | 2 | 0 |

The handoff and refund mutants produce structurally coherent alternative
histories; the independent consumer assertions and journal's lost-charge guard
detect their changed meaning. Mutation identity checks are not used as a
behavioral oracle. The initial marker parser failure was a harness failure and
was excluded; the final formatter begins its marker on a separate line so CLI
progress cannot hide it.

## Exact cohort

Archives were built with WOTEX_PATH_DEPS unset. WoTEx family dependencies load only from the
extracted cohort in env=prod, with separate build/dependency paths and complete
source/lock hashes. Remaining Hex dependencies are bound by the consumer locks. Both continuation consumers resolve the same lock.

| Artifact | SHA-256 |
| --- | --- |
| Core archive | `77c742b0b76c3d4d9d4c9d5e5b47e65755a351021de1ddba73369647b96fee61` |
| Continuum archive | `db7077c5f0ad92426c94a077a4f58f9b7334df25de8c2a1b8ed25143bab6efb5` |
| Routines archive | `88625fee9bc9075bf4483fd1b4069b18d64e94c77ceed912ab629a6c0871bc01` |
| ExBooking archive | `47a7b823391e7710d69f10a31c541dd1ba76e60a66e0692802df5d7be6519dae` |
| Routines source lock | `13d7c931881badf031fd0baaaea2d783565e291845e14e3050546b178e269b22` |
| Source/journal consumer lock | `b59d95b8595581bf44948381924f6396062db43e0768bb5b1de9ccd50055287f` |
| Calendar/civil consumer lock | `79bb3746c94f2f858f6586eacccfe22eb7ebd51f6d574320b6ec25956a2b439b` |
| Archive runner | `642d9e7b6c6fbf3c3bd49aff76d0fd2148768b1cea28252d13397af8a809b586` |
| Source consumer | `59598185c0409599bd0c94c78b2e09d91d3e6b5d29dd9835f428b1c036bd03f7` |
| Journal consumer | `09d0cfc6d4135226641a4ca20897cc9572ce1595a97436ec48b9dc283424feb9` |
| Mutation runner | `a3f83f2e6f72dac2fb85b365d9451c44ea94e08a047095ee140f1be5f9773fdf` |
| Cohort identity consumer | `9812ca5056ffbb4017cf62ae38c9848b4b3abbd6cbdaa9260fee74ad068e41e9` |
| Calendar consumer | `563ac6dc84819821f5f70790e53de87ab4b040e4f1325d1c73c21f0bb33d11eb` |
| Civil consumer | `1b18701d9f9277ca942d9af9b80627793038e7da591fd3eb1372ef4a84348a15` |
| Civil fixture inputs | `58ee1dc575588ed336a41d605615a62ed23d80e5640b9ad28c38685273f4f886` |

Temporary archives, extracted sources, mutants, consumer builds, debug/log
workspaces and generated documentation were removed after the executed checks.
Reusable dependency/build/PLT caches were retained. These checks created no
Docker resources, changed no repository visibility and pushed no Git refs.

This closes the bounded successor's software acceptance. It does not complete
the broader WRO.01–04 targets or qualify a consumer's current installed behavior,
active membership, clocks, durable transactions, authority, containment or physical
effects. Frozen model scopes retain their explicit omissions; satisfaction and
complete-pending environments refuse unsupported_model_scope. Consumer adoption
requires its own complete persistence/admission contract and acceptance evidence.
