# Wotex MQTT Binding usage rules

These rules describe the completed WBM.01–WBM.03 contract. The package
catalogue records implementation status separately.

- Obtain the binding profile from `Wotex.Binding.MQTT` and provide
  `Wotex.Binding.MQTT.Client` explicitly. The binding starts no broker session.
- Apply only the seven specified operation mappings. Preserve the exact
  `mqv:retain`, `mqv:controlPacket`, `mqv:qos`, `mqv:topic` and `mqv:filter`
  terms from the pinned draft; draft behavior is not W3C conformance.
- Keep broker authority in the Form href and Topic Names or Topic Filters in
  their binding terms. Never place a topic or filter in the broker href.
- Let the consumer own connections, sessions, reconnects, credentials,
  deadlines, TLS and access policy. Command, delivery and error values remain
  credential-free.
- A Property read uses the retained-message contract; an arbitrary later
  publication is not its response. QoS does not prove exactly-once physical
  effect or authenticated delivery.
- Re-establish lost subscriptions only under consumer recovery policy and close
  each Runtime subscription through its specified lifecycle.
