# Wotex Routines package guidance

Wotex Routines (`packages/wotex-routines`, Hex `wotex_routines`) owns closed installed behaviour, exact unit conversion, observation values and
the optional bounded pure routine kernel/host contracts. The consumer owns
canonical facts, device qualification, clocks, credentials, policy, persistence
and effects.
It uses `wotex` and `wotex-continuum` only through their public, documented API.
The explicit input adapter optionally consumes public `wotex-profiles` APIs;
ordinary routine values work with that producer absent.
Repository-wide rules are in the root `AGENTS.md`.

## Invariants

- Loading the package starts no process and performs no runtime filesystem
  access; there is no application callback. Long-lived work is returned to
  the consumer as caller-configured child specifications.
- No database, Repo, migration, Ash, Phoenix, Ecto, Oban, global registry,
  framework integration or automatic network activity.

## Where things are

- `lib/wotex/routines.ex`: the entry point, `Wotex.Routines`.
- `bin/check_archive.exs`: archive contents check;
  `bin/check_application_free.exs`: no application callback;
  `bin/check_boundary.exs`: consumer-neutral source scan (all in the full
  gate).
- Specifications: `docs/packages/wotex-routines/specs/` (`catalogue.yaml` owns
  status). Completion plan:
  `docs/packages/wotex-routines/plans/wotex-routines-completion.md`; provenance in
  `docs/packages/wotex-routines/provenance/`.

## Working on this package

| Tier | Command |
| --- | --- |
| 0 | `mix pkg wotex-routines test test/wotex/routines/basis_test.exs`, or `mix impact Wotex.Routines.Basis new --run` |
| 1 | `mix check.fast --package wotex-routines` |
| 2 | `mix check` (full gate here, fast gate in dependents) |

The full gate alone is `mix pkg wotex-routines check --no-retry` (equivalently
`WOTEX_PATH_DEPS=1 mix check --no-retry` inside `packages/wotex-routines`); it
adds dependency audits, Doctor, docs, the 95% coverage floor, Dialyzer, the
boundary scan, the archive check and the application-free check. Run
`mix dialyzer.pkg wotex-routines` in tier 1 when a typespec or inferred return
type changed.

Before changing a public function, list its callers with
`mix refs Wotex.Routines fun` and the tests to run with
`mix impact Wotex.Routines fun`. This package has no native build, software
profile or container lane.

The archive check accepts `--occurrence-archive /absolute/archive/ex_booking.tar` to build the exact WoTEx cohort and execute the isolated public calendar consumer. Supply an inspected producer archive with SP.08; the released 0.2.3 dependency deliberately exercises unavailability instead. This lane does not qualify a host clock, store transaction or device.

`bin/check_archive.exs --composition-consumers` runs two independent extracted-archive composition consumers: source-AST transition correspondence and a consumer-owned journal/arbitration harness. The paired profile and provenance in the owning documentation distinguish these software checks from production host/physical qualification.

`bin/check_archive.exs --continuation-consumers` runs independent source and
journal consumers against one extracted core/Continuum/Routines cohort. Each
has four behavioural cases and the cohort identity check. Five isolated
dependency mutations in each family must fail through assertions with zero
harness errors; compiler/loader failures do not count. The lane covers delayed
edge-origin resume, Time@2, current-state satisfaction and retained complete
pending arbitration. Archives, mutants and consumer builds are disposable and
removed on exit. This software lane does not qualify a host or physical effect.

`bin/check_archive.exs --decision-consumers` runs the independent raw-source and
journal decision consumers against one extracted core/Continuum/Routines cohort.
Each has forty behavioral cases and a passive identity/query case, including
300 exact/one-under resource-bound pairs per family. Both families must catch
all thirteen isolated verifier mutations through assertions, with no harness
errors or skipped cases. The runner uses two fresh mutation VMs concurrently and
joins them before archive cleanup. This lane does not qualify consumer authority,
installed clocks, host transactions or physical effects.

`bin/check_archive.exs --model-consumer --maude-path /absolute/maude` runs the explicitly selected proposal-prefix native archive consumer against exact Hex ExMaude 0.5.0. The interpreter remains separately provisioned; this Port lane does not build the C-Node or qualify containment, execution admission or wider models.

`bin/check_archive.exs --profile-consumers` runs two independent scalar consumers
through exact extracted core/Continuum/Runtime/Profiles/Routines archives, including
complete evaluation/Kernel/edge joins with unaligned original receipts and null
receipt UTC. Both families must catch isolated profile-identity and signed-floor
mutations through assertions. A third consumer checks ordinary Kernel execution
and explicit input refusal with the optional producer absent. Current consumer
admission and physical qualification remain separate.

`bin/check_archive.exs --occurrence-archive /absolute/archive/ex_booking.tar --civil-consumer`
adds the distinct finite civil adapter corpus and a no-application-start query.
This opt-in lane requires the exact SP.09 producer archive; ordinary SP.08
archive checks retain their previous producer requirement. All temporary archive,
extracted dependency and consumer files are removed after the check.
