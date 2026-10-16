# Generic protocols, external profiles and stream ownership

Decision GP-ADR@1.1.0. Updated: 2026-10-16. Status: accepted target.
Implementation: the bounded WPF reader/compiler/authoring package is registered
and implemented; protocol streams and wider consumer qualification remain planned.

## Intent and controlling boundary

The family serves industrial and other IoT consumers. Its size follows reusable
protocol and interpretation mechanisms, not the number of sensor models in the
world. A consumer may select only core values, one protocol, a profile reader or
an optional engine. The repository remains independent Mix projects; loading a
library performs no I/O or automatic registration.

This decision controls new package allocation and profile/stream interpretation.
It refines the [portable delivery decision](portable-delivery-decision.md).
Implemented public representations retain their owning contracts; a new target
does not relabel them as implemented or widen their accepted inputs.

## Four separate artifacts

| Artifact | Owner and allowed content |
| --- | --- |
| Protocol implementation | WoTEx or another explicitly installed producer: framing, correlation, standard protocol vocabulary, security/session mechanics, negotiated timing and bounded cleanup |
| Profile-reading/authoring protocol | Registered `wotex_profiles`: closed grammar, schemas, deterministic validator/compiler, contract export, identity finalization and inert projections |
| Device/sensor/semantic definition | Consumer-owned profiles/model templates: model/firmware mappings, quantities, channels, units, selectors, model restrictions and attributed evidence |
| Operational application/component | Consumer or independently selected producer: instance identity, custody, canonical state, authorization, deployment policies, business workflows, media processing and UI |

There is no WoTEx catalogue of every sensor, manufacturer or quantity kind.
Public templates live in the consumer's release; generated/customer/installation
drafts live in consumer-private custody. A separate definitions repository or
shared catalogue is not required. Optional third-party exports are explicitly
imported with their own versions/notices and local validation/review. WoTEx ships
standard protocol vocabularies and minimal attributed conformance vectors, not
an authoritative worldwide model database. An SDK's required protocol tables
are not permission to import unrelated vendor device catalogues.

[WPF.03](../packages/wotex-profiles/specs/WPF.03-profile-authoring-contract.md)
exports an exact installed contract for manual/AI authors and shares the same
pure validation path with CI/import/runtime. The consumer chooses source data,
generation capability, review and activation; schemas/model scores cannot
qualify a physical mapping or authorize control. The
[research decision](consumer-profile-authoring-research.md) owns the evidence
and alternative analysis. Drafting works with AI absent.

## Addition rules

A new model using an installed binding and supported value contract supplies
external profile data and independent vectors. A new quantity supplies an
external exact semantic/unit descriptor; its names are never library atoms.
A new binary layout supplies bounded installed selector data where sufficient,
otherwise a separately qualified codec contract. A new protocol, stateful SDK,
privileged action or unsupported mathematical operator needs producer code and
an owning contract before implementation. Data cannot invent an operation.

A Thing composes explicit channels/capabilities; no global SensorType enum or
mandatory module per model exists. Parsing an unfamiliar descriptor establishes
its structure, not physical meaning, trust, enrollment or permission to write.
A consumer decides which semantic definitions it accepts and what they mean in
its application. Unknown optional information remains inert; unknown required
mechanics or contract closure refuse. Unsupported controls cannot become no-ops.

## Logic placement and common values

Protocol-specific state machines, authentication, source continuity, packet
correlation and retry constraints stay with their protocol owner. Profile readers
perform only installed bounded operations over explicit inputs. External
definitions supply unit dimensions, quantity identities, invalid sentinels and
model ranges; readers do not infer them from names or raw numbers.

Current WRO.01 Unit/Basis/Fact are the first routine representation, not the
family's exhaustive sensor ontology. The [external-input join](../packages/wotex-routines/specs/WRO.05-external-profile-inputs.md)
requires explicit conversion or unsupported refusal. Profile readers remain
usable without routines. Continuum owns its wire envelopes; preserving a value
does not establish canonical observations. Extract common code only after
independent producer/consumer joins demonstrate the seam; do not add competing
unit, fact or receipt formats under a universal label.

Consumer authorization and journal boundaries remain outside all generic
libraries. Generic rules may compute transitions, and an explicitly selected
component may process samples under a current capability. Neither owns the
consumer's credentials, database or approval decision. Machine-specific recipes,
maintenance workflows, safety assumptions and deployment thresholds stay with
the consumer/qualified controller.

## Streaming allocation

Streaming denotes a negotiated session and bounded delivery lifecycle; it is
not synonymous with audio, video or sensor telemetry. Prospective
[WST.01–02](../packages/wotex-streams/specs/WST.01-stream-values-and-lifecycle.md)
own neutral stream values and allocation of protocol-specific profiles.
RTP/RTCP, RTSP, WebRTC, Sendspin and other bindings remain separately negotiated
and qualified; there is no automatic translation or universal wire framing.

WoTEx may own protocol-required packetization, reassembly, security, timing
reports and finite buffering. Decode/encode, mixing, resampling, speaker-tail
calibration, recording retention, surveillance inference and playback-group
policy belong to a separately selected component/consumer. A codec needed for a
protocol exchange is an explicit optional dependency of that profile, not a
mandatory engine in Runtime. Packet delivery, protocol clock correlation and
physical render alignment remain different claims.

The former prospective `wotex_audio` full-engine allocation is superseded.
Its unimplemented engineering requirements move to the consuming project's
component contract; no audio source package or family registration existed.
A protocol-centric media integration can later use the streams seam without
putting a complete playback/surveillance platform into WoTEx.

## Scale and qualification

Profile count, deployed instance count, active sessions and samples/second are
different workload dimensions. Compile an explicit selected closure, not a scan
of a whole catalogue. Limits apply per call/host/selected cohort; a reader's
bounded page never establishes a limit on all possible device types.

Consumers own buses, gateways, physical resource arbitration, tenancy, trusted
clock inputs, artifact selection, persistence and supervision. Bindings expose
limits and honest loss/continuity so consumers can budget shared resources.
High-rate processing can use an explicit native backend outside the BEAM;
no hard-real-time, safety certification or physical qualification follows from
Elixir supervision, descriptors or software peer tests.

## Delivery and falsifiers

The [delivery plan](generic-protocol-profile-delivery.md) orders the work.
Before new code, freeze its schemas and independent vectors in the owning
package's `priv/`. WPF already has its registered source, schemas and vectors;
register the prospective streams package only when scaffolding is undertaken. Root/generated catalogues must not
claim prospective packages exist.

Acceptance includes two independent consumers: one industrial multi-channel
example and one different application, both supplying external definitions.
Add an unseen quantity/model without changing the reader; refuse an unknown
operator/protocol rather than executing text. Revoke or replace profile/route
basis during work; no stale result or second effect is accepted. Test malformed,
cyclic and over-budget closure, source gaps and independent value conversion.

This is a target decision and design review, not new executed evidence.
Referenced standards motivate boundaries: [W3C WoT Architecture 1.1](https://www.w3.org/TR/2023/REC-wot-architecture11-20231205/),
[EdgeX external device profiles](https://docs.edgexfoundry.org/4.0/microservices/core/metadata/details/DeviceProfile/),
[IO-Link device descriptions](https://io-link.com/technology/iodd),
[RTP/RTCP](https://www.rfc-editor.org/rfc/rfc3550).
