# Synchronous SDK observation progress evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `bf8da8961a6244f3af88569dbf585051388c6f10`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.32.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.31.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.28.0.
The catalogue remains partial.

## Executed dependency and fix

The existing consumer contract permits a result mapper to require an actual
observation receipt before returning completed. A synchronous SDK read retains
the SDK stack lock and its borrowed encoder while awaiting that consumer result.
Previously the ordinary observation worker removed the observation and waited
for the same SDK lock. The new receipt-before-result SDK fixture, run before the
fix, aborts at its successful-read assertion with actual exit 134. The receipt
arrives without a successful read. This is an executed regression, separate from
the earlier fixture that held a lock but sent the result before awaiting state.

The explicit `BridgeHandoffProgress` port now advances a bounded step outside
custody locking, on the synchronous SDK caller while it retains its SDK lock.
The three-argument `BridgeHandoffOwner::Wait` rechecks its original deadline after every
progress step and wake, with at most a one-millisecond progress sleep. Refusal
closes custody and overrides even an already staged completion. Ordinary waits
without this port preserve their existing notification/deadline behavior.

The observation owner leaves queued work available while its ordinary worker
cannot acquire the SDK lock. A synchronous callback can apply one queued
observation under SDK/current custody. A separate finite publication queue lets
the worker encode and submit its receipt without acquiring that callback-held
SDK lock. Application and publication share the same sixty-four outstanding
output reservations; FIFO and original mutation/no-retry semantics remain.

The SDK driver constructs this passive owner before receiver attachment and
starts its worker after event-loop startup. Cleanup stops the worker before
receiver retirement, but retains the borrowed owner through receiver Finish
and joined SDK shutdown. A callback returning from progress cannot use a freed
owner. The guarded fixture explicitly uses the stopped progress owner during
receiver Finish under the SDK lock.

## Actual SDK and portable cases

The six added modes schedule a real installed-provider read on the SDK event
loop. The callback owns a real encoder, reserves actual handoff custody, emits
an opaque fixture request and waits with the progress port. The pipe consumer
awaits observation receipts before submitting its result. Successful readback
parses the SDK's actual attribute report and requires the approved true value.
The fixed callback uses synthetic metadata and establishes no fabric
authentication, SDK ACL grant or consumer authorization.

| Mode | Executed observation |
| --- | --- |
| `observation-wait` | Applied receipt precedes consumer completion and successful native readback while the callback retains its SDK lock |
| `observation-wait-many` | All 64 ordered observations and receipts complete before the consumer result; final native state is read back |
| `observation-wait-refused` | A semantic refusal receipt followed by valid applied state does not stall the synchronous read |
| `observation-wait-timeout` | State publication does not renew the original 500 ms request deadline; a later result cannot revive the timed-out read |
| `observation-wait-close` | Explicit close wakes/drains the read, joins cleanup and supplies closed without a successful read |
| `observation-wait-cancel` | External cancellation wakes/drains the read and supplies no successful read or closed receipt |

All six modes plus the previous twenty-seven process families pass in ordinary
and ASan/UBSan builds: 66 process-case executions. Exact process markers and
actual exit statuses remain required; the intentional failed-cleanup family
exits 70 with no success marker.

The portable owner tests exercise callback reentry into unlocked custody,
completion/refusal races, the original deadline at 599/600 ms, clock regression
with unchanged output, periodic progress without external result notification,
callback closure and no unnecessary progress for foreign, ready or expired
tickets. Unexpected exceptions in the test callback terminate that fixture,
rather than becoming a successful protocol refusal. The affected owner,
input, output and process executables pass on macOS ARM64 and Linux AMD64,
ordinary and ASan/UBSan. The existing twenty-five process watchdog/pipe families
pass in every build. Both changed portable translation units pass clang-tidy.

Nine SDK regressions pass in both builds: `wait`, `wait_input_eof`,
`wait_input_malformed`, `wait_input_partial`, `wait_input_cancel`,
`wait_clock_probes`, `wait_output_close`, `wait_output_cancel` and
`wait_output_lost`. The paired request/result/argument/probe codec and standalone
SDK lifecycle `normal`/`reopen` also pass against both newly linked builds.

## Inputs and artifacts

The exact SDK/dependency/model pins remain those of the
[software profile](../plans/exposed-bridge-profile.md) and
[source manifest](../../../../packages/wotex-matter/test/support/software/sources.json):
SDK revision `250a9e6c50ee2068107f3c4808b680f5f2925415`, generated model digest
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.
Prepared image/toolchain identity is recorded in the
[SDK process-driver evidence](bridge-sdk-process-2026-10.md): Linux AMD64 GCC
12.2.0, Ninja 1.11.1 and CMake 3.25.1. Separate ordinary/sanitized containers use
`--platform linux/amd64 --network none` and explicit read-only current source
mounts. Existing pinned SDK libraries are reused; affected first-party targets
are rebuilt. This is focused qualification, not a fresh full native/software gate.
macOS uses AppleClang 21.0.0.21000334 on 27.0.1 ARM64 and LLVM 23.1.3 tools.

Both process runs record package input digest
`b38c14ddb9e25e15700ab0f7e6c111037f827fe643bef37c496b9b46887fc502`
through `SoftwareManifest.identity/1`. Every recorded member digest is checked
against the committed source. The lockfile SHA-256 remains
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.

| Artifact | SHA-256 |
| --- | --- |
| Ordinary SDK process/lifecycle executable | `b2c305c08786f36c6ca9d3d823acd27c48fee333a2f1c12309763cc2ce86c8f0` |
| ASan/UBSan SDK process/lifecycle executable | `d4f6e46816b7ddfa9b40adb2bbbd804f9c69a30b7d0341e769d6eef53d9b233e` |
| Ordinary SDK server regression executable | `b34d9da7b8e5b17bd5cdcaa9712a79cad1bad270eacd25f712ede57306477bd6` |
| ASan/UBSan SDK server regression executable | `3d3fe75c5e17724b2095b0a625ae505bdc9181c18f99a74d715ae47bf9b3bc5d` |
| Ordinary paired codec executable | `a829a0cccfbc411c93408b9269eaad3b99a4934b1b6240a399daff11e29c7dbe` |
| ASan/UBSan paired codec executable | `0085c8094c807e6961feb4bca7b6395fac5fd7f24cae22dfa388ec90a8ae29ee` |
| Checked package archive | `ab4b08076e0e21090b1fb4db2e3e8001eaf6f0b27beb63d32f9dbaee1fbb23d0` |

## Commands and qualification limits

Commands run from the repository root. Workspace paths below are normalized;
`${build}` and `${cmake_build}` select ordinary or sanitizer graphs. `${mode}`
ranges over the recorded modes. The owning `SoftwareBridgeBuild` marker/exit
verifiers check each SDK result. CTest selects only the four affected executables
and imposes a 20-second per-executable timeout.

```text
ninja --quiet -C /work/${build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test process-${mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test ${explicit_store} ${mode}
cmake --build /work/${cmake_build} --target wotex_matter_bridge_handoff_owner_test wotex_matter_bridge_input_test wotex_matter_bridge_output_test wotex_matter_bridge_process_test --parallel 2
ctest --test-dir /work/${cmake_build} -R '^wotex_matter_bridge_(handoff_owner|input|output|process)_test$' --output-on-failure --timeout 20
clang-tidy -p ${macos_build} packages/wotex-matter/native/src/bridge_handoff_owner.cpp packages/wotex-matter/test/native/bridge_handoff_owner_test.cpp --quiet
mix native.lint --package wotex-matter --base c4d33869 --fix
mix check.fast --package wotex-matter
MIX_ENV=test mix pkg wotex-matter run --no-start bin/check_archive.exs
mix affected --base c4d33869 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

CMake graphs retain the explicit pinned JSON include and sanitizer settings
recorded in the [observation evidence](bridge-sdk-observations-2026-10.md).
ASan/UBSan halt on error; leak detection is enabled on Linux/SDK runs and disabled
on macOS. No sanitizer fault is reported. Intentional fatal exits establish
neither leak finalization nor successful cleanup. The package fast gate passes
382 tests/properties/doctests with 37 explicit-lane exclusions, formatting and
Credo. Exact archive contents and out-of-tree compilation pass. Catalogue tests
pass six cases, generated metadata is current, Markdown links resolve and ExDoc
generation passes. Only Matter is affected against `c4d33869`.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh complete native/software builds,
interop/hardware lanes and benchmarks remain unrun under the focused workflow.
Authenticated request receiver/consumer dispatch, production executable assembly,
actual clock-rate qualification and independent controller/reporting workflows
remain open. These results establish no commissioned peer, complete WMA.09/Matter
conformance, certification, physical effect or containment guarantee.
