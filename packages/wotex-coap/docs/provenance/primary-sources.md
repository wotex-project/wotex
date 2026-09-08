# CoAP primary sources

Research date: 2026-09-08. Primary protocol evidence:

- IETF [RFC 7252, June 2014](https://www.rfc-editor.org/rfc/rfc7252.html), §§3–5, 9, 11:
  UDP framing, token/MID correlation, confirmable retransmissions, option rules
  and congestion limits. Defaults include NSTART=1 and four retransmissions.
- IETF [RFC 7641, September 2015](https://www.rfc-editor.org/rfc/rfc7641.html), §§3–4:
  Observe uses registration/cancellation on the same token and 24-bit serial
  freshness. Observation is eventual consistency, not a guaranteed event log.
- IETF [RFC 7959, August 2016](https://www.rfc-editor.org/rfc/rfc7959.html), §§2–4:
  UDP Block sizes 16..1024; validate offsets, representations and bounds.
- IETF [RFC 9175, 2022](https://www.rfc-editor.org/rfc/rfc9175.html),
  [RFC 8613, July 2019](https://www.rfc-editor.org/rfc/rfc8613.html), and
  [RFC 8974, 2021](https://www.rfc-editor.org/rfc/rfc8974.html):
  Request-Tag/Echo, OSCORE replay/nonce persistence and extended-token security
  are independent requirements, not implied by baseline RFC 7252 support.
- W3C [TD 1.1, 5 December 2023](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
  and [CoAP binding draft](https://w3c.github.io/wot-binding-templates/bindings/protocols/coap/index.html),
  source ef00e4d208c9f1ecc0eb7274ce3e90a7fc3bafc3 (2025-10-22). The binding is
  work in progress; Wotex implements a documented subset without conformance claims.
- [libcoap 4.3.5 server manual](https://libcoap.net/doc/reference/4.3.5/man_coap-server.html),
  upstream revision 7cf7465b784baded4de183290c547d582becfd28. Independent fixture candidate.

Discovery covered framing, security, observation, blockwise and Form gaps.
Follow-up reconciled draft status and peer versions. Stop reason: baseline
claims have primary support; hardware and secure interoperability need execution.
