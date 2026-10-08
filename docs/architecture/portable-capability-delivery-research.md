---
title: "Portable Protocol Delivery Without Consumer Coupling"
type: research
status: active
terminal_state: bounded_validation
version: "0.1.0"
created: "2026-10-03"
source_revision: "c8c727a7c8c18fec82d80cc5ba88d246af3c67fc"
---

# Portable Protocol Delivery Without Consumer Coupling

## Decision

Retain WoTEx's independently consumable, passively loaded libraries and consumer-owned authority. Validate artifact delivery selectively for independently replaceable codecs and native protocol hosts. Do not replace every Mix project with a dynamically loaded plugin, introduce a mandatory orchestration engine, or treat all protocol bindings as pure WebAssembly computation.

The desired property is independent delivery **where independent delivery solves an actual boundary problem**. Hex is suitable for an SDK or reusable Elixir library. It should not be the only possible delivery mechanism for a consumer-selected executable implementation. These statements are compatible.

This memo is bounded research. It adds no runtime, dependency, package release, required background service or new network behavior. Source and documentation inspection are not independent protocol interoperability or physical qualification.

## Evidence and question

Baseline: `c8c727a7c8c18fec82d80cc5ba88d246af3c67fc`. The audit read the root working contract, README, documentation index and package-level runtime/protocol ownership described there. It did not execute all protocol packages or inspect every consumer. This cross-family question belongs in `docs/architecture/`; package-specific specifications remain under their existing owners.

Observed architecture [S1–S3]: a Thing Description is parsed/validated separately from Runtime interaction planning. Form selection chooses a compatible binding; consumers retain credentials, authorization, connection policies, supervision and canonical effects. Subscription APIs expose consumer-supervised work. Several native protocols already have explicit external owners. No package count implies support for every operation of every protocol.

**Question:** which parts can acquire a verified implementation without rebuilding an embedding host, while preserving WoTEx's description, protocol and lifecycle semantics?

## Classify before changing packaging

| Existing kind | Recommended delivery | Why |
|---|---|---|
| Thing Description validation and generic value types | Ordinary passive library / independently implemented standard contract | A language library is not a marketplace plugin problem |
| Declarative Forms, schemas and device mappings | Versioned data artifacts | Data selection should not execute downloaded code |
| Pure byte/value codecs | Optional bounded executable artifact profile | A changing device-format population may warrant independent decoder delivery |
| Consumer HTTP/MQTT clients | Consumer-owned transport behind the existing port | Host connection, TLS, session and egress policy must remain explicit |
| Native protocol controller | Signed target-specific executable closure plus lifecycle contract | Dependencies and hardware custody differ from pure codecs |
| Commissioning, pairing or physical Action authorization | Consumer application authority | Cannot be delegated to an artifact merely because it is signed |

A concrete new implementation requirement must name the relevant row. No domain expansion or speculative plugin marketplace is authorized.

## Proposed interface separation

Preserve the standard interaction vocabulary: Property, Action, Event, Form and Thing Description. Do not replace these with a generic function catalogue that loses protocol meaning. W3C's Thing Description contract is external interoperability authority [E1].

For a portable codec experiment, freeze input representation, bounds, output schema, error vocabulary and implementation identity. The codec receives bytes and explicit metadata, not a socket, device credential, database handle or consumer process registry. Decoder output remains evidence; it does not create enrollment or permission.

For a native host experiment, freeze the command/result/stream protocol, exact executable and dependency digests, supported target, startup/shutdown behavior and durable session-state requirements. An argv list does not prove runtime closure. Loading a library must still start nothing; the consumer chooses when and where an admitted host runs.

Describe runtime kind, platform, tenancy/session scope and artifact format independently. A profile label must not simultaneously imply process isolation, trust, protocol coverage and commercial availability.

## Stateful protocols are the critical counterexample

The documentation describes Matter fabric authority and persistent controller sessions, BlueZ-managed BLE interactions, consumer-owned MQTT sessions and serialized Modbus transactions [S3]. Those are not interchangeable with a stateless parsing function.

An update of a stateful protocol host must preserve or explicitly invalidate its session/fabric state. Record subscription gaps and continuity loss. Do not replay commissioning or an uncertain transmitted write just because a process restarted. A successful acknowledgement is a protocol fact, not proof of canonical or physical state.

A codec can often switch at a message boundary. A device connection may need drain, disconnect, reauthentication, operator approval or unavailable status. The contract must state which; a universal hot-reload promise would be false.

## Security and trust

A publisher requests privileges; the consumer grants them. Effective access is scoped to exact devices/addresses/operations and bounded resources. Descriptions and runtime manifests cannot select arbitrary host files, ports, modules or credential stores.

Bound artifact length, dependency depth, decompression, compilation, messages, memory, runtime, handles, subscriptions and buffers. Refuse an unsupported runtime/security profile rather than falling back to same-VM evaluation. A process boundary is useful but is not an OS sandbox by itself [E2].

For pure components, deny ambient imports and use host-mediated effects only where the selected profile explicitly permits them [E3]. For privileged drivers, give the minimal device/service access and keep credentials/session stores with their named owner. A shared driver process requires a tested multi-consumer isolation contract; otherwise use separate instances.

Signature verification, standard conformance and actual device qualification remain different evidence. Offline consumers need local exact artifacts and trust material; no online registry or cloud service may become necessary for normal installed operation. Trusted update freshness needs an explicit disconnected policy, not disabled checks.

## Distribution and source layout

Keep independent builds and package contracts. Publish an optional executable profile using an established content-addressed manifest/layout, for example OCI, only when it benefits the chosen native or codec artifact [E4]. OCI does not require a container daemon and does not confer sandboxing.

Do not wrap every TD or small declarative mapping in an executable container. Do not add a second semantic hash for an already standardized document just to match an engine's packaging. Distinguish domain identity, executable identity and transport checksum.

A consumer may bundle its selected profile for firmware or import it separately where the host permits updates. That choice is deployment policy. Generic artifact support must not imply that a Nerves appliance accepts arbitrary post-release code.

## Symmetry and ownership

Other semantic systems can share envelope integrity, explicit context, bounded cancellation, conformance evidence and passive binding design. WoTEx still owns protocol semantics and must remain independently usable. Consumer products retain user/tenant, enrollment, automation, durable state and physical-effect authority.

There is no evidence here that all consumers require the same loader, language runtime or deployment topology. Shared implementation extraction should follow two real compatible consumer needs, not create them. Private consumer evidence belongs in its consumer repository; this public memo contains no private deployment dependency.

## Refactor and validation programme

P0: inventory the selected runtime, binding and native-host public entry points; identify where module configuration is build-time convenience versus a necessary semantic boundary. Keep library loading passive.

P1: compare a data-only mapping update with one pure-codec artifact update. If data suffices, choose data. Separately qualify one native host's reproducible closure and restart/session behavior; do not mix the two tests.

P2: offer a consumer-facing descriptor and conformance fixture only for qualified profiles. Preserve existing library APIs where still appropriate; greenfield freedom is permission to improve boundaries, not a reason to remove useful APIs.

| Gate | Owner | Required result |
|---|---|---|
| ENG-PASSIVE | Package owners | Loading code/artifact metadata starts no transport or device operation |
| ENG-CODEC | Codec owner | Native and portable results/refusals agree for identical bounded input; malformed data cannot trigger I/O |
| ENG-CLOSURE | Native-host owner | Clean offline installation reproduces exact executable/dependencies on the declared target |
| ACT-CREDENTIAL | Consumer transport contract | Credentials resolved per interaction; logs, results and artifacts contain no reusable secrets |
| ACT-SESSION | Protocol owner | Restart/update preserves declared continuity or reports loss; no hidden resubscription/write replay |
| ACT-EFFECT | Consumer + protocol owner | Lost response remains uncertain; acknowledgement never promoted into physical success |
| ACT-MULTI | Binding owner | Two independently configured instances do not share session state, authority or lifecycle |
| ACT-VALUE | Consumer integration owner | A named replacement actually avoids a host rebuild or dependency conflict without unacceptable measured cost |

Acceptance tests and resource budgets must be preregistered for actual target hardware. No numerical performance result, executed test pass or purchase is asserted. Failure of ACT-VALUE keeps that implementation a library or explicit bundled host; failure of a safety gate prevents admission regardless of convenience.

## Sources and limits

All repository observations refer to the source revision above:

- S1: [Repository contract](../../AGENTS.md).
- S2: [Root architecture and package roles](../../README.md).
- S3: [Interaction, protocol and lifecycle documentation](../README.md), especially Runtime, HTTP, MQTT, BLE, Matter and Modbus sections.
- Normative destinations identified by the index: [Runtime](../packages/wotex-runtime/specs/WRT.01-consumed-thing-runtime.md), [HTTP transport](../packages/wotex-binding-http/specs/WBH.01-http-transport.md), [MQTT transport](../packages/wotex-binding-mqtt/specs/WBM.03-runtime-transport.md), and [Matter native backend](../packages/wotex-matter/specs/WMA.08-native-backend.md). This memo does not change those contracts.
- E1: [W3C Thing Description 1.1](https://www.w3.org/TR/wot-thing-description11/).
- E2: [Erlang ports](https://www.erlang.org/doc/system/ports.html).
- E3: [Wasmtime security](https://docs.wasmtime.dev/security.html).
- E4: [OCI manifest v1.1.1](https://github.com/opencontainers/image-spec/blob/v1.1.1/manifest.md).

External references were consulted for the architecture programme on 2026-10-03. Source claims remain narrower than execution proof. Further consumer tracing, package code audits and physical interoperability are open gates, not completed work inferred from directory structure.
