# WLB.11: Lean workbench and shared design system

Specification version: 0.3.0. Contract: accepted.

## Implemented source and evidence boundary

`hosts/workbench/` now contains the non-umbrella Phoenix LiveView reference
host, all required HEEx components, a scoped semantic CSS layer, vendored and
digest-pinned Vega assets with upstream licenses, three executable experiments,
session-owned disposable rooms, bounded live metrics and immutable exports,
formal evidence presentation, and a one-MiB JSON evidence report. Its separate
Action approval names and rechecks the decision, proposal digest, Thing,
operation, input, revision and expiry; experiment execution cannot approve it.

The existing host gate compiles with warnings as errors, formats, runs strict Credo,
unused-dependency and security audits, Dialyzer, Doctor, ExDoc, the boundary
scan and the host suite with at least 90% line coverage. Those tests cover empty and
denied states, themes/sidebar semantics, reflow/reduced-motion source rules,
multi-session isolation, reconnect navigation, cancel/replay, escaped TD text,
bounded chart/query/report data, token overrides, immutable exports, formal
unavailability and operation without an LLM. This is implemented source and
reference evidence, not a WCAG certification or artifact-adoption claim;
WLB.08 owns clone-free archive/OCI execution and independent real-browser
cohort evidence.

The interactive analytics extension below adds acceptance obligations. The
chart normalization, mark-correct fallback, CSP-interpreted rendering and
mount/update/disposal lifecycle now have executable source evidence in
`chart_contract_test.exs` and `test/js/chart_hook_test.cjs`. The explicit
`bin/check_chart_browser.cjs` host gate checks real Chromium rendering,
keyboard reset, themes, mobile reflow, reload and session isolation. Its
recorded cohort is source evidence, not the complete WLB.08 browser matrix.
`Insights` and its HEEx controls now invoke the shared optional Lab Explorer
profile only on explicit inspection. Unit and LiveView tests cover range/series/
mark selection, scope substitution, empty results and unchanged run evidence.
The browser gate also exercises updated charts after analysis. See the
[interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md).

## Product and implementation boundary

The Lab includes a first-class UI: an experiment workbench for the Nx/Elixir
community. Phoenix LiveView, HEEx function components and a small scoped CSS
design system are the reference. Livebook/Kino remains the notebook experience;
it is complementary, not hidden inside a custom notebook editor.

The base `wotex_lab` library remains usable without Phoenix, a browser, PromEx,
GreptimeDB or an LLM. A non-umbrella reference host at `hosts/workbench/` owns
its Mix project, endpoint, explicit supervision and optional integrations. It
consumes Lab via artifact requirements and WLB.08's development switch, never
private modules. Its packaged source archive and OCI image provide clone-free
UI distribution. This directory is an accepted deliverable, not source already
implemented by the foundation. No collection of mandatory new repositories.

The base library supplies `Wotex.Lab.DesignSystem.tokens/0`, `version/0` and
`stylesheet/0`: immutable semantic tokens and deterministic scoped CSS, with
no runtime filesystem reads, network calls or global CSS reset. The host adds
HEEx components and assets. Consumers may replace the host/components or
override tokens without changing a scenario, query or WoT contract.

## Interaction and visual language

Use the modern simplicity of a conversational workspace, not another brand's
identity or assets: neutral surfaces, one restrained accent, system fonts,
comfortable reading width, modest radii, fine borders and quiet status badges.
No decorative gradients, glass panels, neon charts, giant cards, animated
backgrounds or mandatory icon/font CDN. Dense data views are allowed where
useful; empty screens explain one clear next action.

The shell has a collapsible left sidebar, a compact top context line and a
single main workspace. The sidebar contains Experiments, Things, Metrics and
Evidence, with settings at the bottom. A run context includes its identity,
source mode, backend and state. Conversation history is subordinate to the
selected experiment, not a new global navigation system.

| View | Main content | Primary action |
| --- | --- | --- |
| Experiments | Nx cookbook/run list, parameters, dataset/TD/model provenance, values/masks/quality preview | Run an admitted experiment |
| Run workspace | Summary, tensor shape/dtype/backend, timeseries, assertions, cleanup and inert proposal | Compare or inspect public calls |
| Things | Disposable TDs, affordances, transport and explicit ownership seam | Read a simulated Property |
| Metrics | Small saved panels, range/filter controls, freshness/loss markers | Ask about the visible measurements |
| Evidence | Dependency/spec/dataset/query digests, conformance outcomes and formal model scope | Inspect or export a bounded report |

BeamLens appears as an “Ask about this run” composer and a collapsible answer
thread, not a full-screen chatbot gate. Answers link to the exact charts,
queries and evidence they used. Users can do every ordinary experiment and
inspection without an LLM. Prompt text never silently dispatches a Thing Action.
Custom dashboards are saved arrangements of admitted metric panels. PromEx
Grafana JSON exports are available; no automatic upload or mandatory Grafana
iframe is part of the default UI. LiveDashboard is trusted operator tooling,
not the public experiment workbench.

## Component and chart contract

Required HEEx components: shell/sidebar, context header, button/icon button,
field/select, tabs, status badge, empty/error state, accessible data table,
metric panel, chart with table alternative, tensor summary, query/evidence
link, prompt composer, answer/source block, and explicit Action approval form.
All use semantic token roles, slots and documented attributes. No caller HTML
string injection, Tailwind/DaisyUI requirement, React runtime or second SPA.

Use bounded Vega-Lite chart specifications shared with the Livebook/Kino lane,
rendered by a narrowly scoped LiveView hook. The host vendors pinned chart
assets, disables external data URLs/expression injection from untrusted input,
and ships no arbitrary user-authored chart execution. HEEx owns controls and
state; the hook owns rendering only. Pin the chart/LiveView compatibility cohort.

Explorer owns optional native dataframe analysis, not chart rendering or
telemetry storage. Series/range/mark controls are server-admitted and keyboard
accessible; changing a view cannot restart a run, alter its evidence or approve
an Action. Summary rows show observed and missing/nonfinite counts and retain
units and source/query identity. Livebook and LiveView consume the same bounded
analysis semantics without a required `kino_explorer` dependency.

The hook must implement mount, update and destruction, finalize superseded
views, survive out-of-order asynchronous renders and restore the fallback on
failure. Fixed host-generated pan/zoom may be added after admission; caller
`params`, signals and expressions remain forbidden. Line/area/point marks and
gaps agree between the enhanced chart and fallback. SVG includes axis labels,
ticks, legend, title/description and an explicit zero area baseline. Tables
are at most 100 rows and disclose truncation rather than embedding every point.

Browser previews are at most 100 rows, 32 columns and 2,000 points per series,
eight visible series per panel. The server limits queries before transferring
data. Downsampling identifies its method and interval and preserves visible
gaps/extrema; raw evidence is not rewritten to match the chart. Do not copy
full tensors/GPU buffers to the browser or run backend work on each render.
Inspect dtype, shape, units, mask/quality codes and source IDs before numbers;
missing and nonfinite/rejected values cannot masquerade as zero. Nx.Serving
queue latency, compilation/warm-up and execution are distinct measurements.

The tensor preview splits the lazy `Nx.Batch` before stacking, builds only the
selected features through public `Nx.LazyContainer` traversal, and slices
vector cells and the quality matrix before host-list conversion. It discloses
row/feature truncation, caps each vector cell at 32 elements and labels mask
counts as preview-element counts. `tensor_window_test.exs` traces every
`Nx.to_list/1` call over a 250-row, 40-feature, 64-element fixture and requires
only 100×32 tensors to cross that boundary. Min/max downsampling uses gap
sentinels before/between/after retained extrema, preserves input order and
cannot draw across an omitted missing span. Missing spans may coalesce;
interval means input points per bucket. A requested downsampling budget below
five is refused when truncation is needed, rather than dropping an extremum
or gap to claim success. The fixed normal budget remains 2,000.

## Accessibility, lifecycle and security

Target WCAG 2.2 AA: keyboard-only operation, visible focus, semantic landmarks,
skip link, labeled controls, accessible names, reflow/zoom, contrast and reduced
motion. Status is conveyed in text, never color alone. Light/dark themes follow
system preference unless explicitly chosen. Charts have table/text alternatives.
Prompt output uses restrained live-region announcements, not token-by-token
screen-reader flooding. No hidden essential content on small screens.

LiveView starts no experiment merely by mounting/reconnecting. Start, cancel,
dataset export and simulated mutation have distinct server-admitted commands.
Authentication/instance scope is rechecked on mount and every event/query;
expired sessions revoke pending work. WLB.07's origin/CSRF/session/egress limits
apply. TD extensions, prompts, labels and model responses render as escaped
text. Use a restrictive CSP, local assets, body/event quotas and secure cookies.
Browser reconnect cannot replay an approval or repeat an Action.

Action approval names the exact disposable Thing, operation, input, proposal
digest, current revision and expiry. The server checks policy and freshness at
dispatch. “Run experiment” cannot also mean “approve this Action”. UI disabled
states are not authorization. ex_maude output appears as model-scoped evidence
with bounds/exhaustion/counterexamples, never a green physical-safety badge.

Acceptance includes browser tests for keyboard/theme/reflow, empty/denied/
stale/loading/failure states, multi-session isolation, reconnect/cancel/replay,
malicious TD/prompt content, bounded chart data, component/token overrides,
live query vs immutable dataset distinction and no-LLM operation. Token
contrast tests support this gate but do not prove whole-UI accessibility.

The base library's design-system surface remains tokens/CSS only. The separate
host implements the endpoint/components; neither token tests nor source-only
component tests claim the complete real-browser acceptance suite.
