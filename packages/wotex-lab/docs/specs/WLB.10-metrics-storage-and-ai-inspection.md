# WLB.10: Metrics, storage and AI inspection

Specification version: 0.3.1. Contract: accepted. Source status: the metric
catalogue, the in-process collector, the bounded ETS history with its read-only
query contract, the exposition parser, the remote-write encoder with its Snappy
codec and the explicit GreptimeDB bridge are implemented in the base library;
the Workbench now implements custom PromEx definitions, bounded collection,
catalogue panel selection and inert Grafana JSON exports. Built-in host
introspection, collection-to-history host activation, protected scraping, OTLP
signal export, BeamLens, history presentation and the MCP query gateway remain
planned. A template export is not proof of a Grafana import or query execution.

## Stack and ownership

The reference host uses `:telemetry`, `Telemetry.Metrics`, PromEx, bounded ETS
history, GreptimeDB and BeamLens. This is a selected, replaceable reference
stack, not a dependency requirement for numerical conversion. No ELK stack,
mandatory Grafana, Prometheus server, cloud account or separate collector is
part of the baseline. All components require explicit host activation.

| Layer | Reference | Ownership |
| --- | --- | --- |
| Events | WLB.06 telemetry namespace | Lab spans around public package calls |
| Metric definitions | Telemetry.Metrics and custom PromEx plugin | Versioned names, units, buckets, finite dimensions |
| Collection | Host PromEx module; built-in BEAM/Phoenix/LiveView plugins | In-process aggregation and protected exposition |
| Active history | Bounded per-instance ETS snapshot store | Disposable, explicitly lossy, no durability claim |
| Durable history | GreptimeDB standalone or supplied service | Local separate process, SQL/PromQL and explicit retention |
| AI investigation | BeamLens custom metrics skill | On-demand, read-only, bounded, evidence-grounded |
| Presentation | WLB.11 LiveView workbench; PromEx dashboard exports | Native default UI; portable Grafana templates |

GreptimeDB standalone is not an embedded BEAM database. It is a single local
service or supplied endpoint with explicit data directory, resource budget,
credentials and lifecycle. The zero-service experience uses ETS; the durable
profile uses GreptimeDB. Neither silently falls back to the other. An unavailable
store is shown as unavailable, never as zero measurements.

PromEx supplies metric capture and Grafana dashboard definitions, not a UI or
a remote-write sender. Lab MUST implement and test the collection-to-store
bridge explicitly. Core libraries MUST NOT gain Lab telemetry dependencies.

## Metric catalogue and collection

One checked-in metric catalogue MUST generate the custom PromEx definitions,
UI panel descriptors, query templates and exported dashboard queries. A name,
unit, bucket, dimension or scope mismatch fails generation. Custom dashboards
compose admitted descriptors, not arbitrary JavaScript, EEx or module names.
`Wotex.Lab.Metrics.Catalogue` is that catalogue as data: `validate/1` fails on
a name, unit, bucket, dimension, scope, event or measurement mismatch and on
duplicate ids, and `to_definitions/0` emits the plain maps a host turns into
Telemetry.Metrics and PromEx definitions. The explicit Workbench's
`Observability.Definitions`, `Plugin` and `Panels` now generate all 43 custom
definitions, UI descriptors and fixed PromQL templates from that catalogue.
Panels retain exact units, buckets, dimensions and scope. Dashboard composition
accepts 1–16 distinct known IDs, never caller code or expressions. Counters show
five-minute rates with per-second display units, gauges their measured values,
and histograms bucket-derived p95. Each label set is preserved; templates do
not accidentally aggregate different receiver job/instance labels or fill
missing data with zeros. The session-verified `/metrics/dashboard.json` route
exports only inert definitions; it does not read measurements or upload JSON.

PromEx 1.12.0 uses the host's compile-time-selected public `PromEx.Storage`
adapter. `Observability.Store` admits only this exact definition cohort and
aggregates synchronously in bounded ETS, with inclusive histogram buckets and
nanosecond integer sums. It never buffers raw samples or reads private PromEx/
Peep tables. PromEx's default manual status group is explicitly dropped.
`Observability.Relay` maps original Lab events to one normalized event per
metric, preserves closed labels and counts rejected source measurements.
`WOTEX_LAB_PROMEX=1` explicitly starts the host-owned one-for-all supervisor;
default collection is off. Public `PromEx.get_metrics/1` works without any HTTP
listener, Grafana agent, automatic upload, database or LLM. The built-in
BEAM/Phoenix/LiveView plugin cohort still requires its separate privacy and
cardinality admission; no raw introspection is enabled by this implementation.

Required metric groups: scenario outcomes/cleanup; transport requests and
subscription churn/drops; Directory operations/conflicts; Continuum delivery
and rejection; Nx admission/encode/inference/decode latency, rows, width,
batch fill, masks, quality and queue depth; conformance outcome/reason counts;
formal verification duration/budget; exporter backlog/loss; query/LLM budget.
Backend/compiler, synthetic vs observed source and model revision belong to
run evidence; only a finite configured backend class is a metric dimension.
Training loss/held-out results are run data, not labels or proof of accuracy.
Every group has catalogue metrics whose source events use the WLB.06
vocabulary; the `formal` and `metrics` components and the `cleanup`, `export`,
`query` and `investigation` operations were added for verification, exporter,
query and investigation metrics. Scenario cleanup, subscription drops, mask,
quality and queue-depth, formal verification and investigation metrics have no
Lab emitter yet; the catalogue states them and nothing simulates them.

Handlers execute synchronously in the emitter. They MUST perform only bounded
validation/aggregation; no network, model call, disk write or blocking query.
Unbounded casts into a GenServer are not a bounded queue. Enqueue admission
must reserve capacity atomically or drop and count the sample. Diagnostics
failure MUST NOT affect numerical output, authorization or cleanup.
`Wotex.Lab.Metrics.Collector` is that handler: it aggregates in the emitter
into a public ETS table with atomic counter updates, reserves series capacity
atomically before creating a series, drops and counts beyond the budget, and
counts its own failures instead of raising into the caller.

Default budgets per instance: 256 active scalar series (histogram bucket,
sum and count each consume capacity), 120 snapshots at 5-second intervals,
8 MiB encoded history, 1 MiB scrape/response, one export in flight, 16 queued
export batches, 5-second export deadline. All limits are explicit positive
configuration with tested hard host ceilings. Oldest history is evicted;
export overload drops the oldest unsent snapshot with a loss counter. Release
evidence records every configured override and all drops, gaps and resets.
The collector (256 series, ceiling 4,096), `Wotex.Lab.Metrics.History` (120
snapshots and 8 MiB, ceilings 10,000 and 64 MiB) and
`Wotex.Lab.Metrics.GreptimeBridge` (one export in flight, 16 queued snapshots
and a 5-second deadline, ceilings 256 and 60 seconds) implement these limits as
validated options and expose every drop, gap and reset in `stats/1`; writing
them into release evidence remains the WLB.06 record's concern.

Dimensions are finite catalogue enums. User Thing IDs, run IDs, topic strings,
URLs, prompts, principal IDs and arbitrary errors MUST NOT become labels.
Bounded host-assigned instance slots are permitted with explicit expiry/reset;
slot reuse cannot join the histories of two instances. VM metrics are host-wide,
collected once, and MUST NOT be presented as per-tenant or per-run memory.
PromEx's global storage-adapter setting is configured once by the host, never
changed by a Lab instance. Lab does not mint modules/atoms per instance.
`Catalogue.dimension_value/4` derives every label from a closed enum, maps
outcome atoms through `outcome_class/1` and unknown profiles or operations to
`other`, and the collector stamps its configured instance slot on each
snapshot. The implemented PromEx host adapter describes the single Workbench
Lab instance, not browser sessions. Its fixed registered names are host-owned;
no per-session atoms/modules are generated. Slot expiry and tenant-isolated
collection/history remain planned. VM metrics are not currently enabled.

Counters preserve reset identity and cumulative semantics. Histograms use
versioned fixed buckets; percentile queries derive from bucket counts, never
average percentiles. Metric durations are seconds after monotonic-unit
conversion; sensor event time, ingestion wall time and monotonic elapsed time
are distinct. Clock rollback cannot produce negative durations or reorder a
series silently. Missing, stale, dropped and zero remain distinguishable.
The collector keeps `started_at` plus `generation` as the reset identity,
converts native durations to seconds and rejects negative durations;
`History.query/2` derives quantiles from bucket deltas; and
`Wotex.Lab.Metrics.Snapshot` keeps a missing series, a `:stale` sample, the
drop counters and a measured zero apart in every reading.

## Explicit GreptimeDB bridge

A supervised BEAM self-scraper calls public `PromEx.get_metrics/1`; it does not
read private PromEx/Peep ETS internals. It accepts the pinned Prometheus text
exposition contract, normalizes counters/gauges/classic histogram samples,
and writes the same admitted snapshots to bounded local history and the sink.
Unknown types or malformed/duplicate series fail that snapshot visibly.
No self-HTTP listener is needed. A protected `/metrics` endpoint is an opt-in
integration surface, not a public tenant data endpoint.
`Wotex.Lab.Metrics.GreptimeBridge` is that self-scraper with an explicit
`scrape` function (a host passes `PromEx.get_metrics/1` or the collector's own
snapshot), `Wotex.Lab.Metrics.Exposition` parses and renders the pinned text
format, and the same admitted snapshot reaches history and the sink. The
protected `/metrics` endpoint remains a planned host surface.

The durable sink uses Prometheus Remote Write 1.0 to GreptimeDB's
`/v1/prometheus/write`: standard generated protobuf, Snappy **block** encoding,
reserved headers, sorted unique labels, millisecond timestamps, ordered samples
and stale markers. This is a bounded exporter adapter, not a query engine.
Pin codec sources/licenses and test official sender compatibility plus actual
GreptimeDB ingestion. Do not relabel plain exposition text as protobuf.
Special wire floats/stale markers are encoded as protocol values without
admitting NaN/Infinity into WoT observations or Nx inputs.
`Wotex.Lab.Metrics.RemoteWrite` hand-encodes `WriteRequest` with the field
numbers documented in its moduledoc and `Wotex.Lab.Metrics.Snappy` supplies the
block codec in pure Elixir; `test/wotex/lab/greptime_bridge_test.exs` proves
actual ingestion into `greptime/greptimedb:v1.1.4` behind `WOTEX_LAB_GREPTIME=1`.
Compatibility with other receivers or official senders is not claimed.

Retry only retryable transport/5xx failures with capped jitter/backoff and the
same snapshot identity; honor bounded 429 retry policy; do not retry invalid
4xx forever. Preserve per-series ordering and report ambiguous/partial writes.
No exactly-once or lossless claim follows from HTTP success. An operator may
supply an existing compliant collector instead of the bridge, but that path
has a separate integration test and is not a baseline requirement.
The bridge implements exactly this policy through `Wotex.Lab.Metrics.ReqSink`
or any host sink function, keeps the snapshot identity across retries and
reports ambiguous writes; the external-collector path is not implemented.

GreptimeDB query credentials and export credentials have separate scopes. The
Lab gateway allows only read templates for inspection, with no arbitrary SQL,
DDL, file functions, cross-database reads or user-selected endpoints. Database
provisioning and TTL changes are operator actions. Standalone defaults that
disable authentication MUST NOT be exposed remotely. Bind private listeners,
verify TLS/hostname, restrict egress and redact credentials before diagnostics.
Default durable metric TTL is seven days; a profile may explicitly override it.
Run evidence is stored separately and does not disappear with metric TTL.
Export credentials are resolved just in time from a host reference and
redacted from stats and errors. The query gateway, TLS and egress policy and
TTL provisioning remain planned host work.

Logs/traces use optional OTLP/HTTP-protobuf export to GreptimeDB's documented
signal endpoints, not a claim that PromEx exports them. Validate signal-specific
pipeline headers, temporality, partial-success replies and retention against
the pinned server. No mandatory collector or tracing of raw sensor payloads.
OTLP export is planned; nothing in the base library sends logs or traces.

## Read-only query contract and BeamLens

UI, MCP and BeamLens share an admitted query descriptor: schema version,
server-bound instance/session scope, catalogue metric/template ID, closed
aggregation enum, finite filters, UTC start/end, step and limits. Caller text
cannot change scope. Default limits: 24-hour range, 5-second minimum step,
10,000 returned points, 1 MiB output, 2-second query deadline, two concurrent
queries per session. Admit estimated work before querying, not just SQL LIMIT
after an unbounded scan. Responses carry source, interval, unit, freshness,
loss/reset markers, query digest and evidence references. Unsupported local
history queries return unsupported; ETS does not pretend to implement PromQL.
`Wotex.Lab.Metrics.Query` is that descriptor with these defaults, its
`estimate/1` admits the work before anything is read, and `History.query/2`
answers gauges, counters with reset awareness and histogram quantiles from ETS
or returns `unsupported_query`. The MCP gateway and the BeamLens callers of
the descriptor remain planned.

History query admission now binds the store's explicit `:instance` identifier
and snapshot `:instance_slot` (default 0). Migration: hosts using `query/2`
must configure `instance: "their-host-id"` when starting history and construct
the descriptor's session scope from authenticated server context. Stores
without that identifier remain storage-only and return `scope_unbound`; a
different instance or snapshot slot returns `scope_denied`. An identifier is
not an authorization credential and shared-BEAM processes remain trusted.
Transport authentication, expiring query capabilities and tenant isolation
still belong to the unimplemented gateway/host profile.

Snapshots and query structs are revalidated at the execution boundary. Query
samples must match the catalogue's type, finite labels and exact histogram
buckets. A store permits 32 active query leases by default (hard ceiling 128),
as well as the descriptor's session limit; leases are monitored, revoked on
caller death and removed on success/error/deadline without retaining idle
session keys. Query buckets are indexed once instead of repeatedly scanning
all stored series for each point. Cooperative deadline checks run during
validation, indexing and point evaluation; they are not OS containment.

Counter and histogram deltas retain all resets inside each query bucket,
including when the interval is coarser than capture. Empty histogram queries
return no data; stale samples are markers, not new zero-valued counters.
Wall-clock rollback is retained as a row flag/loss counter and affected
queries return `clock_rollback`, rather than silently sorting cumulative data.
`metrics_query_test.exs` and `metrics_history_test.exs` reproduce and guard
these cases, forged descriptors, cross-instance/slot substitution, capacity,
caller death and deadline cleanup. Snapshot storage is bounded; hosts must
also bound writer concurrency. Serial GenServer calls alone do not bound an
arbitrary population of callers.

BeamLens is a required reference integration with optional user activation.
Use its public custom-skill callbacks and explicitly selected skills. Never
start its default all-skills set: tracing, raw logs, exception stacks, arbitrary
ETS/process inspection and automatic anomaly investigations are disabled in
the disposable hosted profile. Dependency startup, global names and telemetry
handlers require inspection in the admitted cohort. A host-scoped BeamLens
service is not proof that BeamLens supports isolated per-instance supervisors.
Untrusted hosted tenants require separate worker/OS isolation; shared-VM
introspection is reserved for the trusted local operator profile.
The BeamLens integration, its custom skill, the prompt entry point and the
answer presentation in the following paragraphs are planned; no source exists.

The custom skill exposes bounded `lab_metric_catalogue`, `lab_metric_query`,
`lab_run_summary` and `lab_compare_runs` callbacks. Their service-side request
scope expires with the investigation. A model-supplied instance ID, Lua global,
prompt or prior conversation cannot substitute for that scope. No shell,
arbitrary Elixir, raw SQL, raw credentials, external URL or Action callback is
provided. Dependency base callbacks/node metadata are part of the privacy
review, not assumed absent merely because the custom skill is restrictive.

The prompt entry point is on-demand. Default budget: one investigation per
session, 30 seconds, 8 model turns, 12 tool calls and 32 KiB admitted context;
provider token/cost limits must also be explicit. Cancellation and timeout
terminate the investigation and revoke its query scope, not merely detach the
UI caller. Local providers are supported; cloud model use requires explicit
provider selection and disclosure of exactly which redacted data leaves the
host. No automatic API-key discovery, model download or endless agent loop.

Answers show observed facts separately from hypotheses, source queries/time
ranges and missing evidence. Queried labels/logs, tool results and prompts are
untrusted data, not instructions. Render escaped text, never executable HTML.
No-data, stale data, denied scope, provider failure and cancellation have
distinct UI states. Generated advice cannot authorize or invoke an Action.

## Nx data boundary and acceptance

### Optional Explorer analysis

The [interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md)
selects Explorer for explicit dataframe analysis, not metric capture, storage
or plotting. `Wotex.Lab.Analytics`, `Analytics.Source` and `Analytics.Query`
implement this optional profile against Explorer 0.12.0/Polars. The explicit
Workbench host selects it; `window-anomaly.livemd` demonstrates the same API
beside public Explorer calls. Neither base consumers nor other notebooks need it.
It operates only on admitted, bounded run data or frozen query results. Use a
closed descriptor for series/range selection and summary operations; no raw
SQL, arbitrary expression, caller module, URL or filesystem source is accepted.
Source and query digests, units, missing/nonfinite counts and preview/downsampling
provenance accompany every result. Values from unlike units are never silently
aggregated together. Apply native filtering/aggregation before extracting the
at-most 100-row, 32-column preview; bound the native input and intermediate work
as well as final output. Report native failures as unavailable, never empty
success. The base numerical package closure still excludes Explorer.

The implemented source contract accepts at most eight named series with 2,000
points each and one MiB of canonical scalar data. Queries select a supplied
series and inclusive numeric range, with a 1–100 row preview. Aggregates group
by series and unit; nulls and explicit nonfinite atoms have separate counts.
The profile uses explicit `f64` and refuses integers outside ±(2^53−1), instead
of silently losing precision. Stable, versioned canonical identities bind
source metadata, ordered points and query controls. Tests in
`test/wotex/lab/analytics_test.exs` cover these bounds, null/nonfinite/empty
semantics, native summaries and unchanged Nx backend selection. This is bounded
native computation, not OS containment of untrusted executable code.

LiveView and notebook controls may refine the visible analysis without
re-running an experiment or mutating its evidence. A filtered chart is not a
replacement dataset, and live history does not become immutable merely by
wrapping it in a dataframe. The following dataset contract still applies.

Diagnostic history is lossy and MUST NOT silently become training data. Export
to an experiment creates an immutable, content-addressed dataset with query,
source interval, snapshot/watermark, ordering, units, quality, masks, missing
policy and split provenance. Freeze a consistent snapshot before windowing,
splitting or normalization. Explain every downsampling transform. Resuming a
run cannot silently read changing live metrics as the original dataset.
Dataset export from diagnostic history is planned; the history exposes no
training-data path.

Acceptance requires PromEx-to-ETS/Greptime equality fixtures, reset/stale/
histogram cases, bounded overload, disk/network loss, TTL expiry, shutdown,
two-instance isolation, protected scrape/query endpoints, token sentinels,
prompt injection, cross-session scope substitution, cloud-disclosure and
cancelled-agent tests. Prompt cases include missing-mask spikes, warm-up vs
inference latency, SSE drops, MQTT duplicates and dataset split leakage. All
answers resolve to recorded queries; fluent unsupported answers fail.
`test/wotex/lab/metrics_*.exs` cover the collector-to-exposition equality
fixture, reset, stale and histogram cases, series and history budgets, atomic
admission, bounded exporter overload, retry and no-retry, network loss,
shutdown, two-instance isolation and the export credential sentinel;
`test/wotex/lab/greptime_bridge_test.exs` covers actual ingestion. TTL expiry,
protected endpoints, prompt injection, scope substitution, cloud disclosure and
cancelled-agent tests arrive with their planned features.
