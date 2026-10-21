# Finite native command rendering evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `b63812e1de54d7c13391e10d0d4feceaf3ba882b`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.35.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.34.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.31.0.
The catalogue remains partial.

## Renderer and state ownership

The internal `SdkBridgeCommandRenderer` explicitly attaches to the initialized
endpoint owner. It renders only completed, currently guarded invocations using
the captured principal/timed context. Each admitted command has its individual
permitted response ID, or status-only response. The renderer invokes the native
delegate rather than the installed consumer provider, so rendering does not
create another consumer request. Missing replies, SDK errors and failed data
encoding remain observable. Construction performs no SDK/file/thread work;
attachment retires after receiver completion work drains.

Every child now owns registered Identify with logical IdentifyType None;
TriggerEffect is exposed only on lights. Groups is explicitly joined to that
child's Identify and Scenes instances. This supplies conditional group addition
and scene cleanup without depending on generated legacy Identify lookup or
cluster initialization order.

`SdkBridgeLightCluster` retains the SDK lighting state machine for controls,
effects and timers, with a separate scene handler per light. Its public OnOff
read and scene snapshot use only the approved observation reference. SDK
command/timer OnOff writes are filtered out of persistence. Approved changes
synchronize native bookkeeping, advance the registered cluster's data version
and invalidate stale scene validity. Missing observations remain unavailable.
StartUpOnOff configuration persists before publication and restores under the
existing strict byte validation; the SDK helper that updates its value before
storage is not used for that write.

Physical effects, delayed behavior and scene transitions remain consumer
execution responsibilities. Native control/timer state is protocol bookkeeping,
not physical truth. Endpoint retirement cancels Identify timers explicitly,
unregisters per-child scene handlers, and destroys SDK lighting/scene timers
before releasing borrowed observations and storage. Generated registrations
temporarily replaced by the explicit Groups owner are restored for SDK shutdown.

## Executed command corpus

The guarded
[`sdk_bridge_commands_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_commands_test.cpp)
fixture starts the real configured SDK process driver, installed provider,
consumer receiver and concrete renderer. Independent literal command fields
travel through actual private pipes. Consumer completion precedes native
execution; retained handlers provide real encoded SDK status/data responses.
The fixture rejects asynchronous queries of the original handler's metadata or
exchange. Its fixed success marker and actual exit 0 are separately verified.

The main sequence executes all 22 selected light command paths plus sensor
Identify. Its 25 requests include additional scene View/Membership checks.
Literal response fields require Add/View/Get/Remove/RemoveAll/conditional Groups;
Add/View/Store/Recall/Membership/Copy/Remove/RemoveAll Scenes; Identify and
TriggerEffect; and all six lighting commands. The corpus checks actual lighting
intent separately from unchanged approved OnOff, GlobalSceneControl changes,
Identify values, timed control values and final group removal. A renderer that
only returns Success cannot satisfy these assertions.

| Family | Required executed result |
| --- | --- |
| `all` | All selected command paths, exact response IDs, literal response fields, native control state and approved false scene snapshots |
| `denied` | UnsupportedAccess with no native group mutation |
| `timeout` | Original 500 ms expiry without a result; no native group mutation |
| `revoked` | Actual ACL deletion after request delivery prevents rendering, drains the handle and closes without a successful closed receipt |
| `encoding` | AddGroup commits native group membership, then one injected data-encoding failure produces Failure and closes the generation; no retry or rollback is inferred |
| `reopen` | Separate seed/restore SDK processes preserve the fabric, ACL, group and scene; fresh OnOff remains unavailable until an explicit observation |
| `timers` | Lighting countdowns expire and a delayed scene callback runs while public OnOff stays at approved false and no inferred OnOff key is persisted |
| `remove` | Active light/scene and sensor Identify timers retire; endpoint IDs 3/4 are removed, replacement ID 5 is not an alias, and no old callback survives the later wait |
| `observations` | An explicit applied observation changes public OnOff to true and invalidates the previous scene validity; no observation value is persisted as inferred command state |
| `unavailable` | Scene Store returns Failure rather than snapshotting the SDK lighting default when no OnOff observation exists |
| `multi` | Two simultaneous lights retain opposite approved values and independent scene snapshots/handlers; recall changes no canonical observation |

All eleven families pass in ordinary and ASan/UBSan builds: 22 command-family
executions. Each family counts once, including the fresh-process seed/restore
pair. The corpus uses direct synthetic unicast CASE principals, generated test
fabric certificates and explicit test group keys. It supplies no encrypted,
group or timed exchange qualification, consumer authorization or physical result.

All 30 receiver families and all 33 process families also pass in both builds:
60 and 66 executions. Seventeen SDK server regressions pass in both builds:
`guard`, `endpoints_seed`, `endpoints_reopen`, `requests`, `requests_invalidated`,
`replies`, `provider`, `writes`, `wait`, `wait_input_eof`, `wait_input_malformed`,
`wait_input_partial`, `wait_input_cancel`, `wait_clock_probes`, `wait_output_close`,
`wait_output_cancel` and `wait_output_lost`. The paired codec and legacy SDK
bootstrap `normal`/`reopen` pass in both builds too. These are 40 further
regression executions, for 188 native case-family executions in total.

## Exact inputs and artifacts

The [source manifest](../../../../packages/wotex-matter/test/support/software/sources.json),
software profile and [SDK process-driver record](bridge-sdk-process-2026-10.md)
retain the dependency/toolchain pins: SDK revision
`250a9e6c50ee2068107f3c4808b680f5f2925415`, archive SHA-256
`83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628`
and generated model SHA-256
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.
No generated model input or digest changes here.

Separate network-disabled Linux AMD64 containers mount current first-party source
read-only over the prepared SDK tree. Affected targets and the selected SDK
modern lighting dependency build with Debian GCC 12.2.0/Ninja 1.11.1. Both graphs
subsequently report no work pending. This is focused qualification using cached
pinned dependencies, not a fresh complete native/software build.

`SoftwareManifest.identity/1` records 308 package input members with canonical
source SHA-256
`d2490a70194aa5608860d49e7985975d3d9e9a529581d00044e3a654a1b38661`.
All six command/receiver/process source snapshots equal the committed package
identity, including every per-member digest.

| Artifact | Ordinary SHA-256 | ASan/UBSan SHA-256 |
| --- | --- | --- |
| SDK bootstrap/command fixture | `3ac43eeeee42c373eb641ec6760a2ec05a24006ed63a32eaf0ebec79855d3780` | `8f8878931fbd6bf411fba4df82995fb52e3cfb6f670be164f4d047bbe11d482e` |
| SDK server regression fixture | `aa1bff7aec26e443675115c272b0fdeabf2e83eec4fe379bbc9804f781d28808` | `53fc88147aec67621fcc37bee03c00842597b697ca2f1af9dbf6ef043899a4fb` |

The unchanged codec hashes remain those in the
[receiver record](bridge-sdk-receiver-2026-10.md); both binaries are executed
again here. ASan/UBSan halt on error with Linux leak detection enabled. No
sanitizer fault is reported. Intentional failed-cleanup exit 70 and fresh-process
persistence children using `_Exit` establish no exit-time leak finalization.

The exact archive SHA-256 is
`8ec96062712c47e7aad577ce6c43a70a689341000f1fa7f86566d6dd3c0a1f66`.
The checker builds once with `WOTEX_PATH_DEPS` unset, verifies exact contents and
dependency identity, and compiles extracted source out of tree. All six new
renderer/light/fixture files are present; repository instructions, documentation
and local state are excluded. Disposable archive trees are removed. This is
archive contents/compilation proof, not an independent native bridge consumer.

## Commands and limits

Commands run from the repository root. Native paths below are normalized to the
explicit disposable workspace; `${build}` selects ordinary or sanitizer graphs.
The owning `SoftwareBridgeBuild` wrappers capture actual exits and verify markers.

```text
ninja --quiet -C /work/${build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test commands-${command_mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test receiver-${receiver_mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test process-${process_mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test ${explicit_store} ${mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test /work/${build}/codec-results.ndjson /work/${build}/codec-arguments.ndjson /work/${build}/codec-probes.ndjson
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test normal
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test reopen
mix native.lint --package wotex-matter --base 42cdd057 --fix
MIX_ENV=test mix pkg wotex-matter test test/wotex/matter/software_build_test.exs
mix check.fast --package wotex-matter
MIX_ENV=test mix pkg wotex-matter run --no-start bin/check_archive.exs
mix affected --base 42cdd057 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The focused runner suite passes 28 tests. The package fast gate passes 384
tests/properties/doctests with 37 explicit-lane exclusions, formatting and Credo.
Only Matter is affected against `42cdd057`. Catalogue tests pass six cases,
generated metadata is current, Markdown links resolve and ExDoc generation
passes. Owned SDK test containers are removed after qualification; prepared
dependency/build caches are retained for the continuing programme.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh complete native/software builds,
interop/hardware lanes and benchmarks remain unrun under the focused workflow.
Production executable assembly, authenticated transport/process/probe admission,
actual clock-rate qualification and independent controller/reporting peers remain
open. These direct fixtures establish no transport authentication, consumer
authority, complete WMA.09/Matter conformance, certification, physical effect or
containment guarantee.
