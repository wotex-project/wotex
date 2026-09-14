---
spec:
  id: WMA.02
  title: "Implemented Matter profile"
  status: accepted
  version: 1.1.0
  owner: wotex-matter
  updated: 2026-09-14
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
`EndpointCatalogue` validate the value layer. P04 adds named attribute, command
and event operations plus bounded Descriptor-cluster discovery. The aggregate
canonical compact JSON result budget is 98304 bytes.

The native source implements the SDK `PersistentStorageDelegate` interface for
a version-1 controller store. Creation and reopen require the exact fabric,
controller node, vendor and authority mode. The store holds an exclusive
process lock, preserves SDK key names and opaque bytes, rejects malformed or
oversized state, and uses an intent marker plus fsynced atomic rename for each
setter and deleter.

P03 supplies a first-party C++17 `wotex-matter-host` and the
`Wotex.Matter.Native` Port owner. Explicit `create_new` generates and stores a
root key, root certificate and Identity Protection Key with the pinned SDK
crypto provider. Explicit `open_existing` validates the stored authority and
reopens the exact fabric/controller identity. Controller setup uses the SDK
operational keystore, certificate store, generated controller data model,
production device-attestation verifier and one `DeviceCommissioner`. Startup,
failure, EOF and caller death release the controller and storage lock. P03
provides controller health and fabric admission.

P04 executes bounded reads, event reads, writes and command invokes through the
pinned generated cluster descriptors and connectedhomeip Interaction Model
clients. It carries finite request timeouts through CASE establishment and SDK
timers, preserves DataVersion preconditions, returns every path status and event
identity, and never replays a mutation whose result is uncertain. Descriptor
discovery reads root endpoint zero first, then at most 64 endpoints in chunks of
16.

P05 establishes explicit attribute or event subscriptions only after the SDK
reports `OnSubscriptionEstablished`. It retains revised reporting intervals,
SDK subscription identity, DataVersion or event identity, and distinct report
identity. The native host applies global frame/byte credit and per-stream credit;
the BEAM owner monitors the receiver, checks its queue before delivery and
cancels on receiver death or overflow. Cancellation retires the stream before
success and old-generation callbacks cannot deliver. Automatic recovery remains
disabled by default.

P06 enables recovery only for `resubscribe: true`. It emits a continuity-loss
status, retires the previous delivery generation, and permits at most five SDK
attempts within 60 seconds. Success emits `:resubscribed` with unknown continuity
before a fresh initial snapshot. The public handle remains valid across delivery
generations, while cancellation, receiver death and overflow detach the live SDK
retry state. Recovery never replays writes or invokes.

P07 adds explicit on-network commissioning with a concrete node, valid setup
PIN, exact long-discriminator filter and finite deadline. The native owner uses
filtered discovery and SDK pairing with its production attestation verifier. It
accepts success only after the final commissioning callback and a CASE probe;
SDK failures retain their numeric status and report unknown effect after fabric
mutation may have started. It does not reset the peer, remove a fabric or retry
commissioning automatically. Enhanced commissioning windows use SDK-generated
PIN and salt, wait for final completion and return a secret
`OnboardingMaterial` value whose Inspect output is redacted. AccessControl ACL
values use the generated schema and reject PASE as operational ACL authority.

P08 maps controller-profile Property reads and writes to typed attribute
services and Action invocations to typed command services. Successful Runtime
results preserve the concrete path, numeric status and DataVersion or command
response path. Property observations and Event subscriptions create one private
relay that owns the exact native session and subscription, forces native
resubscription off, validates each native reference/path/value, and presents
one-use frames to the Runtime owner. Event number, priority and timestamp survive
that projection. Terminal loss and owner death release the original native route;
a stop Form cannot redirect cleanup. `health_check/2` performs a caller-selected
concrete attribute read, while `health_check/1` remains probe-required.

`Client` is a consumer-implemented driver contract. It must use a pinned real SDK,
keep fabric stores isolated, enforce attestation/ACLs, inspect all per-path status
results, respect finite request budgets and clean up owned resources. Contract
tests use an explicitly selected test module, never a production fallback.
The optional controller fixture harness also requires an explicitly installed
module. Selecting a module and passing the harness do not independently prove
that the module is SDK-backed or that the fixture is a physical device; that
provenance must be reviewed and recorded separately.
The injected SDK adapter maps concrete read/write/invoke calls to an explicitly
initialized native controller supplied by its factory. It remains separate from
the first-party persistent controller and does not implement the batch request
shape. No Python runtime or SDK binary is bundled. The packaged first-party
controller source is built explicitly outside the Hex archive. P07's production
path compiles against the pinned SDK, and P08's Runtime mapping/ownership tests
execute against the public transport callbacks. The full public ConsumedThing
profile matrix remains P08a, and actual software-peer commissioning scenarios
remain P09 evidence. See
[SDK client contract](WMA.03-sdk-client.md).

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
