# WZG.01 — Coordinator host boundary

Version: 0.14.0-target. The catalogue records implementation status; hardware
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

Commands and workflows preserve the absolute caller deadline across
queueing, serial writes and reply delivery. A valid SRSP queued past expiry cannot
complete successfully. Receiver admission clamps a supplied deadline to the
configured timeout. A timeout after writing, malformed SRSP, serial failure
or loss of a pending caller ends the epoch and closes the adapter. An expired
call rejected before writing leaves the owner usable. Serial callbacks must
return within the consumer's budget; the owner cannot preempt a blocking
callback. External callback error text stays outside public errors and results.

Interviews, bindings, network inspection, channel migration and key rotation recheck caller liveness when
advancing or finishing on a reply. A queued reply cannot release that caller's
monitor or start another workflow step after caller death, even when the
reply precedes the monitor notification in the owner's mailbox.

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

`Wotex.Zigbee.change_binding/4` owns one explicit Bind/Unbind workflow under
current supplied source custody. `Wotex.Zigbee.Binding` requires operation,
raw source IEEE, unicast route, source endpoint, cluster, IEEE/endpoint or
group target and 1–64 host correlation bytes. Revalidate the complete request
and ledger at the receiver, using `Routes.check_peer/5`, and clamp the absolute
deadline to custody expiry. Source IEEE is transmitted in the defined MT field;
host correlation is not transmitted. The ordinary command seam continues to
reject raw Bind/Unbind frames.

The workflow holds admission after its SRSP while awaiting the peer callback.
Ordinary commands, interviews, network inspection and another binding receive
`overload`; unrelated AREQs remain in the finite queue. One caller monitor and
timer cover both reply orders. `Binding.Result` retains NCP admission and a matching source/operation
Event separately. NCP rejection returns an unconfirmed result even if a success
callback arrived first. Malformed SRSP, timeout after dispatch, serial failure
or caller loss closes the owner and retains available evidence. Refusal before
dispatch leaves the owner usable and does not retire an unused pair.

The finite profile follows SWRA198 revision 1.14 sections 3.12.1.14–15 and
3.12.2.13–14, with an exact SDK source resolution recorded in
[`zdo-binding-mt-r1.14.json`](../../../../packages/wotex-zigbee/test/support/profiles/zdo-binding-mt-r1.14.json).
Both `MT_ZdoBindRequest` and `MT_ZdoUnbindRequest` in SDK 2.30.00.34 read a
fixed eight-byte destination and endpoint, contrary to the document's
variable-width usage grid. Both MT payloads are 23 bytes. Group mode one
places its uint16 identifier in the low two bytes, zeroes the other six and
uses endpoint zero. IEEE mode three carries all eight bytes and endpoint
1–240. There is no automatic layout guessing or generic raw ZDO fallback.

The callback retains only source/status and drops the ZDO sequence. It echoes
no endpoint, cluster, destination or host token and carries no security flag.
Retire each `{operation, route}` on dispatch or valid callback observation,
including unsolicited observations, in a table of at most 256 pairs per epoch.
Repeated pairs receive `correlation_exhausted`; new pairs at capacity receive
`overload` without dispatch. This prevents later host requests from consuming
a callback from an earlier request within that epoch. Reuse requires a fresh
owner and fresh custody; neither supplies radio authentication or replay proof.

`Wotex.Zigbee.inspect_network/2` owns a finite pair of empty-payload
`UTIL_GET_DEVICE_INFO` and `ZDO_EXT_NWK_INFO` queries under one absolute
deadline and caller monitor. Both use separate explicit workflow admission;
the ordinary command seam rejects their raw frames. The first SRSP is a
14-byte fixed prefix with status, raw local IEEE, short address, capability
bits, device state and associated count, followed by up to 64 uint16 routes.
Count, length and complete payload must agree. Preserve duplicate and reserved
routes rather than infer peer custody from this local association list.

The second SRSP is exactly 24 bytes: short address, device-state byte, PAN,
parent address, extended PAN, parent IEEE and channel byte, with no status.
SWRA198 revision 1.14 section 3.12.1.48 omits the state and describes a uint16
channel; the exact SDK's `MT_ZdoExtNwkInfo` resolves that disagreement. Source
digests, sections 3.10.1.1/3.12.1.48 and literal vectors are recorded in
[`znp-network-mt-r1.14.json`](../../../../packages/wotex-zigbee/test/support/profiles/znp-network-mt-r1.14.json).
There is no automatic alternate-layout decoding or NV/key query fallback.

`Network.Snapshot` retains the two ordered raw payloads, decoded values and
owner observation times. `observed` requires both replies before expiry;
`partial` retains available readings and a bounded issue. Nonzero device
status stops without a second query. `matching`/`changed` compares reported
short address and state, retaining disagreement without declaring a stable
network. Sequential observations are not atomic. Unknown capabilities,
state and uninitialized metadata remain evidence. No success supplies
credential/counter continuity, joining authority or physical reachability.

The workflow holds admission across both queries and preserves unrelated
AREQs. Expiry before the first write leaves the owner usable; malformed
SRSP, timeout after dispatch, serial failure or caller loss ends the epoch.
Available readings survive in the partial result. No fresh deadline, retry,
reset or formation follows a failed query. Credential custody remains a
separate required port before network administration.

`Wotex.Zigbee.permit_join/4` is the first explicit administrative profile.
It takes an inert `PermitJoin` request and a consumer-owned `Credentials`
port. The request supplies expected raw coordinator IEEE and extended PAN,
PAN `0..65534`, channel `11..26`, duration `0..254` seconds, TCSignificance
`0` or `1` and 1–64 host correlation bytes. The finite MT payload is exactly
five bytes: address mode `2`, coordinator address `0`, duration and
TCSignificance. Duration zero requests closure; 255, remote targets and
broadcasts are refused. Raw permit-join frames remain excluded from ordinary
command admission. No startup, inspection or failure sends this command.

Before authorization, the owner obtains fresh device and network readings
under the original deadline and admission slot. Require complete matching
metadata, coordinator address `0`, device state `9`, coordinator capability
bit and exact requested IEEE/extended PAN/PAN/channel. The state value comes
from the pinned SDK's `devStates_t`; it is not inferred from a device label.
Wrong, changed, uninitialized or unsuccessful readings retain unconfirmed
evidence and never invoke custody or write a permit-join command. Sequential
matching readings still do not establish atomicity or credential continuity.

`Credentials.new/2` accepts an explicit module and opaque consumer pid or
reference. It stores no keys, counters, paths or private adapter options and
starts nothing. The consumer qualifies resident credentials, Trust Center
policy, declared install-code capability and any insecure enrollment fallback.
`authorize/3` receives the handle, a closed context with operation, exact
request, fresh snapshot, owner epoch, current monotonic time and original
deadline, plus the remaining millisecond budget. The callback checks current
custody and policy and returns a signed-64-bit monotonic authorization horizon
or denial. Private reason text and raised/thrown/exited/malformed returns
become fixed `credential_denied` or `credentials` issues. No key/counter bytes
are accepted as a return value. A syntactically valid horizon is not proof
that the consumer performed the required checks.

The receiver subtracts the requested duration from that horizon and clamps
dispatch to the earlier result and original deadline. Equality is expired.
Recheck caller lifetime and time after the custody callback. A denial, mismatch
or known expiry after completed metadata but before permit-join dispatch
retains available evidence and leaves the owner usable. Timeout during an
outstanding query or after permit-join dispatch, malformed SRSP, caller or
serial loss ends the epoch and attempts cleanup once. The callback/serial
adapter must return within the consumer budget; the owner cannot preempt it.
A late callback cannot start another command. A dispatch deadline does not
prove when the NCP processes the request or a physical joining window ends.

`PermitJoin.Result` preserves request, owner epoch, available network readings
and the exact one-byte SRSP. `ncp_admitted`, `ncp_rejected` and `unconfirmed`
describe that observation only. `ZDO_MGMT_PERMIT_JOIN_RSP` (`0xB6`) preserves
source/status without a transaction or duration. `ZDO_PERMIT_JOIN_IND`
(`0xCB`) preserves a local duration, including zero, without a request token
or security disposition. Both remain in the finite event queue with owner
time/sequence and the drop count, even while a command is pending. Neither
can complete a later opening/closing request. Closing is observable through
the local indication when emitted, with physical timing/closure qualification
still required; absence is unknown. NCP admission alone proves no opening,
closure, enrollment, install-code protection or security continuity.

The exact source review and literal vectors live in
[`zdo-permit-join-mt-r1.14.json`](../../../../packages/wotex-zigbee/test/support/profiles/zdo-permit-join-mt-r1.14.json),
covering SWRA198 revision 1.14 sections 3.12.1.22, 3.12.2.21 and 3.12.2.33.
The SDK ignores TCSignificance per its R21 comment and coerces duration 255;
the host declares the first behavior and refuses the second input. Its
callback can suppress a synchronous local indication during this MT call.
The generic send path is outside this profile; the pinned `ZDP_SendData`
source does not return its declared status. No alternative path, implicit
close/retry, reset, formation, key change, backup or restore is introduced.

### Explicit channel migration

`Wotex.Zigbee.ChannelMigration` and `Wotex.Zigbee.migrate_channel/5` supply
one explicitly authorized channel change and a bounded observation cohort.
The complete request contains expected coordinator IEEE, extended PAN, PAN
and original channel, a different target channel `11..26`, an explicitly
qualified settling delay `1..30000` milliseconds, per-peer observation budget
`1..60000` milliseconds, host correlation `1..64` bytes and `1..32` peers.
Each peer has exactly raw IEEE, unicast route `1..0xFFF7`, local endpoint and
Basic server endpoint `1..240`. Identities and routes are distinct; unknown,
duplicate, missing and private-material fields are refused without I/O.

Current `Routes` custody must cover every peer in this owner epoch. The
receiver clamps the original deadline to every custody expiry and checks the
table again after authorization. Two fresh metadata readings must match the
expected commissioned coordinator before `Credentials.authorize/3` receives
operation `:channel_migration`. The consumer qualifies resident security,
the exact firmware's network-manager/request support, administrative pacing,
current update-ID headroom and the configured broadcast delay. The pinned
SDK supplies current `nwkUpdateId + 1`; its receiver tests unsigned `>` and
provides no wrap recovery at 255. Unsupported or exhausted firmware must be
denied. These preconditions are consumer qualification, not inferred from
`SYS_VERSION` or a successful metadata query.

The finite MT request is subsystem 5, command `0x37`, eleven bytes:
destination `0xFFFD` LE16, broadcast mode **`0x0F`**, single target-channel
bit LE32, ScanDuration `0xFE`, ScanCount zero and network-manager address zero.
The parser assigns mode directly; `zcomdef.h` defines `AddrBroadcast = 15`,
contrary to the PDF's `0xFF`. Its SRSP echoes `0x37`, contrary to the PDF's
`0x36` grid. The exact SDK first sends the broadcast, then a unicast copy to
its local address; SRSP exposes only the latter status. Never infer broadcast
delivery or absence of effect from that status. The six-byte ZDO payload
contains channel mask, `0xFE` and the SDK-selected update ID. Arbitrary masks,
energy scans, manager reassignment and unicast administration are excluded.
Exact source paths, digests and literal vectors are pinned in
`test/support/profiles/zdo-channel-migration-mt-r1.14.json`.

One caller monitor and original deadline cover inspection, authorization,
dispatch, one settling timer, target-channel inspection and all peer probes.
The authorization horizon reserves the qualified settling delay for serial
dispatch and bounds later observations; it never extends the caller budget.
The SDK schedules switching after `NIB.BroadcastDeliveryTime * 100` ms. Its
build-overridable default is not proof of the installed delay. The host does
not poll the old channel or resend the administrative request.

Fresh matching coordinator metadata must show the target channel before
peer probes. Each probe is one revision 8 Basic ZCLVersion read using an
unused owner AF transaction/ZCL sequence token, retired before dispatch.
Source matching requires current custody, route, local/remote endpoint,
cluster zero, server-to-client global Read Attributes Response, no
manufacturer extension and the selected sequence. Preserve admission, APS
confirmation, original response/security metadata and decoded records.
Exactly one successful uint8 ZCLVersion `0..254` is the complete Basic
observation; null, duplicates, unexpected, failed or wrong-type records remain
partial evidence. A missing application observation after SREQ admission
may finish that peer and proceed once to the next. An unanswered SREQ or late
SRSP ends the epoch; it cannot be skipped because replies are uncorrelated.

`ChannelMigration.Result` retains original/target readings, local-copy
admission and one result for every requested peer, including unprobed peers.
`observed_cohort` requires target-channel metadata and complete observations
for every selected peer. It establishes no whole-network census, physical
per-device channel, radio authentication, sleepy-device delivery or key/counter
continuity. Different NCP/APS failures and missing responses remain distinct.
Denial or a known refusal before the administrative write leaves the owner
usable. Any administrative dispatch, including local-copy rejection, ends
the owner after observations; reopen and adopt fresh custody before further
traffic. No rollback, retry, reset, rekey or mass re-enrollment follows.

### Explicit network-key rotation

`Wotex.Zigbee.KeyRotation` and `Wotex.Zigbee.rotate_key/5` supply one finite
broadcast update/switch workflow. An inert request carries expected coordinator
IEEE, extended PAN, PAN and channel, current sequence `0..254`, strictly integer
next sequence `current + 1`, qualified distribution and settling delays
`1..30,000` ms, per-peer budget `1..60,000` ms, `1..32` distinct custodied peers
and bounded host correlation. Peer selectors use the channel-migration shape.
Unknown fields, copied malformed shapes, sequence wrap, unicast administration
and public key fields are refused before I/O. Current sequence is a consumer
custody claim; metadata does not verify it.

Fresh matching metadata and current routes precede `Credentials.authorize/3`
with phase `:update`. Its consumer qualifies installed firmware/build flags,
active sequence, unique fresh key, security policy, counter continuity,
broadcast distribution/pacing and both delays. An optional
`Credentials.with_network_key/4` callback retrieves the key privately and
invokes a one-use writer synchronously in the owner process. The writer accepts
exactly 16 nonzero/non-FF octets and rechecks its deadline and caller before
writing. It cannot run from another process, select another command, survive
callback return or dispatch twice. Authorization-only adapters refuse rotation.
The adapter returns no key value; request/result/state/notifications contain no
private material. Transient UART bytes require consumer-protected adapter
handling; secure memory erasure is not claimed. Private returns and faults are
redacted to fixed issues.

Pinned SDK `mt.h`/`mt_zdo.c` define update `0x4E` and switch `0x4F` in subsystem
5. Both require coordinator and MT extension build support. Update payload is
nineteen octets: `0xFFFD` LE16, next sequence and sixteen key octets. The PDF's
128-byte key/`0x83` payload grid confuses bits with bytes; `ssp.h` defines
`SEC_KEY_LEN = 16`. Switch payload is three octets: `0xFFFD` LE16 and the same
sequence. Each SRSP echoes its command with exactly one send-status byte.
Source paths, digests, literal switch/reply vectors and the private update
layout are pinned in `test/support/profiles/zdo-key-rotation-mt-r1.14.json`;
no stored key vector is required.

`ZDSecMgrUpdateNwkKey` calls alternate-key update and NV update after the send
attempt even when it fails. `ZDSecMgrSwitchNwkKey` sets the local switch
flag/index for broadcast destinations regardless of send status. Admission
therefore proves neither distribution nor absence of local effect. Visible
source declares SSP operations but does not provide their implementation or
prove installed activation timing, active sequence or counter behavior.

After update admission, one distribution timer precedes fresh matching
metadata and separate phase `:switch` authorization, including the update
admission. The shortened caller/custody/authorization budget reserves both
delays before update and settling time before switch. No grant extends the
original deadline. A key callback returning past its dispatch budget cannot
advance queued admission or another stage, even before the overall deadline.
One switch and one settling timer precede fresh matching
metadata and the same source-checked Basic probes used by channel migration,
with distinct retired owner AF/ZCL tokens. No retry, fallback, rollback,
counter reset or re-enrollment follows a failure.

`KeyRotation.Result` retains all three metadata snapshots, separate update and
switch admissions and every requested peer, including unprobed peers.
`observed_cohort_after_switch` requires both admissions, unchanged network
metadata and complete Basic observations for that cohort. Those responses do
not identify the protecting key; `activation` remains `:unconfirmed` in every
outcome. Missing, rejected or unavailable peers retain partial evidence.
Independent physical per-peer key/sequence and counter qualification remain
required. Known refusal before key dispatch leaves the owner usable; every
key-write attempt, including a fault or failed send, ends the epoch after
available observations. Reopen and adopt fresh custody before later traffic.

## Acceptance

WZG1-T1: constructor purity and unsupported backend/version errors. WZG1-T2: serial fragmentation, garbage, async reordering and finite budgets. WZG1-T3: command/reply versus later confirmation distinction. WZG1-T4: USB removal, stale handles and recovery without forming a new network. WZG1-T5: macOS and Nerves-compatible serial adapters exercise the same neutral contract. WZG1-T6: vendor profiles remain consumer-owned and no external home-automation daemon is required.

WZG1-T7: explicit local permit-join requires fresh expected-network metadata
and current consumer credential authorization, with finite dispatch/window
budgets, separate indications, private-material exclusion and lifetime cleanup.

WZG1-T8: explicitly authorized finite channel change with SDK-resolved bytes,
current route custody, separate local/per-peer observations, partial outcomes,
one deadline, correlation retirement and epoch cleanup.

WZG1-T9: separately authorized key update/switch with private one-use custody,
source-pinned bytes, finite delays/deadline, distinct per-peer observations,
redaction, partial failures and cleanup without an activation claim.

## Implementation evidence

| Boundary | Executed evidence | Remaining evidence |
| --- | --- | --- |
| Serial adapter | `circuits_uart_test.exs` mocks the UART API and covers exact USB identity, post-open drift, open/write errors, owner cleanup and a `SYS_VERSION` handshake through `Wotex.Zigbee.Owner`. | A real coordinator on macOS and Nerves, unplug/replug, exclusive open and permissions on both hosts. |
| Host protocol | `frame_test.exs`, `owner_test.exs`, `event_test.exs` and `zdo_test.exs` exercise the bounded software profile with an independently encoded simulated peer. | Exact firmware artifact, real NCP reset/recovery and physical endpoint evidence. |
| Startup and teardown | `startup_test.exs` and `test/support/startup_serial.ex` exercise delayed serial open/write, queued version delivery, original and ready-caller loss, one ready waiter, shorter budgets, malformed input, redacted callback faults, immediate close on failed negotiation and one close attempt with an explicit failure result. Suspended callers exercise the version-to-ready gap, link-before-delivery, foreign handoff refusal and expiry within the original budget. Normal caller exit and linked adapter loss close once and preserve redacted pending failures. Existing owner and UART tests cover timely negotiation and consumer supervision. | Qualified callback timing and cleanup on the physical serial hosts. |
| Request identity | `data_request_test.exs` validates EUI-64, route, payload and caller correlation and sends through the simulated serial peer without placing host-only identity in the wire frame. | Manufacturer/direction semantics and resident credential qualification. |
| Identity and node queries | `command_test.exs`, `zdo_test.exs` and `owner_test.exs` cover exact request bytes, bounded identity/node values, failed/malformed replies, independently framed later responses and owner rejection of uncatalogued commands. | Exact real firmware layouts and physical interview qualification. |
| Bounded interview | `interview_test.exs` and `interview_owner_test.exs` cover the independently framed workflow, early responses, duplicate lists/records, wrong sources, identity conflict, partial failures, one deadline, caller death with replies queued before its monitor notification, real route/token exhaustion and a new route for the same IEEE. `owner_test.exs` covers queued late SRSPs and delayed/failed serial callbacks. | Physical firmware and endpoint qualification, resident credential qualification and remaining network administration. |
| Adopted route custody | `routes_test.exs` covers rejoin, conflict quarantine at capacity, expiry, stale evidence, sequence order and epoch replacement. `routes_owner_test.exs` executes an independently framed interview, guarded AF admission, unchanged source security metadata, rejection before I/O, queued expiry and timeout after dispatch. It sets the sequence to its bound to exercise exhaustion; it does not execute that many observations. | Physical rejoin/source qualification, radio authentication and replay disposition from the selected stack. |
| Explicit binding ownership | `binding_test.exs` executes reviewed fixed-layout request/callback vectors and rejects malformed/copied inputs. `binding_owner_test.exs` exercises independent bytes, both observation orders, NCP rejection, peer failure, unrelated/duplicate events, mailbox/custody expiry, caller loss including each final reply queued before the death notification, malformed replies, redacted write faults, close/loss and actual 256-pair retirement with queue overflow. `routes_test.exs` covers source selector/custody refusal. | Exact physical firmware and qualified IEEE/group destinations, binding-table truth and sleepy-device power policy. |
| Network metadata inspection | `network_test.exs` executes exact SDK vectors, count/length bounds, unknown/uninitialized metadata, ordered/changed readings, partial issues and copied-value refusal. `network_owner_test.exs` independently frames both queries, preserves unrelated AREQs, refuses raw/busy/expired calls, and retains partial evidence through malformed replies, late delivery, caller/serial loss, callback faults and close. Each query's reply queued before caller death cannot advance or finish the workflow. | Exact physical firmware, atomic network continuity and qualified credential/counter custody. |
| Credentialed local permit-join | `permit_join_test.exs` executes pinned five-byte request vectors, bounds, copied-value refusal, pure port construction, expected-network comparison and distinct response/indication layouts. `permit_join_owner_test.exs` independently frames metadata and permit requests, authorizes every open/close through a consumer-owned test port, refuses mismatch/denial/raw/busy/expired work, shortens dispatch to the authorization horizon and keeps uncorrelated indications separate. Late/failed custody callbacks, secret canaries, write faults, caller death, wrong/late replies and timeout/loss exercise refusal and one cleanup attempt. | Qualified resident credentials, Trust Center/install-code/fallback policy, physical local joining and closure timing, remote scopes and key/counter export/import for backup/restore. |
| Explicit channel migration | `channel_migration_test.exs` executes source-pinned vectors, network/time/cohort bounds, exact copied shapes and before/after comparisons. `channel_migration_owner_test.exs` independently frames interviews/adoption, metadata, administration and per-peer Basic probes. It exercises both reply orders, partial peers, NCP/APS/record failures, source/header refusal, redacted custody/write faults, settling reservation, original/peer deadlines, queued late replies, caller death before its queued monitor notification, close/loss and actual token exhaustion. | Exact firmware/network-manager support, update-ID headroom and pacing, installed settling delay, resident security, physical router/sleepy migration and the adopted Zigbee core revision. |
| Explicit key rotation | `key_rotation_test.exs` executes SDK layouts and literal switch/reply vectors, constructor/cohort/sequence bounds, copied-value refusal and same-owner capability expiry. `key_rotation_owner_test.exs` independently frames interviews/adoption, three metadata phases, private update, separately authorized switch and cohort probes. It exercises denied/absent/malformed/raised/thrown/exited/foreign/retained/reused callbacks, private-material exclusion from state/context/results, delay reservations, late returns, caller loss before queued monitor delivery, write faults, metadata truncation, missing/invalid/source-mismatched peers and serial loss. | Exact firmware/security policy, fresh key and active sequence, SSP counter/switch behavior, qualified delays/distribution and independent router/sleepy activation. |
