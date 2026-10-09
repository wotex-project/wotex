# Exposed bridge delivery plan

Version: 1.14.0. Delivery plan for the existing WMA.09 target; not a replacement
for the controller contract. The catalogue records execution status.

The pure endpoint registry now allocates monotonically, tombstones removed
endpoints, validates restart snapshots and fails on exhaustion. Its tests
simulate 256 identities and reject duplicate, rewound and overlapping
snapshots. The benchmark measures only BEAM-side custody. The native bridge
store persists SDK values and endpoint custody together with a separate
immutable bridge/model identity. An internal SDK server binding owns startup
and shutdown resources; a consumer-facing native process, request dispatch
and independent controller peer remain open.
The [finite software profile](exposed-bridge-profile.md) pins the source,
Matter 1.6 data model, root/aggregator layout, both bridged Device Types,
mandatory light/sensor clusters, generated model artifacts, build options,
handoff limits, test-attestation inputs and independent controller peer source.
Reproducible model generation and native store custody are implemented.
The native build exercises the server and dynamic endpoint bindings separately
from the controller. Consumer request handoff and peer receipts remain open.

## Scope

A controller interacting with an upstream bridge example is not itself a bridge server. Keep the new server role in a separately owned native process/store profile. Reuse pure path/TLV/descriptor values only where the role semantics match. The current controller SDK pin is a starting reference, not automatic qualification of the server build or new device types.

## 1. Close the server profile before coding

Select the exact connectedhomeip source, Matter specification and Device Type/cluster revisions. Document which bridge root/aggregator/bridged-node constructs and interaction operations are included. List unsupported types and optional features. Generated cluster data, build options, credentials and test peers are part of the profile identity.

The selected consumer handoff is bounded to 500 ms, with sixteen pending
requests and sixty-four approved observations. Five fabrics and fifteen
subscriptions are bounded, with three per fabric. Production credentials have
no sample-provider fallback; the selected SDK test attestation belongs to a
separate test build. No production or certification claim follows from model
generation or sample credentials working. Implement and verify these limits
at the native receiver before accepting server execution.

## 2. Stable endpoint custody

Allocate durable endpoint identities for consumer-owned Thing identities. Persist the mapping with the server store, retain removal tombstones and define exhaustion behavior. Restart must not bind an existing controller's endpoint to a different Thing. Restore includes fabric and endpoint-store compatibility; it is not just re-enumerating devices into arbitrary numeric slots.

Map reachable/unknown/unavailable explicitly. One reachable bridge does not make each child reachable. A consumer supplies capabilities and state; the native server cannot infer the truth of a physical effect from an accepted callback.

The internal `wotex::matter::BridgeStorage` implements native custody. Its
`wotex.matter.bridge-store` version 1 format contains immutable opaque bridge
identity, model SHA-256, vendor/product IDs, active Thing/endpoint/Device Type
records, a monotonic next-endpoint counter and SDK key/value data. Every
inactive ID below the counter is retired; tombstone storage does not grow with
removal history. Opaque Thing identities retain arbitrary bytes, with a
256-byte bound. Sixteen live endpoints and IDs 3 through 65534 are enforced.
Changing a live Thing's Device Type is refused.

The bridge and controller formats reject each other. They share the existing
owner-only directory, nonblocking exclusive lock and temporary-file/intent,
fsync/rename commit mechanism without changing controller serialization.
Bridge mutations publish their output only after that commit succeeds. An
ambiguous crash refuses reopening; a durable crash retains SDK values and the
endpoint mapping. A failed write poisons both SDK and endpoint access. The
server binding terminates its process on that failure before SDK caches can
continue serving. This format is local persistence, not an authenticated
backup/import protocol or a transaction spanning several SDK storage calls.

[`bridge_storage_test.cpp`](../../../../packages/wotex-matter/test/native/bridge_storage_test.cpp)
exercises role/identity mismatch, locking, private modes, opaque identities,
restart/remove/re-add, Device Type refusal, capacity, exhaustion, malformed
state, poisoning and all eight allocation/removal commit cutpoints.
[`sdk_bridge_storage_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_storage_test.cpp)
binds the actual pinned SDK operational keystore and certificate store,
generates an ephemeral test CA and operational key, verifies signatures and
certificates across reopen, discards uncommitted keys and preserves endpoint
custody after SDK fabric-key/certificate removal. The explicit native build
runs this executable in normal and ASan/UBSan modes; it starts neither the
server nor controller singleton. These store tests do not establish server
commissioning, ACL admission or interaction behavior.

The internal
[`SdkBridgeServerBinding`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_server.hpp)
injects the bridge store, operational keystore/certificate store, group and
session providers, ACL storage, report scheduler, generated model, explicit
Ethernet driver, interface and port into the SDK server. The process owner
initializes memory/platform and credentials and serializes startup/shutdown
under the SDK stack lock. Normal shutdown stops the event loop, shuts down
the server and fabric table, and retires model/persistence references. Partial
SDK initialization or destruction without serialized shutdown exits with 70;
a poisoned store exits with 74 before returning to cached SDK service.
The future native Port owner must reap and classify these exits.

[`sdk_bridge_server_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_server_test.cpp)
is a separate test-only target using explicit SDK example attestation and
generated private onboarding material. Its eleven cases cover startup, real
event-loop work, normal/reopened-store shutdown, missing interface/port/DAC,
model/vendor/product mismatch, occupied-port startup failure, omitted shutdown
and SDK/allocation/removal storage failure. The native builder generates the
pinned model and runs every case in normal and ASan/UBSan builds. Endpoints 0
and 1 have the selected Root Node/Aggregator declarations; dummy endpoint 2
is disabled. This lifecycle target does not exercise a commissioning exchange,
authenticated request, consumer callback or independent peer.

The internal
[`SdkBridgeEndpointBinding`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_endpoints.hpp)
borrows that server's authoritative bridge store and serializes sixteen dynamic
children under the SDK stack lock. Durable endpoint identity does not depend
on the SDK slot chosen after restart. Restore validates the complete explicit
consumer configuration before registration. Add/remove commits identity first;
an incomplete SDK registration terminates the process. Child reachability,
On/Off state and nullable temperature measurements come from explicit approved
observations matching both Thing and endpoint identity. Measurements start
unavailable after restart. Temperature bounds remain fixed while registered.
The binding enumerates the finite Device Type/cluster/command metadata and
registers independent Bridged Device Basic Information servers. It does not
implement authenticated consumer command/write dispatch.

[`sdk_bridge_endpoints_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_endpoints_test.cpp)
adds five cases to the separate server target. Fresh/reopened hosts exercise
all sixteen children, exact clusters, revisions and command lists, Descriptor
PartsList, opaque identity, nullable and one-sided bounds, invalid observations,
remove/re-add without endpoint reuse and actual event-loop observations. Direct
SDK group seeding verifies fabric-scoped persistence and permanent removal;
it does not establish commissioned-fabric or ACL admission. Normal shutdown
retires every child registration while preserving group custody. Omitted
shutdown and failed add/remove commits verify the fatal owner paths. These
cases run in normal and ASan/UBSan builds through the native builder.

## 3. Request and report path

Inbound fabric/ACL admission precedes consumer authorization. Supply exact endpoint/cluster/operation, principal/fabric context, request identity and deadline to the consumer. A controller is not entitled to bypass the consumer's policy because commissioning succeeded.

The internal
[`BridgeConsumerHandoff`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_handoff.hpp)
owns sixteen slots, an explicit process generation, non-reused request IDs and
absolute deadlines bounded to 500 ms. It retains admission credit until the
native owner consumes a context, including after expiry. Clock regression,
foreign tickets, duplicate replies and consumer-forged timeout/closure outcomes
are refused. Delayed consumption cannot publish a staged result after expiry;
closure cannot publish a staged result or admit another request. Server shutdown
closes the handoff and terminates before SDK cleanup if any context is unconsumed.
This is request custody, not authenticated consumer dispatch or observation
authority.

[`bridge_handoff_test.cpp`](../../../../packages/wotex-matter/test/native/bridge_handoff_test.cpp)
exercises capacity, exact deadlines, all logical results, delayed delivery,
closure, generation mismatch, clock regression and request-counter exhaustion.
The separate SDK server target adds event-loop handoff, closed/pending startup
refusal and unconsumed-shutdown termination cases. The owner supplies explicit
test times; these cases do not exercise an authenticated Matter request or an
ExposedThing callback.

The internal
[`BridgeHandoffOwner`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_handoff_owner.hpp)
borrows custody and an explicit `BridgeHandoffClock`, sampling elapsed time
inside the same mutex that serializes custody calls. SDK context operations
run through a nonblocking serialized callback; borrowed custody cannot escape
it. A synchronous waiter releases that mutex while blocked, so input resolution
and closure require no SDK stack lock. Every wake rechecks the original absolute
deadline. Closure through SDK context cleanup also wakes waiters. The caller
closes admission, drains contexts and joins all users before destruction or
direct server shutdown accesses the borrowed custody. Destruction with pending
contexts terminates with 70. The owner does not schedule asynchronous SDK work
or grant consumer authorization.

[`bridge_handoff_owner_test.cpp`](../../../../packages/wotex-matter/test/native/bridge_handoff_owner_test.cpp)
tests concurrent sixteen-context admission, input resolution while a simulated
SDK lock is held, exact expiry, regressed clocks, foreign generations, closure
through both paths, spurious notifications and unconsumed destruction. The
separate server target's
[`sdk_bridge_wait_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_wait_test.cpp)
runs installed-provider reads under the actual SDK event-loop stack lock while
the input thread resolves or closes custody independently. Explicit completion
reads an already approved value; denial, absent-reply timeout and closure return
their corresponding statuses and release context credit. The native builder
runs the SDK case in normal and ASan/UBSan builds. Synthetic principals and
completion inputs establish waiting ownership, not authenticated admission,
consumer policy or ExposedThing dispatch.

The internal
[BridgeResultInput](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_input.hpp)
borrows threaded custody, its exact generation and a mandatory nonblocking
notification sink. Its scalar-only SAX decoder admits the six-field
matter-bridge/result frame specified by WMA.09, bounded to 512 bytes including
LF, without a JSON DOM. Decode failure preserves output. Staged duplicates and
consumed/unknown identities are ignored; late notification cannot extend the
original deadline or release context credit. Notifications run after custody
unlocks and may not acquire the SDK stack lock. An asynchronous SDK work owner
must coalesce late notifications within sixteen pending contexts.

Input retains a fixed partial frame. Its explicit descriptor reader enables
nonblocking reads temporarily, restores flags and polls with a caller-owned stop
flag every 50 ms. EOF, partial EOF, malformed/oversized input, failed
allocation/clock/notification, read failure and cancellation close custody and
wake waiters; SDK context drain remains the SDK owner's responsibility.
The reader joins before its caller closes the descriptor or releases custody.
[bridge_input_test.cpp](../../../../packages/wotex-matter/test/native/bridge_input_test.cpp)
tests strict field/type/identity and size boundaries, unchanged failure output,
fragmented/batched input, shared sixteen-slot credit, original expiry,
staged-result loss, stale identities, pipe EOF, cancellation with an open writer,
read failure and descriptor restoration. Four additional separate SDK server
cases resolve fragmented real-pipe results while an installed-provider read
holds the actual SDK stack lock, then verify absent-reply timeout and wake on
EOF, malformed input, partial EOF or cancellation. The native builder runs them
in normal and ASan/UBSan modes. This bounded input foundation has no
consumer-facing Port host, authenticated consumer policy or ExposedThing dispatch.

The internal
[BridgeOutputOwner](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_output.hpp)
copies bounded frame bytes through nonblocking try-lock admission and writes
them on one explicitly owned thread. Sixteen request frames of at most 262144
bytes and four reserved control frames of at most 512 bytes include LF. The
selected encoder owns JSON/schema/role checks. Active writes retain their slot
and byte credit until written or discarded; controls precede queued requests
without interleaving frames, and each class preserves FIFO. SDK admission never
waits for output, silently retries or turns queued/written bytes into Success.
Shared request custody persists until the SDK consumes its result.

Cancellation, explicit closure or consumer loss, including idle loss, closes
admission and shared custody and discards queued bytes. Closure unlocks the
queue before acquiring custody or invoking the required notification sink,
preventing a cycle with SDK admission inside a serialized custody callback.
Notification occurs once after custody closes; the SDK owner separately drains
contexts. The writer temporarily uses nonblocking pipe or stream socket flags
and restores settable file status flags, with 50 ms write-poll and idle-wait
timeouts. Callers own SIGPIPE behavior and join all users before closing
descriptors or destroying output. Queued
bytes or an active writer at destruction terminate with 70. Close does not flush.

[bridge_output_test.cpp](../../../../packages/wotex-matter/test/native/bridge_output_test.cpp)
executes exact frame limits, malformed bytes, allocation/lock/capacity refusal,
copied ownership, concurrent producers, active credit, reserved controls,
ordering without byte interleaving, idle/blocked loss, cancellation, flag
restoration, duplicate-run refusal, custody-lock ordering and fatal missing
close. Three additional installed-provider cases fill the final output slot
inside actual SDK read admission, then wait under the SDK stack lock while an
independent pipe writer closes on explicit closure, cancellation or consumer
loss. The native builder runs them in normal and ASan/UBSan builds. Their opaque
stress bytes prove writer ownership, not a request codec, consumer-facing Port
bootstrap, authenticated admission or ExposedThing dispatch.

The separate
[native request codec](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_request_frame.hpp)
and `Wotex.Matter.Bridge.Wire` implement the exact fifteen-field request and
six-field result representations in both directions. They preserve original
fabric scope, complete principal, opaque Thing identity, selected flags, finite
write values and owned invoke arguments. Retained invoke export copies its
admission-time scope without consulting the current fabric table. The native
encoder leaves failure output unchanged; the BEAM decoder requires the expected
generation and rejects duplicate, missing, extra and unsupported cells.
Native deadlines remain native time. The TLV scan enforces SDK tag/container
rules without an implicit profile; command fields, profile identifiers and
scalar values remain opaque.

[bridge_request_frame_test.cpp](../../../../packages/wotex-matter/native/testing/bridge_request_frame_test.cpp)
passes thirteen native requests through the actual BEAM decoder and eight
BEAM results through the native decoder, including finite scalar/null values
and exact invoke byte/depth/node bounds. Eighty-five tag/container cases compare
BEAM acceptance and refusal with the pinned SDK, including special qualified
tags. Its standalone target isolates real
allocation-failure injection from SDK server fixtures. Both normal and
ASan/UBSan builds execute this pair. The builder validates exact fixture
metadata, counts, order and completion, rejects sanitizer findings, and records
the codec binary and both result and argument input hashes. The
[BEAM wire tests](../../../../packages/wotex-matter/test/wotex/matter/bridge_wire_test.exs)
cover strict framing, malformed/unsupported cells and arbitrary-byte totality.
These codecs supply inert representations; consumer Port bootstrap, clock
projection, mandatory consumer policy and ExposedThing dispatch remain required.

The internal
[`SdkBridgeInvokeContexts`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_requests.hpp)
copies callback principal/path metadata and bounded command arguments before
retaining an SDK `CommandHandler::Handle`. Copies preserve fabric, authentication
mode, subject, CASE Authenticated Tags, commissioning context and operation
flags. Attribute metadata additionally preserves list operation/index and an
optional data version. Owned command arguments use an anonymous-root Structure
of at most 65536 bytes, 24 container levels and 4096 nodes including the root.
Malformed arguments, mismatched handler context and excess capacity acquire no
SDK handle. The owner consumes results on the SDK thread, uses an explicit
command-specific renderer for completion, returns refusal/timeout statuses and
releases the handle even when response encoding fails. An invalidated SDK
handle cannot receive a response. Closure drains this owner's handles before
the event loop stops and preserves other owners' closed handoff contexts.

[`sdk_bridge_requests_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_requests_test.cpp)
adds request-owner cases to the separate SDK server target. Synthetic principal
fixtures exercise owned metadata for CASE, group and commissioning contexts;
the actual SDK Handle interface exercises sixteen retained commands, bounded
payload copies, reader-position preservation, stale tickets, clock regression,
delayed expiry, explicit reply rendering, encoding failure and valid/invalidated
handle cleanup. Omitting shutdown terminates with 70. Normal and ASan/UBSan
builds run these cases through the native builder. This is internal context
ownership: authenticated SDK admission, consumer policy, native Port delivery
and ExposedThing dispatch remain open.

The required
[`SdkBridgeInvokeGuard`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_guard.hpp)
now binds admission and completed rendering to the current SDK fabric, live
command metadata and actual ACL. Its fabric-table delegate assigns non-reused
epochs and captures the exact root key, fabric/node IDs and NOC digest; the
digest also detects rollback without a delegate notification. A retired realm,
removed endpoint, changed command contract or revoked ACL prevents the
completed renderer. Metadata errors remain distinct, and every consumed handle
drains even when refusal encoding fails. The borrowed guard and fabric table
outlive contexts; drain contexts and detach the delegate before SDK shutdown.

[`sdk_bridge_guard_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_guard_test.cpp)
uses generated test certificates, direct SDK fabric/ACL APIs and synthetic
CASE/group callback principals. It runs the retained owner with the actual
guard, testing explicit grants, privilege/target refusal, staged-result ACL
revocation, metadata failures, timed-command requirements, credential update
and rollback, same-realm index reuse, endpoint retirement and missing detach.
The native builder runs its normal and ASan/UBSan cases. Ownership-only tests
use an explicit test-build guard fixture; no permissive production default is
provided. Authenticated transport admission, consumer policy/dispatch and
independent-peer workflows remain open.

The internal
[`StartBridgeWrite`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_writes.hpp)
copies complete callback metadata and the finite profile's four writable
attributes before reserving shared request custody. IdentifyTime, OnTime and
OffWaitTime retain unsigned 16-bit values; StartUpOnOff retains null or its
defined Off/On/Toggle values. Unsupported paths, list operations and mismatched
decoder principals are refused before decoding. SDK type/range errors acquire
no slot and leave the output unchanged. Admission neither applies an attribute
value nor establishes authorization; a synchronous receiver must consume the
ticket at its original deadline before returning its SDK write response.

[`sdk_bridge_writes_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_writes_test.cpp)
uses actual SDK attribute decoders with synthetic principal inputs. It checks
owned metadata/scalars after callback storage changes, exact nullable/range/type
errors, refusal before decoding, sixteen-slot admission, staged-result credit,
deadline and clock refusal, expiry, closure and non-reused identities. Normal
and ASan/UBSan server builds run this case. It establishes internal write
admission; authenticated SDK request admission and consumer execution remain
open.

The internal
[`SdkBridgeCommandReply`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_replies.hpp)
adapts native command-specific rendering to the retained context's copied
principal and timed flag. It copies at most eight permitted response IDs,
restricts replies to the original path and writes at most one reply. Invalid
scope/path prevents further response service. A missing reply and the original
encoding failure remain observable, including when the SDK-defined fallback
Failure status is written. Metadata does not query an asynchronous SDK handler
or its exchange, and retaining a child handle from this scoped adapter exits
with 70 before the adapter can escape its renderer-call lifetime.

[`sdk_bridge_replies_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_replies_test.cpp)
adds two cases to the separate server target. Synthetic principal and group-key
fixtures exercise the actual SDK Groups and Scenes handlers after context
retention, inspect fabric-scoped group/scene custody and verify context cleanup
after response-encoding failure. The scoped adapter tests reject invalid and
excessive response IDs, invalid operations/paths, foreign or duplicate replies,
missing responses, failed encoding/fallback and escaped handles. Normal and
ASan/UBSan builds run these cases through the native builder. These direct
provider calls establish native rendering behavior; commissioned fabric/ACL
admission and consumer policy/dispatch remain required.

The internal
[`SdkBridgeProviderBinding`](../../../../packages/wotex-matter/native/include/wotex_matter/bridge_provider.hpp)
is the installed SDK data-model provider. It borrows the generated provider
and an explicit `BridgeReceiver`, preserves metadata/root operations and
routes live child reads, writes, invokes and list-write notifications to that
receiver without a cluster-execution fallback. Metadata is copied before
delivery. An absent/disabled endpoint cannot reach the receiver, and metadata
allocation failure preserves its error meaning. Attribute/endpoint change
notifications cross the wrapper under the SDK stack lock. Shutdown unregisters
the borrowed listener and closes this provider lifetime. The SDK otherwise
logs provider lifecycle failures and continues; this wrapper terminates with
70 on partial startup, failed shutdown or active destruction.

[`sdk_bridge_provider_test.cpp`](../../../../packages/wotex-matter/native/testing/sdk_bridge_provider_test.cpp)
adds four cases to the separate server target. An explicit test receiver
refuses child attributes before native decoding, retains an invoke without
returning automatic Success and renders only an explicit completion fixture.
The resulting status leaves the approved On/Off Property value unchanged.
Tests verify installed-provider identity, root delegation, copied metadata,
notification forwarding, metadata-allocation errors, closed-provider refusal
and all three fatal lifecycle paths in normal and ASan/UBSan builds. Synthetic
principal inputs do not establish SDK fabric/ACL admission or consumer policy;
the consumer-facing native Port and ExposedThing dispatch remain open.

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

The package catalogue keeps WMA.09 partial while pure/native endpoint custody
and model generation are implemented. Passing controller-side WMA.01-WMA.08 tests must not advance the
server evidence status. Native dependencies are not started by loading a library.
