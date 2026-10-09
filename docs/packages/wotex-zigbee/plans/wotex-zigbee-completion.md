# Wotex Zigbee completion contract

Version: 1.6.0. The catalogue is authoritative for implementation status.

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

- Finite revision 8 Poll Control Check-in and four explicit client command
  codecs preserve quarterseconds, optional default-response flags and exact
  bytes. Source/custody checks preserve Check-in metadata and a bounded host
  response window. Scripted serial evidence distinguishes NCP admission from
  Default Responses; no automatic response, binding or wakefulness claim occurs.

- Consumer-owned expected reporting/Check-in cadence with explicit per-stream
  intervals and grace, long-period, on-change and disabled modes. Source-checked
  observations preserve raw Events, nulls and partial records; delayed consumption
  does not renew a deadline. Bounded tables, host ordering and explicit owner
  rebind preserve history without an offline claim, polling or delivery side effect.

- Explicit source-guarded Bind/Unbind with explicit consumer-selected targets,
  fixed 23-byte MT layouts resolved against the exact SDK parser, one deadline
  and caller monitor, separate NCP/peer observations and partial unconfirmed
  outcomes. The finite per-epoch retirement table prevents route/operation
  reuse because callbacks omit the ZDO transaction. Scripted serial tests cover
  reply ordering, refusal, timeout/loss, redacted faults and cleanup. No binding
  follows automatically from an interview or reporting configuration.

- Explicit device/network metadata inspection under one deadline and caller
  monitor, with exact SDK layouts, bounded association lists, unchanged raw
  and uninitialized values, sequential consistency comparison and partial
  results on failure. Scripted serial tests preserve available readings across
  expiry/loss while retaining unrelated events. This reads no keys/counters
  and establishes no atomic network image or qualified security continuity.

- Explicit local permit-join and closure requests after fresh expected-network
  readings and consumer credential authorization. The opaque custody port
  starts nothing, returns no private material and supplies a finite horizon
  that shortens dispatch time. Scripted tests distinguish NCP admission from
  uncorrelated responses and local duration changes, and exercise denial,
  redaction, late callbacks and cleanup. This does not qualify resident
  security, install-code/fallback policy or physical closure.

- Explicit channel migration checks fresh network metadata and current peer
  custody before consumer credential authorization, sends one source-pinned
  broadcast/local-copy request, waits once and obtains target-channel metadata
  and per-peer Basic observations. One deadline and fresh retired tokens retain
  partial outcomes, distinct admission/APS/ZCL evidence and unprobed peers.
  The horizon reserves settling time. Any administrative dispatch closes this
  owner after observations without rollback or reset. Scripted tests supply
  software evidence; installed update-ID/pacing/delay, physical router/sleepy
  migration and resident security remain unqualified.

- Explicit finite network-key update/switch uses two authorization phases,
  three fresh network readings, a one-use private consumer key writer and
  qualified distribution/settling reservations under one original deadline.
  Exact SDK source resolves the PDF key-width error and preserves local
  effects despite send failure. Separate admissions and every peer's Basic
  observations remain partial evidence; activation stays unconfirmed.
  Scripted tests cover key exclusion, callback misuse/expiry/faults, caller
  loss, delayed writes and per-peer failures. Any key-write attempt closes
  the owner without retry, rollback or counter reset.

The [pinned SDK persistence review](../decisions/pinned-sdk-persistence.md)
identifies why raw NV commands and a source-default restart increment do not
satisfy backup/restore. `backup_boundary_test.exs` executes refusal at the
ordinary host boundary; it supplies no successful snapshot/restore evidence.
The exact firmware/build and its isolation/counter procedure remain necessary.

## Required for WZG.01 completion

1. Qualify the `Circuits.UART` adapter on macOS and a Nerves target against
   real coordinator hardware, including stable USB identity, exclusive
   ownership, reconnect and permission failure behavior.
2. Pin the exact NCP firmware artifact and digest alongside the host API, then
   run real coordinator tests for startup, version drift, reset, USB removal,
   old-epoch rejection and recovery without implicit network formation.
3. Qualify interview-derived IEEE-to-route custody and event-source matching.
   Qualify the consumer credential custody port for local permit-join and
   resident Trust Center/install-code/fallback policy. Specify backend-supported
   key/counter export/import before backup/restore; public request values must
   continue to exclude key bytes.
4. Qualify the migration custody adapter against the exact firmware's
   network-manager support, current update-ID headroom and administrative
   pacing, installed broadcast delivery delay, resident security and actual
   peer observations. Source defaults and scripted replies do not prove those
   preconditions or physical channel switching.

5. Qualify the rotation custody adapter against exact firmware/build flags,
   active sequence, unique fresh key, resident security/distribution policy,
   pacing and both delays. Independently verify SSP switch/counter behavior
   and router/sleepy-device activation; Basic responses and send statuses
   prove neither the protecting key nor counter continuity.

## Required for WZG.02 completion

1. Pin the adopted Zigbee core specification and qualify the finite ZCL
   revision 8 Basic read profile. Qualify explicit local joining/closure and
   consumer sleepy-device power policy. Bounded descriptor/Basic
   interviews, adopted route custody, duplicate identity handling and finite
   record-by-record writes/reporting configuration, expected reporting/Check-in
   cadence, bounded downlinks and explicit finite Bind/Unbind workflows are
   implemented in software. Explicit local permit-join now uses fresh expected
   network readings and consumer credential authorization with finite horizons;
   remote/broadcast scopes and actual enrollment/closure remain unqualified.
   Physical qualification, binding destinations and power-policy evidence
   remain outstanding.
2. Implement network custody and backup/restore with key and counter
   continuity, old-coordinator isolation, explicit permit-join and no silent
   security downgrade. Exercise stale backups and concurrent coordinator
   negatives before exposing administrative commands.
3. Qualify the implemented finite channel-migration workflow and its per-peer
   partial outcomes on real routers and sleepy devices. Qualify the implemented
   finite key-update/switch workflow and its separate per-device observations,
   then implement explicit continuity recovery. Scripted migration/rotation
   checks exercise manufacturer/header and malformed-value refusal, private
   key custody and failure cleanup; they establish no physical migration,
   key activation or counter continuity.

## Required for WZG.03 completion

Record exact cohort identity and run an independent real NCP, a mains-powered
endpoint and a sleepy sensor. Exercise interview, reporting, USB/power loss,
restart, backup/restore, slow consumers and reporting soak. Mark physical and
certification evidence separately. The simulated peer and pure benchmarks do
not establish real radio behavior, battery life or safety-device function.
