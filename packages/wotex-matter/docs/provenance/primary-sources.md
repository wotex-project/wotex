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
