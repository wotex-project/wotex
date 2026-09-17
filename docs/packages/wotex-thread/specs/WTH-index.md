# WTH specification index

Start with the [software implementation sequence](../plans/software-implementation.md).
The .00/.10/.11/.12/.13 contracts describe required target behavior; the existing protocol
and implemented-profile documents distinguish current tested behavior from it.
Implementation readiness does not mean implementation or conformance is complete.

- [WTH.00 Software implementation rules](WTH.00-library-contract.md)
- [WTH.01 Thread protocol and graduation contract](WTH.01-protocol.md)
- [WTH.02 Implemented Thread profile](WTH.02-implemented-profile.md)
- [WTH.10 Complete OpenThread host-management software profile](WTH.10-software-contract.md)

- [WTH.11 Standalone client and protocol workflows](WTH.11-standalone-client-and-preservation.md)
- [Concrete contract cases, specified and unexecuted](../../../../packages/wotex-thread/priv/fixtures/contract-v1.json)

[Source revisions](../provenance/primary-sources.md) and [executed evidence](../provenance/executable-evidence.md) are separate records.

- [Versioned specification catalogue](catalogue.yaml) — owning contracts, dependencies, status and baseline evidence
- [WTH.12 Wotex integration and evidence contract](WTH.12-wotex-integration.md)
- [Concrete Wotex integration corpus](../../../../packages/wotex-thread/priv/fixtures/wotex-integration-v1.json) — specified assertions, not a passed profile

- [WTH.13 Native backend, build and IPC contract](WTH.13-native-backend.md)
- [Concrete native Port corpus](../../../../packages/wotex-thread/priv/fixtures/native-port-v1.json) — specified, unexecuted acceptance cases
