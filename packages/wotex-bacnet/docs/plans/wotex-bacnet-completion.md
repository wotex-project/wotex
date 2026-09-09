# Wotex BACnet completion contract

The independent BEAM library acceptance contract requires typed values and
conversion, exact-revision protocol rules, Form mapping with extension
preservation, structured errors, explicit OTP ownership and cleanup, neutral
telemetry, unit/property/malformed-frame/lifecycle tests and an independent
protocol peer software interoperability lane. Physical-device validation is
separate and does not block the defined software milestone.

A compatibility adapter exposes `capabilities/0`, `connect/1`, `send/2`,
`receive/2`, `disconnect/1`, `health_check/1`, `subscribe/2`, `unsubscribe/2`.
Wire acknowledgements never establish application truth. Unsupported operations
return an explicit error or the documented optional `:not_supported` sentinel.

Consumer integration requires its own differential and interoperability evidence.
Consumer changes, deployment and publication are outside this repository.

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
[WBA.00](../specs/WBA.00-library-contract.md) and
[WBA.10](../specs/WBA.10-software-contract.md), plus
[WBA.11 standalone client and preservation](../specs/WBA.11-standalone-client-and-preservation.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The [WBA.12 integration contract](../specs/WBA.12-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are also mandatory. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.

The production runtime uses BACstack and owned BEAM transport. WBA-S03a defines
consumption-based UDP ingress and validated borrowed receive-policy limits.
The native C stack is an independent software peer only. Required fixture tasks
are `mix wotex.software.build --workspace ABS` and
`mix wotex.software.run --workspace ABS`; they are specified implementation work.
