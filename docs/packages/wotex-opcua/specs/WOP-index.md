# WOP specification index

Start with the [software implementation sequence](../plans/software-implementation.md).
The .00/.10/.11/.12/.13 contracts describe required target behavior; the existing protocol
and implemented-profile documents distinguish current tested behavior from it.
Implementation readiness does not mean implementation or conformance is complete.

- [WOP.00 Software implementation rules](WOP.00-library-contract.md)
- [WOP.01 OPC UA protocol and graduation contract](WOP.01-protocol.md)
- [WOP.02 Implemented OPC UA profile](WOP.02-implemented-profile.md)
- [WOP.10 Complete secure OPC UA client software profile](WOP.10-software-contract.md)

[Source revisions](../provenance/primary-sources.md) and [executed evidence](../provenance/executable-evidence.md) are separate records.

- [WOP.11 Standalone client and preservation](WOP.11-standalone-client-and-preservation.md)
- [Concrete fixture corpus](../../../../packages/wotex-opcua/priv/fixtures/contract-v1.json) — thirteen pure value/identity/reference cases are bound; remaining cases are specified and unexecuted

- [Versioned specification catalogue](catalogue.yaml) — owning contracts, dependencies, status and baseline evidence
- [WOP.12 Wotex integration and evidence contract](WOP.12-wotex-integration.md)
- [Concrete Wotex integration corpus](../../../../packages/wotex-opcua/priv/fixtures/wotex-integration-v1.json) — specified assertions, not a passed profile

- [WOP.13 Native executable and software acceptance](WOP.13-native-executable.md)
- [Pinned native sources](../../../../packages/wotex-opcua/priv/fixtures/native-sources-v1.json) — archive identities, not build evidence
- [Native acceptance corpus](../../../../packages/wotex-opcua/priv/fixtures/native-contract-v1.json) — WOP-X-F01 through WOP-X-F16 are bound by WOP-P01; the partial P02 input tests do not bind later cases
