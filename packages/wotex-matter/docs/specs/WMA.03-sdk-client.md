# WMA.03 Explicit SDK client

The SDK adapter targets connectedhomeip v1.6.0.0, commit
250a9e6c50ee2068107f3c4808b680f5f2925415, with Python's `matter` namespace.
Build/install that SDK into a caller-selected environment. The package never
fetches SDK code or fabric credentials at runtime.

`Wotex.Matter.SDK` implements the Client behaviour. Required options are an
absolute Python `executable`, `factory: "module:function"`, concrete `fabric_id`
and JSON-encodable `settings`. No implicit module, simulated controller or test
commissioner exists. The factory is trusted consumer code, a synchronous context
manager that yields an initialized SDK ChipDeviceController and cleans up its
owned stack/controllers on exit. The consumer owns CA/root selection, fabric
storage, exclusive access to that storage, operational identity and attestation
policy. Factories must not initialize or modify unrelated consumer stores.

Each request owns one Python process and one factory context. The process
boundary is newline JSON capped at 128 KiB with a correlated request ID. Native
stdout/stderr are redirected to a sink after the dedicated response descriptor
is acquired. Output emitted before that isolation still reaches the bounded Port
and causes malformed structured response failure. SDK logs cannot masquerade
as responses. No exception text or settings are returned to the caller. The
BEAM-side timeout covers the external process, while the Python timeout covers
the asynchronous operation; factories must keep synchronous startup/cleanup and
any descendants bounded. Input-pipe closure cancels an active asynchronous
exchange, but the factory remains responsible for descendant cleanup.

The concrete path is validated before invoking the bridge and the controller's
fabricId must match it. Generated SDK registries select attribute/command types.
Reads use fabric filtering, keep preexisting subscriptions, and disable automatic
resubscription. The requested endpoint, cluster and attribute must exist in the
result cache; SDK ValueDecodeFailure results are errors. Writes require exactly one matching AttributeStatus with success
status zero. Empty lists, mismatched paths and nonzero statuses fail.
Commands use the SDK's generated command descriptor and do not suppress responses.
SDK errors propagate as a neutral failure; no wrapper retries are added.

Explicit `timed_request_timeout_ms` is accepted for writes/invokes only within
the remaining interaction budget and 1..65535 ms. The SDK receives the interaction
timeout too. Read deadlines are enforced by the asynchronous process boundary.
Scalar/null/byte/array/struct results convert to bounded JSON;
write/command inputs accept the same explicit byte envelope; bytes use a
`{"type":"bytes","base64":"..."}` envelope. Unknown unsupported result types
fail rather than being stringified. A successful command with no output may
legitimately return null; write success always requires the exact path status.

Default checks execute the pure Python adapter contract against an explicitly
selected test controller, including false/null, fabric mismatch, missing path,
negative/empty/multiple write statuses, timed boundaries and malformed values.
They also check the BEAM executable boundary. Real SDK initialization,
commissioned-device interoperability, denied ACLs and attestation failure remain
unexecuted gates until a suitable factory and isolated fixture are provided.
An injected module or passing fixture harness is not independent SDK evidence.
The adapter does not expose commissioning, subscriptions or fabric mutations.
