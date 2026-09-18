---
spec:
  id: WBA.04
  title: "Complete BACnet/IP client software profile"
  status: accepted
  version: 1.1.1
  owner: wotex-bacnet
  updated: 2026-09-14
---

# WBA.04 Complete BACnet/IP client software profile

Read [WBA.01](WBA.01-library-contract.md), [WBA.05 standalone client and preservation](WBA.05-standalone-client-and-preservation.md), and the [implementation sequence](../plans/software-implementation.md).
This is the implemented software profile. Current code implements typed read/write, strict ACK
classification, explicit stack ownership, COV lifecycle, discovery, sequential
helpers, Runtime observations and consumption-based owned UDP ingress.
Independent discovery, batch, COV, fault and stress evidence is accepted for the
exact cohorts in [executable evidence](../provenance/executable-evidence.md).

## Scope and source authority

Use BACstack 0.0.1 and the ANSI/ASHRAE 135-2024 baseline recorded in
[primary sources](../provenance/primary-sources.md). Full paid service clauses
were not inspected. The implementable service contract below is grounded in the
pinned SDK and independent BACnet C-stack source; it is not a BTL or full-standard
conformance claim. Keep that access limit in public claims.

Required: BACnet/IP ReadProperty, WriteProperty, explicitly configured bounded
Who-Is/I-Am discovery, sequential property-read helpers, SubscribeCOV and
SubscribeCOVProperty with confirmed/unconfirmed notifications, finite renewal
and cancellation. WBA.05 defines discovery and named helper contracts. BACnet/SC,
MS/TP, BBMD/foreign-device registration, routing, ReadPropertyMultiple wire
services, server objects and trend/alarm services are outside this profile. Reject unsupported selectors before I/O.
Do not manufacture a transport from a device instance number.

## WBA-S01 — Address and value boundary

Keep `Address.new/1`, `Address.validate_message/1`, `Wotex.BACnet.send/2`, and the
scalar Form profile in [WBA.03](WBA.03-implemented-profile.md).
Object type is 0..1023; concrete instance 0..4194302; property identifier
0..4194303; optional array index 0..4294967295; optional write priority 1..16.
Nil array index is absent; zero reads array length. Nil priority lets the server
apply its protocol default. Reject priority on reads/subscriptions instead of
discarding it. Known atom aliases use a finite table; proprietary numeric IDs
remain numeric. Reject unsupported SDK encoding explicitly, never reinterpret it.

Native values retain `BACnet.Protocol.ApplicationTags.Encoding`. Supported
Runtime scalar types are Null, Boolean, Signed, Unsigned, Real, Double, String
and OctetString. Null is explicit release; missing write value is an error.
Unknown decoded tags remain opaque native values with tag metadata, and cannot
silently become strings. Public Encoding structs require validation at send time.
**Library policy:** decoded value at most 64 KiB, 1024 elements, depth eight.
Finite Real/Double only. The library scalar profile accepts Signed in
-2^63..2^63-1 and Unsigned in 0..2^64-1; encoding must retain the selected tag.
Keep explicit text character-set identity; do not label unknown encoded bytes UTF-8.

## WBA-S02 — Service completion and APDU ownership

BACstack owns Invoke IDs, APDU framing, segmentation and its retry engine.
Owned `IPv4` configures APDU retries to zero; a borrowed Client has an explicitly
documented consumer retry policy. Never layer wrapper retries over either.
Pass the remaining absolute deadline to each upstream call. An upstream
`{:ok, apdu}` is only an envelope: Abort, Error and Reject still fail.

ReadProperty requires a ComplexACK whose decoded object, property and array index
match the request exactly. WriteProperty requires a SimpleACK for that service.
Subscribe operations require SimpleACK for the selected subscribe service.
Missing APDU, unexpected service, malformed/trailing tags and APDU timeout fail.
Preserve numeric Error class/code and Abort/Reject reason without exposing payloads.
Wrong response identity cannot be consumed by a later operation.

**Library policy:** advertise maximum APDU 1476 on the owned IPv4 transport,
reassembled response ceiling 64 KiB and at most 32 segments. Wire segmentation
negotiation must respect the peer's advertised receive limits. Set `SegmentsStore` option `max_segments: 32` and encode the same receive
segment limit in outgoing confirmed APDUs. Bound each received APDU to 1476 bytes
before it enters the store; 32 such segments remain below the aggregate ceiling.
Set the outgoing Segmentator limit from the explicit peer receive limits.
Borrowed clients must declare matching bounded receive policy; otherwise the
wrapper cannot claim the owned-stack assembly guarantee. No unbounded assembly
is allowed merely because an upstream default accepts it.

## WBA-S03 — Explicit stack lifecycle

Preserve acquisition order `IPv4 transport -> Segmentator -> SegmentsStore ->
Client`; the existing StackOwner records and unwinds the reverse order.
Forward transport events only to the matching live Client generation.
Monitor receiver, session owner and all owned children while calls are in flight.
Child failure closes the group and rejects pending calls. WBA-C03's admission
bound and absolute deadline apply across the complete service operation.

Borrowed `BACstack` retains the caller's Client, transport and segment stores on
disconnect. It owns only its listener/operation/subscription processes and timers.
`BACnet.Stack.Client.subscribe/2` registers a local APDU listener; it does **not**
establish a wire COV subscription. Always unregister that listener on cleanup.
On a dead borrowed Client, fail promptly; never start a replacement stack.

COV requires the verified `StackClient` wrapper. Owned IPv4 uses it
explicitly. A borrowed configuration selects `stack_client_kind: :wotex` and
passes a finite local version handshake before the session opens; an incompatible
PID returns `:unsupported_stack_client` without listener or wire registration.
The default `:bacstack` kind retains raw borrowed SDK ReadProperty/WriteProperty,
but rejects COV before registration. Unknown kinds fail configuration validation.
The wrapper owns its finite COV listener filters and per-receipt reply references;
it does not mutate another process's SDK state. This boundary preserves original
CharacterString bytes and lets every validated confirmed receipt be acknowledged,
including a duplicate received before the prior ACK. The [pinned SDK Client](https://hex.pm/packages/bacstack/0.0.1/files/lib/bacnet/stack/client.ex)
normalizes application tags before notification dispatch and drops confirmed
requests with an outstanding identical source/Invoke-ID reply entry. The wrapper
therefore intercepts COV before those SDK paths rather than claiming the raw
Client can satisfy the same profile.
The wrapper admits at most 64 pending service calls across borrowed sessions.
A cancelled or timed-out exchange retires its Invoke ID for 60000 ms; a finite
256-entry map prevents reuse during that retry window and returns `:busy` when
no ID is available. Allocation rotates through free IDs; retiring a call releases
its SDK timer and partial response assembly without closing a borrowed stack.
COV request assemblies use separate keys from response assemblies, retain the
request maxima octet lost by the pinned SDK decoder, compare normalized headers
across segments, and expire after 1000 ms. They are limited to 64 active assemblies,
32 segments each. Confirmed receipt contexts expire after 1000 ms and never exceed
1024 entries; a saturated or slow listener closes locally with `:slow_consumer`.

## WBA-S03a — Bounded owned UDP ingress

The owned stack uses a BEAM IPv4 transport with consumption-based rearming.
The pinned SDK transport's active-ten socket setting is insufficient: its
`handle_info/2` rearms before its downstream PID consumes forwarded messages.
Final COV receiver queue sampling cannot bound that earlier mailbox. This cell
is implemented by `IngressTransport`, `IngressWindow`, `StackOwner` and
`StackClient`, with explicit receipt consumption.

The selected boundary is a narrow package transport implementing BACstack's
public `TransportBehaviour`, using reviewed pinned packet codecs. It preserves
explicit interface, portal and destination behavior. A source patch to the
pinned transport is permitted only with exact source assertions and its own
regression suite. Never invent an upstream consumption callback or mutate a
borrowed Client's private state. Runtime remains BEAM-only.

Outbound packets use `TransportBehaviour.build_bacnet_packet/3` for NPCI and
APDU encoding. The package constructs the four-byte IPv4 BVLL envelope, including
an explicitly supplied BVLC extension when present. Encoded APDU data is at most
1476 bytes; the complete datagram is at most 1536 bytes. Empty APDU data requires
an explicit BVLC value. Header suppression and explicit NPCI retain the public
builder's semantics. Confirmed broadcasts fail before UDP transmission. Codec
failures expose finite reasons without exception text, stack traces or payloads.

The transport exposes an explicit package consumption protocol. It forwards
`{:wotex_bacnet_datagram, generation, receipt_ref, transport_message}` to its
recorded StackOwner, which forwards the same identity to StackClient. The client
returns `{:wotex_bacnet_consumed, generation, receipt_ref}` directly to the
recorded transport only after the message handler finishes. Every outstanding
reference occupies one credit; a consumed reference is removed once. A forged,
unknown or duplicate acknowledgment is ignored with a bounded counter. No upstream
private message shape is assumed for this acknowledgment.

The owned socket uses active-once, a requested receive buffer of 262144 bytes
(the actual OS value is recorded), and no per-packet Task. A datagram is at most
1536 bytes before decoding; malformed/oversize input is discarded with saturated
uint64 reason counters and no payload telemetry. At most eight datagrams are
admitted across transport, StackOwner and StackClient forwarding. Each carries
an owner-generated reference scoped to the transport generation. StackClient
acknowledges consumption only after processing or discarding that message;
StackOwner forwarding alone is not consumption. The transport rearms only while
credit remains. Unknown, duplicate or foreign-generation acknowledgments cannot
increase credit. Data and acknowledgment frames use explicit package-owned
messages, not guessed BACstack internals. Control, expiry and shutdown messages
must remain responsive while data credit is exhausted.

Credit starvation lasting 100 ms closes the owned group with `:slow_consumer`
under the one C03 cleanup grace. A single terminal cleanup worker requests
system shutdown of the owned StackOwner, permitting cleanup while that owner is
suspended and avoiding a stop-call cycle with the transport. It owns no network
operation and shares the same absolute cleanup deadline; it is never a packet
worker. Session watchers receive the terminal reason before transport shutdown.
Socket-port monitors also fail the group promptly on actual socket closure.
Consumed credit never implies successful APDU
service handling. Invalid/oversize datagrams and application-level rejections
have separate counters. Kernel UDP drops are reported only when an available OS
counter supports them; an unavailable counter is recorded as unavailable, never
as zero. UDP and unconfirmed COV provide no loss-free delivery guarantee. A
confirmed service whose reply is lost retains the protocol retry/duplicate rules;
an interrupted transmitted write remains unknown-effect and is never replayed.

Borrowed `BACstack` accepts explicit `receive_policy: :consumer_managed |
:wotex_bounded`, default `:consumer_managed`. Consumer-managed mode preserves
native read/write and its documented listener APIs but makes no bound on the
consumer's socket/forwarder mailbox. Selecting `:wotex_bounded` requires the
wrapper's local version-three handshake with `[:cov, :discovery,
:bounded_ingress]` and proof of an attached live credit-aware transport; a claimed
option or arbitrary PID alone is insufficient. Incompatible/absent capability
fails `:unbounded_receive_policy` before acquisition. Runtime `:ip_cov` with a
borrowed stack requires the verified bounded mode for target acceptance. The
existing version-one/two wrapper modes retain their locally tested native
operations; their capability list does not imply bounded ingress. Raw
borrowed SDK support remains read/write only and never owns the borrowed stack.

[ingress-v1.json](../../../../packages/wotex-bacnet/priv/fixtures/ingress-v1.json) defines the exact normalization and
locally bound traces. Software tests suspend StackOwner and StackClient separately, emit at least
10000 maximum-size datagrams continuously, and assert at most eight admitted
packet references across the pipeline, one terminal error, saturated-safe counters,
and zero owned socket/process/timer resources after cleanup. Tests also resume a
consumer before starvation, prove credit returns once, and reject replayed/foreign
acknowledgments. Malformed traffic and confirmed COV retransmissions run in the
same fault lane; a flat final-receiver queue is not ingress evidence.

## WBA-S04 — COV registration, correlation and cancellation

Native `subscribe(session, request)` and Client `subscribe/4`/`unsubscribe/3` follow
WBA-C01/C05. Request fields are `type: :cov | :cov_property`, concrete
address fields, required `device_instance` (integer 0..4194302), `receiver`, `confirmed` (Boolean, default true), `lifetime`
(seconds, default 60, range 2..86400), `renew` (Boolean, default true),
`max_queue_length`, `duplicate_window_ms` (default 60000, range 1..60000), and optional finite positive `cov_increment` only for
`:cov_property`. An object COV request omits property/array index; a Property COV
request includes them. Subscription validation is separate from read addressing.
The caller supplies the expected initiating device before registration; the first
notification cannot establish or change it. Runtime may derive it only from the
validated target/configuration association in WBA-I02. The [pinned C-stack COV
codec](https://github.com/bacnet-stack/bacnet-stack/blob/3603048350b8ba543ec76cf6aa8a232b3f4d442d/src/bacnet/cov.c)
encodes the initiating device separately from the monitored object; this required
input is library correlation policy, not an inferred network identity.

Allocate a 32-bit subscriber process identifier explicitly, unique among live
subscriptions on this session/destination. Do not derive it from a PID or reuse
it within a live generation. Bind the handle to the original destination,
initiating device, object, optional property/index, mode and process identifier.
At most 64 live subscriptions per session; overflow fails before registration.

| State/event | Required transition |
| --- | --- |
| Opening | Register local listener before sending SubscribeCOV/SubscribeCOVProperty |
| Correct subscription SimpleACK | Return the C05 handle; begin finite lifetime timer |
| Notification before ACK | Buffer at most one validated initial report; deliver only after ACK |
| Correct notification | Validate source, initiating device, process ID, object and all values; require the requested Property/index entry and retain companion entries |
| Confirmed notification | Reply using `BACnet.Stack.Client.reply/4` and its received reference, with matching invoke ID/service; ACK duplicates without redelivery |
| Renewal | At half the requested lifetime, resend original identity with a fresh service exchange and original finite lifetime |
| Renewal failure or expiry | One terminal error; cancel and close local state |
| Cancel/receiver death | Send original service identity with both lifetime and issue-confirmed-notifications omitted; then unregister listener and release state |

Lifetime zero means indefinite subscription and is rejected by this finite
profile. It is not cancellation. Construct the cancellation APDU directly with
both optional fields nil; the upstream helper's default confirmed flag must not
leak into it. Cancel also omits COV increment. Assert actual encoded tags in tests.
Remote cancellation errors cannot prevent local cleanup. A lost registration
ACK still requires best-effort cancellation because the server may have accepted it.

The local finite lease is anchored conservatively to the start of each control
exchange, and only a matching positive ACK establishes or renews it. Report
`time_remaining` is validated as an unsigned 32-bit wire value and retained as
metadata; it never extends this locally owned lease. All subscription children
and any owned stack share the session's one 1000 ms cleanup grace. Successful
explicit cancellation returns after its subscription owner has exited.

Deduplicate confirmed notifications by source, invoke ID and a bounded digest
of the decoded service identity/content for the peer's configured APDU retry
window (library maximum 60 seconds, 1024 entries). Invoke ID alone is insufficient
because it wraps. Unconfirmed reports have no transaction identity; do not drop
two reports solely because their values are equal. When the duplicate cache is
full, expire then evict oldest entries; memory remains bounded. ACK unrelated
confirmed services only if a separately registered consumer handler owns them;
this adapter must not acknowledge them as successfully processed COV.

## WBA-S05 — Runtime and management meaning

Map `observeproperty` to SubscribeCOVProperty and retain the original Form/routing
association for cancellation. The mapped native message uses `type: :cov_property`
with the URI's object/property/index and initiating `device_instance`. `Transport`
checks that device against its explicit decimal `target` before creating a relay.
An optional Transport `cov` map accepts only `confirmed`, `lifetime`, `renew`,
`max_queue_length`, `duplicate_window_ms` and `cov_increment` with the S04 native
ranges/defaults. It cannot override receiver, device, object, property, index or
service type. Those options are consumer configuration, not inferred Form
extensions. `subscribeevent` is unsupported in this profile:
COV Property reports are not BACnet alarm/Event service support. Runtime delivers
the selected property value plus source/property/tag/time-remaining metadata.
An object-level native COV report is an ordered list of property/index/typed-value
entries, not a map that loses duplicate indices. Bound a report to 1024 entries.
Property COV selects the value whose property and array index exactly match the
request, and preserves the complete validated ordered list in
`metadata.report_values`. Missing selectors and wrong indices do not correlate.
Companion entries are valid: [135-2016 errata, July 6 2020, Table 13-1a](https://bacnet.org/wp-content/uploads/sites/4/2022/08/135-2016-Errata-Summary-2020-07-06-v1.pdf)
includes Status_Flags, and [BTL 15.2 interim tests v18, 9.11.1.X11/X21](https://btl.org/wp-content/uploads/sites/3/2022/06/interim_tests_15.2_v18.pdf#page=122)
also allow associated properties. **Library projection policy:** repeated selected
entries with exactly equal typed values yield that value once and remain intact
in metadata. Conflicting selected values fail with `:conflicting_cov_values`;
list order never chooses a winning value. This projection policy does not remove
or reinterpret duplicates in an object-level native report.
No report is an authorization decision or canonical consumer state.

`health_check/2` accepts an explicit validated ReadProperty probe;
`health_check/1 -> {:error, :probe_required}` in its existing Error envelope.
Only a matching successful read reports `{:ok, :healthy}`. The probe is a native
`%{type: :read_property, object_type: ..., instance: ..., property: ...}` request;
optional array index is retained and non-read probes fail before I/O. A successful
custom-client return must also contain a bounded valid native value. False, zero,
empty values and explicit BACnet Null remain valid probe responses; absent or
malformed values do not prove health. Runtime credentials remain
unsupported; an IP route is explicit configuration, not a security scheme.

## Acceptance scenario families

| ID | Scenario | Required result |
| --- | --- | --- |
| WBA-V01 | Address/priority/index edges, forged Encoding, null versus absent | Exact typed result/error before invalid I/O |
| WBA-V02 | Read ACK wrong object/property/index; malformed/trailing value | Identity error, never stale or default success |
| WBA-V03 | Write/subscribe wrong ACK, wrapped Abort/Error/Reject, missing response | Structured failure retaining numeric status and conservative effect |
| WBA-V04 | Segmented response at limit, over limit, missing/out-of-order/duplicate segment | Bounded assembly or error; no incomplete value |
| WBA-V05 | Fail each startup acquisition; kill owner/child during APDU wait | Reverse cleanup within C03; borrowed stack survives |
| WBA-V06 | COV object/property registration, early initial report, negative ACK | Handle only after correct ACK; bounded early buffering |
| WBA-V07 | Wrong source/device/process/object/index; duplicate confirmed notification | No unrelated delivery; matching duplicate is ACKed once per receipt |
| WBA-V08 | Equal unconfirmed values, reused invoke ID with new content | Fresh reports delivered; no value-based deduplication |
| WBA-V09 | Renewal at half lifetime, lost renewal ACK, stale timer | Correct identity and finite termination |
| WBA-V10 | Cancellation encoded with both fields absent; lifetime zero input | Exact cancel tags; zero rejected, never used to cancel |
| WBA-V11 | Receiver death, overflow, double/foreign cancel, lost registration ACK | Local listener/timer release and original-route best-effort cancel |
| WBA-V12 | Property Form observation, unsupported Event/security, unknown extension | Correct applicability, no forbidden I/O, immutable extensions |
| WBA-V13 | Independent C-stack read/write/release/readback plus confirmed and unconfirmed COV | Actual asserted ACKs/reports/cancellation; missing peer fails |
| WBA-V14 | C09 concurrency/stress and both version lanes | No unowned stack/listener/invoke state after cleanup |

Extend the existing C-stack fixture pinned to
`3603048350b8ba543ec76cf6aa8a232b3f4d442d`. Use a second client to change a disposable
Analog Output, assert the COV value, then cancel and assert no further delivery.
The fixture must expose active subscriber count so local silence alone cannot
prove server cleanup. A fault-injection APDU peer handles malformed responses;
it is separate evidence from the independent stack. No physical network is required.
