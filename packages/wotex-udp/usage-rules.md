# Wotex UDP usage rules

These rules describe the completed normative usage contract. The package
catalogue records implementation status separately.

- Construct numeric local and remote endpoints explicitly. The consumer owns
  name resolution and interface selection.
- Create a finite configuration before explicitly opening a socket. Close the
  socket on shutdown and supervise its owner process if needed.
- Supply finite deadlines. A successful send proves only local OS acceptance.
- Admit broadcast and multicast explicitly. Join a multicast group only on a
  selected interface and release membership during shutdown.
- Treat incoming bytes and source metadata as untrusted. Interpret payloads
  in the consumer protocol layer, under its own correlation and policy.
- Budget datagram bytes, queued bytes, receive credits and concurrent work.
  The OS may drop datagrams under load; do not fabricate a loss count.
