---
spec:
  id: WMA.10
  title: "Complete SDK-backed Matter controller software profile"
  status: accepted
  version: 1.0.0
  owner: wotex-matter
  updated: 2026-09-09
---

# WMA.10 Complete SDK-backed Matter controller software profile

Read [WMA.00](WMA.00-library-contract.md) and the [implementation sequence](../plans/software-implementation.md).
[WMA.11](WMA.11-standalone-client-and-preservation.md) fixes the native API, retained workflows and concrete fixture contract.
Baseline `e546603` includes concrete paths, a bounded TLV codec, Forms and a
factory-supplied one-shot SDK bridge with Python contract tests. It does not yet
prove an installed controller against a real SDK example peer. The target below
adds the first-party persistent controller, subscriptions, explicit on-network
commissioning and complete software evidence.

## Scope and source limitations

Pin connectedhomeip v1.6.0.0, commit
`250a9e6c50ee2068107f3c4808b680f5f2925415`. Matter 1.6 Core text was not available
for clause-level review; [primary sources](../provenance/primary-sources.md)
identify SDK APIs, release evidence and this limitation. The following is an
SDK-derived controller profile, not a complete Matter stack or CSA certification.

Required: concrete attribute reads/writes, commands, event reads, attribute/event
subscriptions, timed interactions, per-path status, persistent fabric storage,
on-network PASE commissioning with attestation, subsequent CASE operations and
explicit commissioning-window control. Group/multicast operations, BLE radio
commissioning, OTA, ICD support, bridge-device hosting and arbitrary cluster code
generation are separate profiles. SDK-defined standard cluster descriptors are
supported through their pinned generated types; unknown vendor schemas require
an explicitly registered consumer descriptor or return unsupported-schema.

## WMA-S01 — Paths and values

Keep `Address.new/1` and its concrete fabric/node/endpoint/cluster/member widths
and reserved ranges from the pinned SDK. Fabric 1..2^64-1, operational node
1..0xFFFFFFEFFFFFFFFF, endpoint 0..0xFFFE; cluster is a valid standard or
vendor-qualified SDK ClusterId, member excludes 0xFFFFFFFF. A message's fabric
must equal the active controller fabric before any lookup or I/O.

Add `ReadPath.new/1` for explicit read-only wildcards. Fields endpoint/cluster/
member may be `:any`; node and fabric stay concrete. Wildcards are never accepted
by write/invoke or silently inferred from nil. At most 64 requested paths and
1024 returned paths; duplicate concrete results are malformed. Keep caller path
order for concrete multi-read results and sort wildcard expansion lexicographically
by endpoint/cluster/member for deterministic output. Native `send/2` keeps the
existing concrete-operation return shapes; add explicit `read_paths/3` for batches.
WMA-N01 additionally requires typed native helper results and bounded endpoint
discovery composed from Descriptor reads, without inventing a wire service.

Retain all typed TLV tags/widths, signed/unsigned integers, Boolean, finite float,
UTF-8, bytes, null, structures, arrays and lists. Absence is not null. Unknown
context/profile tags remain tagged opaque values. Reject unbalanced containers,
invalid UTF-8, impossible lengths, illegal tags and width overflow before allocation.
**Library limits:** 64 KiB encoded TLV, depth eight, 1024 container entries,
1024 aggregate TLV nodes (retain the baseline codec limit); the framed bridge additionally applies C07's 128 KiB line
limit. No arbitrary Python object names or import paths come from the peer.

Use descriptor-based conversion in the pinned SDK registry: key is cluster ID,
member kind and member ID, never a display name. A caller-registered descriptor
is trusted executable code supplied in native configuration, with an explicit
allowlist. Enforce the same scalar/container limits on its output. Do not turn
an unknown structure into a generic JSON object and claim typed parity.

## WMA-S02 — First-party persistent controller and storage

Implement a versioned persistent bridge alongside the existing one-shot factory
contract. Select `lifecycle: :persistent` explicitly. `open` requires absolute
storage path, `storage_mode: :open_existing | :create_new`, vendor ID, fabric ID,
controller node ID, explicit PAA trust directory and controller credentials.
No default fabric, temporary store or test commissioner. `create_new` refuses
an existing store; `open_existing` refuses missing/corrupt state or a fabric mismatch.

Use the pinned API accurately: construct an object implementing
`matter.storage.PersistentStorage`, pass that object to
`ChipStack.ChipStack(persistentStorage=storage)`, then create
`CertificateAuthorityManager(chipStack, persistentStorage=storage)`.
Call `LoadAuthoritiesFromStorage()` for existing state. For authorized creation,
use `NewCertificateAuthority()`, `NewFabricAdmin(vendorId=..., fabricId=...)`,
then `NewController(nodeId=..., paaTrustStorePath=..., useTestCommissioner=False)`.
Do not pass a filesystem string where ChipStack expects a storage object.

The SDK's `PersistentStorageJSON(path)` is a reference serialization format;
the first-party store must add exclusive process locking, owner-only permissions,
atomic replacement and fsync of file and parent directory on Commit. Preserve
its SDK and CA key semantics. Persist before acknowledging changes that depend
on the stored identity. A failed store Commit is terminal, not a warning.
Never regenerate credentials or reuse a stale snapshot after a failed write.
No automatic store migration: an unknown schema version returns an explicit error.
Test process death at each write/rename/fsync boundary and two-process lock contention.

One bridge owns one ChipStack, authority manager, fabric administrator and
controller. SDK thread/event-loop ownership follows its API; serialize controller
entry through one asyncio owner. At most 64 admitted operations and 64 live
subscriptions. EOF/owner death cancels native tasks and subscriptions, shuts down
controller then authority manager then stack/storage, releases lock and exits.
Borrowed custom controllers remain consumer-owned; no first-party lifecycle
guarantee is inferred for arbitrary factories. No SDK import starts from loading
the Elixir dependency alone.

## WMA-S03 — Interaction results and timed operations

Bridge operations are `open`, `read`, `read_paths`, `read_events`, `write`,
`invoke`, `subscribe`, `unsubscribe`, `commission_on_network`, `open_window`,
`health`, `close`. Route reads/writes/commands through `ReadAttribute`,
`ReadEvent`, `WriteAttribute`, `SendCommand` with explicit node/path/descriptors.
Add native `read_events/3` with concrete event paths and optional minimum event
number; preserve event number (unsigned 64-bit), priority, timestamp kind/value
and path. Unknown priority is numeric metadata, not atom creation.

Results retain fabric/node/path, native status and cluster-specific status where
present. Multi-path success is an ordered list of per-path successes/errors,
not all-or-nothing silent filtering. A single-path denied/unsupported result
returns an Error, not nil. Attribute metadata retains DataVersion. Write requests
may require an explicit expected DataVersion (unsigned 32-bit); pass it through
to the SDK, and preserve mismatch status. A successful write ACK does not imply
a readback value or completion of a consumer workflow.

Timed write/invoke uses `timed_request_timeout_ms` in 1..65535, explicitly supplied
where the descriptor requires it and bounded by the remaining interaction deadline.
Missing required timed parameters fail before SDK submission. Invoke timeout
after submission has unknown effect; no SDK-wrapper retry. SDK transport/session
retransmission remains SDK-owned. Native cancellation cannot promise rollback.

## WMA-S04 — Subscriptions and resubscription

Native `subscribe/2` requires `kind: :attribute | :event`, 1..64 concrete paths,
receiver, `min_interval_s` (default 1, 0..65535), `max_interval_s` (default 60,
1..65535), `resubscribe` (Boolean, default false), and C05 queue limit. Require
min <= max. Pass intervals and explicit automatic-resubscription selection to
SDK ReadAttribute/ReadEvent. Return a C05 handle after the SDK establishes a
SubscriptionTransaction; capture revised intervals and subscription identity.

Install `SetAttributeUpdateCallback`, `SetEventUpdateCallback`,
`SetResubscriptionAttemptedCallback` and `SetResubscriptionSucceededCallback`
before delivering application reports. Reconcile the initial cached snapshot
with callbacks so initial values are emitted once; paths without a report remain
absent. Attribute metadata carries DataVersion; Event metadata carries event
number and timestamp. Use SDK event/report identity for deduplication, never
equal scalar values. Callback output validates the complete path and fabric.

Default session/subscription loss is terminal. With explicit `resubscribe: true`,
emit a bounded `:resubscribing` control status, mark the stream continuity as lost,
and allow SDK retry for at most 60000 ms and five attempts. On success increment
the delivery generation, emit `:resubscribed` with `continuity: :unknown`, then
deliver the new initial snapshot. It is not gap-free Event recovery; never imply
missing events were replayed. Expiry/attempt limit terminates. No write/invoke is
replayed as part of subscription recovery.

Cancel with SubscriptionTransaction.Shutdown, detach callbacks and cancel retry
timers. Receiver death/overflow uses the same path. Late native callbacks from
an old generation cannot deliver. A controller shutdown closes all subscriptions
and persists its owned state before releasing the lock.

## WMA-S05 — Explicit commissioning and authorization

Add native `commission_on_network(session, request)` with concrete new node ID,
setup PIN (1..99999998 excluding repeated-digit and 12345678/87654321 reserved
codes), `discriminator` (0..4095) and finite timeout. Use exactly the SDK's
LONG_DISCRIMINATOR discovery filter; unfiltered commissioning is unsupported. Use `CommissionOnNetwork`;
do not shell-parse CHIP Tool text. Require explicit PAA trust and SDK attestation
validation; reject invalid chain, untrusted PAA, invalid attestation signature
and failed proof. Do not set attestation bypass flags or test commissioner mode.
Test certificates belong only to fixture configuration, never a production default.

Commissioning succeeds only on final SDK completion after fabric/operational
credentials and CASE establishment, not on an intermediate PASE connection.
On failure return the SDK numeric status with unknown effect if fabric mutation
may have started; persist known controller changes and require explicit recovery.
Do not automatically factory-reset the peer, remove a fabric or restart commissioning.
Setup code, PSK and operational credentials are secret C04 data.

Add `open_commissioning_window/2` with node, timeout in 180..900 seconds,
iteration count in 1000..100000 and discriminator 0..4095, mapped to
`OpenCommissioningWindow` with `option: kTokenWithRandomPIN` (numeric 1);
the original setup-code mode is unsupported by this API. Native returned onboarding material is explicit secret
output with redacted Inspect; never place it in generic telemetry. Window expiry
is SDK/peer-owned and opening does not create an immortal bridge timer.
ACL reads/writes use typed AccessControl cluster descriptors and explicit
authorization on the peer; PASE access is not operational ACL authority.

## WMA-S06 — Forms and software proof

Retain the Wotex Form profile: attributes are Properties, commands are Actions,
Matter events are Events. This URI/profile is not a W3C standard binding.
`observeproperty` uses an attribute subscription; `subscribeevent` uses an event
subscription. Runtime uses only `resubscribe: false`: its existing session-loss
contract terminates the subscription and delegates restart to the consumer.
The native opt-in recovery mode must not emit unsupported Runtime status atoms
or label a new server subscription as a retained Session. Require concrete Form identities; wildcard batch reads are native
only. Runtime preserves statuses/timestamps/DataVersion and original route on
cancel. Commissioning is explicit native control and cannot be triggered by
reading an arbitrary Form. `health_check/2` takes a concrete read probe; the
one-argument compatibility function retains probe-required behavior.

| ID | Scenario | Required result |
| --- | --- | --- |
| WMA-V01 | Reserved path IDs, wrong fabric, wildcard write/invoke, duplicate returned path | Pre-I/O error; deterministic read expansion |
| WMA-V02 | TLV widths/tags/null/empty, unknown tag, malformed length/depth/UTF-8 | Exact typed preservation or bounded failure |
| WMA-V03 | Store missing/existing/corrupt/wrong fabric, concurrent opener, commit crash boundaries | No credential regeneration, unsafe reopen or shared writer |
| WMA-V04 | Kill at each SDK startup stage, EOF, bad bridge version/ID/log output | Owned SDK/storage lock cleanup; no fabricated result |
| WMA-V05 | Concrete and wildcard reads with denied/unsupported paths | Every requested/expanded path status retained |
| WMA-V06 | Timed write/invoke missing/expired/success, DataVersion mismatch, lost ACK | Exact status; no mutation replay or rollback claim |
| WMA-V07 | Attribute/event subscription initial/update, interval revision, null value | Correct path/value metadata and one initial delivery |
| WMA-V08 | Subscription loss default/opted-in recovery, repeated event, recovery deadline | Terminal or bounded explicit continuity-loss transition |
| WMA-V09 | Cancel/receiver death/overflow/late callback/foreign handle | No native subscription or callback survives cleanup |
| WMA-V10 | On-network commission good/bad PIN, failed attestation, expired window, ACL denied | Actual final SDK outcome; no bypass or PASE-as-ACL success |
| WMA-V11 | Runtime Property/Action/Event contexts and unsupported credentials/extensions | Exact applicability and immutable Form |
| WMA-V12 | SDK example peer commissioned, CASE read/write/command/event/subscription and restart | Real software controller/peer interactions, asserted results |
| WMA-V13 | C09 stress/admission/matrix and native storage/resource counters | Bounded ownership and durable identity after cycles |

Build the pinned Python SDK with `scripts/build_python.sh -m platform -i
out/python_env -b false` in an isolated fixture checkout. Build Linux lighting
and all-clusters applications from the same commit, with BLE disabled, using the
pinned `scripts/build/build_examples.py` host targets
`linux-x64-light-no-ble` and `linux-x64-all-clusters-no-ble` on the required x64
Linux fixture. Record host architecture; do not run an x64 binary on another ISA. Add a fixture wrapper that
records exact build target/flags, controller/peer store paths and software ports,
owns their lifecycle, and generates disposable test attestation material.

The required Linux lane performs on-network commissioning, CASE, denied ACL,
read/write/readback, a typed command, event generation, subscription cancellation
and persistent-controller restart. Separate fabric stores for controller and peer;
never mix CHIP Tool/test harness credentials. Missing SDK/build/response fails
the selected lane. This is real SDK software-peer evidence with a shared SDK;
it is not independent-stack conformance or physical-device certification.
