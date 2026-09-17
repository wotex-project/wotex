---
spec:
  id: WTH.11
  title: "Standalone network management and application composition"
  status: accepted
  version: 1.1.0
  owner: wotex-thread
  updated: 2026-09-09
---

# WTH.11 Standalone network management and application composition

Specification version: `1.1.0`. Status: planned target, not implemented capability.
Requires [WTH.00](WTH.00-library-contract.md) and
[WTH.10](WTH.10-software-contract.md). The narrower baseline is
[WTH.02](WTH.02-implemented-profile.md).

## WTH-N01 — A supplied OpenThread host manager

This package's useful standalone product is bounded Thread network management:
inspect a borrowed daemon, or explicitly own an OpenThread host instance, validate
and manage Datasets, form a network, commission a joiner and observe state.
The supplied OpenThread adapter must complete these operations without a
consumer-authored native host or a Thing Description. The SDK owns Thread mesh/radio
semantics. Wotex Thread owns typed calls, deadlines, secret handling and resource
cleanup. It is not an application transport or a border-router distribution.

All target functions below belong to `Wotex.Thread`. Network operations require
the explicitly selected `OpenThread` client; Daemon retains only .02 reads.
A daemon Session passed to a management function fails `:not_supported` before
any socket write. Validating configuration never enables networking.

| API | Exact contract |
| --- | --- |
| `connect(client: OpenThread, ...)` | `{:ok, %Session{}}` after S03 instance/platform/radio/store acquisition; requires executable, radio URL, interface, storage mode/path and owner |
| `inspect_state(session, options)` | `{:ok, %State{role: atom, network_name: string_or_nil, rloc16: uint16_or_nil, ipv6_enabled: boolean, thread_enabled: boolean, generation: integer}}`; `options` permits `timeout` only; nil is unavailable, not zero |
| `validate_dataset(session, dataset, kind, timeout)` | `:ok` or Error; `kind` is `:active` or `:pending`; call pinned SDK validity with exact bounded bytes |
| `get_dataset(session, kind, timeout)` | `{:ok, %Dataset{}}` or `:dataset_not_found` Error; explicit secret export, redacted Inspect, no arbitrary raw CLI text |
| `form_network(session, dataset, timeout)` | `{:ok, %State{role: :leader}}` after observed leader transition; S04 empty/disabled/creation-authority preconditions |
| `set_enabled(session, %{ipv6: boolean, thread: boolean}, timeout)` | `{:ok, %State{}}` after local SDK change; invalid combination returns `:invalid_state` without side effect |
| `management_active_set(session, request, timeout)` / `management_pending_set(session, request, timeout)` | request `%{dataset: Dataset.t(), extra_tlvs: [{type, bytes}]}` (extra default empty); final callback returns `{:ok, %{accepted: true, effective: :not_verified}}` or Error |
| `commissioner_start(session, options)` / `commissioner_stop(session, options)` | options `timeout`; `{:ok, %{state: :active}}` only after active callback, or `{:ok, %{state: :disabled}}` after stop |
| `add_joiner(session, request, timeout)` / `remove_joiner(session, identity, timeout)` | S05 exact identity/admission; add returns `{:ok, %{identity: identity, lifetime_s: integer}}`; remove returns `:ok` after SDK result |
| `joiner_start(session, request, timeout)` / `joiner_stop(session, options)` | S05 request/completion; start returns `{:ok, %{joined: true}}` on final join callback; it does not promise attached child role; stop returns `:ok` |
| `subscribe(session, %{type: :state, receiver: pid, ...})` / `unsubscribe(session, handle)` | S06 native C05 reports/cleanup; no invented Runtime application subscription |

All `options` and requests reject unknown keys. The timeout forms use C03's
finite bound and deadline admission; an options timeout defaults to the Session
limit. `State.role` is `:disabled | :detached | :child | :router | :leader`; no
simulator-only state or inferred reliability level. `network_name` and `rloc16`
are non-secret summaries; Network Key, PSKc and full Dataset bytes are excluded.
A role becoming child does not prove a requested application service is reachable.
`joiner_start` performs commissioning only; a caller explicitly enables Thread
and waits for a state subscription/query if attachment is part of its workflow.

`identity` is exactly `%{eui64: <<8 bytes>>}` or
`%{discerner: %{length: 1..64, value: integer}}`, never both; matching identities
compare exact bytes/bits. Joiner requests contain `pskd`, and only the optional
provisioning/vendor fields and limits in S05. Treat PSKd as an opaque secret after
validation; Inspect exposes identity/lifetime only. Unknown SDK errors retain
bounded numeric code and phase under `:remote_error`, without stringifying native
buffers. A management timeout after submission has `effect: :unknown`; a validation
failure has `effect: :none`. Callback acceptance remains separate from activation.

These decisions target OpenThread v2026.09.0 commit
`5c8c318627954c99cd1a957a290bbd4b1027d04b`, including its
[Thread role API](https://raw.githubusercontent.com/openthread/openthread/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/thread.h),
[Joiner API](https://raw.githubusercontent.com/openthread/openthread/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/joiner.h) and
[Dataset API](https://raw.githubusercontent.com/openthread/openthread/5c8c318627954c99cd1a957a290bbd4b1027d04b/include/openthread/dataset.h).
They are an SDK-derived profile, not full Thread standard verification.

## WTH-N02 — Network and application boundaries

| Behavior | Required contract | Proof owner |
| --- | --- | --- |
| Dataset/address inspection | Exact TLV bytes, semantic SDK validation and redacted native state | P01/P03, F01–F06 |
| Network formation and commissioning | Actual SDK callbacks/roles, explicit authority and final outcomes | P04/P05/P07, F07/F08, V05–V09 |
| Sleepy sensor and end-device light | Thread mesh configuration with a separately owned CoAP application fixture | P07 |
| Native subscriptions | Non-secret network State and explicit coalescing metadata; application streams belong to their protocol | P06, F09, V10/V11 |
| Delivery/payload capability | No exactly-once or universal 1280-byte application payload promise | P06/P08 |

Application recipes compose with this management client. Temperature and light
read/write functions are not native Thread services. The library owns and proves
its native management workflow independently of any Thing Description.

## WTH-N03 — Real software network and application composition

The P07 software lane creates an isolated network namespace/VM with separate
simulation RCP node IDs and storage for each host. No two instances share a radio.
Use node A to validate and form a fresh active Dataset, then require actual leader
state. Start Commissioner on A, add node B's exact identity with a 60-second
admission lifetime and fixture-only PSKd, and require B's final Joiner completion.
Explicitly enable B and require its child/router role and matching active Dataset.
A wrong PSKd must fail and leave no successful joined report. Stop commissioner
and prove its owned admission records cleared. Network secrets stay in isolated
fixture state and are not printed in the public evidence.

Submit a management Pending Set with a deliberate delayed activation. Record
callback acceptance separately from reads of the old and subsequently active
Dataset. Exercise timeout followed by late callback; no premature success, stale
delivery, new update admission while SDK exchange is active, or freed live context.
After closing both owners, prove RCP descendants, callbacks, sockets and store
locks returned to baseline. Inspect the separately started borrowed daemon in its
own fixture and prove it survives library disconnect.

Exercise the sensor/light composition as a second lane using a pinned OpenThread
software application fixture. The fixture exposes CoAP GET
`/sensor/temperature` with content format text/plain and exact payload `21.50`,
and `/light/on_off` with GET `0`, PUT `1`, then GET `1`. The CoAP client is the
CoAP package or independent libcoap selected explicitly by the runner; this
Thread library only forms/inspects the network. Use a fixture host attached to
the same isolated virtual network, or record an explicit test-only routing
component. Creating a border router is not a hidden library side effect. The
peer counts received PUTs and readbacks; label CoAP result semantics separately
from Thread attachment. A sleepy-device configuration is a software role/configuration
case, not proof of radio power consumption or guaranteed message delivery.

The fixture manifest pins application source, node IDs, addresses, routing
configuration, binaries and payloads. Missing network, peer, callback or required
application reply fails that selected lane. This composition test preserves the
useful workflow while keeping the protocol ownership boundary reviewable.

## WTH-N04 — Concrete corpus and executable acceptance

[contract-v1.json](../../../../packages/wotex-thread/priv/fixtures/contract-v1.json) is fixture format `1.0.0` with
status `specified_unexecuted`. It contains concrete examples; the broader Vxx
rows in .10 are scenario families. Neither a scenario row nor parseable JSON
counts as an executed test. All Vxx alternatives and boundaries still need tests.

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

Add `test/wotex/thread/contract_fixture_test.exs` during P01 and bind each pure
case as its API becomes available; add lifecycle cases in their owning package.
A case without an implementation remains explicitly unexecuted and prevents
accepting its package. Do not check in an always-skipped test or count an ID in
a comment as proof. Final evidence records case ID, fixture SHA-256, executable
test path, command, source revision and result. The selected runner must fail on
unknown fixture format/operation, missing assertion, mismatched output or absent
required peer. Native software workflows below require separate real peer tests.

The management lifecycle fixtures use exact disposable Dataset bytes and an
explicit `scripted_sdk_validation_result: true`. That setup isolates callback
ownership; it is not evidence that those bytes passed the real SDK. P03 must
independently exercise valid/invalid Dataset combinations through the pinned SDK,
and P07 creates its actual network Dataset through the recorded fixture setup.
