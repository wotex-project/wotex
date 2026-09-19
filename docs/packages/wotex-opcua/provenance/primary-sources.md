# OPC UA primary sources and backend authority

Review date: 2026-09-19. Standards, upstream API behavior and package policy are
separate authorities. Source inspection is not execution or certification.

## Standards

- [OPC 10000-4 1.05.07](https://reference.opcfoundation.org/specs/OPC-10000-4): Session/services, certificate validation, Browse 5.9.2 and BrowseNext 5.9.3.
- [OPC 10000-6 1.05.07](https://reference.opcfoundation.org/specs/OPC-10000-6): binary values, DataValue, Variant, ExpandedNodeId and UA TCP.
- [OPC 10000-2 1.05.06](https://reference.opcfoundation.org/specs/OPC-10000-2): security model.
- [OPC 10000-7 1.05.02](https://reference.opcfoundation.org/specs/OPC-10000-7): profiles.
- [OPC 10101 1.00](https://reference.opcfoundation.org/specs/OPC-10101): WoT URI and security binding.
- [W3C TD 1.1 Recommendation 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/): inherited core Form/Property semantics.
- [Binding Registry draft 2025-11-04](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/): draft status; no package conformance inference.

## Native backend

The exact [source manifest](../../../../packages/wotex-opcua/priv/fixtures/native-sources-v1.json) records
observed SHA-256 for downloaded source archives. Source hashes prove byte
identity, not successful compilation. WOP.07 defines all required build lanes.

- [open62541 1.5.7 client](https://github.com/open62541/open62541/blob/d1173ccc31560ffc60c29e24ce8adb19f8c3c686/include/open62541/client.h): explicit lifecycle, noReconnect/noNewSession and client-local namespace mapping.
- [Typed asynchronous service API](https://github.com/open62541/open62541/blob/d1173ccc31560ffc60c29e24ce8adb19f8c3c686/include/open62541/client_highlevel_async.h): request ID/response callbacks and cancellation primitives. WOP uses bounded asynchronous services; synchronous Cancel does not satisfy the event-loop budget.
- [Native types](https://github.com/open62541/open62541/blob/d1173ccc31560ffc60c29e24ce8adb19f8c3c686/include/open62541/types.h): signed integer UA_DateTime and complete UA_DataValue/UA_Variant fields. Native IPC retains 100 ns ticks.
- [Build options](https://github.com/open62541/open62541/blob/d1173ccc31560ffc60c29e24ce8adb19f8c3c686/CMakeLists.txt): explicit OpenSSL backend, subscriptions and reduced namespace generation.
- [OpenSSL 3.5.8](https://github.com/openssl/openssl/tree/f4dc4d58b48d346a8270183f89acf826d459b0ca): pinned cryptographic implementation. Its [release notes](https://openssl-library.org/news/openssl-3.5-notes/) identify the security maintenance release; dependency audit remains mandatory for every evidence cohort.
- [Erlang Ports](https://www.erlang.org/doc/system/c_port.html): external executable ownership. Correct native EOF handling is required for executable termination; a Port alone is not descendant containment.

## Reuse assessment

The 2026-09-16 pinned-source review of open62541's `createSessionCallback` found
that it discards `revisedSessionTimeout`; its connection-attribute API has no
revision value. The source manifest now records one narrow, reproducible patch
to retain that Double, expose it for an active Session and reset it on cleanup.
The patch preserves upstream notices and changes neither signature verification
nor policy selection. The real loopback SDK regression and remaining secure
owner requirements are recorded in executable evidence and WOP.07.

[Opex62541](https://opex62541.hexdocs.pm/introduction.html) already provides an
Elixir/open62541 stdio Port architecture. At source
[c45cb4d](https://github.com/valiot/opex62541/blob/c45cb4d532615078fd7e03039ccb8eef5e629f76/src/opc_ua_client.c),
`dataChangeNotificationCallback` passes only `data->value`, and
`handle_add_subscription` returns only `subscriptionId`. Neither exposes the
full metadata/revisions required by S04. Its unchanged wrapper is not admitted;
reviewed code reuse must preserve attribution and satisfy X01..X06. The selected
runtime is a first-party bounded service adapter, not a dependency on an
unverified wrapper fork.

[stritzinger/opcua](https://github.com/stritzinger/opcua) implements native Erlang
OPC UA. Its published services table does not claim BrowseNext, Call or
subscriptions. It does not satisfy this complete client profile as documented.

## Peer and current evidence boundary

[asyncua 2.0.1](https://github.com/FreeOpcUa/opcua-asyncio/tree/v2.0.1) supplied
the retired independent Python software peer. Its
[DateTime conversion](https://github.com/FreeOpcUa/opcua-asyncio/blob/v2.0.1/asyncua/ua/uatypes.py)
uses Python microsecond-resolution datetime and clamps extreme dates. Therefore
its service observations do not prove exact native 100 ns timestamp handling.
Pure byte vectors and the C peer carry that evidence. Its
[Node convenience code](https://github.com/FreeOpcUa/opcua-asyncio/blob/v2.0.1/asyncua/common/node.py)
accumulates Browse pages; the native target uses explicit bounded service calls.

The former per-request Python runtime adapter and Python peer have been removed.
Their recorded cohorts remain bounded historical evidence for those source
identities. The current compiled C11 peer uses the pinned open62541 stack and is
therefore same-stack evidence, not independent interoperability.
[async-opcua 0.19.0](https://github.com/FreeOpcUa/async-opcua/tree/9ad28fc011002398f2e8a95696a50408a14531d9)
supplies the current independent Rust peer for Browse continuation, Cancel and
the nine positive three-policy/three-token service workflows. The exact graph
is fixed in `Cargo.lock`; the locally patched `async-opcua-server` and
`async-opcua-nodes` crates retain their
MPL-2.0 declarations and upstream VCS identity. The package has no Python
runtime or peer asset; Python remains only in required upstream generation and
isolated audit tooling. Existing pure fixture bytes verified with asyncua are
source cross-checks, not proof of an implemented Wotex codec or native session.

Direct-CA trust, exact certificate pins, terminal Session loss, deadlines,
queue/credit ceilings, consuming continuation handles and conservative unknown
mutation effects are explicit package policies. Independent wire, native audit,
malformed-frame and resource-counter tests are required to accept them.
