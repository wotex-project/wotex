# Changelog

## 0.1.0

- Establish the standalone, caller-owned MQTT binding package.
- Hand the client port the subscription owner pid instead of a delivery
  closure, and decode each `{:wotex_transport_frame, delivery}` in the owner
  through `c:Wotex.Runtime.Transport.decode_frame/3`, which reports the
  delivery Topic Name, QoS and retained flag and ignores unrelated topics.
- Document the client status contract: `:session_lost` after Clean Start or
  session expiry, `:reconnected` when the MQTT Session was resumed.
- Report binding-neutral Runtime result statuses: `:accepted` for a publish
  acknowledgement and `:ok` for a retained read.
- Classify every `Wotex.Binding.MQTT.Error` with `:timeout`, `:unavailable`,
  `:protocol` or `:permanent` for consumer retry decisions.
- Bound a retained read by the remaining request deadline and fail with
  `:deadline_exceeded` before calling the client when nothing remains.
- Admit JSON through the bounded `Wotex.JSON` decoder and carry the payload
  byte limit on every command.
