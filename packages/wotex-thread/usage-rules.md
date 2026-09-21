# Wotex Thread usage rules

These rules describe the completed WTH.01–WTH.07 contract. The package
catalogue records implementation status separately.

- Use `Wotex.Thread.Daemon` only for bounded, read-only inspection of an
  existing `ot-daemon`; the consumer starts, configures and supervises it.
- Start `Wotex.Thread.OpenThread` only with explicit native executable, radio,
  interface, settings-store, platform and owner configuration.
- Treat Operational Datasets as secret-bearing values. Inspection redacts key
  material; validate active and pending datasets through the SDK and export
  bytes only to an authorized boundary.
- Keep state inspection, enablement, network formation, management updates,
  commissioner state and finite joiner admissions as separate operations.
  Acceptance is not activation or proof that a joiner attached.
- Supervise State subscriptions, preserve generation and changed-flags metadata
  and close them through the native retirement barrier.
- Thread management is not a generic application protocol and does not provide
  arbitrary Property writes to devices on a Thread network.
