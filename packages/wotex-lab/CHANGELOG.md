# Changelog

## 0.1.0 — source foundation

- Loopback runtime transport with a linked host session, simulated Thing host
  with admission counters, and NoSec/StaticRef credential adapters exercised
  through real runtime subscriptions under instance supervision.
- Thermal example reads `1 = observed` masks with a mask-weighted target,
  accepts a caller backend, and uses `Encoded` accessors.
- Versioned deterministic thermal simulator and the window-anomaly lane:
  windowed masked scoring, persistence prediction and observation decoding
  with negative cases for fills, quality, units, dtype limits and thresholds.
- Family error shape for `Wotex.Lab.Error` and a role kill-isolation test.
- Req HTTP client with a bounded incremental SSE parser and a linked stream
  session, exercised over real sockets against a disposable Bandit server
  through runtime subscriptions.
- External conformance target exposing the core package as a subject through
  the runner protocol; both bundled corpora pass over a real port.
- Instance-owned ETS Directory repository with explicit authorization, clock
  and identifier ports and a public-API contract suite over keyset paging,
  conditional writes, expiry and authorization ordering.
- Second, independent SQLite Directory repository over Exqlite: database
  transactions and conditional SQL, an explicit instance data directory whose
  schema is created by `start_link/1`, identifier keyset paging in byte order,
  a persisted mutation-generation collection revision, and canonical JSON rows
  revalidated through the public Directory and Thing Description constructors.
  The Directory contract suite now runs the same public-API cases against both
  stores, and adds aborted-transaction rollback, persistent reopen, corrupt-row
  rejection and `retain: false` file teardown for the SQLite lane.
- Accepted WLB.01–WLB.11 specifications and versioned completion contract.
- Explicit instance supervision, bounded scenario descriptors and plugin port.
- Deterministic public-API Nx example with explicit units/backend and inert output.
- Source provenance, metadata validation and package quality gates.
- PromEx/ETS/GreptimeDB/BeamLens and lean Phoenix LiveView workbench contracts.
- Framework-independent neutral design tokens, scoped CSS and contrast tests.
- Tightened destination/credential and IoT lifecycle acceptance requirements.

This entry records a source baseline, not a published release or completed Lab
programme. Catalogue status and acceptance evidence determine supported claims.
