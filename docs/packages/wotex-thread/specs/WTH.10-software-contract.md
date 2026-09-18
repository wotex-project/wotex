---
spec:
  id: WTH.10
  title: "Complete OpenThread host-management software profile"
  status: accepted
  version: 1.1.1
  owner: wotex-thread
  updated: 2026-09-18
---

# WTH.10 Complete OpenThread host-management software profile

Read [WTH.00](WTH.00-library-contract.md) and the [implementation sequence](../plans/software-implementation.md).
[WTH.11](WTH.11-standalone-client-and-preservation.md) fixes the native API, protocol workflows and concrete fixture contract.
The current Dataset/daemon and native SDK management boundaries are described in
[WTH.02](WTH.02-implemented-profile.md) and executable evidence. The accepted
complete profile combines those behaviors with the joiner, state subscription,
software-network and native/tooling obligations in [WTH.13](WTH.13-native-backend.md).

## Scope and architectural decision

OpenThread v2026.09.0, commit `5c8c318627954c99cd1a957a290bbd4b1027d04b`, is the
executable reference. The complete Thread standard was not reviewed; retain the
access limit and SDK-derived status from [primary sources](../provenance/primary-sources.md).
No Thread certification is implied. Thread supplies IPv6 networking; application
Property read/write semantics belong to a protocol such as CoAP or Matter.

The host uses **Mbed TLS 3.6.7** with this SDK,
commit `068ff080b369adfac81509f9b57b2afabaf82dc5`, and its framework commit
`dde0c4a0e448a0552f18817dcea633bb851fd288`. The upstream
[3.6.7 security changelog](https://raw.githubusercontent.com/Mbed-TLS/mbedtls/v3.6.7/ChangeLog)
fixes CVE-2026-50588 in the ECJPAKE ServerKeyExchange parser used by this profile.
The native build must pin this override and record its archive hashes; using
the unmodified SDK crypto submodule is not an accepted build.

Keep `Daemon` read-only and explicitly connected to a consumer-supplied Unix
socket. `Wotex.Thread.OpenThread` is a first-party C++ host using the C SDK API.
It owns a host
OpenThread instance and explicitly configured radio URL. The bridge links the
pinned POSIX OpenThread platform and runs its event loop, processing requests
through WTH-C07. It is a separate host process, not a C pointer into an already
running ot-daemon. Never attach a second owner to the same RCP or create a hidden
system daemon. A borrowed daemon does not gain write authority from this adapter.

Required native management: Dataset validation/get, explicit first-network
formation, management Active/Pending Set, Thread/IP interface enable/disable,
Commissioner start/stop and joiner admission, Joiner start/stop, state reports.
Border-router routing/NAT64, SRP/DNS hosting, NCP firmware, radio drivers,
arbitrary CLI execution and application payload transport are separate profiles.
Radio URL and interface choices are explicit; physical radios are excluded from
the mandatory software lane, which uses OpenThread's simulated RCP/platform.

The native build also applies three unsigned casts before 24-bit shifts in the
pinned SDK's `src/lib/spinel/spinel.c`. Integer promotion otherwise shifts a
high-bit byte into signed `int`, which UBSan rejects during RCP timestamp reads.
`dependencies.json` pins exact before/after source hashes; unknown source fails
before patching, and CMake rejects unpatched SDK input. The actual Spinel decoder
is tested over all 256 high-byte values for signed/unsigned 32/64-bit fields.

## WTH-S01 — Dataset syntax and semantic validity

Preserve `Dataset.decode/1`, `encode/1` and opaque unknown TLVs with their order.
Encoded Dataset ceiling is 254 bytes. Type/length bytes are unsigned; reject
truncation, any duplicate type (including unknown), oversized values and forged
structs. Network Name is 1..16 UTF-8 bytes without U+0000..U+001F or U+007F.
Network Key and PSKc are 16 bytes, Extended PAN ID eight, Channel three,
PAN ID two, Mesh Local Prefix eight, timestamps eight, Delay Timer four and
Security Policy three or four as permitted by the pinned SDK version.

`complete?/2` retains its documented required-field-presence meaning only.
Add `validate_dataset(session, dataset, :active | :pending, timeout)` which
serializes the bounded value and calls
`otDatasetIsValid(const otOperationalDatasetTlvs *, bool aActive)` in the SDK.
At this pin the API takes **TLVs**, not an `otOperationalDataset` pointer.
Use `otDatasetParseTlvs` separately when structured field access is needed.
No pure Elixir presence check may be advertised as SDK semantic validity.

Call the pinned SDK before mutation. Its validity function requires PSKc as
well as the other required TLVs and validates individual TLV values and lengths.
The bridge additionally requires the selected Channel to belong to the parsed
Channel Mask and rejects Pending Timestamp or Delay Timer in an active Dataset;
`otDatasetIsValid` alone does not enforce those two profile rules. Pending
Timestamp and Delay Timer must be present for a pending Dataset, but validation
does not invent an ordering between active and pending timestamps or promise
acceptance against a live network's current Dataset. The management callback
owns that decision. These distinctions follow the pinned
[Dataset validity implementation](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/src/core/meshcop/dataset.cpp)
and [Dataset API](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/src/core/api/dataset_api.cpp).
The bridge returns `:invalid_dataset`
without sending network management traffic on failed validation. Unknown TLVs
survive pure roundtrip; if the SDK does not accept their semantics, return its
failure rather than removing them. Full Dataset bytes, Network Key, PSKc and
joiner PSKd never enter Inspect/logs/errors/telemetry.

## WTH-S02 — Read-only daemon boundary

Retain native `:state`, `:version`, `:network_name`, `:rloc16` operations and
the exact daemon command allowlist. A logical request owns a fresh socket or a
serialized explicitly owned socket; no shell commands. Maximum daemon output
is 8192 bytes (retain the baseline ceiling) and one completion marker. Parse fragmented/coalesced lines and
the pinned daemon response grammar, distinguish command echo from result, and
reject Error, missing Done, extra unsolicited result, invalid UTF-8 or timeout.
Return one typed result, never raw command output including error text.

State is one of disabled/detached/child/router/leader. RLOC16 is a 16-bit value;
retain an explicit unavailable status when the SDK/daemon reports no locator.
Version is bounded text and network name obeys S01. An arbitrary path in a Form
cannot become a command. A timed-out socket closes before a later request.
Borrowed daemon survives disconnect and owner death.

## WTH-S03 — Owned SDK bridge and state lifecycle

`OpenThread.connect/1` requires absolute executable, explicit radio URL,
interface name, storage directory, `storage_mode: :open_existing | :create_new`
and owner. Native configuration rejects an already owned radio/interface/store;
an exclusive storage lock prevents concurrent local owners. SDK settings and
Dataset state use owner-only permissions and durable backend storage. No default
radio selection, root escalation, system service edits or unrelated host network
changes. Explicit SDK enable/disable affects only the configured owned interface.
Tests run within an isolated network namespace or VM with explicit privileges.

The initial C07 ready envelope identifies the executable's pinned backend before
configuration. `open` then initializes the POSIX platform and one `otInstance`
and registers `otSetStateChangedCallback`; only its successful response admits
a Session. The build manifest records exact SDK, crypto and build features.
Run tasklets and platform mainloop with nonblocking request input so owner EOF,
cancel and deadlines remain observable. At most 64 admitted requests; ordinary
work uses at most 63 slots, reserving capacity for an explicit commissioner or
joiner stop. One stop may be on the wire alongside the ordinary active request;
stops precede queued ordinary work, retain separate reply/deadline correlation,
and never evict admitted work. A stop failure after submission has unknown effect.
There is one active
management update and one active joiner attempt. On EOF/close: stop owned joiner
and commissioner, unregister callbacks, disable owned Thread/IP state, finalize
instance/platform, close RCP/storage/locks and exit. Child RCP processes started
by an explicit forkpty URL are owned descendants and must terminate too.

Bridge operations: `open`, `inspect`, `validate_dataset`, `get_dataset`,
`form_network`, `set_enabled`, `management_active_set`, `management_pending_set`,
`commissioner_start`, `commissioner_stop`, `add_joiner`, `remove_joiner`,
`joiner_start`, `joiner_stop`, `subscribe_state`, `unsubscribe`, `close`.
Unknown names and unknown parameters fail before SDK calls. Dataset request/
result bytes use C07's typed base64 envelope and the 254-byte decoded limit.
Inspection returns only the named non-secret fields from S02 plus role-change
flags; secret Dataset export is a separately explicit `get_dataset` operation.

| Dataset operation | Exact C07 parameters | Success result |
| --- | --- | --- |
| `validate_dataset` | `kind: "active" | "pending"`, `dataset: {"type":"bytes","base64":"..."}` | `null`, after SDK and profile validation |
| `get_dataset` | `kind: "active" | "pending"` | exact typed bytes envelope; absent SDK data returns `dataset_not_found` |

Both operations require an acquired SDK instance and leave IPv6, Thread and
stored Dataset state unchanged. Reject extra parameters and noncanonical base64;
Dataset syntax errors use `invalid_dataset` without echoing decoded or encoded
bytes. Get is explicit credential export; inspection never calls it.


## WTH-S04 — Explicit network changes and callback completion

Native `form_network/3` accepts a validated complete active Dataset and finite
timeout. It is allowed only for an owned disabled instance with no existing
active Dataset and explicit `allow_network_creation: true` at open. Apply the
Dataset with `otDatasetSetActiveTlvs`, then enable IPv6 and Thread. Success
requires role transition to leader within the deadline; local setter return
alone is not network formation. Failure reports acquired state and conservative
unknown effect without erasing stored credentials or silently retrying formation.

C07 `form_network` parameters contain only `dataset`, the exact typed bytes
envelope. A success result is S02 State with role `leader`, IPv6 enabled and
Thread enabled. One formation may be pending; another formation or enable-state
change returns `busy` until it ends. Inspection and owner cleanup remain
responsive. Each unsuccessful formation reply from an acquired instance adds
`error.state`, the exact non-secret S02 State; the only other error fields are
`code` and optional numeric SDK `status`. Rejections use `creation_not_allowed`,
`dataset_exists`, `invalid_state`, `invalid_dataset`, `busy` or `remote_error`;
expiry uses `formation_timeout`. This operation-specific error field does not
admit arbitrary metadata on other C07 replies. If the process disappears before
a report, return the uncertain failure without inventing a state snapshot.

Native `set_enabled/3` selects explicit Boolean IPv6 and Thread states. Thread
enabled with IPv6 disabled is invalid. Disabling Thread does not erase Dataset
or credentials. Enabling Thread requires an existing active Dataset that passes
SDK and profile validation; otherwise return `dataset_required` before changing
IPv6 or Thread. This prevents enable from bypassing the explicit formation
permission: the pinned
[Mle::Start implementation](https://github.com/openthread/openthread/blob/5c8c318627954c99cd1a957a290bbd4b1027d04b/src/core/thread/mle.cpp)
can choose a PAN ID and start attachment without an installed Dataset.
C07 `set_enabled` parameters are exactly `ipv6: boolean` and `thread: boolean`;
the success result is the S02 typed State. Disable Thread before IPv6, and enable
IPv6 before Thread; do not repeat a setter when its observed state already
matches. SDK errors retain numeric status in `remote_error`. A transmitted
mutation failure has unknown effect, including a partial two-setter failure;
never infer rollback from the final status. Restrict state mutation to the owned SDK mode; daemon mode fails
unsupported. Return the observed local state after SDK completion, not a claim
about all network participants. No implicit enable is caused by read/validate.

`management_active_set/3` and `management_pending_set/3` accept the validated
Dataset plus optional extra TLVs (combined 254-byte ceiling, no duplicates) and
timeout. The update argument is exactly `%{dataset: Dataset.t()}` or
`%{dataset: Dataset.t(), extra_tlvs: [{0..255, binary()}]}`. Validate and append
extras in supplied order before encoding; duplicate types across both sources
fail. C07 parameters contain exactly the resulting `dataset` typed bytes
envelope, and its success contains exactly `accepted: true` and
`effective: "not_verified"`. Both SDK paths validate the entire merged Dataset
before submission. Use `otDatasetSendMgmtActiveSet` / `otDatasetSendMgmtPendingSet` with
callback/context. An immediate `OT_ERROR_NONE` means submitted, not accepted.
Complete only on callback acceptance/rejection/timeout. Callback acceptance means
the management exchange was accepted; it does not prove network-wide adoption
or pending activation. Return `%{accepted: true, effective: :not_verified}`;
a separately requested Dataset read may verify local effective state.

Match callback context to one request ID/generation. On timeout, retire the
request context safely and ignore a late callback without freeing memory still
owned by the SDK. Keep callback storage until callback or instance shutdown.
Do not submit another update while the SDK still has the timed-out exchange
active; return busy until it completes or close the owned instance. Never fall
back to `ot-ctl dataset set` or a local setter for a production management update.

The host returns `busy` and `invalid_dataset` for a management update only before
submitting it to the SDK; the public Error has `effect: :none`. Expiry after
submission returns the public code `:timeout` with `effect: :unknown` and
`retryable: false`, whether the host or the BEAM owner observes the deadline
first. The host's wire code for that expiry is `management_timeout`.

## WTH-S05 — Commissioner and Joiner

The pinned SDK's discerner mask shifts a 64-bit integer by 64 for the supported
maximum length. The native builder applies a digest-checked full-width mask fix
to `src/core/meshcop/meshcop.hpp`; CMake rejects an unpatched source. WTH-S05/V08
exercises actual SDK admission/removal at every length 1..64 under sanitizers.

Native Commissioner start uses `otCommissionerStart` with state/joiner callbacks.
Return success only when state becomes active, not merely after petition starts.
The public commissioner operations use .11's exact options/result contracts:
`commissioner_start(session, options)` returns `{:ok, %{state: :active}}`, and
stop returns `{:ok, %{state: :disabled}}`. Options permit only a finite `timeout`
(default Session limit). Add returns `{:ok, %{identity: identity, lifetime_s: seconds}}`;
remove returns `:ok`. Admission success means an owned SDK record was installed,
not that a joiner commissioned. C07 start/stop parameters are empty; successes
are exactly `{state: "active"}` and `{state: "disabled"}`. Add parameters contain
exactly `identity`, `pskd`, `lifetime`; success echoes the validated identity and
`lifetime_s`, both checked against the submitted request. Remove parameters
contain exactly `identity`; success is `null`.
Stop uses `otCommissionerStop` and clears this owner's admission records. An
existing externally owned commissioner/instance is not adopted or stopped.
`add_joiner/3` requires an explicit EUI-64 or discerner, PSKd and finite lifetime
(default 60, 1..3600 seconds). Wildcard admission is rejected by this profile.
Pass records to `otCommissionerAddJoiner` or `...WithDiscerner`; removal uses the
matching API and identity. Maximum 64 local admission records; reject excess
before SDK submission, while preserving a lower SDK capacity error.

`JoinerIdentity.new/1` accepts exactly `%{eui64: <<eight bytes>>}` or
`%{discerner: %{length: 1..64, value: non_neg_integer}}`; it never accepts a
wildcard. `JoinerAdmission.new/1` accepts an exact identity map or typed `identity`, `pskd` and optional
`lifetime` (default 60). `JoinerConfig.new/1` accepts `pskd` and the optional
strings below, plus an optional typed discerner identity; absence uses the
SDK's factory-EUI-derived Joiner ID. Unknown fields and forged structs fail
before native submission. Public operation boundaries accept .11 maps as well
as these validated value structs. Credential-bearing structs redact PSKd in `Inspect`.
C07 identities are exact `{type: "eui64", value: uppercase_hex_16}` or
`{type: "discerner", length: integer, value: canonical_unsigned_decimal_string}`.
The decimal value must fit the stated bit length; it is never a JSON float.

PSKd is 6..32 ASCII uppercase letters/digits excluding I, O, Q and Z, matching
the pinned SDK. Discerner is length 1..64 and a value fitting that many bits.
Joiner start requires explicit PSKd and optional provisioning URL (UTF-8 at most 64 bytes), vendor name/model/software
version (each UTF-8 at most 32 bytes) and vendor data (UTF-8 at most 64 bytes),
with no embedded NUL or control characters (library limits, additionally
subject to SDK validation), one active attempt, and uses `otJoinerStart`'s completion
callback. Success is final joiner completion, not a start return or radio scan.
Stop/timeout cancels with `otJoinerStop`; the callback generation must prevent
late completion from reviving the operation. No automatic retry or credential
logging. Existing commissioned state cannot be replaced silently.

## WTH-S06 — State subscriptions and Forms

Add native `subscribe(session, %{type: :state, receiver: pid, ...})` only for
the SDK mode. Return C05 handle after state callback registration and deliver
one initial non-secret snapshot. Reports contain selected changed fields and
the pinned SDK's numeric changed-flags mask. Unknown bits stay numeric.
Coalesce at most one latest snapshot per event-loop iteration, with the OR of
its changed flags; this is a state Property stream, not an ordered packet log.
No Dataset bytes or credentials are included. Receiver death/cancel unregisters
the local listener; the one SDK callback may remain while the owner has other
listeners, and is removed before instance finalization.

Keep existing `thread+unix` Forms explicitly labelled local management inspection,
with controller association and the four read-only paths in WTH.02. Do not add
invented Thread application writes/actions to Runtime. Native SDK management
and state subscription APIs are explicit control APIs; Runtime subscription
remains unsupported until a separate SDK Form profile is specified. C05 native
delivery applies, while C06 stream mapping is inapplicable to this profile.
Capabilities must distinguish daemon inspection from SDK management and never
claim CoAP/Matter payload support. `health_check/1` may report healthy only from
a successful explicit state query on its selected adapter.

## Acceptance scenarios and software network

| ID | Scenario | Required result |
| --- | --- | --- |
| WTH-V01 | TLV truncation/duplicates/unknown/254 or 255 bytes, forged structs | Exact roundtrip or bounded error; no secret details |
| WTH-V02 | Presence-complete but invalid channel/mask/security/timestamps; active/pending distinction | SDK validity decides; no mutation on invalid Dataset |
| WTH-V03 | Daemon split/echo/Done/Error/missing/extra/oversized output, timeout | One typed response or closed-socket failure |
| WTH-V04 | Fail each platform/instance/RCP/store acquisition; kill owner/child | Reverse cleanup, no orphan RCP or held lock |
| WTH-V05 | Create disabled empty network, existing Dataset, invalid enable combination | Only explicit authorized formation; actual leader state required |
| WTH-V06 | Management submit succeeds but callback rejects/times out; late callback | No premature success, replay or use-after-free |
| WTH-V07 | Pending Set accepted but activation delayed | Accepted is distinct from locally effective Dataset |
| WTH-V08 | Commissioner petition reject/active/stop, joiner record expiry/full/invalid PSKd | Final role state and bounded explicit admission |
| WTH-V09 | Correct/wrong PSKd, Joiner timeout/stop, late callback | Final callback result only; no automatic retry |
| WTH-V10 | Initial/changed/coalesced state, unknown flag, receiver overflow/death | Bounded non-secret reports and listener cleanup |
| WTH-V11 | Form read allowlist, wrong controller, write/credential request, extensions | No command injection or invented application semantics |
| WTH-V12 | Pinned simulated RCP/host network with two peers, daemon reads, SDK management/joining | Actual OpenThread callbacks/state exchanges; missing fixture fails |
| WTH-V13 | C09 stress/admission/matrix plus bridge corrupt/EOF/log faults | Owned process/socket/radio/settings baseline restored |

Build the pinned simulation platform with explicit CMake output directory,
`-DOT_PLATFORM=simulation` and RCP/FTD targets. Build POSIX daemon with
`-DOT_DAEMON=ON`; configure its radio URL as
`spinel+hdlc+forkpty://<absolute-built-ot-rcp>?forkpty-arg=<unique-node-id>`.
The fixture manifest records the actual executable paths from the selected
CMake output, SHA, options and node IDs; do not rely on stale documentation's
`output/simulation` path. Use the same host platform integration for the new
bridge and separate simulated RCP IDs for each instance.

The Linux software lane owns disposable namespaces/settings and at least two
network participants. Assert real role transitions, matching active Dataset,
accepted/rejected management callbacks, pending activation, commissioner/joiner
success and wrong-credential failure. Exercise the read-only daemon separately
from the SDK owner so two processes never share an RCP. These are real
OpenThread software-network exchanges using a simulated radio, not a fake
return-value adapter or a claim about physical RF performance.
