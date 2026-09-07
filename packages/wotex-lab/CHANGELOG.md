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
- EMQTT MQTT client adapter with a linked broker session: raw deliveries and
  `:transport_down` to the runtime subscription owner, a bounded retained read
  that separates a missing retained message from a timeout, publish and read
  connections that are always torn down, no automatic reconnect and no
  credential in session state, handles, logs or errors. Exercised against a
  disposable `eclipse-mosquitto:2` broker behind `WOTEX_LAB_BROKER=1` and,
  without a container runtime, against a scripted in-BEAM MQTT 5 peer.
- External conformance target exposing the core package as a subject through
  the runner protocol; both bundled corpora pass over a real port.
- Bounded in-memory Continuum channel with a versioned fault schedule, a
  simulated cloud host that admits manifests, watermarks proposals and
  dispatches intents once, and wire conversions from Nx and runtime values.
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
- Canonical smart room: Directory discovery by TD id over paged listings, an
  HTTP thermostat and a loopback actuator consumed through Runtime, an Nx
  `setTarget` proposal, a decision policy that binds digest, principal,
  watermark, revision and expiry and dispatches once at the edge, and only the
  result crossing the Continuum channel. An MQTT energy meter adds a filled
  power feature and a budget rule that lowers the target when observed power
  exceeds it. Refusals are recorded by reason and a
  restarted policy holds no grants. The reference Thing host takes explicit
  `:actions` effects.
- Accepted WLB.01–WLB.11 specifications and versioned completion contract.
- Explicit instance supervision, bounded scenario descriptors and plugin port.
- Deterministic public-API Nx example with explicit units/backend and inert output.
- Source provenance, metadata validation and package quality gates.
- PromEx/ETS/GreptimeDB/BeamLens and lean Phoenix LiveView workbench contracts.
- Framework-independent neutral design tokens, scoped CSS and contrast tests.
- Tightened destination/credential and IoT lifecycle acceptance requirements.

This entry records a source baseline, not a published release or completed Lab
programme. Catalogue status and acceptance evidence determine supported claims.
