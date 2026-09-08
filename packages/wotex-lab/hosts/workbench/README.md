# WoTEx Lab workbench

This is the non-umbrella Phoenix LiveView reference host owned by
[WLB.11](../../docs/specs/WLB.11-workbench-and-design-system.md). It consumes
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
are resolved as versioned artifacts. The application never downloads chart
code: pinned Vega, Vega-Lite and Vega-Embed builds and their BSD licenses ship
under `priv/static/vendor/`. `elixir bin/provision_chart_assets.exs` is the
explicit digest-verifying renewal command.

The local completion gate is:

```sh
WOTEX_PATH_DEPS=1 mix check --no-retry
```

The host uses a small native check runner because its accepted location is two
levels below another Mix project, a shape that ex_check interprets as a possible
umbrella child. `.check.exs` remains the declarative list of the same checks.
Node is needed for the dependency-free chart-hook tests, not by the running
Elixir host. The exact Decimal 3.1.1 advisory acknowledgement is documented in
the Lab's [dependency review](../../docs/provenance/standards-and-dependencies.md)
and protected by the host's own locked-version and bounded-parser regression.

## Interactive charts and browser evidence

The host explicitly selects Explorer 0.12.0 and invokes the shared
`Wotex.Lab.Analytics` profile when “Apply analysis” is submitted. Series and
inclusive event-time filters, line/point/area selection and compatible-unit
comparisons are read-only: they cannot re-run an experiment or change its
evidence. Summaries distinguish observations, missing and nonfinite values;
tables show at most 100 rows and both source and query digests. Empty ranges
are not measured zeros. Reload does not replay the query. No `kino_explorer`
dependency, arbitrary SQL/expression or browser-selected instance is admitted.

Vega Embed uses its bundled CSP interpreter (`ast: true`); neither
`unsafe-eval` nor a fourth script is required. The renderer cannot load URLs.
The hook applies only a fixed horizontal pan/zoom interaction, follows theme
changes, resets by keyboard and finalizes obsolete views. Accessible SVG and
the maximum 100-row table remain available when enhancement fails. The SVG
supports all three admitted marks and preserves missing-value gaps.

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
script reports actual Node, Playwright and Chromium versions. The 2026-09-08
source cohort passed with Node 26.8.1, Playwright 1.63.0-alpha-2026-08-31 and
Chromium 153.0.8010.12; this is neither a stable-browser compatibility matrix,
WCAG certification nor installed-artifact evidence.

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
Its fixed instance is `workbench`, not the current browser session. No route
reads this host-wide history. Remote query authentication and tenant isolation
remain separate work. Restarting the optional supervisor discards its history;
neither sampling nor dataframe conversion makes it durable or training data.

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
does not imply hostile shared-VM isolation. No model/provider/key discovery is
added. BeamLens remains unactivated pending its separate privacy/lifecycle and
provider-budget acceptance; choosing only custom skills is not sufficient.

The Metrics page's portable-panel selector exports only catalogue definitions
through `/metrics/dashboard.json`, with 1–16 known IDs. A verified browser
session is required; no room or collector starts. Importing the JSON and
choosing a Prometheus-compatible source are operator actions. The export
preserves label sets, uses five-minute counter rates and bucket-derived p95,
and never fills missing data with zero. Grafana import compatibility, durable
history activation, remote/TLS scraping and saved arrangements are separate
acceptance work, not claims made by this source export.

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

## Runtime configuration

Production requires `SECRET_KEY_BASE`. Optional variables are `PHX_HOST`,
`PORT`, `WOTEX_LAB_WORKBENCH_SESSION_TTL_MS`, `WOTEX_LAB_PROMEX`,
`WOTEX_LAB_METRICS_HISTORY` and `WOTEX_LAB_MAUDE`. A Maude
path is verified and supervised explicitly; no configured engine is reported
as unsupported, never as successful evidence.

The separately requested operator listener also uses `WOTEX_LAB_METRICS_PORT`
and `WOTEX_LAB_METRICS_TOKEN`; invalid or incomplete options refuse startup.

All rooms and their child processes are session-owned and bounded. Reports are
limited to one MiB, previews to 100 rows and 32 columns, charts to 2,000 points
per series and eight series, request bodies and LiveView frames to 64 KiB, and
metrics to the configured fixed-size ring.
