# WLB.11: Lean workbench and shared design system

Specification version: 0.12.0. Contract: accepted. Implementation status:
partial.

## Implemented source and evidence boundary

`hosts/workbench/` contains the implemented non-umbrella Phoenix LiveView
reference host, its current HEEx components, a scoped semantic CSS layer,
server-rendered native SVG charts, three executable experiments,
session-owned disposable rooms, bounded live metrics and immutable exports,
formal evidence presentation, and a one-MiB JSON evidence report. Its separate
Action approval names and rechecks the decision, proposal digest, Thing,
operation, input, revision and expiry; experiment execution cannot approve it.
When the trusted-local BeamLens profile is explicitly active, the run/evidence
composer submits one owner-bound bounded investigation and presents escaped
facts, hypotheses, missing evidence, provider/model disclosure and the next
safe read-only check. Findings that do not cite evidence digests the
investigation received are withheld (WLB.10), and cited digests render as
unlinked text. Before a question is submitted, the composer states whether
investigation data leaves the host, where it goes and which bounded content
each request can include. The ordinary UI remains complete when it is disabled.
The public `/healthz` route exposes only schema version and required-process
liveness, creates no session and is usable by the release image's fixed
loopback probe.

The LiveView/Svelte island architecture, shared Phoenix Assets component
system, static Storybook, island transport and enhanced reporting components
specified below are accepted additions and are not implemented by that source
boundary. Existing HEEx and browser tests do not claim them.

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

The interactive analytics extension below adds acceptance obligations. Closed
chart admission and mark-correct server SVG rendering have executable source
evidence in `chart_contract_test.exs`. The separately invoked, optional
`hosts/workbench/bin/check_chart_browser.cjs` source cohort checks real
Chromium rendering, mark updates, exact analysis/chart/dashboard links, saved
session arrangements,
keyboard disclosure and skip navigation, themes, mobile reflow, bounded
downloads, reload/no-replay and session isolation. It also loads saved history
panels from the keyboard and checks their charts, mobile reflow, reload without
replay and absence from a second session. Its first run found history panels
widening a 375-pixel page, because stacked grid items kept the min-content
width of charts and query digests. Stacked items may now shrink and digests
wrap. The cohort also drops and restores the LiveView socket before submitting
a smart-room approval from the keyboard, then requires that neither a further
reconnect nor a reload shows the approval again or changes the dispatched run
in the evidence report. A run cancelled before approval stays undispatched
across a reconnect. A registered Thing Description whose title holds image and
script markup must render that title as text, with no created element, dialog
or executed handler. Without a configured provider the investigation composer
is disabled, names that reason and shows no data disclosure. A separate browser
context then sees the Things, Metrics and Evidence empty states with no room
controls, and the evidence report refuses with 404 while no room exists. It
starts a room from the keyboard, runs the thermal experiment twice and freezes
the retained measurements between the runs: the live sample count grows while
the frozen dataset in the report stays identical, and a formal verification
request without an engine reports the unavailable engine. It is not part of the
twelve-check `mix check` host gate and requires an operator-owned server plus an
explicitly installed Playwright/Chromium toolchain. Its recorded cohort is
source evidence, not the complete WLB.08 browser matrix or a WCAG certification.
`Insights` and its HEEx controls invoke the shared optional Lab Explorer
profile only on explicit inspection. Unit and LiveView tests cover range/series/
mark selection, scope substitution, empty results and unchanged run evidence.
The browser gate also exercises updated charts after analysis. See the
[interactive analytics decision](../decisions/0005-interactive-elixir-analytics.md).
The renderer selection is recorded separately in the
[native SVG decision](../decisions/0007-native-svg-chart-rendering.md).

The Metrics view also exposes catalogue-derived panel selection and a bounded,
session-verified Grafana JSON download. This surface shows definitions only,
never the opt-in PromEx collector's host-wide measurements as session data.
`metric_panels_test.exs` binds every descriptor/query to the catalogue and
`dashboard_test.exs` covers session denial, closed selection, inert export,
session-owned saved arrangements and exact reproducible selection URLs. A deep
link may preview an admitted arrangement without silently replacing the saved
one.

Saved panels are also query-backed for the session room. Each room owns a
catalogue collector attributed to its own process, a history of at most 120
snapshots and 1 MiB, and a random history instance identifier. The room
captures after each run or approval and every five seconds. Things and shared
processes started under the host instance are not attributed. The explicit
`load_history` event revalidates the session and queries only that room's
history. `HistoryPanels` accepts 5-minute, 15-minute and 1-hour ranges with 5-,
15- and 60-second steps. Each label set, at most eight per panel, is one
`Metrics.Query` with every dimension filtered and reduced limits: 2,000 points,
256 KiB, a 250 ms deadline and a 1.5-second load budget. Counters show the
per-second rate inside each step, gauges the last value and histograms the
bucket-derived p95. The native SVG chart keeps empty steps as gaps. Each panel
states its label-set count, freshness, history markers and query digests. A
panel without captured series is unavailable, and a scope from another room
is refused. Mounting runs no query and a new arrangement clears old results.
`history_panels_test.exs` covers two rooms on one host, attribution
through started processes, cleanup with the room, rates, last values, p95,
gaps, eight-series truncation, budget exhaustion, clock rollback and
refusals. `dashboard_test.exs` covers the explicit browser flow, invalid
ranges, cleared arrangements, a second session's empty history and a revoked
session.

The separately selected `WOTEX_LAB_GRAFANA=1` lane in
`grafana_import_test.exs` imports the downloaded JSON for all 43 catalogue
panels, in 16-panel selections, into pinned Grafana 13.2.2. Grafana binds the
Prometheus data source input and stores each exact template. The lane runs
every stored target through Grafana against pinned GreptimeDB 1.1.4 history
that the Workbench bridge wrote from real PromEx captures. Panels with captured
source series, including the eight fed by the thermal fixture, return values;
gauges keep captured values and earlier ranges return none. The other panels
answer without values or errors. This server cohort does not claim Grafana
browser rendering or other Grafana versions.

## Product and implementation boundary

The Lab includes a first-class UI: an experiment workbench for the Nx/Elixir
community. Phoenix LiveView owns the application, session and server state.
HEEx renders the page shell, semantic fallbacks and ordinary controls. Selected
browser-intensive components mount Svelte 5 through Phoenix Assets' PHA.02
island adapter. Livebook/Kino remains the notebook experience; it is
complementary, not hidden inside a custom notebook editor.

The base `wotex_lab` library remains usable without Phoenix, a browser, PromEx,
GreptimeDB or an LLM. A non-umbrella reference host at `hosts/workbench/` owns
its Mix project, endpoint, explicit supervision and optional integrations. It
consumes Lab via artifact requirements and WLB.08's development switch, never
private modules. Its packaged source archive and OCI image provide clone-free
UI distribution. This directory is an accepted deliverable, not source already
implemented by the foundation. No collection of mandatory new repositories.

The base library supplies `Wotex.Lab.DesignSystem.tokens/0`, `version/0` and
`stylesheet/0`: immutable Wotex semantic theme roles and deterministic scoped
CSS overrides, with no runtime filesystem reads, network calls or global CSS
reset. Phoenix Assets owns the generic DTCG token source, component CSS, icons,
HEEx primitives, Svelte primitives, island hook and Storybook. The host composes
those primitives and may add Wotex-specific HEEx structure. Consumers may
replace the reference host or override documented semantic roles without
changing a scenario, query or WoT contract.

## Interaction and visual language

Use the modern simplicity of a conversational workspace, not another brand's
identity or assets: neutral surfaces, one restrained accent, system fonts,
comfortable reading width, modest radii, fine borders and quiet status badges.
No decorative gradients, glass panels, neon charts, giant cards, animated
backgrounds or mandatory icon/font CDN. Dense data views are allowed where
useful; empty screens explain one clear next action.

The shell has a collapsible left sidebar, a compact top context line and a
single main workspace. The sidebar contains Experiments, Things, Metrics,
Evidence and Documentation, with settings at the bottom. Documentation opens
the public inert WLB.12 route and does not allocate a room. A run context
includes its identity, source mode, backend and state. Conversation history is
subordinate to the selected experiment, not a new global navigation system.

| View | Main content | Primary action |
| --- | --- | --- |
| Experiments | Nx cookbook/run list, parameters, dataset/TD/model provenance, values/masks/quality preview | Run an admitted experiment |
| Run workspace | Summary, tensor shape/dtype/backend, timeseries, assertions, cleanup and inert proposal | Compare or inspect public calls |
| Things | Disposable TDs, affordances, transport and explicit ownership seam | Read a simulated Property |
| Metrics | Small saved panels, range/filter controls, freshness/loss markers | Ask about the visible measurements |
| Evidence | Dependency/spec/dataset/query digests, conformance outcomes and formal model scope | Inspect or export a bounded report |
| Documentation | Generated ecosystem guides, protocols, API reference, specifications and source provenance | Search or follow the documented public seam |

BeamLens appears as an “Ask about this run” composer and a collapsible answer
thread, not a full-screen chatbot gate. Answers link to the exact charts,
queries and evidence they used. Users can do every ordinary experiment and
inspection without an LLM. Prompt text never silently dispatches a Thing Action.
Custom dashboards are saved arrangements of admitted metric panels. PromEx
Grafana JSON exports are available; no automatic upload or mandatory Grafana
iframe is part of the default UI. LiveDashboard is trusted operator tooling,
not the public experiment workbench.

The implemented trusted-local slice binds the LiveView owner and revalidated
session room to one host-wide no-queue broker. It selects only the chosen run
and the nearest older run of the same experiment. Current snapshot references
link to the bounded evidence view. Admitted Explorer analysis emits an exact
same-origin query link and one fragment link per server-rendered chart; opening
one explicitly reruns only that bounded analysis against the already-owned run.
Model-output source references still are not converted into caller-selected
links. Disconnect, explicit cancel and deadline terminate the worker and clear
context.

## Component and chart contract

Required shared primitives: shell/sidebar, context header, button/icon button,
field/select, tabs, status badge, empty/error/loading state, accessible table
and data grid, panel, chart with table alternative, tooltip, dialog, menu and
progress. Required Wotex compositions: metric panel, tensor summary,
query/evidence link, prompt composer, answer/source block and explicit Action
approval form. All use semantic token roles, slots and documented attributes.
No caller HTML string injection, Tailwind/DaisyUI requirement, React runtime or
second client router is permitted.

The generic primitives and reporting components belong to Phoenix Assets and
are shared by HEEx, Svelte and Storybook. Wotex-specific policy, copy and
composition remain in the host. A component does not move upstream merely by
being given a generic name; it moves only when its props, events and behavior
make sense for an unrelated Phoenix Assets consumer.

Use bounded, renderer-neutral chart descriptors shared with the Livebook/Kino
lane. The server computes the admitted domain, marks, gaps, axes, legend,
provenance and table model. HEEx renders the native SVG and table fallback. A
registered Phoenix Assets reporting island may enhance that descriptor with
local hover, selection, comparison, zoom and pan while keeping the same labels,
gaps, units and evidence identity. The host ships no general chart grammar,
external data loader or arbitrary user-authored chart execution. Pin the
chart/island/LiveView compatibility cohort.

Explorer owns optional native dataframe analysis, not chart rendering or
telemetry storage. Series/range/mark controls are server-admitted and keyboard
accessible; changing a view cannot restart a run, alter its evidence or approve
an Action. Summary rows show observed and missing/nonfinite counts and retain
units and source/query identity. Livebook and LiveView consume the same bounded
analysis semantics without a required `kino_explorer` dependency.

Before island adoption, LiveView replaces the admitted server-owned SVG
atomically. After adoption, LiveView sends revisioned descriptor snapshots or
patches through PHA.02 and Svelte owns the enhanced chart subtree. Caller
`params`, signals, expressions and URLs remain forbidden. Local pan/zoom changes
only the viewport. Any operation that changes a query, dataset, evidence or
server selection returns to LiveView for admission.
Line/area/point marks preserve missing-value gaps. SVG includes axis labels,
ticks, legend, title/description and an explicit zero area baseline. Tables are
at most 100 rows and disclose truncation rather than embedding every point.

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

## LiveView and Svelte ownership

The Workbench uses one LiveView lifecycle with bounded Svelte islands, not a
LiveView page beside a Svelte single-page application. LiveView owns routes,
session and room identity, canonical assigns, server validation, evidence,
authorization and effectful commands. Svelte owns descendant DOM and local
presentation state inside one `PhoenixAssets.Svelte.Island` mount root.

Every island declares:

- a stable instance ID and registered component name;
- a closed public prop schema and event schema;
- generation and revision identity;
- snapshot, patch and event byte/depth/count limits;
- its HEEx semantic fallback;
- local state that may survive a reconnect;
- controls that require a connected server; and
- focus recovery and accessible-name behavior.

The outer boundary and semantic fallback remain LiveView-owned. Its inner mount
root uses the PHA.02 hook and ignored DOM contract. LiveView may update the
fallback and the mount root's transport `data-*` attributes. Svelte may update
only descendants of that mount root. The hook owns only PHA.02's preserved
readiness handoff attribute on the outer boundary. Any other page patch, island
update or browser enhancer that crosses those ownership lines is a defect.

The first accepted props are a complete finite snapshot. They arrive inline
when they fit PHA.02's attribute limit or through its connected bootstrap while
the fallback remains visible. Connected updates carry a full snapshot or a
patch tied to the exact base revision. Duplicate revisions are ignored. A
stale base, sequence gap, invalid operation, wrong instance or digest mismatch
retains the last valid display and requests one full snapshot. No partial
update is presented as current.

Client events are untrusted. The host rechecks the instance, browser session,
room, selected run/query, current revision, payload shape, deadline and
authorization before changing state. Effectful commands use opaque command IDs
and server deduplication. Disconnect never queues or replays a prompt
submission, export, mutation, approval or Action. A reconnected island disables
server-backed controls until it has accepted a fresh snapshot.

Props contain only the public projection needed to render the component. They
must not contain socket assigns, PIDs, functions, credentials, provider secrets,
policy internals, unrestricted structs, full tensors, GPU buffers or
unbounded telemetry. The browser bundle can reveal all Svelte branches and
copy; server-confidential conditional content must remain in HEEx or arrive
only after authorization.

The reference profile uses no Svelte server process. HEEx supplies the first
render and a patchable fallback beside the ignored mount root. The hook mounts
the manifested Svelte chunk in the browser, then changes the boundary readiness
state after a successful flush. A blocked chunk, invalid snapshot or mount
failure leaves the current fallback visible and the rest of the LiveView
usable. Hook destruction unmounts Svelte, restores fallback visibility and
releases every listener, timer, observer and subscription.

## Shared frontend system and Storybook

Phoenix Assets PHA.02 is the source for generic design tokens, CSS, icons,
component descriptors, Svelte components, HEEx primitives and story fixtures.
Its authored token file follows Design Tokens Community Group 2025.10. Wotex
adds semantic theme values through the documented override schema; it does not
copy component CSS or maintain a parallel Svelte implementation.

The Phoenix Assets Svelte Storybook is the public static component catalogue.
It imports the same Svelte modules and CSS chunks as the Workbench island
registry. Story transports are deterministic mocks for local, loading, success,
validation, error, stale, disconnected and reconnect states. They do not claim
server authorization, persistence, experiment execution or Action dispatch.

A separate Phoenix Storybook integration host exercises the HEEx wrapper,
semantic fallback, LiveComponent targets and real LiveView transport against
the same fixture IDs and digests. It is development and qualification tooling,
not a production dependency of the base library. Any online live catalogue is
isolated from production data and credentials, uses a supported patched
Phoenix Storybook release and has an explicit access decision.

Story coverage includes each applicable variant, size, state, theme, viewport,
keyboard sequence, focus recovery, reduced-motion outcome and failure mode.
Automated accessibility and visual checks are gates and review inputs; they do
not certify WCAG or accept a changed visual baseline automatically.

The Workbench asset build has one Vite owner and one manifest. It loads the
island runtime once and dynamically imports only registered component chunks
used on the route. Storybook manager assets, test mocks and catalogue-only code
must not enter the Workbench production bundle. CSS, runtime and component
families have compressed and uncompressed budgets. Production assets contain
no source map, remote runtime URL, runtime compiler or CDN dependency.

## Accessibility, lifecycle and security

Target WCAG 2.2 AA: keyboard-only operation, visible focus, semantic landmarks,
skip link, labeled controls, accessible names, reflow/zoom, contrast and reduced
motion. Status is conveyed in text, never color alone. Light/dark themes follow
system preference unless explicitly chosen. Charts have table/text alternatives.
Prompt output uses restrained live-region announcements, not token-by-token
screen-reader flooding. No hidden essential content on small screens.

Island mount and update preserve focus by stable semantic key. If the focused
control disappears, focus moves to the component's declared recovery target.
HEEx fallback and mounted Svelte content are never both exposed to assistive
technology. A mount does not move focus, announce duplicate content or reset a
user's unsubmitted local input. Interactive table semantics use the WAI-ARIA
grid pattern only when its full keyboard model is implemented; otherwise the
component remains a table with ordinary focusable controls.

LiveView starts no experiment merely by mounting/reconnecting. Start, cancel,
dataset export and simulated mutation have distinct server-admitted commands.
Authentication/instance scope is rechecked on mount and every event/query;
expired sessions revoke pending work. WLB.07's origin/CSRF/session/egress limits
apply. TD extensions, prompts, labels and model responses render as escaped
text. Use a restrictive CSP, local assets, body/event quotas and secure cookies.
Browser reconnect cannot replay an approval or repeat an Action.

Island component names come from a build-time registry. Props and events use
closed schemas and finite limits. The production build contains no runtime
Svelte compiler, `eval`, remote script, source map or arbitrary dynamic import.
Island telemetry identifies the component, phase and bounded reason without
recording props, prompts, credentials or user content.

Action approval names the exact disposable Thing, operation, input, proposal
digest, current revision and expiry. The server checks policy and freshness at
dispatch. “Run experiment” cannot also mean “approve this Action”. UI disabled
states are not authorization. ex_maude output appears as model-scoped evidence
with bounds/exhaustion/counterexamples, never a green physical-safety badge.

Acceptance includes browser tests for keyboard/theme/reflow, empty/denied/
stale/loading/failure states, multi-session isolation, reconnect/cancel/replay,
malicious TD/prompt content, bounded chart data, component/token overrides,
live query vs immutable dataset distinction, island mount/update/destroy,
stale-patch resynchronization, blocked assets, focus recovery, lifecycle leaks
and no-LLM operation. Token
contrast tests support this gate but do not prove whole-UI accessibility.

The base library's design-system surface remains Wotex theme tokens/CSS only.
The separate host selects Phoenix Assets, Vite, Svelte and LiveView. Neither
token tests, Storybook stories nor source-only component tests claim the
complete real-browser acceptance suite.

## Requirement catalogue

| ID | Requirement |
| --- | --- |
| WLB-S11-01 | Keep the base `wotex_lab` library independent from Phoenix, Vite, Svelte, Node and a browser while shipping immutable Wotex theme roles. |
| WLB-S11-02 | Use one LiveView application lifecycle and mount Svelte only through registered PHA.02 islands with exclusive descendant DOM ownership. |
| WLB-S11-03 | Keep session, room, authorization, canonical state, evidence and effectful commands on the server; expose only closed bounded browser projections. |
| WLB-S11-04 | Apply revisioned snapshots and patches, request full state after any gap or reconnect, and never replay an unacknowledged effectful command. |
| WLB-S11-05 | Compose one Phoenix Assets token/CSS/component system across HEEx, Svelte, DocShell and Storybook without a host component-style fork. |
| WLB-S11-06 | Render useful HEEx fallbacks and preserve the Workbench's admitted operation when an island, asset or LiveSocket is unavailable. |
| WLB-S11-07 | Enhance bounded charts and data controls without admitting arbitrary client programs, remote data, unbounded values or browser-owned evidence. |
| WLB-S11-08 | Build the production Svelte components as a static Storybook and test their real LiveView integration in a separate Phoenix Storybook host. Hosted publication follows the WLB.08 qualification runbook. |
| WLB-S11-09 | Meet the specified keyboard, focus, landmark, reflow, contrast, motion, theme, failure and disconnected-state behavior. |
| WLB-S11-10 | Ship one local content-hashed Vite graph with code splitting, bundle budgets, no production Storybook manager and no Node runtime process. |
| WLB-S11-11 | Preserve session isolation, reconnect safety, explicit Action approval, escaped untrusted content and restrictive browser policy across every island event. |
| WLB-S11-12 | Keep generic components upstream and Wotex domain policy/composition in the host, with executable boundary checks in both repositories. |

## Executable vectors

| ID | Evidence |
| --- | --- |
| WLB-V11-01 | A fresh base-library consumer compiles and runs its design-system API without Phoenix, Node, Vite, Svelte or browser assets. |
| WLB-V11-02 | The Workbench mounts, updates, navigates away from and destroys every island family repeatedly without duplicate instances or retained listeners, timers, observers or subscriptions. |
| WLB-V11-03 | Duplicate, stale, skipped, reordered, malformed, oversized and wrong-instance updates retain the last valid view and result in one full resynchronization. |
| WLB-V11-04 | Socket loss disables server-backed island commands; reconnect sends a full current snapshot and does not repeat a run, export, prompt, approval or Action. |
| WLB-V11-05 | Two sessions and two rooms cannot substitute island instance, revision, query, run, evidence or command identity. |
| WLB-V11-06 | Props and client events reject credentials, socket assigns, PIDs, functions, unrestricted structs, full tensors, unbounded telemetry and unknown fields before transport. |
| WLB-V11-07 | Enhanced charts preserve gaps, units, labels, evidence/query identity, accessible description and the bounded table fallback across themes and updates. |
| WLB-V11-08 | JavaScript-disabled, blocked-chunk, mount-failure and invalid-snapshot cohorts retain shell, fallback, ordinary navigation and every declared safe server action. |
| WLB-V11-09 | The static Storybook imports the same component chunks, CSS and fixture digests as the Workbench; mocks are visibly distinct from real server operation. |
| WLB-V11-10 | Phoenix Storybook and Workbench browser cohorts cover keyboard/pointer interaction, focus recovery, 320-pixel reflow, 400% zoom, themes, high contrast, reduced motion, loading/error/disconnected states and assistive-content handoff. |
| WLB-V11-11 | Production asset inspection finds one manifest, declared chunks within budget and no Storybook manager, source map, remote runtime URL, runtime compiler, arbitrary import or Node production process. |
| WLB-V11-12 | The clone-free Workbench artifact runs the three experiments, metrics, evidence, documentation entry and no-LLM flow with islands enabled and with their client chunks deliberately unavailable. |

## Completion boundary

The current HEEx host remains valid partial evidence. WLB.11 is complete only
when WLB-S11-01 through WLB-S11-12 and WLB-V11-01 through WLB-V11-12 pass
against pinned PHA.02 artifacts. Static Storybook publication is hosted
adoption evidence, not proof of LiveView transport. Phoenix Storybook and local
browser runs are source evidence until the tested host artifact and dependency
cohort are recorded under WLB.08. Publication and hosted adoption follow the
[qualification runbook](../plans/qualification.md).
