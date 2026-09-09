---
spec:
  id: WBL.02
  title: "Implemented BLE profile"
  status: accepted
  version: 1.1.0
  owner: wotex-ble
  updated: 2026-09-09
---

# WBL.02 Implemented BLE profile

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

The current persistent backend is the packaged Python/dbus-next helper, selected
explicitly with `lifecycle: :persistent` and an absolute Python executable.
It owns a private D-Bus sender, bounded discovery generation, explicit Agent
pairing, acknowledged procedures, health and notification/indication streams.
Typed Peer/Characteristic/Value APIs and Property/Event Runtime relays are
implemented. `connection: :borrowed` preserves ordinary borrowed links; pending
Pair sender loss can separately cause BlueZ to disconnect the peer. Explicit
pairing never authorizes removing bonds or registering a default Agent.

Fifteen native adapter cases use real BlueZ and virtual controllers; they are
Python adapter/shared-stack evidence. The C++ .13 backend, completed public
BEAM/Runtime virtual-peer lane and complete stress acceptance are not established
by those results. The accepted native target preserves the domain API and adds
its exact backend identity and bounded credit protocol.

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
