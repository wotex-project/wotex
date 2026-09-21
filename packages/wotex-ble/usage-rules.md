# Wotex BLE usage rules

These rules describe the completed WBL.01–WBL.07 contract. The package
catalogue records implementation status separately.

- Use the first-party persistent BlueZ client with an explicit peer, bus,
  native executable and guardian identity. Choose owned or borrowed link
  lifecycle explicitly; loading the package starts none of them.
- Discover a bounded connected-peer snapshot and retain its generation. Do not
  infer a characteristic from display names, UUID alone or discovery order,
  and reject stale discovery addresses.
- Perform typed reads and acknowledged writes with explicit value type, byte
  order and deadline. A write has no automatic readback or retry.
- Route every pairing decision through the supplied `Wotex.BLE.Agent`. Reject
  unsupported methods, policy timeout or policy failure, and keep challenge
  values out of ordinary request and error data.
- Supervise notification subscriptions, preserve distinct Value changes and
  close with the matching sender and generation. Do not synthesize an initial
  read or claim exactly-once delivery.
- A BlueZ acknowledgement or bond does not authorize another operation or prove
  a physical effect. The consumer owns policy, credentials and canonical state.
