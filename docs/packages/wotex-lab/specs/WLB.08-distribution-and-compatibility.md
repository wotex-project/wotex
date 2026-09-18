# WLB.08: Distribution, compatibility and release evidence

Specification version: 0.9.6. Contract: accepted. Source status: the workspace
switch, the base/profile dependency split, the package content gate, the
source-cohort guard, the base archive-consumer gate, the full-host Workbench
archive/release gate, CycloneDX production-closure SBOM, public API snapshot and
generated npm client source gate are implemented. The
Workbench also has a digest-pinned, non-root OCI Dockerfile, data-free health
route and offline image-source gate; Docker's build-graph check passes, but no
runnable image is claimed while its WoTEx Hex dependencies are unpublished.
The full reference-consumer, distribution and release-candidate runners, built
OCI image, published npm artifact, hosted deployment, prebuilt Nerves firmware
and on-device evidence remain planned. The rpi4 firmware project, exact Nerves
system/toolchain lock, inert host smoke and source gate are implemented under
`hosts/nerves/`; the local cross-build reaches firmware assembly but cannot
finish without the operator-installed `fwup` prerequisite.

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
   dependencies belong to explicitly selected host profiles inside this package.
   The base package must not make brokers, SQLite, Maude, Axon, EXLA, Phoenix or
   an LLM necessary for the first tensor. Profiles share public Lab contracts.
   In source, `mix.exs` declares Runtime, both bindings, Directory, Continuum
   and Exqlite as optional requirements and the conformance runner as a
   development and test dependency; every Lab module behind one of those seams
   is compiled only when its package is loaded, so the base closure is core,
   Wotex Nx, Nx and telemetry. The package gate's `optional_deps` step proves
   it on every run: it compiles Lab without any optional dependency, with
   warnings as errors and in its own build path, and
   `bin/check_optional_deps.exs` then checks that no module behind a seam was
   compiled and that the remote-write and OTLP sinks answer
   `:client_unavailable` and the MCP tools answer that the runtime or formal
   profile is not part of the host.

The dependency arrow points only from Lab to public packages. Unavailable
artifacts fail the applicable gate. Do not silently switch to workspace mode,
claim source builds as published adoption, or change repository visibility.

`elixir bin/check_source_cohort.exs` is a read-only workspace drift guard over the
explicit source/spec/test/fixture cohort. It requires all source owners. It is
an explicit evidence-refresh check run beside the `WOTEX_LAB_INTEGRATION=1`
lanes, not part of the everyday `mix check` gate, which exercises the sibling
packages in `packages/` without binding them to content digests; package-only
checks do not require the sibling packages. Dirty content is covered by content digests;
the historical revision snapshot is not relabeled. A changed hash requires
review and renewed evidence, not automatic readiness promotion.
WLB.04–06 and WLB.09 evidence digests include the reviewed content cohort;
their `missing` dependency archives remain source-only evidence. A package's
new source implementation status does not change the historical index or imply
independent artifact adoption. Dated follow-up decisions live in the seam review.

## Distinct gates

| Gate | Required proof |
| --- | --- |
| `foundation_green` | WLB.01, implemented WLB.02/WLB.03/WLB.11 surfaces; warnings-as-errors, format/Credo, >=95% lines, docs/Doctor, Dialyzer, audits, metadata/boundary/package checks |
| `package_contents_green` | Exact built archive has public lib, `priv/` fixtures/models/cookbooks/containment source/provenance data, README, changelog and license files; no Markdown specification, plan, decision or provenance documents (they reach consumers through HexDocs), trackers, credentials, deps, build output or private paths; production dependency metadata has no path/git refs |
| `archive_consumer_green` | Fresh unrelated Mix application, exact archive-only dependency closure, read-only admitted archives, Git absent from executable PATH during resolution/build/run; TD and Nx positive/negative cases |
| `workbench_archive_green` | Fresh extracted Workbench source artifact, complete host dependency closure from admitted local/public archives, exact cached native-artifact digests, Git absent during resolution/build/release smoke, production compilation and executable release |
| `reference_consumer_green` | WLB.02–WLB.07/WLB.09–WLB.12 complete scenarios against the same cohort; real transport, dual-store, metric/AI, workbench and documentation tests; independent target; exact ownership/effect boundary |
| `documentation_distribution_green` | WLB.12 pinned cohort; isolated source collections; built-in Workbench docs; root/subpath static archive; semantic parity, link, search, browser, accessibility, offline, bundle and rollback evidence |
| `distribution_green` | Hex/Mix.install, all Livebooks, OCI, generated npm client, unified static documentation, disposable hosted demo and declared Nerves target tested; installed-artifact smoke repeated for published cohort |
| `public_release_candidate` | All above plus SBOM/provenance/license/security/API review, verified source/lock/archive/image/model digests and all documented links/commands |
| `stable_api_candidate` | Explicit compatibility decision over every public result/error/default/schema and minimum/current supported cohort; no inference from version or coverage |

`bin/check_package.exs` implements content inspection only.
Package inspection, archive consumers and reference runs allocate separate
private attempts through `bin/support/work_directory.exs`: 128-bit random
names and exclusive directory creation replace per-VM integer names. Reusing
a staging directory can retain removed files in an unpacked candidate, so
existing directories are never merged or overwritten. The helper's test
checks private permissions, fresh allocation and prior-content preservation.
Successful archive consumers delete only their own generated build/registry
scratch material and retain their evidence; they do not erase earlier attempts.
`bin/check_archive_consumer.exs` implements the `archive_consumer_green` gate
for the base profile: it builds the core, Wotex Nx and Lab archives from the
sibling package directories without the workspace switch, admits public dependencies only
at the versions in the Lab lock and only from the local Hex cache, builds a
local Hex registry from those archives, serves it from OTP `httpd` on a
loopback port, and drives a fresh Mix application through a PATH that links
every executable except Git (asserted from inside the consumer) with a fresh
`HEX_HOME` and the registry as the only mirror. The consumer lock is inspected
recursively: every package must be an admitted archive and no profile package
may appear. The smoke runs Thing Description and Nx positive and negative cases
through public APIs and proves the profile modules are absent. The gate writes
a `Wotex.Lab.Evidence.Record` with archive digests and retains only that
record. `bin/check_reference_consumer.exs` supplies a workspace suite run,
not the complete `reference_consumer_green` gate: it runs Lab suites against
the same cohort with broker, GreptimeDB and formal lanes enabled where a Docker
daemon with provisioned images and an explicitly supplied Maude engine are present, records a
lane that could not run as `not_run` rather than passed, and retains an
evidence record with the cohort digests. Each service lane checks its own
already provisioned image; a missing Greptime image no longer disables the
broker lane or silently admits a database pull. No image is pulled by this
admission step. The formal lane requires an explicitly supplied engine path.
The harness passes and records seed 1, requires one valid nonempty terminal
ExUnit summary in addition to process exit success, and preserves failures and
exclusions. Old-format totals are normalized to executed tests by subtracting
excluded cases; unsupported/ambiguous/oversized summaries fail closed. Its
`ReferenceSummary` helper has independent positive and adversarial tests.
Source identity is checked before and after execution. The
`bin/support/reference_inputs.exs` definition includes the harness, Elixir/test
and native containment source, executable Livebooks, fixtures/models,
configuration and the package README, changelog and license files; the
specification, plan, decision and provenance documents live outside the
package and are not inputs. The historical source index and evidence manifests are inputs too; a changed,
removed or newly added matching resource invalidates the digest. Generated
builds, dependency caches, PLTs and retained attempt output are excluded.
`reference_inputs_test.exs` exercises these content/name boundaries. This
strengthens source identity, not output containment or artifact adoption.
The reference harness requires explicit
workspace mode and checks all sibling content against the reviewed cohort at
both boundaries; the cohort file and guard are themselves part of its input
digest. Changed inputs invalidate the run. Each attempt
gets a new private directory, and earlier evidence is never deleted.

`bin/check_workbench_archive.exs` independently exercises the explicit full
host. It builds all eight selected WoTEx packages without workspace paths,
admits every public dependency at the exact Workbench lock version from the
local Hex cache, and admits only the platform-specific Explorer, ExMaude and
BeamLens/BAML precompiled archives needed by this host. Their bytes and the
generated Workbench source tar are digested. The source tar contains only the
declared host source/config/static/lock cohort, is extracted into a fresh
private directory and is rejected if it contains a symlink. The shared local
registry and restricted PATH implementation keeps Git unavailable for
resolution, recursive graph inspection, production compilation and release
creation. The release is executed in `eval` mode and proves the selected public
modules load without Git. This is clone-free local candidate evidence and
promotes WLB.08 adoption to `reference_available`; it is not published-Hex,
OCI-runtime, hosted-browser, independently contained runner or hardware
evidence, so it does not pass `reference_consumer_green` or
`distribution_green`.

## Release review artifacts

`priv/provenance/workbench-bom.cdx.json` is a deterministic CycloneDX 1.7 SBOM
for the exact active production tree resolved by `workbench_archive_green`.
CycloneDX 1.7 was the current official version at the 2026-09-08 review; the
official JSON schema is the reference representation. Every component records
its Hex package URL and declared archive license. Published-cache components
carry their Hex outer SHA-256; locally built, unpublished WoTEx components are
explicitly marked `built` and omit a component hash because the SBOM is itself
inside the Lab archive and cannot truthfully hash its containing archive. The
separate gate evidence records those exact candidate archive digests. All
dependency references must resolve inside the BOM and every direct host
requirement must be present.

`priv/provenance/wotex-lab-api.json` is the pre-1.0 public review baseline for
the base Lab application. It records every application module's exported
function/arity, declared behaviour, struct keys and retrievable typespec clauses.
`bin/generate_api_surface.exs --check` fails on drift and requires an explicit
`--write` review. This is a change detector, not a stable-API decision: default
argument semantics, result/error meaning, serialized schemas and the
minimum/current runtime cohort still require the explicit compatibility review
before `stable_api_candidate` can pass.

The workspace reference script still uses a waiting-task deadline around
`System.cmd`; that is not an independently verified descendant-cleanup or
bounded-output-capture contract. Its record therefore leaves runner containment
and the full reference programme as `not_run`, with cleanup conservatively
`failed` because it is unverified. The parser's eight-MiB input bound does not
bound subprocess output allocation. A passing suite exit is source-test
evidence only, not closure of these accepted runner obligations. It is
workspace evidence, not the artifact-mode runner; the distribution and
release-candidate runners remain acceptance obligations, not approximated by
these scripts. Before running archive-consumer tests, the harness MUST assert
Git is unavailable (`command -v git` must fail) and inspect the resolved
dependency graph recursively, including optional/profile/transitive deps.
Resolution of the normal graph must occur in that restricted environment;
merely hiding Git after dependencies were fetched does not prove the condition.
Registry setup and artifact admission happen explicitly and are captured
separately.

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
client code. The checked-in `clients/typescript/` projection has no runtime
dependencies and its gate runs Node behavior tests plus `npm pack --dry-run`;
this is source/archive-shape evidence, not registry publication or an
installed-artifact smoke. Hosted sessions expire, isolate users and cannot
reach arbitrary devices; DNS/domain/deployment actions remain operator-owned.

The checked-in Workbench Dockerfile uses the pinned multi-architecture digest
of `hexpm/elixir:1.20.2-erlang-29.0.4-debian-bookworm-20260713-slim`, runs the
release as uid/gid 65532, declares only `/tmp` and `/var/lib/wotex-lab` as
ephemeral write locations, and uses the fixed `/healthz` loopback probe. The
documented run profile adds read-only root, tmpfs mounts, memory/CPU/PID limits
and loopback-only publication. `bin/check_oci_source.exs` validates these
properties without building; its opt-in Docker `--check` lane validates the
build graph. Neither is a built-image/runtime/cleanup result.

The reference host owns Phoenix/LiveView, PromEx and BeamLens dependencies.
WLB.10's GreptimeDB process is opt-in; its endpoint/data volume/TTL and resource
limits are explicit. Do not bundle an unauthenticated public database listener.
The no-LLM/no-durable-store profile must run the same core experiments. UI,
metric codecs, BeamLens provider/native dependencies and chart assets have
separately pinned compatibility/license/security cohorts. Whole-VM dependency
state cannot be used as an untrusted multi-tenant isolation boundary.

The Explorer analytics profile follows the
[interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md).
Chart presentation follows the
[native SVG decision](../decisions/0007-native-svg-chart-rendering.md).
Record Explorer/Polars native artifact, Nx, Decimal and chart compatibility
independently; the base archive consumer must still exclude Explorer and Kino.
Archive status and vulnerability warnings need explicit adoption decisions.
An advisory metadata conflict requires version-specific evidence, not a broad
audit disable. `kino_explorer` is not an admitted new required dependency.
Chart wrappers cannot introduce a client-side renderer/dialect or widen the
native descriptor to external URLs, arbitrary expressions or raw JavaScript.

Nerves is a required delivery lane: name the supported target (`rpi4` baseline),
pin the Nerves system/firmware/toolchain, supply a prebuilt bootable image with
integrity/license information, and test offline/start/reconnect plus a recorded
on-target smoke. Host compilation alone cannot pass hardware execution.
The target uses the numerical baseline and explicit supported network adapters;
native EXLA/Maude are capability-specific, not assumed available on firmware.
Build instructions accompany the image; no embedded compiler is required to
try it. Real hardware availability is an evidence prerequisite, not a fabricated
result or removal from scope.

`hosts/nerves/` names only the `rpi4` target and pins Nerves 1.15.0,
`nerves_system_rpi4` 2.1.1 and its aarch64 15.3.1 toolchain closure. Firmware
boot starts one eight-child Lab instance but no experiment, listener,
discovery, model or effect. `WotexLabNerves.Smoke.run/0` is operator-invoked:
it runs the BinaryBackend thermal baseline and reads a simulated Property
through two separately owned loopback Thing processes, returning a public
evidence record without invoking an Action. Its boot assertion is `not_run` on
the host target and can pass only in an rpi4-compiled release. The checked-in
host test and `bin/check_nerves_source.exs` prove this source contract. They do
not substitute for the still-required released-package firmware build,
firmware checksum/license dossier, offline boot, physical reconnect or recorded
on-target smoke.

Maude licensing, binary provenance and platform support follow WLB.09. The
native containment distributions follow WLB.06 profile 2.0.2: ship reviewed
platform/architecture binaries with SHA-256, source/Cargo-lock identity,
licenses, signing/provenance and no Python interpreter requirement. The package
currently includes Rust sources, not precompiled binaries. Provisioning is
explicit; the first tensor neither builds nor starts the helper. Source tests
compile the feature-gated Rust probes separately. macOS source evidence is not
proof of Linux Bubblewrap integration; the WLB.06 Linux lane executes that
integration in source. The WLB.06
kernel-isolated OCI profile carries hostile-target isolation in source; a hosted
worker still owns runtime hardening, image provenance and lifecycle. Those
profile and artifact obligations remain required.

All optional distributions declare their dependency/license closure. Creating or
publishing remote state, domains, packages, firmware releases or images is a
maintainer action. Visibility changes are always manual user-only actions.
