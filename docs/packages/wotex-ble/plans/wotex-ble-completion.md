# Wotex BLE completion contract

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

Consumer policy, deployment and publication are outside this repository.
The source, specifications and evidence contain no consumer-specific metadata.

## Evidence rules

Every advertised behavior must name executable tests and exact standard
revisions. Negative responses and timeouts fail interoperability assertions.
Hardware tests require explicit target configuration; default tests never
contact a physical target. An injected response simulator proves adapter contracts only. Real upstream
software stacks using virtual controllers/radios can prove the explicitly
labelled software interoperability cells; they do not prove physical RF behavior.
Mutable audit notes remain in ignored `docs/tasks/local/`; this document is a
durable acceptance contract, not a progress tracker.

The concrete software scope, API and state-machine decisions are in
[WBL.00](../specs/WBL.00-library-contract.md) and
[WBL.10](../specs/WBL.10-software-contract.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The mandatory target also includes [WBL.11 standalone API and preservation](../specs/WBL.11-standalone-client-and-preservation.md).
The ordered software plan assigns its N requirements and concrete F cases to
implementation packages; parsed fixtures and scenario identifiers alone do not
accept those packages.

The [WBL.12 integration contract](../specs/WBL.12-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are also mandatory. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.

The [WBL.13 native backend contract](../specs/WBL.13-native-backend.md)
requires a first-party compiled Port and Mix/ExUnit software tooling.
Python is permitted only for required upstream build tools or an explicitly
justified independent software peer. It is not part of production execution.
