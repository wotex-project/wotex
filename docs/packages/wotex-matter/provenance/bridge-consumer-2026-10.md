# Authenticated bridge consumer evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `27f9b7a1b8f6c48f1784ead4c99830ad5f0c2fbb`, including the live
consumer delivery in `6002e84cbb7cb2e0ce3107af53dd92e64d044336`.
Owners: [WMA.08](../specs/WMA.08-native-backend.md) version 1.0.11,
[WMA.09](../specs/WMA.09-exposed-bridge-server.md) version 0.37.0-target,
[delivery plan](../plans/exposed-bridge-delivery.md) version 1.36.0 and
[software profile](../plans/exposed-bridge-profile.md) version 1.33.0.
WMA.09 remains partial.

## Live boundary and signing-key correction

The production bridge executable runs under the public BEAM connection, with
an explicitly owned consumer GenServer, required CASE policy and public
ExposedThing handlers. Controller requests traverse actual PASE commissioning,
CASE sessions, SDK metadata/ACL checks, scoped pipes, consumer policy and public
dispatch. No synthetic callback principal or alternate production receiver is
installed. The guarded bootstrap executable only writes explicit private
development material or mutates a closed test controller store for refusal probes.

The restart case exposed a controller defect: an injected operational keypair
was retained in FabricInfo memory, while its NOC survived restart. A fresh CASE
session could therefore fail when the controller needed its signing key.
Creation now allocates the key through the SDK FabricTable/operational-keystore
CSR path, verifies the CSR and issues the NOC for that public key. Commissioner
setup commits the key and certificate together; failed setup reverts pending
fabric data. Reopen requires a stored key and verifies a fresh local signature
against the NOC public key before readiness. The SDK presence check alone only
reads stored bytes; it does not validate this relationship. Tests replace the
stored key with another valid key, then remove it, and require both starts to
refuse without regeneration or a leaked store lock.

## Executed cases

The owning [interop file](../../../../packages/wotex-matter/test/interop/exposed_bridge_test.exs)
and [explicit consumer fixture](../../../../packages/wotex-matter/test/support/software/exposed_bridge.exs)
run four case families in ordinary and ASan/UBSan modes: eight successful family
executions, with no skipped or excluded cases in either focused run.

1. Actual commissioning and CASE light/sensor reads retain the captured subject,
   fabric, NOC digest, root public key, opaque Thing and exact path in policy and
   Runtime Context. Read and On/Off command results wait for applied observation
   receipts. Native subscription reports contain the approved true/false values.
   Consumer denial reaches policy without invoking a handler. Revoking SDK ACL
   access prevents consumer delivery. An expired read kills its worker without
   approving state, and the next read succeeds with zero pending custody.
2. Fresh native/controller processes reopen their stores, retain the authenticated
   fabric/NOC/root and endpoint identities, and accept newly approved state under
   a different process generation. Replacing or removing the controller signing
   key refuses startup before readiness.
3. A separately built pinned SDK `chip-tool` commissions the bridge and writes
   IdentifyTime, OnTime, OffWaitTime and StartUpOnOff. Policy/handler assertions
   require the exact copied scalar or nullable-enum payload. SDK readback observes
   StartUpOnOff 2; consumer denial of a later write preserves that value. The
   existing first-party controller explicitly refuses its unsupported OnTime
   schema before network dispatch; its finite descriptor profile is unchanged.
4. Killing the native process during an authenticated mutation closes the bridge
   generation, retires its consumer worker and reaps the native child. Both
   channel loss and the pending controller mutation retain unknown effect. No
   approved-observation receipt or physical-effect claim is produced.

The independently built program uses the same connectedhomeip SDK revision.
These are shared-SDK software results, not independent-stack or ecosystem proof.

## Clock and execution cohort

The fixture samples the documented ERTS OS monotonic-time value, rather than
frequency-corrected Erlang monotonic time. Each call checks `clock_gettime`,
`CLOCK_MONOTONIC`, an unextended nonnegative sample and used resolution
1000000000, then converts its native unit to whole milliseconds. The selected
native child directly calls the same Linux clock in the inherited time namespace.
Their relative rate is therefore one; the existing projection subtracts its
millisecond quantization allowances. This conclusion uses clock-source identity,
not an elapsed-time experiment or matching units alone. The documented OS sample
and corrected-clock distinction are described by
[ERTS system information](https://www.erlang.org/doc/apps/erts/erlang.html#system_info/1)
and [time correction](https://www.erlang.org/doc/apps/erts/time_correction.html).
Observed ERTS time correction remains enabled. Other clock/runtime/namespace
combinations require separate qualification.

The runtime is Linux ARM64, Elixir 1.20.2/OTP 29.0.4; SDK executables are Linux
AMD64 and execute through the local platform's x86 emulation. They share one
isolated container/kernel and internal Docker network. Required AMD64 dynamic
libraries are copied from the selected SDK-tools image into the disposable
runtime container. This establishes neither an ARM64 SDK build nor native
hardware timing. Runtime image ID:
`sha256:8765b0b7d927693e19f23d2304a49fe68a408ca1ce8dbc64d0577a9fe1f92b4d`.
SDK-tools image ID:
`sha256:c7a0bf7283aa81f21d4fd653805548f625ccb361bfe95af6db9d146449075baa`.
GCC 12.2.0/Ninja 1.11.1 build the ordinary/sanitizer controller, flow and resource
targets and guarded material fixtures. `chip-tool` disables interactive mode
and Perfetto diagnostics, avoiding unrelated optional dependencies. Its source
and existing JSON dependency retain their selected pins. No upstream source is
changed for this peer. Production bridge binaries retain the hashes in the
[executable record](bridge-host-2026-10.md).

## Exact identities

SDK revision `250a9e6c50ee2068107f3c4808b680f5f2925415`, SDK archive SHA-256
`83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628`
and model SHA-256
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`
remain unchanged. Both focused snapshots match every member of the committed
package's `SoftwareManifest.identity/1`: 313 inputs and canonical SHA-256
`eb75bc20d73df82f189630043d033a80f4fee04601a3cc0896b114f1985eb08e`.

| Artifact | Ordinary SHA-256 | ASan/UBSan SHA-256 |
| --- | --- | --- |
| First-party controller | `790ebe0f3d103e822fa89ec9788794379c83e7ef8a0d6f57caab2174776eb343` | `baf607d5b399d7ba437dbad596198419ea04bcfd6f43fd943997487ecccff8bb` |
| Guarded material/refusal fixture | `fe0b9146c3e9e0266a926e3d800cf79941f3cfa4b73b70e49d5d300c513a1e38` | `036f319e292b4c5b9e130c24d18a42b933c572448729035732fcfdef11d16443` |

The independent SDK controller SHA-256 is
`9a5b594484675c9c2e7fb61a00d57ffa29b367beb8c69546c524715b8f4ff05d`.
It is the same peer binary in both modes. The first-party controller and bridge
are sanitizer builds in the sanitizer cohort. No sanitizer fault is reported;
intentional native SIGKILL establishes no exit-time leak finalization.

The exact package archive SHA-256 is
`e7bd5eef677de686f95e282b4a104994d5f315820a297ba23f7b6e1b7d773c5d`.
The checker builds with `WOTEX_PATH_DEPS` unset, verifies exact contents and
dependency identity, then compiles extracted source out of tree. New helper/test
sources are included; instructions, documentation, local state and binaries are
excluded. This proves contents/compilation, not independent archive adoption.

## Commands and limits

Commands run from the repository root. Native paths normalize the explicit
disposable workspace; `${build}` selects ordinary/sanitizer graphs. The focused
Linux runner starts ExUnit without autorun, requires the owning interop file,
sets its explicit fixture path and requires all four tests with zero failures,
skips or exclusions. It records source/binary identities before checking that
source remains unchanged. It does not create an aggregate software-lane receipt.

```text
ninja --quiet -C /work/${build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-host obj/examples/wotex-matter-host/bin/wotex-matter-flow-host obj/examples/wotex-matter-host/bin/wotex-matter-resource-host
ninja --quiet -C /work/${bridge_build} -j4 obj/examples/wotex-matter-host/bin/wotex-matter-sdk-bridge-bootstrap-test
ninja --quiet -C /work/build-process -j4 chip-tool
mix native.lint --package wotex-matter --base 1d0b1141 --fix
mix native.lint --package wotex-matter --base 6002e84c --fix
mix pkg wotex-matter test test/wotex/matter/software_acceptance_test.exs test/wotex/matter/software_build_test.exs test/wotex/matter/software_run_test.exs
mix check.fast --package wotex-matter
mix pkg wotex-matter credo --strict
mix pkg wotex-matter run bin/check_archive.exs
mix affected --base 1d0b1141 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The focused tooling suites pass 39 tests. The fast gate passes 385
tests/properties/doctests with 41 explicit-lane exclusions, formatting and Credo.
After the final native key-validation change, affected native targets and all
eight live executions are renewed; formatting/Credo and archive checks pass.
Six catalogue tests, generated metadata, Markdown links and ExDoc pass. The
software inventory now contains forty cases; complete current/minimum software
lanes are not rerun and their historical receipts are not promoted. The ordinary
suite is not repeated after this final C++/explicit-lane change.

Owned native peers are reaped; both containers contain only their sleep process
before removal. Test credential/authority stores and owned containers/network
are removed. Public pinned PAA input and dependency/build caches remain.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh complete native/software builds,
hardware/installed lanes and benchmarks remain unrun. Wider authenticated command,
fabric and report matrices, independent ecosystems, other deployment/clock
cohorts, containment and exact-archive native adoption remain open. File-digest
admission retains the caller's immutable-artifact precondition; these tests do
not protect against mutation after verification or establish physical effects,
certification or complete WMA.09 conformance.
