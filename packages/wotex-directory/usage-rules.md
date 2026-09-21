# Wotex Directory usage rules

These rules describe the completed WTD.01 and WTD-C contract. The package
catalogue records implementation status separately.

- Construct each Directory service with consumer-supplied repository,
  authorization, clock and identifier ports. The package supplies no storage,
  server, scheduler or policy engine.
- Authorize before repository access. Repository implementations must perform
  expected-version checks and mutations atomically; conflicts never retry
  silently and failed mutations emit no successful Event value.
- Apply bounded RFC 7396 Merge Patch before Thing Description validation. Do
  not substitute JSON Patch or bypass core validation after a patch.
- Use opaque keyset cursors bound to the repository mutation generation.
  Repository offsets are not public cursors, and a mutation invalidates a
  continuation while expiry-only membership change does not.
- Invoke retention and purge explicitly. The consumer owns expiry scheduling,
  durable Event delivery, outbox behavior and recovery.
- Treat Introduction and lifecycle Events as immutable values. The final
  contract does not include HTTP, SSE, RDF or Discovery search profiles.
