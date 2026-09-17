# WOP native software implementation sequence

This acceptance sequence defines the complete WOP.00/.10/.11/.12/.13 native
software profile. Current code/evidence is bounded by WOP.02 and
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
| WOP-P02 | S02/X03/X04: persistent native Session activation, explicit one-shot native projection, server/local namespace mapping, complete framed IPC, credit control, bounded async requests and cancellation/EOF cleanup | persistent_bridge_test.exs; test/native/session_test.c; X-F10..F23/X-F49..F57 plus split/coalescing/malformed/partial-open matrix | Open; bounded credit-gated native output queue and 64-operation native owner with request-scoped failures, nonblocking cancel and health implemented (BEAM host still single-flight); explicitly selected public native client now owns persistent and one-shot secure Sessions and projects typed Value Read/Write/Call maps in persistent mode and legacy success shapes in one-shot mode, bounded child Browse and a persistent-only complete typed reference page; complete compatibility projection, remaining services and full lifecycle remain |
| WOP-P03 | S03: all three SignAndEncrypt policies and all three user-token modes, pin/SAN/URI/CRL/key validation, immutable trust, no downgrade/reconnect/replay | priv/native/security_check.c; test/native/security_test.c; test/interop/security_fault_test.exs; X-F30..F47 | Open; native credential preflight and SDK verifier/configuration implemented; independent-peer matrix and production integration remain |
| WOP-P04 | S04/X05: raw service-level subscriptions, exact revised parameters, full DataValue/overflow metadata, bounded Publish ACK and Republish sequence state | subscription_test.exs; test/native/subscription_test.c; X-F24..F28 | Open |
| WOP-P05 | C03/C05/S02/S04/X04/X05: receiver/Session/owner loss, cancellation failure, saturated output, partial-open/final-owner handoff and terminal-once cleanup | subscription_lifecycle_test.exs; test/native/lifecycle_test.c; X-F18..F23/X-F29 and suspended-owner overproducer stress | Open |
| WOP-P06 | S05: typed Runtime Property observation and explicit health probe, native one-shot compatibility projection, unsupported Event/credential rejection | runtime_stream_test.exs; real Runtime child-spec lifecycle tests | Open |
| WOP-P06a | N01/N03/N04/N05: typed bounded Browse/BrowseNext/release, original Session/deadline, early-release/failure fallback and native root helpers | standalone_contract_test.exs; test/native/browse_test.c; WOP-F14..F16 and complete N boundary matrix | Open; persistent typed handles, next/release/all, original-deadline/cumulative bounds and persistent/one-shot child-list pagination pass C response fixtures and a secure same-stack multi-page wire peer; native C owns one token; multiple live continuations, independent-peer BrowseNext and release counters remain |
| WOP-P07 | X06/S01..S04: independent asyncua secure peer and same-stack exact-tick/fault C peer, typed methods/arrays/users, subscriptions and continuation counters; all policy/token/security cells execute | test/interop/native_secure_test.exs; test/interop/native_paged_test.exs; full V01..V14 software assertions | Open |
| WOP-P07a | I01..I06: exact profiles and Form/context/media selection, Result identity/metadata, complete Error/Retry table, final-owner custody and cleanup through real ConsumedThing | runtime_integration_test.exs; all wotex-integration-v1.json cases and I06 matrix | Open; one native one-shot Runtime ByteString Form Write/readback path is proven, but the profile factory and full matrix remain |
| WOP-P08 | C09/C10/X06: complete software Mix tasks, audit/sanitizer/matrix/stress and isolated native archive consumer with no runtime Python; evidence contains every S/N/I/X assertion and current digest | test/software/lifecycle_stress_test.exs; X-F48; full software runner and out-of-tree package workflow | Open |

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
index and returns a bounded typed DataValue. It rejects NodeId-bearing results
until inverse translation exists. A Bad attribute StatusCode is retained in a
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
outputs await full namespace translation. The independent-peer addition and
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
still has only one live continuation and the independent asyncua peer cannot
exercise BrowseNext; compatibility child-list pagination was separate at that stage.
The next N04 compatibility slice uses that page owner for child-list Browse on
one persistent or temporary one-shot Session. It preserves server order and
duplicates, caps the complete list at 256, and releases a cursor after a later
invalid identity or Uncertain status. Deterministic response fixtures cover
both lifecycles; independent-peer BrowseNext/release evidence is still absent.
The existing independent asyncua peer ignores the requested page size and does
not implement BrowseNext, so no wire pagination or release acceptance is claimed.
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
malformed envelopes, excess elements and aggregate byte overflow. General
typed arrays and Runtime result metadata remain open.
An additional I03 partial slice admits explicit ByteString flat-array inputs
through the Form mapper, checks the pure Variant limits, decodes the validated
base64 elements only at the selected native transport boundary, and sends the
typed array through native Write. A C frame fixture and independent secure
peer check Write/readback. Other typed array types and full I03 acceptance remain
open.

## Verification and evidence

Each package runs focused assertions, then the complete `WOTEX_PATH_DEPS=1 mix
check --no-retry` gate before its local commit. Native changes also run CTest and
the applicable audit/sanitizer lanes. Normal Hex dependency identity remains
authoritative; the path switch is development evidence only. Coverage and audit
thresholds remain intact. No knowingly failing package is committed.

`mix wotex.native.build --workspace ABS` supplies the production helper.
`mix wotex.software.build --workspace ABS` builds pinned disposable peers.
`mix wotex.software.run --workspace ABS` runs every required test, native audit
and cleanup assertion under WOP-X06. Workspace source/toolchain/options/binary
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
