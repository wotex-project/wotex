# WZG.01 Library and coordinator boundary

## Status

Accepted target contract for a planned WoTEx package.

## Purpose

Provide consumer-neutral Zigbee coordinator/network/device interaction without Home Assistant, Zigbee2MQTT, a vendor cloud or a vendor hub as a runtime dependency.

## Boundaries

The package owns:
- coordinator/radio behaviour;
- host/NCP framing;
- network lifecycle and permit-join;
- ZDO discovery/interview;
- Zigbee device/endpoints/descriptors;
- ZCL frame/cluster/attribute/command machinery;
- binding/reporting configuration;
- sleepy-device lifecycle primitives;
- typed observations/errors;
- security/key-custody ports.

It does NOT own:
- home semantics;
- Aqara/Shelly product profiles;
- canonical application state;
- safety policy;
- UI;
- global credential storage.

## Host portability

The public coordinator behaviour is independent of USB, UART or SPI. First implementation SHOULD target a documented serial NCP/coordinator protocol usable on macOS and Nerves. Host-specific serial implementations remain explicit dependencies.

Library construction starts no radio/network process. Long-lived coordinator/network workers are returned as child specifications or started explicitly by the consumer.

## First backend

A TI ZNP-compatible CC2652P7-class coordinator is the preferred first qualification family, subject to exact hardware/firmware evidence. The public contract MUST NOT encode TI-specific concepts where Zigbee semantics suffice.
