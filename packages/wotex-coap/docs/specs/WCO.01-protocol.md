# WCO.01 CoAP protocol contract

## Revision and scope

RFC 7252 (June 2014) owns UDP framing and exchanges. RFC 7641 (September 2015)
owns Observe; RFC 7959 (August 2016) owns Block options and reassembly. Each
capability graduates with independent peer evidence. RFC 8974 extended tokens,
RFC 8613 OSCORE and RFC 9175 Request-Tag are separate capabilities; do not
silently claim them. A requested unsupported secure transport fails closed.

## Values and messages

A Message has type, numeric code, 16-bit MID, token of 0..8 bytes, ordered
(number, binary) option pairs and binary payload. Limit datagrams to 1152 bytes,
options to 64 and aggregate reassembly to an explicit caller budget. Preserve
unknown elective options; unsupported critical options fail request processing.
The codec preserves unknown options rather than inventing semantics. Reserved
option nibble 15, truncated extensions, truncated values, invalid token length,
unsupported version and a trailing payload marker fail with structured errors.
An empty message has no token, options or payload. Nonrepeatable option duplicates
are rejected at semantic validation. Unsigned option values use minimal encoding.

## Exchanges and lifecycle

A connection owns one UDP socket and has one outstanding exchange (NSTART=1).
Correlation uses endpoint and token; ACK/RST additionally require the original
MID. Empty ACK does not complete the application exchange. A separate CON
response is acknowledged. Wrong-peer, stale-token and unrelated MID messages
cannot satisfy a request or extend its absolute deadline. Confirmable requests
retransmit the same bytes/MID/token within a bounded exponential schedule;
non-confirmable requests are sent once. Automatic retry after an exchange fails
is forbidden for writes. Report an ambiguous write effect on timeout.

Do not reuse a MID for the same endpoint within the exchange lifetime. Transport
identities are generated at explicit startup; pure codecs never read clocks or
random sources. Disconnect/owner death closes sockets; loading starts nothing.
Telemetry uses [:wotex, :coap, ...], non-secret counts/durations and result codes.

## Observe and blockwise requirements

An Observe registration requires a success response containing Observe.
Cancellation keeps the relationship token and sends Observe=1. Serial freshness
uses 24-bit wraparound and the 128-second rule; equal/stale notifications do not
become new values. Confirmable notifications require ACK. Owner death must
release the observation. A successful ordinary GET is not an observation.

Block SZX 0..6 represents 16..1024 bytes; SZX7 is rejected for this UDP profile.
Validate NUM, M, exact non-final size, consistent ETag/content format, offsets,
aggregate limits and deadline. Missing or malformed continuations fail. A codec
for Block options alone does not establish a complete blockwise client claim.

## WoT and compatibility

TD 1.1 (2023-12-05 Recommendation) supplies Form values and operation defaults.
The CoAP draft at source ef00e4d208c9f1ecc0eb7274ce3e90a7fc3bafc3 (2025-10-22)
provides cov:method, cov:accept, cov:contentFormat and cov:confirmable. Preserve
extension terms; use read GET, write PUT and Action POST defaults. Binary,
UTF-8 text and JSON conversion must validate the declared content type.
The neutral compatibility adapter preserves callback names/arities and documents
intentional stricter failures. No consumer module is a dependency.

## Acceptance

Golden datagrams, generated malformed packets, all extended-option boundaries,
wrong peer/token/MID, retransmission, empty ACK plus separate response, owner
termination, Observe cancellation/freshness and Block continuity are required.
Independent libcoap tests assert actual responses and fail on timeouts. Secure
modes require negative authentication and replay tests before being advertised.
