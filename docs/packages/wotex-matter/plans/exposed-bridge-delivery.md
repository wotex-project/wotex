# Exposed bridge delivery plan

Version: 1.0.0. Implements the existing WMA.09 target; not executed evidence and not a replacement for the controller contract.

## Scope

A controller interacting with an upstream bridge example is not itself a bridge server. Keep the new server role in a separately owned native process/store profile. Reuse pure path/TLV/descriptor values only where the role semantics match. The current controller SDK pin is a starting reference, not automatic qualification of the server build or new device types.

## 1. Close the server profile before coding

Select the exact connectedhomeip source, Matter specification and Device Type/cluster revisions. Document which bridge root/aggregator/bridged-node constructs and interaction operations are included. List unsupported types and optional features. Generated cluster data, build options, credentials and test peers are part of the profile identity.

Decide native callback deadlines and bounded handoff into the consumer. Commissioning/attestation credentials and test identities must be separated from distributable credentials. No production or certification claim follows from sample credentials working.

## 2. Stable endpoint custody

Allocate durable endpoint identities for consumer-owned Thing identities. Persist the mapping with the server store, retain removal tombstones and define exhaustion behavior. Restart must not bind an existing controller's endpoint to a different Thing. Restore includes fabric and endpoint-store compatibility; it is not just re-enumerating devices into arbitrary numeric slots.

Map reachable/unknown/unavailable explicitly. One reachable bridge does not make each child reachable. A consumer supplies capabilities and state; the native server cannot infer the truth of a physical effect from an accepted callback.

## 3. Request and report path

Inbound fabric/ACL admission precedes consumer authorization. Supply exact endpoint/cluster/operation, principal/fabric context, request identity and deadline to the consumer. A controller is not entitled to bypass the consumer's policy because commissioning succeeded.

Return only the result the selected Matter command semantics can support. A long or uncertain physical effect must not be reported as completed merely because it was queued. Attribute reports originate in consumer-approved observations. Bound report credit and per-fabric subscriptions; reconnect must refresh state rather than hide continuity loss.

Keep duplicate command handling separate from exactly-once claims: the underlying device may not support idempotency. Rejections and unknown outcomes require software-peer fixtures before physical integration.

## 4. Isolation and recovery

Test commissioning window expiry, revoked fabric, malformed TLV, resource exhaustion, native process loss, store failure and consumer timeout. Server failure must not corrupt the independently owned controller role. Self-discovery and bridge-of-bridge compositions need an explicit consumer policy so reported state cannot loop into repeated commands.

## 5. Evidence order

1. Pure endpoint and cluster mapping vectors, with typed unknown/unsupported cases.
2. Native source/store lifecycle tests under sanitizers where supported.
3. Independent SDK controller peers exercising a bridge with at least a light and one different admitted type.
4. Fabric/ACL, multi-controller conflict, restart/remove/re-add and report-flow tests.
5. Exact-artifact consumer integration, then real independent ecosystem controllers.
6. Separate platform distribution, certification and installed-host acceptance.

The package catalogue keeps WMA.09 planned until implementation exists. Passing controller-side WMA.01-WMA.08 tests must not advance the server evidence status. Native dependencies are not started by loading a library.
