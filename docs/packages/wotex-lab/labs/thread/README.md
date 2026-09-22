# Thread physical lab

Protocol contract: `wotex-thread`.

Runbook status: planned. This does not change source implementation status.

## Hardware class

Use an OpenThread-compatible border-router radio and at least one independent
Thread end device.

## Acceptance

- topology, neighbor and route inspection;
- partition and rejoin;
- border-router restart;
- channel and network-identity reporting;
- OpenThread SDK management boundaries;
- no assumption that Thread defines application semantics.

Pair Thread with Matter or CoAP only when those protocol labs own the
application-layer interaction explicitly.
