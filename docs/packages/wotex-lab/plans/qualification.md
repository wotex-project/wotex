# Wotex Lab qualification runbook

This runbook qualifies a completed Lab source revision through artifact,
simulated-peer and hosting environments. Physical-device checks apply only
when a physical deployment is explicitly selected. This runbook does
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

## Simulator baseline

The default Lab qualification uses software devices and real local transports.
It requires no physical device, firmware flash or vendor account. The
[simulator catalogue](../labs/simulators.md) identifies the independent peers,
their pinned inputs and the Elixir tests that exercise WoTEx against them.
Testcontainers owns the new container peers' startup, readiness and cleanup;
ordinary package tests do not start Docker.

A protocol simulator supplies observable register, Property, Action or Event
behavior. A broker alone does not simulate a device, and generated readings
alone do not establish protocol interoperability. Record each demonstrated
boundary separately. Sensor dynamics and fault schedules use explicit inputs;
frontend code contains no fabricated device state.

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

## Optional Nerves hardware qualification

Build the declared `rpi4` firmware from released or verified candidate
dependencies. Record the Nerves system and toolchain, firmware digest, licenses
and `fwup` result. On named hardware, test offline boot, the inert startup
contract, operator-invoked smoke, reconnect behavior and cleanup.

Host-target tests and firmware assembly are source or artifact evidence. They
do not claim a physical boot. This additional deployment qualification is
outside the default simulated Lab. Absence of an rpi4 device does not block
Lab source implementation or simulator qualification.

## Release and API decisions

The repository may generate compatibility reports and release dossiers.
Selecting a public release candidate, accepting an incompatible change,
declaring a stable API, tagging, publishing and changing visibility require a
human maintainer decision. No passing source or artifact gate makes those
decisions implicitly.
