# Wotex BLE completion contract

Plan version: 1.7.0. Package baseline: 0.1.0.

The [WBL.08 successor](../specs/WBL.08-write-modes-and-native-hosts.md) is partial.
Its explicit BlueZ modes, command flag/current-MTU admission and native queue
evidence are implemented through the public API, Runtime and native bridge.
The focused suite and real private D-Bus/native lane exercise these boundaries;
their [exact evidence](../provenance/write-modes-2026-10.md) does not establish
controller/RF behavior. The independent [archive consumers](../provenance/write-mode-archives-2026-10.md)
now pass passive loading, all ten behavioral cases and four assertion-only
mutation runs against exact extracted packages. Continue with installed BlueZ
qualification and the explicitly selected CoreBluetooth host and installed
Mac lifecycle/readiness corpus. WBL08-T1–T5 remain the complete obligations.

The [CoreBluetooth operation contract](../specs/WBL.08-corebluetooth-host-v1.md)
and portable native component now supply mode/length/readiness admission,
ticket-bound callbacks, an original deadline and confirmed-retirement gating.
Fourteen independent scripted-port cases pass in ordinary and sanitizer builds.
The framework-linked SDK owner now implements explicit permission/pairing entry,
bounded complete discovery, per-mode SDK submission and actual callback/object
retirement. Twenty-four injected-selector cases join the fourteen operation cases.
The native process now implements revision-1 bounded IPC, reserved nonblocking
output, original deadlines, exact generation/route validation and joined close.
Its explicit offline macOS builder embeds usage metadata, audits the binaries,
probes closed-input startup and refuses altered artifact reuse. Ten independent
process cases and three build cases cover these source paths. The explicit
public Client now joins pure private Peer/discovery values, bounded session
ownership, typed reads, both write modes and point Runtime operations. Thirteen
Client cases use an independent process peer and the production Host loop;
the [Client record](../provenance/corebluetooth-client-2026-10.md) binds actual
commands, committed source and limits. Native notification ownership now uses
the actual SDK toggle/state/value selectors, explicit mode selection, one
control deadline, sixteen live streams and 64 shared report credits. Early
reports wait for establishment; cumulative acknowledgement and retained stopped
credit prevent unbounded delivery. The literal mode/control corpus and eight
notification case families exercise that SDK seam; the
[SDK notification record](../provenance/corebluetooth-notifications-2026-10.md)
binds the executed inputs and limits. Continue with the Host/Client streaming
join, explicit sleep observation, independent CoreBluetooth archive consumers
and installed Mac lifecycle/readiness qualification. Software point sessions establish no
actual permission/peripheral or RF result.
The [native process/build record](../provenance/corebluetooth-host-2026-10.md)
binds their exact source, archive and executed checks.

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
Mutable audit notes remain in the ignored root `docs/tasks/local/wotex-ble/`; this document is a
durable acceptance contract, not a progress tracker.

The concrete software scope, API and state-machine decisions are in
[WBL.01](../specs/WBL.01-library-contract.md) and
[WBL.04](../specs/WBL.04-software-contract.md). Follow the
[ordered implementation sequence](software-implementation.md) for required
software fixtures, vector traceability, validation and local commits.

The mandatory target also includes [WBL.05 standalone API and preservation](../specs/WBL.05-standalone-client-and-preservation.md).
The ordered software plan assigns its N requirements and concrete F cases to
implementation packages; parsed fixtures and scenario identifiers alone do not
accept those packages.

The [WBL.06 integration contract](../specs/WBL.06-wotex-integration.md) and
[versioned catalogue](../specs/catalogue.yaml) are also mandatory. Acceptance
requires both native protocol workflows and supported cells through public core/Runtime
APIs. Dependency artifacts and local source evidence remain separately identified.

The [WBL.07 native backend contract](../specs/WBL.07-native-backend.md)
requires a first-party compiled Port and Mix/ExUnit software tooling.
Repository-owned runtime and fixture code is restricted to Elixir, Rust, C and
C++. Python is permitted only when an immutable upstream build generator
requires it; it is not part of production or fixture execution.
