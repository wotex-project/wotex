# Wotex Lab qualification runbook

This runbook qualifies a completed Lab source revision through artifact,
hosting and device environments that are not part of implementation. It does
not define public behavior and does not decide `implementation_status` in the
specification catalogue.

## Boundary

Implementation includes the Elixir and Rust library, the LiveView host, Svelte
islands, TypeScript client, Vite and Storybook builds, Nerves source, artifact
builders, validation scripts and their executable tests. Frontend code may use
the browser languages and Node-based build tools selected by WLB.11 and WLB.12.
The base `wotex_lab` library remains independent of those tools, and the
reference release starts no Node runtime process.

Qualification establishes that a particular package archive, OCI image, npm
archive, static site, hosted service, firmware image or physical device works
in its named environment. An unavailable credential, service, runner or device
leaves that claim unqualified. It does not turn implemented source back into
planned source.

## Inputs and records

Qualify one clean commit. Record the commit, package path, lockfiles, source and
artifact digests, dependency cohort, toolchains, operating system,
architecture, command lines, case counts, resource envelope and result-artifact
digests. Candidate archives and published artifacts are different cohorts.

Transient logs and receipts belong under `docs/tasks/local/wotex-lab/`. A
reviewed reproducible result may be added to `provenance/`; historical records
are never relabelled for changed source or artifacts.

## Candidate artifacts

Build and inspect the base package, Workbench source archive and release, OCI
image, generated npm archive, static documentation and static Storybook from the
same admitted cohort. Run each fresh consumer without repository paths or Git.
Record package contents, Software Bill of Materials (SBOM), licenses, advisory
review, runtime identity, health checks, resource limits and cleanup.

Candidate-archive evidence does not establish Hex, container-registry or npm
adoption. Building a deployment artifact does not establish that a hosted
service serves it.

## Hosted adoption and publication

Publication, domain configuration, credentials, default-branch deployment and
remote service changes are maintainer actions. The implementation may supply
fail-closed workflows, manifests, preflight checks and rollback logic.

After a maintainer publishes or deploys an artifact, record its immutable
identity, public or private access decision, URL where applicable, response
headers, health result, browser cohort and rollback result. Repository
visibility changes are manual user-only actions and are never performed by
this runbook.

## Nerves hardware

Build the declared `rpi4` firmware from released or verified candidate
dependencies. Record the Nerves system and toolchain, firmware digest, licenses
and `fwup` result. On named hardware, test offline boot, the inert startup
contract, operator-invoked smoke, reconnect behavior and cleanup.

Host-target tests and firmware assembly are source or artifact evidence. They
do not claim a physical boot. Absence of an rpi4 device does not block source
implementation.

## Release and API decisions

The repository may generate compatibility reports and release dossiers.
Selecting a public release candidate, accepting an incompatible change,
declaring a stable API, tagging, publishing and changing visibility require a
human maintainer decision. No passing source or artifact gate makes those
decisions implicitly.
