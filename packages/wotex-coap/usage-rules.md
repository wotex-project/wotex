# Wotex CoAP usage rules

These rules describe the completed WCO.01–WCO.08 contract. The package
catalogue records implementation status separately.

- Select UDP, DTLS or OSCORE explicitly and provide each identity, peer,
  credential, trust decision, deadline and size limit at the call boundary.
  Use numeric peer addresses unless the consumer supplies name-resolution
  policy.
- Use the GET, POST, PUT and DELETE helpers only through validated requests.
  Account for retransmission and complete Block1/Block2 transfer within one
  absolute deadline; never automatically retry an unsafe operation.
- Perform resource discovery as a bounded GET with CoRE Link Format parsing.
  Preserve raw references and unknown attributes; discovery never traverses or
  authorizes a resource automatically.
- Supervise Observe registration, reports, refresh and cancellation. Preserve
  token, sequence, ETag and block metadata and reject stale observations.
- Treat a response or cancellation acknowledgement as a protocol result, not
  canonical Thing state, durable delivery or proof of physical effect.
- Native OSCORE and software-peer builds are explicit tasks. Loading or
  compiling the package performs no network I/O and starts no native process.
