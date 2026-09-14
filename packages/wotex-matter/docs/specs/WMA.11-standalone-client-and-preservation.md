---
spec:
  id: WMA.11
  title: "Standalone controller and cluster workflows"
  status: accepted
  version: 1.1.1
  owner: wotex-matter
  updated: 2026-09-15
---

# WMA.11 Standalone controller and cluster workflows

Specification version: `1.1.1`. The catalogue and executable-evidence record
track implementation separately from this accepted target.
Requires [WMA.00](WMA.00-library-contract.md) and
[WMA.10](WMA.10-software-contract.md). [WMA.02](WMA.02-implemented-profile.md)
and [WMA.03](WMA.03-sdk-client.md) remain the narrower current baseline.

## WMA-N01 — First-party native controller

A release must include the first-party persistent SDK controller, durable fabric
store and typed interactions specified in .10. A consumer can commission and
interact with a real software peer with the compiled registry and without constructing a Thing Description. The
first-party native backend is .13; current factory contract tests are baseline
evidence only.
Wotex Runtime maps operations to the same native session. It does not own a second
controller or authorize commissioning as a side effect of Form execution.

These target public functions belong to `Wotex.Matter`. Existing concrete
`send/2` results remain compatible; richer operations have explicit new results.

| API | Exact contract |
| --- | --- |
| `connect(client: SDK, lifecycle: :persistent, ...)` | `{:ok, %Session{}}` after S02 storage lock, exact fabric identity and SDK startup; every S02 storage/trust/credential option explicit |
| `read_attribute(session, address, options)` | `{:ok, %AttributeReport{path: address, value: typed_value, data_version: uint32_or_nil}}`; denied/unsupported path returns Error; `options` permits `timeout` only |
| `write_attribute(session, address, typed_value, options)` | `{:ok, %{path: address, status: 0}}` after SDK ACK; options `timeout`, `expected_data_version`, `timed_request_timeout_ms`; no automatic readback |
| `invoke_command(session, address, typed_value, options)` | `{:ok, %{path: response_path_or_nil, value: typed_value_or_nil, status: 0}}`; distinguish status-only reply from empty structure by `path`; timed/deadline options as S03 |
| `read_paths(session, paths, options)` | `{:ok, [%{path: path, result: {:ok, AttributeReport.t()} \| {:error, Error.t()}}]}`; S01 order/bounds; options `timeout` only |
| `read_events(session, paths, options)` | `{:ok, [%{path: path, result: {:ok, EventReport.t()} \| {:error, Error.t()}}]}` retaining S03 identity and per-path failure; options `timeout`, `min_event_number`; event paths concrete |
| `discover_endpoints(session, node, options)` | `{:ok, %EndpointCatalogue{}}` from the descriptor reads below; node includes exact `fabric_id` and `node_id`; options `timeout`, `max_endpoints` (default 64, 1..64) |
| `subscribe(session, request)` / `unsubscribe(session, handle)` | S04 attribute/event C05 lifetime; native opt-in resubscription remains explicit |
| `commission_on_network(session, request)` / `open_commissioning_window(session, request)` | S05 final-result and redacted onboarding-material contracts; never auto-commission on failed reads |

`AttributeReport.value` is one explicit `TLV.element()` with anonymous outer tag;
container children retain their tags. SDK conversion selects the descriptor
width and preserves semantic type; it cannot reconstruct the original wire
integer width after the SDK has decoded it. Exact wire widths belong to the
separate raw TLV codec tests. Null is `%{tag: :anonymous, type: :null,
value: nil}` and never a missing report. This type is also the value accepted by
the named write/invoke helpers. Descriptor conversion controls nullable/writable
fields and command schemas. The existing generic `send/2` baseline shape is not
silently changed to this new report. `EventReport` adds `path`, typed `value`,
`event_number`, numeric `priority`, `timestamp: %{kind: :epoch | :system, value:
non_neg_integer}`, and `status: 0`; unsuccessful paths carry Error instead of a fabricated event
header. Timestamps remain the SDK-reported integer unit
in milliseconds. Unknown native timestamp kinds fail `:unsupported_timestamp`
with bounded numeric kind, rather than guessing an epoch.
Concrete event paths are unique within a request. Event-read results preserve
all historical reports for each requested path, ordered by event number, with
path groups in request order. Paths with no matching history contribute no
entry; an entirely empty history returns `{:ok, []}`. Returned event numbers
must satisfy the requested minimum. Duplicate fabric/node/event identities,
foreign paths and conflicting success/error entries for one path are malformed.
Descriptor validation applies to every returned event value.

`EndpointCatalogue` has fabric/node, root endpoint zero and sorted `endpoints`.
Each endpoint entry has exactly `endpoint`, `device_types`, `server_clusters`,
`client_clusters` and `parts`. Each Descriptor member is either
`{:ok, %{value: value, data_version: uint32_or_nil}}` or a bounded
`{:error, Error.t()}` with effect `:none`. Device types retain numeric
`device_type` and `revision`; cluster and PartsList values remain numeric.
Read root Descriptor PartsList, then each reported endpoint's DeviceTypeList,
ServerList, ClientList and PartsList through concrete batch reads. At most 64
endpoints and 1024 cluster IDs in the whole catalogue. Every child ID must be a
concrete valid endpoint; reject duplicate entries within a PartsList, cycles and
self-reference. A child may occur in both the root's transitive PartsList and
an aggregator's PartsList; that is not a duplicate endpoint error. Read each
endpoint once. Preserve unknown device/cluster IDs numerically. A denied descriptor
path yields an entry error, not an invented empty list. No consistent network
snapshot is claimed across separate reads; retain per-path DataVersion and mark
`consistency: :not_atomic`. Discovery never creates a fabric or scans networks.

## WMA-N02 — Cluster recipes with exact SDK descriptors

The minimum descriptor registry includes the following SDK-derived recipes. This
is a client interoperability profile, not complete device-type certification.
All IDs below are hexadecimal. Temperature values stay signed centi-degree
integers; a consumer may present 2150 as 21.50 °C. Do not silently round a float.

| Recipe | Concrete cluster/member and typed value | Operation |
| --- | --- | --- |
| Thermostat local temperature | `0201/0000`, nullable signed temperature; fixture `i16: 2150` or TLV null | read/subscribe |
| Thermostat cooling/heating setpoint | `0201/0011` cooling `i16: 2600`; `0201/0012` heating `i16: 2000` | read/write with SDK constraints |
| Thermostat mode | `0201/001c`, enum8 retained as `u8`; Off 0, Auto 1, Cool 3, Heat 4 fixture cases | read/write; other SDK enums preserved, not arbitrarily limited to fixture subset |
| Light state | `0006/0000`, Boolean | read/subscribe; the OnOff attribute is not writable |
| Light on/off/toggle | `0006/0001`, `0006/0000`, `0006/0002`, empty command structure | invoke; mutation replay prohibited |
| Endpoint discovery | Descriptor `001d`, members `0000` DeviceTypeList, `0001` ServerList, `0002` ClientList, `0003` PartsList | read; child count is derived from PartsList, not a fabricated attribute |
| Bridged reachability | `0039/0011`, Boolean; Event `0039/0003`, structure context tag 0 Boolean | read/subscribe attribute or event; preserve event number and timestamp |
| Temperature sensor | `0402/0000`, nullable signed temperature | read/subscribe, including null |

The exact descriptor sources at connectedhomeip v1.6.0.0 commit
`250a9e6c50ee2068107f3c4808b680f5f2925415` are
[Thermostat](https://raw.githubusercontent.com/project-chip/connectedhomeip/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/zap-templates/zcl/data-model/chip/thermostat-cluster.xml),
[On/Off](https://raw.githubusercontent.com/project-chip/connectedhomeip/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/zap-templates/zcl/data-model/chip/onoff-cluster.xml),
[Descriptor](https://raw.githubusercontent.com/project-chip/connectedhomeip/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/zap-templates/zcl/data-model/chip/descriptor-cluster.xml),
[Bridged Device Basic Information](https://raw.githubusercontent.com/project-chip/connectedhomeip/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/zap-templates/zcl/data-model/chip/bridged-device-basic-information-cluster.xml), and
[Temperature Measurement](https://raw.githubusercontent.com/project-chip/connectedhomeip/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/zap-templates/zcl/data-model/chip/temperature-measurement-cluster.xml).
The full Matter Core text access limitation in .10 remains; these mappings do
not widen the claim to CSA certification or every cluster.

The required tests cover typed tags/widths/null (P01, F01–F06), exact cluster
recipes (P01/P04/P09), durable controller/fabric equality (P02/P03, F07), and
attribute/event identity and cleanup (P05/P06, F08/F09). Numeric generated
schemas determine operations; OnOff state is read-only and its commands mutate.

## WMA-N03 — Complete controller-to-peer workflow

In the mandatory Linux lane create a fresh locked controller store, explicitly
commission the pinned lighting/all-clusters software peer with fixture PAA trust,
and require final completion followed by CASE. Read Descriptor to locate the
fixture endpoint; record its actual endpoint IDs instead of assuming endpoint 1
is universal. Read light false, invoke On with anonymous empty structure (`1518`
TLV), then separately read true. A direct OnOff attribute write must fail locally
`:not_writable` without an SDK write. Peer ACL denial remains a remote failure.

The all-clusters fixture exposes the thermostat and temperature recipes above.
Read 2150, write heating setpoint 2000 then 2050 with expected DataVersion, read
back 2050, and prove stale DataVersion rejection. A controlled peer null sensor
value must remain null. Subscribe, trigger two distinct reports with equal values
but distinct report identity, cancel, then verify zero callbacks after cancellation.
Use the pinned bridge example or a small test-only SDK peer extension for the
Descriptor/ReachableChanged recipe; record the extension source hash separately.
Its deterministic peer state is test code, not a replacement client transport.

Stop and reopen the first-party controller with `:open_existing`; preserve fabric
and controller identity and perform a CASE read without recommissioning. Inject
an interrupted durable-store commit and enforce terminal failure rather than a
successful stale reopen. Required evidence includes peer-side interaction logs,
redacted native status, subscription count, lock acquisition/release and zero
owned child processes after cleanup. Label this shared-SDK software-peer evidence
accurately; factory contract tests alone cannot accept P09.

## WMA-N04 — Concrete corpus and executable acceptance

[contract-v1.json](fixtures/contract-v1.json) is fixture format `1.0.0` with
status `partially_executed`. P01 binds WMA-F01–F06, WMA-F10 and WMA-F12 to
public operations in `test/wotex/matter/path_value_test.exs`; later lifecycle
cases remain unexecuted. The broader Vxx rows in .10 are scenario families.
Neither a scenario row nor parseable JSON counts as an executed test. All Vxx
alternatives and boundaries still need tests.

Each case has a unique `id`, `requirements`, `kind`, `operation`, `input`, and
`expectation`. The expectation uses `operator: "exact"` over a normalized
observation. Pure runners call the named public operation with only `input`;
expectations must never be handed to the implementation or its client adapter.
`bytes_hex` represents exact bytes with lowercase even-length hexadecimal.
Atoms become their names, tuples become arrays, maps have string keys, struct
module names are omitted, and integers retain full precision. A success projects
to `{"ok": value}`; an error projects only the listed stable `code`, `field`
when specified, and `effect`. Unlisted error fields are not asserted by that
fixture; C04 separately requires their type, boundedness and redaction. Byte
values inside output use `{"bytes_hex": "..."}`, never guessed UTF-8.

Lifecycle cases inject the ordered input `events` at explicit relative `at_ms`
using a controllable clock and a scripted backend. An event at the same time
runs in list order. Symbolic handles such as `bus-1`/`sub-1` identify distinct
resources in this test only. The observation consists of ordered deliveries,
terminal results and backend call/resource counters listed in the expectation.
The runner must inspect real owner state and recorded backend calls to produce
that observation; it must not reproduce the expected state machine inside the
assertion. The trace is an injected contract test, not interoperability evidence.

Add `test/wotex/matter/contract_fixture_test.exs` during P01 and bind each pure
case as its API becomes available; add lifecycle cases in their owning package.
A case without an implementation remains explicitly unexecuted and prevents
accepting its package. Do not check in an always-skipped test or count an ID in
a comment as proof. Final evidence records case ID, fixture SHA-256, executable
test path, command, source revision and result. The selected runner must fail on
unknown fixture format/operation, missing assertion, mismatched output or absent
required peer. Native software workflows below require separate real peer tests.
