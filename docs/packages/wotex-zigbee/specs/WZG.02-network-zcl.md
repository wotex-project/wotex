# WZG.02 Zigbee network and ZCL contract

## Status

Accepted target contract for a planned package.

## Network lifecycle

Network formation, restore, permit-join, leave, rejoin and coordinator replacement are explicit operations with finite deadlines.

A join event is not a complete device profile. Interview obtains node/endpoint/simple descriptors and relevant Basic-cluster identity before downstream profile selection.

## Identity

64-bit IEEE address is preserved as private physical identity evidence. 16-bit network address is transient routing state. Public consumers may substitute pseudonymous identity.

## ZCL

The package provides bounded generic ZCL:
- cluster/attribute identifiers;
- typed attribute values;
- read/write where allowed;
- commands;
- reporting configuration;
- incoming reports/events;
- manufacturer-specific framing without pretending unknown attributes have semantics.

Product-specific manufacturer attributes remain opaque typed evidence until a downstream profile interprets them.

## Sleepy devices

The package models sleepy end devices explicitly. Silence between expected reporting/check-in windows is not immediate unavailability. It MUST NOT introduce high-rate polling merely for UI freshness.

## Security

Network keys and link keys are resolved from consumer custody and never emitted in TDs/logs/errors. Permit-join is bounded. Frame/replay counters and security status are preserved where available.

## WoT mapping

Generic Zigbee does not automatically invent a Thing Model from cluster names. It may provide reusable mapping helpers for standardized clusters, but final semantic admission remains consumer/profile-owned.
