# Wotex Matter usage rules

These rules describe the completed WMA.01–WMA.08 contract. The package
catalogue records implementation status separately.

- Start the first-party native controller only with explicit executable,
  fabric, node, trust, credential and controller-storage configuration. The
  package ships no controller binary and starts none on dependency load.
- Use typed endpoint, cluster, attribute, Event and command paths. Do not infer
  topology from display labels; obtain bounded topology from descriptor reads.
- Use the specified attribute read/write, command invoke, batch path read,
  Event read and endpoint-discovery operations with exact per-path results.
- Keep commissioning and commissioning-window operations separate from Form
  execution. Redact onboarding material and never commission as a side effect
  of a failed interaction.
- Supervise attribute and Event subscriptions. Resubscription is opt-in, and
  continuity plus persisted controller state remain consumer-owned.
- Treat commissioning, writes and commands as non-idempotent unless stronger
  device evidence exists. A successful Matter status is not proof of physical
  effect or authority for another operation.
