# WST.02 — Protocol-specific stream profiles and conformance

Version: 0.1.0. Updated: 2026-10-13. Status: accepted target.
Implementation: planned. Evidence: missing.

## Boundary and explicit entry

[WST.01](WST.01-stream-values-and-lifecycle.md) supplies neutral descriptors,
opaque custody, exact epochs, bounded control/frame/queue budgets, current
consumer guards and honest delivery/continuity status. This contract assigns
stream mechanics to exact protocol profiles. It does not declare all streaming
protocols implemented or one universal most-common protocol.

A selected profile MUST have an owning protocol contract before code: exact
standard/source revision, role/direction, discovery/negotiation, security/trust,
parameter and format schemas, packetization/clock rules, supported controls,
timeouts/retry windows, shared resources, cleanup and independent wire vectors.
A package name/version or camera/speaker logo cannot supply a missing field.
Source/codec/helper dependencies are explicit per profile; no broad audio/video
engine becomes a core/Runtime dependency.

## Profile allocations

**WST02-01 — Installed profile.** Registration contains exactly profile reference,
implementation_ref, roles, directions, operations, parameter_schema,
format_contracts, security_contract, timing_contract, resource_contract,
lifecycle_contract and vector_ref. References use WST.01 exact ID/version/digest;
sets are sorted unique. Supplied modules/ports are explicit consumer startup
configuration, never names resolved from this data. A required missing or changed
contract refuses unsupported_profile/stale_basis before private custody resolution.
Role/direction/control/schema are independently checked.

External device profiles map actual model capabilities onto this installed
registration. They cannot invent a stream URI, remote source identity, format,
microphone grant or network trust from a fingerprint. Return private custody
references for sensitive negotiated endpoints; redact URLs/authentication data.
No profile-reader loop enumerates all camera or speaker models.

**WST02-02 — RTP/RTCP.** RFC 3550 provides media packet sequence/timestamp and
RTCP reports; it does not provide reliable delivery or whole-path rendering
guarantees. A qualified RTP profile owns exact payload-type binding, packet
limits, SSRC changes/collisions, sequence/timestamp wrap and reordering windows,
RTCP association/report freshness, transport and any selected security profile.
RTCP source/NTP correlation is retained as protocol information, not proof of
a trusted capture/render clock. SSRC is not a stable authenticated device ID.

Payload remains opaque until an explicit codec/payload-format profile is selected.
Codec-specific fragmentation/reassembly and configuration have exact byte limits
and deadline/loss behavior. Do not guess H.264/PCM/etc. from payload bytes.
Plain RTP and protected SRTP profiles have distinct trust; no security downgrade
is automatic. No receive/drop statistic becomes a frame-render success result.

**WST02-03 — RTSP and ONVIF.** RTSP controls presentation/session establishment;
RTP or another negotiated mechanism carries media. RTSP 1.0 (RFC 2326) and 2.0
(RFC 7826) require separate explicitly qualified profiles; supporting one does not
establish the other. SETUP/PLAY/PAUSE/TEARDOWN/session timeout/authentication and
interleaved/UDP transport rules belong to that exact selected contract.

ONVIF discovery, Media/Media2 configuration, Events and optional PTZ/recording
controls are additional service/binding contracts, not a codec or an assumption
that every camera supports every advertised profile. An ONVIF-returned URI is
private instance evidence, never a publisher-supplied endpoint. Only the selected
supported services are exposed as WoT affordances; unknown controls refuse.
Protocol certification, live streaming, recording and image analysis remain
separate evidence/authority scopes.

For a surveillance assessment, inspect actual ONVIF/RTSP/RTP capabilities first;
ordinary browser delivery is a separate consumer/bridge path. No broad market
share ranking or automatic universal camera support is claimed.

**WST02-04 — WebRTC.** WebRTC is a protocol suite: ICE connectivity, secure media,
DTLS-SRTP key establishment, negotiation and optional SCTP data channels have
distinct contracts. A WebSocket connection or an RTP parser does not establish
WebRTC support. The selected implementation owns congestion/feedback, candidate
handling, trust, channel limits, packet protection and session retirement.

Signaling, TURN/STUN configuration, credentials and allowed destinations are
consumer-owned explicit setup. No public profile enables a relay/proxy or remote
candidate automatically. Application codec/display/inference/recording remain
independent. Browser/native peer and network-path conformance must be tested
before a profile advertises support.

**WST02-05 — Sendspin and device-specific media protocols.** Sendspin's selected
specification defines source/player roles, negotiation, timestamped audio,
clock exchanges and current encryption/pairing requirements. Those protocol
mechanics can be a WoTEx binding. The inspected sendspin-rs server proposal is
unmerged; its protocol parity is an entry audit, not current conformance.
A synchronized-output engine consuming it owns resampling/render tails and
actual cross-device acoustic qualification.

AirPlay/RAOP, Cast and HTTP-pull media require their own exact registrations and
security/session/timing/codec obligations. A helper's DSP/compatibility internals
do not make the whole playback engine a WoTEx responsibility. Adopt only its
declared needed profile with pinned source/notice/custody evidence. Private
credential/pairing channels are required before a helper using secret argv/output
is production-adopted. Native group membership/remote takeover belongs to the
protocol's complete resource/ownership scope, not an inferred brand-wide group.

Classic Bluetooth output, OS audio capture, mixing, tail calibration, audio
decoding/resampling and music/surveillance application workflows belong to the
selected component/host. BLE GATT remains a separate protocol. Recording retention,
object detection and security response policy cannot be encoded as profile-reader
operators or implicitly activated by a negotiated stream.

**WST02-06 — Reuse and failure.** WebSocket/HTTP/MQTT are delivery mechanisms
whose application payload and lifecycle still need exact binding contracts.
A sensor event stream is not automatically a media stream. Share proven bounded
values/custody seams, not one wire protocol across unrelated SDKs.

A changed negotiated format, source/clock epoch, pairing identity, protocol
profile or implementation fences current sessions. Refuse unsupported cells;
never route them to another protocol, decoder or default OS output silently.
Loss/retransmission/reassembly and deadline rules preserve gap/unknown outcomes.
WST.01 guard/ownership cleanup applies, with the exact protocol's remote tail
and cancellation behavior. No unknown handoff becomes a second PLAY/start.

## Acceptance and sources

The initial deliverable is truthful selected-profile allocation and independent
conformance, not all protocols at once. Each later protocol/codec owner freezes
its packet/parameter and state-machine contract under its package before code.
No unspecified parameter schema, decoder or security assumption is left to
device metadata.

| Case | Requirements | Stimulus and falsifier | Evidence |
| --- | --- | --- | --- |
| WST02-T1 | 01–02 | RTP/RTCP independent packets: wrap/collision/reorder/loss, unknown payload and false clock assertion | Exact packet status/gap; no decoder/render inference |
| WST02-T2 | 01, 03 | Independent RTSP versions/negotiations and ONVIF missing service, changed URI/auth/timeouts | Supported cell or explicit refusal; no URI/secret exposure |
| WST02-T3 | 01, 04 | Browser/native WebRTC peers, missing negotiation/keying, denied relay/destination and reconnect | Qualified suite only, current trust and bounded retirement |
| WST02-T4 | 01, 05 | Exact Sendspin peer; helper wrong profile/pairing/clock, changed native group and source takeover | No hidden downgrade, extra target or second start |
| WST02-T5 | 01–06 | Same packet delivery with successful/failed/absent consumer decoder/renderer | Protocol status unchanged; processing/render result stays separate |

Primary standards: [RTP/RTCP RFC 3550](https://www.rfc-editor.org/rfc/rfc3550),
[RTSP 1.0 RFC 2326](https://www.rfc-editor.org/rfc/rfc2326),
[RTSP 2.0 RFC 7826](https://www.rfc-editor.org/rfc/rfc7826),
[WebRTC transports RFC 8835](https://www.rfc-editor.org/rfc/rfc8835),
[ONVIF Profile T](https://www.onvif.org/profiles/profile-t/).
Sendspin research baseline:
[spec ee8aad9](https://github.com/Sendspin/spec/tree/ee8aad9660fc57345e726a888486f47f66a41f97).
ONVIF/service/codec releases are selected and pinned at their own implementation
entry; none is a dependency pin or new executed evidence in this contract.
