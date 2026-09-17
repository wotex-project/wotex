# Executable evidence

Current implementation: bounded Dataset/daemon APIs and a first-party C++ SDK
host with semantic Dataset validation/export, interface/Thread enablement,
formation, management callbacks and commissioner lifecycle/admissions. Native
ExUnit and C++/process fixtures exercise real SDK/RCP software boundaries; their
presence is scoped evidence, not a complete Thread profile. Joiner execution,
complete simulated-network/application workflows and final
stress/native/package closure remain required.
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

## Native host process ownership and four software lanes, 2026-09-17

`test/software/native_host_process_test.exs` restores, in ExUnit, the host
process cases formerly held by the retired Python owner driver. Each case opens
the real host through a Port, checks the exact ready frame, sends `flow_open`
and drives C07 frames directly against the SDK and simulation RCP:

- open, inspect, version and close with a private mode-0600 store preserved
  byte for byte across close and `open_existing`, and the interface removed;
- competing store and interface owners fail with `storage_unavailable` and
  `interface_in_use` without disturbing the first owner;
- eight invalid configurations fail with `invalid_request` and create no store;
  unopened `inspect` fails `not_open` and an unknown operation `not_supported`;
- symlinked, hard-linked, mode-0644 or directory `settings.data` and
  `settings.Swap` entries fail with `storage_unavailable` and leave the outside
  file unchanged;
- every byte split of a request, two coalesced requests, and a radio child that
  writes 300000 bytes to its own standard error produce exact replies and no
  stray frame;
- truncated input at EOF, duplicate keys, a 131073-byte line and a request before
  `flow_open` terminate the host with nonzero status;
- killing the worker or the radio releases descendants, the interface and the
  store lock, proven by reopening the store;
- a radio that ignores SIGHUP and SIGTERM and never completes startup is reaped
  after owner EOF or SIGTERM, including with 4000 queued input frames; and
- 100 open/close cycles restore process and interface baselines.

`test/fixtures/stubborn_radio.c` is the injected radio for the blocked-startup
cases; it is not radio or SDK evidence. The 100-cycle case carries a 300-second
ExUnit bound because a sanitizer-host cycle under a concurrent lane exceeded the
default 60 seconds. The ten cases are required in both software lanes, raising
each lane inventory to 22 cases.

On emulated x86_64, Erlang/OTP 29.0.4 needs `+JMsingle true`. The owner clears
the child environment, so the injected escript peer previously started without
it, failed emulator startup and turned 30 bridge cases into `cleanup_timeout`.
`sdk_bridge_test.exs` now writes the lane's `ERL_FLAGS` into the escript header,
and `mix wotex.software.run` passes and records `ERL_FLAGS`. The production host
has no BEAM and is unaffected.

All four lanes ran `mix wotex.software.build` and `mix wotex.software.run` on
fresh workspaces from the same source tree, in privileged containers with
`WOTEX_PATH_DEPS=1`. The x86_64 lanes run under Docker Desktop emulation on an
arm64 host.

| Lane | Image | Run | Native tests | Normal lane | Sanitizer lane | Result SHA-256 |
| --- | --- | --- | --- | --- | --- | --- |
| Linux arm64, Elixir 1.18.4 / OTP 27.3.4.15 | `sha256:95ca03c1f4714893eb0f33791ecb05eb8a234816fe96aa9a7168c1c3c9012b68` | 252630 ms | 5/5 | 154/154 | 22/22 | `e8edfc6b21f07897f8602cb360f8b5cb074e66243a2d5ef0815ee8f4dbbd8892` |
| Linux arm64, Elixir 1.20.2 / OTP 29.0.4 | `sha256:cd12556442e9d686112fc225e1b2ce62db1eb9f7e1fff22b9d9bf24591728535` | 256204 ms | 5/5 | 154/154 | 22/22 | `53a796bb52c4a7eb7556e98796d4576f8ee4007698505ba4548d429d24c76d26` |
| Linux x86_64, Elixir 1.18.4 / OTP 27.3.4.15, `+JMsingle true` | `sha256:052f076067fbb6b76e976e62d4ce5f35a33220f0a650e2aed5cba5d17e0f7743` from the pinned image's amd64 manifest | 132022 ms | 5/5 | 154/154 | 22/22 | `a6cf91d4329037dd7d29645b72ad76f2b5de6aa81762120621a1622d1e099fc9` |
| Linux x86_64, Elixir 1.20.2 / OTP 29.0.4, `+JMsingle true` | `sha256:38288d79170bd92f6f34dec49f484323f5aeaffe283a6a08f0476c3096b269d2` from the pinned image's amd64 manifest | 140247 ms | 5/5 | 154/154 | 22/22 | `50516596d6f8fdafcc431e26178d30318bad741bce63a27bc69e82c601fde2f3` |

Every result reports zero surviving workspace processes and unchanged source
identity. All lanes use Debian 12.15 with GCC/G++ 12.2.0-14+deb12u1, CMake
3.25.1 and Ninja 1.11.1. Host, RCP and manifest digests differ per lane and
workspace; each is bound in its result. The x86_64 results execute the required
reference architecture and toolchain under emulation, not on native x86_64
hardware.

| Source | SHA-256 |
| --- | --- |
| `test/software/native_host_process_test.exs` | `5e21310bffd462f549ca7cfdfde0e9bb1473220064e56234ea3253c6534eedd1` |
| `test/fixtures/stubborn_radio.c` | `a19ea6733534363d3bffc2c66c5b208a59027503ff4fca839aec4a990c18cd49` |
| `lib/wotex/thread/software/run.ex` | `0d30e3f39ea39fab26bdd6f69f1443d41cc3e5b8ce07a99bb85fe8f07267d799` |
| `test/software/acceptance.json` | `c58b28b7e02724b609c585ffa6bc8c29b469eebdb02a00e16a0d23b4708cba4d` |
| `test/wotex/thread/sdk_bridge_test.exs` | `4ccafa935dda284fe879d6457525c827b8484613c82caaec1657c354fd9a9895` |

WTH-B-F11–F13 process-flow cases, the P07 network fixture and C09 stress remain
unexecuted.

## Native State subscriptions, 2026-09-17

`Wotex.Thread.subscribe/2` accepts `%{type: :state}` with optional `receiver`,
`max_queue_length` (1..10000, default 1000) and `timeout` for an OpenThread
Session; other clients keep the `:not_supported` sentinel. The host's
`subscribe_state` registers a listener in `priv/openthread/streams.hpp`, replies
with its `subscription_id` and stream `generation`, and then submits the initial
snapshot through the report-flow owner. SDK state callbacks only accumulate the
changed-flags mask. Each event-loop iteration takes one snapshot and reports it
with the OR of that iteration's flags to every live stream; flags observed with
no listener are discarded. A stream whose report cannot be queued receives one
`stream_error` with `queue_overflow` followed by its barrier. `unsubscribe`
writes the barrier before its null reply, and an unknown stream returns
`subscription_not_found`. The WTH.13 State stream frames subsection defines each
exact frame.

`Wotex.Thread.OpenThread.Connection` validates every stream frame, registers
reports in the credit ledger and sends each report to a per-stream
`Wotex.Thread.OpenThread.StreamOwner`. The owner checks the final receiver's
queue; the connection rechecks it, delivers
`{:wotex_thread, reference, {:ok, %State{}, %{changed_flags: flags}}}` and only
then acknowledges native credit. A full receiver queue delivers one
`receiver_overflow` error and cancels the native stream. A native stream error
first delivers the stream's already validated reports in sequence order, then
one terminal error. Receiver death cancels without delivery; stream-owner death
delivers `owner_down`; session close gives each live stream one terminal error
and stops its owner. An internal cancellation that cannot be written within its
1000 ms deadline closes the generation. Cancellation of a closed handle succeeds;
this generation remembers at most 1024 closed handles, and a handle whose owner
ended returns `:ok` without I/O. Unknown streams, reports beyond stream or
session credit, and barriers for live streams close the generation.

`test/native/streams_test.cpp` asserts the initial report, per-iteration
coalescing with unknown bit 31, discarded listener-less flags, barrier
sequence, overflow error ordering while another stream continues, blocked
control failure and 64-stream capacity. The contract driver's
`state_coalescing` operation executes corpus case WTH-F09 through the same
stream owner; `native_contract_test.exs` compares the exact observation.
`state_subscription_test.exs` runs in the default gate against the injected
escript peer: initial and credited reports with exact cumulative
acknowledgements, idempotent cancellation, admission and forged-handle
validation, receiver overflow, ordered native overflow, receiver death, session
close, and three generation-closing faults (17 reports in one write beyond
16-report stream credit, an unsolicited barrier and a report for an unknown
generation). `test/software/native_state_test.exs` uses the real SDK and
simulation RCP: two streams receive distinct generations and initial disabled
snapshots, formation delivers role-flagged reports ending in leader, the
cancelled stream stays silent while the other receives the disable transition,
and receiver death plus session close release stream owners.

| Lane | Run | Native tests | Normal lane | Sanitizer lane | Result SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Linux arm64, Elixir 1.18.4 / OTP 27.3.4.15 | 251675 ms | 6/6 | 166/166 | 25/25 | `b18ccdf29eabf542b1d3834dd549cc435b722b823a432e8fb4d98c041294cc65` |
| Linux arm64, Elixir 1.20.2 / OTP 29.0.4 | 251314 ms | 6/6 | 166/166 | 25/25 | `3eb69fed0206c1dbeff73da2d836a2a3b0ccf71169f6a3be51cc0461181d56f8` |
| Linux x86_64 (emulated), Elixir 1.18.4 / OTP 27.3.4.15, `+JMsingle true` | 142420 ms | 6/6 | 166/166 | 25/25 | `402442c42915af5f4f904597c892889c9f51072c33d95cae3605653671dcf03a` |
| Linux x86_64 (emulated), Elixir 1.20.2 / OTP 29.0.4, `+JMsingle true` | 151700 ms | 6/6 | 166/166 | 25/25 | `cfe491821c477c44f898b8a95358a33ec19c294d38ca7b7e5b1078a7ea4b5ac5` |

The lanes used the same images and commands as the preceding four-lane record,
each on a fresh workspace built from one snapshot of this source, with zero
survivors and unchanged source identity. The macOS gate passed 142 checks with
26 software/hardware exclusions.

| Source | SHA-256 |
| --- | --- |
| `priv/openthread/streams.hpp` | `e163a7c02414ec03af164c78947e6ebfdc11bbebc1123891be431bb228e46312` |
| `priv/openthread/host.cpp` | `f6aae02d90591c20b6a763a5796c4c4f7e80deebd903be55b74be9a3fa212123` |
| `test/native/streams_test.cpp` | `b71a60c713c17e4184e253971cc0f6297ee870747c4699a8eb8104e8624c4212` |
| `test/native/contract_driver.cpp` | `51eb96ee45ccf96a13859104668ad557b06a71f454a30d707d5161db13d8c736` |
| `lib/wotex/thread/open_thread/connection.ex` | `c38321b53e221247cc9dc42d7323955d0b092576db8a541c3cc90a54ca42a54b` |
| `lib/wotex/thread/open_thread/stream_owner.ex` | `9a26cd611a37dc1005aad0c54439f3efc9cbdd3d53a478d2a0aa2734fa1376f6` |
| `lib/wotex/thread/open_thread/frame.ex` | `9ba74ca47b41adcf7f2e75e1db53aea877735ea8094a0a718c99bbd7ecea6116` |
| `lib/wotex/thread.ex` | `6fca13b466018e0d646dfba274ca43d33fe725361fcaed739c50a677a085c374` |
| `test/wotex/thread/state_subscription_test.exs` | `41fb09637337bbe66cf33eba30235f1a98d60af1dcffba1f80438e4457f5ad22` |
| `test/software/native_state_test.exs` | `3fb160fa1f3eda6e7085a8772226365a368f170951a81911d6bc70729afd7948` |
| `test/fixtures/sdk_bridge.escript` | `68262c3a982d70b4cb615d4f4eb117ff28d3d6a34db03061d0099168c96febeb` |

WTH-B-F11–F13 process-flow cases (native callback bursts while the connection,
stream owner or receiver is suspended), the P07 network fixture and C09 stress
remain unexecuted.

A report queued without credit keeps its encoder until credit returns. The first
State stream encoder captured the snapshot, flags and identity by reference, so a
drained report read storage released after its iteration. The encoder now owns
copies. `streams_test.cpp` queues a report, acknowledges credit and requires the
drained report to keep its own role, flags and newly assigned sequence; with the
reference capture restored the Apple clang sanitizer build aborted on a corrupted
value (exit 134), and with the copy it passes. The fixed native tests passed 6/6
under ASan/UBSan/LeakSanitizer in all four Linux lanes of the following run
(results `687d6c76a7cc3986f956b4b8eda3062595f6710297afb9fd6fbaf6e34df6519f`,
`e6382087cf75e52d6899874935efa20cd1ab85c56fffe736b3b0839da2fd26d5`,
`5300ba2e3ed4a5cf86758e0fc9a5df38a9da1fd92569768223c79d11d1395cd3` and
`ce08179b1d8d2beb57b331cf54f0648fec8ca3c7a66c1ce9f0a6736b49f68608`); the
arm64 Elixir 1.20.2 run failed three ExUnit cases, recorded with their correction
below. Fixed `priv/openthread/streams.hpp` SHA-256 is
`3c8d4d1287b0ebb8d625dc619979466264bd4a151c03f0f6919b95dcf64ed0cf` and
`test/native/streams_test.cpp` is
`a13f63b238e269dda39ce71bc542fa50410cda241bde6d6335ba3e8f9d5847b0`.

## Graceful native close within the cleanup grace, 2026-09-17

The connection wrote `close` and sent SIGTERM 40 ms later. A host or injected
peer that had not replied by then was terminated, so a slow but correct close
became forced termination, and under a concurrent lane the escript peer could be
cut off mid-reply. That run's Elixir 1.20.2 arm64 lane returned
`invalid_response` from one bridge disconnect and `cleanup_timeout` from the
first sanitizer-host State connect. WTH.13 B02 gives the owner C03's 1000 ms
grace before termination, so SIGTERM now follows `close` after 700 ms; SIGKILL
remains at 900 ms and the cleanup deadline at 1000 ms.

The longer grace exposed the sanitizer host's own close time on arm64: 498–522 ms
to the close reply, which includes the explicit leak check after SDK teardown,
and 981–1001 ms to exit because LeakSanitizer ran again at exit in the worker and
guardian. Sanitizer hosts now default `leak_check_at_exit=0` through
`__asan_default_options`; the explicit post-teardown check remains, and explicit
environment options still override the default. Three measured closes of the
rebuilt sanitizer host took 484–529 ms to reply and 490–536 ms to exit. The
State software test now uses a 10000 ms connect bound and simulation node 24,
distinct from the node IDs used by the other software modules.

| Lane | Run | Native tests | Normal lane | Sanitizer lane | Result SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Linux arm64, Elixir 1.18.4 / OTP 27.3.4.15 | 187226 ms | 6/6 | 166/166 | 25/25 | `bb2fa52ee96badd40cb21c901ff4ac76f57bc1f3fefd9de873de27101e60452d` |
| Linux arm64, Elixir 1.20.2 / OTP 29.0.4 | 178633 ms | 6/6 | 166/166 | 25/25 | `86408ab696f61d839c89f54e7d20a5808f9c2c712838571a5b954e1bf78a236b` |
| Linux x86_64 (emulated), Elixir 1.18.4 / OTP 27.3.4.15, `+JMsingle true` | 146450 ms | 6/6 | 166/166 | 25/25 | `4ccc494ff42cf4e5ef1317673484e753bb941b254be55780efb1bb04465d3000` |
| Linux x86_64 (emulated), Elixir 1.20.2 / OTP 29.0.4, `+JMsingle true` | 150595 ms | 6/6 | 166/166 | 25/25 | `8837608f90728d604385fc8528acf3c658c9cacef73eaf2f04dcff864528fd82` |

All four results report zero survivors and unchanged source identity.

| Source | SHA-256 |
| --- | --- |
| `lib/wotex/thread/open_thread/connection.ex` | `205bc3396e28239c69baf6a6037fc07e9c0d72efa51d01b2cbc7fa86a196f42c` |
| `priv/openthread/host.cpp` | `c2c9e82926cc22a383ef85668ffb4f0ce9657efd426bb8c67f4f12916416a802` |
| `test/software/native_state_test.exs` | `4fab31812c31bf715ebf1848f2fae14fb246c74012f0af899099aa435ba02247` |

## Process-flow cases WTH-B-F11–F13, 2026-09-17

`test/software/process_flow_test.exs` executes the three `process_flow` cases of
`native-port-v1.json`. Each case copies `wotex-thread-flow-host` into a private
directory beside its `flow-host.flow.json` configuration. That executable is the
production host compiled with `WOTEX_THREAD_FLOW_TESTING`; its only addition is a
State callback source that, after a harness gate file appears, records one SDK
changed-flag callback per event-loop iteration through the production stream,
credit and output code and pads each report value with JSON whitespace to the
case's `value_bytes`. The production host contains no such input. The software
build compiles this host without sanitizers so its callback rate reflects the
production event loop; the loop polls the gate within 1 ms and runs without
waiting while callbacks remain. The source writes one result with its callback
and iteration counts, report sequences assigned, stream errors, retirements and
the maxima of queued and outstanding report credit and of every output lane.

A receiver process opens a real SDK session with the simulation RCP, subscribes
with the case `queue_limit` and waits for the initial report and returned credit.
The harness suspends the actual connection, stream owner or receiver, writes the
gate, resumes the process at 50 ms and samples the connection, owner and receiver
mailboxes every millisecond through 1050 ms. It classifies Port lines as reports,
controls or replies, requires every observed report value to be exactly 128
bytes, and counts owner and receiver deliveries. After a terminal delivery and
native completion the receiver disconnects. The harness then requires the
receiver to have exited normally and the connection, stream owner, Port and every
native process to be gone before counting survivors.

`frame_bound` compares native maxima with 64 queued and outstanding reports, 64
report, 256 control and 64 reply output frames, and the sampled mailboxes with 64
Port reports, 64 owner reports, `queue_limit` receiver reports, 256 controls and
64 replies. `byte_bound` applies 1048576 bytes to native report and control
bytes and to sampled report, control, owner and receiver bytes, and 8388608 bytes
to replies. The harness also requires 10000 callbacks and iterations, one
retirement, no live stream, at least one delivery, a `queue_overflow` terminal
for the suspended connection and owner, and `queue_overflow` or
`receiver_overflow` for the suspended receiver. The exact normalized observation
then equals the corpus expectation. Each run writes `process-flow-WTH-B-F1x.json`
beside its case results.

In the recorded run the uninstrumented source completed all 10000 callbacks in
4.1–6.6 ms. Every case reached 64 queued native reports with 16 outstanding and
ended with one `queue_overflow` terminal; no delivery followed a terminal. With
the connection suspended its mailbox held 16 report lines. With the owner
suspended its credit stayed unreturned until the stream error delivered the 16
validated reports ahead of the terminal and retirement stopped the owner. The
suspended receiver held 16–31 deliveries, below its 64-message limit, before
resuming; the native queue overflowed first on every lane. A sanitizer-instrumented source ran too slowly on emulated x86_64 to
overflow within the 50 ms suspension, and a 50 ms idle loop before the gate
delayed the burst until after resumption; both were corrected before the
recorded run.

| Lane | Run | Native tests | Normal lane | Sanitizer lane | Result SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Linux arm64, Elixir 1.18.4 / OTP 27.3.4.15 | 192424 ms | 6/6 | 169/169 | 28/28 | `0b495d82bc13af400b7d02d705d3bc8152049b1fc4eb8b28ef9c501770fbe0ca` |
| Linux arm64, Elixir 1.20.2 / OTP 29.0.4 | 189576 ms | 6/6 | 169/169 | 28/28 | `d9dd146cd51f71857c62eff4948832ada02f5a2593c758362fd01ff41bee1fa9` |
| Linux x86_64 (emulated), Elixir 1.18.4 / OTP 27.3.4.15, `+JMsingle true` | 149887 ms | 6/6 | 169/169 | 28/28 | `181ffe1b165bbe7c6a0d722e77544ce056b9f97e2a66084f726609bfd5f9b763` |
| Linux x86_64 (emulated), Elixir 1.20.2 / OTP 29.0.4, `+JMsingle true` | 156001 ms | 6/6 | 169/169 | 28/28 | `272720a8068464e6f546f301b71bd114c52fc5849358099ff2cc67b44e6c1c1c` |

Both lanes of each run execute the three cases, now required in the inventory,
and all four results report zero survivors and unchanged source identity.

| Source | SHA-256 |
| --- | --- |
| `test/software/process_flow_test.exs` | `7b976f6211750f6eaf770910f8eba336d4aca472fecd8fe7b14468c444e5d4b0` |
| `priv/openthread/host.cpp` | `46c3c0efb8053a361f803157d0ea2cabc4a46c016eeb9c532951f4189ef6f1e4` |
| `priv/openthread/streams.hpp` | `a3eda38ff94d0db22166b28221c03426f686488b07095a6409f152bfddd3e124` |
| `priv/openthread/flow.hpp` | `e8c7a8b3a9893acc98bc8c3a474f8335cc1a9ebe8ebf922068966ad4c4a78506` |
| `priv/openthread/CMakeLists.txt` | `c564d14572d2274380e36244928539428cbcba0a4d16b81e7587b298ca680bf0` |
| `lib/wotex/thread/software/build.ex` | `bb1490374d868e61e05bd4023675036bf90f8a9f437443e79030746a45987e11` |
| `lib/wotex/thread/software/run.ex` | `315915b5639dda5183fecde6fafba0f14953fad9e96fc4538c74fe221324f766` |
| `test/test_helper.exs` | `f761431ef9908ed0e0415db352d6cb1fb6d16b50358e043c60755f6d196cde97` |
| `test/software/acceptance.json` | `647e4ceed31b685f09ec496c5b2b9e8cdc158b324a9bff936ca66b05884726fd` |
| `docs/specs/fixtures/native-port-v1.json` | `91d70393eb17360ea253f249ff3710d568c3fd12941b9eae91f7c8aa6dc3ba18` |

C09 stress, dependency audit and clean archive validation remain open for P00.

## Lifecycle stress, 2026-09-17

`test/software/lifecycle_stress_test.exs` executes the C09 software stress cases
in both lanes of every software run, against the real host and simulation RCP
unless stated otherwise. Every lifecycle cycle captures the Port's guardian, its
SDK worker and the radio it started from `/proc`, requires at least those three
processes while open, and requires each to be gone after the cleanup grace
together with the connection process.

- 1000 sequential `inspect_state`, `state`, `network_name` and `rloc16`
  operations return exact typed values. Afterwards the connection has no
  pending request, waiter, queued or active request, control, subscription,
  stream, report, monitor or mailbox message, and its report ledger has no
  pending report, live stream or retained byte with every assigned sequence
  acknowledged. Native RSS (guardian, worker and radio), connection memory and
  BEAM total memory are sampled every 100 operations and written per lane
  beside the case results; they are reported, not asserted.
- 100 BEAM open/close cycles verify that the guardian and radio executable
  links equal the configured host and RCP paths, the interface exists while
  open, and the owned processes, Port count and interface return to baseline
  each cycle. The BEAM process count returns to its baseline at the end.
- 100 receiver-death cycles subscribe with a separate receiver, wait for its
  initial report, kill it, require the stream owner to exit and restore the
  full connection and ledger baseline above before the next cycle. The native
  host admits 64 live streams, so cycles 65–100 also require native retirement
  of every earlier stream.
- 32 concurrent callers each issue 25 alternating `state`/`version` requests;
  all 800 replies correlate to their exact type and the baseline is restored.
- 10 forced 200 ms startup deadlines use a radio that never completes Spinel
  startup; each returns `timeout` within 1300 ms and no host or radio process
  or interface remains.
- 10 peer-loss cycles kill the SDK worker; the connection terminates, later use
  fails with `connection_closed` or `invalid_handle`, and the guardian, worker,
  radio and interface are released.
- 30 malformed-reply cycles (bad JSON, truncated and oversized lines) use the
  injected escript peer. They are injected-contract evidence, not SDK
  interoperability; each closes its generation with `invalid_response`,
  `response_limit` or `connection_closed` and the peer process exits.

A first run (lane 17) of an earlier draft failed its receiver-death case on
three of four lanes because it checked the connection state once, before the
last cancellation reply had arrived; lane 18 passed after that check waited for
the reply. That draft sampled RSS into one file that the sanitizer lane
overwrote and checked native processes only in the deadline case. The recorded
run below executes the strengthened test on the committed refactor source.

| Lane | Run | Native tests | Normal lane | Sanitizer lane | Result SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Linux arm64, Elixir 1.18.4 / OTP 27.3.4.15 | 291357 ms | 6/6 | 176/176 | 35/35 | `03a0a42613e4a32730101dd0ce158b56f58ddf929c5e288cbcbf975916aac241` |
| Linux arm64, Elixir 1.20.2 / OTP 29.0.4 | 291321 ms | 6/6 | 176/176 | 35/35 | `49e94907e97e67b7746474e9b56baf5ce2a6a60dc7ebfb24a197bcc7a7183c5f` |
| Linux x86_64 (emulated), Elixir 1.18.4 / OTP 27.3.4.15, `+JMsingle true` | 235305 ms | 6/6 | 176/176 | 35/35 | `e339061eda92c43ae30f3b3df949b2c2a5be2728e62e18f82e4cfc2908829288` |
| Linux x86_64 (emulated), Elixir 1.20.2 / OTP 29.0.4, `+JMsingle true` | 260694 ms | 6/6 | 176/176 | 35/35 | `1c5994ebe3b85afc652723d49eacf390c7027c8db2540e37ad8b475d5805272a` |

All four results report 176/176 normal-lane and 35/35 sanitizer-lane cases,
each lane including the seven stress cases, with zero survivors and unchanged
source identity.
Over the 1000 operations the uninstrumented host's native RSS stayed constant
on every lane (7648 KiB and 7624 KiB on arm64, 14832 KiB and 14836 KiB on
emulated x86_64), and connection process memory stayed between 39328 and 112656
bytes. The AddressSanitizer host grew by 10536–13352 KiB, from 62556–63696 KiB
to 73096–75936 KiB, roughly 1 MiB per 100 operations. That growth is consistent
with AddressSanitizer's freed-memory quarantine rather than evidence of a leak,
but these runs do not separate the two; the flat uninstrumented trend is the
production observation.

| Source | SHA-256 |
| --- | --- |
| `test/software/lifecycle_stress_test.exs` | `09ed34e43af78a4a14cd32adcca9b17a032f1c81f2c8beb6f8afd4d564f6a73e` |
| `test/software/acceptance.json` | `203aec22df7e3cf63aff8ff9511a2674f82d104bc408312748b09e3c960df433` |
| `lib/wotex/thread/open_thread/connection.ex` | `12959cdec08e9b9a5671244703a85feb1b5b441cdfdac74ce48213724f000d2e` |
| `lib/wotex/thread/software/build.ex` | `fa5ae3045dc6791f4309d4b30dbc64d78015f3025a578879c6699e3763f00324` |
| `lib/wotex/thread/software/run.ex` | `337494a31a036a4e0b4b03d8f966c8f0a266018c7b4dbcad813bcfb6e99ca78c` |
| `test/fixtures/stubborn_radio.c` | `a19ea6733534363d3bffc2c66c5b208a59027503ff4fca839aec4a990c18cd49` |
| `test/fixtures/sdk_bridge.escript` | `68262c3a982d70b4cb615d4f4eb117ff28d3d6a34db03061d0099168c96febeb` |

Dependency audit and clean archive validation remain open for P00.

## Native source advisory review, 2026-09-17

`bin/check_native_advisories.exs` is a live release check for the exact native
sources in `priv/openthread/dependencies.json`: OpenThread
`5c8c318627954c99cd1a957a290bbd4b1027d04b`, Mbed TLS
`068ff080b369adfac81509f9b57b2afabaf82dc5` (tag `v3.6.7`), its framework
`dde0c4a0e448a0552f18817dcea633bb851fd288` and nlohmann/json
`9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03` (tag `v3.11.3`, the pinned header's
release). It submits one OSV commit batch, then NVD CPE queries for Mbed TLS
3.6.7 (`arm` and `trustedfirmware` vendors), nlohmann/json 3.11.3 and every
OpenThread version, and an NVD `OpenThread` keyword query because the pinned
commit has no CPE version. Every reported advisory needs a checked-in
[review](../../../../packages/wotex-thread/priv/provenance/native-advisories.json). A `fixed_in_pin` review is accepted only when
the GitHub compare API reports each named fix commit as an ancestor of the pin.
`test/wotex/thread/native_advisories_test.exs` keeps the review file bound to
the build pins in the default gate; it does not query any service.

OSV commit queries alone are insufficient here: a control query for Mbed TLS
3.6.0 (`2ca6c285a0dd3f33982dd57299012dacab1ff206`) returned no OSV result,
while NVD CPE queries for 3.6.0 returned 11 (`arm`) and 15
(`trustedfirmware`) CVEs. A second control that dropped the CVE-2025-66442
review and named the current OpenThread `main` head
`b8f0b95a8d7507542b95db343c2ef6ba4734f67e` as the CVE-2026-8369 fix exited 1,
reporting both.

The recorded run at 2026-09-17T12:11:58Z (`WOTEX_PATH_DEPS=1 mix run --no-start
bin/check_native_advisories.exs`, log SHA-256
`53e9e9c154721f1b6a5ca241f493ce42ce30b2cd728577b82bbf40d7b7b6855c`) exited 1.
OSV returned no advisory for the four commits, and neither nlohmann/json CPE nor
the OpenThread CPE matched a CVE. NVD reported 13 advisories. Three are fixed in
the pin by verified ancestry: CVE-2019-20791 (`b8c3161`, `c3a3a0c`),
CVE-2023-2626 (`3d5cb36`) and CVE-2026-8369 (`26a882d`, 555 commits before the
pin). Six are not applicable: wpantund (CVE-2020-8916, CVE-2021-33889), Silicon
Labs SDK, gateway or RCP components (CVE-2023-41095, CVE-2024-3017,
CVE-2025-2329) and the Mbed TLS Clang select-optimize timing channel
CVE-2025-66442, which the GCC 12.2.0 build with `MBEDTLS_HAVE_ASM` and without
RSA, CBC or cipher padding in its generated configuration does not meet. Three
keyword matches are unrelated products.

CVE-2025-36939 remains unreviewed. NVD and the GitHub advisory
GHSA-x6v7-jjvq-5rr9 describe MLE assertion failures and a stack-based buffer
overflow reachable by an authenticated attacker on the same Thread network,
referenced by the August 2026 Nest security bulletin. Neither source names an
affected range, fixed version or fix commit, so the review cannot establish
that pinned commit `5c8c318` (committed 2026-08-31) contains the fix. The check
therefore fails, and the native dependency audit does not pass until the
maintainer identifies the upstream fix or changes the pin.

| Source | SHA-256 |
| --- | --- |
| `bin/check_native_advisories.exs` | `11e955afd934ced8c385e0c6a4ded2cdec69fcb300509636290d0e17fed1fdb9` |
| `docs/provenance/native-advisories.json` | `49e8f3ff8d8397a578b170b2893a0616c669344daaff386b78c47e65251776a0` |
| `test/wotex/thread/native_advisories_test.exs` | `b98b73ff98d17553482469a03723ca5ce52b1f6293e017d4fccc4f0c7aff886b` |
| `priv/openthread/dependencies.json` | `a05a44006bafbf57e165f3f7cab4ef88b398cb512e136f7b08375a128842bf17` |

## Contract corpus binding, 2026-09-17

`test/wotex/thread/contract_fixture_test.exs` runs in the default gate. It
requires the exact `contract-v1.json` top-level fields, format 1.0.0, IDs
WTH-F01–F10, the fixed operation-to-kind table, exact-operator expectations and
WTH S/N requirement identifiers. Every case is bound to the test that compares
its actual observation, or recorded as unexecuted with its owning package:
WTH-F07 and F08 (P04 lifecycle callbacks). WTH-F09 later executed through the
native State stream owner.
The pure Dataset cases and the fragmented daemon case already execute in
`dataset_boundary_test.exs` and `daemon_fault_test.exs`. The binding cannot
count an unexecuted case as evidence.

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
