# Matter primary sources

The selected SDK is connectedhomeip v1.6.0.0 commit
`250a9e6c50ee2068107f3c4808b680f5f2925415`.
[WMA.13](../specs/WMA.13-native-backend.md) pins the source archive, transitive
source/build manifest and first-party C++ host. The full Matter 1.6 Core text is
not available for clause-level review here. The contract is an SDK-derived
controller profile; neither source review nor shared-SDK peers establish CSA
certification or complete standard coverage.

- [Controller factory](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/CHIPDeviceControllerFactory.h)
  initializes the owned SDK system state and controller.
- [Device commissioner](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/CHIPDeviceController.h)
  owns filtered discovery, pairing and final commissioning callbacks.
- [ReadClient](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/ReadClient.h)
  defines read/report/establishment/deallocation callback lifetime; Close is private and report callbacks cannot destroy their client.
- [WriteClient](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/WriteClient.h)
  defines pre-encoded typed writes, path status and OnDone lifetime.
- [CommandSender](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/CommandSender.h)
  defines explicit timed invocation, path-specific response and terminal completion.
- [Commissioning window](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/CommissioningWindowOpener.h)
  defines generated onboarding data and final asynchronous completion.
- [Storage delegate](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/lib/core/CHIPPersistentStorageDelegate.h)
  defines synchronous keyed opaque-byte persistence.
- [Operational keystore](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/crypto/PersistentStorageOperationalKeystore.h)
  owns persisted operational key state.
- [Operational certificate store](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/credentials/PersistentStorageOpCertStore.h)
  owns persisted operational certificate state.
- [Controller build](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/BUILD.gn)
  declares the native controller library.
- [Generated controller data model](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/data_model/BUILD.gn)
  declares typed schema generation from the pinned controller model.

The SDK gitlink selects [BoringSSL 9cac8a6](https://github.com/google/boringssl/tree/9cac8a6b38c1cbd45c77aee108411d588da006fe);
.13 fixes `chip_crypto="boringssl"` and the verified archive hash. Native dependency
audit remains a required build gate.

P02's SDK-header compile also resolves the pinned gitlinks for
`nestlabs/nlassert` at `c5892c5ae43830f939ed660ff8ac5f1b91d336d3`
(archive SHA-256 `392f0a7f1c35cc3520d5f71faf37bfe4518e00ba0dc704068f4fbf6eba5427a5`)
and `nestlabs/nlio` at `0e725502c2b17bb0a0c22ddd4bcaee9090c8fb5c`
(archive SHA-256 `f7ffbc6fd3e9029c6aa558aec8f80819d1e9a8daba67633d512de23560147f34`).
The P02 runner also verifies nlohmann/json 3.11.3 at WMA.13's fixed
`9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6`
header hash. These are compile/parser inputs, not controller or crypto evidence.

The finite registry and exact thermostat/light/bridge/temperature recipes are in
[WMA.11](../specs/WMA.11-standalone-client-and-preservation.md), with pinned XML
sources. Native SDK generation/bootstrap may use upstream Python at build time;
no Python wheel, runtime factory or dynamic class import completes the controller.
The current one-shot Python adapter is documented solely by
[WMA.03](../specs/WMA.03-sdk-client.md). Its API-contract tests are not native
commissioning/CASE/subscription evidence.

W3C [TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
owns Thing Description semantics. A package-defined protocol Form profile is
not W3C certification. Source review supports API choices; execution evidence
belongs to [executable-evidence.md](executable-evidence.md). Native .13 specifies
library policy for limits, credits, error classes and ownership, not extra
protocol-standard guarantees.
