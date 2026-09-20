# Native artifact foundation

Specification version: 0.2.0. Contract: accepted foundation.

This contract governs native artifacts built, qualified or adopted by the
WoTEx repository. It applies to native executables, shared libraries, firmware
inputs, target root-filesystem overlays and virtual-machine or controller
images. It does not turn WoTEx packages into a general binary catalogue.

The contract separates four concerns:

1. A package owns its source, build inputs and declared qualification profiles.
2. Root tooling owns inventory, planning, canonical identity and verification.
3. A consumer owns artifact adoption and runtime composition.
4. An evidence owner records what ran on which target without promoting
   unavailable hardware, runners or published artifacts to passing states.

`tooling/packages.yaml` remains the closed repository inventory. Native
artifact tooling MUST read package and profile membership from that manifest.
Directory names, filesystem globs and successfully loaded modules MUST NOT add
work to the inventory or make an undeclared artifact admissible.

## Ownership boundaries

Each package that produces a native artifact owns:

- the exact upstream source revision and digest;
- first-party native source and patches;
- build features and supported target/profile combinations;
- the command that creates the artifact in a caller-supplied workspace;
- package-specific functional, sanitizer and interoperability evidence; and
- the runtime owner for any executable process.

Root tooling owns:

- schema validation;
- canonical build identity and payload verification;
- change-to-matrix planning;
- bounded download, extraction and cache adoption;
- target dependency inspection; and
- human-readable and machine-readable inspection commands.

Root tooling does not own protocol behavior, daemon policy, firmware startup or
package-specific test meaning. A generated child specification may remove
repetitive executable-path plumbing, but the package continues to own
supervision, custody, timeouts, output bounds, cleanup and error semantics.

The Lab may consume artifacts and record reference-host evidence. No package
may depend on Lab for artifact construction, identity or verification.

## Native artifact descriptor

Every artifact-producing profile MUST have a schema-validated descriptor. The
descriptor is data available to root tooling without executing an artifact or
starting an application. It contains:

- descriptor schema version;
- package name and profile name;
- artifact kind;
- supported target tuples and explicit unsupported tuples;
- source components and patch sets;
- toolchain and build-environment inputs;
- normalized build options and features;
- expected output paths and file kinds;
- runtime compatibility requirements;
- external shared-library requirements, when applicable;
- legal-information and provenance inputs; and
- the package build and qualification tasks.

An unsupported tuple carries a reason. Omitting a tuple and declaring it
unsupported are distinct: omission makes no support claim, while an explicit
exclusion explains why a planner must not create that cell.

Descriptors MUST NOT contain credentials, machine-specific absolute paths,
mutable tags, local cache locations or publication state.

## Canonical identity

An artifact has two independent SHA-256 identities:

- The **build identity** covers every input allowed to affect the output.
- The **payload identity** covers the complete adopted output.

Both identities use the full lowercase 64-character hexadecimal digest.
Truncated forms may appear in logs or filenames but MUST NOT authorize cache
reuse, artifact adoption, qualification or publication.

The build-identity document contains at least:

- descriptor schema version and artifact format version;
- WoTEx package name and repository revision;
- complete first-party source digest;
- every upstream source URL, revision and verified digest;
- ordered patch identities and their content digests;
- target operating system, architecture, endianness, libc and ABI;
- compiler, linker, SDK, Rust toolchain and relevant language-standard versions;
- immutable build-container digest when a container is used;
- OTP and native-interface compatibility where they can affect the output;
- normalized features, flags and build options;
- qualification profile, including sanitizer configuration;
- base system, root filesystem, guest or controller-image identity when used;
  and
- digests of transitive native inputs admitted by the build.

Canonical identity uses the JSON Canonicalization Scheme from
[RFC 8785 (June 2020)](https://www.rfc-editor.org/rfc/rfc8785) over a document
that contains no floating-point values. Lists whose order has no semantic
meaning are sorted before encoding. Map keys are strings. Absence and an empty
collection remain distinct. Tests MUST prove that reordered maps and unordered
sets retain identity while any semantic input change moves it.

The payload identity covers a deterministic manifest of every output entry:
relative path, kind, size, normalized mode, link target where permitted and
SHA-256 for each regular file. Archive compression, timestamps and host user or
group identifiers are not semantic payload inputs. The enclosing archive MAY
have an additional transport digest.

The artifact manifest records both identities and repeats the canonical build
inputs required to inspect them. The manifest schema is independently
versioned. A schema reader rejects unknown major versions and unknown required
fields; it preserves unknown optional fields when it rewrites a manifest.

## Build and retrieval equivalence

A local source build and a retrieved prebuilt artifact are two delivery paths
for the same artifact contract. Either path MUST produce or admit the same
build identity, manifest schema and payload rules.

Source fallback is explicit. Failure to retrieve an artifact MUST NOT silently
change a qualification or release-candidate run into a source build. A caller
selects one of these modes:

- `source`: build only from the admitted source cohort;
- `prebuilt`: retrieve and verify only;
- `prefer_prebuilt`: retrieve first and use a source build only when the caller
  explicitly allows the fallback in that invocation.

The selected mode and the path actually used are evidence fields. A source
build is not evidence that a hosted or published artifact exists.

Remote bytes are untrusted until verification completes. Every retrieval path
MUST verify the expected full digest independently of transport security or a
registry's internal content addressing. Credentials are scoped to the selected
origin and MUST NOT be forwarded across redirects to another origin.

## Safe adoption and cache rules

Artifact verification occurs before files become visible at the canonical
cache location. Adoption uses a fresh sibling staging directory, verifies the
complete payload, then installs with one same-filesystem atomic rename. A
failed attempt removes only its private staging directory and never replaces a
previous valid entry.

Extraction has explicit limits for:

- compressed bytes;
- entry count;
- total expanded bytes;
- one expanded file;
- path length and nesting depth; and
- manifest size and decoding depth.

Archive entries MUST use normalized relative UTF-8 paths. Absolute paths,
empty components, `.` or `..` components, duplicate normalized paths, device
nodes, sockets, FIFOs and escaping hard links are rejected. Symlinks are
rejected unless the descriptor explicitly permits them and their normalized
targets remain inside the artifact root. Set-user-ID, set-group-ID and
world-writable modes are rejected unless a package-specific contract names the
exact path and reason.

A cache entry is valid only when its manifest parses, both identities verify,
its descriptor and target remain admitted, and every declared output is
present with the recorded kind, mode, size and digest. Directory presence,
filename agreement or an unverified manifest is insufficient.

Cache keys include the full build identity. Concurrent builders use an
exclusive per-identity lease with a bounded wait. A process that loses its
lease cannot publish or adopt its result. Garbage collection never follows
symlinks and removes only entries it has parsed as cache-owned.

## Target dependency closure

A target artifact containing ELF files MUST be checked against the exact target
root filesystem and all sibling artifacts admitted to the same assembly. The
check validates ELF class, architecture, endianness and every `DT_NEEDED`
entry. A matching filename from the wrong target or an unadmitted host library
does not satisfy the requirement.

The check reports all unresolved or incompatible dependencies in one result.
It runs before firmware, guest-image or release assembly. Package-local success
does not replace the assembled-target check because another admitted artifact
may provide or conflict with a required library.

Equivalent format-specific checks are required before WoTEx claims support for
a non-ELF target. No generic filename-only fallback makes such a target green.

## Runtime contract

Artifact construction, retrieval and adoption are build-time or provisioning
operations. Loading a WoTEx package or starting its application MUST NOT build,
download, extract, publish or auto-start a native artifact.

A native executable starts only under an explicit consumer-owned child
specification or operation. Its package contract defines:

- executable admission and digest verification;
- argument and environment allowlists;
- working-directory ownership;
- standard-input, standard-output and standard-error bounds;
- request and shutdown deadlines;
- descendant custody and cleanup;
- restart behavior; and
- structured error values.

Generated wrappers cannot weaken those requirements or turn a process-global
resource into implicit application startup.

## Change-aware qualification matrix

Root tooling computes qualification cells from the closed manifest. A cell is
the tuple:

`{package, profile, target, toolchain lane, system identity}`.

The planner provides human-readable, JSON and count output. Its selection rules
are pure and independently tested. At minimum:

- a package descriptor, source, patch or native test change selects that
  package's admitted cells;
- a target or system pin change selects every package cell using that target;
- a toolchain or build-environment change selects every cell using that input;
- planner, builder or verifier changes select a declared smoke cohort;
- documentation-only changes select no native cells unless they change a
  machine-read contract; and
- an unusable diff selects the declared smoke cohort and reports the fallback
  instead of returning an empty plan.

The existing WoTEx dependency graph still determines affected dependents. The
native planner refines those packages into target/profile cells; it does not
replace `mix affected` or maintain another dependency graph.

The planner validates each emitted slice against the executor's expansion
limit before handing the matrix to CI. It divides larger plans along semantic
boundaries such as target or system identity. An oversized plan fails in the
planner job so branch protection receives a failing check rather than a
workflow-expansion error without a job result.

The initial required external cells remain explicit:

- BLE Linux x86_64 production and sanitizer builds;
- BLE Linux x86_64 virtual-controller guest evidence;
- Thread cells whose build identity records the OpenThread revision, patches
  and security disposition; and
- the declared Nerves target with its exact system, firmware and toolchain
  identities.

An ARM64 host result does not satisfy a Linux x86_64 cell. Emulation is a
separate profile and does not replace native-runner evidence unless the owning
package specification explicitly grants that equivalence. Host compilation
does not satisfy physical-device evidence.

## Security and provenance

Every upstream source is pinned by immutable revision and verified digest.
Every patch is stored or generated from reviewed repository content and enters
the build identity. Advisory results record the queried source identity,
database or feed revision, observation time and disposition.

An unresolved known vulnerability blocks adoption by a release-candidate or
distribution gate. A source update or reviewed patch may clear the block after
the affected package evidence is rerun. An exception requires a maintainer
security decision that names the exact source revision, affected artifact
identities, scope, expiry and compensating controls. Tooling cannot infer or
grant that decision.

Each adopted artifact carries or links by digest to:

- source and patch receipts;
- build manifest;
- payload manifest;
- dependency closure;
- licence texts and notices;
- an SBOM for the artifact's active contents;
- qualification results; and
- signing or attestation data when the selected distribution profile requires
  it.

Legal information is part of the admitted payload. Missing legal information
fails the applicable artifact gate even when the executable passes functional
tests.

## Evidence and adoption states

The following states are independent:

- `declared`: a valid descriptor exists;
- `built`: source produced a locally verified artifact;
- `qualified`: required tests ran on the named target/profile;
- `adopted`: an independent consumer used the verified artifact;
- `published`: a maintainer-published immutable artifact was retrieved and
  verified; and
- `device_verified`: the declared physical target ran the required procedure.

No state implies a later state. A locally built artifact is not published. A
host smoke is not device evidence. A package test is not assembled-firmware
evidence. A manifest generated without verifying its payload is not adoption.

Evidence records name the repository revision, descriptor version, full build
and payload identities, runner architecture, operating system, toolchain,
selected delivery mode, start and finish time, command, result and retained
log digest. Unsupported, skipped, unavailable and not-run cells remain distinct
from passed cells.

## Tooling surface

The root project provides bounded commands for these operations:

- plan qualification cells;
- build one declared cell in a caller-supplied absolute workspace;
- inspect a descriptor or artifact manifest;
- verify a local artifact without adopting it;
- retrieve one exact artifact into private staging;
- adopt a verified artifact into the local cache;
- inspect the assembled target dependency closure; and
- list or remove exact cache entries.

Commands accept one package or one explicit cell by default. Repository-wide
execution requires an explicit flag. Inspection and planning perform no
downloads, builds, publication or runtime startup.

No automated agent command publishes an artifact, creates a tag, changes a
remote, changes repository visibility or promotes an evidence state.

## Required evidence

Implementation is incomplete until tests cover:

| Area | Required cases |
| --- | --- |
| Descriptor | valid descriptor; unknown version; missing required field; undeclared package/profile/target; explicit unsupported tuple |
| Identity | deterministic canonicalization; every semantic field changes identity; order-insensitive sets; full-digest enforcement; schema-version movement |
| Retrieval | success; missing artifact; digest mismatch; redirected credentials; partial download; bounded error aggregation |
| Extraction | traversal; absolute path; duplicate normalized path; symlink escape; special file; oversized archive, entry, manifest and expansion; interrupted adoption |
| Cache | valid reuse; corrupt manifest; changed payload; concurrent builders; stale lease; prior valid entry preserved on failure; bounded garbage collection |
| Dependency closure | satisfied libraries; all missing libraries reported; wrong architecture/class/endianness; sibling-provided library; conflicting providers |
| Matrix | each change class; dependent packages; unsupported cells; unusable diff fallback; deterministic order; empty documentation plan; visible limit failure; semantic slicing |
| Runtime | explicit startup; digest rejection; argument/environment bounds; output saturation; owner loss; timeout; descendant cleanup; structured failures |
| Evidence | state non-implication; runner architecture; source versus prebuilt mode; unavailable runner; physical-device separation; security exception expiry |

Package specifications add protocol-specific and interoperability evidence.
They reference this contract instead of restating its identity, extraction,
cache or state rules.

## Implementation slices

The foundation is delivered in dependency order. A later slice does not weaken
an earlier slice or make unimplemented operations appear available.

| Slice | Source status | Evidence status |
| --- | --- | --- |
| Descriptor, identity, inspection and planning | Implemented | Focused local tests pass; declared external cells have not run merely because they can be planned |
| Payload manifest and local verification | Planned | Not run |
| Cache adoption and concurrency | Planned | Not run |
| Assembled-target dependency closure | Planned | Not run |
| Exact prebuilt retrieval | Planned | Not run |
| Mechanical runtime wrappers | Planned where repetition justifies them | Not run |

These statuses describe repository-owned source. They do not promote a
descriptor or planned cell beyond `declared`, and they do not claim hosted,
published, x86_64, firmware or physical-device evidence.

1. Add descriptor parsing, schema validation, canonical build identity,
   manifest inspection and pure matrix planning. These operations are
   read-only.
2. Add deterministic payload manifests and local verification, including the
   adversarial archive corpus. Verification still performs no cache adoption.
3. Add private staging, atomic local cache adoption, leases and bounded garbage
   collection.
4. Add assembled-target dependency checks and connect package qualification
   profiles to planned cells.
5. Add retrieval from declared origins with independent digest verification.
6. Add package-specific executable wrappers only where they remove repeated
   plumbing without taking lifecycle policy from the package.

Publication, release promotion and visibility changes are not implementation
slices. They remain maintainer actions after the corresponding local and
independent-consumer evidence exists.

## Non-goals

This foundation does not define:

- a public binary-package repository;
- a general operating-system package manager;
- automatic publication or release promotion;
- repository visibility policy;
- protocol behavior or conformance;
- firmware startup policy;
- a replacement for Hex package archives; or
- permission to distribute third-party binaries whose licences have not been
  reviewed.
