# Wotex Continuum usage rules

These rules describe the completed WCT.01–WCT.03 contract at wire schema
2.0.0. The package catalogue records implementation status separately.

- Use registered `WotexContinuum` values for manifests, compatibility,
  capability, exchange, delivery, lifecycle, degradation and exit records.
  Constructing or decoding a value performs no host action.
- Reconstruct untrusted maps through the owning constructor. Reject unknown
  fields, atom/string collisions and invalid options instead of trusting a
  struct or choosing the looser of constructor and schema behavior.
- Preserve `schema_version`, apply explicit decode limits and validate against
  the matching shipped schema. Package-canonical JSON is not RFC 8785 JCS.
- Treat capabilities as declarations, `ActionIntent` as data, delivery as a
  claim and unknown effects as unresolved until consumer reconciliation.
- Apply lifecycle transitions as pure generation-advancing graph operations.
  The consumer atomically persists generations and owns shutdown and recovery.
- Keep identity, artifact admission, authorization, dispatch, persistence,
  queues, retries, clocks and credential custody in the consumer host.
