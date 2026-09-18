# Wotex CoAP completion contract

Plan version: 1.2.0. Package baseline: 0.1.0.

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
publication are outside this package. Do not import consumer history or
metadata into this package's neutral history.

## Evidence rules

Every advertised behavior must name executable tests and exact standard
revisions. Negative responses and timeouts fail interoperability assertions.
Hardware tests require explicit target configuration; default tests never
contact a physical target. An injected response simulator proves adapter contracts only. Real upstream
software stacks using virtual controllers/radios can prove the explicitly
labelled software interoperability cells; they do not prove physical RF behavior.
Mutable audit notes remain in the ignored root `docs/tasks/local/wotex-coap/`; this document is a
durable acceptance contract, not a progress tracker.

The concrete software scope, API and state-machine decisions are in
[WCO.01](../specs/WCO.01-library-contract.md) and
[WCO.05](../specs/WCO.05-software-contract.md), plus the mandatory
[WCO.06 standalone/preservation contract](../specs/WCO.06-standalone-client-and-preservation.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The [WCO.07 integration contract](../specs/WCO.07-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are also mandatory. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.

[WCO.08](../specs/WCO.08-native-build-and-software-evidence.md) defines native build and software
runner contracts. Mix/ExUnit owns orchestration; BEAM/OTP and the explicitly
selected native SDK own protocol execution.
