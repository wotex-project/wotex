---
spec:
  id: WMA.02
  title: "Implemented Matter profile"
  status: accepted
  version: 1.1.0
  owner: wotex-matter
  updated: 2026-09-09
---

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

`ReadPath` admits explicit read-only endpoint, cluster and member wildcards while
keeping fabric and node concrete. `read_paths/3` accepts at most 64 selectors,
retains at most 1024 unique concrete results, preserves every per-path success or
error, orders concrete requests by caller position and sorts each wildcard
expansion by path. `AttributeReport`, `EventReport`, `Descriptor` and
`EndpointCatalogue` validate the P01 value layer without performing discovery or
SDK I/O. The aggregate canonical compact JSON result budget is 98304 bytes.

`Client` is a consumer-implemented driver contract. It must use a pinned real SDK,
keep fabric stores isolated, enforce attestation/ACLs, inspect all per-path status
results, respect finite request budgets and clean up owned resources. Contract
tests use an explicitly selected test module, never a production fallback.
The optional controller fixture harness also requires an explicitly installed
module. Selecting a module and passing the harness do not independently prove
that the module is SDK-backed or that the fixture is a physical device; that
provenance must be reviewed and recorded separately.
The SDK adapter maps concrete read/write/invoke calls to an explicitly initialized native
controller supplied by its factory. It does not implement CASE/PASE or the
Interaction Model; those remain inside the caller-provisioned SDK/controller.
It does not implement the new batch request shape; a selected client must
implement that callback result explicitly.
No Python runtime, SDK binary, controller factory or commissioning workflow is
bundled. See [SDK client contract](WMA.03-sdk-client.md).

## Evidence and compatibility

See [executable evidence](../provenance/executable-evidence.md) for specific tests,
commands and remaining gates, and [source revisions](../provenance/primary-sources.md).
Public callbacks provide a neutral compatibility surface, not drop-in semantic
parity. `send/2` completes synchronously; no fictitious receive queue exists.
Compatibility claims require exact differential scenarios for the advertised API.

Runtime adapters reject credential objects they cannot interpret. Native client
credentials/options are supplied explicitly by the consumer. A custom Client
implementation is trusted executable code and must honor the timeout and cleanup
contract; the wrapper cannot impose those guarantees on an arbitrary module.
Unknown Form extensions remain immutable but are not silently treated as
implemented protocol behavior. Finite deadlines, unsupported operations and
remote failures use structured Error values. Failed mutations report unknown
effect when execution may have started; a transport acknowledgment is not
canonical device state.
