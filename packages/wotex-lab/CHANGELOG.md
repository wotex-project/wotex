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
- Bounded Axon room-model training with a time-first split, training-only
  normalization, held-out persistence comparison, serialized parameters and
  content digests; BinaryBackend/Evaluator and EXLA CPU run as an explicit
  numerical cohort with transfer, deallocation and tolerance evidence.
- Explicit-instance `Nx.Serving` examples cover inline and supervised serving,
  batch padding, finite timeout flush, concurrent reply correlation, overload
  refusal and worker/caller shutdown when a serving child is stopped.
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
- Hosted HTTP destination admission requires HTTPS, an exact origin and an
  all-public DNS answer, pins the selected peer through connect and retains TLS
  hostname verification; the local profile verifies a CA-signed fixture.
- The MQTT profile adds closed session/inflight/packet/Last-Will configuration,
  verified MQTTS, broker ACL isolation, abrupt-loss Will delivery, session
  expiry and device-clock/reset-aware sample admission before `Wotex.Nx`.
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
- Lab telemetry under `[:wotex, :lab, component, operation, event]` with
  allowlisted, bounded metadata and exception spans that carry the kind only,
  emitted by the runtime, HTTP, SSE, Directory, Continuum, conformance, Nx
  and policy seams. Evidence records with explicit missing-archive statements,
  public-evidence refusals, canonical encoding and content digests.
- Base and profile dependency split: Runtime, both bindings, Directory,
  Continuum and Exqlite are optional requirements whose Lab modules compile
  only when the package is loaded; the conformance runner is a development
  dependency. The archive-consumer gate resolves the base profile from admitted
  archives through a local Hex registry with Git absent from the PATH and
  records evidence with archive digests.
- Optional ex_maude formal profile: the digest-addressed `thermal-control-v1`
  model with safe and deliberately broken modules, an explicit abstraction, a
  closed serializer, bounded verification with complete-search exhaustion,
  engine reaping after timeouts and pool removal, counterexample replay
  through the smart-room policy, and `Wotex.Lab.stop_child/3`.
- Model Context Protocol server pinned to 2025-11-25 with stdio and
  Streamable HTTP transports, embedded catalogue and provenance resources,
  simulated-Thing resources of an explicit instance, bounded read tools with
  session quotas, and writes only behind a host token with per-request
  idempotency keys.
- Reference-consumer gate that runs every suite with the broker, GreptimeDB
  and formal lanes enabled where their dependencies exist and records absent
  lanes as not run; the formal profile now emits under the `formal` telemetry
  component with a budget measurement.
- Sixteen executable Livebook cookbooks under `priv/cookbooks/`, one per
  WLB.07 row, each with goal, prerequisites, ownership, run cells, deliberate
  breakage, safe telemetry, expected output, public seam, spec/completion
  IDs and replacement adapter instructions, showing the package calls beside
  any Lab convenience API. `Mix.install` names published-artifact
  requirements and says plainly that no `wotex*` package is published yet.
  `Wotex.Lab.Cookbook` catalogues the notebooks with a lane status and a
  notebook evidence status; `test/wotex/lab/cookbook_test.exs` evaluates
  every cell of every notebook against the workspace cohort through a
  test-only runner and asserts sections, catalogue ids, loaded modules and
  each notebook's final checks. `formal-control` and `nerves-and-mcp` retain
  partial notebook evidence: the formal source lane has not yet been wired
  into its cookbook and the Nerves target remains incomplete. The Serving and
  Axon notebooks execute their padding, timeout, overload, training and
  backend-cohort claims.
- Fixture manifests (schema 1.1.0) for the thermal, loopback, HTTP, MQTT,
  Directory and Continuum fixtures with media type, provenance, input and
  expected-output digests, positive/negative vector ids, spec/seam/operation
  ids and scenario.
- `Wotex.Lab.Graph` generates the versioned source graph that joins the
  catalogue, the completion plan, the upstream provenance snapshot (statuses
  verbatim, absent axes `not_reported`), the cookbooks, the fixtures and the
  Lab scenario, adapter and seam descriptors; it rejects unresolved ids,
  paths and callbacks, duplicates, undeclared ownership changes and scenario
  cycles, renders `/.well-known/wotex`, `/manifest.json`, `/manifest.jsonld`,
  `/ecosystem.ttl`, `/fixtures/index.json`, `/docs-index.jsonl`,
  `/openapi.json` (3.2.0), `/asyncapi.yaml` (3.1.0) and `/llms.txt`, and
  answers the WLB.07 ownership questions from graph nodes. `mix run
  --no-start bin/check_graph.exs` validates every representation in
  `mix check`. `Wotex.Lab.Telemetry.forward/4` forwards spans to an explicit
  receiver.
- Accepted WLB.01–WLB.11 specifications and versioned completion contract.
- Explicit instance supervision, bounded scenario descriptors and plugin port.
- Revision-pinned scenario definitions and an explicit trusted-component host,
  with strict plugin manifests and dependency pins, preflight reconstruction of
  forged structs, unique bounded attempts, monitored callback execution,
  partial-start unwind, cancellation, cleanup and deterministic logical replay.
- Deterministic public-API Nx example with explicit units/backend and inert output.
- Source provenance, metadata validation and package quality gates.
- PromEx/ETS/GreptimeDB/BeamLens and lean Phoenix LiveView workbench contracts.
- Metrics base library: a checked-in versioned metric catalogue as data with
  closed dimensions and an outcome-class mapping, an instance-owned collector
  that aggregates Lab telemetry in the emitter with an atomic series budget,
  reset identity and negative-duration rejection, a bounded per-instance ETS
  snapshot history with atomic admission, eviction and loss counters, the
  admitted read-only query descriptor answered from ETS with reset-aware
  counters and bucket-derived quantiles or refused as unsupported, a parser
  and renderer for the pinned Prometheus text exposition, a hand-encoded
  Remote Write 1.0 sender with a pure Elixir Snappy block codec, and a
  supervised self-scraper/exporter bridge with bounded retry, overload drops,
  ambiguous-write reporting and just-in-time redacted credentials. Exercised
  against a disposable Bandit endpoint and, behind `WOTEX_LAB_GREPTIME=1`,
  against a disposable `greptime/greptimedb:v1.1.4` container with SQL
  read-back. The telemetry vocabulary gained `formal` and `metrics`
  components and `cleanup`, `export`, `query` and `investigation` operations;
  the Continuum channel and the thermal example emit delivery and batch
  measurements.
- Framework-independent neutral design tokens, scoped CSS and contrast tests.
- Tightened destination/credential and IoT lifecycle acceptance requirements.

This entry records a source baseline, not a published release or completed Lab
programme. Catalogue status and acceptance evidence determine supported claims.
