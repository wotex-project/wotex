# Wotex Modbus completion contract

Plan version: 1.1.0. Package baseline: 0.1.0. Normative owner:
[specification catalogue](../specs/catalogue.yaml).

Graduate this library independently. Acceptance requires typed values and
conversion, exact-revision protocol rules, Form mapping with extension
preservation, structured errors, explicit OTP ownership and cleanup, neutral
telemetry, unit/property/malformed-frame/lifecycle tests and an independent
protocol peer software interoperability lane. Physical-device validation is
separate and does not block the defined software milestone.

A compatibility adapter exposes `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
Wire acknowledgements never establish application truth. Unsupported operations
return an explicit error or the documented optional `:not_supported` sentinel.

The consumer keeps its implementation until differential scenarios and real
interoperability prove the supported scope. Consumer changes, deployment and
publication are outside this repository. Do not import consumer history or
metadata into this neutral history.

## Evidence rules

Every advertised behavior must name executable tests and exact standard
revisions. Negative responses and timeouts fail interoperability assertions.
Hardware tests require explicit target configuration; default tests never
contact a physical target. An injected response simulator proves adapter contracts only. Real upstream
software stacks using virtual controllers/radios can prove the explicitly
labelled software interoperability cells; they do not prove physical RF behavior.
Mutable audit notes remain in the ignored root `docs/tasks/local/wotex-modbus/`;
this document is a durable acceptance contract, not a progress tracker.

The concrete software scope, API and state-machine decisions are in
[WMB.01](../specs/WMB.01-library-contract.md) and
[WMB.04](../specs/WMB.04-software-contract.md), plus the mandatory
[WMB.05 standalone/preservation contract](../specs/WMB.05-standalone-client-and-preservation.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The [WMB.06 integration contract](../specs/WMB.06-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are also mandatory. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.

[WMB.07](../specs/WMB.07-native-build-and-software-evidence.md) defines native build and software
runner contracts. Mix/ExUnit owns orchestration; BEAM/OTP TCP owns protocol
execution, and the libmodbus C peer is an independent test fixture.

The final WMB-P07 package cell installs exact core, Runtime and Modbus candidate
archives through an isolated temporary Hex registry and exercises the public
boundary from a clean consumer. This is local release-candidate verification,
not publication or evidence of public-registry availability.

WMB-P08 reconciles that candidate with its package metadata and consumer-visible
API behavior, dependency and toolchain lanes, legal/security boundary, standards
scope and explicit nonclaims. The resulting dossier is a verification map, not
release, publication or external-adoption evidence.
