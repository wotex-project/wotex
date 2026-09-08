# Matter primary evidence

Research date: 2026-09-08. Audience: maintainers. The protocol contract above
distinguishes normative standards, upstream implementation behavior, inferred
integration choices and evidence still requiring hardware or SDK execution.

- [CSA Matter 1.6 announcement](https://csa-iot.org/newsroom/matter-1-6-enables-more-intuitive-setup-multi-ecosystem-experiences-and-context-driven-control/).
- [connectedhomeip v1.6.0.0](https://github.com/project-chip/connectedhomeip/releases/tag/v1.6.0.0).
- [SDK path identifier types](https://github.com/project-chip/connectedhomeip/blob/v1.6.0.0/src/lib/core/DataModelTypes.h).
- [SDK TLV definitions](https://github.com/project-chip/connectedhomeip/blob/v1.6.0.0/src/lib/core/TLVTypes.h).
- [SDK TLV reader validation](https://github.com/project-chip/connectedhomeip/blob/v1.6.0.0/src/lib/core/TLVReader.cpp).
- [CHIP Tool guide](https://project-chip.github.io/connectedhomeip-doc/development_controllers/chip-tool/chip_tool_guide.html).
- [SDK access control guide](https://project-chip.github.io/connectedhomeip-doc/guides/access-control-guide.html).
- [CSA certification process](https://csa-iot.org/certification/why-certify/).

Research searched standards/revision availability, wire/address rules, transport
ownership, security and interoperability gaps, then reviewed upstream APIs.
Stop reason: consequential design claims have primary evidence or explicit
access limits. No physical or secure-stack execution was performed by research.

W3C [TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/)
is the Thing Description baseline. [Binding Registry 2025-11-04 draft](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/)
does not turn a package-defined profile into a W3C Recommendation.

The SDK adapter was checked against the exact pinned
[controller API](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/ChipDeviceCtrl.py),
[cluster descriptor registries](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/clusters/ClusterObjects.py)
and [attribute status/path definitions](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/clusters/Attribute.py).
ReadAttribute returns an endpoint/cluster/attribute-keyed cache; WriteAttribute
returns one status per path. The adapter validates both identities and statuses.
Read options keep existing subscriptions and disable automatic resubscription.
The native SDK and a commissioned device were not available for execution;
API-contract tests do not replace that interoperability gate.

## Software-contract review, 2026-09-08

All source links below pin SDK commit
`250a9e6c50ee2068107f3c4808b680f5f2925415`, v1.6.0.0:

- [ChipStack](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/ChipStack.py)
  takes a PersistentStorage object, not a pathname.
- [Storage](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/storage/__init__.py)
  defines PersistentStorage and PersistentStorageJSON. The sample JSON backend
  can log a load/save exception and continue; .10 requires an explicit durable
  first-party implementation that fails closed and never recreates missing identity.
- [CertificateAuthority](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/CertificateAuthority.py)
  and [FabricAdmin](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/FabricAdmin.py)
  define explicit authority/fabric/controller creation and shutdown.
- [ChipDeviceCtrl](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/ChipDeviceCtrl.py)
  defines typed interactions, CommissionOnNetwork and OpenCommissioningWindow.
- [Attribute subscriptions](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/src/controller/python/matter/clusters/Attribute.py)
  expose update/recovery callbacks and Shutdown. Bounded retry/continuity policy
  in .10 is library policy rather than an SDK guarantee of gap-free event history.
- [Python build script](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/scripts/build_python.sh)
  and [host target definitions](https://github.com/project-chip/connectedhomeip/blob/250a9e6c50ee2068107f3c4808b680f5f2925415/scripts/build/build/targets.py)
  define the explicit Linux no-BLE software fixture builds.

These inspected implementation APIs make the adapter buildable without invented
normative clause citations. Full Matter 1.6 normative-text access remains absent;
SDK-derived software behavior and CSA certification are different claims.

## Standalone contract review, 2026-09-09

[WMA.11](../specs/WMA.11-standalone-client-and-preservation.md) records
additional source-pinned API and retained-workflow decisions. Its concrete
fixtures are specified, unexecuted acceptance data. This review does not add
an interoperability or standards-conformance result.
