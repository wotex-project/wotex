# Wotex OPCUA completion contract

Plan version: 1.1.0. Package baseline: 0.1.0.

The independent library acceptance contract requires typed values and
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
Consumer changes, deployment and publication are outside this package.

## Evidence rules

Every advertised behavior must name executable tests and exact standard
revisions. Negative responses and timeouts fail interoperability assertions.
Hardware tests require explicit target configuration; default tests never
contact a physical target. An injected response simulator proves adapter contracts only. Real upstream
software stacks using virtual controllers/radios can prove the explicitly
labelled software interoperability cells; they do not prove physical RF behavior.
Mutable audit notes remain in the ignored root `docs/tasks/local/wotex-opcua/`; this document is a
durable acceptance contract, not a progress tracker.

The concrete software scope, API and state-machine decisions are in
[WOP.01](../specs/WOP.01-library-contract.md) and
[WOP.04](../specs/WOP.04-software-contract.md), plus
[WOP.05 standalone client and preservation](../specs/WOP.05-standalone-client-and-preservation.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The [WOP.06 integration contract](../specs/WOP.06-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are mandatory.
[WOP.07](../specs/WOP.07-native-executable.md) fixes the open62541 executable,
source digests, build tasks and native acceptance corpus. Repository-owned
runtime and peer code is Elixir, Rust or C; Python remains only an upstream SDK
generator and isolated audit tool. The removed Python adapter and peer do not
satisfy independent-stack acceptance. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.
