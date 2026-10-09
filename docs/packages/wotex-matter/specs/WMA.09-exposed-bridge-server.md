# WMA.09 Exposed Matter bridge/server target

## Status

Version: 0.8.0-target.

Target contract. The package catalogue records implementation status separately.
Existing WMA.01-WMA.08 remain controller-side and MUST NOT be cited as
bridge/server evidence.

## Purpose

Add an explicitly separate Matter server/accessory role capable of exposing consumer-owned Things as Matter endpoints, including bridged non-Matter devices.

## Required boundary

The native connectedhomeip host owns generic:
- Matter server lifecycle;
- fabric/commissioning state;
- bridge root/aggregator semantics;
- endpoint allocation and durable endpoint identity;
- Device Type/cluster declarations;
- inbound attribute reads/writes/commands;
- event/attribute reporting;
- commissioning windows and ACL enforcement;
- restart/recovery.

The consumer owns:
- which Things are exported;
- semantic mapping from consumer domain to Matter Device Types;
- authorization beyond Matter fabric admission;
- physical Action-effect truth;
- safety policy.

## Runtime integration

Inbound Matter requests MUST pass through an authenticated/authorized consumer boundary before ExposedThing dispatch. A successful Matter command is not automatically a physical-effect observation.

Endpoint identity MUST remain stable across host restart and must not silently rebind to another Thing.

The native bridge store MUST have a separate format and immutable consumer-owned
bridge identity, model digest, vendor and product identity. It MUST NOT select a
controller node, generate a controller authority or accept a controller store.
Endpoint allocation and removal MUST commit durably before acknowledgment. A
removed endpoint MUST remain retired across restart; re-adding the same Thing
allocates a new endpoint. An existing live Thing MUST NOT change Device Type
under its current endpoint. The finite profile admits sixteen live endpoints
and allocates IDs 3 through 65534 without wrapping.

SDK fabric values and endpoint custody MUST share the bridge's locked atomic
store. An incomplete commit or incompatible store MUST prevent startup; a
failed durable write MUST terminate further store service and cause the server
owner to stop. A compatible local reopen does not establish safe import of an
older copy, anti-rollback protection or an atomic multi-call SDK fabric change.

The server process MUST explicitly own SDK memory/platform initialization,
credentials, the generated data-model provider, the network driver, interface
and service port. Missing credentials or a model/vendor/product identity
mismatch MUST prevent server initialization. The disabled model-generation
endpoint MUST NOT be served. Each native process has one SDK server lifetime.
Normal shutdown MUST stop the event loop before releasing SDK resources and
retire global references to borrowed providers. A partial SDK initialization
or poisoned store MUST terminate the native process before it can serve cached
state; the outer owner MUST reap and classify that process without retrying a
mutation.

Dynamic SDK slots MUST remain distinct from durable endpoint IDs. Restore MUST
receive one explicit consumer configuration for every live Thing and refuse
missing, duplicate or incompatible Device Types before registering children.
The selected temperature capabilities MUST remain fixed for the registered
lifetime. Unknown bounds and unavailable measurements MUST retain their null
meaning; a restart MUST NOT promote a previous measurement to current truth.
An observation MUST match both the Thing identity and its current endpoint.
Invalid observations MUST preserve previously approved state and reachability.
Permanent removal MUST retire SDK cluster registrations and endpoint-scoped
group/attribute custody. Normal shutdown MUST preserve durable group custody.

The native consumer handoff MUST retain a slot for every unconsumed request
context, including a staged result or expired request. It MUST admit at most
sixteen contexts, bind each ticket to one explicit process generation and a
non-reused request ID, and preserve one absolute deadline no later than 500 ms
after admission. Clock regression MUST be refused. Neither queue admission nor
a staged result grants authorization or establishes a physical effect. A
result consumed at or after expiry MUST become a timeout. Closure MUST refuse
new requests and retire all unconsumed results; the native owner MUST consume
their contexts before releasing SDK resources. Unconsumed handoffs at server
shutdown MUST terminate the native process before SDK cleanup.

Before an SDK request callback returns, retained metadata MUST own the complete
principal, including fabric, authentication mode, subject, CASE Authenticated
Tags and commissioning context, together with its exact path and operation
flags. Retained command arguments MUST be copied into one anonymous-root TLV
Structure of at most 65536 encoded bytes, 24 container levels and 4096 nodes,
counting the root. Malformed or excessive arguments MUST acquire neither a
request slot nor an SDK command handle. A retained invoke context MUST own an
SDK command handle until its result is consumed. An invalidated handle MUST
NOT be used for a response. Only an explicit renderer for the selected command
semantics may encode a completed consumer result; response-encoding failure
MUST still release the consumed context. Closure MUST drain retained handles
under the SDK stack lock before stopping the event loop. Destruction with a
retained handle MUST terminate the process.

A delayed native renderer MUST use the captured principal and timed context,
without querying the original SDK handler's session or exchange. Its scoped
reply adapter MUST copy at most eight distinct permitted response command IDs
and write at most one reply for the original endpoint/cluster/command path.
Invalid scope or path MUST prevent response service. A data-encoding failure
MUST remain observable even if the SDK-defined Failure-status fallback is
written. A renderer that produces no reply MUST NOT establish completion.
Retaining an SDK handle from the scoped adapter MUST terminate the process
before a borrowed adapter can escape its renderer-call lifetime.

## Bridged devices

A bridge may represent non-Matter physical devices. The bridge contract MUST preserve that distinction and cannot claim the underlying device itself is Matter-certified.

## Evidence

Required software peers include a bridged light and at least one non-light endpoint. Physical ecosystem evidence is separate and should include independent Matter controllers only after the generic server contract passes software gates.

CSA certification is outside ordinary package conformance and must never be implied by passing WMA tests.

## Finite server profile

The [exposed bridge profile](../plans/exposed-bridge-profile.md) owns the
selected Matter 1.6 Device Types, mandatory clusters/commands, generated
model, build options, bounded consumer handoff and separately owned test
credentials/peer inputs. The required On/Off Light includes Identify, Groups,
the Lighting feature and Scenes Management; a three-command On/Off-only
endpoint does not satisfy that selected Device Type. Temperature Sensor
includes Identify. Fabric-scoped group/scene operations and permitted
attribute writes MUST retain consumer authorization before dispatch.

Reproducible model generation is distinct from server implementation. It
does not establish fabric-store custody, commissioning, callback behavior,
reporting, independent-peer interoperability or certification.

## Delivery

The [exposed bridge delivery plan](../plans/exposed-bridge-delivery.md) sequences the existing target's native profile, endpoint custody, consumer authorization, reporting and independent-peer evidence. It adds no implementation claim to this target or the controller catalogue.
