# Thread physical lab

**Owner:** `wotex-thread`

Status: planned physical lane.

## Hardware class

OpenThread-compatible border-router radio plus at least one independent Thread end device.

## Acceptance

- topology/neighbor/route inspection;
- partition/rejoin;
- border-router restart;
- channel/network identity reporting;
- OpenThread SDK management boundaries;
- no assumption that Thread itself defines application semantics.

Pair with Matter or CoAP only when those protocol labs explicitly own the application-layer interaction.
