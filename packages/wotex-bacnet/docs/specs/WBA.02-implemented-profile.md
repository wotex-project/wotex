---
spec:
  id: WBA.02
  title: "Implemented BACnet profile"
  status: accepted
  version: 1.1.0
  owner: wotex-bacnet
  updated: 2026-09-09
---

# WBA.02 Implemented BACnet profile

The implemented draft-derived URI subset is
`bacnet://device-instance/object-type,object-instance[/property[/array-index]]`.
All identifiers use unsigned decimal digits. Omitted property means Present_Value (85); omitted
array index means the whole property. `.this`, named URI identifiers, query
parameters and fragments are unsupported. Property read/write select
ReadProperty/WriteProperty. Command priority remains available in the explicit
protocol API, not the URI profile. The `bacv:hasDataType` scalar subset supports Null, Boolean, Signed, Unsigned,
Real, Double, String and OctetString. Other extension semantics are not applied;
extension terms remain preserved in the Form. Known type selectors are validated
for reads and observations as well as writes. Forms that omit `contentType`
retain that omission; explicit content types fail before native acquisition.

`Transport.request/3` requires `target: "device-instance"` matching the Form plus
an explicitly configured client/destination. The device identity does not encode
an IP address. The consumer supplies the routing association. The native adapter retains ApplicationTags.Encoding values. Runtime extracts
supported scalars and retains the tag in result metadata; unknown values remain
intact. Write Forms require an explicit `bacv:hasDataType` declaration, or the
caller supplies an already typed Encoding value.
An explicit null release uses `Encoding.create!({:null, nil})`; a floating value
uses `Encoding.create!({:real, 42.5})`. The backend validates BACnet tags.

`IPv4` owns transport, Segmentator, SegmentsStore and Client. The group monitors
its caller, forwards decoded transport events and stops all children on failure
or disconnect. Startup unwinds prior children. APDU retries are always zero.
`BACstack` borrows a Client; the consumer owns its supervision/retry policy.
A task deadline isolates caller exits/timeouts but cannot retract an APDU.
Proprietary numeric identifiers pass Address validation; actual support depends
on BACstack's data model and may fail explicitly.
Both concrete adapters reject unknown or duplicate configuration keys before
opening resources. Unsupported security selectors, including BACnet/SC, cannot
be ignored and therefore fail instead of downgrading to BACnet/IP.

## Native helpers and observations

`read_property/4` and `write_property/5` validate native values and acknowledgments.
`read_properties/4` performs 1..64 distinct Property reads sequentially under one
admission slot and absolute deadline. `who_is/1..3` requires an explicit bounded
discovery configuration and returns typed `Device` observations. Identical
I-Am reports are deduplicated; conflicting identities fail the complete window.
Neither helper implements a Runtime aggregate operation or directory service.

Finite object and Property COV subscriptions support confirmed and unconfirmed
reports, renewal, selector validation, and cleanup of owned listeners, timers,
and workers. COV and discovery require the owned `IPv4` client or a verified
Wotex stack wrapper with the corresponding capability. Raw borrowed BACstack
Clients preserve read/write support and never gain implicit listener ownership.

`profile/0` returns the native read/write Runtime profile; `profile(:ip_cov)`
adds Property observation. The Runtime relay owns its native association and
monitors the Runtime subscription owner. Request results require native value
validation or the matching write acknowledgment. Mapping, setup, exchange,
conversion, and successful cleanup share one deadline. Native numeric error
details remain available to direct callers; Runtime retains the finite class
and code, and unknown-effect writes remain non-retryable.

These native and Runtime behaviors have executable lifecycle tests. The owned
`IngressTransport` uses active-once sockets and eight consumption credits across
StackOwner and StackClient, a 1536-byte datagram ceiling, and a 100 millisecond
starvation deadline. Its counters preserve malformed, oversize and pre-service
rejection distinctions. Socket loss and starvation release the owned group;
in-flight writes retain unknown effect.

Borrowed native sessions default to `receive_policy: :consumer_managed`.
`:wotex_bounded` requires the version-three wrapper plus verification of its
actual live transport and generation. Borrowed Runtime COV requires that mode.
Local tests exercise each ingress corpus case, including 10000 maximum-size
datagrams with StackOwner and StackClient suspended separately. Independent C
tests exercise object and Property COV, discovery, batch reads, priority release,
lost ACKs and public Runtime Property observation/stop. Full receiver-death stress
and final WBA-P06 evidence remain
required; this section does not accept the complete target profile.

## Evidence and compatibility

See [executable evidence](../provenance/executable-evidence.md) for specific tests,
commands and remaining gates, and [source revisions](../provenance/primary-sources.md).
Public callbacks provide a neutral compatibility surface, not drop-in semantic
parity. `send/2` completes synchronously; no fictitious receive queue exists.
The consumer must run differential scenarios before replacing its implementation.

Runtime adapters reject credential objects they cannot interpret. Native client
credentials/options are supplied explicitly by the consumer. A custom Client
implementation is trusted executable code and must honor the timeout and cleanup
contract; the wrapper cannot impose those guarantees on an arbitrary module.
Unknown Form extensions remain immutable but are not silently treated as
implemented protocol behavior. Finite deadlines, unsupported operations and
remote failures use structured Error values. Failed mutations report unknown
effect when execution may have started; a transport acknowledgment is not
canonical device state.
