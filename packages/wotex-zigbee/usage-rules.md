# Wotex Zigbee usage rules

These rules describe the completed normative usage contract. The package
catalogue records implementation status separately.

- Supply a `Wotex.Zigbee.SerialPort` adapter, exact hardware identity and
  exact five-byte firmware version. Match a reconnected adapter to that
  identity before opening a new owner epoch.
- Start an owner explicitly with `Wotex.Zigbee.open/1` or under a consumer
  supervisor. Keep the serial device exclusively owned; close a handle after
  use. A stale handle cannot address a restarted owner.
  Caller-owned opening links before handle delivery and closes on normal or
  abnormal caller exit. Copying its handle does not transfer that lifetime;
  use a consumer-supervised child specification for shared long-lived use.
- Treat an SRSP as request admission by the NCP. Match later APS/ZDO/ZCL
  indications with source, endpoint, cluster, sequence and transaction
  context. Count dropped indications before trusting a continuous view.
- Use `Wotex.Zigbee.DataRequest` for AF traffic that must retain interviewed
  EUI-64 peer identity and caller correlation. Explicitly adopt a complete
  interview with `Wotex.Zigbee.Routes`; retain its latest table, including
  conflict updates. Use `Wotex.Zigbee.send_routed_data/4` to check that table
  at the serial receiver. Neither IEEE identity nor a route authenticates a
  report.
- Use `Wotex.Zigbee.Interview` with an expected IEEE, a candidate unicast
  route and a registered local AF endpoint for bounded descriptor/Basic
  inspection. Check partial issues and original duplicate/conflicting claims
  before adopting a route. Each owner epoch has finite route/token slots;
  an interview cannot reuse a previously queried route in that epoch.
- Supply monotonic time and a finite custody lifetime from the identity
  observation. Resolve source Events through current custody without
  upgrading their security disposition. Rebind and interview again after
  replacing an owner. Custody expiry does not declare a sleepy device offline.
- Limit commands to the documented ZDO and AF profile. Network formation,
  reset, restore, permit-join and key changes require a separate explicit
  administrative profile and authorization.
- Keep keys and counters in consumer-controlled custody. Do not clone a live
  coordinator or restore an old counter state. A 16-bit network address is
  only a route; use stable IEEE identity for durable device records.
- Treat incoming frames, manufacturer strings and security metadata as
  untrusted observations. Apply product and Thing policy outside this
  package. A successful radio command does not prove physical effect.
- Preserve ZCL nulls, read failures, raw bytes and unsupported tails. Select
  full-range numeric attribute IDs explicitly in `ZCL.decode_attributes/3`
  only when the adopted definition uses that range. The codec does not infer
  cluster or manufacturer semantics.
- Authorize writes and reporting changes explicitly before putting a
  `Wotex.Zigbee.ZCL.Configuration` request payload in a `DataRequest`.
  Retain both values and actual send/NCP/APS observations. Use `observe/5`
  with current custody for source/header matching and ordered record outcomes;
  the consumer owns finite deadlines and distinct transaction/sequence context.
  Matching alone does not prove dispatch or prevent replay. Default Responses,
  ambiguous omissions and unsupported configurations remain unconfirmed.
- Set send/receive reporting intervals explicitly and qualify cluster limits,
  binding destinations and battery impact. Maximum `0xFFFF` disables reporting;
  minimum `0xFFFF` with maximum zero restores defaults. Both modes require
  analog change zero. No retry, binding or polling follows from construction
  or observation.
- Authorize and qualify each Bind/Unbind destination before constructing
  `Wotex.Zigbee.Binding` and calling `Wotex.Zigbee.change_binding/4` with
  current source custody. Keep the request, NCP admission and peer status
  separate. The callback echoes no binding fields or transaction and supplies
  no security flag. Each route/operation pair is retired within its owner
  epoch, including unsolicited callbacks; reuse requires a fresh owner and
  custody. Peer status does not prove future reporting or battery suitability.
- Use bounded deadlines and queues. A timeout ends the owner epoch so a
  delayed uncorrelated SRSP cannot satisfy a later command.
- Retain the latest `Wotex.Zigbee.Downlinks` queue, expire requests explicitly
  and select a bounded peer FIFO only under consumer delivery policy. Send
  ready receipts through `Wotex.Zigbee.send_queued_data/4` with current custody
  to preserve absolute expiry. Selection and expiry prove no wakefulness,
  delivery or offline status. Rebind after owner replacement; queued routes
  are never retargeted automatically.
- Keep `Wotex.Zigbee.ZCL.PollControl` arguments in quarterseconds and
  interpret zero by the specific command. Check-in observation preserves
  source metadata and a finite host response window; it proves no wakefulness.
  Authorize response/interval/stop commands explicitly and qualify server
  limits, bindings and battery impact. No automatic response follows decoding.
- Arm `Wotex.Zigbee.Freshness.Policy` expectations per selected report or
  Check-in stream, with qualified intervals and grace rather than a universal
  inactivity timeout. On-change and disabled modes have no periodic deadline.
  Retain every returned cadence table, including snapshots, and supply
  monotonic time. Null renews packet cadence while remaining unavailable data;
  ambiguous and opaque records retain evidence without renewing it. A late
  window proves no offline state or reachability. Rebind after owner
  replacement and retain dropped-event evidence separately. No cadence
  operation sends, polls, changes intervals or attempts queued downlinks.
- Keep serial open, version negotiation and callback cleanup within the
  configured startup budget, including handle handoff. A ready wait cannot
  renew that budget. An adapter must clean up resources if open fails before
  returning a port.
  Treat an explicit close error as unconfirmed adapter cleanup.
