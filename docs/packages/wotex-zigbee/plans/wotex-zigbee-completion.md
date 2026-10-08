# Wotex Zigbee completion contract

Version: 0.9.0. The catalogue is authoritative for implementation status.

## Delivered software slice

- TI CC26x2 SDK 2.30.00.34 ZNP Monitor/Test framing (SWRA198 revision 1.14),
  exact `SYS_VERSION` admission, one explicit owner and finite queues.
  Startup preserves one deadline through serial open/write/version delivery,
  monitors negotiating callers and redacts callback failures. Caller-owned
  opening retains the original budget through handle handoff, establishes its
  link before delivery and closes on normal or abnormal caller exit. Linked
  adapter loss fails pending operations with redacted cleanup. Explicit close
  reports failure and attempts acquired-port cleanup once.
- Non-administrative IEEE identity, node, active-endpoint, simple-descriptor and AF data requests.
  Synchronous reply and later indications remain distinct. Finite ZDO
  identity and descriptor responses decode into typed values. The owner
  revalidates complete commands against this finite profile before serial I/O.
- One owner-backed interview obtains matched IEEE/node/endpoint descriptors
  and selected Basic attributes under one deadline and caller monitor. It
  preserves partial outcomes, duplicates, unknown profiles and unrelated
  queued events. Route and AF/ZCL token retirement remain finite per epoch.
- Selected Basic client reads are pinned to ZCL document 07-5123 revision 8,
  with source provenance and independently framed scripted-peer tests.
- Bounded ZCL global Read Attributes request and response/report decoding for
  an explicit scalar and short-string type subset. Pinned revision 8
  non-values remain null with their original bytes; adopted full-range numeric
  attributes use explicit caller policy. Unknown widths retain the opaque
  remainder; malformed known types fail.
- Simulated serial peer with its own frame builder, malformed/fragmented byte
  tests, serial loss and timeout tests and coverage. The pure-code benchmark
  is a historical baseline; the changed ZCL codec and configuration profile
  have not been benchmarked.
- Inert revision 8 ordinary writes, send/receive reporting configuration and
  reporting readback with finite records and exact frame budgets. Explicit
  interval modes, scalar non-values and partial record outcomes retain raw
  evidence. Source/header matching uses adopted custody and the original AF
  context. Scripted peer tests distinguish dispatch, NCP admission, APS and
  ZCL observations. The consumer owns authorization, a finite correlation
  window and distinct transaction/sequence context; no binding or automatic
  retry occurs.
- `Circuits.UART` adapter for macOS/Linux with exact USB VID/PID/serial-number
  selection, exclusive open, post-open identity check, byte/error forwarding
  and owner-linked cleanup. A mocked UART exercises the adapter and an
  end-to-end `SYS_VERSION` handshake; no real coordinator was attached.
- A bounded AF data request carries durable EUI-64 peer identity, current
  route and caller correlation while sending only ZNP-defined fields on the
  wire.
- An inert consumer-owned route ledger explicitly adopts complete interviews,
  replaces a rejoined identity's route, quarantines conflicting claims and
  fences source resolution by owner epoch, expiry, time and bounded sequence.
  Guarded AF sends check the current supplied table before I/O and clamp their
  deadline to custody expiry. Consumers retain the latest table, including
  conflict updates; host custody does not establish radio authentication.

- Consumer-owned downlink queues bound global/per-peer counts, payload bytes
  and finite lifetimes. Explicit FIFO selection, expiry, cancellation and
  epoch invalidation retain removal receipts. Selected commands check current
  custody and use absolute receiver deadlines through mailbox and serial
  delivery. No automatic wakeup, polling, retry or reachability claim occurs.

## Required for WZG.01 completion

1. Qualify the `Circuits.UART` adapter on macOS and a Nerves target against
   real coordinator hardware, including stable USB identity, exclusive
   ownership, reconnect and permission failure behavior.
2. Pin the exact NCP firmware artifact and digest alongside the host API, then
   run real coordinator tests for startup, version drift, reset, USB removal,
   old-epoch rejection and recovery without implicit network formation.
3. Qualify interview-derived IEEE-to-route custody and event-source matching.
   Specify the coordinator's credential custody port before network
   administration; public request values must continue to exclude key bytes.

## Required for WZG.02 completion

1. Pin the adopted Zigbee core specification and qualify the finite ZCL
   revision 8 Basic read profile. Implement explicit joining,
   binding and sleepy-device freshness policy. Bounded descriptor/Basic
   interviews, adopted route custody, duplicate identity handling and finite
   record-by-record writes/reporting configuration are implemented in software.
   Physical qualification, binding destinations and power-policy evidence
   remain outstanding.
2. Implement network custody and backup/restore with key and counter
   continuity, old-coordinator isolation, explicit permit-join and no silent
   security downgrade. Exercise stale backups and concurrent coordinator
   negatives before exposing administrative commands.
3. Add explicit channel migration/key rotation results with per-device
   partial outcomes, and test manufacturer extensions and malformed values.

## Required for WZG.03 completion

Record exact cohort identity and run an independent real NCP, a mains-powered
endpoint and a sleepy sensor. Exercise interview, reporting, USB/power loss,
restart, backup/restore, slow consumers and reporting soak. Mark physical and
certification evidence separately. The simulated peer and pure benchmarks do
not establish real radio behavior, battery life or safety-device function.
