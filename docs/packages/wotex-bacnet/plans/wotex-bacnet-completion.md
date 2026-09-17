# Wotex BACnet completion contract

Plan version: 1.1.0. Package baseline: 0.1.0. Normative owner:
[specification catalogue](../specs/catalogue.yaml).

Revision 1.1.0 records the repository move and changes no acceptance
obligation. Documentation now lives under `docs/packages/wotex-bacnet/`.
Package archives no longer ship Markdown documentation, governance files or
agent files; specifications are published through HexDocs. Fixtures and
machine-read provenance ship under `priv/`. The repository-level gate
(`WOTEX_PATH_DEPS=1 mix check --no-retry` from `packages/wotex-bacnet`) and the
CI lanes now discharge `repository_green` and `archive_consumer_green`. Tags
use `wotex-bacnet-v<version>`.

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
Mutable audit notes remain in the ignored root `docs/tasks/local/wotex-bacnet/`;
this document is a durable acceptance contract, not a progress tracker.

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
`mix wotex.software.run --workspace ABS`; their accepted source-bound cohorts are
recorded in executable evidence and they remain outside production runtime work.
