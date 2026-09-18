# WBL specification index

Start with the [software implementation sequence](../plans/software-implementation.md).
The .00/.10/.11/.12/.13 contracts describe required target behavior; the existing protocol
and implemented-profile documents distinguish current tested behavior from it.
Implementation readiness does not mean implementation or conformance is complete.

- [WBL.00 Software implementation rules](WBL.00-library-contract.md)
- [WBL.01 BLE protocol and graduation contract](WBL.01-protocol.md)
- [WBL.02 Implemented BLE profile](WBL.02-implemented-profile.md)
- [WBL.10 Complete BlueZ GATT central software profile](WBL.10-software-contract.md)

- [WBL.11 Standalone client and protocol workflows](WBL.11-standalone-client-and-preservation.md)
- [Concrete contract cases](../../../../packages/wotex-ble/priv/fixtures/contract-v1.json) — specified cases; only cases bound to executed tests are evidence

[Source revisions](../provenance/primary-sources.md) and [executed evidence](../provenance/executable-evidence.md) are separate records.

- [Versioned specification catalogue](catalogue.yaml) — owning contracts, dependencies, status and baseline evidence
- [WBL.12 Wotex integration and evidence contract](WBL.12-wotex-integration.md)
- [Concrete Wotex integration corpus](../../../../packages/wotex-ble/priv/fixtures/wotex-integration-v1.json) — specified assertions, not a passed profile

- [WBL.13 Native backend, build and IPC contract](WBL.13-native-backend.md)
- [Concrete native Port corpus](../../../../packages/wotex-ble/priv/fixtures/native-port-v1.json) — specified acceptance cases; the catalogue identifies the executed ones
