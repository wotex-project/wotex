# HTTP / SSE physical lab

**Owner:** `wotex-binding-http` + `wotex-runtime`

## Initial hardware

Nano 33 IoT #2 as an independent Wi-Fi Thing. Shelly Motion 2 may be added only after its local API/firmware is verified and cloud enrollment is unnecessary.

## Required scenarios

- Property read over HTTP.
- Writable fixture property or harmless Action.
- Event/observation through the binding's accepted streaming/polling semantics.
- explicit content type;
- deadline/timeout;
- peer restart;
- malformed JSON/value;
- authentication failure when enabled;
- no protocol-specific application branch above Runtime.

## Universal comparison

Expose the same `motion` semantics as the BLE fixture and compare the Runtime-level result with the BLE lane.
