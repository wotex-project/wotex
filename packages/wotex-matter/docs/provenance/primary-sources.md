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
