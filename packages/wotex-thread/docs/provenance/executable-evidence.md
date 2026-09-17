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

## Report flow credit primitives, 2026-09-17

`priv/openthread/flow.hpp` is the shared native report-credit owner. It admits
at most 64 live streams, assigns strictly increasing session report sequences,
transmits only with session frame/byte credit and `min(16, queue_limit)` stream
credit, and records each exact encoded length including the newline. Reports
without credit enter one bounded queue of 64 reports and 1048576 reserved bytes;
each queued report reserves its widest (maximum-sequence) encoding and obeys its
stream's `queue_limit`. Acknowledgements release only an exact cumulative prefix
for the same 32-character session generation; zero, repeated, decreased,
untransmitted and wrong-byte values fail without changing counters. Retirement
discards unsent reports, writes exactly one barrier through a separate control
writer and retains outstanding credit until an ordinary acknowledgement covers
it. A queued stream without credit does not block another stream. Writer failure
or sequence/byte-counter exhaustion marks the generation failed.

`Wotex.Thread.OpenThread.ReportLedger` is the matching immutable BEAM ledger. It
registers only the next sequence for a live stream within 64 reports, 1048576
bytes and the stream's `min(16, queue_limit)` bound. A report joins the
cumulative acknowledgement only after token-matched consumption or an exact
retirement barrier, which deletes the stream so later reports or barriers fail.

`test/native/flow_test.cpp` asserts per-stream and session credit, byte credit,
queue and `queue_limit` overflow, re-encoding of queued reports with their
assigned sequence, invalid acknowledgements without mutation, retirement
barriers, live-stream capacity, writer failure and sequence/byte exhaustion.
`test/native/contract_driver.cpp` receives corpus inputs only and prints
observations from the production parser and flow owner.
`test/wotex/thread/native_contract_test.exs` (tag `software`, driver selected by
`WOTEX_THREAD_CONTRACT_DRIVER`) compares those observations with
`native-port-v1.json`: WTH-B-F01–F05 through the production request validator,
F07–F10 through report credit accounting with exact frame lengths and sequences,
and F14/F15 through an interactive session whose reports and barriers are
registered, consumed and acknowledged by the production BEAM ledger.
`report_ledger_test.exs` runs in the default gate.

| Lane | Toolchain | Result |
| --- | --- | --- |
| macOS arm64 | Apple clang 21.0.0, CMake 4.4.3, ASan/UBSan without LeakSanitizer; Elixir 1.20.2 / OTP 29.0.4 | 3/3 CTest; 3/3 contract tests |
| Linux arm64, image `sha256:95ca03c1f4714893eb0f33791ecb05eb8a234816fe96aa9a7168c1c3c9012b68` built from `hexpm/elixir@sha256:473f77ee88977dc8cc5d05fb91080a308be86be3fc27d50aef9a837d07c8268b` | Debian 12.15, GCC/G++ 12.2.0-14+deb12u1, CMake 3.25.1, Ninja 1.11.1, ASan/UBSan/LeakSanitizer; Elixir 1.18.4 / OTP 27.3.4.15 | 3/3 CTest; 7/7 contract and ledger tests, seed 0 |

The Linux lane configured `priv/openthread` with `-DCMAKE_BUILD_TYPE=Debug
-DWOTEX_NATIVE_SANITIZERS=ON -DWOTEX_NATIVE_TEST_SOURCE=...`, built with Ninja,
ran CTest and then `mix test test/wotex/thread/native_contract_test.exs
test/wotex/thread/report_ledger_test.exs --include software --seed 0` with
`WOTEX_PATH_DEPS=1`. Its contract driver SHA-256 was
`d0541054faf950b94b8660a69466f1a2fe0fbe4f24aed9778574e91cfab7c2c8` and flow
test `9c5e1c9cca00b8bf814d38e50849575884377d74c7afe14ec81a18155bf58e82`. A
negative control that removed the cumulative-byte comparison made the native
flow test abort and failed F08.

| Source | SHA-256 |
| --- | --- |
| `priv/openthread/flow.hpp` | `966c8e327fd5132b8b4277854a240f8f22d2f9d562a0f8ac431e73b06d32de20` |
| `priv/openthread/protocol.hpp` | `5b941710d7cfbd48491e98cc2d604841f0d22d4184d82a154eae5e80b45b5ce8` |
| `test/native/flow_test.cpp` | `9b8ac61a70210a358830f6ca71ba1bfc9371aa465e4a6d06a1d12ac302c2e809` |
| `test/native/contract_driver.cpp` | `73f94ec3f7950ac750d7155455b85c842bfe36fe18aa3cf3e84f6cd7ff792db4` |
| `lib/wotex/thread/open_thread/report_ledger.ex` | `0bd48fb5c70449c6182f4849322a2740350fd446d2dd0be320deb1bcf76622ed` |
| `test/wotex/thread/native_contract_test.exs` | `d738927ba440a4ef6be80ea8534585d53f0f867114d5aa2d0db06a0c77e93d47` |
| `docs/specs/fixtures/native-port-v1.json` | `91d70393eb17360ea253f249ff3710d568c3fd12941b9eae91f7c8aa6dc3ba18` |

These are production credit primitives and a contract driver, not a helper
process.

## Host flow initialization and output reservations, 2026-09-17

The BEAM connection now writes exactly one `flow_open` frame after the ready
frame and before `open`. Its session generation is 16 fresh bytes from
`:crypto.strong_rand_bytes/1` as 32 lowercase hexadecimal characters and is not
exposed through process status. The host accepts that frame once; a request
before it, a second initialization, an invalid generation or an acknowledgement
the report-flow owner rejects terminates the generation. `report_ack` is
admitted only with its exact five fields. The guardian applies the same inbound
validator to every owner line. Frames from JSON text decode integers as unsigned
values; the parser compares them as unsigned 64-bit integers, which the native
test's `2^64-1` acknowledgement exposed.

`priv/openthread/output.hpp` replaces the former single 128 KiB output string.
Frames keep stdout order while charging one of three reservations: at most 64
successful replies of up to 131072 bytes each, 256 control or failure frames of
up to 4096 bytes each, and 64 credited report frames within 1048576 bytes.
A frame keeps its reservation until its final byte is written; an exhausted
reservation or a failed report-flow writer ends the generation rather than
blocking or evicting work. Ready, failure and close frames use the control
reservation; other successes use the reply reservation.

`test/native/output_test.cpp` asserts each lane's frame count, frame size and
aggregate bounds, independence between lanes, ordered partial nonblocking writes
with reservations held until completion, and closed-reader failure.
`protocol_test.cpp` adds exact `flow_open`/`report_ack` allowlists, unsigned
field bounds, version/event checks and the shared inbound validator. The escript
ownership peer records the initialization, and `sdk_bridge_test.exs` asserts
one valid, distinct, status-redacted generation before `open` for each
connection. `native_contract_test.exs` executes WTH-B-F06 against the real host:
the first frame equals the corpus ready frame, and after input closure and the
1000 ms grace no guardian, worker or member of their process groups remains.

On Linux the injected escript peer waiting for a release discarded `close` and
depended on SIGTERM. Elixir 1.18.4/OTP 27.3.4.15 needed about 1026 ms to shut
down an escript blocked on standard input after SIGTERM, beyond the 900 ms
escalation, so two deadline tests observed `cleanup_timeout`. The peer now
serves `close` while waiting, as the native host does, and those tests assert
the logged `close` frame. SIGTERM-ignoring cleanup remains covered by the
`close_stall` mode.

| Lane | Result |
| --- | --- |
| macOS arm64, Apple clang 21.0.0, Elixir 1.20.2 / OTP 29.0.4 | 4/4 sanitizer CTest; `sdk_bridge_test.exs` 33/33 |
| Linux arm64 minimum: image `sha256:95ca03c1f4714893eb0f33791ecb05eb8a234816fe96aa9a7168c1c3c9012b68`, Debian 12.15, GCC 12.2.0, CMake 3.25.1, Ninja 1.11.1, Elixir 1.18.4 / OTP 27.3.4.15, privileged container | `mix wotex.native.build` normal and `--sanitizers` hosts; 4/4 ASan/UBSan/LeakSanitizer CTest; Spinel matrix; 45/45 ExUnit (contract F01–F10/F14/F15, native owner, native Dataset/formation/management/commissioner and bridge tests) with the normal host; 8/8 software tests with the sanitizer host; seed 0 |
| Linux arm64 current: image `sha256:cd12556442e9d686112fc225e1b2ce62db1eb9f7e1fff22b9d9bf24591728535` from `hexpm/elixir@sha256:5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da` (arm64 manifest), same toolchain, Elixir 1.20.2 / OTP 29.0.4 | Same builds and commands: 4/4 CTest, Spinel matrix, 45/45 and 8/8 ExUnit |

The Linux run built the simulation RCP with `-DOT_PLATFORM=simulation
-DOT_APP_RCP=ON -DOT_RCP=ON -DOT_FTD=OFF -DOT_MTD=OFF -DOT_APP_CLI=OFF
-DOT_APP_NCP=OFF` from the manifest-bound patched SDK tree and the Dataset seed
and Spinel test from a sanitizer SDK configuration. Normal host
`7ffca56512e00b5ef31282feaf7e1b431ede2c21e6ea7b2795b9f0ad55525c10`, sanitizer
host `2261ad512583bb6c61943142ed0cbda064d920e756711c89c33ed341991dd974`, RCP
`62159ea108a52d31d06b97074d825632f0bd164e509b7625d864ecca36f5997b` and contract
driver `0c2335e7ba6757916aa98dc26e4a674d1792fd9a76602a123ff88e96cfa21f85`.
These builds embed their workspace path, so binary hashes differ between
workspaces. The lane was a manual container script, not the specified
`mix wotex.software.build`/`run` tasks.

| Source | SHA-256 |
| --- | --- |
| `priv/openthread/host.cpp` | `aab028ca093b3073d9fae4cbd7699a87b511612a8388c91de73a8ca7751b498a` |
| `priv/openthread/output.hpp` | `857860b717dbe684a203afc9de6c1c0a03e61243823659caf292ce39c9f66cbe` |
| `priv/openthread/protocol.hpp` | `75cd199a8f8d125ecb700b2ca650e2a92bfd8cc573fe5e7e9237dfe424a76424` |
| `test/native/output_test.cpp` | `cf878689fbfc5ad007ad5b8795640f3dd39f41e783a4d699f1f9e25de0d5e40e` |
| `test/native/protocol_test.cpp` | `260ac52a2d39d8dcb76c04c8a9bb9f5b7f22b20119e5eec2709910a1561b1248` |
| `lib/wotex/thread/open_thread/connection.ex` | `7fc067e3d9de5301ced1037967d88c57ec4ee2bcce89461ba94b840c42a9be60` |
| `test/fixtures/sdk_bridge.escript` | `3c33aef2a2ef143487e703dceb57bc0e63146ff712fb1a0fd946d20abfc5fb50` |
| `test/wotex/thread/native_contract_test.exs` | `42d33388608b1a9987d1f09f7635d8e26abed1164dd7ab3a2f7dc2c83405f950` |

The production host still has no report source: no stream report or
`stream_retired` barrier crosses its Port. F11–F13, the Mix software tasks, the
x86_64 lane and C09 stress remain unexecuted.

## Mix software build and run, 2026-09-17

`mix wotex.software.build --workspace ABS` (`Wotex.Thread.Software.Build`)
requires Linux, the repository `test/native` sources and exactly one absolute
workspace. It compiles its command guardian, runs `Wotex.Thread.Native.Build` for
a normal host in `native/` and a sanitizer host in `native-sanitized/`, builds
the pinned simulation `ot-rcp` from the manifest-bound patched SDK tree, and
builds the sanitizer protocol, storage, output, flow and Spinel tests, contract
driver and Dataset seed. Every step runs through the guardian with separate
arguments, a cleared environment and finite deadlines. `software-manifest.json`
(schema `wotex.software-build`) binds both native manifests, all fixture
executables, build logs, source files, build module digests, tool digests and
configure arguments. `Wotex.Thread.Native.Workspace` now selects native or
software manifests explicitly; a workspace of one family is never reused as the
other. Sanitizer builds add `-fno-sanitize-recover=all`, so an UndefinedBehavior
report terminates the instrumented process instead of continuing unseen.

`mix wotex.software.run --workspace ABS` (`Wotex.Thread.Software.Run`) never
builds. It requires the completed software manifest, verifies it and both native
manifests, and creates a terminal `software-run/` directory. It executes the five
sanitizer native test executables, then two guarded ExUnit lanes with
`WOTEX_REQUIRE_SOFTWARE=1`: the full suite with the normal host
(`mix test --include interop --include software --exclude hardware --seed 0`),
and `test/software` plus the native contract tests with the sanitizer host. The
test helper fails when any fixture variable is missing under that setting and
installs a formatter that records every executed case. `test/software/acceptance.json`
names the 12 required cases per lane; a lane passes only when its command exits
zero, each required case passed exactly once and no recorded case failed, skipped
or was invalid. The runner then kills and counts surviving processes whose
executable lies inside the workspace, compares source identity before and after,
and writes `result.json` (schema `wotex.thread.software-run`).

| Lane | Result |
| --- | --- |
| Linux arm64, image `sha256:95ca03c1f4714893eb0f33791ecb05eb8a234816fe96aa9a7168c1c3c9012b68`, Elixir 1.18.4 / OTP 27.3.4.15 | Build 89 s; run passed in 92973 ms: 5/5 native tests, normal lane 142/142 cases, sanitizer lane 12/12, 0 survivors, source unchanged. Software manifest `81dacbd4ead22e9a3839ebde8e58ec0ba1a3e85d6b0473e570e94942341d8a3c`, result `06a68b3b7b7229e51a5735bb511c70458ee22bf387d62168d1ef19e6214fd90d`, normal host `07e230d6a853a8f159d4a30ffa799b64f36b4123ed7097aca7624f1472049ed4`, sanitizer host `520bcf9a6c34e05940fb062af7d2a9c2415e0fa5bc10b7ac483de55b9b11c2aa`, RCP `e864dadc7b14fc73879cca1b983b69a79d37d7534b78ff98e43c84c05d64822f` |
| Linux arm64, image `sha256:cd12556442e9d686112fc225e1b2ce62db1eb9f7e1fff22b9d9bf24591728535`, Elixir 1.20.2 / OTP 29.0.4 | Build 98 s; run passed in 94307 ms: 5/5 native tests, 142/142 and 12/12 cases, 0 survivors, source unchanged. Software manifest `7322b13eed52817c07fdf94e411941a27d021c52e9846b2b42fa303971fc47ab`, result `2793b736208f102d6c3a5c856bab47afe3f2ac0a460e833e6ffa6046175aee5e`, normal host `30599f9678d992568ec70a25e79d6ed15551f778695db3dedcec0f7f6845967d`, sanitizer host `2f4c88b3ac07a89b627b31f4f45e23fe3b85fa08b43888104accdca221ea4645` |

Both lanes ran in privileged containers for the SDK's TUN interface, with
`WOTEX_PATH_DEPS=1` and a fresh copy of the source tree. A second
`mix wotex.software.build` on the first workspace verified it without rebuilding.
Negative controls on Linux arm64: a copy of the completed workspace with one
appended byte in `ot-rcp` failed with `build_manifest_mismatch` before creating a
run directory; an empty workspace failed with `software_workspace_not_built`; a
second run of a completed workspace failed with `software_run_exists`.
`software_build_test.exs`, `software_run_test.exs` and the workspace tests run in
the default gate; the lane evaluation cases cover missing, failed, skipped,
invalid, duplicated, zero-case and malformed results.

| Source | SHA-256 |
| --- | --- |
| `lib/wotex/thread/software/build.ex` | `323879eb289a1d3196d50efb1720a68fd7d94c249ca49289b01c3b84af7f2811` |
| `lib/wotex/thread/software/run.ex` | `f8ab98c909223e6c3a83e442d5906a4b3f199e04a1f89c29377e79f8e8beeb55` |
| `lib/wotex/thread/native/workspace.ex` | `82934a3f17323ec834a33fa66cf2afba2f97fd37dfeafe61cbc4ae5f87079823` |
| `test/software/acceptance.json` | `7c3af5bfb6c2c3ea8a39f1c7d2c92720e52572593ac1f9ae9bf87ea289f67c66` |
| `test/support/software_cases.ex` | `c8b1f46994d68a50935dc04b1c51d918e689cbe3b71c6d7c47d0af1b8032d746` |
| `test/test_helper.exs` | `0f16e2ce1f2ad072d01bb7504517eca0c64528953bc8af1c8faef1991d6f2b2b` |
| `priv/openthread/CMakeLists.txt` | `38ea90b899c395aa56fc229d0d6bb7779fa03d76c31ad24b8f8caf29c44e2ae6` |

The x86_64 reference lane, process-flow cases, report sources, the P07 network
fixture and C09 stress are not part of this run.

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
