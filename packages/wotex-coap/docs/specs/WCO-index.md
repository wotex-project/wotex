# WCO specification index

Start with the [software implementation sequence](../plans/software-implementation.md).
The implemented profile contains BEAM UDP/Observe/discovery, Runtime UDP
streams and OTP DTLS. Secure Runtime profiles, OSCORE and complete Mix software
closure remain partial. Native/software build tasks, the current independent
UDP/DTLS software-run cohort and its same-stack OSCORE cohort execute; OSCORE
independence and the complete fault,
stress, sanitizer and toolchain matrix remain planned. The catalogue and
provenance distinguish these scopes.

- [WCO.00 Software implementation rules](WCO.00-library-contract.md)
- [WCO.01 CoAP protocol contract](WCO.01-protocol.md)
- [WCO.02 Implemented CoAP profile](WCO.02-implemented-profile.md)
- [WCO.03 Whole-body transfers](WCO.03-blockwise.md)
- [WCO.10 Complete CoAP client software profile](WCO.10-software-contract.md)

- [WCO.11 Standalone client and feature preservation](WCO.11-standalone-client-and-preservation.md)

[Source revisions](../provenance/primary-sources.md) and [executed evidence](../provenance/executable-evidence.md) are separate records.

- [Versioned specification catalogue](catalogue.yaml) — owning contracts, dependencies, status and scoped execution evidence
- [WCO.12 Wotex integration and evidence contract](WCO.12-wotex-integration.md)
- [Concrete Wotex integration corpus](fixtures/wotex-integration-v1.json) — specified assertions, not a passed profile

- [WCO.13 Native build and software evidence](WCO.13-native-build-and-software-evidence.md) — explicit Mix tasks, native peer ownership and acceptance
