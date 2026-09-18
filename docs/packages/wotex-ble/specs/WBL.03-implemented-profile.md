---
spec:
  id: WBL.03
  title: "Implemented BLE profile"
  status: accepted
  version: 1.1.1
  owner: wotex-ble
  updated: 2026-09-17
---

# WBL.03 Implemented BLE profile

This is a local Wotex Form profile, not a standardized W3C BLE binding:
`ble://device-key/service-uuid/characteristic-uuid`. Property read/write map to
GATT ReadValue/WriteValue. `device-key` is a consumer routing identity. Runtime
requires an identical `target` and the corresponding BlueZ adapter configuration.
No automatic Bluetooth address resolution or pairing is inferred from the URI.

UUID normalization accepts 16/32-bit integer or text identities and 128-bit UUIDs;
ATT encoding expands to 16 bytes in little-endian order. Decode accepts only two
or sixteen octets. Address optionally validates ATT handle 1..65535. Read results
and write inputs are raw bytes, at most 512; characteristic-specific units,
signedness/scaling and DataSchema validation remain explicit consumer choices.

The BlueZ adapter checks normalized service and characteristic identity against
its configured object path association, invokes `busctl` with separate arguments,
requests acknowledged writes, and validates exact `ay` response length/octets.
Output is capped at 4096 bytes and calls have finite deadlines. The OS owns the
connection and ATT transaction state. The package does not stop BlueZ, disconnect
borrowed devices, or acquire notification/discovery ownership in one-shot mode.
Adapter options are allowlisted and unique. Unknown or duplicate keys and
unsupported security selectors fail before `busctl` is started; the adapter never
interprets a caller's requested security level as proof of BlueZ link security.

## Persistent implementation

The persistent backend is the first-party C++ host from WBL.07, selected
explicitly with `lifecycle: :persistent` and the complete verified host and
runtime guardian path/SHA-256 cohort. No interpreter backend remains. It owns a private D-Bus sender, bounded discovery generation, explicit Agent
pairing, acknowledged procedures, health and notification/indication streams.
Typed Peer/Characteristic/Value APIs and Property/Event Runtime relays are
implemented. `connection: :borrowed` preserves ordinary borrowed links; pending
Pair sender loss can separately cause BlueZ to disconnect the peer. Explicit
pairing never authorizes removing bonds or registering a default Agent.

The Mix-built host passes the 11 public BLE and Runtime tests and the 5 WBL-C09
lifecycle stress tests against real BlueZ and virtual controllers in both BEAM
lanes ([software run receipt](../provenance/software-run-v3.json)). The x86_64
guest lane and final package gates are not established by those results. The native backend preserves the domain API and
adds its exact backend identity and bounded credit protocol.

## Evidence and compatibility

See [executable evidence](../provenance/executable-evidence.md) for specific tests,
commands and remaining gates, and [source revisions](../provenance/primary-sources.md).
Public callbacks provide a neutral compatibility surface, not drop-in semantic
parity. `send/2` completes synchronously; no fictitious receive queue exists.
Compatibility claims require exact differential scenarios for the advertised API.

Runtime adapters reject credential objects they cannot interpret. Native client
credentials/options are supplied explicitly by the consumer. A custom Client
implementation is trusted executable code and must honor the timeout and cleanup
contract; the wrapper cannot impose those guarantees on an arbitrary module.
Unknown Form extensions remain immutable but are not silently treated as
implemented protocol behavior. Finite deadlines, unsupported operations and
remote failures use structured Error values. Failed mutations report unknown
effect when execution may have started; a transport acknowledgment is not
canonical device state.
