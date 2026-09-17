# WoTEx Lab workbench

This is the non-umbrella Phoenix LiveView reference host owned by
[WLB.11](../../../../docs/packages/wotex-lab/specs/WLB.11-workbench-and-design-system.md). It consumes
the public Lab and profile-package APIs; the base `wotex_lab` library does not
depend on Phoenix.

The host exposes three bounded experiments, disposable session-owned Things,
scoped live metrics and downloadable evidence. Running an experiment never
approves a Thing Action. The smart-room experiment stops at a named, expiring
decision and dispatches only after the separate exact approval form passes the
policy and freshness checks again. Mounting or reconnecting starts no room or
experiment.

## Development

From this directory:

```sh
WOTEX_PATH_DEPS=1 mix setup
WOTEX_PATH_DEPS=1 mix phx.server
```

`WOTEX_PATH_DEPS=1` is the sole workspace switch. With it unset, dependencies
are resolved as versioned artifacts. Charts are rendered server-side as native
HEEx/SVG; the application neither downloads nor ships a browser chart runtime.

The local completion gate is:

```sh
WOTEX_PATH_DEPS=1 mix check --no-retry
```

The host uses a small native check runner because its accepted location is two
levels below another Mix project, a shape that ex_check interprets as a possible
umbrella child. `.check.exs` remains the declarative list of the same checks.
Node is needed only for the optional Playwright browser cohort, not by the
running Elixir host. The exact Decimal 3.1.1 parser regression and removal of
the now-unmatched advisory waiver are documented in the Lab's
[dependency review](../../../../docs/packages/wotex-lab/provenance/standards-and-dependencies.md) and
protected by the host's own locked-version and bounded-parser regression.

## Interactive charts and browser evidence

The host explicitly selects Explorer 0.12.0 and invokes the shared
`Wotex.Lab.Analytics` profile when “Apply analysis” is submitted. Series and
inclusive event-time filters, line/point/area selection and compatible-unit
comparisons are read-only: they cannot re-run an experiment or change its
evidence. Summaries distinguish observations, missing and nonfinite values;
tables show at most 100 rows and both source and query digests. Empty ranges
are not measured zeros. Reload does not replay the query. No `kino_explorer`
dependency, arbitrary SQL/expression or browser-selected instance is admitted.

The sole renderer is server-owned HEEx/SVG; it accepts no URL, expression,
signal or arbitrary Vega grammar. LiveView replaces the SVG after admitted
analysis changes. The accessible chart and maximum 100-row table support all
three admitted marks and preserve missing-value gaps. Pan/zoom is not an
implemented feature. Explorer remains the dynamic analysis engine, not the
renderer.

Tensor previews split the lazy batch before stacking and slice before copying
to host lists. Their observed/filled counts describe only the shown elements,
with row/feature/vector truncation disclosed. Min/max downsampling keeps gap
sentinels around retained extrema; it cannot draw a line across an omitted gap.
Its interval is input points per bucket, not an assumed event-time duration.

The optional browser gate requires an explicitly installed Playwright/browser
cohort and a disposable local server. It never downloads them. For example,
start the host with `PORT=4107 WOTEX_PATH_DEPS=1 mix phx.server`, then run:

```sh
node bin/check_chart_browser.cjs http://127.0.0.1:4107
```

Supply Playwright through your tool environment (for example `NODE_PATH`). The
script reports actual Node, Playwright and Chromium versions. The 2026-09-17
source cohort passed with Node 26.8.2, Playwright 1.63.0-alpha-2026-08-31 and
Chromium 153.0.8010.12. It covered saved dashboard and exact analysis/chart
links, keyboard disclosure/skip navigation, reflow, session isolation and
bounded downloads. It also covered keyboard-loaded history panels with mobile
reflow, reload without replay and session isolation. A later run of the same
cohort added a keyboard-submitted smart-room approval around LiveView socket
reconnects without replay, a cancelled run that stays undispatched, a Thing
Description title with image and script markup rendered as text, and the
disabled investigation composer without a provider, and then a fresh browser
context with its empty states, a keyboard-started room, a frozen dataset that
stays unchanged while live measurements grow, and the unavailable formal
engine. The first run of the
history checks found a 10-pixel horizontal overflow at 375 pixels, which the
host stylesheet now prevents. This is neither a stable-browser compatibility
matrix, WCAG certification nor installed-artifact evidence.

## Optional operator-owned metrics

`WOTEX_LAB_PROMEX=1 WOTEX_PATH_DEPS=1 mix phx.server` explicitly activates the
fixed host collector. It is off by default and describes the Workbench Lab
instance as a whole, not individual browser sessions. It starts no public
scrape listener, Grafana agent, database, LLM or built-in VM/LiveView inspection.
The 43 custom definitions come from the Lab catalogue. The selected public
PromEx storage adapter has a 256-scalar-series budget; histogram buckets, sum
and count each consume capacity. It aggregates synchronously without buffering
raw samples, preserves inclusive buckets/subsecond sums, and counts drops and
invalid source measurements. Backend labels default to `other`, not an inferred
or changed Nx backend. An attached operator IEx session can call
`PromEx.get_metrics(WotexLabWorkbench.Observability.PromEx)` without self-HTTP.

Add `WOTEX_LAB_METRICS_HISTORY=1` to explicitly activate local history alongside
PromEx. Enabling history without PromEx refuses startup. The sampler captures
every five seconds into 120 snapshots / 8 MiB of volatile ETS, with one writer
and no catch-up queue. It starts no database and uses no fake successful sink.
Reviewed host configuration can set `metrics_history_options` (`interval_ms`,
`max_snapshots`, `max_bytes`, `max_queries`) within the documented hard bounds.
An operator can inspect `WotexLabWorkbench.Observability.Sampler.stats()` and
`Wotex.Lab.Metrics.History.stats(WotexLabWorkbench.Observability.Supervisor.History)`.

The public capture API pairs PromEx text with the custom adapter's body-hash
receipt, preserving reset identity, clocks and loss counters. Changed or
unavailable receipts fail the sample; the sampler counts failures and subsequent
gaps, preserves one-time stale markers and exposes evictions through history.
Its fixed instance is `workbench`, not the current browser session. No browser
route reads this host-wide history; only the separately activated loopback
query listener described below does. Remote query authentication and tenant
isolation remain separate work. Restarting the optional supervisor discards its history;
neither sampling nor dataframe conversion makes it durable or training data.

Set `WOTEX_LAB_GREPTIME_URL` to the exact local endpoint
`http://127.0.0.1:<port>/v1/prometheus/write` together with
`WOTEX_LAB_PROMEX=1` to activate the bounded remote-write exporter. Other hosts,
paths, URL credentials, queries and fragments are refused; remote/TLS export is
not silently treated as this local profile. If `WOTEX_LAB_GREPTIME_TOKEN` is
present, it must be a 43–128 character URL-safe Bearer token and is resolved
from that fixed environment reference inside each export worker rather than
stored in application state. Adding `WOTEX_LAB_METRICS_HISTORY=1` writes the
same captures to volatile ETS and GreptimeDB through the exporter; the periodic
standalone sampler is then omitted so captures are not duplicated.

Retention is provisioned explicitly. From an attached operator session, run
`WotexLabWorkbench.Observability.Provisioning.provision("http://127.0.0.1:<port>", database: "wotex_lab")`
to create the database with the seven-day default TTL, or pass `ttl: "30d"`
(whole hours or days from `1h` to `3650d`). The call verifies the TTL that the
receiver reports and repeats safely to change it. Then set
`WOTEX_LAB_GREPTIME_DATABASE=wotex_lab` so each write carries
`x-greptime-db-name`; without it writes go to `public`, which the Lab does not
provision. GreptimeDB removes expired data per flushed file, so recent unflushed
rows can outlive the TTL briefly. Durable-row verification remains operator
work.

For a hosted receiver, set `WOTEX_LAB_GREPTIME_ADMIN_TOKEN` in the attached
operator session and call
`WotexLabWorkbench.Observability.Provisioning.provision_hosted("https://metrics.example", database: "wotex_lab", ttl: "30d")`,
adding `tls_ca_certfile:` for a private CA. The administrative token follows
the 43–128 character URL-safe rule and must differ from every export, query,
OTLP and listener token; the call refuses it otherwise. It uses the same
hosted DNS, pinning and TLS checks as hosted export.

For an operator-provisioned remote receiver, explicitly select the separate
hosted profile:

```console
WOTEX_LAB_PROMEX=1 \
WOTEX_LAB_GREPTIME_PROFILE=hosted \
WOTEX_LAB_GREPTIME_URL=https://metrics.example/v1/prometheus/write \
WOTEX_LAB_GREPTIME_AUDIENCE=https://metrics.example \
WOTEX_LAB_GREPTIME_TOKEN=<43-128-character-url-safe-token> \
mix phx.server
```

`WOTEX_LAB_GREPTIME_CA_CERTFILE` may name an explicitly provisioned private CA;
otherwise the system trust store is used. Hosted export requires HTTPS, an
exact audience origin and Bearer authentication. Each write re-resolves the
host, refuses private/link-local/metadata/multicast or mixed DNS answers, pins
one public peer, and verifies the original hostname through TLS. It follows no
redirect and performs no implicit client retry. This is an egress transport
profile, not evidence that a remote receiver retained the row; remote scrape
ingress and deployment verification remain separate.

An operator attached to this same VM can explicitly open a short-lived query
scope. This requires the history activation above; it never enables it:

```elixir
alias WotexLabWorkbench.Observability.Inspection
alias Wotex.Lab.Metrics.Gateway

{:ok, access} = Inspection.open()
monitor = Process.monitor(access)
now = DateTime.utc_now()
{:ok, reference} = Gateway.query(access, %{
  "schema_version" => "1.0.0",
  "metric" => "nx_operations_total",
  "aggregation" => "sum",
  "start_at" => DateTime.to_iso8601(DateTime.add(now, -60, :second)),
  "end_at" => DateTime.to_iso8601(now),
  "step_ms" => 5_000
})
receive do
  {:metric_query, ^access, ^reference, result} -> result
  {:DOWN, ^monitor, :process, ^access, _reason} -> {:error, :inspection_unavailable}
after
  3_000 -> Gateway.cancel(access, reference)
end
:ok = Gateway.revoke(access)
Process.demonitor(monitor, [:flush])
```

The owner is the calling process, not a supplied identifier. The broker admits
one scope per process and 32 for the host, binds the exact history PID and
generates its session identity. A scope defaults to 30 seconds, 12 calls and
two in-flight queries; `open/1` accepts only `ttl_ms` (1–60,000), `max_calls`
(1–128) and `query_limits` that tighten the Lab defaults. The two-second query
deadline includes blocked history calls. Cancellation, expiry, owner/history
death and host shutdown stop pending workers; failures consume admitted-call
budget. Already delivered results are inert and must be ignored after closure.
Monitor the gateway: abrupt process/VM death can prevent a terminal reply and
must be reported as unavailable, not a completed query or cancellation.
There is no result-retention service or queued-query backlog.

Request fields cannot select scope, credentials, limits, endpoints, SQL or
modules. Copied gateway PIDs do not authorize a different process. This local
operator API is not exposed by a browser event, HTTP route or MCP tool, and
does not imply hostile shared-VM isolation.

The BeamLens profile is trusted-local only and requires all four explicit
settings:

```console
WOTEX_LAB_PROMEX=1 \
WOTEX_LAB_METRICS_HISTORY=1 \
WOTEX_LAB_BEAMLENS=trusted-local \
WOTEX_LAB_BEAMLENS_PROVIDER=codex_then_ollama \
mix phx.server
```

Use `WOTEX_LAB_BEAMLENS_PROVIDER=ollama` to prohibit Codex entirely. The first
mode uses an existing signed-in ChatGPT-plan Codex session and visibly falls
back to the fixed local model `qwen3.5:4b-q4_K_M`; it never accepts Codex
API-key auth or downloads a model. Codex runs one ephemeral read-only/no-network
turn in an empty private directory with tools, search, connectors and inherited
MCP/plugin entries disabled. The internal BAML bridge accepts only bounded,
non-streaming loopback requests carrying its boot-random capability while the
broker owns an active investigation. The capability is call-bounded and
inactive between requests; the bridge is unavailable when the profile is off.

`WotexLabWorkbench.Investigation.Broker.ask/2` is the trusted-local prompt entry
point used by the run and evidence LiveViews. It admits one host-wide
investigation with no queue, binds browser work to the live session room,
returns an owner-only reference, and sends
`{:investigation, reference, result}`. Its 30-second/eight-turn lifecycle clears
run context and replaces the BeamLens agents after every terminal state.
Session expiry/revocation terminates the room-bound worker. The four custom
callbacks cannot issue Actions or select scope/endpoints. BeamLens
0.3.1 nevertheless adds node/OS/uptime callbacks and starts its log store; that
explicit disclosure is why this profile is not admitted for shared hosted
tenants.

Before a question is submitted, the composer states whether investigation data
leaves this host. With `codex_then_ollama` it does: Codex is attempted first,
then the configured Ollama endpoint. With `ollama` it stays on the host only
for a loopback base URL. The composer lists the bounded content a request can
include, including the node name, operating system, uptime and current time
that BeamLens adds.

The browser revalidates the signed session and live room on every submit and
cancel, then supplies only the selected run and nearest older same-experiment
run through a closed summary. It renders one escaped terminal answer with
facts, hypotheses, missing evidence and provider/model status. Model-supplied
URLs are ignored; evidence links remain local, and the answer has no Action or
approval seam. A finding appears only when it cites `sha256:` digests that
this investigation received from its run summaries or callbacks. Other findings
are withheld and counted under missing evidence. When no finding remains, the
answer is marked unsupported.

The Metrics page's portable-panel selector exports only catalogue definitions
through `/metrics/dashboard.json`, with 1–16 known IDs. A verified browser
session is required; no room or collector starts. Importing the JSON and
choosing a Prometheus-compatible source are operator actions. The export
preserves label sets, uses five-minute counter rates and bucket-derived p95,
and never fills missing data with zero. Saved arrangements are session-only and
cannot activate either the collector or the separately configured durable
exporter.

Once a room exists, **Load history** charts the saved panels from that room's
own history. Each room owns a catalogue collector attributed to the room
process, the processes it started and the tasks it awaits. It also owns a
volatile history of at most 120 snapshots and 1 MiB. The room captures after
each run or approval and every five seconds, and discards both with the room.
Things' server processes, shared host processes and other sessions are not
included. Choose a 5-minute, 15-minute or 1-hour range. Counters show the
per-second rate inside each step, gauges the last value and histograms the
bucket-derived p95. Each panel shows at most eight label sets, states the total,
and lists its freshness, history markers and query digests. Empty steps are
gaps. Opening the page runs no query, and this history is separate from the
host-wide PromEx collector.

The separately selected Grafana lane checks import and query execution for one
pinned server cohort. It needs Docker and the digest-pinned Grafana 13.2.2 and
GreptimeDB 1.1.4 images, which it does not pull:

```sh
docker pull grafana/grafana:13.2.2@sha256:ac461fb352abc50da10a51c7d02462e9c05488f11f53f14b3ad79a8145f638a0
docker pull greptime/greptimedb:v1.1.4@sha256:9726587eac95d0360755254cd59a528dbf48abfdf268478aea6a644f62afe44c
WOTEX_LAB_GRAFANA=1 WOTEX_PATH_DEPS=1 mix test test/wotex_lab_workbench/grafana_import_test.exs
```

The test writes two real PromEx captures through the bridge. It imports the
downloaded JSON for all 43 panels, runs every stored target through Grafana
and removes its containers and network. It covers neither Grafana browser
rendering, other Grafana versions nor a Prometheus server.

### Protected local scrape

The optional scrape listener has its own port and serves only `GET /metrics`;
it does not replace the browser host's `/metrics` page. Set
`WOTEX_LAB_METRICS_PORT` explicitly (for example 9464) alongside
`WOTEX_LAB_PROMEX=1`, and supply `WOTEX_LAB_METRICS_TOKEN` through your process
manager's secret environment. Use a cryptographically random URL-safe token
of 43–128 characters (32 random bytes encoded as unpadded base64url is 43).
No credential is discovered or generated, and only its SHA-256 enters the
listener's options. Rotate it by restarting with a newly provisioned token.

Clients must send `Authorization: Bearer <token>`. Cookies, browser sessions,
query strings and forwarding headers grant no access. The address is fixed to
127.0.0.1; binding another address is not an option. HTTP/2, WebSockets, CORS,
compression and connection reuse are disabled. It admits eight connections,
16 headers of at most 2,048 bytes, a 1,024-byte request line, no request body
and at most one MiB of response text. Socket read/write inactivity timeouts
are two seconds; this is not an absolute slow-header deadline or an untrusted
remote-service claim. The same custom metric collector remains host-wide.

An unavailable collector returns 503, never empty success. Responses are
non-cacheable; protocol/exception logging is disabled on this listener to
avoid reflecting credential-bearing input. HTTP status remains observable to
the client. This local operator profile is not a TLS/remote deployment, and
must not be port-forwarded or exposed by a proxy as if it were one. Neither
the listener nor its credential starts a database, history, experiment or LLM.

### Protected local query

The optional query listener is a second loopback listener for the operator
history. Set `WOTEX_LAB_METRICS_QUERY_PORT` and `WOTEX_LAB_METRICS_QUERY_TOKEN`
together with `WOTEX_LAB_PROMEX=1` and `WOTEX_LAB_METRICS_HISTORY=1`. The query
token follows the scrape token rules and must differ from it; startup is
refused otherwise.

Send `POST /query` with `Authorization: Bearer <token>`,
`Content-Type: application/json` and a `Content-Length` of at most 8,192 bytes.
The body holds only `schema_version`, `metric`, `aggregation`, `filters`,
`quantile`, `start_at`, `end_at` and `step_ms`:

```sh
curl -sS -X POST http://127.0.0.1:9465/query \
  -H "Authorization: Bearer $WOTEX_LAB_METRICS_QUERY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"schema_version":"1.0.0","metric":"nx_operations_total","aggregation":"sum","start_at":"2026-01-01T00:00:00Z","end_at":"2026-01-01T00:05:00Z","step_ms":5000}'
```

The server chooses the instance and session scope. Each request gets one
short-lived inspection scope limited to a six-hour range, 2,000 points,
256 KiB of output and a two-second deadline. Refusals are JSON objects with a
stable `code`. Like the scrape listener, this profile is loopback-only unless the remote
transport below is selected, and it is not a tenant endpoint.

To read the same descriptors from the local GreptimeDB receiver, also set
`WOTEX_LAB_GREPTIME_QUERY_URL=http://127.0.0.1:<port>` and send the body to
`POST /durable/query`. Reads use the database named by
`WOTEX_LAB_GREPTIME_DATABASE`, or `public` without it, and the `workbench`
instance label that the exporter writes; the request cannot choose either.
Durable reads still need `WOTEX_LAB_PROMEX=1`, but with them the listener no
longer needs `WOTEX_LAB_METRICS_HISTORY=1`. Durable answers come
from fixed PromQL templates, so `avg` over gauges and steps that are not
whole seconds are refused, and `start_at` must be a whole multiple of
`step_ms` in Unix time. A receiver that refuses the template or answers
outside it gives 502; an unreachable receiver or a missing database gives
503. The local reader sends no credential.

For an operator-provisioned hosted receiver, set
`WOTEX_LAB_GREPTIME_QUERY_PROFILE=hosted`, set
`WOTEX_LAB_GREPTIME_QUERY_URL` to its exact HTTPS origin, such as
`https://metrics.example`, and provide `WOTEX_LAB_GREPTIME_QUERY_TOKEN`.
`WOTEX_LAB_GREPTIME_QUERY_CA_CERTFILE` may name a private CA. The query token
follows the same 43–128 character URL-safe rule and must differ from
`WOTEX_LAB_GREPTIME_TOKEN`, `WOTEX_LAB_OTLP_TOKEN`,
`WOTEX_LAB_GREPTIME_ADMIN_TOKEN`, `WOTEX_LAB_METRICS_TOKEN` and
`WOTEX_LAB_METRICS_QUERY_TOKEN`; startup is refused otherwise. Each read
re-resolves the host, refuses private or mixed DNS answers, pins one public
address and verifies the hostname through TLS.

### Remote operator transport

To scrape or query from another host, set `WOTEX_LAB_METRICS_TRANSPORT=remote`
for both listeners and provide:

- `WOTEX_LAB_METRICS_BIND`, the IP address to bind, such as `10.0.4.12`;
- `WOTEX_LAB_METRICS_TLS_CERTFILE` and `WOTEX_LAB_METRICS_TLS_KEYFILE`, the
  server certificate and key;
- `WOTEX_LAB_METRICS_TLS_CLIENT_CACERTFILE`, the CA that issues client
  certificates for your scrapers and operators;
- `WOTEX_LAB_METRICS_ALLOW`, up to 16 comma-separated CIDR ranges such as
  `10.0.4.0/24,2001:db8:4::/48`.

The listeners then accept only TLS 1.3 connections that present a client
certificate from that CA and originate inside a listed range, and still require
their Bearer tokens. Use SHA-256 or stronger certificate signatures; TLS 1.3
refuses SHA-1 chains. Forwarding headers are ignored, so place the listener
where the scraper connects to it directly. Issuing, rotating and revoking
certificates is operator work.

## Runtime configuration

Production requires `SECRET_KEY_BASE`. Optional variables are `PHX_HOST`,
`PORT`, `WOTEX_LAB_WORKBENCH_SESSION_TTL_MS`, `WOTEX_LAB_PROMEX`,
`WOTEX_LAB_METRICS_HISTORY`, `WOTEX_LAB_CONTROL_MUTATIONS` and `WOTEX_LAB_MAUDE`. A Maude
path is verified and supervised explicitly; no configured engine is reported
as unsupported, never as successful evidence.

The separately requested operator listeners also use `WOTEX_LAB_METRICS_PORT`
and `WOTEX_LAB_METRICS_TOKEN`, or `WOTEX_LAB_METRICS_QUERY_PORT` and
`WOTEX_LAB_METRICS_QUERY_TOKEN`, and durable reads use `WOTEX_LAB_GREPTIME_QUERY_URL`;
invalid or incomplete options refuse startup.

## OTLP spans and exception logs

Set `WOTEX_LAB_OTLP_URL=http://127.0.0.1:<port>/v1/otlp` to send Lab spans and
exception logs to a local GreptimeDB receiver, and optionally
`WOTEX_LAB_OTLP_DATABASE` to write them into a database provisioned with a
retention TTL. The exporter needs no PromEx or history activation. Each span
carries only the component, operation, outcome class, profile and, for
exceptions, the exception kind; Thing references, scenario identifiers,
results and exception reasons are never exported. The exporter buffers at
most 512 records per signal, sends one request at a time every five seconds and
drops records instead of retrying, so treat these signals as diagnostics.

For an authenticated hosted receiver, set `WOTEX_LAB_OTLP_PROFILE=hosted`,
`WOTEX_LAB_OTLP_URL` to its exact HTTPS base URL, such as
`https://traces.example/v1/otlp`, `WOTEX_LAB_OTLP_AUDIENCE` to that URL's
origin and `WOTEX_LAB_OTLP_TOKEN` to a 43–128 character URL-safe Bearer token.
`WOTEX_LAB_OTLP_CA_CERTFILE` may name a private CA. The token must differ from
`WOTEX_LAB_GREPTIME_QUERY_TOKEN`, `WOTEX_LAB_GREPTIME_ADMIN_TOKEN`,
`WOTEX_LAB_METRICS_TOKEN` and `WOTEX_LAB_METRICS_QUERY_TOKEN`; startup is
refused otherwise. Each export
re-resolves the host, refuses private or mixed DNS answers, pins one public
address and verifies the hostname through TLS.

## Control API mutations

The `/api/v1` control API always serves the catalogue reads and the
bearer-bound `readEvidence`, `readRun` and `queryMetrics` operations.
`queryMetrics` (`POST /api/v1/metrics/query`) takes the same JSON query
descriptor as the operator query listener and answers from the session room's
own history, with a one-hour range, 2,000 points and a one-second deadline. `startRun`, `cancelRun`
and `approveDecision` answer 403 `mutations_disabled` until the operator sets
`WOTEX_LAB_CONTROL_MUTATIONS=1`, which starts the host's rate and concurrency
limiter with 30 admissions per session per minute, one mutation in flight per
session and eight across the host.

Each mutation needs the session bearer, an `Idempotency-Key`, a JSON body of
at most 4,096 bytes with `deadline_ms` from 1 to 30,000, and either no `Origin`
header or the endpoint's own origin. The session room executes a key once and
replays the retained outcome for an identical retry with
`Idempotent-Replayed: true`. An approval must repeat the granted decision's
identifier, Thing, Action, input, proposal digest, state revision and expiry;
the room policy then rechecks freshness and dispatches the simulated Action at
most once. The full contract is in
[WLB.07](../../../../docs/packages/wotex-lab/specs/WLB.07-cookbooks-and-machine-interfaces.md#http-control-mutations).

## OCI release source

`Dockerfile` builds the released Workbench dependency cohort from Hex and then
runs its release as uid/gid 65532 on an exact multi-architecture base-image
digest. The public `/healthz` endpoint reads only required-process liveness and
does not create a session; the image health check reaches it over loopback with
OTP itself. `/tmp` and `/var/lib/wotex-lab` are the only declared ephemeral
write locations. A hardened local run is:

```sh
docker run --rm --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --tmpfs /var/lib/wotex-lab:rw,noexec,nosuid,size=64m \
  --memory 512m --cpus 1 --pids-limit 256 -p 127.0.0.1:4000:4000 \
  -e SECRET_KEY_BASE -e PHX_HOST=localhost wotex-lab-workbench:candidate
```

`elixir ../../bin/check_oci_source.exs` is the offline source-shape gate.
`WOTEX_LAB_OCI_CHECK=1` additionally asks Docker to validate the build graph;
it resolves image metadata and may populate the local builder cache, but does
not execute the image build. A full image build remains blocked until the
WoTEx packages named in `mix.lock` exist in the selected Hex repository. The
source check is not an image digest, runtime smoke or publication claim.

All rooms and their child processes are session-owned and bounded. Reports are
limited to one MiB, previews to 100 rows and 32 columns, charts to 2,000 points
per series and eight series, request bodies and LiveView frames to 64 KiB, and
metrics to the configured fixed-size ring.
