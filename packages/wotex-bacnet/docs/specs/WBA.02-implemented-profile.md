# WBA.02 Implemented BACnet profile

The implemented draft-derived URI subset is
`bacnet://device-instance/object-type,object-instance[/property[/array-index]]`.
All identifiers are decimal. Omitted property means Present_Value (85); omitted
array index means the whole property. `.this`, named URI identifiers, query
parameters and fragments are unsupported. Property read/write select
ReadProperty/WriteProperty. Command priority remains available in the explicit
protocol API, not the URI profile. The `bacv:hasDataType` scalar subset supports Null, Boolean, Signed, Unsigned,
Real, Double, String and OctetString. Other extension semantics are not applied;
extension terms remain preserved in the Form.

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
