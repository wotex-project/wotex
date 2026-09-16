# Executable evidence

Current implementation: bounded Dataset/daemon APIs and a first-party C++ SDK
host with semantic Dataset validation/export, interface/Thread enablement,
formation, management callbacks and commissioner lifecycle/admissions. Native
ExUnit and C++/process fixtures exercise real SDK/RCP software boundaries; their
presence is scoped evidence, not a complete Thread profile. Joiner execution,
state subscriptions, complete simulated-network/application workflows, Mix fixture
orchestration and final stress/native/package closure remain required.
The production runtime requires no Python; existing Python build/test utilities
are current tooling. Selected native lanes must fail if their SDK/peer/configuration
is absent. Physical-radio testing is a separate optional lane.

## Mandatory local gate

`WOTEX_PATH_DEPS=1 mix check` runs compile warnings-as-errors, formatting, strict
Credo, unit/property tests and minimum 95% coverage, Dialyzer, Doctor, ExDoc,
dependency audit, Hex packaging, unpacked out-of-tree compilation and the
Application-free structural check. Runtime path dependencies require the explicit
switch; the archive preserves ordinary Hex dependency declarations.
The pinned Decimal parser regression remains active; there are no advisory
waivers. See SECURITY.md and the dependency-security test.

## Native source admission groundwork, 2026-09-17

`Wotex.Thread.Native.Source` validates gzip tar member type, root, path and
finite count/aggregate size before extraction to an empty absolute directory.
It strips special file mode bits and rejects links. The reviewed Spinel and
discerner edits require the exact pinned source hash, exact replacement counts
and exact patched hash before writing. `native_source_test.exs` checks accepted
regular files, executable permissions, wrong roots, links, symlinked output,
bad patch hashes, second application and unknown source. These functions are
not yet called by a Mix native build task; the Python build utility remains the
current build entry point, and WTH-B01 is not accepted.

## Python-free injected ownership peer, 2026-09-16

The BEAM ownership fixture is now `test/fixtures/sdk_bridge.escript`. ExUnit
copies it with an absolute `escript` interpreter path before opening the Port.
It reads and writes the same C07 frames, mode files and request log as the
previous injected fixture. The production Port still clears the child
environment; a direct empty-environment smoke test opens and replies, and
`test/wotex/thread/sdk_bridge_test.exs` passes 31/31, including malformed
frames, forged handles, deadlines, ignored SIGTERM cleanup, Dataset,
management and commissioner cases. This is an injected peer, not SDK or radio
interoperability evidence. Python remains in the separate native build and
native test utilities pending WTH-B01 Mix/ExUnit migration.

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
| `test/native/management_test.py` | `c2bc8d0271ed2b6ff2f3db593b1bae8a28c95bbf4ad51b695732b96778352557` |
| `test/native/commissioner_test.py` | `408d99e4e0fc57d1e0f107baf6808865d3d6b0f8a3419c9cbf72a6673219e573` |
| `priv/openthread/host.cpp` | `9253964efa577ff27401c912865500322f0bd7636f30453fe59c1128c573a083` |
