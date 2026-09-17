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
  upstream revision 7cf7465b784baded4de183290c547d582becfd28. Independent UDP/DTLS software peer.

Protocol, SDK and draft revisions define distinct authorities. Software
interoperability requires actual peer assertions; source review is not execution.

## Software scope and SDK authority

- [RFC 6347, January 2012](https://www.rfc-editor.org/rfc/rfc6347.html)
  defines the selected DTLS 1.2 wire protocol; OTP owns record processing and
  handshake retransmission. [RFC 5280, May 2008](https://www.rfc-editor.org/rfc/rfc5280.html)
  supplies certificate/CRL validation semantics. The fixed cipher allowlist,
  exact SAN matching, bounded offline trust material and no-downgrade behavior
  in WCO-S05 are explicit library profile choices.

- [RFC 6690, August 2012](https://www.rfc-editor.org/rfc/rfc6690.html), sections
  2–4, supplies link-format grammar and the well-known resource. Discovery does
  not authorize later interaction.
- [OTP 29.0.4 TLS cipher definitions](https://github.com/erlang/otp/blob/OTP-29.0.4/lib/ssl/src/tls_v1.erl)
  and [OTP ssl API](https://www.erlang.org/doc/apps/ssl/ssl.html) define the DTLS
  adapter boundary. The web API page was OTP 29.0.6 when reviewed; implementation
  evidence must name the actual OTP build. A local OTP 29.0.4 capability query
  confirmed the selected RSA and PSK AES-128-GCM suites. PSK suites are under
  `ssl:cipher_suites(anonymous, 'dtlsv1.2')`, not the `all` selector; this OTP
  category does not mean the selected PSK exchange has no key authentication.
  Configure the one selected suite explicitly, never enable the whole category.
- [libcoap 4.3.5 OSCORE API](https://libcoap.net/doc/reference/4.3.5/man_coap_oscore.html)
  exposes configuration, session construction and sender-sequence save callback.
  Its illustrative file-save code is not a crash-safe store specification.
  The public API does not supply the receiver-state persistence contract required
  for unrestricted safe restart. The .10 single-process-generation context rule
  is an explicit library security decision, not a claim of SDK persistence.
- [libcoap pinned source](https://github.com/obgm/libcoap/tree/7cf7465b784baded4de183290c547d582becfd28)
  is the native OSCORE engine and software peer. Label that OSCORE peer same-stack;
  RFC 8613 known-answer and replay/crash tests remain separate evidence.

Implemented Observe, OTP DTLS and blockwise evidence is recorded in
executable-evidence.md. OSCORE remains a target; source review alone does not
accept its native Port or durable-state behavior. Atomic-only upload and body limits are
library profile choices within RFC 7959's wider behavior.

## Standalone source authority

WCO.11 makes native method, URI and discovery behavior explicit. RFC 6690
sections 3.1–3.3 prohibit senders from repeating rt/if/sz; this package chooses
strict rejection of those malformed descriptions. This differs from the
first-occurrence receiver rules for rel/title/title* in
[RFC 5988, October 2010, sections 5.3–5.4](https://www.rfc-editor.org/rfc/rfc5988.html#section-5.3).
Repeated extension/hreflang values remain ordered. Anchored-link context is
preserved without automatic resolution or dereference. URI percent decoding
follows RFC 7252 section 6.4; package input limits are explicit policy.
The concrete corpus fixes inputs and expected outcomes. Execution receipts
identify the implemented discovery/Observe cases and their tested source.
