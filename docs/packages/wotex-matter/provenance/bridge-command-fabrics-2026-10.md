# Authenticated command and fabric evidence

Recorded: 2026-10-21. Package: `packages/wotex-matter`.
Source commit: `be0fbb04bd3d8031d6cd65bc290ea4b2015f11cc`.
Owners: [WMA.09](../specs/WMA.09-exposed-bridge-server.md) version
0.38.0-target, [delivery plan](../plans/exposed-bridge-delivery.md) version
1.37.0 and [software profile](../plans/exposed-bridge-profile.md) version 1.34.0.
WMA.09 remains partial.

## Executed boundary

The [command interop file](../../../../packages/wotex-matter/test/interop/exposed_bridge_commands_test.exs)
adds two live families to the four in the
[consumer interop file](../../../../packages/wotex-matter/test/interop/exposed_bridge_test.exs).
Both complete six-case filesets pass against ordinary and ASan/UBSan production
bridge/controller artifacts: twelve successful family executions, with zero
failures, skips or exclusions. The selected SDK controller is independently
built from the same SDK source; this is shared-SDK software evidence.

The explicit consumer uses required CASE policy, public ExposedThing handlers
and the production connection/receiver/renderer. Its protocol-bookkeeping
Action acknowledges the selected native command without publishing a physical
observation. The existing On/Off Action separately publishes approved state and
waits for its applied receipt. Each command checks captured subject, fabric,
bridge node, opaque Thing, exact path, bounded copied TLV and the same Runtime
Context at policy and handler delivery.

The command family exercises all twenty-two selected paths: Identify (2), Groups
(6), On/Off (6) and Scenes Management (8). It checks native data-response status,
selected response fields, two-member and empty group lists, scene membership,
copy readback and removal. StoreScene captures approved false after native
lighting controls. RecallScene completes through the protocol Action without a
consumer observation. The final public OnOff read returns the consumer's applied
false, with zero pending requests/observations and no active clock probe.

AddGroup before key provisioning retains native UnsupportedAccess (126).
Explicit root Group Key Management writes install the key set and map; the same
AddGroup then succeeds. No fixture directly inserts group data into the server.
This is protocol setup and refusal evidence, rather than a renderer defect.

The fabric family commissions two independent controller stores through an
enhanced window, verifies distinct fabric indices, roots and NOC digests, and
uses the same group/scene IDs with different scene values. A controller cannot
view another fabric's entries. Removing all groups from one fabric removes its
scenes; re-adding the group still returns NotFound for the old scene. The other
fabric retains its scene. Consumer denial blocks only the selected fabric's
handler and preserves its group after permission is restored. Authenticated root
RemoveFabric returns Success; a subsequent removed-controller request fails
without consumer delivery, while the surviving controller still reads its group.
The removed-controller probe uses a two-second SDK command timeout under the
fixture's existing twenty-second process bound.

The four renewed families retain the scope in the
[consumer record](bridge-consumer-2026-10.md): light/sensor reads and approved
subscription changes, consumer/SDK denial, expiry and worker retirement, stable
stored identity with mismatched/missing controller-key refusal, all four finite
writes, and killed native mutation with unknown effect.

## Exact source and artifacts

Both completed receipts match all 314 inputs in the committed
`SoftwareManifest.identity/1`, including the owning tests, helper, inventory and
archive checker. Each member was compared with its committed bytes. Canonical
source SHA-256: `35f3fbd4e984913e16931df4d4eabf22504ad4a6b2e61fe8f9d3909f645e67d9`.
Package lock SHA-256:
`50786439517ca8e894d21db0aa3156f9bab7e94189127fd4ecd1485bf693f1a4`.
Exact archive SHA-256:
`7056db68a8d5eeb04de87e057f1d8265a01f8b8072ec9af021a4ef80244947dc`.
The archive checker unsets `WOTEX_PATH_DEPS` for the build, verifies contents and
dependency identity, and compiles extracted source out of tree. The new test is
included; documentation, contributor instructions and binaries are excluded.
This establishes contents/compilation, not native archive adoption.

| Artifact | Ordinary SHA-256 | ASan/UBSan SHA-256 |
| --- | --- | --- |
| Production bridge | `8b6e04d1c6e88919689fb00e78398cbfb43e1089b7dfeccae0de4442231fd571` | `7fed6f9fdb31e6c6846e97a6d8fefbf5f3d7bed514b4fb3c19a7be602a8d8769` |
| First-party controller | `790ebe0f3d103e822fa89ec9788794379c83e7ef8a0d6f57caab2174776eb343` | `baf607d5b399d7ba437dbad596198419ea04bcfd6f43fd943997487ecccff8bb` |
| Guarded material/refusal fixture | `fe0b9146c3e9e0266a926e3d800cf79941f3cfa4b73b70e49d5d300c513a1e38` | `036f319e292b4c5b9e130c24d18a42b933c572448729035732fcfdef11d16443` |

The SDK controller peer is the same ordinary binary in both cohorts:
`9a5b594484675c9c2e7fb61a00d57ffa29b367beb8c69546c524715b8f4ff05d`. These cached native artifacts retain the identities recorded
by the prior [production](bridge-host-2026-10.md) and
[consumer](bridge-consumer-2026-10.md) builds; no C++ source changes or fresh SDK
builds occur in this slice. SDK revision:
`250a9e6c50ee2068107f3c4808b680f5f2925415`; SDK archive SHA-256:
`83032f0c98b02c8c16defc6e70ebe288c127ef3661153feca32839fb65b33628`;
model SHA-256:
`dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671`.

The cohort uses Linux ARM64 Elixir 1.20.2/OTP 29.0.4 and Linux AMD64 SDK binaries
through local x86 emulation, in one isolated container/kernel and internal
network. Runtime image ID:
`sha256:8765b0b7d927693e19f23d2304a49fe68a408ca1ce8dbc64d0577a9fe1f92b4d`.
The explicit OS CLOCK_MONOTONIC qualification is unchanged from the consumer
record; ERTS time correction remains enabled. This proves no ARM64 SDK build,
physical timing or other deployment/clock cohort.

## Validation and limits

From the repository root:

```text
mix pkg wotex-matter test test/wotex/matter/software_acceptance_test.exs test/wotex/matter/software_build_test.exs test/wotex/matter/software_run_test.exs
mix check.fast --package wotex-matter
mix pkg wotex-matter run bin/check_archive.exs
mix affected --base 7ed75561 --detail
mix test test/wotex/workspace/catalogue_test.exs
mix wotex.catalogue
mix docs.check
mix docs.pkg wotex-matter
```

The focused Linux runner uses `mix run --no-deps-check --no-start`, starts
telemetry and ExUnit explicitly with seed 19/max_cases 1, supplies the fixture,
requires both interop files and requires exactly six passes with no exclusions.
It snapshots source/artifact identities and checks unchanged source at completion.
The final ordinary and sanitizer runs take 45.9 and 50.9 seconds respectively.
No aggregate software-lane receipt is created.

The focused tooling suites pass 39 tests. The fast gate passes 385 checks
(3 doctests, 4 properties, 378 tests), with 43 explicit-lane exclusions;
compilation, formatting, strict Credo and native formatting pass. Catalogue
checks pass six tests; generated metadata, Markdown links and ExDoc pass.
The software inventory contains forty-two cases. Full current/minimum software
lanes and historical aggregate receipts are not renewed.

Test stores/private material are removed by case teardown. Before container
removal there are no live native/BEAM peers; the sleep parent retains terminated
ERTS helper entries. Removing the owned container destroys that namespace, and
the owned network is removed. Public pinned PAA input and build/dependency
caches remain.

Full `mix check`, Dialyzer, SDK clang-tidy, fresh full native/software builds,
hardware/installed lanes and benchmarks remain unrun. Wider authenticated
conflict/report/recovery matrices, independent ecosystems, native archive
adoption and installed-host/platform qualification remain open. These tests
supply no physical-effect, certification or complete WMA.09 conformance claim.
