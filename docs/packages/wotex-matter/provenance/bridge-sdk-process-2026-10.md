# SDK bridge process-driver evidence

Recorded: 2026-10-20. Package: `packages/wotex-matter`.
Source commit: `7e8d0d5dba929ea1a9ffd71a671bf36f039c2e2b`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.30.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.29.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.26.0.
The catalogue remains partial. This record qualifies the internal SDK driver
and its required receiver composition port through actual process pipes.

## Executed boundary

`SdkBridgeProcessDriver` joins `RunBridgeProcess` to explicit private loading,
SDK memory, configured resources, installed provider/endpoints and the SDK event
loop. Construction accesses no SDK resource. A valid open precedes driver entry;
receiver attachment occurs under the SDK stack lock before event-loop startup.
Result-ready notification consumes real generation-scoped handoff custody on
the input thread without taking that lock. Shutdown closes admission, drains
the receiver under the SDK lock, joins the loop and retires SDK resources,
borrowed providers and private owners before SDK memory shutdown. The existing
coordinator supplies its original startup and nonrenewed cleanup deadlines.

The guarded fixture uses pinned SDK development attestation material in private
files and an explicit closed commissioning window. It checks installed root,
aggregator, light and sensor endpoints, ready/model/generation identity, clock
sampling, joined cleanup, restored working directory, a closed commissioning
provider and actual store-lock release by reopening the store after shutdown.
The receiver refuses all child read/write/invoke operations. Its opaque queued
request and synthetic ticket exercise output ordering and actual result custody;
they establish no authenticated request decoding or consumer execution.

| Cases | Required observation |
| --- | --- |
| `normal`, `reopen` | Actual configured SDK startup; ready/probe/close; compatible durable mappings and released resources |
| `missing-config`, `credentials`, `bad-interface` | Missing private input or interface prevents ready and receiver attachment |
| `bad-open`, `missing-open` | Invalid or absent first control prevents SDK startup |
| `input-eof`, `cancel`, `generation`, `output-lost` | EOF, explicit cancellation, wrong generation or output loss closes the actual SDK lifetime without a closed receipt |
| `attach-fail` | Partial receiver attachment is retired before SDK cleanup |
| `finish-fail` | Actual child exit 70; no successful process or closed receipt |
| `result`, `result-refuse` | Actual handoff result consumed before close or notification refusal |
| `pending` | Closed, unconsumed ticket drained before SDK shutdown |

All sixteen cases pass in ordinary and ASan/UBSan builds: thirty-two executions.
The output-loss fixture holds input open until process return, so competing EOF
cannot substitute for its selected shutdown trigger. Each successful fixture
reports exactly `owned SDK process driver and pipes passed`; the wrapper checks
the actual exit status. Fatal retirement reports no success marker and exits 70.
The verifier rejects the older standalone lifecycle marker, wrong exits, extra
output, duplicate receipts, missing LF and sanitizer diagnostics. The owning
builder runs all sixteen cases in each mode and records their binary digests.

The preexisting standalone SDK lifecycle fixture also passes `normal` and
`reopen` against both newly linked binaries. The portable coordinator executable
passes all twenty-five scripted real-pipe case families in fresh Linux AMD64
CMake builds, ordinary and ASan/UBSan. Those fifty family executions renew the
coordinator after its SDK-compiler shadow-warning cleanup; they exercise no
authenticated peer. ASan/UBSan report no faults with leak detection enabled.
Intentional fatal `_Exit` paths do not establish leak finalization or successful
resource cleanup.

## Build and artifact identity

The selected SDK is connectedhomeip v1.6.0.0,
`250a9e6c50ee2068107f3c4808b680f5f2925415`, archive SHA-256
`83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628`.
The existing [source manifest](../../../../packages/wotex-matter/test/support/software/sources.json)
pins its dependency/tool archives. The generated bridge-model digest remains
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.

Linux AMD64 uses GCC 12.2.0, Ninja 1.11.1 and CMake 3.25.1. The prepared tool
image derives from the owning builder's pinned
`node:24-bookworm@sha256:6dac556d980b7f0e5498d08f08cee0ca67798b4ad6c23964a9214920e67758d0`.
Its local image ID is
`c7a0bf7283aa81f21d4fd653805548f625ccb361bfe95af6db9d146449075baa`.
The qualification container uses `--platform linux/amd64 --network none`, one
explicit workspace and read-only current package/source mounts. No image is
published. Existing pinned SDK libraries are reused; GN regenerates separate
ordinary/sanitized graphs, and all four changed translation units are explicitly
rebuilt before linking. This is focused current-source qualification, not a new
complete native/software gate. The earlier preparation manifest belongs to its
immutable source snapshot and is not promoted to this commit.

Both qualification runs record the same package input identity, calculated by
the existing `SoftwareManifest.identity/1` sorted path/NUL/digest/LF algorithm:
`7727e8bb44002ca373af1d77001427db61d73f4373c46ae7b2d77e235a3dbd10`.
The lockfile SHA-256 is
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.

| Artifact | SHA-256 |
| --- | --- |
| Ordinary SDK process/lifecycle executable | `aaf8316555d7d1d4275f5839352e7d0a4b08d563d6e1abb30ddb08fcb51cc21b` |
| ASan/UBSan SDK process/lifecycle executable | `fe2eaff3c2dd6e5dfaacaa38607115edb94f0cecf42b8b1ee507b472996bdfb2` |
| Ordinary GN arguments | `42a46e0928aa064cd99207bb5f0809cbe7c2b326dd3d5a3c701ee89c1d692bb5` |
| ASan/UBSan GN arguments | `2ef255e1fd2016c3c409760ea3a759ec448f674c1fee7dd2e9206c5fdcef63f4` |
| Ordinary portable coordinator executable | `e96720d5e474f930cd4bf06f6986b4de80d06c2240a80356fcd72375be98ce81` |
| ASan/UBSan portable coordinator executable | `f5654d2d9842c9a6852f5d35d798a91493b3f8a101f9107b075f4950a9848494` |
| Checked package archive | `059c8a8e21f46edd1fc9d71540e49c9589c27191437e3f1626eb0b9952db6093` |

The archive check builds with the registry dependency selection, verifies exact
contents including the four new driver/fixture files, excludes repository
instructions and documentation, and compiles the extracted archive out of tree.
It establishes packaging, not independent native driver adoption.

## Commands and package checks

Commands run from the repository root. `${sdk_workspace}` normalizes the explicit
disposable build directory; `/src` is the read-only current package mount.
`process-{mode}` ranges over the sixteen modes above. The owning
`SoftwareBridgeBuild.process_command/2` wrapper checks actual exits and
`verify_process!/2` checks exact output. Both modes use
`ASAN_OPTIONS=detect_leaks=1:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`.

```text
/work/tools/gn/gn --root=/work/sdk gen /work/build-process
ninja --quiet -C /work/build-process -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test
/work/tools/gn/gn --root=/work/sdk gen /work/build-process-sanitized
ninja --quiet -C /work/build-process-sanitized -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test
timeout 20 /work/build-process/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test process-{mode}
timeout 20 /work/build-process-sanitized/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test process-{mode}
cmake -S /src/native -B /work/process-cmake -DWOTEX_MATTER_JSON_INCLUDE=/work/sdk/examples/wotex-matter-host/third_party
cmake --build /work/process-cmake --target wotex_matter_bridge_process_test --parallel 2
ctest --test-dir /work/process-cmake -R ^wotex_matter_bridge_process_test$ --output-on-failure
cmake -S /src/native -B /work/process-cmake-sanitized -DWOTEX_MATTER_JSON_INCLUDE=/work/sdk/examples/wotex-matter-host/third_party -DWOTEX_MATTER_SANITIZERS=ON
cmake --build /work/process-cmake-sanitized --target wotex_matter_bridge_process_test --parallel 2
ctest --test-dir /work/process-cmake-sanitized -R ^wotex_matter_bridge_process_test$ --output-on-failure
mix pkg wotex-matter test test/wotex/matter/software_build_test.exs
mix check.fast --package wotex-matter
mix native.lint --package wotex-matter --base f5df9c1b --fix
mix native.lint --package wotex-matter --base f5df9c1b
MIX_ENV=test mix pkg wotex-matter run --no-start bin/check_archive.exs
mix affected --base f5df9c1b --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The focused software-builder file passes 26 tests. The fast package run passes
compilation, Elixir formatting, Credo and all 382 tests/properties/doctests;
37 explicit-lane tests are excluded. Its final native format step initially
fails two changed lines. Those lines are formatted and the separate native lint
passes; the complete fast command is not rerun solely for formatting. Catalogue
tests pass six cases, generated metadata is current, repository Markdown links
resolve and ExDoc generation passes. Only Matter is affected against `f5df9c1b`.

Per the authorized focused workflow, full `mix check`, Dialyzer, SDK clang-tidy,
fresh full native/software and interop/hardware lanes, benchmarks and release
operations are unrun. Production executable assembly, authenticated receiver and
consumer dispatch, approved-observation application/reporting, actual clock-rate
qualification and independent controller workflows remain open. These results
establish no commissioning, complete Matter/WMA.09 conformance, certification,
physical effects or containment guarantee.
