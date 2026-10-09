# Exposed bridge software profile

Version: 1.6.0. Finite WMA.09 implementation target. The
[catalogue](../specs/catalogue.yaml) records implementation separately.
Model generation, native storage, internal SDK server lifecycle and dynamic
endpoint bindings are implemented. Consumer request dispatch remains open.

## Source and generated data

`connectedhomeip` v1.6.0.0, commit
`250a9e6c50ee2068107f3c4808b680f5f2925415`, is the source baseline. The
[source manifest](../../../../packages/wotex-matter/test/support/software/sources.json)
pins the SDK archive, dependencies, GN and ZAP packages. The
[bridge model profile](../../../../packages/wotex-matter/test/support/software/bridge-model.json)
pins the selected Matter 1.6 XML and upstream ZAP inputs, the derived model,
all seven generated C++/IDL artifacts, build options, test-attestation inputs
and independent `chip-tool` peer sources.

The [model fixture](../../../../packages/wotex-matter/test/support/software/bridge-model-zap.json)
derives from the SDK's Apache-2.0 bridge, lighting and all-clusters ZAP
examples. Its attribution is in the package `NOTICE`. The CSA specification
XML is reviewed by digest; its contents are not redistributed in the fixture.
The SDK's example attribute defaults are not authoritative for the selected
Matter 1.6 revision. In particular, the model selects On/Off revision 6 and
Temperature Measurement revision 6.

Endpoint 0 is Root Node `0x0016` r4, with Descriptor, Access Control, Basic
Information, General Commissioning, Network Commissioning, General Diagnostics,
Administrator Commissioning, Operational Credentials and Group Key Management.
The Linux profile uses an externally configured Ethernet/IP network; it
enables neither BLE nor Thread. Endpoint 1 is Aggregator `0x000E` r2, with
Descriptor. Endpoint 2 contains disabled generation-only dummy data.
Bridged endpoints begin at 3, admit at most 16 live identities and cannot
reuse a removed ID; exhaustion at 65534 is terminal for further allocation.

Each live child declares Bridged Node `0x0013` r3 and its actual functional
Device Type. A child does not acquire Matter certification by being bridged.
The internal endpoint binding registers the SDK's independent Bridged Device
Basic Information server for each child. Its stable opaque UniqueID derives
from the immutable bridge identity and Thing identity. A restored consumer
configuration supplies the label and temperature bounds explicitly; the store
persists endpoint and Device Type custody, not that semantic configuration.

## Finite interaction set

| Device | Cluster and revision | Required profile behavior |
| --- | --- | --- |
| Every child | Descriptor `0x001D` r3; Bridged Device Basic Information `0x0039` r6 | Device/parts lists, stable identity and approved reachable observations; child reachability is independent of bridge reachability. |
| On/Off Light `0x0100` r3 | Identify `0x0003` r6; Groups `0x0004` r4; On/Off `0x0006` r6 with Lighting; Scenes Management `0x0062` r1 | Identify and TriggerEffect; finite fabric-scoped group and scene operations including CopyScene; Off, On, Toggle, OffWithEffect, OnWithRecallGlobalScene and OnWithTimedOff; mandatory lighting attributes and permitted writes. |
| Temperature Sensor `0x0302` r3 | Identify `0x0003` r6; Temperature Measurement `0x0402` r6 | Identify; read/report MeasuredValue with explicit unavailable/null handling and declared bounds. |

IdentifyTime and the Lighting feature's OnTime, OffWaitTime and StartUpOnOff
writes pass the same fabric ACL and consumer authorization boundary as commands.
Group and scene changes must retain fabric identity and bounded durable custody;
recall must not bypass consumer authorization or infer a physical effect.
Group names, Scene Names, Level Control, binding, OTA, fabric synchronization,
power-source information and additional Device Types are outside this profile.
Generated union bindings can contain a command needed by one Device Type;
each live endpoint must expose only its own admitted command list.

The endpoint binding fixes temperature capabilities for each registered
lifetime and reads approved measurements without persisting them. An absent
bound is unknown, and an absent measurement is unavailable/null. The pinned
SDK's modern Temperature Measurement implementation declares revision 4;
the binding wraps its read surface for the selected revision 6 while retaining
the SDK's cluster ownership and cleanup. The owner exposes no capability-range
mutation. Dynamic metadata enumerates the selected mandatory commands; their
authenticated consumer execution remains a separate delivery obligation.

## Native ownership and limits

The selected normal and ASan/UBSan builds use the profile's exact GN options
and an independent server process/store identity. Five fabrics and fifteen
subscriptions are bounded, with three subscriptions per fabric. At most
sixteen consumer requests and sixty-four approved observations may be pending.
An inbound request carries the SDK-authenticated principal/fabric, exact
endpoint/cluster/operation, request identity and one absolute deadline.
Consumer handoff expires after 500 ms. Queue admission does not justify a
successful command status; denial, timeout and unknown outcome remain explicit.
Approved logical state and physical-effect truth remain distinct.

The internal handoff owner accepts an explicit 16-byte process generation and
uses non-reused 64-bit request IDs. Its serialized native caller supplies time
from one monotonic clock; the handoff refuses regression and deadline extension.
Sixteen slots include staged and expired results until their native contexts
are consumed. A result delivered at the original deadline becomes a timeout,
even if received earlier. Closure discards staged results, refuses new requests
and preserves context credit until consumed. The server binding borrows this
owner and terminates before SDK cleanup if any context remains unconsumed.
The separate SDK request owner copies principal, path and operation metadata
before the callback's borrowed values expire. Invoke contexts retain an actual
SDK command handle and an owned anonymous-root TLV Structure, bounded to 65536
encoded bytes, 24 container levels and 4096 nodes including the root. Excessive
or malformed payloads acquire no handoff slot or SDK handle. A completed result
requires an explicit command-specific renderer; refusal and expiry produce
their corresponding failure status. Encoding failure releases the consumed
handle. Invalidated handles receive no response. Closure discards staged
completion and drains retained handles under the SDK stack lock before the
event loop stops; destruction with a retained handle terminates the process.
The scoped reply adapter copies the captured principal/timed context and up
to eight distinct permitted response IDs. It writes one reply for the original
request path, reports a missing reply or encoding failure and preserves that
failure when the SDK-defined fallback status is written. It never queries the
original asynchronous handler's session or exchange. Retaining a child handle
from the scoped adapter terminates the process before it can escape rendering.
These internal owners have no consumer Port, SDK-provider interception or
consumer policy/dispatch integration. Capturing synthetic principal values
does not establish authenticated admission.

Production attestation and commissioning material are consumer-owned, with no
absent-provider or example-credential fallback. An explicitly separate test
build uses the pinned SDK example provider, test VID `0xFFF1`/PID `0x8001`
and isolated, generated onboarding material. This model fixture contains
credential source digests only. It includes no attestation private-key bytes
or production credential claim. The selected peer is the pinned SDK's
`examples/chip-tool:chip-tool`, independently built from the server.
Model generation does not build either executable. The native build separately
builds the internal server lifecycle test in both modes; the independent peer
has not been executed against a first-party bridge.

## Executed model evidence and reproduction

Host source baseline: `626beb834f125d38eacf73b4007e3290e7c91c4a`, package
`packages/wotex-matter`. The pinned SDK archive was verified and extracted into
a disposable workspace. Two independent ZAP runs produced identical model
outputs; two further reproductions in the pinned container image matched all
seven recorded artifact digests. Generation used networking-disabled containers
with SDK/tool inputs mounted read-only. It did not compile or start a server.

From the repository root, with explicit verified SDK/tool directories:

```console
mix pkg wotex-matter wotex.matter.bridge.model --sdk /absolute/sdk --tools /absolute/tools --workspace /absolute/new-output
mix pkg wotex-matter test test/wotex/matter/software_bridge_model_test.exs test/wotex/matter/bridge_endpoint_registry_test.exs
```

The model tests reject missing mandatory commands/attributes, wrong lighting
features/revisions and changed named source inputs before generation. These
checks and artifact digests establish the selected model only. Separate native
tests cover atomic fabric/endpoint persistence, SDK server startup/shutdown,
sixteen dynamic children, approved observations, bounded owned command arguments,
actual SDK handle retention and cleanup with failure exits in both sanitizer
modes. Reply tests execute the pinned SDK's Groups and Scenes handlers with
copied fabric context and explicit synthetic group keys, inspect resulting
fabric-scoped custody and reject foreign paths, response IDs, duplicate replies,
encoding failures and escaped adapter handles. Request-owner tests use synthetic
CASE, group and commissioning principal values and explicit test clocks. Authenticated consumer dispatch,
subscription/report flow, end-to-end handoff timeouts and independent peer workflows
remain required. Passing controller-side WMA.01–WMA.08 evidence does
not satisfy those server obligations. Certification and installed ecosystem
acceptance remain separate.
