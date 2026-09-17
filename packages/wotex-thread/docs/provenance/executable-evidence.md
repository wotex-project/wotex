# Executable evidence

Current implementation: bounded Dataset/daemon APIs and a first-party C++ SDK
host with semantic Dataset validation/export, interface/Thread enablement,
formation, management callbacks and commissioner lifecycle/admissions. Native
ExUnit and C++/process fixtures exercise real SDK/RCP software boundaries; their
presence is scoped evidence, not a complete Thread profile. Joiner execution,
state subscriptions, complete simulated-network/application workflows, Mix fixture
orchestration and final stress/native/package closure remain required.
The production runtime and explicit native build require no Python; dormant
Python native test drivers have been retired. Selected native lanes must fail if their SDK/peer/configuration
is absent. Physical-radio testing is a separate optional lane.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting and
the default unit/property/ExUnit suite. For the native build change, `mix lint`
(strict Credo and Dialyzer), `mix doctor`, `mix docs`, `mix hex.audit` and
`mix deps.audit` also passed. `mix hex.build` passed with `WOTEX_PATH_DEPS`
unset and included the Mix task, native C guardian and no generic Python
builder. An unpacked out-of-tree package compile and the Application-free
structural check remain separate release checks. Runtime path dependencies
require the explicit switch; the archive preserves ordinary Hex dependency
declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Mix native build, 2026-09-17

`Wotex.Thread.Native.Source` validates gzip tar member type, root, path and
finite count/aggregate size before extraction to an empty absolute directory.
It now streams pinned codeload HTTPS archives with TLS peer/hostname validation,
120-second deadline, 128 MiB body limit and exact SHA-256 before atomic
publication. Cached regular files are rehashed. The pinned Mbed TLS framework
archive was fetched and matched its checked-in SHA-256 in a manual native-source
smoke run. GitHub codeload's one PAX global metadata entry is admitted before
regular-file path validation; other special entries remain rejected.
It strips special file mode bits and rejects links. The reviewed Spinel and
discerner edits require the exact pinned source hash, exact replacement counts
and exact patched hash before writing. `native_source_test.exs` checks accepted
regular files, executable permissions, wrong roots, links, symlinked output,
bad patch hashes, second application, unknown source, traversal, absolute
names, links, device entries and FIFOs. The generic Python build utility and
its Python unit driver have been replaced by the Mix task and ExUnit checks.

`Wotex.Thread.Native.Workspace` now rejects invalid and duplicate task arguments,
symlink paths, unrelated nonempty directories and incomplete builds. Its manifest
owner hashes required regular-file artifacts and verifies identity and hashes
without invoking the builder on reuse. A failed build retains an exclusive
marker and requires disposal. `native_workspace_test.exs` executes those cases.
`native_command_test.exs` compiles the C build guardian and tests exact argument
execution, output limits and deadline cleanup. The Mix task uses that guardian
for tool probes, CMake configure/compile and ELF inspection.

In a disposable Debian 12 arm64 container, Elixir 1.18.4/OTP 27, GCC/G++
12.2.0, CMake 3.25.1 and Ninja 1.11.1 built the pinned OpenThread host through
`mix wotex.native.build --workspace /output/native6`. A second invocation
verified and reused the completed workspace without rebuilding. The manifest bound the
three archive SHA-256 values, source tree, tool executables, build logs, JSON
header and host ELF. The resulting host SHA-256 was
`41badd90f953149a1dc808aa6e02c708632f72035d95a5dd30223962dacb70f2`;
with networking disabled it emitted exactly one `openthread` ready frame for
revision `5c8c318627954c99cd1a957a290bbd4b1027d04b`. The same lane's CMake
probe did not find Python and its successful build did not invoke Python.
This is an additional architecture build smoke, not the required x86_64 lane,
SDK interoperability, native corpus or full WTH-B01 acceptance.

## Python-free injected ownership peer, 2026-09-16

The BEAM ownership fixture is now `test/fixtures/sdk_bridge.escript`. ExUnit
copies it with an absolute `escript` interpreter path before opening the Port.
It reads and writes the same C07 frames, mode files and request log as the
previous injected fixture. The production Port still clears the child
environment; a direct empty-environment smoke test opens and replies, and
`test/wotex/thread/sdk_bridge_test.exs` passes 31/31, including malformed
frames, forged handles, deadlines, ignored SIGTERM cleanup, Dataset,
management and commissioner cases. This is an injected peer, not SDK or radio
interoperability evidence. The dormant standalone Python native drivers were
subsequently retired. WTH-B01 Mix/ExUnit acceptance remains open.

A BEAM peer loses SIGTERM delivered during emulator startup. With a 100 ms
startup deadline the escript was often still booting, so the owner's SIGKILL
escalation intermittently returned `cleanup_timeout` and the wrong-ready and
open-reply modes expired before they were exercised. The startup and open
deadline cases now use `test/fixtures/startup_stall_peer.c`, compiled by the
test with `/usr/bin/cc`; it honors SIGTERM from process creation and asserts
exact `timeout` within 1100 ms. Wrong ready identity, invalid open result and
open failure use the escript with the ordinary 5000 ms deadline and assert
exact `invalid_response`, `invalid_response` and `storage_unavailable` plus the
logged `open`/`close` frames. Both cases passed five consecutive runs beside 24
busy shell loops on macOS arm64 with Elixir 1.20.2/OTP 29.0.4, where the
previous form failed in 45 of 50 loaded connects. These remain injected-peer
ownership assertions.

## Acceptance boundary

[WTH.13](../specs/WTH.13-native-backend.md) defines the required native binary,
Mix/ExUnit tasks, exact version lanes and credit/resource tests. Its corpus is
specified and unexecuted. A passing current gate, a listed test path or a source
hash cannot establish execution of that target. Each completed software run must
bind case, corpus, source, SDK/binary, toolchain and cleanup-result hashes.
The mandatory runtime matrix is Elixir 1.18.4/OTP 27.3.4.15 and Elixir
1.20.2/OTP 29.0.4. Only identified executed lanes count as passing evidence.

## Committed source identities

These hashes identify the committed implementation/test inputs reviewed here;
they are not release artifacts or a claim about every future run. Fixture WIP is
excluded. Native software results require their own immutable manifest.

| Source | SHA-256 |
| --- | --- |
| `test/software/native_owner_test.exs` | `c247296bcc4b61170ea0d625c3c1e72c01b95df57f063408262657c972097c0a` |
| `test/software/native_dataset_test.exs` | `68fbf4c69a9a460e20a4470844ea8029b740215af8da9a9c388b482a41a65811` |
| `priv/openthread/host.cpp` | `9253964efa577ff27401c912865500322f0bd7636f30453fe59c1128c573a083` |
