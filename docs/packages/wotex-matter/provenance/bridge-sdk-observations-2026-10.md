# Native SDK observation delivery evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `a8a37454acbcbfea3292069975f4cb27a0ffd4bd`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.31.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.30.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.27.0.
WMA.09 remains partial.

## Executed application boundary

The process input validates the observation's exact generation, current custody
clock and strictly increasing ID before transferring its owned value. Observation
IDs remain independent of request and clock-probe IDs. Observations retain the
existing 1024-byte frame limit including LF; result, open, close and clock
controls retain 512 bytes. The input reader applies no SDK state and takes no
SDK lock.

`SdkBridgeObservationOwner` reserves one of sixty-four distinct output slots
before queue admission. The reservation stays charged during queued work,
application, queued receipt and complete transmission or discard. Request and
control capacities remain sixteen and four. One worker acquires the SDK lock,
checks current custody and applies the exact Thing/endpoint/capability through
`SdkBridgeEndpointBinding::Observe`. It publishes the correlated applied/refused
receipt outside SDK/custody locks. Queue/output mutexes are never held across
SDK acquisition or descriptor I/O. The SDK driver joins this worker outside SDK
locks before receiver, endpoint and SDK cleanup.

Semantic refusal preserves previous approved state and reachability. Closed
custody prevents queued application. Malformed/replayed input and full admission
end the generation. Encoding or output failure after application closes without
retry; missing receipt does not establish whether application occurred. Terminal
finish discards unstarted reservations while preserving an active frame through
LF before closed. These are approved-state mechanics, without command authority
or physical-effect inference.

The guarded SDK fixture uses private pinned development material and an explicit
closed commissioning window. Its receiver refuses child operations. State checks
read actual SDK attributes through the generated provider/external storage;
they do not compare only receipt fields or a fixture shadow state.

| Added SDK case | Executed observation |
| --- | --- |
| `observations` | Light true/false/unavailable, independent reachability, sensor value/null and fixed range endpoints are applied and read back |
| `observation-refused` | Six wrong Thing/endpoint/capability/range cases return refused and preserve prior light, sensor and reachability |
| `observation-credit` | Sixty-four queued updates retain receipt credit while the SDK lock is held; a clock probe still completes; receipts remain ordered |
| `observation-result` | Real result custody and a probe complete while an earlier observation waits for the SDK lock |
| `observation-full` | A sixty-fifth observation closes input while the SDK lock remains held; no queued state is applied |
| `observation-close`, `observation-cancel` | A custody-closure barrier precedes releasing the SDK lock; queued state remains unapplied and cleanup joins |
| `observation-replay` | A duplicate ID cannot replace the state already applied by its first receipt |
| `observation-generation`, `observation-malformed` | Foreign generation and decoded duplicate keys reach no SDK application |
| `observation-long` | A 256-byte opaque Thing identity crosses a frame larger than 512 bytes and reaches actual SDK state |

All eleven added families and the sixteen previous process families pass in
ordinary and ASan/UBSan builds: 54 executions. The existing process-specific
marker and actual exit verifier remain mandatory. The deliberate failed-cleanup
case exits 70 without a success marker. All successful cases also exercise
joined SDK retirement and store-lock reopening.

The portable input/output/process executables pass on macOS ARM64 and Linux
AMD64, ordinary and ASan/UBSan: twelve executable runs. Input tests exercise
1024-byte observation framing, preserved 512-byte controls, real allocation
refusal with unchanged caller output, fragmented frames, separate ID namespaces,
clock refusal and notification failure. Output tests exercise exact independent
capacities, reservation identity, duplicate/forged completion, allocation refusal,
counter exhaustion and closure. A prefilled real pipe holds an observation active
while all sixty-four slots remain charged; terminal finish releases the other
reservations and preserves the active frame before closed. The process executable
also passes its existing twenty-five real-pipe/watchdog families in every build.

Nine SDK wait/input/output regression modes pass in both builds: `wait`,
`wait_input_eof`, `wait_input_malformed`, `wait_input_partial`, `wait_input_cancel`,
`wait_clock_probes`, `wait_output_close`, `wait_output_cancel` and
`wait_output_lost`. Both paired request/result/argument/probe codec runs pass,
and standalone SDK lifecycle `normal`/`reopen` pass in both newly linked builds.

## Source and artifact identity

SDK, generated model, dependency sources and tool inputs retain the exact
[software profile](../plans/exposed-bridge-profile.md) and
[source manifest](../../../../packages/wotex-matter/test/support/software/sources.json).
The SDK revision is `250a9e6c50ee2068107f3c4808b680f5f2925415` and the generated
model digest is `dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.
The prepared image/toolchain identity is the one recorded in the
[SDK process-driver evidence](bridge-sdk-process-2026-10.md): Linux AMD64 GCC
12.2.0, Ninja 1.11.1 and CMake 3.25.1. Qualification uses explicit read-only current
source mounts and `--platform linux/amd64 --network none`.

GN regenerates both existing graphs and rebuilds current first-party inputs;
the changed input object is explicitly removed before linking each SDK process
target. Exact pinned SDK libraries are reused. This qualifies the affected SDK
targets rather than claiming a fresh full native/software build. Portable CMake
targets compile current source independently. macOS uses AppleClang
21.0.0.21000334 on 27.0.1 ARM64; clang-format/tidy are LLVM 23.1.3.

Both process runs record the same package input digest using
`SoftwareManifest.identity/1`:
`02ea512ff632451cf335002f2b91a05bc67f54042d00d2eb353d776bdd487322`.
Every recorded member digest is checked against the committed source.
The lockfile SHA-256 remains
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.

| Artifact | SHA-256 |
| --- | --- |
| Ordinary SDK process/lifecycle executable | `a47e1b86752d6d956e00155733acb0072a11fc910e81a008d29d033e84b87a55` |
| ASan/UBSan SDK process/lifecycle executable | `156546db21c7f484648b3fef658209870a5f299dd900ba1616da3f0d32ea9346` |
| Ordinary SDK server regression executable | `28d4a32b7baa2d3559afec7061efcf00dd2c32f845c4ed6ad5dc3a53d4b1ee88` |
| ASan/UBSan SDK server regression executable | `6330eed66dcbe56d57289e10341141fba9ac2d910809cfff94d30eab376186b7` |
| Ordinary paired codec executable | `180487c801d8a352f0f7e09bd97dd5d9ff992a665a50bedf66a0f769f25d913b` |
| ASan/UBSan paired codec executable | `d4b2b3ca8a2ed25ad4bb00bf6a2cd0302f8e897b807ee97e77e097125d5ab691` |
| Checked package archive | `6778d195603f40fd721fa426419170996ead8d9be75c83f5b14e9f922bc0337d` |

## Commands and limits

Commands run from the repository root. Paths below normalize the disposable
workspace; `/src` is the explicit current package mount. `${build}` ranges over
ordinary and sanitizer graphs, `${mode}` over the recorded cases, and the host
CMake variants use the corresponding absolute workspace paths. Every CTest
invocation selects only the three affected executables and has a 20-second
per-executable timeout.

```text
/work/tools/gn/gn --root=/work/sdk gen /work/${build}
ninja --quiet -C /work/${build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test process-${mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test ${explicit_store} ${mode}
cmake -S /src/native -B /work/${cmake_build} -DWOTEX_MATTER_JSON_INCLUDE=/work/sdk/examples/wotex-matter-host/third_party
cmake --build /work/${cmake_build} --target wotex_matter_bridge_input_test wotex_matter_bridge_output_test wotex_matter_bridge_process_test --parallel 2
ctest --test-dir /work/${cmake_build} -R '^wotex_matter_bridge_(input|output|process)_test$' --output-on-failure --timeout 20
clang-tidy -p ${macos_build} packages/wotex-matter/native/src/bridge_input.cpp packages/wotex-matter/native/src/bridge_output.cpp packages/wotex-matter/native/src/bridge_process.cpp packages/wotex-matter/test/native/bridge_input_test.cpp packages/wotex-matter/test/native/bridge_output_test.cpp --quiet
mix native.lint --package wotex-matter --base 6373d932 --fix
mix check.fast --package wotex-matter
MIX_ENV=test mix pkg wotex-matter run --no-start bin/check_archive.exs
mix affected --base 6373d932 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

Sanitizer CMake builds additionally set `-DWOTEX_MATTER_SANITIZERS=ON`. ASan/UBSan
use halt-on-error; leak detection is enabled on Linux/SDK runs and disabled on
macOS. No sanitizer fault is reported. Deliberate `_Exit` paths establish neither
leak finalization nor successful cleanup. All five selected portable translation
units pass clang-tidy. The fast package gate passes all steps: 382
tests/properties/doctests, 37 explicit-lane exclusions, formatting and Credo.
The archive check verifies exact contents and out-of-tree compilation; it is no
independent native adoption claim. Catalogue tests pass six cases, generated
metadata is current, Markdown links resolve and ExDoc generation passes. Only
Matter is affected against `6373d932`.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh complete native/software builds,
interop/hardware lanes and benchmarks are unrun under the focused workflow.
Production executable assembly, authenticated child request/consumer dispatch,
actual clock-rate qualification and independent controller/reporting workflows
remain open. This evidence establishes no commissioned peer, physical effect,
complete WMA.09/Matter conformance, certification or containment guarantee.
