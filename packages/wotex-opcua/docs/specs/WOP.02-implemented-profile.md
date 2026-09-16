---
spec:
  id: WOP.02
  title: "Implemented OPC UA profile"
  status: accepted
  version: 1.0.23
  owner: wotex-opcua
  updated: 2026-09-16
---

# WOP.02 Implemented OPC UA profile

This document inventories the existing Python-backed protocol adapter and the
partial public native Session client. It does not accept the complete native
target in WOP.10–WOP.13. Python remains a runtime requirement when selecting the
older `Asyncua` adapter; the explicitly selected `Open62541` client uses no
runtime Python process.

The OPC 10101 URI subset is
`opc.tcp://host:port/path?id=percent-encoded-NodeId`. A single `id` query parameter
is required; default port is 4840. Property read/write map to Value-attribute
operations. Method binding parameters are not guessed; call remains available
through the explicit protocol API. Form `target` is the endpoint URI with port
and without the `id` query. Runtime configuration must match it exactly.
Other OPC 10101 features are not claimed by this subset.

Writes require an explicit local-profile `wotex:variantType` (for example
`Double`) or a typed input envelope. This extension is not an OPC 10101 term.
`Value.encode/2` validates scalar width before encoding; ByteString input is raw
binary. Runtime extracts native read values and puts Variant type/StatusCode
in result metadata; bad status never becomes a successful Property value.

NodeIds support numeric, string, GUID and opaque identifiers. Namespace is
16-bit; numeric identifiers are unsigned 32-bit. Strings/opaque IDs are bounded
to 4096 bytes. GUID text is canonical and wire encoding observes mixed byte
order. Scalar codecs bound strings to 65536 bytes, preserve null versus empty,
reject overflow/non-finite values, and return the unconsumed stream tail.
Boolean decoding maps zero to false and every nonzero byte to true; encoding
uses zero and one, as required by OPC UA Part 6 v1.05.07
[§5.2.2.1](https://reference.opcfoundation.org/specs/OPC-10000-6/5.2.2.1).
The same rule applies inside Variants, DataValues and reference directions.
ExpandedNodeId codecs retain explicit URI/server fields and normalize the
numeric namespace when a URI is present. QualifiedName and LocalizedText retain
namespaces, locales and null-versus-empty text. Full ReferenceDescription codecs
preserve both expanded identities, direction, names and the finite NodeClass.
These pure structures do not resolve a namespace or follow a remote reference.
Variant codecs cover the finite built-in type table, explicit array/null/empty
distinctions, checked dimensions, opaque ExtensionObjects and read-only future
IDs 26..31. DataValue codecs retain value presence, full status and exact signed
100 ns timestamps, normalize 10 ps fractions, and preserve unconsumed bytes.
Arrays have a 1024-element ceiling; Variant/DataValue consumed bytes are limited
to 1 MiB including metadata. The native C value library constructs bounded SDK
Variants/DataValues and projects their finite typed fields. Native request/service
integration is partial; SDK receive-side preallocation limits remain work. The
existing `Value` adapter still has its scalar contract.
UA chunk framing defaults to 1 MiB and validates message type, chunk kind and
length before allocating/waiting. Chunk framing alone does not validate secure
channels, sequence numbers, RequestId, RequestHandle or service status.

The real adapter delegates those channel/session checks to pinned asyncua 2.0.1.
Its externally provisioned Python environment is an explicit implementation
dependency; the package neither hides nor installs it. Malformed handles,
requests, timeouts, unknown options
and duplicate security options fail before the bridge starts.
Its HEL negotiation caps messages at 1 MiB and chunks at 16. The JSON process
boundary caps request/response bytes at 128 KiB and correlates a request ID.
The caller owns the process; closure of its input cancels the exchange. No
credentials are placed in command-line arguments. Native stderr joins the same
bounded result channel and cannot count as success. Stdout is a single JSON
result; failures expose no native exception text. Read scalars retain their
Variant type and StatusCode. ByteStrings use an explicit base64 representation.

The implemented certificate profile requires a current, signed
issuer CRL and a leaf directly issued by a trusted self-signed CA. It is a
purposefully limited trust profile; intermediate chains and certificate renewal
are unsupported. Basic256Sha256 SignAndEncrypt is mandatory. No additional
security policy or complete OPC UA conformance/certification claim is made.

## Explicit native build tooling

`mix wotex.opcua.native.build --workspace ABS` and the owning root alias
`mix wotex.native.build` build the native dependency/bootstrap executable.
The build pins source digests, static SDK/OpenSSL options and tool identities;
its completion receipt binds downloaded archives, static libraries, executable
and command logs. Reuse verifies every artifact and current tool-version output.
The separate `wotex_opcua_custody` executable has its own receipt digest. Its
opaque bidirectional queues and independently executing owner-loss cleanup are
tested through real pipes; CTest includes stopped-worker, blocked-consumer,
complete final-output, descriptor isolation and direct-reaping cases.
The build guardian bounds command output, time and ordinary owned process groups.
Its trusted compiler bootstrap has explicitly unverified descendant cleanup on
failure. Source, workspace and tool failures cannot produce a completion receipt.
The build applies one reviewed open62541 patch: it retains the received
`revisedSessionTimeout`, exposes it as a Double connection attribute while the
Session is active, and resets it on cleanup. It also discovers the exact
pinned endpoint and user-token policy over a SignAndEncrypt channel, rejecting
certificate/URL substitution and ambiguous matching token policies. Every original and modified source
digest is fixed; all inputs are checked before any file changes. Patched source
files and the patch log are receipt artifacts. An altered input or already
patched source is rejected. The same-stack C regression opens three loopback
SDK Sessions and verifies fractional, equal and lower requested revisions plus
copy lifetime and post-close rejection. Security None is confined to that test
binary; this is SDK metadata evidence, not secure production Session acceptance.
The separate C-only Session probe uses the native configuration and verifier
adapter against an independent asyncua peer. It proves Basic256Sha256 anonymous
activation, the revised timeout and an explicit NamespaceArray read in that
test binary. Production open/close then acquired the NamespaceArray
asynchronously and checked the server revision before service work was added.

The current C executable emits versioned readiness, exits on owner EOF and runs
explicit SHA-256/SDK DateTime dependency self-tests. It now assembles a bounded
input line and applies the strict JSON reader and closed outer request envelope
to that process input. Malformed frames terminate with `invalid_request`; an
expired native deadline yields `deadline_exceeded`. A validated Basic256Sha256
anonymous `open` now activates the pinned SDK Session, reads and validates the
server NamespaceArray, checks the server-revised timeout and emits a correlated,
credit-spending success. A one-at-a-time asynchronous `read` accepts a concrete
NodeId and null index range, resolves its server namespace URI to the SDK-local
index and returns a typed DataValue. Bad StatusCodes retain the numeric status
in a structured error. NodeId-bearing result values remain unsupported until
inverse namespace translation exists. `close` cooperatively deletes the Session
and acknowledges cleanup; EOF also releases it. A one-at-a-time `write` validates
one typed Variant, retains copied SDK-owned memory through its asynchronous
request and returns one numeric result status. A rejected or timed-out transmitted
Write retains unknown effect and is never retried. A one-at-a-time asynchronous
`call` resolves concrete object and method NodeIds through the server URI and
SDK-local namespace map, copies up to 64 typed input Variants into SDK-owned
memory and returns the method status, ordered input argument statuses and typed
outputs. Bad method status and uncertain post-submission failures retain unknown
effect without retry. NodeId-bearing arguments and outputs remain unsupported
until full namespace translation exists. The internal BEAM owner validates
these responses and replenishes consumed credit. Browse/subscriptions,
complete output buffering, cancellation, full namespace translation and other
policy/token interoperability remain open P02/P03 work. The older explicit
`Asyncua` adapter remains Python-backed.
The native configuration helper validates explicit policy, token and credential
paths and snapshots bounded files for the native `open` request.
`Open62541.connect/1` now uses that helper and the owned C host for a persistent
secure Session, or defers file and process I/O in one-shot mode. Its current
public request path exposes typed native DataValue, Write status and Call result
maps through the facade; the independent Basic256Sha256 anonymous peer passes
read, write/readback, Call and one-shot read. This is an explicitly selected
partial native client, not a complete compatibility or Runtime projection.
For this client, the facade preserves `effect: :none` on its finite local
Write/Call input and configuration rejections. Transmitted or otherwise
uncertain mutation failures remain conservatively `effect: :unknown`; the
complete cancellation/error matrix remains open.
`Native.Frame` encodes exact outer request fields and maps the owner deadline
from the separately captured ready clock sample. The native build test uses
that production encoder to drive the real process. The internal
`Native.Host.request/4` sends correlated frames through
the custody guardian, validates terminal controls and open/read/write/call/close responses, and
replenishes delivered response credit. Unsolicited output ends the generation.
An `open` request now has additional native-side shape checks: exact keys,
three allowed security-policy URI strings, `SignAndEncrypt`, bounded text and
session timeout, closed user-token maps, and canonical base64 byte envelopes.
Native credential preflight then parses complete DER certificates/CRLs and
unencrypted PKCS#8 keys, validates RSA key pairs, checks application/user usage,
validity and identity, and verifies the direct self-signed CA/server chain and
current signed issuer CRL. Exact DNS/IP SAN and application URI checks precede
network access. Unknown noncritical certificate extensions remain admissible;
unknown critical and duplicate extensions fail. Invalid credentials return the
bounded `certificate_invalid` opening error. Validity starts are inclusive and
expiry is exclusive, tested with explicit wall-clock samples. The peer verifier
additionally checks a complete DER pin and refreshed trust during SDK network
verification. See the [native security boundary](../../priv/native/security.md).
The owner now sends one bounded initial credit control before its request. The
C process binds that credit to the generation, rejects a request without it,
and rejects further credit before any output has been consumed. Terminal output
uses the separate control allowance. Open/read/write/call/close responses consume credit and
the owner replenishes validated consumption. Report queues and subscriptions
remain unimplemented.
`Native.Host` admits both explicit executable digests before process creation,
receives strict versioned readiness, and links to the original caller only after
successful initialization and a one-use ownership claim. Hashing, spawn,
readiness and claim share the original startup deadline. Owner death, an
unclaimed-host deadline or failed readiness closes the Port; independent custody
handles stopped SDKs. The readiness corpus preserves integer clock boundaries
and rejects duplicate keys, invalid UTF-8, extra frames and oversized control
output. Actual built-SDK startup is exercised by the required native build test.
SDK report credits and the remaining Session/service matrix remain required
implementation; bootstrap readiness itself advertises none of those capabilities.

The native JSON foundation parses strict, bounded frames into a fixed allocator
pool, rejects duplicate decoded keys, and validates exact signed/unsigned
integer and finite floating-point projections. Vendored parser and license
digests are verified before native builds. The standalone corpus includes
integer endpoints, adjacent 100 ns tick integers, negative zero, malformed
Unicode and allocation/structural boundaries. The typed C conversion corpus
checks exact SDK binary bytes, arena rollback and retained response copies.
Direct SDK tests cover count, string, ByteString, complete wire-size and writer
pool boundaries. These primitives neither admit a service response nor prove
that its complete JSON frame fits the native transport budget.

## Evidence and compatibility

See [executable evidence](../provenance/executable-evidence.md) for specific tests,
commands and remaining gates, and [source revisions](../provenance/primary-sources.md).
Public callbacks provide a neutral compatibility surface, not drop-in semantic
parity. `send/2` completes synchronously; no fictitious receive queue exists.
The consumer must run differential scenarios before replacing its implementation.

Runtime adapters reject credential objects they cannot interpret. Native client
credentials/options are supplied explicitly by the consumer. A custom Client
implementation is trusted executable code and must honor the timeout and cleanup
contract; the wrapper cannot impose those guarantees on an arbitrary module.
Unknown Form extensions remain immutable but are not silently treated as
implemented protocol behavior. Finite deadlines, unsupported operations and
remote failures use structured Error values. Failed mutations report unknown
effect when execution may have started; a transport acknowledgment is not
canonical device state.
