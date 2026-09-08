# WMA.02 Implemented Matter profile

This is a local Wotex Form profile, not a standardized W3C Matter binding:
`matter://fabric-id/node-id/endpoint/cluster/member`. IDs are decimal and
concrete; Property read/write select attributes and Action invocation selects
a command. Runtime requires `target: "fabric-id"` exactly matching the Form.
The SDK driver validates actual fabric authority and per-member semantics.

TLV bounds are 65536 bytes, 1024 nodes and depth eight. Explicit signed/unsigned
integer widths, finite floats, Boolean, UTF-8/byte strings, null and three
container kinds are supported. All tag control forms survive decode. Arrays
require anonymous children; structures require unique non-anonymous tags.
Unknown context/profile tags are retained. The codec does not claim schema
validation, secure transport or unknown-element policy for the Interaction Model.

`Client` is a consumer-implemented driver contract. It must use a pinned real SDK,
keep fabric stores isolated, enforce attestation/ACLs, inspect all per-path status
results, respect finite request budgets and clean up owned resources. Contract
tests use an explicitly selected test module, never a production fallback.
The optional controller fixture harness also requires an explicitly installed
module; its existence is not evidence of SDK or device interoperability.
No commissioning or operational transport is bundled in this version.

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
