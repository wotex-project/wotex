# Decision: native workbench, local metrics and bounded AI inspection

Status: accepted. Applies to WLB.10/WLB.11 and completion plan 1.1.0.

[Decision 0010](0010-liveview-svelte-islands.md) later extends the rendering
selection with bounded Svelte islands. LiveView remains the application,
session, authorization and canonical-state owner selected here.

The reference stack is Phoenix LiveView/HEEx, Telemetry.Metrics/PromEx,
bounded ETS snapshots, GreptimeDB durable history and on-demand BeamLens.
Livebook/Kino is the notebook path. Shared semantic CSS tokens live in the
base library; integration applications own processes, endpoints and clients.

This chooses a clear experience while keeping library consumers free to choose
their own host. It does not impose a UI framework, database, LLM, Grafana or
Prometheus server on the first Nx example. No ELK components are included.
The visual direction is a quiet conversational workspace with an ordinary
sidebar, readable content and sparse controls, not a branded application clone.

GreptimeDB fits the requested local-first time-series history. It is a separate
service, not an in-VM store. PromEx is a collection/dashboard-definition library,
not a sender or UI renderer. WLB.10 therefore makes the BEAM self-scraper and
remote-write bridge an explicit, independently tested component. This avoids
silently assuming that two compatible products are already integrated.

BeamLens is naturally suited to investigating Lab metrics through custom skills.
Its default introspection/automatic monitoring is broader than a disposable
multi-user Lab needs. Explicit skills, provider choice, bounded requests and
service-enforced read scope are required. The host handles dependency-global
names and state; separate tenants do not gain shared VM introspection.

Neither a metric dashboard nor an AI explanation is numerical or conformance
evidence by itself. Dataset exports are immutable snapshots. Formal checking
through ex_maude remains bounded, model-scoped evidence; it never grants an
Action permission. These boundaries are visible in the workbench.

## Primary sources inspected

- [PromEx 1.12.0](https://hexdocs.pm/prom_ex/1.12.0/PromEx.html): metric capture,
  public `get_metrics/1`, host configuration and Grafana templates.
- [GreptimeDB quick start](https://docs.greptime.com/getting-started/quick-start/):
  standalone listeners and deployment/authentication boundary.
- [GreptimeDB HTTP endpoints](https://docs.greptime.com/reference/http-endpoints/):
  remote write, SQL/PromQL and signal-specific OTLP APIs.
- [Remote Write 1.0](https://prometheus.io/docs/specs/prw/remote_write_spec/):
  wire format, ordering, retries and staleness requirements.
- [BeamLens 0.3.1 architecture](https://hexdocs.pm/beamlens/0.3.1/architecture.html)
  and [custom skills](https://hexdocs.pm/beamlens/0.3.1/Beamlens.Skill.html):
  static operators, callbacks, on-demand analysis and built-in inspection scope.
- [Phoenix components](https://hexdocs.pm/phoenix/1.8.13/components.html) and
  [LiveView JS interop](https://hexdocs.pm/phoenix_live_view/1.2.11/js-interop.html):
  server-owned component state and narrowly scoped chart hooks.
- [Kino.VegaLite](https://hexdocs.pm/kino_vega_lite/0.1.13/Kino.VegaLite.html):
  notebook charts with explicit streaming windows.
- [WCAG 2.2](https://www.w3.org/TR/2024/REC-WCAG22-20241212/): accessibility
  target; token contrast is only one part of acceptance.

Inspection date: 2026-09-07. These are design/API references, not an installed
or verified integration cohort. WLB.08 requires exact locks, binary digests,
licenses and positive/negative integration evidence before availability claims.
