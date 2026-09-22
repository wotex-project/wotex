# MQTT physical lab

Protocol contract: `wotex-binding-mqtt` and `wotex-runtime`.

Runbook status: ready to prepare. No physical result is claimed.

## Initial hardware

Use Nano 33 IoT #2 or an ESP8266 ESP-01S as the physical MQTT peer with an
operator-controlled broker.

## Required scenarios

- retained Property state;
- non-retained Event delivery;
- Last Will after abrupt peer loss;
- QoS and profile behaviour supported by the binding;
- session expiry and reconnect;
- duplicate delivery;
- stale retained-value admission;
- ACL isolation;
- broker restart;
- bounded inflight work.

## Semantic target

Use the same motion and environment Thing Model as the BLE and HTTP lanes where
affordances overlap. MQTT topic structure must not leak into ordinary WoT
values.
