---
spec:
  id: WBA.11
  title: "Standalone BACnet client and feature preservation"
  status: accepted
  version: 1.1.1
  owner: wotex-bacnet
  updated: 2026-09-14
---

# WBA.11 Standalone BACnet client and feature preservation

Specification version: **1.1.1**. Implementation status: **implemented for the
accepted software cohort**. Requirements in this file extend
[WBA.10](WBA.10-software-contract.md). Named helpers, discovery, lifecycle
bindings and independent software acceptance are recorded in
[executed evidence](../provenance/executable-evidence.md). Software limits below
are library policy, not BACnet standard limits.

## WBA-N01 — A usable protocol client independent of Thing Descriptions

The package must provide a complete first-party BACnet/IP client through `IPv4`
and a separately documented borrowed `BACstack` adapter. A consumer supplies
interface/destination, supervision and policy; it must not implement discovery,
ACK decoding, COV, timeout correlation or stack cleanup to use the library.
Native values and operations work without a Thing Description, Form, Runtime
Request, payload schema or global registration. Mapping and Runtime Transport
adapt these same operations; they must not be a second protocol implementation.

The software release floor is: explicit open; optional bounded discovery;
typed read; typed write; readback; finite COV; cancellation; explicit close.
First-party and borrowed modes run the same public contract suite, with the
ownership differences asserted separately. Callback availability is insufficient:
capabilities must reflect the selected adapter's validated operations.

The owned IPv4 adapter accepts explicitly configured local and destination UDP
ports in 1..65535. Port zero is not an implicit allocation request. Destinations
accept integer IPv4 octets with first octet 1..223, or the explicit limited
broadcast address 255.255.255.255. The selected interface and its mask determine
local broadcast and routing; a final zero octet alone does not establish a
network address. Destination validation does not imply route availability.
This is package addressing policy. BACstack 0.0.1's own IPv4 transport restricts
ports to 47808..65535; the owned adapter implements destination validation and
UDP sending through its public transport behaviour and packet builder. Borrowed
transports retain their owner's port restrictions.

| Useful baseline asset | Required disposition | Owning surface and proof |
| --- | --- | --- |
| Object/property addressing, aliases, array index zero, explicit priority | Preserve and validate again at operation entry | `Address`, WBA-S01/WBA-V01 |
| ReadProperty and acknowledged WriteProperty | Retain native tagged values and named helpers | WBA-N02, WBA-S02; matching and wrong ACK cases |
| Sequential reads of several properties | Retain a bounded sequential helper, with no ReadPropertyMultiple claim | WBA-N03; request-order/fail-fast/deadline cases |
| Who-Is device discovery | Retain discovery using an explicit destination and finite listener owner | WBA-N04; actual Who-Is/I-Am peer proof |
| Owned IPv4 transport and borrowed Client | Preserve separate ownership modes | WBA-S03; fail every acquisition and keep borrowed Client alive |
| Scalar Form mapping and compatibility callbacks | Preserve success shape and unknown extensions | WBA.02 and the Wotex integration contract |
| Existing C-stack read/write/release scenarios | Retain as independent evidence and extend to discovery/COV | Required software runner; no silent missing-response pass |
| Bare success without an ACK, fixed sleeps and mailbox scraping | Replace with correlated bounded operations | WBA-S02/N04; late/unrelated/missing response cases |
| COV API placeholders | Implement the finite wire lifecycle specified in WBA-S04 | A callback or local listener is not a completed wire subscription |

## WBA-N02 — Named operations and exact success shapes

Add these documented root helpers. They share validation and the operation owner
used by `send/2`; no helper opens a second connection or retries a write.

```elixir
read_property(session, object_type, instance, property)
# => {:ok, Encoding.t() | [Encoding.t()]} | {:error, Error.t()}

write_property(session, object_type, instance, property, encoding)
# => :ok | {:error, Error.t()}

read_properties(session, object_type, instance, properties)
# => {:ok, %{non_neg_integer() => Encoding.t() | [Encoding.t()]}}
#  | {:error, Error.t()}

who_is(session, low_limit \\ nil, high_limit \\ nil)
# => {:ok, [Wotex.BACnet.Device.t()]} | {:error, Error.t()}
```

The five-argument write helper is for a scalar property with absent priority and
array index. Advanced addressing uses `Address` and `send/2`; helpers must not
guess priority 16 or silently drop a supplied index. A successful write helper
normalizes the matching WriteProperty SimpleACK to `:ok`; `send/2` retains its
existing acknowledged result shape. `Encoding` is explicitly supplied for native
writes; scalar conversion uses `Value.encode/2` with a declared type.

For example, reading Analog Output 0's Present_Value uses object type 1,
instance 0, property 85. Writing `%Encoding{encoding: :primitive, type: :real,
value: 25.5}` followed by reading can produce a typed Real 25.5 observation.
Releasing an explicitly addressed priority uses a typed Null write. Neither
SimpleACK nor readback proves a physical actuator effect.

## WBA-N03 — Sequential batch reads

`read_properties/4` accepts a list of 1..64 property aliases or numeric property
identifiers. Validate the whole list, normalize aliases, and reject duplicate
normalized identifiers with `:duplicate_property` before the first APDU. A map
cannot preserve duplicate requests; silently overwriting them is forbidden.
Each selector means an entire property, with absent array index and priority.
The general `send/2` path remains available for indexed reads.

Issue one ReadProperty at a time in caller order. Use one admission slot and one
absolute deadline for the entire batch. Each subsequent call receives only the
remaining time; no later call starts after expiry. This is sequential composition,
not atomic snapshot semantics and not a ReadPropertyMultiple wire service.

Return a map keyed by normalized numeric property identifiers only after every
read succeeds. At the first failure, preserve its structured error code and
numeric protocol status; add only `batch_index` (zero-based), `property`, and
`completed_count` to bounded details. Do not include successful values or payloads
in the error and do not return partial success. No later property is requested.
Validation failures have effect `:none`; all reads retain effect `:none` even
when earlier reads succeeded.

## WBA-N04 — Bounded discovery without automatic routing

Both first-party adapters accept an optional explicit `discovery` configuration:

```elixir
discovery: %{
  destination: {{192, 0, 2, 255}, 47808},
  timeout_ms: 1000,
  max_devices: 256
}
```

The IPv4 address must be a validated unicast or explicitly selected local
broadcast destination; port is 1..65535. The already selected interface owns
the socket. `timeout_ms` is 10..60000 and `max_devices` is 1..1024. Require all
three fields and reject unknown keys. Discovery is optional; absent configuration
makes `who_is` fail with `:discovery_not_configured` before any listener or I/O.
Do not derive broadcast/interface from the default route or device instance.
Foreign-network discovery, BBMD registration and routing remain outside scope.

Native discovery requires the owned Wotex StackClient or a borrowed wrapper whose
bounded capability handshake explicitly includes discovery. The version-2 response
is `{:wotex_client, 2, [:cov, :discovery]}`; version 1's COV-only response continues
to support its existing operations, but cannot authorize discovery. Retain the
verified feature set in the session owner. Raw borrowed BACstack Clients retain
read/write support and return `:not_supported` for discovery before registration;
never probe an unknown raw SDK message or mutate its internals. The pinned
`Client.handle_call/3` send path does not reject a dead queued caller; the Wotex
wrapper must check both caller liveness and the absolute deadline at final send.

Both limits may be nil to omit the two Who-Is range fields. Otherwise both must
be integers in 0..4194302 with low <= high; a single limit is invalid. There is
one outstanding discovery per session (`:discovery_busy` on a second) because
Who-Is/I-Am has no request identifier. The operation window ends at the earlier
of its configured timeout and the session interaction deadline. Only a configured
window ending before the interaction deadline can return a complete observation
list; a window cut by that deadline, including equality, fails with
`:deadline_exceeded`. Cleanup and final delivery still consume the same interaction
deadline. Discovery holds one of the 64 shared operation-admission slots. Remaining
time below 10 ms fails before sending. Register the local listener first, send exactly
one Who-Is, and collect validated I-Am reports until the window closes. Do not
sleep and inspect an unrelated caller mailbox. A send failure is an error and
releases the listener immediately.

`Device` is an immutable value with exactly these fields:

| Field | Type and validation |
| --- | --- |
| `source` | `{{a,b,c,d}, port}`; each octet 0..255, port 1..65535; actual I-Am source |
| `instance` | Device object instance 0..4194302 |
| `max_apdu` | Positive integer 1..65535 from I-Am; observation, not permission to exceed WBA-S02's owned transport limit |
| `segmentation` | `:segmented_both`, `:segmented_transmit`, `:segmented_receive`, or `:no_segmentation` |
| `vendor_id` | Unsigned integer 0..65535 |

Reject malformed/non-I-Am traffic from the discovery result; count it only in
bounded telemetry, without payloads. Out-of-range I-Am instances are ignored.
Identical reports with the same `{source, instance}` count once. A changed
max-APDU/segmentation/vendor field for that key during the same window fails
with `:conflicting_discovery_response`. Two sources advertising the same instance
remain two observations; do not silently select a route. A `(max_devices + 1)`th
distinct identity fails with `:discovery_limit`; never return a truncated list
as complete. Sort results by IPv4 octets, port, then instance. An empty successful
window returns `{:ok, []}` and proves only absence of matching reports during
that window. Independent fixture tests require their configured identities.

I-Am can be unsolicited or delayed from an earlier Who-Is; discovery reports
are observations received in this window, not cryptographically authenticated
or transaction-correlated replies. A result never edits the session destination.
The consumer must explicitly select a discovered route for a later connection.

At completion, timeout, caller death, Client death or disconnect: stop collection,
unregister the exact listener, cancel timers, and discard late callbacks using
the local operation generation. Cleanup follows WBA-C03. Borrowed transport and
Client survive. The SDK's `ClientHelper.who_is/3` is useful source evidence, but
its default destination selection and internal Task timing do not satisfy this
ownership contract without an adapter.

## WBA-N05 — Concrete fixture corpus and execution binding

[contract-v1.json](../../../../packages/wotex-bacnet/priv/fixtures/contract-v1.json) is a specified assertion
corpus with current executable bindings, not an independent peer test result. The WBA-Vxx table in .10 lists scenario
families. Each family still needs executable boundary and fault cases; these
concrete cases fix selected exact expectations without exhausting each family.

The local corpus format is version 1.0.0. `operation` names the public function
or test-adapter action. `input` is the only material supplied to the system under
test. The runner holds `expectation` separately and compares the entire declared
projection with the `exact` operator. JSON keys become known struct fields, and
only documented finite atoms are translated; never create atoms from arbitrary
input. Native `Encoding` projects to `encoding`, `type`, `value` and `extras`;
native `Address`/`Device` project to their documented fields. Binary input and
tail use lowercase hexadecimal; byte values use the C07 bytes/base64 envelope.
Errors project to `{code, effect}` plus the expressly expected details. This
projection does not waive separate Error class/redaction assertions.

The `upstream_encoding` tier constructs the named BACstack service and encodes
its APDU, or just its service-parameter tags where expressly requested. It checks
source-level wire examples separately from the operation's ownership.
Lifecycle cases use a virtual millisecond clock starting at zero and scripted
transport events. A script supplies inputs and peer responses, never the expected
public result. Normalize owned resources to counts, not PIDs. Compare sent
service order, public outcome, delivered observations and final ownership counts.
Deadline equality is expired. A timeout event advances the clock and runs due
timers; no wall-clock sleep is allowed in these deterministic cases.

Every executable binding records its N/S/V requirement IDs, JSON case ID and
SHA-256 of the corpus bytes. Merely parsing JSON or copying an ID into a fixture
manifest does not accept a requirement. The runner must invoke the library and
assert the expected result; independent software cases additionally assert
actual peer observations and cleanup counters. Current bindings are in `service_boundary_test.exs` (F01–F04),
`discovery_values_test.exs` (F05–F06), `cov_test.exs` (F07), `batch_test.exs`
(F08–F09), and `discovery_window_test.exs` (F10–F11), under
`test/wotex/bacnet/`. Source-driven APDU golden checks and lifecycle adapter
checks remain separate from independent peer evidence.

## Source basis and release acceptance

The reviewed source is the pinned [BACstack 0.0.1 package](https://repo.hex.pm/tarballs/bacstack-0.0.1.tar),
especially `ClientHelper.who_is/3`, `Services.WhoIs`, `Services.IAm`, and Client
subscribe/unsubscribe. The package's direct-source API names and encoding are
implementation evidence. Full paid ANSI/ASHRAE clauses were not inspected; no
BTL or complete BACnet conformance follows from this profile.

Acceptance requires one native example performing discovery, explicit route
selection, ordered property reads, write/readback/release, COV and cleanup using
the first-party client. Run it against the pinned independent C stack and assert
device identity, every service response, subscriber count and listener cleanup.
Also run the same read/batch/discovery contract on a borrowed Client and prove
that close leaves its resources alive. No placeholder factory or scripted peer
alone can establish this standalone release floor.
