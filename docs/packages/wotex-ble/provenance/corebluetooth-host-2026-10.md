# CoreBluetooth native process and build evidence

Recorded: 2026-10-20. Package: `packages/wotex-ble`.
Source parent: `cd8083f80b042aabf4a49b6d5fb4ce4d7ebff1e4`. The dirty-input
identities below bind the native process, builder and SDK fresh-owner retirement
before their owning commit. Owner: [WBL.08](../specs/WBL.08-write-modes-and-native-hosts.md)
version 0.5.0 and [native process/build entry](../specs/WBL.08-corebluetooth-host-v1.md)
version 0.3.0.

## Executed boundaries

The portable process fixture implements its own Driver and literal outcomes,
then uses the production framing, reply reservation, deadline, output and close
loop. ExUnit supplies independent JSON expectations through the pinned runtime
guardian and real pipes. Ten cases check passive startup, malformed/private
input, 256 complete discovery records, exact generation/route/bytes/modes,
canonical-value refusal, one active procedure, original deadlines, a successful
producer callback observed at expiry, missing markers, reused IDs, partial EOF,
close over an accepted write and unconfirmed cleanup.

The unread-output case runs a separate child with a full discovery corpus and
100 requests while the parent never reads stdout. Reply saturation retires the
child and exits within the bounded wait. A close success follows actual Driver
retirement/destruction; a withheld timeout is emitted only after cleanup. Marker
delivery is never treated as physical completion or authority.

Three macOS build cases execute the actual offline Apple build, audit the
running architecture, Apple system dependencies and exact embedded usage plist,
probe closed-input startup, verify the executable/guardian through the existing
artifact boundary, reuse the workspace read-only and refuse a changed executable
without repair. The build records selected tool digests, SDK version/settings
and API-header hashes, source/build-helper digests, arguments and artifacts.
Selected tools/SDK and deployment files are required to remain immutable.
The initial trusted C compiler bootstrap retains its existing unverified
descendant-cleanup scope; later commands use the command guardian.

## Commands and results

Commands ran from the repository root on macOS 27.0.1 ARM64, Elixir 1.20.2 /
OTP 29.0.4, Apple SDK 27.0, Apple clang 21.0.0 and LLVM 23.1.3. Deployment
target macOS 14 is a compiler selection, not a macOS 14 runtime result.

```text
mix pkg wotex-ble test test/wotex/ble/corebluetooth_host_test.exs
mix pkg wotex-ble test test/wotex/ble/corebluetooth_build_test.exs
WOTEX_BLE_NATIVE_LANE=sanitizers mix pkg wotex-ble test test/wotex/ble/corebluetooth_operation_test.exs test/wotex/ble/corebluetooth_sdk_test.exs test/wotex/ble/corebluetooth_host_test.exs
mix check.fast --package wotex-ble
mix wotex.native.suite --package wotex-ble --suite corebluetooth --tidy
clang-tidy packages/wotex-ble/test/native/corebluetooth_host_peer.cpp -- -std=c++17
MIX_ENV=test mix pkg wotex-ble run --no-start bin/check_archive.exs
mix test test/wotex/workspace/native_suite_test.exs test/wotex/workspace/native_check_test.exs
mix affected --base HEAD --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-ble
```

The fast gate passes 352 cases (nine doctests, seventeen properties and 326
tests), with 58 explicit-lane exclusions. The fourteen operation, sixteen SDK
and ten process cases pass under ASan/UBSan; the existing component policy
disables leak scanning. All three real build cases pass, including final
bootstrap-argument metadata, bounded filesystem-error handling and tamper
refusal. Three macOS translation units and the portable process peer pass
clang-tidy without first-party findings. Native formatting, strict Credo,
documentation generation/links and seventeen focused root tooling tests pass.

The archive check passes exact members/source bytes and out-of-tree compilation.
It includes the seven CoreBluetooth native files and builder/task sources,
excluding contributor instructions, tests and documentation. The final archive
SHA-256 is `95bd905ad54cec4e9bca36e25d1a3298ab0e54067283fe559d60dfa9a89642d6`;
package lock SHA-256 is `50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.
The existing ordinary-check warning about the optional write-mode consumer
module remains; that optional lane was not executed. Extracted compilation
does not establish a native build or runtime consumer from the archive.

The manifest compile-entry change marks the family affected. Validation stays
with BLE and the owning root tests; full gates across other packages were not
run. The full package gate, Dialyzer, coverage, dependency audits, Linux BlueZ
native/software lanes, independent CoreBluetooth archive consumers, installed
permission/peripheral operation and physical qualification were not run.
All owned test workspaces/binaries and both ordinary-check archive directories
were removed after verification; normal tooling caches remain reusable.

## Exact inputs

Paths are relative to `packages/wotex-ble`.

| File | SHA-256 |
| --- | --- |
| `priv/corebluetooth/native/host.hpp` | `65e1cade550550da21b6276039648a285c80af59fcd6133930935c0ab250dce8` |
| `priv/corebluetooth/native/main.cpp` | `0e2e2257a2565724c9169f68eddc69637b71083b005dc7c74ff2bc9be6e45fd9` |
| `priv/corebluetooth/native/Info.plist` | `896e0b93b1f7c23f928c8c1c6bc2960a22dc30e5cf518a96a3e437aaec8e12aa` |
| `priv/corebluetooth/native/sdk.cpp` | `1f3558b4f0e202ff7b09c6b7cb07b6051f2ea51f3d8c3bd76f8a55242cc0b2b3` |
| `lib/wotex/ble/core_bluetooth/build.ex` | `a9f7a1f178c06e01df6ef9a6207eb50446379572933a51c753e14c0778043c42` |
| `lib/mix/tasks/wotex.ble.corebluetooth.build.ex` | `0526350c6ede0d6a812c5e7a998dee46663938044b04ce588759fef423708f37` |
| `test/native/corebluetooth_host_peer.cpp` | `eacbf6691e0e02c4a24d78150a30e056e35296e866a54dc9bc6b8e5a05509bb4` |
| `test/wotex/ble/corebluetooth_host_test.exs` | `408b5063f608602d65032fea4bc0d65373eb3d48e1bba9e7bb2ea3d7012a9aa0` |
| `test/wotex/ble/corebluetooth_build_test.exs` | `8ca14dfb926bcffc6595eed403e709a1bd87738507b1d3337b261f6b0f855c89` |
| `bin/check_archive.exs` | `e22c827e14c998355f43de9b46f988c9a64376bf569be2e61009193ecfefb33e` |

## Remaining integration

The public Client/session owner, Runtime integration, notifications, explicit
sleep observation and installed Mac qualification remain required. The SDK
selector tests, independent Driver process and passive real-host probe supply
different evidence; none supplies an authenticated peripheral or RF result.
WBL.08 remains partial.
