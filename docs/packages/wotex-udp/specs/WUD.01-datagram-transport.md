# WUD.01 Generic datagram transport

## Status

Accepted target contract for a planned WoTEx package. No implementation claim.

## Purpose

Provide caller-owned bounded UDP/datagram mechanics reusable by protocol packages/consumers. UDP alone is not a WoT binding and does not define Property/Action/Event semantics.

## Required capabilities

- IPv4/IPv6 unicast where host supports it;
- explicit broadcast;
- explicit multicast membership where selected;
- local/remote endpoint values;
- bounded datagram size;
- send/receive deadlines;
- source-address metadata;
- caller-owned socket lifecycle and supervision;
- explicit interface selection;
- typed socket/timeout/permission errors;
- no hidden retry policy;
- no application environment discovery or singleton.

Constructing values starts no process or socket.

## Security

Inbound datagrams are untrusted. Enforce finite bytes, queue depth and receive budgets. Broadcast/multicast must be explicitly enabled. No payload is interpreted by this package.

## Boundary

LIFX packet framing/discovery belongs to its consumer adapter. CoAP keeps its own accepted protocol/native ownership unless a later evidence-backed refactor proves a reusable datagram seam without weakening its contracts.

## Evidence

First physical consumer evidence SHOULD include old LIFX LAN broadcast/unicast traffic, but LIFX behavior is not part of WUD conformance.
