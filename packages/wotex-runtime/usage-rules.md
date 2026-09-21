# Wotex Runtime usage rules

These rules describe the completed contract defined by WRT.01–WRT.03 and its
completion contract. The package catalogue records implementation status
separately.

- Construct `Wotex.Runtime.ConsumedThing` and `Wotex.Runtime.ExposedThing` from
  a validated Thing Description, an explicit binding profile and an explicit
  transport.
- Supply request identity, absolute deadline and credentials through the
  documented context boundary. Never retain credentials in a Thing
  Description, Form, request, result, telemetry event or public error.
- Treat Form and binding-profile selection as deterministic compatibility
  matching, not authorization or endpoint policy.
- Keep inbound policy and schema admission outside ExposedThing dispatch. An
  invalid route must invoke no handler, and handler failures remain explicit.
- Treat a successful exchange as a protocol result, not canonical Property
  truth, proof of an Action effect or authority for another operation.
- Supervise subscription child specifications, bound receiver overload and
  close handles through the specified lifecycle. Runtime provides no durable
  recovery or exactly-once remote cleanup.
