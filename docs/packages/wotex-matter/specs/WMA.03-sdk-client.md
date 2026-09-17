---
spec:
  id: WMA.03
  title: "Explicit native SDK client"
  status: accepted
  version: 2.0.0
  owner: wotex-matter
  updated: 2026-09-17
---

# WMA.03 Explicit native SDK client

The selected controller client is `Wotex.Matter.Native`. It runs the pinned
connectedhomeip v1.6.0.0 SDK through the first-party C++17
`wotex-matter-host` specified in [WMA.13](WMA.13-native-backend.md). This
replaces the earlier one-request Python factory adapter. No factory import path,
Python interpreter or Python bridge is an admitted runtime option. The package
still permits Python required by upstream SDK source generation at build time;
that toolchain is pinned and recorded by the native build manifest.

`Native.connect/1` accepts explicit controller identity, authority, storage,
trust and executable options described in WMA.13. `lifecycle: :persistent`
owns one controller until disconnect. `lifecycle: :oneshot` requires an existing
store and stored authority; its passive handle starts a fresh native controller
for each concrete read, write or invoke and closes it before returning. It
cannot commission, discover, subscribe or create credentials. Both modes
enforce exact fabric identity, finite deadlines, bounded framed IPC and
structured errors. Neither mode retries a write or invoke after an unknown
effect, and neither falls back to another backend.

The consumer owns the absolute executable path, controller configuration,
credential custody and explicit connection lifetime. The first-party backend
owns SDK startup, attestation checks, storage locking, per-path status
validation and cleanup. [WMA.11](WMA.11-standalone-client-and-preservation.md)
defines the typed standalone operations; [WMA.12](WMA.12-wotex-integration.md)
defines the two Runtime profiles. The pinned software-peer evidence and exact
native acceptance limits are recorded in
[executable evidence](../provenance/executable-evidence.md).

Selecting an arbitrary module implementing `Wotex.Matter.Client` remains an
injection boundary for consumers and tests. Passing that contract alone does
not establish an SDK, security or interoperability claim. The former
`Wotex.Matter.SDK` factory API and its `matter_bridge.py` process are removed
from this development package; consumers selecting that module must migrate to
explicit `Wotex.Matter.Native` options. The package is still a development
version, so this document does not claim a published compatibility guarantee.
