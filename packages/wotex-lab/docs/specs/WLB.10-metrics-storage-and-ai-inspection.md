# WLB.10: Metrics, storage and AI inspection

Specification version: 0.1.0. Contract: accepted.

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

Required metric groups: scenario outcomes/cleanup; transport requests and
subscription churn/drops; Directory operations/conflicts; Continuum delivery
and rejection; Nx admission/encode/inference/decode latency, rows, width,
batch fill, masks, quality and queue depth; conformance outcome/reason counts;
formal verification duration/budget; exporter backlog/loss; query/LLM budget.
Backend/compiler, synthetic vs observed source and model revision belong to
run evidence; only a finite configured backend class is a metric dimension.
Training loss/held-out results are run data, not labels or proof of accuracy.

Handlers execute synchronously in the emitter. They MUST perform only bounded
validation/aggregation; no network, model call, disk write or blocking query.
Unbounded casts into a GenServer are not a bounded queue. Enqueue admission
must reserve capacity atomically or drop and count the sample. Diagnostics
failure MUST NOT affect numerical output, authorization or cleanup.

Default budgets per instance: 256 active scalar series (histogram bucket,
sum and count each consume capacity), 120 snapshots at 5-second intervals,
8 MiB encoded history, 1 MiB scrape/response, one export in flight, 16 queued
export batches, 5-second export deadline. All limits are explicit positive
configuration with tested hard host ceilings. Oldest history is evicted;
export overload drops the oldest unsent snapshot with a loss counter. Release
evidence records every configured override and all drops, gaps and resets.

Dimensions are finite catalogue enums. User Thing IDs, run IDs, topic strings,
URLs, prompts, principal IDs and arbitrary errors MUST NOT become labels.
Bounded host-assigned instance slots are permitted with explicit expiry/reset;
slot reuse cannot join the histories of two instances. VM metrics are host-wide,
collected once, and MUST NOT be presented as per-tenant or per-run memory.
PromEx's global storage-adapter setting is configured once by the host, never
changed by a Lab instance. Lab does not mint modules/atoms per instance.

Counters preserve reset identity and cumulative semantics. Histograms use
versioned fixed buckets; percentile queries derive from bucket counts, never
average percentiles. Metric durations are seconds after monotonic-unit
conversion; sensor event time, ingestion wall time and monotonic elapsed time
are distinct. Clock rollback cannot produce negative durations or reorder a
series silently. Missing, stale, dropped and zero remain distinguishable.

## Explicit GreptimeDB bridge

A supervised BEAM self-scraper calls public `PromEx.get_metrics/1`; it does not
read private PromEx/Peep ETS internals. It accepts the pinned Prometheus text
exposition contract, normalizes counters/gauges/classic histogram samples,
and writes the same admitted snapshots to bounded local history and the sink.
Unknown types or malformed/duplicate series fail that snapshot visibly.
No self-HTTP listener is needed. A protected `/metrics` endpoint is an opt-in
integration surface, not a public tenant data endpoint.

The durable sink uses Prometheus Remote Write 1.0 to GreptimeDB's
`/v1/prometheus/write`: standard generated protobuf, Snappy **block** encoding,
reserved headers, sorted unique labels, millisecond timestamps, ordered samples
and stale markers. This is a bounded exporter adapter, not a query engine.
Pin codec sources/licenses and test official sender compatibility plus actual
GreptimeDB ingestion. Do not relabel plain exposition text as protobuf.
Special wire floats/stale markers are encoded as protocol values without
admitting NaN/Infinity into WoT observations or Nx inputs.

Retry only retryable transport/5xx failures with capped jitter/backoff and the
same snapshot identity; honor bounded 429 retry policy; do not retry invalid
4xx forever. Preserve per-series ordering and report ambiguous/partial writes.
No exactly-once or lossless claim follows from HTTP success. An operator may
supply an existing compliant collector instead of the bridge, but that path
has a separate integration test and is not a baseline requirement.

GreptimeDB query credentials and export credentials have separate scopes. The
Lab gateway allows only read templates for inspection, with no arbitrary SQL,
DDL, file functions, cross-database reads or user-selected endpoints. Database
provisioning and TTL changes are operator actions. Standalone defaults that
disable authentication MUST NOT be exposed remotely. Bind private listeners,
verify TLS/hostname, restrict egress and redact credentials before diagnostics.
Default durable metric TTL is seven days; a profile may explicitly override it.
Run evidence is stored separately and does not disappear with metric TTL.

Logs/traces use optional OTLP/HTTP-protobuf export to GreptimeDB's documented
signal endpoints, not a claim that PromEx exports them. Validate signal-specific
pipeline headers, temporality, partial-success replies and retention against
the pinned server. No mandatory collector or tracing of raw sensor payloads.

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

BeamLens is a required reference integration with optional user activation.
Use its public custom-skill callbacks and explicitly selected skills. Never
start its default all-skills set: tracing, raw logs, exception stacks, arbitrary
ETS/process inspection and automatic anomaly investigations are disabled in
the disposable hosted profile. Dependency startup, global names and telemetry
handlers require inspection in the admitted cohort. A host-scoped BeamLens
service is not proof that BeamLens supports isolated per-instance supervisors.
Untrusted hosted tenants require separate worker/OS isolation; shared-VM
introspection is reserved for the trusted local operator profile.

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

Diagnostic history is lossy and MUST NOT silently become training data. Export
to an experiment creates an immutable, content-addressed dataset with query,
source interval, snapshot/watermark, ordering, units, quality, masks, missing
policy and split provenance. Freeze a consistent snapshot before windowing,
splitting or normalization. Explain every downsampling transform. Resuming a
run cannot silently read changing live metrics as the original dataset.

Acceptance requires PromEx-to-ETS/Greptime equality fixtures, reset/stale/
histogram cases, bounded overload, disk/network loss, TTL expiry, shutdown,
two-instance isolation, protected scrape/query endpoints, token sentinels,
prompt injection, cross-session scope substitution, cloud-disclosure and
cancelled-agent tests. Prompt cases include missing-mask spikes, warm-up vs
inference latency, SSE drops, MQTT duplicates and dataset split leakage. All
answers resolve to recorded queries; fluent unsupported answers fail.
