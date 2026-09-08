---
spec:
  id: WOP.11
  title: "Standalone OPC UA client and feature preservation"
  status: accepted
  version: 1.0.0
  owner: wotex-opcua
  updated: 2026-09-09
---

# WOP.11 Standalone OPC UA client and feature preservation

Specification version: **1.0.0**. Status: **planned**. This extends
[WOP.10](WOP.10-software-contract.md) and corrects its former exclusion of Browse.
The [implemented profile](WOP.02-implemented-profile.md) and
[executed evidence](../provenance/executable-evidence.md) describe current
capabilities. None of the planned pure-codec, persistent-session or pagination
requirements below is accepted merely by specifying it.

## WOP-N01 — First-party client and preserved protocol assets

The package owns a usable typed OPC UA client independent of Thing Descriptions
and Runtime. A consumer supplies explicit endpoint, trust, credentials and
supervision. The package supplies the first-party SDK adapter, value conversion,
secure Session owner, browsing, monitored items and deterministic cleanup.
A consumer-written bridge factory is an extension seam, not the default product.
The SDK owns protocol security; the library owns validation and bounded public
behavior around it. Mapping and Transport adapt the native operations.

| Useful baseline asset | Required disposition | Owning surface and proof |
| --- | --- | --- |
| Four NodeId kinds and pure UA scalar/frame codecs | Preserve as independent bounded values | `Address`, `Binary`, `Frame`; WOP-S01/V01/V04 |
| ExpandedNodeId, Variant, DataValue and reference-related parsing contracts | Rewrite into complete public pure codecs with explicit tails and limits | WOP-N02; exact bytes and malformed/allocation cases |
| Native read/write and method scenarios | Preserve typed operations and compatibility success shapes | WOP-S01/S02/S05; status and individual Call result tests |
| Address-space browsing | Preserve current child-NodeId projection and add complete typed references with bounded continuation ownership | WOP-N03/N04; multi-page peer and release-failure tests |
| Monitored-item/subscription scenarios | Implement complete Publish/Republish/loss behavior | WOP-S04; registration alone is not delivery support |
| One-shot secure adapter | Retain explicit compatibility mode, including browse | WOP-N04; successful and negative same-stack tests remain labelled |
| Insecure channel/session machinery and ignored cleanup failures | Replace with the pinned secure SDK and owned failure cleanup | WOP-S02/S03; no copied None-channel implementation in production |
| WoT Forms and callback surface | Preserve exact target identity and extension terms | WOP.02 and Wotex integration contract |

The release floor is an explicit secure connection, namespace-URI resolution,
bounded typed browsing, typed read/write/readback, typed Call, monitored delivery,
cancel and close. This workflow must work through the first-party adapter without
requiring a Form or a Runtime Request.

## WOP-N02 — Public pure binary contracts

Add `Binary.encode_variant/1`, `decode_variant/1`, `encode_data_value/1`,
`decode_data_value/1`, `encode_expanded_node_id/1`, `decode_expanded_node_id/1`,
`encode_qualified_name/1`, `decode_qualified_name/1`, `encode_localized_text/1`,
`decode_localized_text/1`, `encode_reference_description/1`, and
`decode_reference_description/1`. Each encoder returns `{:ok, binary}` or
`{:error, Error.t()}`. Each decoder returns `{:ok, value, unconsumed_binary}` or
`{:error, Error.t()}`. Partial input returns `:invalid_binary`; existing
NodeId-specific errors remain `:invalid_node_id`. No decoder owns transport state.

Native Variant/DataValue maps use the .10 version 1 JSON field names as atom
keys, known type names as strings, and actual binaries for byte bodies. Version 1
always carries `array: false | true`; no inference from nil, list, dimensions or
type is allowed. Scalars omit dimensions; arrays use a flat list or nil. A null
array has no dimensions; an empty array is an empty list, not nil. The pure
DataValue decoder preserves exact DateTime ticks; SDK timestamp precision limits
remain explicit metadata on service observations. Bad DataValue status is a
valid pure decoded value; the service result adapter classifies it as failure.
Parsing a valid error response is distinct from treating an operation as success.

ExpandedNodeId is `%{node_id: Address.t(), namespace_uri: nil | String.t(),
server_index: non_neg_integer()}`. URI is nil or a nonempty UTF-8 string of at
most 4096 bytes; server index is 0..4294967295. The standard URI-presence flag
makes the encoded namespace index immaterial. Normalize it to zero on decode
and require zero when encoding an explicit URI. A present empty/null URI is
rejected by this concrete identity profile. Preserve a nonzero server index;
it does not authorize connecting to another server.

QualifiedName is `%{namespace: 0..65535, name: nil | String.t()}`.
LocalizedText is `%{locale: nil | String.t(), text: nil | String.t()}`; both keys
are required. Null and empty text differ. Their strings have the .10 64 KiB
value limit. A ReferenceDescription has exactly these fields:

```elixir
%{
  reference_type_id: Address.t(),
  is_forward: boolean(),
  node_id: expanded_node_id,
  browse_name: qualified_name,
  display_name: localized_text,
  node_class: 0 | 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128,
  type_definition: expanded_node_id
}
```

The full reference profile always requests result mask 63. Preserve namespace
and locale in names; do not flatten references to display text or accidentally
treat a remote ExpandedNodeId as a local NodeId. The two expanded fields use
the same representation; null type definition is the null NodeId with no URI
and server index zero. NodeClass zero is unspecified, not an inferred Variable.

Apply .10 element/depth/byte limits while parsing, before allocating a declared
array. Retain future Variant IDs 26..31 as the read-only opaque envelope in WOP-S01;
reject unsupported known type selectors and invalid field masks, malformed lengths
below -1, truncated elements, invalid UTF-8 and impossible dimension products.
An ExtensionObject with an unknown type remains opaque; it never loads a module
or class. Its binary or XML body retains encoding identity. Enforce depth eight across supported typed value structures and a total 1 MiB
consumed-value budget. Nested Variant/DataValue element types outside the .10
finite type table remain explicitly unsupported.
Preserve unconsumed tails exactly; do not silently consume trailing bytes.

## WOP-N03 — Bounded reference pages and continuation handles

Add `Wotex.OPCUA.Browse.references(session, node, opts \\ [])`,
`Browse.next(session, continuation)`, `Browse.release(session, continuation)`,
and `Browse.all(session, node, opts \\ [])`. These require persistent mode;
otherwise return `:persistent_session_required` before I/O.

`references/3` and `next/2` return `{:ok, %Browse.Page{references: list,
status: uint32, continuation: handle_or_nil}}` or a structured error.
`all/3` returns `{:ok, %{references: list, status: uint32}}` only after complete
pagination. `release/2` returns `:ok` only after successful release or after the
owning Session is already closed. The page list contains the complete typed
ReferenceDescriptions in server order; do not deduplicate distinct references
or sort them. Good status is retained numerically. An Uncertain status is exposed
on a page; `all/3` fails `:incomplete_browse` instead of claiming a full result.
Bad status fails with `:remote_error` and the complete numeric status.

Options are a strict keyword list with the following keys; reject duplicate and
unknown keys. Validate node and all options before admitting work.

| Option | Default | Allowed value |
| --- | --- | --- |
| `direction` | `:forward` | `:forward`, `:inverse`, `:both` |
| `reference_type_id` | `"ns=0;i=33"` (HierarchicalReferences) | Concrete NodeId; `"ns=0;i=0"` requests all reference types |
| `include_subtypes` | `true` | Boolean |
| `node_class_mask` | `0` | Integer 0..255 |
| `page_size` | `128` | Integer 1..256; never send the unbounded value zero |
| `max_pages` | `64` | Integer 1..64, total across this browse |
| `max_references` | `4096` | Integer 1..4096, total across this browse |
| `timeout_ms` | Session timeout | Integer 1..60000, capped by the caller's remaining deadline |

Use the default View (null View NodeId, zero timestamp/version) and exactly one
node per Browse operation. Nondefault Views, path translation, graph recursion
and history are separate profiles. A consumer may traverse explicit references;
the library must not recursively browse or follow remote server identities.

A continuation is an opaque `%Browse.Continuation{pid, reference, generation}`
with secret-free Inspect. Store the server bytes only inside the owner; maximum
4096 bytes, no public logging or telemetry. At most 64 live continuations per
Session and one in-flight call per handle. Each `next` consumes the handle and
returns a fresh handle if another page exists, even when the server reuses the
same opaque bytes. A repeated/foreign live handle fails `:invalid_continuation`
before I/O. Reusing the same server bytes is not itself a protocol violation.

The original absolute browse deadline, cumulative page count, reference count
and byte count survive every page. User think time counts against that deadline.
Do not refresh it on `next`. Maximum aggregate decoded references is 1 MiB;
the bridge's 128 KiB line ceiling additionally applies to each page. An empty
page with a continuation is permitted and counts toward the page bound. A page
larger than the requested page size, over-bound totals or malformed result count
fails with `:response_limit`/`:invalid_response` and starts cleanup. Exactly one
BrowseResult is required for the one requested node or continuation.

Call the pinned SDK's service-level `session.browse` and `browse_next`, not its
unbounded convenience `get_references`/`get_children` loop. Version 1 bridge adds
`browse`, `browse_next`, `browse_release`. `browse` carries concrete `node_id`,
the validated options and remaining deadline; the native owner returns complete
reference payloads and an opaque owner token. Elixir maps that token to its
generation-bound handle. `browse_next` and `browse_release` carry only that
owned token; the original filters cannot change between pages. No caller may
inject arbitrary server continuation bytes over the public API.

## WOP-N04 — Release, compatibility and failures

Stopping early, deadline expiry, owner/caller death, excess results and explicit
release send BrowseNext with `releaseContinuationPoints=true` using the latest
server continuation, on its original Session. Normal exhaustion has no live
continuation to release. Successful release expects a successful response header
and empty results/diagnostic arrays. It is not a normal one-result next page.

Release has the .00 cleanup grace of at most 1000 ms, separate from the expired
interaction deadline. On release failure, lost Browse/BrowseNext response with
possibly allocated server state, or an unidentifiable continuation: close the
Session with deletion enabled and terminate its other operations/subscriptions.
Closing a Session bounds state whose continuation bytes were never received.
Do not keep the Session alive and claim cleanup based only on local handle
deletion. A known dead Session makes later release harmless; a live consumed or
foreign handle is rejected, avoiding an unbounded tombstone registry.

Add native convenience `read_node(session, node)`, `write_node(session, node,
typed_value)` and `browse(session, node)`. Read returns `{:ok, typed_data_value}`;
write returns `:ok` only for a matching successful result. Call remains the
explicit object/method operation from .10. The root `browse/2` and existing
`send(session, %{type: :browse, node_id: ...})` compatibility path return
`{:ok, [canonical_node_id_text]}` for forward HierarchicalReferences including
subtypes, matching the current child-list purpose. It has a total 256-child
limit, preserves server order, and uses the bounded typed service path. An
ExpandedNodeId referring to a nonlocal server or namespace URI without exact
local resolution fails `:unsupported_remote_reference`; do not discard identity
to fit the old string shape. Retain duplicate child identities if distinct
references produced them.

One-shot compatibility performs all pages on the same temporary Session and
closes it afterward. It cannot issue each page on a new Session. Typed page
handles are deliberately unavailable in one-shot mode. Early limit, decode or
transport failure still releases the continuation or closes that temporary
Session. Keep existing read/write/Call one-shot result translations versioned;
do not silently change them to the richer native helper shapes.

## WOP-N05 — Concrete fixtures and acceptance binding

[contract-v1.json](fixtures/contract-v1.json) is a **specified, unexecuted**
corpus. Existing WOP-Vxx entries in .10 are scenario families, not implemented
test vectors. The starter corpus fixes representative bytes and state outcomes;
every family still requires its complete boundary/security/fault cases.

Corpus format version 1.0.0 separates `input` from `expectation`. The runner
passes only `input` to the operation/test adapter and compares the complete
declared projection using `exact`. It must not supply expected values to a fake
client. JSON atom keys and fixed enums translate through finite tables. Variants
and DataValues use .10 version 1 JSON; Address projects to canonical NodeId text,
ExpandedNodeId to its three explicit fields, and binaries/tails to lowercase
hexadecimal. Byte values within typed payloads use C07 base64 envelopes.
Errors project to `{code, effect}` with any expressly expected numeric details;
separate tests still assert Error class, secret exclusion and retry policy.

Lifecycle scripts use a virtual millisecond clock beginning at zero. They supply
peer responses, caller actions and clock advances. The exact expected projection
contains sent service order, public results, delivery counts and final resource
counts; substitute stable fixture handle names for actual PIDs/references only
in observations. Equality with a deadline is expired. A deterministic lifecycle
test is ownership/correlation evidence, not independent security interoperability.

Add normal ExUnit bindings at `test/wotex/opcua/standalone_contract_test.exs`,
native bridge bindings at `test/native/test_browse.py`, and extend the independent
open62541 fixture with enough children to force pages and expose live continuation
counts. Each binding records N/S/V IDs, case ID and SHA-256 of corpus bytes.
JSON validation or ID presence alone cannot accept a work package. Require actual
results and counters, including cancellation after page one, deadline between
pages, lost next response, and a response requiring Session closure.

## Primary source basis

OPC 10000-4 **1.05.07** defines
[Browse](https://reference.opcfoundation.org/specs/OPC-10000-4/5.9.2) and
[BrowseNext](https://reference.opcfoundation.org/specs/OPC-10000-4/5.9.3).
Reference fields and same-Session continuation/release behavior derive from
those service contracts. The numeric caps, consuming local handle, deadline
policy and conservative Session-close fallback are library choices.

The reviewed [asyncua 2.0.1 Node implementation](https://github.com/FreeOpcUa/opcua-asyncio/blob/v2.0.1/asyncua/common/node.py)
sets an unlimited requested reference count and accumulates pages in its
convenience path. That is why the target uses its lower-level service calls.
Pure encoding follows OPC 10000-6 1.05.07
[Variant](https://reference.opcfoundation.org/specs/OPC-10000-6/5.2.2.16),
[ExpandedNodeId](https://reference.opcfoundation.org/specs/OPC-10000-6/5.2.2.10) and
[DataValue](https://reference.opcfoundation.org/specs/OPC-10000-6/5.2.2.17), also recorded in
[primary sources](../provenance/primary-sources.md). The SDK is the service
implementation; it does not remove the need for independent pure-codec fixtures
or the independent secure peer required by the software plan.
