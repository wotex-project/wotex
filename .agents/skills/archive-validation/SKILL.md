---
name: archive-validation
description: Validate package contents, artifact adoption or a public compatibility claim against exact archives. Use when packaging changes or archive evidence is requested; exclude routine code edits and release publication.
user-invocable: false
---

# Validate an exact archive

Input: the package, source revision, lockfile, claimed compatibility surface
and supplied archives when available.
Output: inspected archive contents and executed consumer results tied to
those exact inputs, or explicit limits on what was verified.

Read the package's `AGENTS.md` and its archive check
(`bin/check_archive.exs` or `bin/check_package.exs`). Identify which checks
build archives, fetch dependencies, require sibling artifacts or retain
evidence before running them. Use existing package tasks; do not add setup
helpers or treat source-path mode as artifact adoption.

For an authorized archive build, unset `WOTEX_PATH_DEPS` at the build step.
Check the package file list and unpacked members against the package's
allowlist, including `usage-rules.md` and the exclusion of contributor
instructions and local client state. Bind members to source bytes and confirm
runtime dependency identity with the existing archive check.

Exercise the claimed public seam through the package's isolated archive
consumer. Check passive dependency loading for libraries; reference hosts
have their own explicit application lifecycle. Standards or runtime compatibility
claims require the corresponding vectors and toolchain results, beyond a
successful build.

For Continuum wire compatibility, include the applicable schema version,
vector digests and canonical round-trip results. For Directory port adoption,
use its archive-only repository and operation contract suites when that lane
is requested. Load the package's evidence instructions only for that claim.

Report repository revision, package path, archive and lock digests, toolchain
and actual commands in chat. Preserve historical evidence until its owning
checks have been rerun. Do not infer readiness from source visibility or a
development version.
