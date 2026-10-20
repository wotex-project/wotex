# Native bridge process coordination evidence

Recorded: 2026-10-20. Package: `packages/wotex-matter`.
Source commit: `ec7307d69cc319095d09008e434f75c9173ce0e3`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.29.0-target
and [bridge delivery plan](../plans/exposed-bridge-delivery.md) version 1.28.0.
This record qualifies the internal process coordinator with a scripted SDK
composition port. Production SDK process assembly remains open.

## Executed boundary

`RunBridgeProcess` joins the existing generation custody, result/clock input and
bounded output owners. Its first open is bounded to 512 bytes including LF;
one selected 1..5000-millisecond startup budget includes both that wait and ready
admission. Malformed, incomplete and extra pre-ready input cannot resolve a
request or sample a probe. SDK initialization retains exclusive startup custody
until its driver returns. Concurrent loss publishes cancellation without touching
that custody. Ready precedes any requests queued by the driver during startup.

Shutdown closes admission, joins the reader and invokes the explicit driver
cleanup once. Only successful cleanup permits the final closed receipt. The
writer preserves any active frame through LF before that receipt. One cleanup
deadline includes input retirement, SDK drain and final output. The watchdog uses neither custody
nor output locks, including when the driver deliberately holds custody forever.
False cleanup or a missed startup/cleanup deadline terminates the child process
with 70 and supplies no successful cleanup receipt. Input retirement notifies
the process once before clock/custody validation can block; that notification
arms the deadline without waiting for the reader or main thread. Descriptor-loss
monitoring also detects EOF while a probe is blocked on custody. Later input,
driver and output stages retain the same deadline.

The fixture owns real input/output pipes, a separate audit pipe and child
processes. It checks actual exit statuses, joined children and public settable
descriptor flags. macOS also exposes kernel write-history bits through F_GETFL;
those bits are outside the settable status mask. Its scripted driver reserves
real custody and consumes a real result through the input callback. A small
opaque request frame checks queue ordering; it does not establish SDK request
encoding, authenticated admission or consumer dispatch.

| Case families | Count | Executed observation |
| --- | ---: | --- |
| Invalid descriptors and budgets | 1 | Four invalid calls enter no driver |
| Fragmented open, queued request, result and probe | 1 | Ready first; exact generation/sample; result consumed before close |
| Malformed, oversize, wrong-role, duplicate and partial first frames | 5 | No ready receipt; fixed input refusal |
| Missing open | 1 | Original opening deadline refuses startup |
| Delayed open plus slow initialization | 1 | The combined startup budget is not renewed; no ready receipt |
| Normal, refused and stuck cleanup; explicit cancellation | 4 | Closed only after success; failed/stuck cleanup terminates; cancellation emits no closed |
| Input EOF after ready | 1 | Driver cleanup completes without a closed receipt |
| Early probe during initialization | 1 | Startup cancels without sampling or ready |
| Driver startup refusal | 1 | Driver cleanup runs once; no ready |
| Stuck startup | 1 | Watchdog terminates the actual child |
| Output loss during startup | 1 | Cooperative cancellation and cleanup without ready |
| Startup/cleanup holding custody during output loss | 2 | Audit handshake proves the lock is held; watchdog still terminates |
| Running custody held during EOF, close and probe/EOF | 3 | Input retirement and descriptor loss arm cleanup before a blocked custody call; the child terminates without closed |
| Independent processes | 1 | Closing one leaves the other's probe and close usable |
| Blocked final output | 1 | A maximum-sized active frame cannot be abandoned to fabricate closed or block forever |

All twenty-five families pass in all four builds: macOS normal and ASan/UBSan,
and Linux ARM64 normal and ASan/UBSan. Each successful executable reports exactly
`bridge-process-cases=25`. Native CTest passes all nine portable executables on
macOS and all ten on Linux, including its private-file interposition fixture.
The process test takes about seven seconds; no SDK initialization, network
interface, commissioning exchange or physical target is used.

ASan/UBSan report no faults in these runs. macOS uses `detect_leaks=0`; Linux
uses `detect_leaks=1`. Fixture children deliberately use `_Exit`, including the
fatal watchdog paths. These results do not establish child leak finalization,
successful SDK cleanup after a fatal exit or native memory containment.

## Commands and toolchains

Commands run from the repository root. `${native_workspace}` below normalizes
the disposable absolute workspace. Its `json/nlohmann/json.hpp` is staged from
the repository's byte-identical copy of the existing selected nlohmann 3.11.3
input; its digest matches [the Matter source pin](../../../../packages/wotex-matter/test/support/software/sources.json).
CMake receives that path explicitly; production code discovers no sibling source.

```text
cmake -S packages/wotex-matter/native -B ${native_workspace}/normal -DWOTEX_MATTER_JSON_INCLUDE=${native_workspace}/json -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build ${native_workspace}/normal --parallel 2
ctest --test-dir ${native_workspace}/normal --output-on-failure
cmake -S packages/wotex-matter/native -B ${native_workspace}/sanitized -DWOTEX_MATTER_JSON_INCLUDE=${native_workspace}/json -DWOTEX_MATTER_SANITIZERS=ON -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build ${native_workspace}/sanitized --parallel 2
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir ${native_workspace}/sanitized --output-on-failure
clang-tidy -p ${native_workspace}/normal packages/wotex-matter/native/src/bridge_input.cpp packages/wotex-matter/native/src/bridge_process.cpp packages/wotex-matter/native/testing/bridge_process_test.cpp
HEX_OFFLINE=1 mix pkg wotex-matter deps.get
mix native.lint --package wotex-matter --base 5bdf1201 --fix
mix check.fast --package wotex-matter
MIX_ENV=test mix pkg wotex-matter run --no-start bin/check_archive.exs
mix test test/wotex/workspace/catalogue_test.exs
mix affected --base 5bdf1201 --detail
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The macOS host is 27.0.1 ARM64, with AppleClang 21.0.0.21000334 and SDK 27.0;
clang-format/tidy are LLVM 23.1.3. Native compilation enables Wall, Wextra,
Wpedantic and Werror. All three selected translation units pass clang-tidy. Four bounded-string
exception-analysis false positives have adjacent NOLINT reasons; external/header
diagnostics are suppressed.

Linux uses the cached `wotex-native-linux:977d7ed5daf3af46` ARM64 image, image ID
`8765b0b7d927693e19f23d2304a49fe68a408ca1ce8dbc64d0577a9fe1f92b4d`, with GCC
13.3.0. Every container runs with `--rm --network none --platform linux/arm64`,
the package mounted read-only at `/src` and the workspace at `/work`. Executed
inner commands are:

```text
cmake -S /src/native -B /work/linux-normal -DWOTEX_MATTER_JSON_INCLUDE=/work/json -DWOTEX_MATTER_SANITIZERS=OFF -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build /work/linux-normal --parallel 2
ctest --test-dir /work/linux-normal --output-on-failure
cmake -S /src/native -B /work/linux-sanitized -DWOTEX_MATTER_JSON_INCLUDE=/work/json -DWOTEX_MATTER_SANITIZERS=ON -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build /work/linux-sanitized --parallel 2
env ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir /work/linux-sanitized --output-on-failure
```

The package fast gate passes 381 cases: three doctests, four properties and
374 tests, with 37 explicit-lane exclusions. Package compilation, strict Credo,
formatting, six catalogue tests, generated catalogue, Markdown links and ExDoc
pass. Initial package preparation uses the locked offline cache and changes no
lockfile; upstream tooling emits existing compiler warnings during preparation.
The affected set against `5bdf1201` is Matter only.

The ordinary archive check verifies native member/source bytes, including all
three new process files, and compiles extracted Elixir source out of tree. It
removes its workspace automatically; a separate existence check confirms removal.
The four native build trees and staged header are also removed after recording
their identities. These source builds do not establish native artifact adoption
from an independently installed package archive.

Full gates, Dialyzer, coverage, the SDK-bound native build, real SDK driver
assembly, authenticated requests/probes, qualified clock rates, native approved
observations, controller interoperability and hardware qualification were not
executed. No complete bridge/server, certification or physical-effect claim
follows from this coordinator. WMA.09 remains partial.

## Exact inputs and artifacts

Package paths are relative to `packages/wotex-matter` at the source commit above.

| Input or artifact | SHA-256 |
| --- | --- |
| `native/include/wotex_matter/bridge_process.hpp` | `1ca92631d23ccc5ec81218244b21fe0ff97429e94304d984fa1358f8be24a52c` |
| `native/include/wotex_matter/bridge_input.hpp` | `2aff0a8d52023d3025b079eb5843c79473b19c26dfbfae572fb64d31a6f11a10` |
| `native/src/bridge_input.cpp` | `d9dc4de6393c2f6d1dbf8a62ad3e091c25ccbfe3ea03e656fcfea1d3d689df51` |
| `native/src/bridge_process.cpp` | `0d4c0b0cfb9a66fa3149bbb6780acf9fb92046c0d6e8d75c46e7c944288d909b` |
| `native/testing/bridge_process_test.cpp` | `3325f04de96f113f56eac6d29b5db008d2bc0d056c9d2fb402d330f10583da87` |
| `native/CMakeLists.txt` | `c2d14a90668d7f82c8b7d8fcb7fdceb3cba4b1de17842bc46fad492160184538` |
| `bin/check_archive.exs` | `45673b4f43c8f73e6dddb6ff4b29e7b2c86a4e97035e6442a3a3c157cfd49e3e` |
| `mix.lock` | `50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4` |
| Selected JSON header | `9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6` |
| Ordinary package archive | `6da7d3e984ab0ee4211a5f8d2b7afc50a8963b3976271a0ce193f6b9dbfea826` |
| macOS normal process test | `9499bdcb6dc524f7b44e23ef5e88a52eb5015715e18d1268de244b31416ff748` |
| macOS sanitized process test | `f714255d6e89861504ebe665e8be82b11f696d10110ea7bc183050101d8ddf2d` |
| Linux ARM64 normal process test | `d2457a6e209984d37eac575438d458fbc86ade2b7e36d0d22673bc6aaba2f2a0` |
| Linux ARM64 sanitized process test | `b76f2d06a863c29e1057815b0a091f18ebc2512a007a9ce092f6d0a0d7fd1dcb` |
