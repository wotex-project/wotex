# Guarded SDK consumer receiver evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `70bf17e9efc19c9dc9bb9b53e6f2fdd51132b3db`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.33.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.32.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.29.0.
The catalogue remains partial.

## Implemented join and observed correction

The internal `SdkBridgeConsumerReceiver` attaches actual SDK fabric scopes,
attribute/invoke guards and retained contexts to the process's shared request
custody. It resolves live opaque Thing identities and emits the existing scoped
request frames. Synchronous read/write waits use explicit observation progress;
completed operations revalidate the original scope before native service.
Finite writes reconstruct a fresh decoder from the copied scalar. Invokes return
no automatic Success and require an explicit native command renderer.

A completion worker serializes with SDK callbacks while retaining no custody
mutex during native rendering or handler release. The new threaded
`SdkBridgeInvokeContexts::Respond` overload takes the correlated result under
the matching owner, then performs guard validation/rendering outside that mutex.
The renderer fixture explicitly reacquires custody, so retaining the mutex would
stall the bounded test. Input notifications acquire no SDK lock. Receiver work
retires and joins outside SDK locks before final context/fabric cleanup under
the SDK lock. The borrowed observation owner survives joined SDK shutdown.

The initial `write-version` fixture aborts with actual exit 134 at its required
DataVersionMismatch assertion. The external OnOff observation previously called
the reporting notification without advancing the codegen cluster data version.
Using the pinned SDK's `emberAfAttributeChanged` now advances that version and
notifies reporting. The completed write then refuses the stale supplied version
and preserves its previous OnTime configuration. Consumer completion itself
never establishes canonical OnOff state.

Native external storage now retains IdentifyTime, OnTime and OffWaitTime values
and persists StartUpOnOff before publication. A fresh SDK process reopens the
same store and reads the configured StartUpOnOff value, without a retained SDK
cache. This establishes that persistence cell, not complete cluster timing or
production light behavior.

## Executed cases

The guarded fixture uses the installed provider, actual SDK event loop,
explicit development credentials, real private pipes, generated operational
fabric certificates and current SDK ACL entries. Its callback principals are
synthetic CASE inputs, not authenticated transport deliveries.

| Receiver families | Executed assertion |
| --- | --- |
| `read`, `read-observe` | Successful native readback; an applied observation receipt can precede consumer completion while the read retains its SDK lock |
| `read-denied`, `read-failed`, `read-unknown`, `read-timeout` | Refusal/Failure/Timeout replaces successful native encoding; expiry uses the original 500 ms deadline without a consumer result |
| `write`, `write-denied`, `write-version` | Copied scalar applies after completion; denied and stale-version writes preserve previous configuration |
| `write-null`, `write-invalid`, `foreign-decoder` | Nullable configuration works; invalid enum and mismatched decoder principal admit no request |
| `invoke`, `invoke-denied`, `invoke-failed`, `invoke-unknown`, `invoke-timeout` | Retained handle replies exactly once and retires; non-completed outcomes never enter the native completed renderer |
| `invoke-revoked`, `invoke-render-error` | Current ACL revocation and failed reply encoding drain handles and close the generation without a successful closed receipt |
| `invoke-full`, `invoke-closed` | Sixteen contexts retain their handlers; seventeenth admission refuses; close drains pending work with Failure and no completed rendering |
| `pase`, `missing-acl`, `endpoint` | Unsupported authentication, absent ACL and invalid endpoint admit no consumer request; an explicit probe still progresses |
| `groups` | An explicit test group key and captured principal permit actual SDK AddGroup execution; native group membership and one command-specific data response are required |
| `startup-reopen` | Separate write/read child processes preserve StartUpOnOff value 2 through SDK shutdown, store reopen and fresh endpoint initialization |

All 26 families pass in ordinary and ASan/UBSan builds: 52 receiver-case
executions. The fixture requires its own exact success marker and actual exit 0;
the owning runner rejects other markers, missing receipts, noise and failed exits.
The production command renderer remains an explicit port; the fixture's status
renderer and Groups case do not supply a complete production command set.

All 33 existing process families also pass in both builds: 66 executions,
including the intentional failed-cleanup exit 70. Seventeen SDK server regressions
pass in both builds: `endpoints_seed`, `endpoints_reopen`, `requests`,
`requests_invalidated`, `replies`, `provider`, `writes`, `guard`, `wait`,
`wait_input_eof`, `wait_input_malformed`, `wait_input_partial`, `wait_input_cancel`,
`wait_clock_probes`, `wait_output_close`, `wait_output_cancel` and
`wait_output_lost`. The paired codec and legacy SDK bootstrap `normal`/`reopen`
also pass in both builds. These are 40 additional regression executions and
158 total native case executions, counting a fresh-process pair as one family.

## Exact inputs and artifacts

The [source manifest](../../../../packages/wotex-matter/test/support/software/sources.json)
and software profile retain SDK revision
`250a9e6c50ee2068107f3c4808b680f5f2925415`, archive SHA-256
`83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628`
and generated model SHA-256
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.
Both network-disabled Linux AMD64 containers mount current first-party source
read-only over the prepared SDK checkout. Affected targets rebuild against the
cached pinned dependencies; this is not a fresh complete native/software build.

The prepared toolchain image has SHA-256
`c7a0bf7283aa81f21d4fd653805548f625ccb361bfe95af6db9d146449075baa`,
with Debian GCC 12.2.0 and Ninja 1.11.1. Its pinned base/tooling provenance is in
the [SDK process-driver record](bridge-sdk-process-2026-10.md).
ASan/UBSan halt on error, with Linux leak detection enabled. No sanitizer fault
is reported. Intentional fatal exits establish no leak finalization or successful
cleanup. The fresh-process persistence children use `_Exit` after normal driver
cleanup; they exercise sanitizer instrumentation but do not run exit-time leak
finalization.

`SoftwareManifest.identity/1` records 300 package input members. The canonical
source SHA-256 is
`9215667e0e6a118417dc46a9b72a3cbfc0c7353f554df6c0bea034f1d6df651b`.
Every member in all four receiver/process qualification snapshots matches the
committed package bytes.

| Artifact | Ordinary SHA-256 | ASan/UBSan SHA-256 |
| --- | --- | --- |
| SDK bootstrap/receiver fixture | `8da57a405672ea0a3c4cc40350a93cdcbbe845f97da32a8a3fcd858948fab5f4` | `19ad066be5f0c8222e747a28c8481c8ea6e2948e7883c4f9e4b8443696419b9a` |
| SDK server regression fixture | `0724c91f3df168764201b36d288f76b345bf809498e65c90217acd50a3d4b4c2` | `3dd9c8ef0357b587e90b89c2724f8bbdefb18ebc8762e44e027aa08f0adf265d` |
| Paired bridge codec fixture | `ee1826a9a0f8d89e2085cf4e6092203e0bcb1717a887584a8785f8a181157736` | `6a3f94fe4fe3f5ab588a6cd2d6737bfb2c94e2f49948c6a538163890db89dd11` |

The exact package archive SHA-256 is
`9f68674150f4d06306dea3d3f2708823d4acc79006970932c8e25551317d3082`.
The archive checker builds once with `WOTEX_PATH_DEPS` unset, validates exact
contents and dependency identity, and compiles the extracted source out of tree.
It includes the four receiver source/test files and excludes repository guidance,
documentation and local state. This proves package contents/compilation, not an
independent authenticated bridge consumer. Disposable archive trees are removed.

## Commands and qualification limits

Commands run from the repository root; native paths below are normalized to the
explicit disposable workspace. `${build}` selects ordinary or sanitizer graphs,
`${receiver_mode}` and `${process_mode}` range over the owning runner's declared
cases, and `${mode}` ranges over the seventeen server regressions above. SDK
wrappers capture actual exit status and use the owning marker verifiers.

```text
ninja --quiet -C /work/${build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test receiver-${receiver_mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test process-${process_mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test ${explicit_store} ${mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test /work/${build}/codec-results.ndjson /work/${build}/codec-arguments.ndjson /work/${build}/codec-probes.ndjson
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test normal
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test reopen
mix native.lint --package wotex-matter --base 583eb1b8 --fix
MIX_ENV=test mix pkg wotex-matter test test/wotex/matter/software_build_test.exs
mix check.fast --package wotex-matter
MIX_ENV=test mix pkg wotex-matter run --no-start bin/check_archive.exs
mix affected --base 583eb1b8 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The focused runner suite passes 27 tests. The package fast gate passes 383
tests/properties/doctests with 37 explicit-lane exclusions, formatting and Credo.
Only Matter is affected against `583eb1b8`. Catalogue tests pass six cases,
generated metadata is current, Markdown links resolve and ExDoc generation
passes. Native compilation uses warnings as errors. Owned SDK containers are
removed after qualification; prepared dependency/build caches are retained for
the continuing implementation programme.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh complete native/software builds,
interop/hardware lanes and benchmarks remain unrun under the focused workflow.
Production executable assembly, the complete native command renderer,
authenticated transport/process/probe admission, actual clock-rate qualification
and independent controller/reporting peers remain open. These direct fixtures
establish no transport authentication, consumer authorization, complete Matter
conformance, certification, physical effect or containment guarantee.
