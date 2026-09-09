# WMA specification index

Start with the [software implementation sequence](../plans/software-implementation.md).
The .00/.10/.11/.12/.13 contracts describe required target behavior; the existing protocol
and implemented-profile documents distinguish current tested behavior from it.
Implementation readiness does not mean implementation or conformance is complete.

- [WMA.00 Software implementation rules](WMA.00-library-contract.md)
- [WMA.01 Matter protocol and graduation contract](WMA.01-protocol.md)
- [WMA.02 Implemented Matter profile](WMA.02-implemented-profile.md)
- [WMA.03 Explicit SDK client](WMA.03-sdk-client.md)
- [WMA.10 Complete SDK-backed Matter controller software profile](WMA.10-software-contract.md)

- [WMA.11 Standalone client and protocol workflows](WMA.11-standalone-client-and-preservation.md)
- [Concrete contract cases, specified and unexecuted](fixtures/contract-v1.json)

[Source revisions](../provenance/primary-sources.md) and [executed evidence](../provenance/executable-evidence.md) are separate records.

- [Versioned specification catalogue](catalogue.yaml) — owning contracts, dependencies, status and baseline evidence
- [WMA.12 Wotex integration and evidence contract](WMA.12-wotex-integration.md)
- [Concrete Wotex integration corpus](fixtures/wotex-integration-v1.json) — specified assertions, not a passed profile

- [WMA.13 Native backend, build and IPC contract](WMA.13-native-backend.md)
- [Concrete native Port corpus](fixtures/native-port-v1.json) — specified, unexecuted acceptance cases
