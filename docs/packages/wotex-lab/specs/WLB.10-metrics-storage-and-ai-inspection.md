# WLB.10: Metrics, storage and AI inspection

Specification version: 0.30.0. Contract: accepted. Source status: implemented.

The base library owns the metric catalogue, bounded collection and ETS history,
read-only query contract, immutable dataset export, Prometheus exposition,
remote-write encoding, GreptimeDB bridge, retention, durable query templates
and OTLP export. The Workbench owns PromEx collection and panels, Grafana
exports, local and hosted GreptimeDB transports, protected operator listeners,
session-room queries and the trusted-local BeamLens profile.

The Workbench also provides a separate public TLS tenant gateway. A digest-only
registry binds each credential to one durable metric instance. Public queries
cannot select scope, receiver, database or limits. Public investigations run in
a freshly started external BEAM VM under a native process-tree custodian. The
worker receives expiring loopback provider and query capabilities, never tenant,
receiver or provider credentials. `tooling/packages.yaml` and
`priv/native-artifacts/hosted-investigation.json` admit its target-specific
artifact profile.

Hosted exporter, reader, gateway and provisioning source is not proof of a
deployed receiver, retained row or public adoption. The executed source evidence
covers the local TLS listener, target-native artifact construction, the isolated
worker and its loopback bridges on the recorded runner. Linux targets and a
public hosted receiver remain separate evidence cells. A dashboard template is
not Grafana execution evidence; the pinned Grafana lane below supplies that
evidence for one server cohort.

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
`Observability.Definitions`, `Plugin` and `Panels` generate all 43 custom
definitions, UI descriptors and fixed PromQL templates from that catalogue.
Panels retain exact units, buckets, dimensions and scope. Dashboard composition
accepts 1–16 distinct known IDs, never caller code or expressions. Counters show
five-minute rates with per-second display units, gauges their measured values,
and histograms bucket-derived p95. Each label set is preserved; templates do
not accidentally aggregate different receiver job/instance labels or fill
missing data with zeros. The session-verified `/metrics/dashboard.json` route
exports only inert definitions; it does not read measurements or upload JSON.
With `WOTEX_LAB_GRAFANA=1`, the Workbench `grafana_import_test.exs` imports
that JSON for every catalogue panel into pinned Grafana 13.2.2 and runs each
stored target through Grafana against pinned GreptimeDB 1.1.4. The bridge wrote
that history from two real PromEx captures. The test requires distinct label
sets, unchanged gauge values, bounded p95 values and no values before capture.
No Prometheus server, other Grafana version or browser rendering is claimed.

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
`query` and `investigation` operations describe verification, exporter,
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
counts its own failures instead of raising into the caller. Its optional
`:attribute_to` owner restricts recording to events emitted by that process,
by processes whose `$ancestors` include it or by tasks whose `$callers`
include it; other events are ignored before any table access. Attribution
follows OTP process-dictionary conventions and is a collection filter for
trusted same-BEAM code, not an authorization or containment boundary.
`metrics_collector_test.exs` covers owner, started-process and task
attribution, unrelated emitters and option refusal.

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
no per-session atoms/modules are generated. Each Workbench session room
instead owns an attributed collector and a separate bounded history under a
random instance identifier, both discarded with the room (WLB.11). Events from
Things and shared processes started under the host instance are outside that
attribution. The implemented profiles do not multiplex several tenants into a
shared collector slot: browser rooms own and discard their collectors, while
the hosted gateway reads operator-provisioned durable instances. A future host
that reuses shared collector slots must define expiry and reset semantics. VM
metrics are not currently enabled.

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
format, and the same admitted snapshot reaches history and the sink.

Supplied Snapshot structs are revalidated at bridge admission. New captures
MUST strictly advance the whole snapshot's wall-clock millisecond timestamp
relative to the last admitted capture. Equal milliseconds or rollback return
`unordered_snapshot` and increment `rejected` before history, stale markers or
queue insertion. Attempt sequence numbers are consumed; later history can show
the gap. No timestamp is shifted and no zero sample is substituted. This is a
conservative whole-snapshot rule even when its series set changes. The watermark
does not rewind on queue loss, retry exhaustion or permanent rejection. Retries
reuse their already admitted identity and are not new captures. The watermark
belongs to one live bridge; restart/multi-writer receiver coordination remains
host work, not persisted or global ordering authority.

The Workbench's optional `Observability.Scrape` supplies `GET /metrics` on a
separate 127.0.0.1-only HTTP/1 port, leaving the browser host's existing Metrics
page unchanged. `WOTEX_LAB_METRICS_PORT` and a separately provisioned 43–128
character URL-safe `WOTEX_LAB_METRICS_TOKEN` explicitly select it; PromEx must
also be enabled. Only the token digest enters listener configuration, and
comparison uses constant-time digest equality. A single Bearer header is the
only authority. Cookies, session identifiers, query strings, non-loopback
peers and forwarded identities cannot authorize access. Token rotation is an
operator restart, not automatic credential discovery.

This pinned Bandit profile admits eight connections, one request per
connection, a 1,024-byte request line, at most 16 admitted headers of 2,048
bytes each and one MiB of response text. Request bodies, query strings and
Origin headers are refused. HTTP/2, WebSockets, CORS, compression and keepalive
are disabled. Read/write inactivity waits are two seconds; they are not a
whole-header deadline against slow clients. The default transport is a trusted
local operator surface, not an untrusted-hosted profile. Do not promote it
through port forwarding or a proxy; use the separately admitted remote
transport below instead.
Responses are non-cacheable. Collector failure is 503, never invented zeros.
Protocol and exception logging are disabled for this listener to avoid
credential reflection; client statuses remain visible. No public route reads
history, and no listener credential authorizes any numerical run or Action.
The host's `metrics_scrape_test.exs` covers pure admission and real sockets:
auth/URL/cookie/forwarding substitution, absence/failure, connection capacity,
unread oversized body refusal without draining, shutdown and token sentinels.

`Observability.OperatorTransport` is that separately admitted remote transport
for both the scrape and query listeners. `WOTEX_LAB_METRICS_TRANSPORT=remote`
selects it and requires `WOTEX_LAB_METRICS_BIND` (an IP literal),
`WOTEX_LAB_METRICS_TLS_CERTFILE`, `WOTEX_LAB_METRICS_TLS_KEYFILE`,
`WOTEX_LAB_METRICS_TLS_CLIENT_CACERTFILE` and `WOTEX_LAB_METRICS_ALLOW`, a list of
1 to 16 comma-separated CIDR ranges; any missing or malformed value refuses
startup. The listener then serves HTTPS with TLS 1.3 only and the strong Plug
suite, requires a client certificate that chains to the configured CA within
depth two, issues no session tickets and answers 403 unless the socket peer
address lies inside a range. An IPv4 range does not admit an IPv4-mapped IPv6
peer, and forwarding headers never change the peer. The Bearer credential,
request framing, connection and response bounds are unchanged. Configuration
checks only that the certificate and key paths are regular files.
`metrics_operator_transport_test.exs` covers remote admission and refusals,
exact IPv4 and IPv6 prefix matching, and real TLS sockets for both listeners
with certificates generated at test time: a trusted client succeeds with the
listener's own credential, the other listener's credential gets 401, a client
without a certificate or with a certificate from another CA fails the
handshake, plaintext HTTP gets no HTTP response and a trusted client outside the
ranges gets 403. Certificate issuance, rotation, revocation and the network
path to the listener remain operator responsibilities; this is not a tenant
endpoint.

For the zero-service profile, the Workbench's `Observability.Capture.sample/0`
calls public `PromEx.get_metrics/1`, parses the bounded exposition and pairs it
with the custom Store's matching SHA-256 receipt. The receipt carries the actual
capture clocks, collector reset identity and loss counters which plain text
does not contain. A different body or collector restart cannot silently attach
unrelated metadata: receipt mismatch/unavailability refuses that attempt.
Identical body hashes can use a later matching receipt from the same live
collector. This does not promise transactional cross-series capture while
telemetry handlers are concurrently updating aggregates.

`WOTEX_LAB_METRICS_HISTORY=1` requires `WOTEX_LAB_PROMEX=1` and explicitly adds
one `Observability.Sampler` writer and instance-bound `History` to the host's
one-for-all supervisor. Defaults are five seconds, 120 snapshots and 8 MiB;
`metrics_history_options` allows reviewed interval (1–60 seconds), snapshot,
byte and active-query budget overrides within their existing hard ceilings.
The next periodic tick follows completion, with no catch-up queue, and no
database/sink is faked for the local-only path. Source and history failures
consume attempt sequence numbers, are counted and are not stored as zeros.
Subsequent rows disclose gaps/reset identities; vanished series receive one-time
stale markers. All history is discarded if the optional cohort restarts.
The fixed `workbench` instance is host-wide, not a browser-tenant scope; no
route reads it. Its separately invoked local `Observability.Inspection` API
opens an owner-bound query capability, not browser-session access.
`metrics_history_test.exs` in the Workbench exercises real
PromEx capture, receipt loss, reset, stale/gap semantics, periodic sampling,
eviction, startup refusal and lifecycle cleanup. Authenticated browser query/
presentation still requires its independent tenant-isolation acceptance.

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
The receiver test uses real Collector measurements with explicit distinct
fixture timestamps, so machine speed cannot turn two intended sampling
intervals into one millisecond. A separate direct-encoder/sink test proves the
pinned Greptime receiver accepts two same-label, same-timestamp writes while
retaining only the latest row, matching its documented
[deduplication model](https://docs.greptime.com/user-guide/concepts/data-model/).
That bypass test is not permission for the bridge to submit new colliding
captures. Successful-request counters are not a count of durable rows.

Retry only retryable transport/5xx failures with capped jitter/backoff and the
same snapshot identity; honor bounded 429 retry policy; do not retry invalid
4xx forever. Preserve per-series ordering and report ambiguous/partial writes.
No exactly-once or lossless claim follows from HTTP success. An operator may
supply an existing compliant collector instead of the bridge, but that path
has a separate integration test and is not a baseline requirement.
The bridge implements exactly this policy through `Wotex.Lab.Metrics.ReqSink`
or any host sink function, keeps the snapshot identity across retries and
reports ambiguous writes; the external-collector path is not implemented.

The Workbench local-durable profile sets
`WOTEX_LAB_GREPTIME_URL=http://127.0.0.1:<port>/v1/prometheus/write` alongside
`WOTEX_LAB_PROMEX=1`. It refuses other local hosts, paths, userinfo, queries and
fragments. The separate hosted profile additionally sets
`WOTEX_LAB_GREPTIME_PROFILE=hosted`, an exact HTTPS
`WOTEX_LAB_GREPTIME_AUDIENCE`, a Bearer token and, only for an explicitly
selected private CA, `WOTEX_LAB_GREPTIME_CA_CERTFILE`. It refuses HTTP,
unauthenticated use and mismatched origins. `Metrics.ReqSink` resolves every
hosted exchange, refuses empty, private, link-local, metadata, multicast and
mixed public/private answer sets, pins one admitted peer and retains the
original hostname for HTTP authority, SNI and certificate verification. A
shared Finch is forbidden for this profile because it would bypass per-write
pinning. Both profiles fix the five-second sampling/deadline, 16-item queue and
4 KiB response ceiling. Only the fixed token environment reference enters
supervision and each disposable export worker resolves and validates the
URL-safe Bearer value just in time. The token is not retained in application or
bridge state. When volatile history is also active, the exporter is its sole
writer; the standalone sampler does not duplicate captures. The optional
cohort shares one-for-all shutdown with PromEx and the relay. Tests cover exact
endpoint/audience admission, local TLS hostname verification, private and mixed
DNS refusal, secret absence, missing/invalid credential resolution, explicit
activation, single-writer composition and lifecycle cleanup. This is source
proof for admitted exporter transports, not proof of a running remote receiver
or a durable row.

GreptimeDB query credentials and export credentials have separate scopes. The
Lab gateway allows only read templates for inspection, with no arbitrary SQL,
DDL, file functions, cross-database reads or user-selected endpoints. Database
provisioning and TTL changes are operator actions. Standalone defaults that
disable authentication MUST NOT be exposed remotely. Bind private listeners,
verify TLS/hostname, restrict egress and redact credentials before diagnostics.
Default durable metric TTL is seven days; a profile may explicitly override it.
Run evidence is stored separately and does not disappear with metric TTL.
Export credentials are resolved just in time from a host reference and
redacted from stats and errors. The base library's fixed durable read templates
and the Workbench's durable reader are described with the query contract
below. Hosted exporter, reader and provisioning TLS and egress policy and the
mutual-TLS operator listener transport are implemented.

`Wotex.Lab.Metrics.Retention` implements local TTL provisioning without
transport. `plan/1` admits a lowercase database identifier other than
`public`, `information_schema` and `greptime_private`, and a TTL of whole hours
or days from `1h` to `3650d`, defaulting to `7d`. `provision/2` sends only
`CREATE DATABASE IF NOT EXISTS <db> WITH (ttl = '<ttl>')`, then
`ALTER DATABASE <db> SET 'ttl' = '<ttl>'`, then a fixed
`information_schema.schemata` read through a host executor. It converts the
normalized TTL that GreptimeDB reports, such as `2months 29days 2h 52m 48s`,
to seconds and returns `retention_not_applied` unless they equal the plan. A
refused statement, unavailable receiver or unreadable option is
`retention_refused`, `retention_unavailable` or `retention_unverified`, without
the receiver's error text. The Workbench's
`Observability.Provisioning.provision/2` is the explicit operator call for an
exact `http://127.0.0.1:<port>` receiver: it posts the generated statements to
`/v1/sql` with five-second deadlines, no redirect or retry and a 64 KiB
response ceiling. `WOTEX_LAB_GREPTIME_DATABASE` separately makes the exporter
send `x-greptime-db-name` with each write; without it writes stay in `public`,
whose retention the Lab does not provision.

GreptimeDB 1.1.4 enforces TTL per stored file, not per query. A flushed file
whose newest row is older than the TTL disappears, and raising the TTL later
does not restore it. Rows still in memory, or sharing a file with newer rows,
remain queryable until a later flush or compaction. Retention therefore bounds
stored history; consumers must not treat it as a query-time age filter.
`metrics_retention_test.exs` covers plan bounds, fixed templates, TTL text
conversion, refusal, unavailable, unverified and drift cases. In the
`WOTEX_LAB_GREPTIME=1` lane, `greptime_bridge_test.exs` provisions a one-hour
database on the pinned server, writes a two-hour-old capture through
`ReqSink`, shows it before the flush and absent after flushing the metric
engine's physical table, keeps a current capture, re-provisions three hours
without restoring the expired row and observes a real refused statement.
The Workbench's `metrics_provisioning_test.exs` covers receiver admission, the
exact statements, refused, malformed, oversized and unreachable answers, and
the exporter's database header.

`Observability.Provisioning.provision_hosted/2` is the same explicit operator
call for a hosted receiver. It admits an exact HTTPS origin without path,
query, fragment or userinfo, the plan's `:database` and `:ttl` and an optional
`:tls_ca_certfile`, and sends the same generated statements to
`/v1/sql?db=public` through `Metrics.ReqSink`'s hosted destination policy with
that origin as audience. Every statement re-resolves the host, refuses
private, link-local, metadata, multicast and mixed answers, pins one public
peer and verifies the original hostname through TLS, with five-second
deadlines and a 64 KiB response ceiling. The Bearer credential comes from
`WOTEX_LAB_GREPTIME_ADMIN_TOKEN` for every statement and is never stored. It
must be a 43–128 character URL-safe token that differs from the export,
durable query, OTLP and both operator listener credentials, so no running
exporter or reader holds DDL authority; otherwise the call returns
`credential_unavailable` before any connection. The tests cover origin and
option admission, credential format and separation, and refusal of an origin
that resolves to loopback as `retention_unavailable` before any connection.
Provisioning a public hosted receiver is not exercised, and the call does not
prove that such a receiver enforces the TTL it reports.

Logs/traces use optional OTLP/HTTP-protobuf export to GreptimeDB's documented
signal endpoints, not a claim that PromEx exports them. Validate signal-specific
pipeline headers, temporality, partial-success replies and retention against
the pinned server. No mandatory collector or tracing of raw sensor payloads.
`Wotex.Lab.Otlp.Exporter` implements that optional export for Lab telemetry.
A host starts it explicitly with a sink; while alive it attaches one handler to
the closing `:stop` and `:exception` events of every catalogued component and
operation and detaches it on stop. `Wotex.Lab.Otlp.Events` turns each event
into one internal span named `component.operation`, with random trace and span
identifiers and no parent, and each exception into one ERROR log record with a
fixed body and event name. Attributes come only from the closed component,
operation, outcome class, profile and exception kind vocabularies; Thing
references, scenario identifiers, results and exception reasons never leave
the process. `Wotex.Lab.Otlp.Encoder` hand-encodes the opentelemetry-proto
v1.5.0 `ExportTraceServiceRequest` and `ExportLogsServiceRequest` fields it
needs, refuses records outside that shape and decodes `partial_success`.

The exporter keeps at most `max_buffer` records per signal (512, ceiling
4,096), counts drops in its buffers and in the emitting-process handler when
its mailbox is full, and exports at most `max_batch` records (256, ceiling
1,024) per request with one request in flight, a `deadline_ms` of 5,000 and
an `interval_ms` of 5,000. A 2xx answer with a valid `partial_success` counts
accepted and rejected records; any other status, malformed response, sink
error, crash or deadline counts the batch as failed. Failed batches are not
retried and nothing is persisted, so the export is lossy. There is no
temporality to validate because only traces and logs are exported.

`Wotex.Lab.Otlp.GreptimeSink` sends traces to `/v1/otlp/v1/traces` with
`x-greptime-pipeline-name: greptime_trace_v1`, which GreptimeDB 1.1.4 requires,
and logs to `/v1/otlp/v1/logs`; a selected database adds
`x-greptime-db-name`. It writes through `Metrics.ReqSink`, whose result now
also carries the response body cut at the sink's 4 KiB ceiling. Without a
`:credential` it sends none. A zero-arity `:credential` function is called for
every write; its `{:ok, credential}` answer becomes that exchange's
`authorization` header and is not retained, and any other answer fails the
write as `credential_unavailable` before a connection opens.
`otlp_encoder_test.exs` checks field numbers against an independent
decoder, closed-shape refusals, partial-success decoding and the projection
vocabulary. `otlp_exporter_test.exs` covers options, trace and log export
without payload metadata, partial success, rejected statuses, sink errors,
crashes, deadlines, buffer and batch bounds, handler detachment, periodic
export, the sink's headers and paths, the per-write Bearer header and the
refused credential. In the `WOTEX_LAB_GREPTIME=1` lane,
`greptime_otlp_test.exs` provisions a two-day database, exports OK, timeout and
exception spans and one log on the pinned server, reads them back from
`opentelemetry_traces` and `opentelemetry_logs`, finds the database TTL on
both tables and records a missing pipeline header as a rejected batch.

`WOTEX_LAB_OTLP_URL=http://127.0.0.1:<port>/v1/otlp` and an optional
`WOTEX_LAB_OTLP_DATABASE` activate the exporter in the Workbench through
`Observability.Otlp`, independently of PromEx, with service instance
`workbench` and the default budgets; an invalid value refuses startup. The
exporter observes Lab spans from every session on the host.
`WOTEX_LAB_OTLP_PROFILE=hosted` instead admits an exact HTTPS URL ending in
`/v1/otlp`, without query, fragment or userinfo, whose origin equals
`WOTEX_LAB_OTLP_AUDIENCE`, plus an optional `WOTEX_LAB_OTLP_CA_CERTFILE`.
Writes then use `Metrics.ReqSink`'s hosted destination policy: every
exchange re-resolves the host, refuses private, link-local, metadata,
multicast and mixed answers, pins one public peer and verifies the original
hostname through TLS. The Bearer credential comes from
`WOTEX_LAB_OTLP_TOKEN`, which boot checks and every write reads again without
storing it. It must be a 43–128 character URL-safe token that differs from
the durable query credential, the administrative provisioning credential and
both operator listener credentials, so an export credential never doubles as
a read or administrative credential; a missing, malformed
or reused credential fails the batch as `credential_unavailable`.
`metrics_otlp_test.exs` covers local and hosted receiver, audience and
database admission, the paths and headers of a real local export, credential
format and separation, token absence from exporter options, a hosted
receiver that resolves to loopback failing as `destination_not_admitted`
and a missing credential as `credential_unavailable`, both before any
connection, and the refused application start. Hosted export to a public
receiver is not exercised and is not proof that a receiver retained records.

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
or returns `unsupported_query`. `Metrics.Request` and `Metrics.Gateway`
admit local inspection callers of this descriptor; the trusted-local BeamLens
skill uses that gateway with tighter limits, and the MCP `query_metrics` tool
opens one gateway per call from a host-bound history and scope. The operator
HTTP query binding below opens one inspection scope per request, for local
history or the configured durable receiver. The WLB.07 `queryMetrics` control
operation opens one gateway per request over the bearer session's attributed
room history. The public tenant gateway has a separate credential, listener,
rate policy and durable-only scope described below.

`Wotex.Lab.Metrics.DurableQuery` answers the same admitted descriptor from a
PromQL-compatible durable receiver through fixed read templates and a host
executor. Every selector carries the scope's `instance` matcher and one exact
matcher per catalogue filter, so caller text never reaches PromQL. Gauges
support `last`, `sum`, `min` and `max`; counters `last`, `sum`, `increase` and
`rate`; histograms `increase` (over `_count`) and bucket-derived
`histogram_quantile`. Gauge `avg` is refused because PromQL cannot reproduce
the per-sample average of local history. Sample aggregations use a trailing
window equal to the whole-second step, so the receiver's lookback cannot fill a
missing step. Increases, rates and quantiles use the larger of the step and
three capture intervals and are the receiver's extrapolated values, not the
exact per-step deltas of local history. Steps must be whole seconds and
`start_at` a whole multiple of the step in Unix time. On GreptimeDB 1.1.4 an
unaligned grid whose window equals the step can omit a value although a stored
sample lies inside that window, so such descriptors are refused as
`unsupported_query`. A multi-series `last` answer is
ambiguous. `NaN` and infinite values are omitted and marked, and point and
output limits apply to the admitted answer. Receiver error text is never
returned, and each response carries the query and template digests. The module
performs no network access; database, credentials, endpoint and body bounds
belong to the host executor. `metrics_durable_query_test.exs` covers every
template, window rule, refusal, answer shape and limit. With
`WOTEX_LAB_GREPTIME=1`, `greptime_durable_query_test.exs` writes seven
captures, with one deliberately absent, to the pinned server. Durable `last`
and `sum` answers then equal local history for the same captures, including
the gap. Increases are non-negative and positive where calls occurred, p95
values stay within the observed bucket, and another instance scope reads
nothing.

`Metrics.Gateway` accepts a `:durable` executor instead of a `:history` PID,
with an optional `:capture_interval_ms` of 1,000 to 60,000 (5,000 by
default). The same owner binding, call budget, worker limit, deadline,
cancellation, expiry and owner-death rules apply; the executor runs inside
the query worker and stops with it. A binding with both sources, neither
source or an interval for a history source is refused. The Workbench's
`Observability.DurableReader` is that executor for a local receiver.
`WOTEX_LAB_GREPTIME_QUERY_URL` admits only an exact
`http://127.0.0.1:<port>` base URL, and the database is the exporter's
`WOTEX_LAB_GREPTIME_DATABASE`, or `public` without it. The executor accepts
only the four-parameter range template and posts it as a form body to
`/v1/prometheus/api/v1/query_range?db=<database>`; on GreptimeDB 1.1.4 that
query parameter overrides the `x-greptime-db-name` header and a `db` form
field is ignored. It has a one-second connect deadline, a two-second receive
deadline, no redirect or retry and a one MiB response ceiling; the local
profile sends no credential.
Status 200, 400 and 422 bodies are decoded for the template to admit or
refuse; any other status, an oversized or undecodable body or a transport
failure makes the store unavailable. That server answers a query against a
missing database with an empty success, so an empty answer from a selected
database is followed by the fixed read
`SELECT schema_name FROM information_schema.schemata WHERE schema_name = '<database>'`
and a missing database is reported as unavailable, not as no data.

`WOTEX_LAB_GREPTIME_QUERY_PROFILE=hosted` instead admits an exact HTTPS
origin, without path, query, fragment or userinfo, and an optional
`WOTEX_LAB_GREPTIME_QUERY_CA_CERTFILE`. Hosted exchanges go through
`Metrics.ReqSink`'s hosted destination policy with that origin as audience:
each exchange re-resolves the host, refuses private, link-local, metadata,
multicast and mixed answers, pins one public peer and verifies the original
hostname through TLS. The Bearer credential comes from
`WOTEX_LAB_GREPTIME_QUERY_TOKEN`, which boot checks and each executor call
reads again without storing it. It must be a 43–128 character URL-safe token
that differs from the metric and OTLP export credentials, the administrative
provisioning credential and both operator listener credentials, so query,
export and administrative credentials keep separate scopes; a missing,
malformed or reused credential makes the store unavailable. The response is
cut at the same one MiB ceiling, so an oversized hosted answer fails JSON
decoding and is also unavailable.
`metrics_durable_reader_test.exs` covers local and hosted receiver and
database admission, the exact request, refused, oversized, malformed and
unreachable answers, the database check, credential format and separation,
refusal of a hosted origin that resolves to loopback before any connection,
the listener binding and activation. Hosted success against a public receiver
is not exercised. With
`WOTEX_LAB_GREPTIME=1`, the Workbench's `greptime_durable_read_test.exs`
provisions a database on the pinned server and runs the host supervisor
with volatile history, the exporter writing to that database and the
durable reader. After three thermal runs and captures, `sum` answers for
three catalogue metrics through `/durable/query` equal the `/query` answers
from local history. An unaligned start gets 422, a reader bound to `public`
or to another instance reads nothing and a missing database is unavailable.

History query admission binds the store's explicit `:instance` identifier
and snapshot `:instance_slot` (default 0). Migration: hosts using `query/2`
must configure `instance: "their-host-id"` when starting history and construct
the descriptor's session scope from authenticated server context. Stores
without that identifier remain storage-only and return `scope_unbound`; a
different instance or snapshot slot returns `scope_denied`. An identifier is
not an authorization credential and shared-BEAM processes remain trusted.
The operator and public tenant listeners supply distinct transport boundaries.
The local expiring capability below is not a substitute for either.

`Wotex.Lab.Metrics.Request.decode/3` admits only eight string-keyed fields:
schema version, catalogue metric, aggregation, finite filters, UTC endpoints,
step and optional quantile. Scope, limits, endpoint, SQL and callback fields are
refused, not silently discarded. It looks up existing finite enum values without
creating atoms. Network frontends must bound encoded input before JSON decoding;
this decoder bounds the resulting field structure, not an arbitrary HTTP body.

`Wotex.Lab.Metrics.Gateway` is one temporary in-VM capability, explicitly bound
by a trusted host to an owner PID, instance/session scope and exact live history
PID. A copied PID cannot authorize another caller. Defaults are a 30-second
lifetime, 12 admitted calls and at most two query workers. Lifetime is capped
at 60 seconds and calls at 128; query budgets can only tighten the `Query`
defaults. The supplied request cannot change these choices. `query/2` returns
a correlation reference; live completion/cancellation sends one terminal result
message per admitted call. Consumers must monitor the gateway, since abrupt
process/VM death can prevent delivery and means unavailable. Missing data and
typed failures remain distinct, and successful responses
retain the source, interval, units, loss/freshness markers and query digest.

There is no accepted-work queue. The deadline includes submission/admission
and blocked history calls, is enforced by the owning gateway and is checked
again before result delivery. Cancellation, expiry, owner/history death and
shutdown stop linked query workers; cancelled/failed calls do not regain their
budget. History refuses late acquisition messages from already-dead local
callers, avoiding a transient lease after cancelled work resumes. A restarted
history cannot inherit an old capability. OTP scheduling is not hard real time
or OS containment; arbitrary same-BEAM callers are trusted, and transport hosts
must separately bound ingress and simultaneous scopes. Already delivered inert
messages cannot be recalled: frontends must ignore results for closed scopes.

With history explicitly enabled, Workbench starts an idle
`Observability.Inspection` broker. `open/1` is an explicit local-operator call:
the broker binds `workbench`, generates the session ID, admits one capability
per calling process and caps the whole host at 32 live scopes. Neither owner,
scope, history nor an endpoint is an operator request option. Opening performs
no query or LLM call. No browser route, LiveView event or MCP tool exposes this
host-wide history, and neither a browser token nor the scrape credential grants
access. With durable reads also configured, the broker starts even without
history, and `open/1` takes `source: :durable` to bind the durable reader
instead; an unconfigured source is `inspection_source_unavailable`. The
browser's saved panels query only the session room's attributed history
described in WLB.11. Public tenant queries and investigations use the separate
durable-only gateway below.

### Operator HTTP query binding

`WotexLabWorkbench.Observability.QueryListener` is the only HTTP route to that
history. It starts only when the operator sets `WOTEX_LAB_METRICS_QUERY_PORT`
and `WOTEX_LAB_METRICS_QUERY_TOKEN` with local history or durable reads active,
and startup is refused when both are off or when the query credential equals
the scrape credential. The listener binds IPv4 loopback, keeps only the
credential's SHA-256, admits eight connections with one HTTP/1 request each and
serves only `POST /query` for local history and `POST /durable/query` for the
durable reader. A request carries `Authorization: Bearer`, one
`Content-Type: application/json`, one `Content-Length` from 1 to 8,192 bytes
and no query string, `Origin`, `Expect` or `Transfer-Encoding`. The body is
the closed `Metrics.Request` field set; scope and limits in the body are
refused as `invalid_request`.

Each request process opens one `Inspection` scope with a three-second lifetime,
one call and reduced limits: six-hour range, 5-second minimum step, 2,000
points, 256 KiB output, a two-second deadline and one worker. It waits at most
2.25 seconds for the terminal result, cancels late work and revokes the scope
before answering. A 200 answer is the query result as JSON of at most one MiB.
Refusals are JSON `code`, `phase` and `message` objects: 400 for framing, body
and descriptor errors, 401 for a missing or wrong credential (including the
scrape credential), 403 for a non-loopback peer, 404 and 405 for other paths
and methods, 409 for `clock_rollback`, 413 for a declared body above 8,192
bytes, 415 for another media type, 422 for `unsupported_query`,
`query_too_large` or `output_too_large`, 429 when inspection scopes are
exhausted, 502 when the durable receiver refuses the template or answers
outside it, 503 when the selected source is unavailable or not activated and
504 at the deadline.
`metrics_query_listener_test.exs` covers configuration, activation
dependencies, credential separation, framing refusals, server-bound scope,
unsupported and invalid descriptors, scope capacity, unavailable history, the
deadline with a blocked history and a real loopback socket. The listener also
accepts the mutual-TLS remote transport described with the scrape listener.
Neither transport is a tenant endpoint; session-scoped HTTP reads use the
WLB.07 `queryMetrics` control operation instead.

### Public tenant gateway

`Observability.HostedListener` is a separate HTTPS listener activated by
`WOTEX_LAB_HOSTED_PORT`. Startup also requires an IP-literal bind, certificate
and key files, a configured durable reader, an explicit investigation provider,
the tenant registry and the three verified worker artifacts described below.
The listener serves TLS 1.3 with no session tickets, HTTP/2, WebSockets,
compression or keepalive. It admits 64 connections and one HTTP/1 request per
connection. Query bodies are at most 8 KiB; investigation bodies are at most
16 KiB. Requests require one Bearer header, `application/json`, one positive
`Content-Length`, no query string, cookie, `Origin`, `Expect` or
`Transfer-Encoding`, and at most 16 headers. Responses are non-cacheable and
carry no cookie.

`Observability.HostedAccess` loads one absolute, regular, stable file of at most
64 KiB using schema `wotex-lab-hosted-tenants/v1`. The document contains 1–64
exact entries with `id`, `instance` and `token_sha256`; ids, instances and
digests are each unique. Tokens are 43–128 URL-safe characters, but only their
full SHA-256 digests enter the file or process state. The file must have no
group or other permissions. A tenant digest must not match the configured
scrape, operator-query, Greptime write/query/admin or OTLP credential.
Authentication uses constant-time digest comparison and returns an owner-bound
lease. Owner death and the request's `after` block release active capacity,
including malformed and interrupted bodies after authentication.

`POST /v1/query` binds the authenticated entry's durable executor and instance
to a fresh `Metrics.Gateway`. The body is only the closed request descriptor;
scope, endpoint, receiver, database, credential and limits cannot be supplied.
Each query has one call, one worker, a six-hour range, 5-second minimum step,
2,000-point and 256 KiB output ceilings, and a two-second deadline. A tenant may
run two queries concurrently and admit 60 per monotonic one-minute window.
There is no public path to ETS history.

`POST /v1/investigations` accepts only `prompt`, `current` and `baseline`.
Prompts are non-blank UTF-8 binaries of at most 4 KiB; the two optional JSON
maps share an 8 KiB ceiling. A tenant may run one investigation and admit four
per monotonic hour. The host admits eight workers in total and queues none.
Each active request owns two random 256-bit loopback capabilities, one for the
selected provider and one for the server-bound query bridge. Each capability
expires with the request and admits at most eight calls. The worker receives no
tenant credential, durable-receiver credential, provider credential, database
or endpoint choice.

`Investigation.HostedCommand` verifies the full SHA-256 and stable file identity
of the native custodian, Escript runtime and worker archive for every request.
It creates a mode-0700 private directory, writes one mode-0600 request, removes
the caller environment except the private home/temp path and fixed locale, and
invokes the native custodian. A random result capability binds the worker's
final frame, so dependency diagnostics on standard output cannot impersonate a
result. Request files and private directories are removed on every terminal
path.

The Rust custodian creates a new session and process group. It enforces a
30-second wall ceiling, a CPU limit derived from that ceiling, 1 GiB aggregate
sampled RSS, 64 live descendants, 256 file descriptors and 256 KiB of captured
output. Output is drained through a bounded in-memory reader; the output limit
does not prevent the verified worker from extracting its embedded BAML NIF and
skill resources into the private directory. Timeout, output, memory, process,
signal and parent-loss outcomes remain distinct. The custodian kills the process
group and every observed escaped descendant before returning `cleanup=ok`.

`mix wotex.lab.hosted.build --workspace ABSOLUTE_NEW_DIRECTORY --runtime
ABSOLUTE_ESCRIPT` builds the custodian offline and the target-specific Escript,
then atomically installs the two executables with `native-build.json`. Clean
private Mix and Rebar builds, a private Cargo target and a checksum-verified
private NIF cache prevent repository build state and ambient compiler flags
from entering the result. The Escript archive retains only the hosted worker,
its five Lab metric contract modules and its admitted runtime dependencies;
archive paths, counts, sizes, timestamps and ownership fields are checked and
normalized.
`mix wotex.lab.hosted.check` re-verifies those files and runs the one-request VM
with unavailable loopback bridges; a successful check returns an admitted
provider-unavailable result after complete cleanup. The
`hosted-investigation` native-artifact descriptor supplies the root planner and
identity contract through the `hosted-linux-x86-64`, `hosted-linux-aarch64` and
`hosted-darwin-aarch64` targets. These targets bind the repository's exact
Erlang, Elixir and Rust pins. Artifact construction does not publish or adopt
it.

`hosted_access_test.exs`, `hosted_listener_test.exs` and
`hosted_investigation_test.exs` cover strict tenant documents, credential
separation, rate and concurrency limits, owner death, framing, real TLS,
cross-tenant scope substitution, capability exhaustion, the target-native
builder and a complete external-worker/provider-bridge round trip. The Rust
tests cover configuration, private files larger than the output ceiling,
output overflow, timeout and descendant cleanup. These are local source and
target-native results, not evidence of a deployed public receiver or another
target architecture.

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
ETS/process inspection and automatic anomaly investigations are disabled. The
trusted-local profile runs in the Workbench VM and binds its verified browser
session and room to `Investigation.Broker`. Public tenant investigations never
share that tree. Each starts a new external VM containing only the hosted skill,
its request context and the dependency's required processes, then terminates
the whole process tree. This is isolation from parent-BEAM globals and state;
it is not a sandbox for unreviewed executable code.

The 0.3.1 source review found unconditional log-store startup in the standard
supervisor, inherited node-information callbacks and queued operator invocations
whose caller timeout does not revoke the run. See the
[dependency review](../provenance/standards-and-dependencies.md#beamlens-integration-admission).
The Workbench pins BeamLens 0.3.1 and does not use its default supervisor. Its
host composition sets the custom skill and eight-iteration limit in the actual
coordinator/operator process state, admits no queue, and replaces both static
agents after every completion, failure, cancellation, timeout or owner death.
The unavoidable upstream log store still starts, and the upstream operator
still merges `get_current_time` and `get_node_info` with the four custom
callbacks. In the trusted-local profile those callbacks disclose the Workbench
node, OS and uptime. In the public profile they describe the disposable worker;
its new log store contains no parent-host logs and dies with the request. No
built-in skill, anomaly process, tracer, exception store or VM-event store
starts. No provider or key lookup occurs at boot.

The custom skill exposes bounded `lab_metric_catalogue`, `lab_metric_query`,
`lab_run_summary` and `lab_compare_runs` callbacks. Their service-side request
scope expires with the investigation. A model-supplied instance ID, Lua global,
prompt or prior conversation cannot substitute for that scope. No shell,
arbitrary Elixir, raw SQL, raw credentials, external URL or Action callback is
provided by the custom skill. Each metric call creates a server-bound one-call
gateway with a 2.5-second TTL, five-minute range, 61-point, 2 KiB and 1.5-second
query ceilings, then revokes it. Current/baseline summaries are supplied by the
trusted server, canonicalized as JSON, content-addressed and limited to 8 KiB
combined; the model can select only `current` or `baseline`. A 16 KiB cumulative
callback-output budget makes repeated calls fail closed. Dependency base
callbacks and node metadata remain outside the custom callback claim; their
trusted-local and disposable-worker disclosures are stated above.

The prompt entry point is on-demand. The implemented trusted-local budget is
one investigation for the entire host, 30 seconds, 8 model turns/tool actions,
8 provider bridge calls and 32 KiB admitted context;
provider token/cost limits must also be explicit. Cancellation and timeout
terminate the investigation and revoke its query scope, not merely detach the
UI caller. Local providers are supported; cloud model use requires explicit
provider selection and disclosure of exactly which redacted data leaves the
host. No automatic API-key discovery, model download or endless agent loop.
`Investigation.Disclosure` derives that statement from configuration alone,
and the browser composer shows it before a question is submitted. With
`codex_then_ollama`, data leaves the host: Codex through the signed-in
ChatGPT-plan account is attempted first, then the configured Ollama endpoint.
With `ollama`, data stays on the host only when the configured base URL is plain
HTTP on a loopback host. Any other endpoint is disclosed as leaving it. Either
provider can receive the question (4 KiB), the fixed skill and operator
instructions with catalogue metadata, the closed current and baseline run
summaries (8 KiB), read-only callback results (16 KiB) and the node name,
operating system, uptime and current time that BeamLens 0.3.1 adds.
Credentials, session and room tokens, dataset rows, Thing Description documents
and other sessions' data are not part of that content.

The browser binds its revalidated live room and LiveView owner to the broker.
There is one investigation for the entire trusted host, no queue, a 4 KiB
prompt, 8 KiB run context, 16 KiB cumulative callback output, 30 seconds,
eight turns/tool actions and eight provider calls. It returns an owner-only
reference. A different process cannot cancel it. Owner or room death, session
revocation/expiry, explicit cancel and timeout brutally stop the worker, clear
context and replace both BeamLens agents. `WOTEX_LAB_BEAMLENS`
must equal `trusted-local`, PromEx and local history must also be enabled, and
`WOTEX_LAB_BEAMLENS_PROVIDER` must explicitly equal `ollama` or
`codex_then_ollama`. The bridge is plain HTTP only on an exact loopback host.
Its boot-random 256-bit Bearer capability is shared only by the private BeamLens
client registry and broker, and is admitted only while the broker owns an active request;
each admission consumes that request's eight-call budget. Missing, replayed
outside the active scope and over-budget capabilities are refused. The bridge
also rejects streaming/non-loopback/oversized messages and is inert when disabled.

The provider boundary is explicit. A Codex App Server call must use an already
signed-in ChatGPT-plan account,
refuse API-key accounts and unavailable quota, create an ephemeral thread in a
private empty directory, disable tools/search/connectors/inherited MCP servers,
use read-only/no-network/no-approval policies, and close its owned stdio port.
The fallback is exactly `qwen3.5:4b-q4_K_M` at the configured loopback Ollama
OpenAI-compatible endpoint, non-streaming, reasoning disabled and capped at
320 output tokens. It never pulls a model. The 29-second provider deadline
allocates at most half the remaining time to Codex and gives the balance to
Ollama when `codex_then_ollama` was explicitly selected. `ollama` never attempts
Codex. The provider status and fallback reason are explicit result metadata
and a PubSub transition; fallback is never silent. Disposable deadline workers
are killed on timeout and owner death. Tests exercise the real BeamLens process
tree and metric gateway plus fake provider/agent workers; no live model turn is
part of default acceptance.

Answers show observed facts separately from hypotheses, source queries/time
ranges and missing evidence. Queried labels/logs, tool results and prompts are
untrusted data, not instructions. Render escaped text, never executable HTML.
No-data, stale data, denied scope, provider failure and cancellation have
distinct UI states. Generated advice cannot authorize or invoke an Action.
The implemented Workbench selects the current run and only the nearest older
run of the same experiment, reduces both to a closed JSON summary, and renders
one terminal live-region update. It accepts no model-supplied link: snapshot
identifiers and the bounded session report resolve only to `/evidence`.

`Investigation.ContextStore` records the evidence digests an investigation
actually receives: the admitted current and baseline summary digests and each
digest in a callback result that fits the output budget, at most 64. The broker
attaches that record to a completed result before clearing the context, so
it cannot pass to a later investigation. `Investigation.Answer` shows a finding
only when its context, observation or hypothesis cites at least one digest and
every cited digest is in that record. Findings that cite nothing, or cite a
digest no callback returned, are withheld and counted under missing evidence.
If none remain, the answer is `unsupported`. Cited digests appear as unlinked
sources. Grounding checks that a finding names received evidence, not that
its prose interprets that evidence correctly.

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
`Metrics.History.freeze/2` serializes capture with history writes and returns
the exact storage sequence/count/byte/time watermark used by the query.
`Metrics.Dataset.freeze/3` binds that capture to an explicit experiment and
creates a deterministic content identity over the query, interval, watermark,
unit, ordered rows, loss and transform provenance. Every query step has a
numeric-or-null value, observed/missing mask and quality markers. Export is
always `unsplit`; it performs no normalization or additional downsampling, and
does not automatically start an experiment or convert rows to tensors. A later
split or normalization therefore requires a separately recorded provenance
step rather than silently rereading live history.

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
shutdown, two-instance isolation, immutable diagnostic export and the export
credential sentinel;
`test/wotex/lab/greptime_bridge_test.exs` covers actual ingestion, and the Workbench
`greptime_durable_read_test.exs` compares durable and local-history answers for
the same PromEx captures. The local
protected query endpoint and TTL expiry have their own tests described above.
`metrics_operator_transport_test.exs` covers the mutual-TLS scrape and query
listeners. `hosted_access_test.exs` and `hosted_listener_test.exs` cover the
digest-only registry, credential separation, quotas, owner cleanup, public
framing, server-bound durable scope and a real TLS 1.3 socket.
`hosted_investigation_test.exs` builds the target-native artifact and runs the
external VM through the real custodian and loopback provider bridge; its model
transport is fake and its BeamLens/BAML worker is real. The package artifact
test independently builds, qualifies and then corrupts an output to prove
digest refusal. Native tests force output overflow and timeout while checking
whole-tree cleanup. None of these tests claims another target architecture or a
deployed public receiver.

The Workbench `investigation_acceptance_test.exs` runs scripted
agents through the real broker, context store, skill callbacks and query
gateway. Its prompt corpus covers missing-mask spikes, warm-up versus inference
latency, SSE drops, MQTT duplicates and dataset split leakage with an injected
run note. Grounded findings are shown with escaped text and no Action seam.
Uncited, fabricated and mixed citations are withheld, and a digest from an
earlier investigation cannot ground a later one. Cancelling an agent blocked
in a metric query kills the worker, closes its inspection scope and leaves no
history lease. `investigation_disclosure_test.exs` covers cloud-first, loopback,
non-loopback, unconfigured and unselected providers, and the browser
investigation test finds the disclosure on the run page. Local capability
scope substitution, bounded admission, blocked calls, expiry, cancellation,
worker/owner/history death, history replacement and late-result rejection are
covered by `metrics_gateway_test.exs`. The Workbench's
`metrics_inspection_test.exs` adds actual PromEx-to-query integration, per-owner
and 32-scope host admission, startup, shutdown and restart boundaries. These are
local query lifecycle tests, not provider cancellation or HTTP/MCP evidence.
