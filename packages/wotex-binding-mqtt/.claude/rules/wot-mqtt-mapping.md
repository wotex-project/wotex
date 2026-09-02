# WoT MQTT mapping rule

Apply when changing Forms, commands, topics, filters, QoS, or Runtime transport
behavior.

- Accept broker-only `mqtt` and `mqtts` href values.
- Read `mqv:topic` and `mqv:filter` only from the Form.
- Use the editor-draft defaults: reads, observations, and Event subscriptions
  subscribe; writes and Action invocations publish; stop operations unsubscribe.
- A Property read requires `mqv:retain` to be true, a finite client timeout, and
  a retained delivery.
- Normalize QoS integers and strings to integer levels zero through two.
- Reject wildcards in Topic Names and reject malformed Topic Filters.
- Subscription delivery closures decode JSON and send only
  `{:wotex_transport, payload}` to the Runtime receiver.
