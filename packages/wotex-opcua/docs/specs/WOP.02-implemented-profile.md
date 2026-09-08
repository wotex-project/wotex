# WOP.02 Implemented OPC UA profile

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
UA chunk framing defaults to 1 MiB and validates message type, chunk kind and
length before allocating/waiting. Chunk framing alone does not validate secure
channels, sequence numbers, RequestId, RequestHandle or service status.

The real adapter delegates those channel/session checks to pinned asyncua 2.0.1.
Its externally provisioned Python environment is an explicit implementation
dependency; the package neither hides nor installs it, and no native Elixir OPC
UA transport is claimed. Malformed handles, requests, timeouts, unknown options
and duplicate security options fail before the bridge starts.
Its HEL negotiation caps messages at 1 MiB and chunks at 16. The JSON process
boundary caps request/response bytes at 128 KiB and correlates a request ID.
The caller owns the process; closure of its input cancels the exchange. No
credentials are placed in command-line arguments. Native stderr joins the same
bounded result channel and cannot count as success. Stdout is a single JSON
result; failures expose no native exception text. Read scalars retain their
Variant type and StatusCode. ByteStrings use an explicit base64 representation.

The certificate profile is described in README. It requires a current, signed
issuer CRL and a leaf directly issued by a trusted self-signed CA. It is a
purposefully limited trust profile; intermediate chains and certificate renewal
are unsupported. Basic256Sha256 SignAndEncrypt is mandatory. No additional
security policy or complete OPC UA conformance/certification claim is made.

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
