---
spec:
  id: WCO.11
  title: "Standalone client and feature preservation"
  status: accepted
  version: 1.1.0
  owner: wotex-coap
  updated: 2026-09-09
---

# WCO.11 Standalone client and feature preservation

Specification: `WCO.11@1.1.0`. Status: required target behavior; this document is
not a test result. Requires [WCO.00](WCO.00-library-contract.md),
[WCO.10](WCO.10-software-contract.md) and the existing
[atomic blockwise profile](WCO.03-blockwise.md).

## Library boundary

This library must provide a useful native CoAP client without requiring a Thing
Description, Form, Runtime Request or consumer framework. Native callers can
open a session, discover resources, perform GET/POST/PUT/DELETE with complete
bodies, observe a resource, and cancel/release everything they opened. Protocol
messages, block values, link parsing and freshness arithmetic remain pure APIs.
The package owns its UDP exchange and observation machinery; OTP owns DTLS,
and the explicitly selected libcoap bridge owns OSCORE exchanges.

The Wotex HTTP and MQTT packages are intentionally binding adapters through
consumer-supplied clients. Their no-client scope does not narrow this protocol
library. Inherit their typed values, immutable mappings, exact operation/media
cells, caller ownership and evidence discipline. WoT mapping remains a leaf over
the native client and Wotex core values, without a second codec or observation
state machine. Dependency loading performs no network activity or startup.

## WCO-D01 — Preserve useful features and replace weak machinery

| Useful asset | Required disposition and owning API | Proof obligation |
| --- | --- | --- |
| Native method helpers | Provide `get/2,3`, `post/3,4`, `put/3,4`, `delete/2,3` over `send/2` | Identical request/response semantics to the corresponding validated message map |
| Pure codec/options | Preserve `Message`, `Codec`, `Block` and `Observe` | Exact bytes, malformed boundaries, elective extension preservation, finite pure calls |
| Existing Block1/Block2 implementation | Retain the working whole-body path; add initial-report continuation | Current upload/readback regressions plus representation identity and incomplete-body failures |
| Resource discovery | Complete first-party `discover/2` and `LinkFormat.decode/2` | Actual GET, Content-Format 40, bounded parse, raw references and unknown attribute preservation |
| Observe registration/cancellation scenarios | Owned registration, report, renewal and cancellation under WCO-S03 | A registration request alone cannot set `supports_streaming: true`; initial response, reports, refresh, cancel and receiver loss must pass |
| Synchronous compatibility calls | Preserve `send/2`, explicit session lifecycle and live probe behavior | No separate receive queue; no successful socket-open result presented as remote health |
| Security seams | First-party OTP DTLS and optional pinned libcoap OSCORE adapters | Real protocol operations and failure tests; a callback stub is insufficient |
| Consumer retry, polling and durable delivery | Remain consumer policy | No hidden reconnect, new write attempt, durable event-log promise or automatic discovered-resource traversal |

The implemented native helpers include complete transfer, discovery parsing and
owned Observe registration, reports, renewal and cancellation. Native DTLS uses
OTP. The remaining secure Runtime and OSCORE cells have separate acceptance;
[executable evidence](../provenance/executable-evidence.md) records the actual
native and independent-peer cohorts. Capabilities describe only admitted modes.

## WCO-D02 — Exact helper and URI contract

All names below are under `Wotex.CoAP`. Method helper signatures are:

```elixir
get(session, path, options \\ [])
post(session, path, payload, options \\ [])
put(session, path, payload, options \\ [])
delete(session, path, options \\ [])
```

Each returns `{:ok, %Message{}}` only after a complete accepted response, or
`{:error, %Error{}}`. GET and DELETE have an empty request body; POST and PUT
accept explicit binary bodies, including empty bytes. There is no automatic
JSON encoding, string conversion, or `nil`-to-empty conversion in native helpers.
WoT content conversion belongs in Mapping. Method helpers use the session's
finite timeout, body/block limits and selected security adapter.

Options are a proper keyword list with unique keys from `confirmable`,
`content_format`, `accept`. `confirmable` defaults to `true` and must be Boolean.
Formats are `nil`, an integer 0..65535, or the closed aliases `:text` (0),
`:link_format` (40), `:octet_stream` (42), `:json` (50), `:cbor` (60). `accept`
and `content_format` default to nil (option absent); integer zero is an explicit
zero-length unsigned option, not absence. A non-nil Accept creates option 17.
Duplicate/unknown keys or invalid values return `:invalid_request` before I/O.

`message/1` remains pure and `send/2` uses it. Their accepted map keys are exactly
`method`, `path`, `payload`, `confirmable`, `content_format`, `accept`; required
method/path and helper-generated payload rules are identical. The map API may
explicitly provide a binary payload with any supported method; helpers never
invent such a payload. Unsupported methods or fields fail before admission.
Any negative class 4/5 response is `:remote_response` with numeric `details.code`;
it is not successful payload. A terminal 2.31 Continue is invalid completion.
Errors for transmitted mutations retain unknown effect under WCO-C04.

`path` is a UTF-8 relative reference limited to 4096 encoded bytes. Empty path
means `/`; a path lacking a leading slash is relative to the endpoint root.
Reject a scheme, authority, user information, fragment, controls and malformed
percent escapes. Split path segments and query arguments **before** decoding
each percent escape exactly once. A literal `+` stays `+`. Retain repeated and
empty interior segments and query arguments in order. Reject decoded `.` and
`..` path segments rather than silently sending forbidden Uri-Path values.
Existing option count (64), option length, datagram and body limits still apply;
an encoded URI fitting 4096 bytes can therefore fail a smaller wire limit.

These URI decisions follow the separation in
[RFC 7252 (June 2014), §§5.10.1 and 6.4](https://www.rfc-editor.org/rfc/rfc7252.html#section-6.4).
The local admission limit and relative-root shorthand are package policy.
Transport chooses unpredictable live tokens and safe MIDs; a helper does not
reuse `Message.message_id: 0` as a production identity. Protocol retransmission
resends the same correlated CON; it never starts a second application mutation.

## WCO-D03 — Discovery is a complete bounded operation

`discover(session, %{query: query})`, also accepting `%{}` as nil query, performs
GET `/.well-known/core` with Accept 40 under one session deadline. Query is nil
or an encoded query string of at most 1024 bytes without a leading `?`; use D02
percent and argument rules. Unknown map keys fail. Apply a 65536-byte body ceiling
while downloading, before allocation/assembly, even if the session permits more.
Only 2.05 Content and exactly one Content-Format option with decoded value 40
produce discovery success. A different successful status is
`:invalid_discovery_response`; absent/wrong format is `:unexpected_content_format`.
Negative status retains `:remote_response`; no response becomes an empty list.

`LinkFormat.decode(body, options \\ [])` returns `{:ok, links}` or library Error.
Links are ordered `%{href: binary, attributes: [{binary, binary | true}]}` values.
`href` retains the raw URI-reference and attributes retain their spelling and
input order; unquote/unescape quoted values once. An empty body yields `[]`.
Do not coerce `ct`, `sz` or unknown values to integers or split `rt` into an
application taxonomy. This prevents overflow and preserves extension data.

The only parser options are unique `max_body_bytes` (1..65536), `max_links`
(1..256), `max_attributes` (1..32) and `max_token_bytes` (1..1024), defaulting to
their maxima. Lowered limits apply during scanning; unknown/invalid options give
`:invalid_link_options`. Keep a bounded state machine for URI, parameter name,
unquoted value, quoted value and escape. Commas inside `<...>` or quoted strings
are data; escaped quotes/backsplashes do not terminate a string. Reject malformed
grammar, invalid UTF-8, controls including folded lines, trailing comma, dangling
escape, missing `>` or an unterminated quote as `:invalid_link_format`. No partial
list is returned. Limit failure is `:link_limit` with library-owned `field` set
to `:body`, `:links`, `:attributes` or `:token` and bounded `details.limit`.

Preserve repeated extension attributes, such as `x=1;x=2`, in their original
order. Do not mistake this for permission to repeat `rt`, `if` or `sz`:
[RFC 6690 (August 2012), §§2 and 3](https://www.rfc-editor.org/rfc/rfc6690.html#section-3)
forbids senders from repeating these singleton attributes and reserves `href`
from use as an attribute. This package rejects these cases as
`:invalid_link_format`; strict rejection is receiver policy, not an assertion
that RFC 6690 specifies that exact error. Large valid `sz` remains a bounded
string. The RFC 5988 (October 2010) receiver rule is different for `rel`, `title`
and `title*`: keep the first occurrence and ignore subsequent ones, as required
by [§§5.3–5.4](https://www.rfc-editor.org/rfc/rfc5988.html#section-5.3).
Retain repeated `hreflang` and extension attributes. Reject duplicate `anchor`,
`media` and `type` as this package's strict policy; preserve deprecated `rev`
syntactically without applying relation semantics. Validate the grammar of
standard attributes; do not implement a blanket “last map value wins” rule.
Count every syntactically encountered attribute against the limit, including
later occurrences that the receiver rule discards. Ignoring a duplicate cannot
be used to bypass scanning/allocation bounds.

Discovery returns the same raw links as the pure parser. It does not resolve,
dereference or automatically convert descriptions to Thing Descriptions. Preserve
`anchor` and `rel` so a caller can interpret link context correctly. Any future
resolution API must take an explicit endpoint/base and honor RFC 6690 §2.1/2.3;
it may not use the host's current directory or discard anchored-link meaning.
No DNS lookup, outgoing connection, authorization or automatic follow occurs
because an advertised target is absolute or belongs to another authority.

## WCO-D04 — Complete standalone observation workflow

This resource-dependent workflow uses only native calls, a software peer with `/temperature`
and explicit supervision. It must appear as an executable integration example:

1. Open a session for `127.0.0.1:5683` with timeout 3000 ms. Discover with query
   `rt=temperature-c`; require an advertised `/temperature` with `obs` flag.
2. GET `/temperature` with Accept 0; assert a complete 2.05 body `"20"`, including
   exact bytes and Content-Format. A discovery flag does not establish Observe.
3. Subscribe on that session to `%{path: "/temperature", receiver: self(),
   renew: false, max_queue_length: 1000}`. Return the opaque handle only after
   the initial valid Observe response; deliver `"20"` exactly once with serial 10.
4. Use a separately owned second client to change the peer resource. Receive a
   fresh report serial 11 with `"21"`; a duplicate CON gets an ACK and no duplicate
   delivery. Two distinct fresh reports containing `"21"` each are both deliveries.
5. Cancel through `unsubscribe(session, handle)` using the original token/URI.
   After its confirmed response, emit no more values, release the dedicated
   session, and make repeated cancellation/disconnect succeed without new I/O.

`subscribe(session, path)` defaults its receiver to the caller and applies S03's
other defaults. Map inputs require a valid receiver PID if provided. The native
success delivery is `{:wotex_coap, reference, {:ok, %Message{}, metadata}}`:
the complete Message remains available, with metadata keys `code`, `observe`,
`etag`, `content_format`, `max_age`. Missing ETag/format are nil; max_age is the
decoded unsigned value/default 60. Metadata types are: code integer 64..95
excluding terminal 95; observe integer 0..16777215; ETag binary 1..8 bytes or nil;
Content-Format integer 0..65535 or nil; Max-Age integer 0..4294967295.
This report profile admits at most one ETag; multiple response ETags are
`:invalid_observation_response`, a local validation rule distinct from retaining
multiple request-side conditional ETags. Report messages keep the first Block2 response's token,
Observe, representation identity and response status while exposing the fully
assembled payload. Native callers select their own content decoder; Runtime
decodes through its declared media profile after full assembly.

S03's one-observation session rule, virtual clock freshness, token ownership,
admission, receiver bound and cancellation states are mandatory. URI normalization
uses D02 for registration, refresh and cancellation; storing the normalized
option sequence prevents percent-decoding twice. Startup failure and receiver
death release any acquired socket even before a usable handle existed. Local
cleanup without a peer acknowledgment must not be reported as remote cancellation.

## WCO-D05 — Concrete fixture and executable-oracle contract

`docs/specs/fixtures/contract-v1.json` supplies exact inputs/expected outputs.
The WCO-Vxx table in WCO.10 describes scenario families. Neither its rows nor
the existence of JSON cases constitutes accepted executable evidence. The corpus
instantiates selected wire, URI, discovery, freshness and observation cells;
all remaining scenario edges and secure known-answer/fault tests stay required.

Format is local `wotex-protocol-contract@1.0.0`. Each case has unique `id`,
`requirements`, `scenarios`, `tier`, `operation`, `input`, and `expectation` with
`operator: "exact"`. Pass only input to the system under test. The independent
assertion side compares actual projected outputs with `expectation.value`.
Never give expected outputs to a callback being evaluated as protocol evidence.

| Operation | Fixed adapter / observed projection |
| --- | --- |
| `codec.encode` / `codec.decode` | Convert Message JSON using a closed atom allowlist; encode bytes or decode once; observe result with `hex` or full Message projection |
| `codec.validate` | Validate the supplied Message option set; observe success or error |
| `message.new` | Call pure `message/1`; observe full projected Message with placeholder MID 0/token empty; no network identity allocation |
| `observe.fresh` | Call `Observe.fresh?/3` using all three explicit inputs; observe Boolean |
| `link_format.decode` | Call the bounded pure parser; observe ordered raw href/attribute values or error |
| `observation.trace` | Inject clock, token/MID allocation and datagrams via the explicit test Datagram adapter; observe outbound bytes, native deliveries, completion and resource counts |

Message projection is exactly `type`, `code`, `message_id`, `token_hex`,
`options` as ordered `[number, lowercase_hex]` pairs, and `payload_hex`. Bytes
are never decoded as UTF-8 just to fit JSON. Native tuples use `status: "ok"`
with `value` (or `hex` for an encoder); a standalone `:ok` has only status.
Errors project `code`, `field`, `details`, `retryable`, `effect` under
`{"status":"error","error":...}`. Additional integration error-class checks
remain separately required. JSON null is nil. Use fixed string/atom tables;
do not call an unrestricted atom constructor on fixture or protocol input.

Virtual trace time starts at zero; events execute in `(at_ms, list_position)`
order and `drain` handles ready messages/timers. `subscribe` invokes native
registration asynchronously, `peer_datagram` supplies explicit numeric source
endpoint and bytes, and `unsubscribe` invokes cancellation. `observe` names
the one normalized fixture handle, not a forgeable production reference.
The fixture-only injected allocator consumes the input MID/token sequence;
exhaustion fails the test and cannot switch to random values. Compare outbound
datagrams in order and count duplicate ACKs. Deliveries project only body hex,
serial and code from actual messages; other metadata has separate S03 tests.
Final counts include owned sockets, pending timers and active subscriptions;
the consumer-owned receiver is excluded. No sleeps or operating-system-wide
resource counts substitute for deterministic assertions.

The runner rejects missing/duplicate cases, unsupported operations and mismatched
shapes. Each executed case records fixture SHA-256, ID, implementation commit,
toolchain, command, observed result and pass/fail. P01–P05 must bind their IDs
to actual assertions as the adapters/features arrive. P09 must run the complete
corpus and all Sxx scenario expansions, independent UDP/DTLS peers, labelled
same-stack OSCORE proofs, faults, stress and matrix/archive gates. A JSON parser
test or an assertion that an identifier exists is not requirement acceptance.

## Source basis

Protocol revision pins remain in [primary sources](../provenance/primary-sources.md).
Method/URI behavior was checked against RFC 7252 (June 2014); discovery grammar,
singleton and anchored-link rules against RFC 6690 (August 2012); freshness and
cancellation against RFC 7641 (September 2015). The executable-evidence cohorts identify implemented source and tests. Native wrappers, strict local
limits, projected fixture format and mandatory standalone workflows are library
design requirements, not claims that a standards body specifies this Elixir API.
