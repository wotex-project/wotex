---
spec:
  id: WCO.03
  title: "Whole-body transfers"
  status: accepted
  version: 1.0.0
  owner: wotex-coap
  updated: 2026-09-09
---

# WCO.03 Whole-body transfers

RFC 7959 (August 2016), sections 2.3–2.7, defines the block sequencing,
negotiation and representation rules. RFC 9175 (February 2022), section 3,
supplies the Request-Tag option. The codec accepts non-minimal received unsigned
option encodings and emits minimal encodings; known option lengths are checked
before dispatch.

`Connection.transfer/4`, the compatibility `send/2` and Runtime requests execute
an entire transfer exclusively on their connection. The same absolute deadline
covers queuing and every exchange. Message IDs remain distinct within the
exchange lifetime; a cryptographically random eight-byte token identifies each
transfer. Retransmission repeats the exact current datagram. Failed transfers
are never restarted automatically.

Body limits default to 1 MiB, block size to 512 bytes and exchanges to 4096.
Callers may lower the body/exchange limits and select block sizes 16–1024.
Runtime accepts `max_body_size`, `max_blocks` and `block_size`. Explicit low-level
Block options use `Connection.request/3`; the whole-body API rejects caller
options it manages itself.

Large POST/PUT bodies use Block1, Size1 and a stable Request-Tag. Each successful
non-final acknowledgment must match the transmitted block number, advertise a
same-or-smaller size, and request atomic continuation with 2.31 and no payload.
The next block number scales when the server reduces its preferred size.
If-None-Match is sent only on the first block. This profile deliberately rejects
per-block non-atomic success because a whole-body success would be ambiguous.
The final acknowledgment cannot request continuation. A failure after an upload
starts reports unknown effect, including partial server state.

Block2 responses are assembled sequentially. The first negotiated size cannot
exceed the request; subsequent sizes, response code, Content-Format and ETag
identity must remain consistent. Non-final payloads fill their declared block;
offsets and aggregate byte/exchange budgets are checked. Missing continuations,
changed representations, remote errors and malformed descriptors fail the whole
transfer. A completed response removes Block1/Block2 descriptors and retains
representation metadata. Combined upload/download continuations retain the
method and Request-Tag, with no repeated request body or Block1 option.

`blockwise_test.exs` contains generated complete-body reassembly, real UDP
size negotiation, combined transfers, malformed acknowledgments, changed ETags,
bounded allocation and failure vectors. Independent-peer evidence is recorded
in the provenance document after executing the relevant fixture.
