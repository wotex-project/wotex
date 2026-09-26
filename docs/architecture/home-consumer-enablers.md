# Generic enablers required by local-first consumers

A downstream local-first home consumer exposed three reusable gaps that belong in WoTEx rather than the product:

1. **Generic bounded UDP/datagram infrastructure** — target WUD.01.
2. **Generic Zigbee coordinator/network/ZCL package** — target WZG.01-WZG.03.
3. **Matter exposed bridge/server role** — target WMA.09; existing Matter support remains controller-side.

These specifications deliberately contain no home-product or vendor semantics. Product profiles, canonical state, automation and safety remain consumer responsibilities.

The changes are additive. Existing CoAP ownership is not refactored merely to share UDP, and existing Matter controller contracts remain intact.
