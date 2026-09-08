# Source and dependency baseline

Observation date: 2026-09-07. The companion `source-index.json` is a checked-in
inspection snapshot, not a generated release ecosystem manifest or a progress
tracker. It records immutable repository revisions, catalogue/plan paths,
observed source statuses and exact public behaviour source locations. All
eight inspected WoTEx worktrees were clean. No private implementation or local
filesystem path is a published input.

That original revision snapshot remains historical. The follow-up
[seam review](consumer-seam-review.md) describes scoped source repairs and the
separate content-based cohort, which includes uncommitted input. It does not
rewrite the original snapshot as though repairs existed at those commits.
The [workbench/observability decision](../decisions/0003-native-workbench-and-observability.md)
records the additional primary references and dependency boundaries.

The WoTEx Hex API routes for `wotex`, `wotex_runtime`, `wotex_binding_http`,
`wotex_binding_mqtt`, `wotex_directory`, `wotex_continuum`, `wotex_conformance`
and `wotex_nx` returned HTTP 404 at inspection. This is a dated observation,
not a permanent assertion. Candidate metadata uses 0.1.0 source baselines;
archive digests are not invented. `ex_maude` was available as 0.4.1.

## Primary references

| Source | Selected use and limitation |
| --- | --- |
| [W3C TD 1.1 Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/) | Core owns supported TD/TM/DataSchema meaning; no new Lab conformance claim |
| [Nx 0.13.1](https://hexdocs.pm/nx/0.13.1/Nx.html) and [Serving](https://hexdocs.pm/nx/0.13.1/Nx.Serving.html) | Explicit tensor/backend/defn/batch execution; Serving names/options follow this cohort |
| [Axon 0.8.1](https://hexdocs.pm/axon/0.8.1/Axon.html) | Optional consumer training integration selected explicitly by the host; the bounded room-model lane exercises `Axon.Loop` without adding model authority |
| [EXLA 0.13.1](https://hexdocs.pm/exla/0.13.1/EXLA.html) | Optional compiled CPU backend cohort for the room-model and tensor seams; the Lab asserts declared numerical tolerance, host transfer and deallocation, and makes no GPU claim |
| [Req](https://hexdocs.pm/req/Req.html) | Chosen finite HTTP and streaming reference; SSE lifecycle remains explicit Lab work |
| [Telemetry 1.3](https://hexdocs.pm/telemetry/readme.html) | Event emission library for Lab-owned spans and measurements under `[:wotex, :lab, ...]`; exporters, metrics and dashboards are separate WLB.10 host concerns |
| [EMQTT 1.16.0](https://hex.pm/packages/emqtt/1.16.0) | Chosen MQTT 5 client behind the optional `{:emqtt, "~> 1.15"}` requirement, resolved to 1.16.0 by `mix.lock`; credential custody and no-automatic-reconnect are asserted against this revision, and wire/session behaviour beyond the exercised cases is not claimed |
| [eclipse-mosquitto 2](https://hub.docker.com/_/eclipse-mosquitto) | Disposable local MQTT broker for the WLB.04 broker lane, selected by tag; not a digest-pinned release artifact and not a broker conformance claim |
| [Exqlite 0.40.0](https://hexdocs.pm/exqlite/0.40.0/Exqlite.html) | Chosen SQLite access, pinned by `mix.lock`; the transactions, conditional SQL and conflict mapping belong to the independent Lab adapter |
| [ExMaude 0.4.1](https://hex.pm/packages/ex_maude/0.4.1) | Optional `{:ex_maude, "~> 0.4.1"}` requirement, MIT; the Lab uses `ExMaude.Pool.child_spec/1`, `ExMaude.Pool.transaction/2` and `ExMaude.Server.execute/3` with the port backend only. Its compile step fetches a precompiled NIF for the unused native backend through rustler_precompiled; the Lab never selects that backend |
| [Maude 3.5.1](https://github.com/maude-lang/Maude/releases/tag/Maude3.5.1) | Rewriting logic engine, GPL-2.0, provisioned by the operator and pinned by digest as a profile input; the macOS arm64 release archive inspected on 2026-09-08 has SHA-256 `95851274f57b3853aab833674e2b770ed800f38fb1f3d03c97dcac56346c13dc`. Finite-model claims and the executable license are separate from WoT standards |
| [Livebook](https://livebook.dev/) and [Nerves Livebook](https://github.com/livebook-dev/nerves_livebook) | Executable notebooks and bootable embedded adoption convention; Lab supplies its own tested artifacts |
| [ExDoc 0.40.4](https://hexdocs.pm/ex_doc/0.40.4/readme.html) | Markdown/llms documentation inputs, not a replacement for normative catalogues |
| [OpenAPI 3.2.0](https://spec.openapis.org/oas/v3.2.0.html) | Selected Lab HTTP description dialect; no claim about all generators supporting it |
| [AsyncAPI 3.1.0](https://www.asyncapi.com/docs/reference/specification/v3.1.0) | Selected event/MQTT interface description dialect |
| [JSON-LD 1.1](https://www.w3.org/TR/json-ld11/) and [RDF 1.1 Turtle](https://www.w3.org/TR/turtle/) | Ecosystem graph representations only |
| [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Pinned stdio/Streamable HTTP baseline; transport conformance and control policy require separate tests |
| [Prometheus text exposition 0.0.4](https://prometheus.io/docs/instrumenting/exposition_formats/) | Pinned input contract of the WLB.10 self-scraper; counters, gauges and classic histograms only, parsed and rendered by `Wotex.Lab.Metrics.Exposition` |
| [Prometheus Remote Write 1.0](https://prometheus.io/docs/specs/prw/remote_write_spec/) and [prompb](https://github.com/prometheus/prometheus/tree/main/prompb) (Apache-2.0) | `WriteRequest`/`TimeSeries`/`Label`/`Sample` field numbers hand-encoded by `Wotex.Lab.Metrics.RemoteWrite`; no generated protobuf and no claim beyond the tested receiver |
| [Snappy block format](https://github.com/google/snappy/blob/main/format_description.txt) (BSD-3-Clause) | Pure Elixir literal and 16-bit-offset copy encoder plus full block decoder in `Wotex.Lab.Metrics.Snappy`; stream framing is not implemented |
| [greptime/greptimedb:v1.1.4](https://hub.docker.com/r/greptime/greptimedb) | Disposable standalone container for the `:greptime` lane, selected by tag; ingestion through `/v1/prometheus/write` and read-back through `/v1/sql` are the only exercised endpoints, not a digest-pinned release or a server conformance claim |

## Native containment source cohort

Observation date: 2026-09-08. The external helper replaces the Python runtime
and test probes. Production `cargo tree --no-default-features` contains only
the original `wotex-contained-exec` 2.0.0 and libc 0.2.189. The locked
`test-probes` feature adds serde_json 1.0.151 and its test-only closure. Cargo
Audit 0.22.2 reported no vulnerabilities for the 13 lock entries against
RustSec database revision `8a1eb4f933fb5821add5b4e98601ebd90b8b3538`.
The helper and libc use Apache-2.0 and MIT/Apache-2.0 respectively; no native
third-party source is vendored and no NIF is added.

The Darwin aarch64 cohort uses Rust/Cargo 1.97.1 with Elixir 1.20.2/OTP 29.
After reproducing a transient `libproc` exec-accounting gap, the bounded retry
passed 300 short-lived BEAM launches (ten runs of the 30-launch regression).
Persistent absent accounting still fails closed. The six native unit tests
and four lifecycle tests also passed strict Clippy and rustfmt on Linux with
Rust 1.85.1, in the disposable `rust:1.85.1-bookworm` image manifest
`sha256:e51d0265072d2d9d5d320f6a44dde6b9ef13653b035098febd68cce8fa7c0bc4`
with two CPUs, 512 MiB and 128 PIDs. The container mounted a read-only source
snapshot; it did not alter host namespace or security settings. This proves
the native Linux helper cohort, not Bubblewrap/cgroup integration or published
binary adoption. The renewed WLB.06 record identifies the actual Darwin helper
binary and retains an explicit not-run hostile-worker assertion.

## Explicit Workbench PromEx cohort

Observation date: 2026-09-08. The host alone selects PromEx 1.12.0 (MIT) and
Telemetry.Metrics 1.2.0. Its lock also records Peep 4.4.0 (Apache-2.0),
telemetry_metrics_prometheus_core 1.2.1, telemetry_poller 1.3.0, octo_fetch
0.5.0, castore 1.0.21 and ssl_verify_fun 1.1.7. Existing locked releases did
not change; archive checksums remain in `hosts/workbench/mix.lock`.

The public [PromEx.Storage behaviour](https://hexdocs.pm/prom_ex/1.12.0/PromEx.Storage.html)
supports the host's own bounded aggregation adapter. Inspection of the pinned
[Core adapter](https://github.com/akoutmos/prom_ex/blob/1.12.0/lib/prom_ex/storage/core.ex)
and [Peep adapter](https://github.com/akoutmos/prom_ex/blob/1.12.0/lib/prom_ex/storage/peep.ex)
found that Core buffers histogram samples while the Peep dependency's custom
bucket helper uses strict comparisons and its atomic backend rounds sample
sums to integers. The Lab catalogue instead requires inclusive buckets and
fractional seconds. The Workbench therefore uses neither backend: its own
adapter stores bounded aggregates with inclusive thresholds and nanosecond
integer sums. Source tests compare the real public PromEx scrape against the
Lab collector, including 1/5/25 ms boundaries and subsecond sums. No private
PromEx/Peep storage API or dependency patch is involved.

Activation is explicit and custom-catalogue-only. PromEx's default status group
is dropped; its optional Cowboy listener, Grafana agent and dashboard upload
are disabled. The absent optional Plug.Cowboy module produces an upstream
compile diagnostic; adding an unused HTTP server or hiding that diagnostic is
not part of this cohort. BEAM/Phoenix/LiveView built-in introspection requires
a separate admission review and is not enabled. The base library still has no
PromEx dependency. The portable JSON uses classic Grafana schema 39 and fixed
[Prometheus rate/histogram queries](https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile).
Export shape/query equality is tested; a Grafana import or PromQL-engine cohort
is not claimed by those source tests.

## History admission and metrics source cohort

Observation date: 2026-09-08. The eight metrics/Greptime test files passed
52 tests with seed 1 on Elixir 1.20.2 / OTP 29 / aarch64 Darwin, including the
real Remote Write ingestion and SQL read-back test. The disposable
`greptime/greptimedb:v1.1.4` image resolved to
`sha256:9726587eac95d0360755254cd59a528dbf48abfdf268478aea6a644f62afe44c`.
Its source-test profile uses a loopback-only ephemeral HTTP port, no persistent
volume, 2 CPUs, 1 GiB memory with no additional swap and 256 PIDs; cleanup was
verified after the test. This does not prove TTL provisioning, authenticated
remote deployment, official-sender compatibility or the unimplemented query
gateway/BeamLens integration.

History queries now require explicit instance binding; snapshot slots, query
leases and catalogue metric semantics are independently admitted. Tests cover
within-bucket resets, no-data/stale histograms, rollback, forged descriptors,
scope substitution, caller-death cleanup and cooperative deadline refusal.
No new dependency or automatic history/HTTP/database activation is introduced.

The same source/toolchain cohort subsequently exercised the explicit Workbench
PromEx-to-ETS sampler: five dedicated tests cover receipt matching, unavailable
capture, reset/stale/gap semantics, periodic retention and startup/lifecycle
boundaries. The owning observability pair passes 11 tests. A separate actual
application boot with both activation flags and its HTTP endpoint explicitly
disabled ran the thermal scenario and admitted one 2,923-byte snapshot into the
default 120-snapshot / 8 MiB history, with zero sampling failures. The application
was stopped afterward. This is source-host integration, not browser-tenant
history, a protected HTTP listener, durable activation or artifact adoption.

The protected local scrape cohort uses the existing Bandit 1.12.5,
ThousandIsland 1.5.0 and Plug 1.20.3 lock entries. Five additional tests exercise
closed auth/configuration and real loopback sockets, including an unread large
body, eight-connection capacity and cleanup; the three observability test files
pass 16 tests. A separate actual application boot used an explicit ephemeral
metrics port, a disposable test credential and a disabled browser HTTP endpoint.
The thermal scenario produced a 5,917-byte HTTP 200 scrape, with no token in the
response or listener options, and application shutdown removed the listener.
No remote/TLS, slow-header whole-request deadline, untrusted-hosted or artifact
adoption claim follows. The ordinary browser Metrics page was not repurposed.

## Acknowledged dependency advisories

### Optional Explorer source cohort

Observation date: 2026-09-08. The optional Lab profile and explicit Workbench
host resolve Explorer 0.12.0, aws_signature 0.4.3, table 0.1.2 and table_rex
4.1.0; existing locked versions, including Decimal 3.1.1, are unchanged.
The exact Hex archive checksums are in both lock files. The exercised native
target is `libexplorer-v0.12.0-nif-2.15-aarch64-apple-darwin.so`: upstream's
archive checksum is `sha256:daf57367a83a0cc731af14a7474dfd17f204fa891efa38973983480839ee48c2`,
and the loaded, extracted library hashes to
`sha256:84154cdd12b555990453f6dae40d1c28af51f49490bb264fc0615d3e6cb221ce`.
This is an Elixir 1.20.2 / OTP 29 source cohort, not a Linux, minimum-toolchain,
Nerves or installed-host artifact claim. Explorer/table_rex emit upstream
compiler diagnostics on Elixir 1.20; the Lab and host compile cleanly with
warnings as errors. No dependency code or warning policy was patched to hide them.

`Analytics` uses only admitted in-memory scalar data and closed Polars
operations. It does not call Explorer filesystem, cloud, SQL or arbitrary
expression APIs. Native computation remains inside the VM and is not a
replacement for WLB.06's external-executable containment boundary. The base
archive gate proves neither Explorer nor its profile module enters the first
tensor's dependency closure. No `kino_explorer` or chart wrapper is selected.

### Optional MQTT cohort

Observation date: 2026-09-08. The optional `emqtt` requirement resolves `gun`
and `cowlib`, which carry open advisories with no patched Hex release at that
date: `GHSA-w4f7-4cxr-rv3c` (gun), `EEF-CVE-2026-43966`, `EEF-CVE-2026-43969`
and `EEF-CVE-2026-43971` (cowlib). Every affected code path is Cowboy/Gun HTTP,
cookie, link-header or HPACK/QPACK handling reached through emqtt's WebSocket
and QUIC transports. `Wotex.Lab.Adapters.MQTT.Session` selects `emqtt_sock`,
the plain TCP transport, and never `emqtt_ws` or `emqtt_quic`.

`mix.exs` (`hex: [ignore_advisories: ...]`) and `.mix_audit.ignore` therefore
acknowledge exactly these identifiers so `mix check` reports a real regression
rather than a permanent failure. This is a dated, scoped acknowledgement, not a
claim that the advisories are invalid: a consumer that also uses gun or cowlib
for HTTP is affected independently of Lab, and the acknowledgement must be
removed once a patched release exists.

### Decimal affected-range inconsistency

Observation date: 2026-09-08. `decimal` 3.1.1 is reported as vulnerable by the
current EEF/OSV record for `EEF-CVE-2026-32686`, even though that record's prose
says versions before 3.0.0 are affected. The upstream
[3.0.0 changelog](https://github.com/ericmj/decimal/blob/v3.1.1/CHANGELOG.md)
records the decimal128 input limits that reject pathological exponents, and the
[GitHub advisory](https://github.com/advisories/GHSA-rhv4-8758-jx7v) names
3.0.0 as the patched version. The [EEF/OSV record](https://osv.dev/vulnerability/EEF-CVE-2026-32686)
nevertheless listed 3.0.0 through 3.1.1 in its affected-version data on the
observation date. There is no later Decimal release to select.

The Lab therefore acknowledges `EEF-CVE-2026-32686` for the exact locked
3.1.1 release. `test/wotex/lab/dependency_security_test.exs` exercises the
reported unbounded-exponent payload behind a deadline and requires both parse
entry points to reject it. This is a temporary response to contradictory
machine-readable metadata, not a general waiver: remove the acknowledgement if
the lock moves below 3.0.0, the regression fails, or the advisory range changes.

Selected versions are design baselines, not claims that they are universally
the newest or compatible. Runtime dependencies are pinned by `mix.lock`; full
profile dependency and binary cohorts are admitted by WLB.08. Changing a source
revision requires checking its spec/API/claim differences and renewing affected
evidence. External standards schemas are linked, not copied into Lab fixtures.
