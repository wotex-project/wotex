# MQTT binding library rule

Apply to all source, tests, packaging, and documentation.

- Loading the package starts no process and creates no connection.
- A consumer-supplied client port owns every MQTT session and handle.
- Never retain an execution context or copy an external client error into a
  package error.
- Public values are immutable and credential-free.
- Package output is JSON only and is bounded before decoding.
- Keep normal Hex dependency identity independent of the local source switch.
