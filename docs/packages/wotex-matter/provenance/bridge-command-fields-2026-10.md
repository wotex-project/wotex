# Native command field admission evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `1f5485ef4455e3d1f9aba61234a60a3d0e90097d`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.34.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.33.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.30.0.
The catalogue remains partial.

## Admission requirement and implementation

The installed receiver previously bounded/copied a command's TLV Structure and
checked current SDK metadata/ACL before delivering it to the consumer. It did
not decode the selected command fields before that delivery. The pinned SDK's
generated OnWithTimedOff decoder accepts an empty Structure, leaving its members
at zero defaults. Its list decoder also defers member decoding until iteration.
Neither a valid TLV envelope nor a successful initial decoder call establishes
complete command field validation.

The required `BridgeInvokeGuard::ValidateArguments` phase now follows current
scope capture and bounded argument copying, before request reservation or handler
retention. `SdkBridgeInvokeGuard` implements all 22 selected Identify, Groups,
On/Off and Scenes Management schemas. A separate field scan requires the model's
mandatory fields and refuses duplicate context fields. Unique unknown fields
remain in the owned payload. SDK generated decoders establish field types;
every lazy typed list is traversed, including scene extension fields and nested
attribute/value pairs. Selected group/name, timed-command and scene scalar bounds
and the scene value choice are checked before consumer execution.

Refusal preserves the borrowed reader position, ticket output, request identity
and SDK handler ownership. The guard performs no stateful native operation,
consumer dispatch or authorization. Stateful group/scene availability, complete
command semantics and native command responses remain renderer obligations.
SDK enum fallback behavior is not replaced with an invented enum policy.

The field IDs, conformance and selected scalar constraints are reviewed against
the exact `data_model/1.6/clusters/{Identify,Groups,OnOff,Scenes}.xml` inputs pinned
by the [model manifest](../../../../packages/wotex-matter/test/support/software/bridge-model.json).
Those model inputs and generated bindings are unchanged; no new model digest is
asserted by this field-admission change.

## Executed native proof

The new
[`sdk_bridge_command_arguments_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_command_arguments_test.cpp)
corpus writes independent literal TLV fields rather than using SDK command
encoders or the production validator to generate expected inputs. It checks:

- all 22 admitted command schemas and each of their 35 required fields;
- removal, duplication and incorrect type for each required field;
- acceptance of a unique unknown field and refusal of its duplicate;
- exact preservation of scalar type errors and SDK list schema-mismatch errors;
- group/name and timed-command boundaries, optional null/numeric scene transition
  time, reserved scene IDs and oversized transition/name values;
- malformed group-list tails, missing nested scene fields, invalid scene value
  choices and incorrect nested value types;
- unsupported commands, wrong operation and unchanged caller reader position.

The corpus separately invokes the pinned generated decoder on an empty
OnWithTimedOff Structure and requires its successful zero-default result. The
new guard must refuse the same input. The owning SDK `guard` case requires the
new explicit 22-command/35-field marker as well as the retained metadata,
credential, ACL and retirement markers.

Four additional installed-provider/real-pipe receiver families pass in both
ordinary and ASan/UBSan builds:

| Mode | Required observation |
| --- | --- |
| `invoke-fields` | Missing OnWithTimedOff fields return InvalidCommand before request or handle admission |
| `invoke-list` | An invalid member after a valid GroupList member is refused before consumer delivery |
| `invoke-duplicate` | Duplicate AddGroup fields admit no request or handle |
| `invoke-recover` | A valid On command after refusal receives request ID 1; its unknown field remains exactly `1524fa2a18` in the copied TLV payload |

The refusal families require empty handoff custody and unchanged borrowed reader
position. The consumer receives only its later explicit clock sample, rather
than a command request. The generic retained-owner fixture additionally injects
an argument-guard type error and requires unchanged ticket output and no retained
handler or request credit.

All 30 receiver families pass in both builds: 60 executions. All 33 existing
process families pass in both builds: 66 executions. Seventeen SDK server
regressions pass in both builds: `guard`, `endpoints_seed`, `endpoints_reopen`,
`requests`, `requests_invalidated`, `replies`, `provider`, `writes`, `wait`,
`wait_input_eof`, `wait_input_malformed`, `wait_input_partial`, `wait_input_cancel`,
`wait_clock_probes`, `wait_output_close`, `wait_output_cancel` and
`wait_output_lost`. The paired codec and legacy bootstrap `normal`/`reopen` also
pass in both builds. This totals 166 native case executions, counting the
fresh-process persistence pair as one family.

## Exact source and artifacts

The [SDK process-driver record](bridge-sdk-process-2026-10.md) and
[receiver record](bridge-sdk-receiver-2026-10.md) own the unchanged dependency,
model and prepared toolchain pins. SDK revision is
`250a9e6c50ee2068107f3c4808b680f5f2925415`; model SHA-256 is
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.
Separate network-disabled Linux AMD64 containers mount current first-party source
read-only over the prepared SDK tree. Affected targets rebuild with Debian GCC
12.2.0/Ninja 1.11.1. Both graphs subsequently report no work pending for those
targets. This is focused qualification against cached pinned dependencies.

`SoftwareManifest.identity/1` records 302 package input members with canonical
source SHA-256
`5d124f38e0715671dadaff8438bb9c8fcba749201a49968d4e0b91b28455c373`.
All four receiver/process qualification source snapshots equal the committed
package identity, including every per-member digest.

| Artifact | Ordinary SHA-256 | ASan/UBSan SHA-256 |
| --- | --- | --- |
| SDK bootstrap/receiver fixture | `e4d15d2e833fbe6a9aa054ab01b22aefadd642a955ba4ae3be2667327b93738c` | `4c22b798e8a625372f5ad05253219cf179c1b78392a3418d2741d14b9d4525ee` |
| SDK server/command-field fixture | `355f46cc86de7d08d6202a5eccf16b7d41271c75fdb43a0ad527a9161f2a0d9a` | `739bb0c357d343baef7fe44a8d8eccf908240a9f599e26c40b095879ca518077` |

The unchanged paired codec binaries retain the exact hashes recorded in the
receiver record and are executed again here. ASan/UBSan halt on error; Linux
leak detection is enabled and no sanitizer fault is reported. Intentional fatal
cleanup exits and the persistence fixture's `_Exit` children establish no
exit-time leak finalization.

The exact archive SHA-256 is
`f05dfa2172945efaab07ee067c8138978b625aebc206a01b6ab9d9853f471855`.
The checker builds once with `WOTEX_PATH_DEPS` unset, validates exact contents
and dependency identity, then compiles the extracted source out of tree. Both
new command-field fixture files are present; repository guidance, documentation
and local state are excluded. Disposable archive trees are removed. This is
package/compilation evidence, not independent authenticated bridge adoption.

## Commands and limits

Commands run from the repository root. Native workspace paths below are
normalized; `${build}` selects ordinary or sanitizer graphs. The owning
`SoftwareBridgeBuild` wrappers capture actual exits and verify markers.

```text
ninja --quiet -C /work/${build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-server-test ${explicit_store} ${mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test receiver-${receiver_mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test process-${process_mode}
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-bridge-codec-test /work/${build}/codec-results.ndjson /work/${build}/codec-arguments.ndjson /work/${build}/codec-probes.ndjson
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test normal
timeout 20 /work/${build}/obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test reopen
mix native.lint --package wotex-matter --base 1ceea459 --fix
MIX_ENV=test mix pkg wotex-matter test test/wotex/matter/software_build_test.exs
mix check.fast --package wotex-matter
MIX_ENV=test mix pkg wotex-matter run --no-start bin/check_archive.exs
mix affected --base 1ceea459 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The focused runner suite passes 27 tests. The package fast gate passes 383
tests/properties/doctests with 37 explicit-lane exclusions, formatting and Credo.
Only Matter is affected against `1ceea459`. Catalogue tests pass six cases,
generated metadata is current, Markdown links resolve and ExDoc generation
passes. Owned test containers are removed after qualification; prepared caches
are retained for the continuing implementation programme.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh complete native/software builds,
interop/hardware lanes and benchmarks remain unrun under the focused workflow.
The complete native command renderer, production executable, authenticated
transport/process/probe admission, actual clock-rate qualification and independent
controller/reporting peers remain open. Direct synthetic-principal fixtures
establish no transport authentication, consumer authorization, complete Matter
conformance, certification, physical effect or containment guarantee.
