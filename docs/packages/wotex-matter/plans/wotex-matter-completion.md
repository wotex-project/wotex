# Wotex Matter completion contract

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

Consumer policy, deployment and publication are outside this package.
The source, specifications and evidence contain no consumer-specific metadata.

## Evidence rules

Every advertised behavior must name executable tests and exact standard
revisions. Negative responses and timeouts fail interoperability assertions.
Hardware tests require explicit target configuration; default tests never
contact a physical target. An injected response simulator proves adapter contracts only. Real upstream
software stacks using virtual controllers/radios can prove the explicitly
labelled software interoperability cells; they do not prove physical RF behavior.
Mutable audit notes remain in the ignored root `docs/tasks/local/wotex-matter/`;
this document is a durable acceptance contract, not a progress tracker.

The concrete software scope, API and state-machine decisions are in
[WMA.01](../specs/WMA.01-library-contract.md) and
[WMA.05](../specs/WMA.05-software-contract.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The mandatory target also includes [WMA.06 standalone API and preservation](../specs/WMA.06-standalone-client-and-preservation.md).
The ordered software plan assigns its N requirements and concrete F cases to
implementation packages; parsed fixtures and scenario identifiers alone do not
accept those packages.

The [WMA.07 integration contract](../specs/WMA.07-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are also mandatory. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.

The [WMA.08 native backend contract](../specs/WMA.08-native-backend.md)
requires a first-party compiled Port and Mix/ExUnit software tooling.
Python is permitted only for required upstream build tools or an explicitly
justified independent software peer. It is not part of production execution.
