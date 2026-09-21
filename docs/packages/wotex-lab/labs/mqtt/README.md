# MQTT physical lab

**Owner:** `wotex-binding-mqtt` + `wotex-lab`

## Initial hardware

Nano 33 IoT #2 or ESP8266 ESP-01S as physical MQTT peer. Use an operator-controlled Mosquitto broker.

## Required scenarios

- retained Property state;
- non-retained Event delivery;
- Last Will after abrupt peer loss;
- QoS/profile behaviour supported by the binding;
- session expiry/reconnect;
- duplicate delivery;
- stale retained value admission;
- ACL isolation;
- broker restart;
- bounded inflight behaviour.

## Semantic target

Use the same motion/environment Thing Model as BLE/HTTP where affordances overlap. MQTT topic structure must not leak into ordinary WoT values.
