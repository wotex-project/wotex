---
spec:
  id: WBA.02
  title: "BACnet protocol and graduation contract"
  status: accepted
  version: 1.1.0
  owner: wotex-bacnet
  updated: 2026-09-09
---

# WBA.02 BACnet protocol and graduation contract

BACstack 0.0.1 (2025-08-20) is the pinned client implementation. ANSI/ASHRAE
135-2024 is the current standard baseline; complete paid service clauses were
not inspected and no full conformance is claimed. ReadProperty, WriteProperty
and finite COV subscriptions are independent graduation cells.

Addresses carry Object Type, instance 0..4194302, Property Identifier, optional
array index and write priority 1..16. Object instances reserve 4194303 for
wildcard use. Numeric proprietary object/property identifiers remain opaque;
unknown tagged values are preserved. Array index zero means array length;
nil means absent. Null is an explicit release value, not a missing response.

The consumer selects the owned IPv4 stack or supplies an explicitly supervised
borrowed BACstack Client, transport, Segmentator and SegmentsStore. Borrowed processes are never stopped by this
package. Owned startup must unwind every earlier resource on partial failure.
Client.send manages Invoke IDs and retries; do not add wrapper retries.
Only the expected ComplexACK ReadProperty result or matching SimpleACK write
response succeeds. Abort, Error and Reject remain failures even when BACstack
wraps them in {:ok, apdu}. Missing response and apdu_timeout are always errors.
Read responses must match object, property and array-index identity.

Confirmed COV notifications need ACK, source/process/object correlation and
bounded duplicate tracking. Finite lifetimes require explicit renewal. Cancel
by omitting both lifetime and issue-confirmed-notifications with the original
subscription identity; lifetime zero is not cancellation. Upstream helper
behavior needs wire verification. A codec/port alone does not claim COV delivery.

The W3C BACnet binding is a work-in-progress draft not reviewed by ASHRAE.
Use explicit library-profile Forms and label the draft boundary. Map Property
read/write to corresponding services, preserve extensions and never confuse
WriteProperty acknowledgment with accepted canonical Property state.

Acceptance: typed and malformed service vectors, proprietary values, wrong ACK,
Abort/Error/Reject, missing response, bounded calls, owner death, borrowed
resource retention, COV cancellation and independent BACnet C-stack peer tests.

## Common library rules

Use structured credential-free Error values, explicit finite budgets, immutable
address/value maps, no Application callback and no implicit runtime selection.
Compatibility callbacks are capabilities/connect/send/receive/disconnect/health_check/
subscribe/unsubscribe. A consumer port failure, malformed return or missing
transport is an error; never select simulation. Telemetry event prefixes are
[:wotex, :bacnet, ...] with bounded non-secret measurements. Consumer integration
requires its own differential and interoperability evidence.
