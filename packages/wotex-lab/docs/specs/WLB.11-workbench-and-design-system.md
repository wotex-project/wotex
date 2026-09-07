# WLB.11: Lean workbench and shared design system

Specification version: 0.1.0. Contract: accepted.

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

Browser previews are at most 100 rows, 32 columns and 2,000 points per series,
eight visible series per panel. The server limits queries before transferring
data. Downsampling identifies its method and interval and preserves visible
gaps/extrema; raw evidence is not rewritten to match the chart. Do not copy
full tensors/GPU buffers to the browser or run backend work on each render.
Inspect dtype, shape, units, mask/quality codes and source IDs before numbers;
missing and nonfinite/rejected values cannot masquerade as zero. Nx.Serving
queue latency, compilation/warm-up and execution are distinct measurements.

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

The foundation implements tokens/CSS only. It does not claim a running Phoenix
endpoint, implemented HEEx components, charts or the browser acceptance suite.
