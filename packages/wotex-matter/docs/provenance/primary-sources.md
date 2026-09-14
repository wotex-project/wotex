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
- [Production attestation verifier](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/credentials/attestation_verifier/DefaultDeviceAttestationVerifier.h)
  binds commissioning to the configured PAA trust store and attestation result.
- [ReadClient](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/ReadClient.h)
  defines read/report/establishment/deallocation callback lifetime; Close is private and report callbacks cannot destroy their client.
- [WriteClient](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/WriteClient.h)
  defines pre-encoded typed writes, path status and OnDone lifetime.
- [CommandSender](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/app/CommandSender.h)
  defines explicit timed invocation, path-specific response and terminal completion.
- [Commissioning window](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/CommissioningWindowOpener.h)
  defines generated onboarding data and final asynchronous completion.
- [Manual setup payload generator](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/setup_payload/ManualSetupPayloadGenerator.h)
  and [QR setup payload generator](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/setup_payload/QRCodeSetupPayloadGenerator.h)
  serialize SDK-generated enhanced-window onboarding material.
- [Controller cluster selection](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/data_model/controller-clusters.zap)
  includes AccessControl and AdministratorCommissioning in the generated client
  data model.
- [Access control guide](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/docs/guides/access-control-guide.md)
  describes the fabric-scoped ACL attribute, CASE and Group auth modes, and
  peer-enforced denial.
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

The P03 build resolves these connectedhomeip gitlinks from verified source
archives:

- [Pigweed `c9687b52`](https://github.com/google/pigweed/tree/c9687b52fa704606d19952255c78142fdb2a131a),
  archive SHA-256 `2e8d3380080d2ae9cc56f69d05d6f008989b092d6c9f71dc0c0fa25d4a2c3651`;
- [BoringSSL `9cac8a6`](https://github.com/google/boringssl/tree/9cac8a6b38c1cbd45c77aee108411d588da006fe),
  archive SHA-256 `4d0310f2d8dc2bb19598ecc46907d44a93cc3bfbde97943c0e9e34ef4f0698b8`;
- [uriparser `04d8b8d`](https://github.com/uriparser/uriparser/tree/04d8b8df5e0c6bf6c06e472540c015943a613bd2),
  archive SHA-256 `1577e0267263625dbfb53ca18a1530142b89e2762593a7c6cbcec2d730f83007`.

WMA.13 fixes `chip_crypto="boringssl"`. Native dependency audit remains a
required separate gate.

P02's SDK-header compile also resolves the pinned gitlinks for
`nestlabs/nlassert` at `c5892c5ae43830f939ed660ff8ac5f1b91d336d3`
(archive SHA-256 `392f0a7f1c35cc3520d5f71faf37bfe4518e00ba0dc704068f4fbf6eba5427a5`)
and `nestlabs/nlio` at `0e725502c2b17bb0a0c22ddd4bcaee9090c8fb5c`
(archive SHA-256 `f7ffbc6fd3e9029c6aa558aec8f80819d1e9a8daba67633d512de23560147f34`).
The P02 and P03 runners also verify nlohmann/json 3.11.3 at WMA.13's fixed
`9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6`
header hash.

P03 selects the Chromium Infrastructure Package Deployment client at git
revision `f78815586bf74e9878223463db7cf315c16853d1`, instance
`wzIb8E5mCOKbiJf7unggzWIKqjtBb0z_Fo1m4r0AEk8C`, SHA-256
`6bf4733d673bfa644d7c1862b62bdc941e1c8f5b6ea886c61c37433f4a53dbb2`.
That client installs GN instance
`NE_8G-C-1QSR3Fzth11KzRynkGGK71LSQjiCBQaD6hoC`, executable SHA-256
`3dcfa89818814fed6e252a82ef6fc4027184010d05619d224ca4dfc17e8ae85c`,
and ZAP `v2026.05.12-nightly.2` instance
`YSTXcN2b2sI35obRtz_f4SiOmbkL8_JFLCk-0fJQwKYC`, whose `zap-cli` SHA-256 is
`ad4b3bc455eb315c2f9149e8be423255b0acdd4b9cf4acb3beb37c09f126cc9d`.

The SDK generator runs from the verified archive with these build-only Python
artifacts. They are absent from the runtime binary and Hex package.

| Package | Version | Artifact SHA-256 |
| --- | --- | --- |
| [click](https://pypi.org/project/click/8.3.3/) | 8.3.3 | `a2bf429bb3033c89fa4936ffb35d5cb471e3719e1f3c8a7c3fff0b8314305613` |
| [coloredlogs](https://pypi.org/project/coloredlogs/15.0.1/) | 15.0.1 | `612ee75c546f53e92e70049c9dbfcc18c935a2b9a53b66085ce9ef6a6e5c0934` |
| [humanfriendly](https://pypi.org/project/humanfriendly/10.0/) | 10.0 | `1697e1a8a8f550fd43c2865cd84542fc175a61dcb779b6fee18cf6b6ccba1477` |
| [lark](https://pypi.org/project/lark/1.1.5/) | 1.1.5 | `8476f9903e93fbde4f6c327f74d79e9b4bd0ed9294c5dfa3164ab8c581b5de2a` |
| [Jinja2](https://pypi.org/project/Jinja2/3.1.6/) | 3.1.6 | `85ece4451f492d0c13c5dd7c13a64681a86afae63a5f347908daf103ce6d2f67` |
| [MarkupSafe](https://pypi.org/project/MarkupSafe/2.1.2/) | 2.1.2 | `f2bfb563d0211ce16b63c7cb9395d2c682a23187f54c3d79bfec33e6705473c6` |
| [lxml](https://pypi.org/project/lxml/6.1.0/) | 6.1.0 | `d036ee7b99d5148072ac7c9b847193decdfeac633db350363f7bce4fff108f0e` |
| [python-path](https://pypi.org/project/python-path/0.1.3/) | 0.1.3 | `b62d9aac1da4daee3f036ed088532cf8b68666d3aa103567dc22b6539316c8b3` |

The finite registry and exact thermostat/light/bridge/temperature recipes are in
[WMA.11](../specs/WMA.11-standalone-client-and-preservation.md), with pinned XML
sources. Native SDK generation uses the exact build-only artifacts listed above;
no Python component is shipped or executes in the production controller.
The current one-shot Python adapter is documented solely by
[WMA.03](../specs/WMA.03-sdk-client.md). Its API-contract tests are not native
commissioning/CASE/subscription evidence.

W3C [TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
owns Thing Description semantics. A package-defined protocol Form profile is
not W3C certification. Source review supports API choices; execution evidence
belongs to [executable-evidence.md](executable-evidence.md). Native .13 specifies
library policy for limits, credits, error classes and ownership, not extra
protocol-standard guarantees.
