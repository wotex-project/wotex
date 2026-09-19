# WOP native software implementation sequence

This acceptance sequence defines the complete WOP.01/.10/.11/.12/.13 native
software profile. Current code/evidence is bounded by WOP.03 and
[executable evidence](../provenance/executable-evidence.md). A planned API or
fixture is not a completed implementation. Read CLAUDE, matching rules/skills,
all five target specifications, the source manifest and catalogue before work.

## Ordered work packages

Each package depends on all preceding packages. Existing valid pure values and
compatibility shapes remain part of its regression boundary. Package identifiers
are stable; a package may have several logical tested commits. The matrix is
binding implementation work, not a changelog.

| Package | Implementation and acceptance | Executable destinations | Status |
| --- | --- | --- | --- |
| WOP-P00 | X01/X02/X07: pinned SDK/OpenSSL source admission, native Mix build task, separate bidirectional custody guardian, package assets, versioned ready and both executable digests; Opex reuse obeys the reviewed metadata/security boundary | native/build_test.exs, native/build_fault_test.exs, native/workspace_test.exs; native host ready/digest/EOF tests; X01/X02 manifest/failure cases and WOP-G01..G10 native custody cases | Accepted |
| WOP-P01 | S01/N02/N05: typed pure Variant/DataValue/ExpandedNodeId/QualifiedName/LocalizedText/reference codecs, exact signed ticks and array/null/opaque distinctions; lossless JSON integer/negative-zero IPC | typed_values_test.exs; production native value/contract checks; WOP-F01..F13 and X-F01..F16 | Accepted |
| WOP-P02 | S02/X03/X04: persistent native Session activation, explicit one-shot native projection, server/local namespace mapping, complete framed IPC, credit control, bounded async requests and cancellation/EOF cleanup | persistent_bridge_test.exs; test/native/session_test.c; X-F10..F23/X-F49..F57 plus split/coalescing/malformed/partial-open matrix | Open; bounded credit-gated native output queue and 64-operation native owner with request-scoped failures, nonblocking cancel and health implemented; the internal BEAM host admits 64 concurrent monitored callers with timeout/death cancellation and per-request terminal effects and identity-bearing values are projected between SDK-local and server namespace indexes; the public persistent handle admits Read/Write/Call from any process and a counter-bearing secure peer proves close deletion and open-phase owner-death release; explicitly selected public native client now owns persistent and one-shot secure Sessions and projects typed Value Read/Write/Call maps in persistent mode and legacy success shapes in one-shot mode, bounded child Browse and a persistent-only complete typed reference page; one-shot failures are shown against the same-stack peer to carry the same native code, effect and class as persistent mode for timeout, connection failure, Bad status, unsupported type, invalid request and authentication failure; remaining services, cross-stack parity and full lifecycle remain |
| WOP-P03 | S03: all three SignAndEncrypt policies and all three user-token modes, pin/SAN/URI/CRL/key validation, immutable trust, no downgrade/reconnect/replay | priv/native/security_check.c; test/native/security_test.c; test/interop/security_fault_test.exs; test/interop/rust_peer_test.exs; X-F30..F47 | Open; native credential preflight, SDK verifier/configuration and finite authentication/certificate failure projection implemented; both the same-stack C peer and independent async-opcua Rust peer execute all nine X-F30..F38 policy/token Session cells for Read/Write/Call/Browse/subscribe/unsubscribe/close with peer subscription and MonitoredItem counters returning to zero, zero live continuations and zero local processes after close; both execute X-F39..F47 fail-closed rejection/fault cells, with each isolated Rust peer recording zero accepted application requests and the client leaving no Session or helper process; V09 tampered and replayed response chunks through a byte proxy fail Read and Write (Write effect unknown) and end the Session; username token algorithms match each advertised policy; the secure, policy/token and fault suites pass in the Linux lanes on both runtimes for their recorded same-stack cohort; forged service/requestHandle content (not constructible without channel keys) remains |
| WOP-P04 | S04/X05: raw service-level subscriptions, exact revised parameters, full DataValue/overflow metadata, bounded Publish ACK and Republish sequence state | priv/native/subscription_check.c; priv/native/publish_sequence_check.c; persistent_bridge_test.exs; test/interop/native_subscription_test.exs; X-F24..F28 | Open; native raw-service subscribe/unsubscribe, bounded Publish with acknowledgements and backpressure, Republish recovery, lifetime loss and report projection bind X-F21 and X-F24..F29 (native traces and Session processing); the BEAM host and public persistent API deliver initial and fresh reports, bound receiver queues, cancel late or abandoned subscriptions and return same-stack peer subscription and MonitoredItem counters to zero; the same-stack peer proves one-time ordered Republish recovery, unavailable-Republish `sequence_gap`, StatusChange `subscription_lost` and overflow InfoBits with peer counts at zero; a peer Bad Publish acknowledgement status closes the Session and returns peer counts to zero; a peer lifetime expiry while the SDK process is stopped ends the subscription as subscription_lost; the independent Rust peer proves initial/fresh report ordering and metadata, idempotent cancellation, receiver-death isolation and terminal-once receiver overflow with zero peer resources and a usable Session; stopping the SDK beyond the revised lifetime independently expires the server subscription, returns peer counts to zero and delivers one subscription_lost after resumption without ending the Session; terminating an isolated Rust server emits one connection_failed, ends the Session and local helpers without reconnect/replay, and a newly started peer serves only through an explicit fresh connection; the independent peer also withholds one notification to prove ordered one-time Republish recovery, then discards one to prove terminal `sequence_gap`, with both Republish requests counted by the server; the destinations are priv/native/subscription_check.c, test/wotex/opcua/persistent_bridge_test.exs and test/interop/native_subscription_test.exs |
| WOP-P05 | C03/C05/S02/S04/X04/X05: receiver/Session/owner loss, cancellation failure, saturated output, partial-open/final-owner handoff and terminal-once cleanup | test/wotex/opcua/subscription_lifecycle_test.exs; priv/native/owner_check.c; persistent_bridge_test.exs; test/interop/rust_peer_test.exs; X-F18..F23/X-F29 and suspended-owner overproducer stress | Open; owner death with live subscriptions, a failed server delete, peer loss and a suspended owner under a continuous same-stack report producer end each subscription once and release native processes and peer resources; output written before native exit is handled in order; X-F23 final-owner handoff is bound at the Runtime transport boundary with an injected streaming client; X-F19's Runtime class is bound through the host; at the second independent peer (async-opcua) a timed-out Call and a Call whose caller died each reach the server's Cancel service, counted by the server, and the Session keeps serving after both late responses; independent receiver death cancels only its subscription, independent receiver overflow emits one terminal error and independent lifetime expiry emits one subscription_lost with peer counts returning to zero and the Session still usable; independent server loss emits one connection_failed, reaps the Session helpers and requires an explicit fresh connection; the same loss through a real Runtime child emits one unavailable error and one transport_down, stops the observation owner and reaps the relay helpers without reconnect; a native lifecycle destination beyond priv/native/owner_check.c remains |
| WOP-P06 | S05: typed Runtime Property observation and explicit health probe, native one-shot compatibility projection, unsupported Event/credential rejection | runtime_stream_test.exs; real Runtime child-spec lifecycle tests | Open; `health_check/2` Read probe implemented with same-stack evidence; Runtime observeproperty relay with real ConsumedThing child specifications, owner death/stop/peer loss cleanup, Event and credential rejection implemented with same-stack evidence; the independent async-opcua peer executes scalar Double read/write through both production Runtime profiles, observation cleanup on explicit stop, owner death and terminal peer loss, and Int32/Double array plus dimensioned Int16 matrix roundtrips through ConsumedThing; peer loss emits one classified error and one transport_down, stops the owner, reaps the relay helpers and requires an explicitly fresh child for a replacement peer; X-F23 is bound with an injected streaming client; typed Runtime arrays of every supported scalar, DateTime, Guid, NodeId and StatusCode type return only after complete Variant validation; broader independent wire types remain |
| WOP-P06a | N01/N03/N04/N05: typed bounded Browse/BrowseNext/release, original Session/deadline, early-release/failure fallback and native root helpers | standalone_contract_test.exs; priv/native/browse_trace_check.c; open62541_test.exs; test/interop/native_paged_test.exs; test/interop/rust_peer_test.exs; WOP-F14..F16 and complete N boundary matrix | Open; persistent typed handles, next/release/all, original-deadline/cumulative bounds and persistent/one-shot child-list pagination pass C response fixtures and a secure same-stack multi-page wire peer; native C owns up to 64 continuation chains with per-chain bounds, a duplicate native token ends the generation, and an unconsumed continuation is released at its original deadline (failed release closes the Session) with probe and same-stack wire evidence; WOP-F14..F16 execute through the native browse trace with an injected SDK send boundary, an injected clock and the scripted host role, with mutants; at the second independent peer (async-opcua, 40 children) the server's live continuation-point count follows Browse, BrowseNext, explicit release, two concurrent chains, `max_references`/`max_pages` failures and deadline expiry back to zero, and `all/3` and child-list Browse return the children in server order; the rest of the N boundary matrix remains |
| WOP-P07 | X06/S01..S04: compiled secure peer in the admitted stack, an independent peer for the full policy/token/security matrix, async-opcua BrowseNext/release and Cancel counts, typed methods/arrays/users, subscriptions and continuation counters | test/interop/native_secure_test.exs; test/interop/native_paged_test.exs; test/interop/rust_peer_test.exs; full V01..V14 software assertions | Open; the compiled open62541 C peer passes the secure, policy/token, fault, subscription and lifecycle suites. The async-opcua Rust peer independently supplies BrowseNext/release and Cancel counts, executes all X-F30..F38 policy/token service workflows with resource counters returning to zero, rejects every isolated X-F39..F47 fault before application traffic, roundtrips Int32/Double arrays plus a dimensioned Int16 matrix through Runtime and proves initial/fresh monitoring, idempotent cancellation, receiver-death isolation, terminal-once receiver overflow, ordered Republish recovery, unavailable-Republish termination, server-proven lifetime expiry and terminal server loss without reconnect/replay through both the native Session and Runtime observation paths. Broader typed wire breadth and the remaining V01..V14 assertions remain. |
| WOP-P07a | I01..I06: exact profiles and Form/context/media selection, Result identity/metadata, complete Error/Retry table, final-owner custody and cleanup through real ConsumedThing | runtime_integration_test.exs; all wotex-integration-v1.json cases and I06 matrix | Open; one native one-shot Runtime ByteString Form Write/readback path is proven; the Runtime observation relay runs through real child specifications; Error.class and the complete I04 retry table bind WOP-I-F02..F07; static one-shot/session profiles, contentType rejection and persistent Read/Write projection bind WOP-I-F01 and pass same-stack read/write/observe; both profiles also read/write a scalar Double against the independent async-opcua peer, whose real observation releases peer and local resources after stop, owner death and terminal peer loss, with an explicitly fresh child required for a replacement peer; its ConsumedThing array slice roundtrips Int32, Double and dimensioned Int16 values; an exact-archive consumer runs the native secure workflow and the Runtime integration suite passes on both required runtimes (X-F48); broader independent wire types and the remaining I03/I05/I06 cells (Action/Call Forms stay native-only) remain |
| WOP-P08 | C09/C10/X06: complete software Mix tasks, audit/sanitizer/matrix/stress and isolated native archive consumer with no runtime Python; evidence contains every S/N/I/X assertion and current digest | test/software/lifecycle_stress_test.exs; X-F48; full software runner and out-of-tree package workflow | Open; earlier cohorts passed the software tasks with the retired hash-pinned Python peer. The current task builds the peer as a content-bound C artifact and retains only the isolated pip-audit lock; current-source full-lane receipts must be regenerated. Earlier macOS arm64, Linux arm64 and translated x86_64 results remain historical evidence for their exact source identities; a native x86_64 host remains. |

Paths without a directory prefix in the table are under `test/wotex/opcua/`.
All referenced tests and Mix tasks are required implementation unless present
and already asserting the exact contract. No success-shaped placeholder, skipped
required facility, fixture echo or test identifier alone satisfies acceptance.

The status column applies to the exact sources, toolchains and executions in
the evidence document. P00 acceptance establishes source/build/bootstrap and
portable guardian custody only. P01 adds pure typed values and native SDK value
projection, including an exact-match namespace translation primitive; it does
not acquire a server NamespaceArray or accept a secure native Session or any
later service, subscription, Runtime, peer, stress or archive-consumer packet.
The initial P02 input slice executes the strict parser inside the SDK process,
validates a closed outer request envelope and rejects expired native deadlines.
The pure BEAM `Native.Frame` encodes the outer request and conservatively maps
the separately sampled owner clock onto the native clock. The native build
test passes that encoded frame to the actual executable.
The internal host now sends a single owner-bound frame through custody and
decodes one generation-matched terminal error; invalid or unsolicited output
ends that process. Correlated secure open/read/write/call/close responses are now
admitted and replenish consumed credit.
Native `open` parameters now reject unknown keys, insecure modes/policies,
noncanonical bytes and invalid user-token/timeout shapes before any SDK I/O.
Native credential preflight now verifies DER/PKCS#8, RSA key pairs, direct-CA
trust, certificate usage/validity/signatures, exact SAN/URI and the issuer CRL.
Its C-generated test corpus includes positive and negative credentials. The
reusable peer verifier now runs as an SDK callback in a separate C Session
probe. Configuration tests cover all three policy names and user-token shapes;
the independent peer proves one Basic256Sha256 anonymous Session and explicit
NamespaceArray read in both the C probe and production owner. This is a
security prerequisite of P02, not acceptance or reordering of P03.
The owner and C ingress now share an explicit first credit control and fixed
generation. Open/read/write/call/close output consumes credit and the BEAM owner replenishes it;
bounded service/report queues remain required. The production service slice
does not accept P02 or X-F17..F23 as a complete family.
The SDK build now preserves the server's actual revised Session timeout through
one digest-checked patch. Three real SDK Sessions against an isolated C loopback
peer verify fractional and integer values, copy lifetime and cleanup. This
test-only Security None lane is a prerequisite for accurate native open metadata.
The new pinned secure discovery patch, C probe and executable owner cover one
independent secure peer. The full service, lifecycle and policy/token matrix
remains open.
The next P02 slice issues one asynchronous Value Read per admitted request,
translates a concrete server namespace index through its URI to the SDK-local
index and returns a bounded typed DataValue. At that stage it rejected
NodeId-bearing results pending inverse translation. A Bad attribute StatusCode is retained in a
finite `remote_error`. Independent-peer read/read-failure checks do not accept
the complete S02/X04 operation, concurrency or cancellation contracts.
The next P02 slice sends one asynchronous typed Write with an SDK-owned value
copy, preserves the individual numeric result status and never retries. A Bad
status or timeout after submission retains unknown effect. Independent-peer
Write/readback and Bad Write checks are a partial service slice, not complete
S02/X04 or P02 acceptance.
The next P02 slice sends one asynchronous Method Call with concrete object and
method NodeIds translated through the server URI and SDK-local namespace map.
It copies up to 64 typed input Variants into SDK-owned memory and retains them
through the callback, then returns method status, ordered input argument
statuses and typed outputs. Bad method status or uncertain post-submission
failure retains unknown effect, with no retry. NodeId-bearing arguments and
outputs then awaited namespace translation. The independent-peer addition and
owner timeout case remain partial S02/X04 and P02 evidence.
The native configuration helper now validates exact Elixir option, policy and
token shapes without reading files, then snapshots bounded regular credential
files under the caller's deadline into the closed native `open` map. A separate
independent-peer check opens and closes a secure Session using that projection.
The explicitly selected public `Open62541` client now uses this projection for
persistent and one-shot Session ownership. An independent secure peer passes
public read, Write/readback, Method Call and one-shot read. The Python runtime
adapter has been removed; complete error/lifecycle compatibility and typed Browse pagination,
subscriptions, cancellation and the remaining security/lifecycle matrix remain
open.
The facade now keeps a native client's finite local Write/Call validation and
configuration rejections at `effect: :none`, while uncertain mutation failures
remain unknown. This is partial X04 effect classification, not full cancellation
or lifecycle acceptance.
One additional independent-peer case writes and reads back a typed ByteString
array through the public native client, preserving embedded zero and binary
octets. It extends the partial P02 service evidence without accepting the full
typed-value or lifecycle matrix.
The next P02/N03 slice uses service-level Browse with an explicit 1..256 page
size. It retains all seven ReferenceDescription fields and projects only a
complete page of local child NodeIds through the selected public native client.
At that stage, oversized server pages and continuations closed the native
Session; BrowseNext, release, typed page handles and original-deadline
pagination were still open. Independent-peer tests exercised complete-page results,
server page-limit failure and public persistent/one-shot projection.
The subsequent N03 partial slice exposes complete seven-field reference pages
through persistent-only `Browse.references/3`. Strict finite option validation
precedes I/O; native frame validation and pure reference codecs retain typed
identities and server order. Remote ExpandedNodeIds remain data, unknown local
namespace indices fail, and excess references fail. At that stage a
continuation still closed the native Session.
The next native-only N03 slice adds an internal opt-in for one C-owned
continuation point. BrowseNext consumes its local token and can return a fresh
token even when the server bytes repeat; Browse release expects an empty result.
Cumulative 64-page, 4096-reference and 1 MiB binary-result ceilings fail closed.
The BEAM frame validates local token syntax. At that stage the public host
closed on every returned continuation pending handle ownership.
The next persistent typed slice binds a native local token to a BEAM reference
and generation. `Browse.next/2` consumes it, `release/2` sends bounded cleanup,
and `all/3` collects ordered pages without refreshing the original deadline.
Deterministic response fixtures cover reuse/foreign references, empty first
page, cap exhaustion, Uncertain status and release failure. The native owner
still has only one live continuation and the former asyncua peer could not
exercise BrowseNext; compatibility child-list pagination was separate at that stage.
The next N04 compatibility slice uses that page owner for child-list Browse on
one persistent or temporary one-shot Session. It preserves server order and
duplicates, caps the complete list at 256, and releases a cursor after a later
invalid identity or Uncertain status. Deterministic response fixtures cover
both lifecycles; independent-peer BrowseNext/release evidence was still absent.
The retired asyncua peer ignored the requested page size and did not implement
BrowseNext, so it claimed no wire pagination or release. The
independent peer, on the async-opcua Rust stack, now supplies that evidence with
the server's own live continuation-point count.
The following N04 compatibility slice maps one-shot native Read to the older
`{type, value, status}` envelope, Write success to `"written"`, and Call to nil,
one value or an ordered list. It also preserves ByteString envelopes. The
independent secure peer and C response fixture exercise the successful shapes;
error/status and full lifecycle compatibility remain open. Persistent operations
continue to expose richer typed native results.
One I01 integration slice decodes the existing Form mapper's validated base64
ByteString only when the selected transport client is `Open62541`, then hands
the raw bytes to its typed Write boundary. A C response fixture asserts the
native IPC byte envelope; an independent secure peer passes Runtime Form
Write/readback/restore. Other clients keep the existing mapping unchanged.
The following I03 partial slice decodes bounded flat ByteString arrays from
one-shot native Read through Runtime Form selection. The independent peer
confirms ordered binary elements after typed Write; the value adapter rejects
malformed envelopes, excess elements and aggregate byte overflow.
An additional I03 partial slice admits explicit ByteString flat-array inputs
through the Form mapper, checks the pure Variant limits, decodes the validated
base64 elements only at the selected native transport boundary, and sends the
typed array through native Write. A C frame fixture and independent secure
peer check Write/readback. A further S05 slice admits typed arrays of every
supported scalar type through the Form mapper and returns scalar and array
Variants of Null, Boolean, integer, Float, Double, String, DateTime, Guid,
ByteString, NodeId and StatusCode types, with `opcua_dimensions` for a matrix,
from persistent native Reads and observations only after complete Variant
validation; the independent secure peer reads, writes and restores Int32 and
Double arrays. Full I03 acceptance remains open.

## Verification and evidence

Each package runs focused assertions, then the complete `WOTEX_PATH_DEPS=1 mix
check --no-retry` gate before its local commit. Native changes also run CTest and
the applicable audit/sanitizer lanes. Normal Hex dependency identity remains
authoritative; the path switch is development evidence only. Coverage and audit
thresholds remain intact. No knowingly failing package is committed.

`mix wotex.native.build --workspace ABS` supplies the production helper.
`mix wotex.software.build --workspace ABS` builds pinned disposable peers.
`mix wotex.software.run --workspace ABS --core-archive ABS --runtime-archive ABS`
runs every required test, audit, archive consumer and cleanup assertion under
WOP-X06. Workspace source/toolchain/options/binary
manifests reject unrelated contents and stale reuse. No task starts hardware,
configures a remote, publishes, tags or pushes.

A requirement record names its exact asserting test, case ID, corpus SHA-256,
source/archive/fixture identities, runtime/native cohort, command, exit status
and resource counters. Independent-peer, same-stack C, injected-contract and
pure-codec evidence remain distinct. Native DateTime exact-tick assertions use
the C lane; Python's normalized timestamps cannot discharge them. Required
missing setup is a failure under WOTEX_REQUIRE_SOFTWARE=1.

Final acceptance includes all C09 operation/concurrency/lifecycle counts, all
supported native OS/CPU cohorts, minimum/current Elixir/OTP, native dependency
audits, ASan/UBSan, remote cleanup/expiry counters and an isolated archive-only
consumer. Its runtime starts no Python, shell or compiler. Hardware testing,
certification, publication and consumer parity are separate claims and do not
excuse unfinished software. The catalogue and current-profile documentation
state only the cells with current executed evidence.
