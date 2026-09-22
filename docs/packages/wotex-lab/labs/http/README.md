# HTTP/SSE physical lab

Protocol contract: `wotex-binding-http` and `wotex-runtime`.

Runbook status: ready to prepare. No physical result is claimed.

## Initial hardware

Use Nano 33 IoT #2 as an independent Wi-Fi Thing. Add Shelly Motion 2 only
after verifying its local API and firmware and confirming that it needs no
cloud enrollment.

## Required scenarios

- Property read over HTTP;
- writable fixture Property or harmless Action;
- Event or observation through the binding's accepted streaming or polling semantics;
- explicit content type;
- deadline or timeout;
- peer restart;
- malformed JSON or value;
- authentication failure when enabled;
- no protocol-specific application branch above Runtime.

## Universal comparison

Expose the same `motion` semantics as the BLE fixture and compare the
Runtime-level result with the BLE lane.
