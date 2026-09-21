# Wotex OPC UA usage rules

These rules describe the completed WOP.01–WOP.07 contract. The package
catalogue records implementation status separately.

- Start the owned open62541 client only with explicit executable, guardian,
  endpoint, security, credential and trust configuration. Native preparation
  and builds run only through explicit tasks.
- Keep NodeIds, AttributeIds, DataValues, Variants, method arguments and
  results typed. Never select a node or trust policy from a display name.
- Use the specified Read, Write and Call operations without automatic retries.
  A timeout or lost response may leave a write or call effect unknown.
- Use persistent sessions for bounded Browse, BrowseNext, continuation release
  and multi-page collection. Continuations are opaque and generation-bound;
  close or failure must release them.
- Supervise monitored-item subscriptions, preserve Publish/Republish ordering
  and close handles through their specified session lifecycle.
- Match failures by structured fields rather than message text. A Good status
  or acknowledgement is not canonical Thing state or proof of physical effect.
