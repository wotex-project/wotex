# Software fixture source verification

The explicit fixture tooling uses Elixir/OTP for source admission and evidence.
From the BACnet source checkout, run
`mix wotex.software.build --workspace /absolute/disposable/workspace`.
The workspace must be empty or contain a matching verified build manifest.
The fully qualified task is `wotex.bacnet.software.build`; the shorter name is
an alias owned by this root project.
The [POSIX guardian](../../interop/native/README.md) owns its local commands.
These test-support modules are loaded by the fixture workflow; BACnet runtime
dependency loading never invokes them.

`SoftwarePackage` verifies the exact BACstack version, inner checksum and outer
archive hash in the Mix lock. It checks the outer SHA-256 before decompression.
For Hex format 3, the inner checksum covers the version bytes, metadata bytes
and compressed contents in that order. Metadata terms are not evaluated.
The pinned archive contains 232 package files. Every installed file must match;
changed, missing or additional source files and links fail verification.
`hex_metadata.config` must match the archived metadata. The ordinary `.hex`
file is hashed as Hex-managed installation metadata, separately from the
package's source identity.

`SoftwareManifest` records fixture input hashes, artifact hashes and source
identities. Archive tables permit only regular files and directories, at most
4096 distinct members and 64 MiB total file bytes. Each member path remains
relative and excludes traversal. The fixed BACstack archive has a separate
1 MiB compressed limit; the C archive has a 16 MiB compressed limit.
Workspace artifacts and their intermediate directories
must be ordinary files and directories, with no symbolic links. Atomic receipt
writes preserve an occupied temporary path as a failure.

Source hashes include Elixir code, native headers and implementations, CMake
and Docker recipes, shell entry points, executable fixture corpora and the
project definition and lock. They are available in an archive without Git.
A commit/tree pair requires one complete successful Git result; the runner
must additionally establish that the hashed inputs match that committed tree.

`test/software/source_manifest_test.exs` binds WBA-C09/WBA-V13 to workspace,
archive, receipt and installed-source assertions. Its software-tagged case
requires `WOTEX_BACNET_SOFTWARE_WORKSPACE/bacstack.tar` and verifies the actual
pinned dependency, then rejects a changed copy. The Mix workflow and final
software cohorts remain separate acceptance obligations.

The build records both normal and ASan/UBSan peer versions, their static SDK
libraries and binary hashes. Its pinned Linux image records compiler, linker,
libc, CMake, operating system, CPU architecture, package versions and CMake
cache options. Build commands
retain separate arguments, exit status and bounded output hashes, including
failed commands. A ready manifest is written only after the build and inspection
succeed and its source files are unchanged. Reuse verifies the local artifact
files and independently reads the same image's binaries and metadata again.

The guardian holds a reusable native workspace lease. Its first compilation
uses a separate bootstrap owner, which releases the empty bootstrap lock on
caller death and acknowledges normal release. An interrupted initial build
without a ready manifest remains incomplete and is not silently reused.
`build_task_test.exs` exercises the actual Mix task lookup, wrong-root rejection,
unrelated-workspace preservation and software-tagged native reuse/tamper checks.
