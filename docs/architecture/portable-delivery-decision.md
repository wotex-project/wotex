# Optional implementation delivery

Decision `PD-ADR@1.1.0`, 2026-10-08. Accepted design direction; implementation
status is recorded by the package catalogue. Source review baseline:
`c8c727a7c8c18fec82d80cc5ba88d246af3c67fc`. This decision reconciles
[extension research](../research/runtime-extension-architecture.md) at
`64ae7ec506ecf2e9a8ebfc80dbc4f074396aef42` and
[portable delivery research](portable-capability-delivery-research.md) at
`70d74e060a7d397381c50db14a5b07809c51c2ab`. Those research documents remain
historical proposals; this decision and the package contracts define the target.

## Decision and scope

Keep the 18 independent Mix projects, Hex dependency requirements and explicit
consumer registration. A normal library consumer needs no extension manifest,
loader or registry. A selected implementation may additionally be delivered as
an exact local data or executable artifact when it solves a demonstrated
replacement or dependency problem. This decision authorizes specification of
that optional boundary, not a marketplace, online installer or mandatory
extension manager.

Runtime owns common immutable admission and lifecycle values. A binding owns
its domain mapping, IPC and process custody. Root tooling owns native build
identity, verification and dependency closure. Consumers own installed trust
material, policy, supervision, devices, session stores and route changes.
Nothing adds a package dependency on the root tooling or Lab. Shared code is
extracted only after two independently useful integrations establish the seam.

The target contracts are [WRT.04 admission](../packages/wotex-runtime/specs/WRT.04-implementation-admission.md),
[WRT.05 lifecycle](../packages/wotex-runtime/specs/WRT.05-implementation-lifecycle.md)
and [WRT.06 codec](../packages/wotex-runtime/specs/WRT.06-bounded-codec.md).
The package catalogue separates implemented values from remaining binding and
target qualification. Existing WRT.01–03, native artifact foundation 0.7.0 and
protocol specifications retain their ownership.
WoTEx is unreleased. Current API names, layouts and defaults are not a released
compatibility obligation; change them when the target design requires it,
revising owning specifications/catalogues and affected callers together. Keep
package ownership and consumer authority because they serve the design, not
because of a presumed installed user base. WRT.04–06 at 1.1.0 define exact
target APIs and record formats now; tests prove the target rather than choose it.
Implementation must revise a protocol's own contract before adding a profile
or changing its process protocol. See the [delivery plan](portable-delivery-plan.md)
for dependency order and the [gap analysis](../research/portable-delivery-gap-analysis.md)
for source evidence and unresolved qualification.

## Options considered

| Option | Decision | Reason and reversal criterion |
|---|---|---|
| Explicit trusted BEAM libraries | Retain as default | Existing public ports already support consumer-selected adapters; deployment rebuilds are often acceptable |
| Consolidation or umbrella | Reject in this programme | Contradicts the independent-project contract; research supplies no measured consumer or CI benefit requiring a change |
| Data-only replacement | Prefer when sufficient | Device mapping updates need no executable privileges; measure this before a codec host |
| Target-specific OS process | Select for the bounded native proof | Fits existing native ownership; preserves crash separation and protocol-specific custody; does not imply sandboxing |
| New universal protocol IPC | Defer | BLE and Matter already have different framing depths, operations and state; forced uniformity would change useful domain contracts |
| Dynamic BEAM installation | Exclude | Same-VM trust, dependency and code-version interactions add risk without a demonstrated requirement |
| WebAssembly | Separate experiment | Pure codecs may benefit; controller state, privileged I/O and SDK closures remain separate; no `wasm-v1` claim exists |
| OCI distribution | Optional later carrier | Content-addressed delivery can carry exact artifacts; it does not supply authorization, signatures or a process sandbox |

## Package inventory and allocation

This is an allocation of work, not a new support matrix. The package graph
comes from `tooling/packages.yaml`; roles come from the root README and owning
specifications at the baseline. No complete package audit or execution pass is
implied by this table.

| Package | Retained responsibility | Optional delivery work |
|---|---|---|
| `wotex` | Thing Description, Thing Model, DataSchema and Form values | Declarative data remains passive; no loader in TD parsing |
| `wotex-runtime` | Interaction planning and consumer ports | WRT.04–06 values and optional codec seam; no native supervisor or installer |
| `wotex-directory` | Directory repository and authorization ports | No extension authority or trust registry |
| `wotex-nx` | Observation and numerical boundaries | No executable installation or Action authority |
| `wotex-continuum` | Versioned exchange values | Existing wire identities remain independent |
| `wotex-conformance` | Revision-pinned external target evidence | Runner may evaluate a separately specified profile; no loader dependency |
| `wotex-binding-http` | HTTP consumer port and SSE | Trusted BEAM delivery counterexample |
| `wotex-binding-mqtt` | MQTT mapping and consumer-owned sessions | Session replacement requires its own profile and continuity evidence |
| `wotex-bacnet` | BACnet protocol and finite supported profile | Native artifact adoption stays package-owned |
| `wotex-ble` | BlueZ GATT and sender/notification custody | First native-host proof; immutable executable cohort, explicit interruption |
| `wotex-coap` | CoAP exchange, Observe and protection owners | Protection state and Observe recovery cannot be treated as codec state |
| `wotex-matter` | Controller/fabric authority and exposed bridge | Exclusive store and uncertain commissioning effects are replacement counterexamples |
| `wotex-modbus` | Serialized TCP exchange and value mapping | Candidate byte codec and data-only comparison; no automatic write replay |
| `wotex-opcua` | Secure Session, services and subscription owners | Session continuity remains a separate qualification cell |
| `wotex-thread` | OpenThread host, Dataset and state ownership | Dataset secrets and management authority remain consumer-owned |
| `wotex-udp` | Bounded datagram infrastructure | A datagram implementation is not a WoT binding |
| `wotex-zigbee` | Partial ZNP/ZCL profile | No portable coordinator claim from a codec experiment |
| `wotex-lab` | Independent reference consumers and evidence display | Optional proof consumer; no runtime authority for other packages |

## Security and standards rationale

TD 1.1 defines interaction descriptions, not executable installation. The
extension descriptor is a WoTEx value outside the TD vocabulary; a TD cannot
choose a host module, executable or credential store. The exact
[TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
remains the standards baseline.

Erlang Ports provide a byte interface and an owner relationship to an external
program. They do not establish descendant cleanup or privilege confinement;
those require binding and deployment evidence. The consulted
[OTP 29.1.1 Ports documentation](https://www.erlang.org/doc/system/ports.html)
is architectural guidance, not an expansion of WoTEx's supported OTP lanes.

The [OCI image manifest 1.1.1](https://github.com/opencontainers/image-spec/blob/v1.1.1/manifest.md)
supports artifact media types and digest-linked objects. A `subject` association
does not establish publisher authorization. WoTEx retains its native build and
payload identities inside any carrier.

Signed update freshness is separate from exact payload integrity. The
[TUF specification 1.0.33](https://theupdateframework.github.io/specification/v1.0.33/)
requires trusted metadata versions and expiry checks. WoTEx specifies two
admission modes: an independently approved local pin, or a consumer-verified
update receipt. Offline operation never silently turns an expired update into
a valid receipt. This is a consumer integration boundary, not a claim that
WoTEx implements TUF.

[Wasmtime security documentation](https://docs.wasmtime.dev/security.html),
consulted 2026-10-08, describes memory isolation and capability-oriented WASI
filesystem access. These make a codec experiment plausible; they do not prove
host-import safety or deterministic execution for a WoTEx profile. A future
binding must pin its runtime and ABI revisions and pass the same codec vectors.

## Consequences and nonclaims

Independent delivery may avoid a host rebuild for one selected implementation.
It does not guarantee hot replacement of a device connection, cross-platform
execution, stronger trust, faster execution or a smaller dependency closure.
The first stateful replacement is deliberately stop/reopen with reported loss;
parallel candidates must not touch an exclusive store or physical device.

No package consolidation, source dependency switch, version release, hosted
artifact or automatic network access follows from this decision. Performance,
independent interoperability, sandboxing and hardware results remain open
qualification requirements. A failed usefulness gate keeps the implementation
an ordinary library or explicitly bundled host.
