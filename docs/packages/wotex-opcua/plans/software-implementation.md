# OPC UA software implementation

The accepted software profile is implemented. This document keeps the delivery
order and executable ownership readable without preserving the incremental
history of how each slice landed. Exact run identities and historical receipts
remain in [executable evidence](../provenance/executable-evidence.md); fresh
platform runs follow the [qualification runbook](qualification.md).

## Delivery map

Each packet depends on the packets above it. A test double proves only the seam
it controls; wire and lifecycle claims use the same-stack C peer or the
independent async-opcua Rust peer as stated below.

| Packet | Implemented boundary | Primary executable owners | Status |
| --- | --- | --- | --- |
| WOP-P00 | Pinned open62541/OpenSSL admission, static build, executable identity, ready protocol and bidirectional custody guardian | `native/build_test.exs`, `native/build_fault_test.exs`, `native/custody_test.exs`, `bin/check_native_custody.exs` | Accepted |
| WOP-P01 | Typed Variant/DataValue/identity/reference codecs, exact DateTime ticks, null/empty distinctions and native JSON projection | `typed_values_test.exs`, `standalone_contract_test.exs`, `priv/native/value_check.c`, `priv/native/native_contract_check.c` | Accepted |
| WOP-P02 | Persistent and one-shot Sessions, namespace resolution, bounded framed IPC, output credit, 64-operation admission, cancellation and terminal cleanup | `persistent_bridge_test.exs`, `native_secure_test.exs`, `native_lifecycle_test.exs`, `oneshot_error_parity_test.exs` | Accepted |
| WOP-P03 | Three SignAndEncrypt policies, three user-token modes, immutable trust, pin/SAN/URI/CRL/key checks, downgrade rejection and no replay | `security_fault_test.exs`, `tampered_traffic_test.exs`, `rust_peer_test.exs`, `priv/native/security_check.c` | Accepted |
| WOP-P04 | Service-level monitored values, revised parameters, Publish acknowledgements, bounded Republish recovery and exact sequence integrity | `native_subscription_test.exs`, `persistent_bridge_test.exs`, `rust_peer_test.exs`, `priv/native/publish_sequence_check.c` | Accepted |
| WOP-P05 | Receiver, Session and owner loss; cancellation failure; saturated output; final-owner handoff; terminal-once cleanup | `subscription_lifecycle_test.exs`, `native_lifecycle_test.exs`, `runtime_stream_test.exs`, `rust_peer_test.exs`, `priv/native/owner_check.c` | Accepted |
| WOP-P06 | Health probe, typed Runtime Property reads/writes/observations, explicit unsupported Event/credential boundaries and final-owner relay | `runtime_integration_test.exs`, `runtime_stream_test.exs`, `native_runtime_stream_test.exs`, `rust_peer_test.exs` | Accepted |
| WOP-P06a | Typed bounded Browse/BrowseNext/release, filters, cumulative limits, original deadline, continuation ownership and compatibility child collection | `open62541_test.exs`, `native_paged_test.exs`, `rust_peer_test.exs`, `priv/native/browse_trace_check.c` | Accepted |
| WOP-P07 | Same-stack C workflows plus independent Rust policy/token, fault, Browse, Cancel, subscription, Runtime and resource-counter evidence | `native_secure_test.exs`, `native_paged_test.exs`, `native_subscription_test.exs`, `rust_peer_test.exs` | Accepted |
| WOP-P07a | Public core/Runtime integration, exact profiles, route/media selection, Result identity, error/retry classes and integration corpus | `runtime_integration_test.exs`, `runtime_stream_test.exs`, `native_runtime_stream_test.exs`, `priv/fixtures/wotex-integration-v1.json` | Accepted |
| WOP-P08 | Explicit software build/run, dependency and source audits, normal and sanitizer CTest, lifecycle stress, runtime matrix and exact-archive consumer | `native/software_test.exs`, `test/software/lifecycle_stress_test.exs`, `Wotex.OPCUA.Native.Software` | Accepted |

## Acceptance boundaries

The public profile contains typed values; persistent and one-shot secure
Sessions; Read, Write and Call; bounded typed and child-list Browse; monitored
Value subscriptions; and Runtime Property reads, writes and observations. It
does not imply History, PubSub, EventFilter, failover, reverse connect,
certification or the complete OPC UA standards family.

The independent Rust peer binds every admitted policy/token combination and
every named security rejection before application traffic. It also provides
server-side counts for Cancel, continuations, subscriptions, MonitoredItems,
Republish, secure-channel renewal and Writes. Destructive cases use isolated
peer instances, so a lost response can prove both the request boundary and the
client's terminal cleanup without contaminating another assertion.

Browse acceptance includes filtered references in every direction, local and
remote ExpandedNodeIds, unknown namespace handling, duplicate and empty pages,
Uncertain and Bad statuses, malformed result envelopes, lost responses,
aggregate byte limits, 64 simultaneous continuations and owner death. The same
server counters prove explicit release and implicit Session cleanup.

Subscription acceptance includes malformed creation and cancellation replies,
the 32-handle bound, duplicate and conflicting Publish sequences, Republish
success and failure, overflow, lifetime expiry, receiver death, peer loss and
an invalid Session response after an applied Write. Every terminal path asserts
the documented effect and returns owned resources to baseline.

Runtime acceptance uses real `ConsumedThing` calls and child specifications.
It covers the complete supported scalar set, every supported non-null array,
every writable array, a dimensioned matrix, exact metadata, explicit stop,
owner death and peer loss. Action/Call Forms and Events are intentionally not
advertised; Call remains a native API.

## Verification

Focused changes use the package test or impact command, followed by
`mix check.fast --package wotex-opcua`. Native source changes also use
`mix native.lint --package wotex-opcua`. The explicit software runner owns the
full native build, peers, audits, sanitizer tree, stress suite and exact-archive
consumer; it is not part of a routine bounded edit.

The archive consumer unpacks exact `wotex`, `wotex_runtime` and `wotex_opcua`
archives, builds the helper from the dependency, performs six public secure
operations and asserts that no Python, shell or local helper remains. Registry
publication is not asserted.

Source implementation status does not claim that every platform receipt is
fresh. Runtime, OS, architecture, sanitizer and published-artifact adoption are
qualification dimensions recorded separately from the catalogue.
