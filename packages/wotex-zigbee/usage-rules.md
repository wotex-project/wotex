# Wotex Zigbee usage rules

These rules describe the completed normative usage contract. The package
catalogue records implementation status separately.

- Supply a `Wotex.Zigbee.SerialPort` adapter, exact hardware identity and
  exact five-byte firmware version. Match a reconnected adapter to that
  identity before opening a new owner epoch.
- Start an owner explicitly with `Wotex.Zigbee.open/1` or under a consumer
  supervisor. Keep the serial device exclusively owned; close a handle after
  use. A stale handle cannot address a restarted owner.
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
- Use bounded deadlines and queues. A timeout ends the owner epoch so a
  delayed uncorrelated SRSP cannot satisfy a later command.
