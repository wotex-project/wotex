# WMA.09 Exposed Matter bridge/server target

## Status

Proposed target contract. Not implemented. Existing WMA.01-WMA.08 remain controller-side and MUST NOT be cited as bridge/server evidence.

## Purpose

Add an explicitly separate Matter server/accessory role capable of exposing consumer-owned Things as Matter endpoints, including bridged non-Matter devices.

## Required boundary

The native connectedhomeip host owns generic:
- Matter server lifecycle;
- fabric/commissioning state;
- bridge root/aggregator semantics;
- endpoint allocation and durable endpoint identity;
- Device Type/cluster declarations;
- inbound attribute reads/writes/commands;
- event/attribute reporting;
- commissioning windows and ACL enforcement;
- restart/recovery.

The consumer owns:
- which Things are exported;
- semantic mapping from consumer domain to Matter Device Types;
- authorization beyond Matter fabric admission;
- physical Action-effect truth;
- safety policy.

## Runtime integration

Inbound Matter requests MUST pass through an authenticated/authorized consumer boundary before ExposedThing dispatch. A successful Matter command is not automatically a physical-effect observation.

Endpoint identity MUST remain stable across host restart and must not silently rebind to another Thing.

## Bridged devices

A bridge may represent non-Matter physical devices. The bridge contract MUST preserve that distinction and cannot claim the underlying device itself is Matter-certified.

## Evidence

Required software peers include a bridged light and at least one non-light endpoint. Physical ecosystem evidence is separate and should include independent Matter controllers only after the generic server contract passes software gates.

CSA certification is outside ordinary package conformance and must never be implied by passing WMA tests.

## Delivery

The [exposed bridge delivery plan](../plans/exposed-bridge-delivery.md) sequences the existing target's native profile, endpoint custody, consumer authorization, reporting and independent-peer evidence. It adds no implementation claim to this target or the controller catalogue.
