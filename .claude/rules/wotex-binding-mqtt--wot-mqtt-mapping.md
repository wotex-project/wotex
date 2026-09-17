---
paths:
  - "packages/wotex-binding-mqtt/**"
---

# WoT MQTT mapping rule (wotex-binding-mqtt)

Apply when changing Forms, commands, topics, filters, QoS, or Runtime transport
behavior.

- Accept broker-only `mqtt` and `mqtts` href values.
- Read `mqv:topic` and `mqv:filter` only from the Form.
- Use the editor-draft defaults: reads, observations, and Event subscriptions
  subscribe; writes and Action invocations publish; stop operations unsubscribe.
- A Property read requires `mqv:retain` to be true, a retained delivery, and a
  client timeout bounded by the remaining request deadline.
- Normalize QoS integers and strings to integer levels zero through two.
- Reject wildcards in Topic Names and reject malformed Topic Filters.
- Subscriptions hand the client the subscription owner pid, never a closure. The
  client sends `{:wotex_transport_frame, delivery}` and
  `{:wotex_transport_status, status}` to that owner, which decodes the delivery
  and reports its Topic Name, QoS, and retained flag as metadata.
- A publish acknowledgement is an `:accepted` result; a retained read is `:ok`.
- Every binding error carries a retry class.
