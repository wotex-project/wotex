---
spec:
  id: WOP.10
  title: "Complete secure OPC UA client software profile"
  status: accepted
  version: 1.1.1
  owner: wotex-opcua
  updated: 2026-09-17
---

# WOP.10 Complete secure OPC UA client software profile

Read [WOP.00](WOP.00-library-contract.md), [WOP.11 standalone client and preservation](WOP.11-standalone-client-and-preservation.md), and the [implementation sequence](../plans/software-implementation.md).
This accepted target defines the native software profile. The current partial
native implementation is described in WOP.02. Target
acceptance requires the first-party native executable and every required software
lane; specification acceptance is not implementation evidence.

## Scope, references and implementation boundary

Use OPC 10000 Parts 4/6 1.05.07, Part 2 1.05.06, Part 7 1.05.02 and OPC 10101
1.00, pinned in [primary sources](../provenance/primary-sources.md).
Required services are Read, Write, Call, bounded Browse/BrowseNext/release,
namespace resolution, secure channel/Session lifecycle, and data-change
monitored subscriptions. WOP.11 specifies the complete browse contract. History,
PubSub, redundant-server failover, event filters, reverse connect, discovery
server hosting and a native BEAM security stack are separate profiles.
No certification is claimed.

The first-party `Wotex.OPCUA.Open62541` adapter owns an external C executable
using open62541 1.5.7 and OpenSSL 3.5.8. WOP.13 fixes source digests, build flags,
IPC, SDK integration and executable acceptance. Runtime operation requires no
Python interpreter or Python packages. asyncua 2.0.1 remains an independent
test peer for cross-stack interoperability.

The SDK owns UA TCP framing, secure-channel cryptography, token renewal, Session
activation and service codecs. The native executable owns bounded service
requests, Publish/Republish ordering, correlation and cleanup through SDK APIs.
Pure `Binary` and `Frame` contracts remain independent of the SDK transport.
A custom Client is an explicit port with its own trust and ownership obligations.

## WOP-S01 — Node identity and typed values

`Address.new/1` accepts numeric/string/GUID/opaque NodeIds. The native API includes
`Address.from_namespace_uri/3` with URI, kind and identifier. The value
stores a URI identity without guessing its index. Before every new Session's
first operation, read NamespaceArray and resolve the URI exactly; no match or
duplicate match is an error. Never carry an old index into a new Session.
Concrete namespace is 0..65535; numeric ID 0..4294967295; string identifier at most
4096 UTF-8 bytes and serialized NodeId text at most 8192 bytes. Opaque identity has the existing 4096-byte library ceiling.
Percent-decoded Form identity must roundtrip reserved `;`, `=`, `&`, `?`, `%`.

`Value.encode/2` accepts scalars and an explicit array envelope
`%{type: type_name, array: true, value: flat_list_or_nil}` with optional
`dimensions: [positive_integer]`. Scalars explicitly carry `array: false`.
Nil array, empty array and scalar null differ. Dimensions are positive integers,
at least two and at most eight, whose checked product equals element count;
omit dimensions for a one-dimensional, empty or null array. Limit 1024 elements, 64 KiB per string/ByteString and
1 MiB total native value; the 128 KiB bridge line limit may reject a smaller
serialized result with `:response_limit`, never truncate it. No type inference
from a JSON number. Preserve all existing scalar widths, signed zero and finite
float limits; non-finite numbers fail before JSON serialization.

The typed value profile includes DateTime (UTC integer ticks of 100 ns since 1601-01-01, signed 64-bit),
Guid (canonical text), NodeId, ExpandedNodeId, StatusCode (unsigned 32-bit), QualifiedName,
LocalizedText and opaque ExtensionObject (encoding NodeId plus bytes/XML body).
Unknown ExtensionObjects roundtrip as opaque tagged values; do not dynamically
instantiate classes from names received over the bridge. Numeric field and array
limits are validated before allocation. DateTime conversion never guesses a
local timezone. `UA_DateTime` and the native IPC preserve the full signed
64-bit tick value, including sub-microsecond ticks and extreme values. Service
observations carry `datetime_resolution_ns: 100` and
`raw_datetime_ticks_available: true`. DateTime never passes through floating
point or a calendar conversion. The independent Python peer cannot prove raw
100 ns precision: exact-tick cases require the native codec/C peer lane.
Picosecond fields remain separate from DateTime ticks.
Wire signed length -1 means null; values below -1 are malformed.

Version 1 typed payload shapes are fixed below. A Variant envelope always carries
`type`, `array`, `value`, and optional `dimensions`; `array` is a required Boolean
on the bridge, not inferred from value shape. The table describes an element
value field. `array: false` requires an element payload; `array: true` requires an
ordered list of element payloads or JSON null. Reject dimensions on scalar, null
array or empty array. Null Variants are scalar-only.

| Type | JSON value shape |
| --- | --- |
| Null | JSON null only; `array: false`, no dimensions |
| Boolean/integer/finite float/String | Corresponding JSON scalar, checked against the explicit type width; String may also be null |
| ByteString | C07 `{ "type": "bytes", "base64": "..." }`, or null |
| DateTime/StatusCode | Integer ticks / unsigned status number, respectively |
| Guid | Canonical lowercase hyphenated UUID string |
| NodeId | Canonical NodeId text accepted by Address.new/1 |
| ExpandedNodeId | `{ "node_id": "ns=0;i=1", "namespace_uri": null, "server_index": 0 }`; WOP-N02 defines URI/index rules |
| QualifiedName | `{ "namespace": 0, "name": "..." }`; name may be null |
| LocalizedText | `{ "locale": null, "text": null }`; both keys required, each null or UTF-8 |
| ExtensionObject | `{ "encoding_id": "ns=0;i=...", "encoding": "binary", "body": { "type": "bytes", "base64": "..." } }`; encoding is none, binary or xml; none requires null body, and binary/xml preserve an explicit null body separately |

The supported built-in type IDs are 0..15 and 17..22. XmlElement (16),
DataValue-as-Variant (23), Variant arrays (24) and DiagnosticInfo (25) are outside
this value profile and fail `:unsupported_type`. This does not exclude the
standalone DataValue decoder containing a supported Variant. On binary decode,
future type IDs 26..31 must be retained as `{ "type": "Reserved", "type_id": n,
"array": false, "value": bytes_or_null }`, or the corresponding byte-payload
array with `array: true`; do not guess a known type. This read-only envelope
retains the numeric type ID. Encoders and SDK writes reject Reserved with
`:unsupported_type`; IDs 32..63 fail `:invalid_binary`. This future-ID
preservation obligation belongs to the pure decoder. Native services fail
`:unsupported_type` when the SDK cannot represent an incoming reserved type;
they never fabricate its numeric identity from a decoded payload. Unknown
ExtensionObjects with explicit encoding identity remain opaque native values.

Reject unknown keys and malformed payload/type combinations. Keep existing
one-shot result shapes through an explicit version translation, not permissive
guessing. Namespace-URI addresses are native API values in this milestone;
the existing concrete NodeId Form syntax is unchanged.

Version 1 DataValue is `{ "has_value": true, "value": variant, "status": 0 }`
with optional `source_timestamp`, `server_timestamp`, `source_picoseconds` and
`server_picoseconds`. When has_value is false, omit value; when true, a typed
null Variant is valid. Timestamp fields use the S01 DateTime tick representation.
DataValue validation requires value-presence, Variant type, unsigned StatusCode and
optional source/server timestamps. Writes require picosecond fractions 0..9999
and the corresponding timestamp. Pure binary decode follows Part 6: encoded
fractions >=10000 normalize to 9999; fractions without their matching timestamp
are consumed but omitted from the semantic value. These fields count 10 ps
intervals. The source/server fields must not be interchanged. SDK observations
retain the same normalized rule. Absence is
distinct from a present null Variant. Good and Uncertain status preserve value
and full status metadata; Bad severity returns a structured failure retaining
the status. Uncertain must never be relabelled Good. A service-wide success
cannot erase individual Write/Call result statuses.

## WOP-S02 — Persistent bridge and resource lifecycle

`Open62541.connect/1` accepts `lifecycle: :persistent` by default and the explicit
`:oneshot` compatibility projection. Both use the same native executable and
typed service path. Persistent mode is required for subscriptions. Its
`connect/1` returns only after channel
creation, CreateSession, ActivateSession and namespace initialization succeed.
Use WOP-C07 versioned envelopes; fail an unsupported bridge version explicitly.
Version 1 admits only the pinned native backend and exact protocol schema.
Unversioned external programs do not satisfy it.

Bridge operations are `open`, `read`, `write`, `call`, `browse`, `browse_next`,
`browse_release`, `subscribe`, `unsubscribe`, `health`, `cancel`, `close`. Browse payloads
and ownership follow WOP-N03/N04. Open contains validated endpoint/security/authentication and
finite Session timeout (default 60000 ms, range 1000..3600000, server revision
retained). Read/write accept one concrete node and optional index range; this
profile rejects nonempty index ranges. Call contains concrete object/method NodeIds and at most 64 typed inputs.
Return an ordered typed output list and individual input argument statuses.
No output schema guessing. Other operation parameters follow S01/S04 exactly.

Keep one SDK Client per persistent bridge and at most 64 admitted operations.
Native requests have generation, IPC ID and SDK request-ID correlation. A
timeout suppresses the response and cancels owned work; a transmitted Write/Call
retains unknown effect. WOP.13 defines cancellation without blocking the loop. Shutdown deletes subscriptions, closes
Session with deletion enabled, closes channel/socket, then exits. Kill/EOF and
partial initialization unwind these acquisitions. Native stdout/stderr must not
pollute the framed channel. SDK internal logs never become Error details.

Channel renewal may occur transparently inside the live Session; namespace
identity and monitored-item identity stay bound to that Session. Session loss
is terminal for this profile: fail in-flight work and all subscriptions, close
the bridge, and require an explicit fresh connection. Disable SDK automatic
reconnect/replay. This avoids silently losing subscription history or replaying
mutations. A future recovery profile would require its own gap contract.

## WOP-S03 — Security and user authentication

Required channel modes: SignAndEncrypt with Basic256Sha256,
Aes128_Sha256_RsaOaep and Aes256_Sha256_RsaPss. Map only these exact names to the
pinned SDK security-policy URI values:

| Elixir policy | Exact policy URI |
| --- | --- |
| `:basic256sha256` | `http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256` |
| `:aes128_sha256_rsaoaep` | `http://opcfoundation.org/UA/SecurityPolicy#Aes128_Sha256_RsaOaep` |
| `:aes256_sha256_rsapss` | `http://opcfoundation.org/UA/SecurityPolicy#Aes256_Sha256_RsaPss` |

 No automatic best-policy selection, downgrade,
Basic128Rsa15, Basic256 or Sign-only operation. Security None remains limited to
an explicitly selected isolated fixture adapter and cannot satisfy secure gates.

Retain the implemented explicit server certificate pin and direct-CA trust
profile: configured self-signed trust root directly issues the server leaf.
Intermediates and dynamically fetched trust material are rejected in this
milestone. Validate signature, validity time, exact SAN hostname/IP, application
URI, key usage/EKU, critical extensions and current correctly signed issuer CRL.
Check client certificate identity/usage/time and match private key before open.
Trust is immutable per generation. Require RSA key size at least 2048 bits,
SHA-256-or-stronger certificate signatures and policy-specific nonce checks in
the SDK. The certificate-verification adapter enforces exact SAN/URI/pin/CRL
checks before accepting the endpoint, independently of SDK defaults.

User-token mode is explicit `:anonymous`, `:username`, or `:certificate`.
Username/password and user certificate/private key are distinct from the
application certificate. Require a matching endpoint UserTokenPolicy and secure
channel, then let the SDK construct/sign/encrypt the token according to that
policy. No anonymous fallback on rejected credentials. Unsupported token policy
fails; never send a password under None. Credentials, nonce, keys, certificate
body and endpoint URL are excluded from Inspect/logs/telemetry/error details.

Authentication success does not grant a Write/Call. Preserve per-service access
denial status. A refused operation is not a successful nil result. Native security
dependency audits and independent-peer tests are mandatory, beyond ExUnit.

## WOP-S04 — Monitored data changes

`subscribe/2` takes `node_id`, `receiver`, `publishing_interval_ms` (default 1000,
10..60000), `sampling_interval_ms` (default 1000, 0..60000), `queue_size`
(default 100, 1..1000), `discard_oldest` (Boolean, default true),
`keepalive_count` (default 10, 1..1000), `lifetime_count` (default 30, 3..10000)
and C05 queue limit. Lifetime must be at least three times keepalive count.
Create one UA Subscription and one Value-attribute MonitoredItem per handle.
Use explicit server-revised parameters from CreateSubscription/CreateMonitoredItems;
reject nonpositive/invalid revisions and failed item status before returning a handle.

The initial DataChange is delivered exactly once when received; server ACK alone
does not invent an initial value. Preserve client handle, item status, DataValue
timestamps, publish sequence and overflow status in metadata. The native
owner uses complete service-level PublishResponse values, not a scalar-only
monitored-item callback. WOP.13 defines the explicit Publish request/ACK loop. Accept nonempty notification sequence numbers 1..2^32-1 with wrap to 1;
keepalives do not consume a notification sequence. Keep at most 1024 accepted
sequence/digest entries. For a gap, request each missing sequence with SDK
Republish, bounded to 100 messages and one interaction deadline, validating
subscription and expected sequence before delivery. A conflicting duplicate,
larger gap or BadMessageNotAvailable is terminal. Do not call the SDK's
subscription recreate/reconnect helper. Publish ACKs belong to the bounded native
owner after successful validation. The owner detects an unrecoverable gap,
unknown item, terminal status or missing keepalive beyond revised lifetime and
terminates with `:subscription_lost`/`:sequence_gap`. No silent fresh subscription.
Duplicate notifications recovered through Republish are not delivered twice.
Equal values with new timestamps/status can be fresh reports. A queue overflow
flag is surfaced explicitly; it cannot be hidden by scalar conversion.

Cancellation deletes the server MonitoredItem and Subscription; on failed ACK,
close the Session to force server cleanup and report the cancellation error.
Receiver death/bridge death also releases all native tasks. Handle generation,
admission, backpressure and terminal-once behavior follow WOP-C03/C05.

## WOP-S05 — Forms and compatibility

Keep OPC 10101 URI rules and the explicit Runtime target association. Preserve
existing read/write/Call successful return shapes in one-shot mode. Extend
`observeproperty` to the persistent monitored-item profile; `subscribeevent`
remains unsupported because EventFilter/EventNotifier is outside this profile.
Use explicit native NodeIds for Call object/method; no URI member guessing.
Runtime credentials remain nil-only; the explicitly selected native adapter
configuration owns security material for its session lifetime. Reject an
uninterpreted ExecutionContext credential before I/O.
Return typed arrays and metadata through Runtime only after complete validation.
The facade provides `health_check/2` with a concrete read probe; `health_check/1` keeps its
probe-required error. A successful TCP connection alone is not healthy UA service.

## Acceptance scenario families

| ID | Scenario | Required result |
| --- | --- | --- |
| WOP-V01 | Four NodeId encodings, URI reserved characters, namespace reordering | Exact identity; URI re-resolves on each new Session |
| WOP-V02 | Scalar/array/null/empty, integer/float edges, DateTime precision/range/sentinel, mismatched dimensions, excessive allocation | Exact typed result or pre-I/O validation error; native timestamp ticks and resolution metadata are exact |
| WOP-V03 | DataValue missing/null, Good/Uncertain/Bad, timestamps and unknown ExtensionObject | Presence and full status retained; Bad fails |
| WOP-V04 | Binary invalid signed lengths, every frame split/coalescing, chunk limit | Tail preserved; bounded failure without allocation amplification |
| WOP-V05 | Kill bridge during each open phase, EOF, wrong ID/version, late response, log flood | No false success, protocol contamination or leaked child/socket |
| WOP-V06 | Renew channel during read/monitoring; expire Session during write | Renewal preserves identity; loss terminal; write never replayed |
| WOP-V07 | Each allowed policy and user-token mode; wrong password/token policy/access ACL | Actual secure success or preserved authentication/access failure |
| WOP-V08 | Untrusted/expired/wrong-host/wrong-URI/revoked cert, bad CRL, mismatched key, downgrade | Connection fails; no None fallback |
| WOP-V09 | Tampered chunk/signature, stale sequence/token, wrong service/requestHandle | SDK/bridge fails correlated operation; no accepted forged result |
| WOP-V10 | Revised subscription intervals, failed item, initial report, same-value new status | Valid handle/revisions; correct fresh delivery |
| WOP-V11 | Duplicate Publish/Republish, recoverable and unrecoverable gap, queue overflow | Dedup/recovery or explicit terminal/overflow evidence |
| WOP-V12 | Receiver death, cancel failure, foreign/double cancel, server restart | Server subscription deletion or Session close; no silent reconnect |
| WOP-V13 | Runtime Property observation, invalid Event/context/credential, extension | Correct mapping and original-route cleanup |
| WOP-V14 | Independent asyncua secure read/write/Call/monitor, plus exact-tick C peer and security faults | Real asserted results for all secure profile cells |
| WOP-V15 | C09 stress, concurrent calls, admission overflow and version matrix | Correlation and owned/native resource baseline restored |

The independent wire peer is asyncua 2.0.1 with the complete pinned fixture
environment from WOP.13. The native C peer uses the same open62541 pin as the
client and is labelled same-stack. It supplies exact 100 ns values, controlled
Publish/revision faults and resource counters that the Python peer cannot
represent faithfully. Both peers expose disposable scalar/array variables,
typed methods and explicit users/certificate identities. Security fault tests
use controlled certificates, clock inputs and a bounded byte proxy. Both lanes
are required; neither peer substitutes for the other. No physical server is required.
