# Portable delivery: source review and remaining gaps

Research revision `PD-R@1.1.0`, 2026-10-08. Reviewed source:
`c8c727a7c8c18fec82d80cc5ba88d246af3c67fc`. Research inputs:
`64ae7ec506ecf2e9a8ebfc80dbc4f074396aef42` and
`70d74e060a7d397381c50db14a5b07809c51c2ab`. This document records analysis
and proposed acceptance cases. It is not an executed interoperability report.

## Findings

The research agrees on optional independent delivery, consumer authority and
passive libraries. Its extension terminology hides three different problems:
replacing data, executing pure codecs and replacing stateful protocol hosts.
Those require different boundaries. Hex remains a useful distribution choice;
it neither creates nor prevents a semantic extension contract.

WoTEx is unreleased. Existing exported APIs are design material, not a deployed
compatibility constraint. WRT.04–06 now specify the exact target interfaces and
receipt formats; implementation evidence must prove those contracts. Protocol
version/identity checks remain necessary for correct execution and are distinct
from preserving unreleased library APIs.

The extension branch's older baseline is not sufficient for current design.
At the reviewed main revision, root native tooling already supports descriptor
admission, full build/payload identity, bounded retrieval/extraction and closure
checks. Existing native bindings already define strict IPC and startup custody.
The gap is connecting those proofs to consumer trust, current policy and safe
replacement without importing build tooling into runtime libraries.

## Gap and disposition matrix

| Gap / weakness | Reviewed source and implication | Target closure / evidence still required |
|---|---|---|
| Packaging treated as execution ABI | `README.md`, `tooling/packages.yaml`, `docs/architecture/package-graph.md`: 18 independent projects and explicit ports | Keep package graph; WRT.04 adds optional descriptor values, never mandatory manifests |
| BindingProfile confused with installation or grants | `packages/wotex-runtime/lib/wotex/runtime/binding_profile.ex`: operation/scheme/media declaration only | WRT.04 separates domain support cells, installed implementation and consumer grants; test a compatible but denied implementation |
| Artifact hash mistaken for publisher trust | `lib/wotex/workspace/native_artifact/verifier.ex`, `retrieval.ex`: checks exact expected identities, not a publisher-signature policy | WRT.04 requires consumer pin or verified-update receipt bound to descriptor and payload; spoofed publisher text grants nothing |
| Competing identity model | `docs/architecture/native-artifact-contract.md` 0.7.0 defines build and payload identity | Reuse identities; descriptor/configuration digests bind different objects; no new hash for TD domain identity |
| Verify/execute race | WBL.07, explicit native artifact selectors: immutable deployment is required; later path-based execution is not atomic | Reject mutable deployment for the first profile; attacker-model evidence for read-only deployment, including same-UID replacement; fd-based execution needs a separate target contract |
| Closure beyond argv | Native foundation requires exact target ELF dependency closure; a verified executable alone is insufficient | Admit guardian/SDK/loader closure together; missing dependency or wrong libc fails before spawn; no generic non-ELF success |
| Child process called a sandbox | Native owners use Ports and guardians; process separation does not restrict OS privileges | WRT.04 names enforcement profile and trusted execution; untrusted native code refused until a proven OS confinement profile exists |
| Cross-node deadline ambiguity | WRT.01 Context uses node-local monotonic time or UTC DateTime | WRT.05 translates a remaining budget at send, retains local deadline, rejects late success; no monotonic timestamp sent to another clock domain |
| Replacement presumed atomic | WMA.08 controller store/fabric authority; BlueZ connection and sender custody | WRT.05 prohibits candidate access to active exclusive resources and rollback after uncertain effects; fault cases at every transition |
| A restarted stream presented as continuous | Runtime Transport terminal session statuses; native report ledgers and credits | Generation-fence all reports, terminate old handles, report gap; no sequence reset presented as continuity |
| Cancellation confused with physical rollback | WRT.01 retry boundary and Modbus Connection transaction ownership | Retain `effect_unknown` for transmitted mutations; cancellation releases local resources and never establishes no device effect |
| Descriptor-selected modules/paths | Runtime transports and Credentials are supplied explicitly; root inventory is closed | WRT.04 resolves only consumer registration and admitted payload-relative paths; no string-to-atom conversion, PATH search or module discovery |
| Ambiguous optional/required fields | Research proposes future manifest fields without a precise evolution rule | WRT.04 closes v1 objects, isolates ignorable extensions and rejects unknown requirements before I/O |
| Resource budgets merely aspirational | Runtime bounds top-level values; BLE/Matter native frames have different depth limits | WRT.06 defines codec budgets and malformed/threshold cases; WRT.05 requires concrete per-binding queue/cleanup bounds |
| Shared host leaks authority | Existing owner/handle APIs do not establish arbitrary tenant isolation | Default one implementation instance per consumer scope; two-instance and shared-session negative tests; no multi-tenant claim |
| Offline signature freshness underspecified | Research asks for offline operation but supplies no clock/root/rollback policy | WRT.04 pin mode or verified-update mode; persist update high-water versions with consumer custody; expired metadata blocks new update admission |
| OCI mandatory without benefit | Carrier does not improve small data mappings or solve sandboxing | Keep local archive baseline; add OCI adapter only after two useful consumers and explicit media types/digests |
| WASM conflated with native control | Pure computation differs from hardware access, session state and commissioning | Codec semantic contract first; separately pin imports, runtime, interruption, allocation and floating-point policy before a WASM profile |
| Catalogue redesign unsupported | `lib/wotex/workspace/catalogue.ex` accepts `planned`, `partial`, `implemented`, `deprecated`, `withdrawn` | Keep enum; record new specifications `planned`; evidence and adoption remain separate fields rather than invented statuses |
| Evidence promoted from research | Both branches use architecture inspection, not implementation conformance | Planned vectors in WRT.04–06; exact commit/package/target/result receipts only after owning checks execute |

## Source trace and limitations

The review read Runtime ConsumedThing, Transport, Credentials and BindingProfile source;
BLE BlueZ facade and explicit selector contract; Matter native IPC and
controller credential/store obligations; Modbus Connection admission and
serialized exchange; root native Verifier/Retrieval and catalogue source;
the package graph and documentation index. File names above are locating
evidence at the exact baseline, not claims that text search proves behavior.
The [decision](../architecture/portable-delivery-decision.md) allocates all
18 package roles; focused behavioural tracing is still required when a package
profile changes.

Public caller and impact tracing remains an implementation prerequisite;
source review is not a substitute for that trace or executed binding tests.
Matter ownership is under `Wotex.Matter.Native`; a generic controller module
must not be invented from the role name. This research establishes no
application, SDK, hardware, benchmark, containment or independent consumer
result.

## Primary-source research register

Consulted 2026-10-08. Sources support the narrow facts below; target requirements
and numerical budgets are WoTEx engineering decisions, not standards mandates.

| Source / exact baseline | Relevant fact | Consequence |
|---|---|---|
| [TD 1.1, Recommendation 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/) | Forms describe interaction access; security schemes describe interaction security | Keep Property/Action/Event semantics and consumer policy; no standard extension-loader claim |
| [Erlang Ports, OTP 29.1.1 documentation](https://www.erlang.org/doc/system/ports.html) | External byte interface has a connected owner; linked-in drivers can affect the VM | Separate native process custody and same-VM trust; validate supported project lanes independently |
| [BlueZ 5.83 GATT characteristic API](https://raw.githubusercontent.com/bluez/bluez/5.83/doc/org.bluez.GattCharacteristic.rst) | Notifications are shared between sessions; StopNotify releases one session; acquired descriptors close on reconnect | A sender-specific session and reconnect must be explicitly owned; no generic gap-free upgrade |
| [OCI image manifest 1.1.1](https://github.com/opencontainers/image-spec/blob/v1.1.1/manifest.md) | Artifact type, descriptor digests and subject associations describe content | Treat OCI as a carrier; require separate trust and native identity verification |
| [TUF specification 1.0.33](https://theupdateframework.github.io/specification/v1.0.33/) | Role thresholds, persisted versions, hashes and expiry defend update selection | Consumer verifies update receipts; no expiry bypass for disconnected installs and no TUF conformance claim |
| [Wasmtime security documentation](https://docs.wasmtime.dev/security.html), unversioned, accessed 2026-10-08 | Guest isolation and imported/WASI authority need host configuration | Research-only until runtime release, ABI and imports are pinned and tested; unversioned page is not a release baseline |
| [RFC 8785, June 2020](https://www.rfc-editor.org/rfc/rfc8785) | JCS defines deterministic JSON serialization within its admitted value model | Native identity remains authoritative; descriptor JSON excludes floats and large JSON integers |
| [RFC 8259, December 2017](https://www.rfc-editor.org/rfc/rfc8259.html) and [RFC 4648, October 2006](https://www.rfc-editor.org/rfc/rfc4648.html) | JSON syntax and Base64 encoding rules | WoTEx adds explicit duplicate-key rejection, allocation bounds and one canonical byte encoding |
| [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) | Distinct version core, prerelease and build metadata grammar | Descriptor syntax pins 2.0.0; exact minor compatibility and update trust remain WoTEx decisions |

Open empirical questions are consumer usefulness, target latency/memory,
reproducible closure, independent codec implementation agreement and physical
session recovery. The [delivery plan](../architecture/portable-delivery-plan.md)
states the experiment and stop condition for each. Unknown results remain
unknown; they are not reasons to omit refusal or ownership requirements.
