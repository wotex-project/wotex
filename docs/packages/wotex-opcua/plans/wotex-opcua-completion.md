# Wotex OPCUA completion contract

Plan version: 1.1.0. Package baseline: 0.1.0.

Revision 1.1.0 records the monorepo layout without changing any obligation.
Documentation now lives under `docs/packages/wotex-opcua/`. Package archives no
longer ship Markdown documentation, governance files or agent files;
specifications are published through HexDocs. Fixtures and machine-read
provenance ship under `priv/`. The repository-level gate
(`WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-opcua`) and the CI
lanes now discharge `repository_green` and `archive_consumer_green`. Tags use
`wotex-opcua-v<version>`.

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
[WOP.00](../specs/WOP.00-library-contract.md) and
[WOP.10](../specs/WOP.10-software-contract.md), plus
[WOP.11 standalone client and preservation](../specs/WOP.11-standalone-client-and-preservation.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The [WOP.12 integration contract](../specs/WOP.12-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are mandatory.
[WOP.13](../specs/WOP.13-native-executable.md) fixes the open62541 executable,
source digests, build tasks and native acceptance corpus. Python is an independent
software peer and build-generator dependency only in the accepted target.
The removed Python adapter did not satisfy that target. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.
