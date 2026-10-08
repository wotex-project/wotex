# WZG.01 — Coordinator host boundary

Version: 0.9.0-target. The catalogue records implementation status; hardware
qualification is separate.

## NCP architecture

**WZG1-01.** The first architecture uses a network co-processor running a qualified Zigbee stack. Elixir owns the host protocol, lifecycle, typed commands/results and consumer-facing observations. It does not implement the radio PHY/MAC timing in BEAM processes. An arbitrary IEEE 802.15.4 radio or a Thread Spinel RCP is not interchangeable with a Zigbee coordinator NCP.

The public boundary is neutral: coordinator identity/capabilities, network operations, ZDO/ZCL requests, reports, persistence/credential ports and lifecycle. Chipset framing is a backend. A product profile, home rule, canonical Thing state or safety response is not part of this package.

## First backend decision

**WZG1-02.** Start with one documented serial NCP backend. TI ZNP/Monitor-Test is the first host backend; EZSP over ASH is a separate potential backend, not a protocol synonym. Pin the exact NCP firmware, SDK/API version, serial parameters and supported commands. Open host control and vendor firmware licensing are distinct; the package must not claim full radio-stack source openness without evidence.

Primary architecture references: [TI ZNP](https://software-dl.ti.com/simplelink/esd/simplelink_cc26x2_sdk/2.30.00.34/exports/docs/zstack/html/zigbee/znp_interface.html) and [Silicon Labs NCP overview](https://docs.silabs.com/zigbee/9.1.0/zigbee-coprocessors-overview/). The first host API uses the TI CC26x2 SDK 2.30.00.34 revision; exact coordinator firmware bytes remain consumer-configured and physical firmware qualification is outstanding.

## Serial ownership

**WZG1-03.** A consumer supplies a serial port implementation. One supervised owner holds the coordinator; no global auto-discovery or silent serial-path selection occurs. Match the configured hardware identity after USB reconnect and negotiate the protocol version before restoring network use. Only an explicit command may form, erase or replace a network.

Handle fragmented/coalesced serial frames, invalid lengths/checksums, async indications and transport reset. Bound frame bytes, pending requests, report queues and deadlines. ZNP synchronous replies and later AF/ZDO confirmations are separate observations. EZSP implementations must implement their admitted ASH/version/recovery profile rather than assume an unframed serial stream. A timeout cannot be interpreted as a network reset request.

Ordinary commands and interviews preserve the absolute caller deadline across
queueing, serial writes and reply delivery. A valid SRSP queued past expiry cannot
complete successfully. Receiver admission clamps a supplied deadline to the
configured timeout. A timeout after writing, malformed SRSP, serial failure
or loss of a pending caller ends the epoch and closes the adapter. An expired
call rejected before writing leaves the owner usable. Serial callbacks must
return within the consumer's budget; the owner cannot preempt a blocking
callback. External callback error text stays outside public errors and results.

Startup also uses one absolute deadline, established before spawning the
owner. Serial open, `SYS_VERSION` write and version reply delivery consume
that budget. A port returned after expiry is closed without a version write;
a queued valid version reply cannot complete after expiry. `Owner.ready/2`
admits a wait from 1 to 60,000 ms and can shorten, never extend, the remaining
negotiation budget. A ready wait against an already usable owner queued past
its own deadline fails without closing that owner.

The original startup caller and a pending ready waiter are monitored during
negotiation. Caller loss while opening is checked when the callback
returns; no subsequent version request is written. Caller loss during
negotiation ends the owner.

`Wotex.Zigbee.open/1` and `Owner.open/1` preserve that original caller monitor
and startup deadline through handle handoff. Version admission before the
caller can request its handle leaves the owner waiting within the same
budget; another waiter cannot claim the handle. The owner establishes its
caller link and lifetime monitor before delivering the successful reply.
Normal or abnormal caller exit ends that owner, fails pending operations and
attempts serial cleanup once. Copying a handle does not transfer this lifetime.
Caller-owned owners trap linked exits so adapter loss follows the same
redacted failure/cleanup path. A consumer-supervised `Owner.start_link/1`
retains its supervisor's lifetime policy; `Owner.start/1` remains the separate
unlinked startup/ready seam.

Known startup failures use a shutdown result with
the public error, avoiding a crash report of callback state or queued bytes.
Raised, thrown, exited, malformed and returned failures from open, write or
close are redacted. An acquired port receives one close attempt on failure
or teardown. An adapter that fails before returning a port owns cleanup of
its unreturned resources. Explicit close returns a serial error if the
callback does not return `:ok`; failure does not become a successful cleanup
claim. A blocking callback remains subject to the consumer's adapter contract.

## Values and calls

**WZG1-04.** Pure values carry logical IEEE identity, endpoint, cluster, manufacturer code, direction, typed payload and caller context. The backend maps correlation/sequence tokens under finite outstanding windows. A sent serial command, APS acknowledgement, ZCL default response and attribute report are distinct result classes. No result grants consumer authorization or proves physical effect.

The first AF request seam carries raw eight-byte EUI-64 peer identity, its
current 16-bit route, endpoints, cluster, local transaction byte and bounded
caller correlation. Peer identity and caller correlation stay on the host;
ZNP receives only its defined AF fields. The consumer verifies the route to
IEEE mapping during interview and after rejoin. A route-only compatibility
call remains available but does not claim durable identity.

`Wotex.Zigbee.Routes` is an inert, consumer-owned ledger keyed by raw IEEE
identity. It admits a complete matching interview from its current owner
epoch. Entries retain the identity observation time, owner sequence,
generation and an explicit lifetime of at most 24 hours. A newer observation
can replace the same identity's route; older evidence cannot rewind it.
Different identities claiming an occupied route quarantine the claims,
including at capacity. The consumer must retain the updated table returned
with `route_conflict`. Forgetting one claim does not promote another.

The owner stamps each received AREQ Event with its epoch, monotonic
millisecond time and a sequence from 1 to `0xFFFFFFFFFFFFFFFF`. Sequence
exhaustion ends the epoch rather than wrapping. Pure `Event.from_frame/1`
leaves this metadata absent. `Routes.resolve/3` requires current unexpired
custody and an observation from that epoch at or after the adopted identity
observation, including sequence order within one millisecond. It retains the
unchanged Event and its security disposition. These are host observations,
not authentication or proof that a radio frame is fresh.

`Wotex.Zigbee.send_routed_data/4` revalidates the supplied current table at
the serial receiver before I/O. It requires the request's IEEE identity and
route to match current custody in that receiver epoch and clamps the absolute
operation deadline to custody expiry. Expiry before dispatch leaves the owner
usable; expiry after dispatch ends the epoch through the normal timeout path.
The consumer owns table serialization and supplies its latest value; old
immutable snapshots cannot detect later consumer decisions. Rebinding to a
new owner retains peer records but requires a fresh interview before use.
Custody expiry grants no authorization and does not declare a quiet device
offline.

The non-administrative query API includes `Wotex.Zigbee.ieee_address/3` and
`node_descriptor/3`. Both take a known unicast route from 0 to `0xFFF7` and a
finite timeout. The IEEE request selects single-device response type zero and
start index zero; node descriptor destination and address of interest are the
same route. Neither request searches broadly, opens joining or changes network
custody. A returned `Wotex.Zigbee.Reply` is immediate NCP admission only.

The owner admits complete canonical frames from the declared IEEE, node,
active-endpoint, simple-descriptor and AF data constructors. An ordinary owner
call cannot send raw administration, an extended IEEE query, modified flags or
a mismatched destination/address of interest. Rejection is `invalid_command`
before serial I/O. Each admitted command's SRSP must contain exactly its
single status byte; malformed or mismatched SRSPs invalidate the owner epoch.
Startup `SYS_VERSION` remains the separate five-byte negotiation.

`Wotex.Zigbee.ZDO.ieee_address/1` and `node_descriptor/1` decode the corresponding
AREQs into `zdo_ieee_address` and `zdo_node_descriptor` Events. The IEEE value
retains eight raw identity bytes, route, status, start index, associated count
and at most 35 associated routes. It supplies no independent source-address
field because this MT callback has none. The node value retains separate
source/address-of-interest, all descriptor flag bytes and the complete bounded
13-byte descriptor. A failed status exposes no successful node descriptor.
IEEE identity and node capability claims remain untrusted interview evidence.

These layouts follow the SDK-bundled
[Monitor/Test API SWRA198 revision 1.14](https://software-dl.ti.com/simplelink/esd/simplelink_cc26x2_sdk/2.30.00.34/exports/docs/zstack/Z-Stack%20Monitor%20and%20Test%20API.pdf),
sections 3.12.1.2–3 and 3.12.2.2–3. Revision 1.14 places StartIndex before
NumAssocDev in the IEEE callback. No automatic layout guessing or later-revision
fallback occurs. Exact firmware qualification must validate these layouts.

`Wotex.Zigbee.interview/3` owns one non-administrative workflow under one
deadline and one caller monitor. `Wotex.Zigbee.Interview` supplies the expected
raw IEEE identity, candidate route, registered local AF endpoint and finite
descriptor/Basic selection. Matching responses can arrive before their SRSP,
but cannot advance without successful NCP admission. APS confirmation and ZCL
Read Attributes Response are both retained for Basic reads. Ordinary commands
and other interviews receive `overload` while the workflow owns admission.
An admitted workflow returns `Wotex.Zigbee.Interview.Result` with ordered
steps, separate observations and explicit partial issues. An outer owner call
timeout may prevent delivery of that result when an adapter blocks.

The owner retires routes used by ordinary ZDO queries or interviews. A route
with an earlier ZDO query cannot start another interview in the same epoch;
return `correlation_exhausted` before I/O. A new route for the same IEEE remains
eligible. At most 128 distinct queried routes are retained per epoch; excess
new routes receive `overload`. Basic AF transaction/ZCL sequence bytes are
selected from the unused 256-byte window and never reused by interviews in
that epoch. Ordinary AF transactions and extractable ZCL sequence bytes also
retire slots. Exhaustion returns a partial result without issuing another
read. Reopening a consumer-selected owner creates a new host epoch without
forming or resetting the NCP network. These bounds do not authenticate frames
or establish replay-proof radio identity.

Credentials are resolved through explicit custody and not stored in public request values, errors or telemetry. Opaque owner handles have epochs; a replaced process cannot complete the prior owner's operation. Loading the package starts nothing; stateful owners are explicit child specifications.

`Wotex.Zigbee.send_queued_data/4` dispatches a validated inert
`Wotex.Zigbee.Downlinks` receipt against current supplied route custody.
The receiver checks complete receipt/request fields, owner epoch and
non-future enqueue time before I/O. The absolute operation deadline is at
most the supplied receipt deadline, custody expiry and caller/configured
timeout. Mailbox waits cannot renew that budget. Expiry before writing leaves
the owner usable; expiry after writing ends the epoch through the normal
timeout path. Receipts remain consumer-owned context, not proof of prior
queue admission or authorization. A reply remains NCP admission only.

`downlinks_test.exs` exercises finite admission/selection.
`zcl_configuration_owner_test.exs` dispatches selected write/reporting requests
through an independently framed peer and checks mailbox expiry, timeout after
writing, copied/future/old-epoch receipts and current-custody rejection.
Physical sleepy/check-in and battery qualification remain outstanding.

## Acceptance

WZG1-T1: constructor purity and unsupported backend/version errors. WZG1-T2: serial fragmentation, garbage, async reordering and finite budgets. WZG1-T3: command/reply versus later confirmation distinction. WZG1-T4: USB removal, stale handles and recovery without forming a new network. WZG1-T5: macOS and Nerves-compatible serial adapters exercise the same neutral contract. WZG1-T6: vendor profiles remain consumer-owned and no external home-automation daemon is required.

## Implementation evidence

| Boundary | Executed evidence | Remaining evidence |
| --- | --- | --- |
| Serial adapter | `circuits_uart_test.exs` mocks the UART API and covers exact USB identity, post-open drift, open/write errors, owner cleanup and a `SYS_VERSION` handshake through `Wotex.Zigbee.Owner`. | A real coordinator on macOS and Nerves, unplug/replug, exclusive open and permissions on both hosts. |
| Host protocol | `frame_test.exs`, `owner_test.exs`, `event_test.exs` and `zdo_test.exs` exercise the bounded software profile with an independently encoded simulated peer. | Exact firmware artifact, real NCP reset/recovery and physical endpoint evidence. |
| Startup and teardown | `startup_test.exs` and `test/support/startup_serial.ex` exercise delayed serial open/write, queued version delivery, original and ready-caller loss, one ready waiter, shorter budgets, malformed input, redacted callback faults, immediate close on failed negotiation and one close attempt with an explicit failure result. Suspended callers exercise the version-to-ready gap, link-before-delivery, foreign handoff refusal and expiry within the original budget. Normal caller exit and linked adapter loss close once and preserve redacted pending failures. Existing owner and UART tests cover timely negotiation and consumer supervision. | Qualified callback timing and cleanup on the physical serial hosts. |
| Request identity | `data_request_test.exs` validates EUI-64, route, payload and caller correlation and sends through the simulated serial peer without placing host-only identity in the wire frame. | Manufacturer/direction semantics and credential port. |
| Identity and node queries | `command_test.exs`, `zdo_test.exs` and `owner_test.exs` cover exact request bytes, bounded identity/node values, failed/malformed replies, independently framed later responses and owner rejection of uncatalogued commands. | Exact real firmware layouts and physical interview qualification. |
| Bounded interview | `interview_test.exs` and `interview_owner_test.exs` cover the independently framed workflow, early responses, duplicate lists/records, wrong sources, identity conflict, partial failures, one deadline, caller death, real route/token exhaustion and a new route for the same IEEE. `owner_test.exs` covers queued late SRSPs and delayed/failed serial callbacks. | Physical firmware and endpoint qualification, credential port and network administration. |
| Adopted route custody | `routes_test.exs` covers rejoin, conflict quarantine at capacity, expiry, stale evidence, sequence order and epoch replacement. `routes_owner_test.exs` executes an independently framed interview, guarded AF admission, unchanged source security metadata, rejection before I/O, queued expiry and timeout after dispatch. It sets the sequence to its bound to exercise exhaustion; it does not execute that many observations. | Physical rejoin/source qualification, radio authentication and replay disposition from the selected stack. |
