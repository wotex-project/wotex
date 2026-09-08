# WLB.08: Distribution, compatibility and release evidence

Specification version: 0.3.0. Contract: accepted. Source status: the workspace
switch, the base/profile dependency split, the package content gate, the
source-cohort guard and the archive-consumer gate are implemented; the full
reference-consumer, distribution and release-candidate runners, OCI, npm,
hosted and Nerves deliverables remain planned.

## Dependency modes

1. `workspace` is `WOTEX_PATH_DEPS=1`, allowed only in dev/test/docs. Path
   dependencies explicitly select `:dev` for nested WoTEx packages, avoiding
   their production path guard and keeping dependency test helpers out of Lab.
   It supports development, never independent artifact evidence.
2. `candidate` uses digest-verified local package archives in an isolated
   consumer. Source is extracted from those archives only. A private local Hex
   repository/cache may deliver them; Mix requirements remain Hex requirements.
   No path/git dependency, symlink to a sibling or hidden copied source is allowed.
3. `released` uses published immutable Hex versions with recorded lock/checksum
   and archive digests. Base dependencies are core, Wotex Nx and Nx. Runtime,
   bindings, Directory, Continuum, conformance and heavyweight integration
   dependencies belong to explicitly selected host profiles inside this repo.
   The base package must not make brokers, SQLite, Maude, Axon, EXLA, Phoenix or
   an LLM necessary for the first tensor. Profiles share public Lab contracts.
   In source, `mix.exs` declares Runtime, both bindings, Directory, Continuum
   and Exqlite as optional requirements and the conformance runner as a
   development and test dependency; every Lab module behind one of those seams
   is compiled only when its package is loaded, so the base closure is core,
   Wotex Nx, Nx and telemetry.

The dependency arrow points only from Lab to public packages. Unavailable
artifacts fail the applicable gate. Do not silently switch to workspace mode,
claim source builds as published adoption, or change repository visibility.

`elixir bin/check_source_cohort.exs` is a read-only workspace drift guard over the
explicit source/spec/test/fixture cohort. It requires all source owners and
is separate from package-local CI. Dirty content is covered by content digests;
the historical revision snapshot is not relabeled. A changed hash requires
review and renewed evidence, not automatic readiness promotion.

## Distinct gates

| Gate | Required proof |
| --- | --- |
| `foundation_green` | WLB.01, implemented WLB.02/WLB.03/WLB.11 surfaces; warnings-as-errors, format/Credo, >=95% lines, docs/Doctor, Dialyzer, audits, metadata/boundary/package checks |
| `package_contents_green` | Exact built archive has public lib/spec/plan/decision/provenance/fixtures/license files; no trackers, credentials, deps, build output or private paths; production dependency metadata has no path/git refs |
| `archive_consumer_green` | Fresh unrelated Mix application, exact archive-only dependency closure, read-only admitted archives, Git absent from executable PATH during resolution/build/run; TD and Nx positive/negative cases |
| `reference_consumer_green` | WLB.02–WLB.07/WLB.09–WLB.11 complete scenarios against the same cohort; real transport, dual-store, metric/AI and workbench tests; independent target; exact ownership/effect boundary |
| `distribution_green` | Hex/Mix.install, all Livebooks, OCI, generated npm client, disposable hosted demo and declared Nerves target tested; installed-artifact smoke repeated for published cohort |
| `public_release_candidate` | All above plus SBOM/provenance/license/security/API review, verified source/lock/archive/image/model digests and all documented links/commands |
| `stable_api_candidate` | Explicit compatibility decision over every public result/error/default/schema and minimum/current supported cohort; no inference from version or coverage |

`bin/check_package.exs` implements content inspection only.
`bin/check_archive_consumer.exs` implements the `archive_consumer_green` gate
for the base profile: it builds the core, Wotex Nx and Lab archives from the
sibling checkouts without the workspace switch, admits public dependencies only
at the versions in the Lab lock and only from the local Hex cache, builds a
local Hex registry from those archives, serves it from OTP `httpd` on a
loopback port, and drives a fresh Mix application through a PATH that links
every executable except Git (asserted from inside the consumer) with a fresh
`HEX_HOME` and the registry as the only mirror. The consumer lock is inspected
recursively: every package must be an admitted archive and no profile package
may appear. The smoke runs Thing Description and Nx positive and negative cases
through public APIs and proves the profile modules are absent. The gate writes
a `Wotex.Lab.Evidence.Record` with archive digests and retains only that
record. `bin/check_reference_consumer.exs` implements the workspace form of
`reference_consumer_green`: it runs every Lab suite against the same cohort
with the broker, GreptimeDB and formal lanes enabled where a Docker daemon
with the pinned images and a pinned Maude engine are present, records a
lane that could not run as `not_run` rather than passed, and retains an
evidence record with the cohort digests. It is workspace evidence, not the
artifact-mode runner; the distribution and release-candidate runners remain
acceptance obligations, not approximated by these scripts. Before running archive-consumer tests, the harness MUST assert Git is
unavailable (`command -v git` must fail) and inspect the resolved dependency
graph recursively, including optional/profile/transitive deps. Resolution of
the normal graph must occur in that restricted environment; merely hiding Git
after dependencies were fetched does not prove the condition. Registry setup
and artifact admission happen explicitly and are captured separately.

CI modes are foundation/package, archive, lab, interop, chaos, conformance,
matrix, benchmark, distribution and release-candidate. A disabled or unsupported
mode is not green. Locked and newest permitted dependencies are separate jobs.
Minimum cohort is Elixir 1.18/OTP 27 and current baseline 1.20/OTP 29; exact
patches and OS are recorded. Nx/EXLA and Maude have explicit supported-platform
matrices. Scheduled benchmarks use pinned machines; shared runners have no
unqualified absolute performance gate.

## Clone-free deliverables

Hex and Mix.install run the numerical entry point. Livebooks install the same
artifacts. OCI provides the full disposable host with least-privilege user,
read-only base filesystem, quotas, ephemeral instance storage, health/cleanup
checks and optional digest-pinned broker. npm is schema-generated control
client code. Hosted sessions expire, isolate users and cannot reach arbitrary
devices; DNS/domain/deployment actions remain operator-owned.

The reference host owns Phoenix/LiveView, PromEx and BeamLens dependencies.
WLB.10's GreptimeDB process is opt-in; its endpoint/data volume/TTL and resource
limits are explicit. Do not bundle an unauthenticated public database listener.
The no-LLM/no-durable-store profile must run the same core experiments. UI,
metric codecs, BeamLens provider/native dependencies and chart assets have
separately pinned compatibility/license/security cohorts. Whole-VM dependency
state cannot be used as an untrusted multi-tenant isolation boundary.

The Explorer analytics profile follows the
[interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md).
Record Explorer/Polars native artifact, Nx, Decimal and chart compatibility
independently; the base archive consumer must still exclude Explorer and Kino.
Archive status and vulnerability warnings need explicit adoption decisions.
An advisory metadata conflict requires version-specific evidence, not a broad
audit disable. `kino_explorer` is not an admitted new required dependency.
Chart wrappers cannot silently upgrade the admitted Vega-Lite dialect or
enable external URLs, arbitrary expressions or raw JavaScript.

Nerves is a required delivery lane: name the supported target (`rpi4` baseline),
pin the Nerves system/firmware/toolchain, supply a prebuilt bootable image with
integrity/license information, and test offline/start/reconnect plus a recorded
on-target smoke. Host compilation alone cannot pass hardware execution.
The target uses the numerical baseline and explicit supported network adapters;
native EXLA/Maude are capability-specific, not assumed available on firmware.
Build instructions accompany the image; no embedded compiler is required to
try it. Real hardware availability is an evidence prerequisite, not a fabricated
result or removal from scope.

Maude licensing, binary provenance and platform support follow WLB.09. All
optional distributions declare their dependency/license closure. Creating or
publishing remote state, domains, packages, firmware releases or images is a
maintainer action. Visibility changes are always manual user-only actions.
