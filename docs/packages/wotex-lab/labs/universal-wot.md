# Universal WoT physical interoperability lab

## Purpose

Prove that the same semantic Thing is consumable through multiple physical
protocol implementations while preserving one application-facing affordance
contract.

## Reference Thing

Use a small `MotionEnvironmentThing` model with:

- Property `motion` : boolean
- Property `temperature` : number, optional when fixture hardware lacks it
- Property `batteryLevel` : number, optional
- Event `motionDetected`
- Action `identify` : optional, harmless fixture-only LED blink/beep

Every protocol fixture exposes only the subset it physically supports. Required semantic equivalence applies to affordances present in both compared implementations.

## Initial physical implementations

### BLE

Nano 33 IoT #1 + PIR/IMU:
- GATT read for motion state
- notification for motion changes
- optional harmless identify action through acknowledged write

### HTTP

Nano 33 IoT #2:
- GET Property
- SSE or bounded polling/observable path according to HTTP binding contract
- POST/PUT harmless identify action if admitted

### MQTT

Nano 33 IoT #2 or ESP-01S:
- retained property topic
- event publication
- command topic with correlation according to the MQTT binding profile

## Acceptance matrix

For every pair of protocols:

- same TD/TM semantic names and DataSchemas;
- same unit interpretation;
- same valid/invalid input outcomes at the WoT boundary;
- same consumer operation names;
- no application branch on transport;
- loss/reconnect produces typed transport/lifecycle differences without changing semantic identity;
- duplicated physical events do not become silently invented canonical state;
- credential material remains outside TDs;
- no protocol-specific metadata leaks into ordinary Property values.

## Negative cases

- malformed BLE value versus malformed HTTP JSON versus malformed MQTT payload;
- unsupported action;
- stale retained MQTT state;
- disconnected BLE peer;
- HTTP timeout;
- duplicate event delivery;
- restart host between observation and subsequent read.

## Evidence

A run records:
- exact Thing Model/TD digest;
- fixture firmware commit;
- protocol package commit;
- host OS/controller/broker identity;
- each Runtime request/result;
- semantic comparison result.

The report must say which comparisons were physical and which were simulator/software-only.
