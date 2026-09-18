---
spec:
  id: WMA.05
  title: "Complete SDK-backed Matter controller software profile"
  status: accepted
  version: 1.1.2
  owner: wotex-matter
  updated: 2026-09-17
---

# WMA.05 Complete SDK-backed Matter controller software profile

Read [WMA.01](WMA.01-library-contract.md) and the [implementation sequence](../plans/software-implementation.md).
[WMA.06](WMA.06-standalone-client-and-preservation.md) fixes the native API, protocol workflows and concrete fixture contract.
The accepted target is the persistent first-party C++ controller in
[WMA.08](WMA.08-native-backend.md). The persistent controller profile and its
accepted evidence are recorded in [WMA.03](WMA.03-implemented-profile.md). The
one-shot native lifecycle is described in [WMA.04](WMA.04-sdk-client.md).

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
supported through their pinned generated types; schemas outside the finite .11/.13 registry return `:unsupported_schema`.

## WMA-S01 — Paths and values

Keep `Address.new/1` and its concrete fabric/node/endpoint/cluster/member widths
and reserved ranges from the pinned SDK. Fabric 1..2^64-1, operational node
1..0xFFFFFFEFFFFFFFFF, endpoint 0..0xFFFE; cluster is a valid standard or
vendor-qualified SDK ClusterId, member excludes 0xFFFFFFFF. A message's fabric
must equal the active controller fabric before any lookup or I/O.

Add `ReadPath.new/1` for explicit read-only wildcards. Fields endpoint/cluster/
member may be `:any`; node and fabric stay concrete. Wildcards are never accepted
by write/invoke or silently inferred from nil. At most 64 requested paths and
1024 returned paths; duplicate concrete attribute results are malformed. Keep caller path
order for concrete multi-read results and sort wildcard expansion lexicographically
by endpoint/cluster/member for deterministic output. Native `send/2` keeps the
existing concrete-operation return shapes; add explicit `read_paths/3` for batches.
WMA-N01 additionally requires typed native helper results and bounded endpoint
discovery composed from Descriptor reads, without inventing a wire service.

A finite batch reply has an aggregate 98304-byte result budget, measured as its
canonical compact JSON result value before the enclosing C07 envelope. The
serializer enforces this budget incrementally before growing its output buffer;
1024 individually valid paths do not permit 1024 independent 64 KiB results.
Use at most 98304 aggregate retained encoded result bytes plus bounded path/status
records. A callback that would exceed the result budget stops collection and
returns `:response_limit` with `effect: :none` for the read, after SDK cleanup.
No partial success, silent truncation, hidden pagination or replay is permitted.
The caller may explicitly request a smaller batch. A single unrepresentable
result fails identically. Bytes count after Base64/JSON encoding; the separate
131072-byte frame limit still applies to the complete envelope. A mutation result
that exceeds bounds remains an unknown-effect error, never a safe retry.

Retain all typed TLV tags/widths, signed/unsigned integers, Boolean, finite float,
UTF-8, bytes, null, structures, arrays and lists. Absence is not null. Unknown
context/profile tags remain tagged opaque values. Reject unbalanced containers,
invalid UTF-8, impossible lengths, illegal tags and width overflow before allocation.
**Library limits:** 64 KiB encoded TLV, depth eight, 1024 container entries,
1024 aggregate TLV nodes (retain the baseline codec limit); the framed bridge additionally applies C07's 128 KiB line
limit. No arbitrary Python object names or import paths come from the peer.

Use descriptor-based conversion in the pinned SDK registry: key is cluster ID,
member kind and member ID, never a display name. The first-party registry is compiled from the pinned generated C++ schema.
Enforce the same scalar/container limits on every conversion output. Do not turn
an unknown structure into a generic JSON object and claim typed parity.

## WMA-S02 — First-party persistent controller and storage

The first-party C++ controller uses `lifecycle: :persistent`; .13 separately
defines the bounded native one-shot read/write/invoke mode. `open` requires
an absolute native executable, absolute `storage_path`, `storage_mode:
:open_existing | :create_new`, vendor ID, fabric ID, controller node ID,
absolute PAA trust directory and `.13`'s explicit authority mode. The complete
create mode is `authority: :generate_root`; the complete existing mode is
`authority: :stored`. No default fabric, temporary store or factory callback.
`create_new` refuses existing storage; `open_existing` refuses missing/corrupt
state, unknown schema, key/certificate mismatch or a different fabric/controller.

Implement `chip::PersistentStorageDelegate` with `SyncGetKeyValue`,
`SyncSetKeyValue`, `SyncDeleteKeyValue`, preserving the SDK key names and opaque
bytes. Use `chip::PersistentStorageOperationalKeystore` and
`chip::Credentials::PersistentStorageOpCertStore` with that delegate. Root issuer
state is first-party durable state, distinct from peer attestation trust; issuance
and controller factory initialization follow .13. No Python storage schema or
CertificateAuthorityManager is a production requirement.

The storage directory is owner-only (0700), with a process-held exclusive lock
and regular no-follow state/temporary files (0600). The version-1 document has
`schema: "wotex.matter.store"`, `version: 1`, exact fabric/controller/vendor
identity, and a `values` map from SDK keys to canonical base64 byte strings.
First-party authority keys use the `wotex/authority/` namespace. Maximum key
length is 255 UTF-8 bytes without NUL; values are at most 65535 decoded bytes,
4096 keys and 16 MiB encoded file. Duplicate keys, invalid base64 or bounds fail
before SDK startup. This store has its own bounded parser; C07 frame limits do
not restrict durable file size. A checksum is not an authenticity claim.

Each successful setter/deleter means the complete new snapshot is written to an
owned same-directory exclusive temporary file, fsynced, atomically renamed and
the parent directory fsynced before success. Partial-write/fsync/rename failure
poisons the store and terminates controller operations. SDK transaction semantics
remain SDK-owned; the wrapper does not invent atomicity across separate SDK
writes. Unknown/incomplete authority state fails closed, with no regenerated key
or stale-state recovery. Test crashes at every write/rename/fsync boundary and
concurrent open from two processes. Secrets never enter logs or generic metadata.

One native owner holds the SDK factory/system state and one DeviceCommissioner.
Only its SDK event-loop thread enters APIs; callback contexts, finite admission,
reverse startup cleanup and shutdown are specified in .13. EOF/owner death
releases subscriptions, controller/system state and the storage lock within the
local grace or terminates/reaps its own process. Loading the dependency starts
no SDK and opens no storage.

## WMA-S03 — Interaction results and timed operations

Bridge operations are `open`, `read`, `read_paths`, `read_events`, `write`,
`invoke`, `subscribe`, `unsubscribe`, `commission_on_network`, `open_window`,
`health`, `close`. Route interactions through the pinned C++ `ReadClient`,
`WriteClient` and `CommandSender` APIs and callback ownership in .13 with
explicit node/path/generated descriptors.
Add native `read_events/3` with concrete event paths and optional minimum event
number; preserve event number (unsigned 64-bit), priority, timestamp kind/value
and path. Unknown priority is numeric metadata, not atom creation.
Event reads may return multiple historical events for one concrete path, or no
events after the supplied minimum. Retain every distinct event, grouped in
requested path order and ordered by event number within a path. Event identity
is fabric/node/event number; duplicates are malformed. At most 1024 event/status
records fit within the existing aggregate result budget. An empty successful
event read is `{:ok, []}`, not an invented missing-path failure. A per-path error
remains an error entry and cannot coexist with successful events for that path.

Results retain fabric/node/path, native status and cluster-specific status where
present. Multi-path success is an ordered list of per-path successes/errors,
not all-or-nothing silent filtering. A single-path denied/unsupported result
returns an Error, not nil. Attribute metadata retains DataVersion. Write requests
may require an explicit expected DataVersion (unsigned 32-bit); pass it through
to the SDK, and preserve mismatch status. A successful write ACK does not imply
a readback value or completion of a consumer workflow.

Successful mutation replies remain bound to the admitted target. Write
acknowledgements match fabric, node, endpoint, cluster and attribute. Command
data replies match fabric, node, endpoint and cluster, with a typed value valid
for the returned command identifier. A command status-only reply has neither
a response path nor a value; an empty structure remains a present value with
a response path. Mismatched identities and unpaired path/value fields are
malformed acknowledgements with unknown mutation effect.

Timed write/invoke uses `timed_request_timeout_ms` in 1..65535, explicitly supplied
where the descriptor requires it and bounded by the remaining interaction deadline.
Missing required timed parameters fail before SDK submission. Invoke timeout
after submission has unknown effect; no SDK-wrapper retry. SDK transport/session
retransmission remains SDK-owned. Native cancellation cannot promise rollback.

## WMA-S04 — Subscriptions and resubscription

Native `subscribe/2` requires `kind: :attribute | :event`, 1..64 concrete paths,
receiver, `min_interval_s` (default 1, 0..65535), `max_interval_s` (default 60,
1..65535), `resubscribe` (Boolean, default false), and C05 queue limit. Require
min <= max. Pass intervals through `ReadPrepareParams`; a `ReadClient` Subscribe interaction
returns a C05 handle only after `OnSubscriptionEstablished`. Capture revised
intervals and the SDK subscription identity.

Implement `ReadClient::Callback` report, attribute/event data, error, completion
and establishment callbacks. Preserve the bounded initial report buffer until
establishment; emit each reported initial path once, never invent missing paths.
Attribute metadata carries DataVersion; event metadata carries event number and
timestamp. Use SDK event/report identity for deduplication, never equal scalar
values. Callback output validates the complete path and fabric. Credit flow and
callback-safe destruction follow .13; report callbacks cannot block on stdout.

Default session/subscription loss is terminal. With explicit `resubscribe: true`,
emit a bounded `:resubscribing` control status, mark the stream continuity as lost,
and allow SDK retry for at most 60000 ms and five attempts. On success increment
the delivery generation, emit `:resubscribed` with `continuity: :unknown`, then
deliver the new initial snapshot. It is not gap-free Event recovery; never imply
missing events were replayed. Expiry/attempt limit terminates. No write/invoke is
replayed as part of subscription recovery.

Cancel by retiring delivery and scheduling ReadClient destruction on its SDK
thread after callbacks return; detach callbacks and cancel retry timers. Receiver death/overflow uses the same path. Late native callbacks from
an old generation cannot deliver. A controller shutdown closes all subscriptions
and persists its owned state before releasing the lock.

## WMA-S05 — Explicit commissioning and authorization

Add native `commission_on_network(session, request)` with concrete new node ID,
setup PIN (1..99999998 excluding repeated-digit and 12345678/87654321 reserved
codes), `discriminator` (0..4095) and finite timeout. Use exactly the SDK's
LONG_DISCRIMINATOR discovery filter; unfiltered commissioning is unsupported. Use filtered `DiscoverCommissionableNodes`, `PairDevice` and `AutoCommissioner`;
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
`CommissioningWindowOpener::OpenCommissioningWindow` with no caller PIN or salt,
so SDK crypto generates the onboarding material; wait for its final callback.
The original setup-code mode is unsupported by this API. Native returned onboarding material is explicit secret
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

`mix wotex.software.build --workspace ABS` builds the first-party native controller
and pinned C++ lighting/all-clusters/bridge peers. The SDK's upstream build and
ZAP/GN generation scripts may require build-time Python; source/executable hashes
and exact flags belong in the .13 manifest. Required peer targets are
`linux-x64-light-no-ble` and `linux-x64-all-clusters-no-ble`; the bridge extension
has a separate source hash. The runner owns peer/controller stores, software
ports, disposable fixture attestation material and all process cleanup. A shared
SDK does not constitute independent-stack conformance.

The required Linux lane performs on-network commissioning, CASE, denied ACL,
read/write/readback, a typed command, event generation, subscription cancellation
and persistent-controller restart. Separate fabric stores for controller and peer;
never mix CHIP Tool/test harness credentials. Missing SDK/build/response fails
the selected lane. This is real SDK software-peer evidence with a shared SDK;
it is not independent-stack conformance or physical-device certification.
