# WLB.11: Lean workbench and Lab design system

Specification version: 0.32.0. Contract: accepted. Implementation status:
partial. Evidence status: partial. Adoption status: reference_available.

Version 0.32 adds explicitly selected host-configured Modbus room profiles.
The session registry admits up to four closed IPv4 endpoint profiles and
exclusively leases each remote endpoint to one live room. Built-in loopback
rooms retain their existing defaults. Browser input selects only a configured
profile id; it cannot supply an address, module, credentials or executable.

## Configured Modbus room profile

The host's `room_profiles` option defaults to `[]`. Each list member is an
atom-keyed map containing exactly `id`, `title`, `host`, `port` and `unit_id`.
`id` is 1–32 ASCII lowercase letters, digits or hyphens, begins with a letter
and differs from the reserved `loopback` id. `title` is nonempty valid UTF-8
of at most 64 bytes without control characters. `host` is a four-element IPv4
tuple with octets 0–255, `port` is 1–65535 and `unit_id` is 1–247. Duplicate ids
or host/port pairs, unknown keys and malformed limits refuse host startup
before any transport or room starts. Endpoint selection is trusted host input;
classic Modbus TCP supplies no transport authentication or encryption.

Opening or verifying a browser session lists only ids/titles/availability and
starts no room or network activity. Explicit Start chooses a profile; an
unknown id or leased endpoint returns a typed error without acquiring a child.
Repeated Start for the same live session/profile returns its existing room;
changing profile requires the old room to end. Session expiry, revocation,
startup rollback or room death releases only that room's lease after its
transport actors have stopped. A stale DOWN
notification cannot release a replacement room's lease. Room-owned Lab
children are temporary and monitored: a failed child retires its room rather
than silently recreating state. The registry retains their exact identities
and reaps them even if the room dies without running its cleanup. Rooms monitor their
registry. The host supervises the registry before its Lab instance using
rest-for-one, so registry loss retires existing rooms before replacement
admission becomes reachable. Explicit End room atomically checks the view's
expected room identity, refuses stale replacement views, revokes pending local work,
confirms room cleanup and releases its lease; it performs no device reset.

A Modbus room owns the same three reference roles and graph as the default
room. Temperature reads two Input Registers at zero-based offset 0; power
reads two Input Registers at offset 2; target reads two Holding Registers at
offset 0. Values use the existing WMB float32 big-endian mapping and Cel/W
units. The explicit `setTarget` Action writes the target's two Holding
Registers through `writeMultipleHoldingRegisters`, bounded to 5–35 Cel.
These mappings describe this Lab reference profile, not a global device model.
Descriptions and presentation defaults come from backend seed ownership;
returned values come only from actual Runtime transport results.

Each room-owned transport actor monitors its room, delegates bounded requests
to the public Modbus transport with a maximum 1000 ms request timeout. Only
the owning room and its explicitly bound policy (Actions only) may call it.
It retains
only actual read receipts and operation counters, and closes with the room.
The standard transport owns and closes each TCP exchange. No observation or
Event capability, polling loop, automatic reconnect, command replay or cached
success is invented. A peer failure remains a typed operation error. Loss of a transport actor
during a mutating request reports unknown effect, never a confirmed refusal.
Repeated
explicit reads may open a fresh connection. Smart-room Runs retain the existing
separate exact-scope Action approval, cancellation and at-most-once dispatch.
The host projects the Modbus `:written` acknowledgement to the JSON string
`"written"` at its Continuum boundary. No physical effect is inferred from it.
Once a policy accepts a dispatch attempt, transport, record or readback failure
makes the Run terminally failed, with retained dispatch outcome and no confirmed
effect. It cannot expose approval or cancellation as if the attempt were still
pending, and cannot replay the Action.

WLB-V11-19 covers pure profile refusal, no-start listing, source selection,
exclusive leases and stale/dead room cleanup. An Elixir browser cohort boots
the independent PyModbus peer through Testcontainers, verifies actual reads,
separate approval and target readback, unavailable observation, reconnect/peer
loss and subsequent room release. The test peer stays outside production and
ordinary host startup. Native design and broader qualification remain partial.

Version 0.31.1 permits expression-bodied inline handlers in event attributes,
`on…` callback props and legacy `on:` directives. Calls, assignments, toggles
and async expressions remain expressions. A block-bodied handler must be a
named script function passed by reference; conditional and wrapper expressions
cannot conceal an inline block handler. The source gate and negative vectors
own this distinction. UI behavior, wire formats and command authority are unchanged.

Version 0.31 strengthens the frontend source contract through the
[frontend standard](../frontend-standard.md): named template handlers,
primitive composition, a 300-line Svelte limit, transitive load-time ordering
and spacing around types/imports/lifecycle groups. Biome 2.6.2 schema-verified
rules and GritQL plugins run alongside the Svelte/TypeScript AST gate; negative
vectors and actual-binary plugin probes run in the existing Lab CI lane.
Formatting runs only formatting and spacing. Platform constructor exemptions
are explicit and test classes remain subject to AST checks.

The canvas surface keeps its path and public props while its rune state moves
to a closure factory with reactive getters and setters for existing bindings.
Repeated grid/tab/filter rows own local handlers and domain controls compose
native primitives. The standalone Storybook loader preserves receiver and
lazy-loading behavior through arrow callbacks. UI data, events, command
authority and the generated control SDK API are unchanged. Native design and
artifact qualification remain partial.

Version 0.30 adds an executable frontend architecture contract. Base controls
own `assets/primitives/<name>/`; composed UI owns `assets/components/<name>/`;
both colocate stories. Tokens/styles/icons live in `assets/design-system/`.
The grid, chart and tabs islands delegate to shared Svelte components rather
than duplicate markup and keyboard behavior. Canvas tools and context menus
are reusable components. The remaining island adapters own only the transport
and their instance state.

Application functions use arrow syntax and consistent blank-line separation.
Protocol state and mounted-island controllers use explicit closure factories;
the LiveView adapter passes its receiver to callbacks as an argument. Markup
handlers reference a function or delegate one call. Internal source imports
use `$lib`/`$seeds` aliases and `.ts` extensions, resolved consistently by Vite,
Storybook, TypeScript and the Node unit runner. The runner requires Node 22.15
or newer. AST checks and negative tests enforce these rules. All production
Svelte components have colocated stories, including canvas nodes, pins,
controls, menus and missing-aware plots. New example data remains Mix-owned.

Menu navigation is scoped to its own enabled controls; Enter relies on native
button activation and fires once. Tab identities are instance-local. Grid
focus remains reachable when a refreshed table shrinks. Browser tests cover
the refactored components, disabled menu entries and exact activation counts.
Destroyed controllers refuse retained commands and ignore late snapshots or
patches. Concurrent initial snapshots mount one component; destruction during
chunk loading cannot mount a late component. Direct lifecycle tests cover
these boundaries without a browser timing delay.
Wire schemas, backend ownership and Action authority are unchanged. Wider
qualification and native Figma acceptance remain separate.

Version 0.29 adds the static Storybook build to the Workbench gate and its
rendered catalogue to the Elixir browser suite. Every published story is
rendered in light and dark themes and scanned by the installed accessibility
addon; component and island keyboard controls and empty-grid semantics have
browser regressions. Unreadable dark-theme controls, token-swatch text and
empty-grid ARIA structure are corrected. A no-JavaScript journey checks that
server-rendered Things remain readable and navigation performs no operations.
The current Lab CI lane installs Chromium explicitly and runs all Elixir
browser journeys after the source gate. This adds verification obligations;
island schemas, backend state, Action authority and production dependencies
are unchanged. Automated scans do not establish WCAG certification, complete
native Figma acceptance or published renderer adoption.

The frontend gate also audits the complete pnpm lock at every advisory
severity. Storybook and its framework/addon move together to 10.6.2, Vite to
8.3.3 and the transitive `source-map-js` to 1.2.2. No advisory is suppressed;
future matching records fail the gate. These are build/catalogue dependency
updates, not a new browser authority seam.

Version 0.28.0 retains session-measurement filters across refresh and freeze.
The query builder and session-measurement disclosures retain their browser
state through updates. Closing a
canvas inspector gives focus restoration one owner; the board-menu fallback
cannot schedule a competing delayed focus after the originating node or edge.
The completed capture receives a short status message and appears in the
Evidence dataset table with a direct capture download. Downloaded session reports retain the full rows and
their corrected content identity under WLB.10; no preview truncation or browser
sample values substitute for captured data. Elixir browser journeys cover
query/pin/saved restore, dataset/report downloads and explicit Action review,
cancellation and approval. They do not close full application qualification.

Version 0.27 centralizes reference-room, component and island-story sample definitions in
the host's `priv/seeds.exs`. Explicit `mix seed` generates deterministic JSON;
`mix seed --check` refuses missing or stale output without mutation. Neither
command starts the application, a room, an operation or an external service.
Room startup admits the bounded seed and its Thing Descriptions before starting
Things. Missing, malformed, duplicate, unsupported or oversized input refuses
startup without fallback data. The seed file is not evaluated at runtime.
Production browser islands receive server snapshots only; static Storybook
imports the generated example payloads. Sample Runs, observations, query results
and evidence are never generated by the browser or inferred from simulator
initial state. Existing session isolation, explicit room startup and command
authority are unchanged. Complete browser and archive qualification remain open.

Version 0.26 tightens the existing island protocol without adding fields or
commands. Canonical object keys sort by UTF-16 code units on both sides;
invalid UTF-8, unpaired browser surrogates and non-string/non-atom server keys
are refused. Mixed supplementary/BMP key sets therefore have corrected digests
and require a fresh snapshot from the matching server/browser build.

A server patch must advance exactly one revision, use closed add/remove/replace
operations and reproduce the declared next payload from its validated base.
Paths decode `~0` and `~1`; array indices are unsigned decimal without leading
zeros, and `-` is accepted only for a final append. Missing targets and unsafe
prototype segments are refused. The browser preserves its last valid state on
rejection, requests one full snapshot, rejects stale or contradictory full
snapshots and cannot commit a patch whose base changed during asynchronous
validation. Each Workbench LiveView mount and live catalogue component owns a
fresh, monotonically increasing decimal generation within its host VM. Normal
patches and resync retain it and the same declared capabilities; a remounted
view can reset revision only with its newer generation. A VM restart loses the
old in-memory session, so it cannot resume that instance identity. Shared
Elixir/browser vectors cover exact bytes, digests and escaped-path transitions. These checks do not close the remaining native-design,
complete accessibility or archive-adoption obligations.

Version 0.25 aligns compact reading typography and board spacing. The 38-pixel
board control uses equal 12-pixel side padding. A numeric reading and its unit
share one 24/28-pixel text group with the same size, weight and baseline. Thing
cards put state and retained receipt time in a compact footer and derive their
height from content. Property inspectors, Run results and Run pin values use
the same typography. These presentation
changes add no payload fields, observations, operations or authority.

Version 0.24 adds Search board to the board menu and Command/Control K.
The contextual drawer lists only the current bounded canvas projection and
session-owned pins: at most 32 subjects and sixteen pins. Case-insensitive
whitespace-separated terms must all match the subject title, identity or kind,
or a retained pin title, metric/source or Run identity. Queries are valid UTF-8
and at most 128 bytes; invalid queries retain the last accepted matches and show
an inline error. Results sort by lowercased title then stable identity.

Opening, filtering and selecting perform no Property read, history query,
provider request, Run or mutation. Selection revalidates ownership and opens
the existing Thing, process or pin inspector. Back restores the query and
matching result focus. Closing returns to the board control without moving
the canvas. Input ArrowDown/Up enters the results; result arrows wrap, Home/End
select their bounds and Enter opens the current subject. Search applies its
automatic focus once per mount, so delayed focus retries cannot take focus
back from a result during fast keyboard navigation. If a focused result is
removed by an authoritative update, focus returns to the search field. An empty board,
no matches and a disappeared result have distinct states. The ordinary input
remains available without the Svelte canvas; the keyboard shortcut is scoped
to the Workbench and leaves documentation search alone. This adds no island
wire fields or operations. Client-owned layout-profile markers survive the initial
LiveView mount and later patches without requiring another viewport resize.
Complete accessibility and native Figma alignment
remain separate acceptance work.

Version 0.23 adds captured Run result pins alongside the existing room-history
pins. Explicit Pin supplies the owned Run ID, exact record digest, chart index
0–7 and an optional closed Analysis query. The session resolves the current
Run and refuses stale digests, malformed queries and unavailable charts. The
capture retains the decoded outcome, original record, normalized query and
chart mark. Charts keep their admitted values and null gaps; only displayed
time uses the original Run's elapsed-seconds origin. Pinning recomputes bounded
presentation from the recorded Run and starts no Run, transport operation,
history query or provider request.

Run pins share the sixteen-slot board ceiling with history pins. Each capture
is at most 64 KiB and contains at most eight uniquely named series and 512
points in total; larger charts are refused without truncation. Identical Run,
record, index, normalized query and chart captures reuse one pin and retain
its renamed title and saved geometry. A changed capture has a distinct ID.
Run pins are immutable: Refresh, Pause and Resume are refused. Open run only
opens the stored contextual path. Removing or arranging a capture grants no
Action authority. Reload and documentation return restore the capture without
execution. Room death clears chart, outcome and record data; session expiry
or revocation discards the board.

Canvas `pins` is an additive union. Legacy metric records retain their exact
shape. A Run pin has exactly `kind` (`run`), `id`, `title`, `run_id`,
`record_digest`, `chart_index`, `source_mode`, `state`, `started_at`, `unit`,
`mark`, `outcome`, `series`, `x`, `y`, `width` and `height`. IDs use the node
identifier grammar; digest is `sha256:` plus 64 lowercase hexadecimal digits.
Title allows 128 UTF-8 bytes, source mode/state 64 and unit 32. Started time
is a UTC ISO 8601 string ending in `Z`, of at most 32 bytes. Mark is line, point or area.
Outcome is null after room death, or exactly label/value/unit/note (128 bytes
each except unit, 32). Series and geometry inherit the metric pin bounds,
except for the 512-point total ceiling. Both nested encoders admit this union.
The inert `pin_open_run` canvas event carries only an owned Run pin ID.
Captured Sources exposes the captured record and query; opening the current
Run does not replace that capture or claim that its state is still current.

Version 0.22 separates Run results from their contextual Data, Analysis, Run
details, Action review and Ask views. The closed optional `view` query accepts
`result`, `data`, `analysis`, `details`, `review` or `ask`; an absent value opens
the result, or Analysis for an existing exact-analysis link. A view change
performs no read, Run, export or approval. An explicit `analysis` query retains
its existing bounded analysis semantics. Unknown views and extra query fields
are refused without substituting another run. Sources remains scoped to the
selected run through the existing evidence route.

Results show the decoded outcome, compact facts and native SVG charts for
multi-point series, with their bounded table alternatives. Additional result
charts open in disclosures; single observations stay in the facts and Data.
The displayed time axis is elapsed seconds
from the earliest event in the original run; Data and Analysis preserve exact
event timestamps, values, masks, quality, dtype, shape and units. Missing values
remain gaps. Presentation transforms never replace recorded observations.
Review exposes the exact existing decision before its separate approval form;
opening it grants no authority. Back returns to the same result and canvas.
The existing five-second view refresh reads current owned Run status and
updates review expiry without replaying a command. Expired approval is
disabled in the presentation; the server still checks exact scope and expiry
at dispatch. Exact monotonic expiry remains available in decision details.

The existing JSON report endpoint additionally accepts the single `run` query
field. It selects only that run from the current verified session, includes
its record, proposal, decision and dispatch, and labels the report with a run
scope. Unrelated runs, session datasets, formal results and policy records are
excluded from this projection. The existing one-mebibyte ceiling applies.
Unknown runs receive 404, malformed query shapes receive 400, and session
refusals receive 403. The query-free session report retains its existing shape.
Export remains an explicit download and executes no experiment or Action.

Version 0.21 adds room-owned typed connection configuration for the reference
smart-room process. A canvas gesture prepares a draft; only explicit Apply or
Remove commits an admitted binding against its exact room revision. The next
explicit Run uses that binding. Neither configuration nor its projection opens
a transport, reads a Property, starts a subscription or dispatches an Action.

Version 0.20 adds explicit Property observation to existing reference rooms.
Observe and Pause are available only for declared capabilities. The room owns
an eight-child observation supervisor; each temporary runtime child monitors
its view receiver and bounds its delivery queue at 128 messages with stop on
overflow. Opening menus, mounting, reconnecting and returning from documentation
start no observation. Observe seeds a readable Property through an explicit
runtime read, then presents Waiting until a real subscription sample arrives.
Receipts become Stale after 15 seconds without a new sample; Pause and transport
loss retain the last value with their explicit state. A documentation snapshot
retains paused receipts and closes the view's observers. No worker or stream
reference enters that snapshot. The inspector puts Property values and controls
first, with Statistics and full identifiers/Forms in disclosures. Canvas nodes
use compact room labels and receipt times; Sources retains exact Thing IDs and
timestamps. Device event time and physical effects are not inferred.

Version 0.19 retains the current Workbench presentation for a documentation
round trip. The canvas supplies only admitted geometry and selection; the
server retains its own drafts, explicit readings and completed results. Return
restores presentation without executing another operation. The built reader's
visual alignment and complete application qualification remain incomplete.

Version 0.18 binds Ask to admitted room history and returns recorded charts
that can be pinned without re-querying or parsing model text. Draft questions
survive panel changes, completion and failure; no provider is needed for the
manual builder. Version 0.17 adds session-owned room-history pins and saved
canvas geometry.
The query builder uses the closed metric catalogue and existing history ranges.
Only an executed result with measured values can be pinned. Reload restores
the cached pin definitions and saved geometry, paused until explicit Resume.
The complete application qualification remains incomplete.

Version 0.16 adopts the grayscale canvas direction and adds the registered
`canvas` island. The initial source slice replaces the Thing card list with a
bounded Svelte Flow graph and contextual panels. A 38-pixel floating board menu
replaces the sidebar. `/` opens the canvas; `/experiments`, `/runs/:id`,
`/metrics` and `/evidence` patch the same LiveView and keep that canvas mounted.
Experiment drafts, explicit Thing readings and local canvas geometry survive
panel transitions. Run evidence binds its selected session-owned run and returns
to it. Complete metric composition, documentation restoration, live observation
subscriptions and complete browser journeys remain incomplete. No historical
evidence qualifies those additions.
DesignSystem 0.5 uses the supplied identity's grayscale roles, 4-pixel radii,
28-pixel controls and 12-pixel panel padding. Dark decorative borders use
`#444B5A`; focus and control-boundary roles remain distinct from them.

Version 0.15 adds editable brand identity and Lab page/flow deliverables under
the [design contract](../plans/brand-and-lab-design.md). The initial native
files are drafts. Their remaining design acceptance makes this expanded
specification partial without retracting the implemented host described below.
Existing package APIs, tokens, routes and effect boundaries do not change.

Version 0.15.2 renders tensor dimensions and integer-array previews as numeric
lists, including nested arrays whose integers happen to be printable character
codes. Existing preview limits, values, masks, quality codes and backend
ownership are unchanged.

Version 0.15.1 repairs experiment-form retention and numeric controls. Each
LiveView owns drafts for only the admitted experiments and parameters, with
UTF-8 string values of at most 32 bytes. Missing keys use catalogue defaults;
empty LiveView unused-field markers are accepted only beside their named
admitted parameter and are discarded before draft storage. Other unknown
fields are refused. Blank numeric values retain the existing default-admission
behavior. Editing revalidates the signed session and parameters without
allocating a room, extending command authority or starting a run. Malformed
snapshots cannot replace the retained draft. A submission rejected by parameter
admission keeps the bounded inputs,
links the offending field to its error and disables Run until corrected.
Unknown select values remain visibly unsupported, with no backend fallback.
Number controls expose the admitted bounds and integer/float steps. Theme and
board-menu updates preserve drafts; LiveView form recovery sends the inert change
event rather than Run. A fresh view starts with defaults until its browser
recovers the form. Only an explicitly submitted, re-admitted valid form can
allocate its room and run. The focused `experiment_forms_test.exs` host suite
covers refusal/correction, malformed input, replay, session/view isolation and
revocation. Existing public library and control-API parameter admission is
unchanged. Native design and broader browser acceptance remain partial.

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

The reference host now owns its Wotex tokens, CSS, HEEx components, Svelte
components, island transport and static Storybook. Phoenix Assets remains the
generic asset-build substrate and supplies no Lab product semantics. The
previous Workbench composition supplied a responsive sidebar shell, editorial
experiment cards, mobile dock and structured empty and error states. The
grayscale canvas edition below supersedes that visual direction. The public
documentation route adds a host-owned responsive reading composition around
the shared inert document renderer, including navigation, search, contents,
reading flow, code, tables and print behavior. Storybook adds a qualification
canvas that presents the same tokens and semantic fallbacks instead of relying
on the manager's default surface. Its single Vite graph
produces bounded, content-hashed Workbench and Storybook entries. The chart,
data-grid, tabs and canvas islands retain semantic HEEx fallbacks and use closed,
revisioned snapshots and events. A separate Phoenix Storybook host exercises
the real LiveView transport against the same registered components and fixture
identities. Focused browser cohorts cover lifecycle, malformed and stale
updates, reconnect resynchronization, command non-replay, fallback behavior,
keyboard operation, reflow, zoom, themes, contrast, reduced motion and asset
failure. Asset inspection rejects remote runtime dependencies, source maps,
runtime compilation and Storybook manager code in the production graph.

The existing host gate builds static Storybook, compiles with warnings as errors, formats, runs strict Credo,
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
normal `mix check` host gate and requires an operator-owned server plus an
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
browser-intensive components mount Svelte 5 through the Lab-owned island
adapter. Livebook/Kino remains the notebook experience; it is
complementary, not hidden inside a custom notebook editor.

The base `wotex_lab` library remains usable without Phoenix, a browser, PromEx,
GreptimeDB or an LLM. A non-umbrella reference host at `hosts/workbench/` owns
its Mix project, endpoint, explicit supervision and optional integrations. It
consumes Lab via artifact requirements and WLB.08's development switch, never
private modules. Its packaged source archive and OCI image provide clone-free
UI distribution. The implemented host remains separate from the base library;
no collection of mandatory new repositories is introduced.

The base library supplies `Wotex.Lab.DesignSystem.tokens/0`, `version/0`,
`contract/0` and `stylesheet/0`: immutable Wotex semantic theme roles,
deterministic identities and scoped CSS overrides, with no runtime filesystem
reads, network calls or global CSS reset. The Workbench host owns the concrete
HEEx and Svelte components, island hook, fixtures, Vite graph and Storybook.
Phoenix Assets owns only generic asset discovery, build and manifest behavior.
Consumers may
replace the reference host or override documented semantic roles without
changing a scenario, query or WoT contract.

## Interaction and visual language

Use the supplied unboxed mark and its grayscale palette. The light canvas is
`#F4F5F7`, with white surfaces and `#181D27` text. Dark uses `#181D27` canvas,
`#232936` surfaces, `#D6DBE3` text and subdued `#444B5A` decorative borders.
Contrast uses white surfaces and charcoal text and boundaries. Status always
has a text label. Use compact type, consistent 4-pixel corners, 28-pixel
single-line controls and subtle shared shadows on floating surfaces. Numeric
values and units, including `°C target`, align on a text baseline. Documentation
remains flat. Use local icons and the optimized repeating SVG graph-paper tile.

Workbench product surfaces begin with the current task and its authoritative
subject. They use these task archetypes before selecting a component or page
template:

- `inspect` for one run, Thing Description, query, evidence record or formal result;
- `compare` for bounded runs, series, contexts or evidence revisions;
- `act` for starting or cancelling a run, exporting data or approving one exact Action;
- `monitor` for freshness, loss, metrics, lifecycle and exception state; and
- `compose` for bounded experiment parameters, queries and investigation prompts.

Documentation remains an editorial reading surface and does not inherit the
Workbench shell or allocate a room. Cards are used only when a run, experiment,
Thing or evidence record is independently selectable or actionable. A dashboard
composition is limited to recurring metric monitoring or a decision that requires
several admitted measurements.

Product composition follows the width of the task container rather than a device
class:

| Profile | Task-container width | Composition |
| --- | --- | --- |
| compact | below 600 pixels | one task column with supporting evidence disclosed in semantic order |
| medium | 600 through 839 pixels | task plus selected supporting context |
| expanded | 840 pixels or wider | task and relevant evidence may remain visible together |

CSS container queries own these profiles. Viewport media queries remain limited to
environmental capabilities such as reduced motion, pointer precision and print.
A profile change preserves the selected experiment, run, Thing, Interaction
Affordance, query, evidence digest, revision, local draft, chart selection, focus
key, connected state, pending command identity and recovery path. It does not
submit, replay or approve an operation.

Compact composition cannot hide evidence identity, query scope, units, missing or
nonfinite values, freshness, authorization, Action approval scope, command outcome,
errors or reconnect recovery. Expanded composition may expose relevant context but
cannot add unrelated panels or change the authoritative subject.

The target shell is a persistent spatial workbench with at most two floating
menu surfaces: a 38-pixel board dropdown with equal 12-pixel side padding, and a
36-pixel icon rail. Search, viewport controls and documentation live in
submenus. Inspectors, configuration and results open in context with 20-pixel
canvas-edge insets. Closing them preserves geometry, selection and viewport.
Evidence belongs to the selected subject rather than a persistent primary
navigation item. Documentation opens the inert WLB.12 route without allocating
a room. The source shell has the board menu and one Select/Pan/Add/Metrics/
Experiments/Fit rail. Experiment selection, results and reports use contextual
panels; Metrics offers room-scoped Ask results, the query builder and metric
pins. Below 600 pixels the inspector clears the board control
with a 76-pixel top inset; its other canvas-edge insets remain 20 pixels.

| View | Main content | Primary action |
| --- | --- | --- |
| Workbench (`/`) | Owned Things and typed topology, current readings and process state | Start a room or select a subject |
| Experiments (`/experiments`) | Selected admitted experiment, retained parameters and source disclosure | Run an admitted experiment |
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

## Editable identity, pages and flows

Deliver a separate WoTEx brand identity file and a Lab Workbench file in Figma.
The [design contract](../plans/brand-and-lab-design.md) owns their inventory,
native links, source authority and acceptance. Brand guidelines include selected
artwork, colours, typography, voice, layout, applications and an asset handoff.
Proposed artwork and rules remain distinguishable from approved identity.

The Workbench file contains shared native foundations/components, canonical
designs for Experiments, Run workspace, Things, Metrics, Evidence and
Documentation, and goal-based task flows with adjacent briefs. Maintain actual
prototype connections for ordinary continuation, back, cancel, explicit Action
approval, failure, expiry and reconnect recovery. Cover all three task-container
profiles and source theme roles. Numerical results remain inert and transport
completion does not prove a physical effect.

Keep source identities and hashes outside visible product flows. Preserve
native IDs and designer-owned proposals during reconciliation. Inspect editable
layers, variables, component links and representative renders; execute the
named journeys in native Play. Retain native archives and independently verify
restoration before claiming recoverable handoff. Static presence, source tests
and a wired reaction graph do not establish native interaction acceptance.

## Component and chart contract

Required shared primitives: shell/board menu, context header, button/icon button,
field/select, tabs, status badge, empty/error/loading state, accessible table
and data grid, panel, chart with table alternative, tooltip, dialog, menu and
progress. Required Wotex compositions: metric panel, tensor summary,
query/evidence link, prompt composer, answer/source block and explicit Action
approval form. All use semantic token roles, slots and documented attributes.
No caller HTML string injection, Tailwind/DaisyUI requirement, React runtime or
second client router is permitted.

The primitives and reporting components belong to the Lab reference host and
are shared by HEEx, Svelte and Storybook. Wotex policy, copy, presentation and
composition stay together. A component does not move to Phoenix Assets merely
because it has a generic name; the substrate remains UI-free.

Use bounded, renderer-neutral chart descriptors shared with the Livebook/Kino
lane. The server computes the admitted domain, marks, gaps, axes, legend,
provenance and table model. HEEx renders the native SVG and table fallback. A
registered Lab reporting island may enhance that descriptor with
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
patches through the Lab island protocol and Svelte owns the enhanced chart subtree. Caller
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
counts as preview-element counts. Shapes and integer-array cells render as
numeric lists rather than inferred character strings. `tensor_window_test.exs`
checks a twelve-row, nine-feature integer batch through encoded values, masks,
quality and rendered metadata. It also traces every
`Nx.to_list/1` call over a 250-row, 40-feature, 64-element fixture and requires
only 100×32 tensors to cross that boundary. Min/max downsampling uses gap
sentinels before/between/after retained extrema, preserves input order and
cannot draw across an omitted missing span. Missing spans may coalesce;
interval means input points per bucket. A requested downsampling budget below
five is refused when truncation is needed, rather than dropping an extremum
or gap to claim success. The fixed normal budget remains 2,000.

## LiveView and Svelte ownership

The `canvas` public props are `label` (UTF-8, at most 256 bytes), `nodes` (at
most 32) and `edges` (at most 64). Each node requires exactly `id`, `kind`, `title`,
`identity`, `value`, `unit`, `status`, `detail`, `x` and `y`, with an optional
`operations` list. That list contains at most three unique `read`, `observe` or
`pause` entries and defaults to empty; other node fields remain closed. IDs are unique
1–128-byte ASCII identifiers using letters, digits, `.`, `_`, `:` and `-`,
starting with a letter or digit. Kinds are `thing`, `process` or `entry`.
Title, value and detail allow 128 UTF-8 bytes; identity allows 256, unit and
status 32. Coordinates are finite and within ±20,000. Each edge has exactly
`id`, `source`, `target`, `label`, `kind` and `target_handle`: unique identifier,
existing node endpoints, a 128-byte label, `input` or `proposal`, and
`temperature`, `power` or `input`, respectively. Both encoders validate the
nested records, identities, bounds and references before rendering.

Canvas `inspect` carries only `id` and is inert. The host revalidates the signed
session, island instance, exact revision and membership in the current graph.
Right-click and ellipsis open the same menu; the HEEx fallback offers labelled
inspection buttons. Local node movement, pan, zoom, selection and fit cannot
change wiring, select a Form, allocate a room or authorize an Action. A handle
gesture opens the connection draft described below without adding an edge. Reconnect
requires a current full snapshot before inspection is enabled and retains local
geometry. Only explicit Property read or observation receipts populate values;
simulator state is not an observation. The timestamp is the host receipt time,
not a device event time. Registered Directory entries stay inert and use stable
identities. The graph describes admitted experiment wiring.

Canvas `read`, `observe` and `pause` carry only the current node `id`; the server
resolves its represented Property and revalidates the session, room, revision,
node membership and declared capability. A temporary observer is owned by the
room's bounded supervisor and its current view receiver. Pause requests exact
runtime unsubscription; receiver or room death stops it. Stream loss, invalid
samples and queue overflow preserve the last receipt with an unavailable state
and require explicit Observe to restart. Numeric reference samples are bounded
to ±1e100 before they enter view state. Multiple Properties retain separate
receipts; reading one cannot replace a different Property on the canvas.
Canvas `statistics` and `sources` carry only `id`, open the same inspector at
its corresponding disclosure and execute no Property or Action operation.
Documentation retains paused receipts without replaying or restarting a stream.

### Typed reference connections

The room owns three process ports: `temperature` accepts one readable scalar
number or integer Property with exact unit `Cel`; `power` accepts the same
with unit `W`; `proposal` targets only the room policy's admitted Actuator
`setTarget` Action. Property eligibility requires an actual read Form. An inert
Directory entry, unknown Thing, incompatible DataSchema or unit, unsupported
Action and undeclared operation are refused. No implicit unit conversion or
transport admission is performed. The initial bindings preserve the existing
Thermostat temperature, Energy meter power and Actuator proposal path.

Canvas `inspect_connection` carries only a known port `id`. Canvas
`propose_connection` carries exactly `connection`, whose closed fields are
`source`, `target` and `target_handle`: bounded current node identifiers and
one declared process/Actuator handle. Both events revalidate session, island
revision, room membership and endpoint direction and perform no mutation. The
Connect tool and non-spatial connection list reach the same labelled editor.

Apply submits exactly `port`, `thing`, `affordance` and a canonical decimal
`revision`; Remove submits the port and revision. The room serializes changes,
compares its own connection revision, revalidates the selected affordance and
increments the revision only for a changed binding. Stale or malformed drafts
and cross-room identities cannot overwrite current configuration. The draft
and its error remain available for explicit reload or correction. A pending
Action decision must be cancelled or resolved before a binding can change.
Configuration advances the room's state revision without granting authority.

The next explicit smart-room Run resolves all required bindings before any
Property read. Temperature and proposal are required; power is required only
when its existing meter option is enabled. Numerical feature order remains
temperature then power, with exact selected Thing/affordance identity, units,
and the existing missing-power fill/mask. The immutable run records the binding
revision as a scalar outcome and exact endpoints as ordered `connection:` input
references containing port, Thing ID, affordance kind/name and unit. The existing separate Action review, expiry,
deduplication and policy dispatch remain authoritative.

Applied connections survive tool patches, reload and documentation return in
their owning room. An uncommitted bounded draft may survive documentation;
restoration never applies it or restores authority. Empty-room authoring starts
no room. Closing, cancelling, dragging, reconnecting and saved-layout restore
perform no connection change. Edge labels may project an exact cached source
Property receipt; unavailable data is never replaced with zero.

Canvas `open` also carries only `id`. The host admits exactly `add`, `connections`,
`metrics` or `experiments` after verifying the signed session, instance and revision. It
only patches to a contextual panel; it never allocates a room, reads a Property,
queries metric history or runs an experiment. Inspecting the admitted smart-room
process opens its configuration. The canvas mount identity remains stable across
Workbench patches. Invalid/stale events cannot change the selected subject;
revoked sessions remove the canvas. Documentation belongs to a separate LiveView.

### Ask and recorded metric results

Metrics leads with one bounded question and an explicit Ask action. Build query
is the alternate path, open when a provider is unavailable or no room exists.
An unavailable provider disables Ask while keeping the draft editable. Editing
or reopening a tool starts no room, model request or query. The server retains
valid UTF-8 questions of at most 512 characters / 4 KiB across panel patches,
completion and failure. Duplicate submission during a running request leaves
that request intact; navigation cancels it and ignores a late completion.

The already-admitted room supplies metric scope to the broker (WLB.10).
Metrics can ask without a prior run; run/evidence tools still require their
selected run. Completed answers show the exact server-retained charts received
through the room metric callback, with compact plots, source/window/unit/query
disclosures and Pin to workbench. Recorded evidence links resolve only to the
corresponding same-page chart. Pin supplies a closed 0–7 result index, verifies
session and room again and retains that result without re-querying or parsing
model text. A revoked session immediately shows the denied shell and drops its
private presentation. The no-provider manual builder remains fully usable.

### Metric pins and layout

Canvas additionally accepts optional `pins` (at most 16), `view` (zero or one
viewport) and decimal-string `layout_revision` (at most 32 bytes). A metric pin has
exactly `id`, `title`, `metric`, `source`, `range`, `unit`, `aggregation`, `state`, `auto_refresh`,
`end_ms`, `series`, `x`, `y`, `width` and `height`. ID and metric use the node
identifier grammar; title allows 128 UTF-8 bytes, source/aggregation/state 64,
and unit 32. The range is `5m`, `15m` or `1h`. `end_ms` is a safe integer UTC
range endpoint. `auto_refresh` is a boolean; the context menu uses it independently
of cached/unavailable status text. Pin coordinates use the node bounds; width is 300–800 pixels
and height 200–600. Each of at most eight uniquely named series has exactly
`name` (128 UTF-8 bytes) and `points` (at most 61 `[x, y]` pairs). Coordinates
are finite within ±10^100; only y may be null. Pin IDs and node IDs cannot
collide. The viewport has exactly x/y (finite within ±100,000) and zoom
(0.25–2). Both encoders validate these nested records.

The host's builder queries one catalogue metric and one inherited history range
on explicit Query. It fixes room scope and type-appropriate aggregation through
`HistoryPanels`; browser data cannot supply scope, chart values or expressions.
Pin retains the validated definition, result, query digests and data window.
No samples disables Pin. A failed refresh keeps the previous timestamped chart
with an unavailable indication. Dotted bridges annotate interior missing
intervals between measured endpoints; they introduce no zero or numeric
interpolation. All-missing series remain unavailable.

Canvas events `pin_refresh`, `pin_pause`, `pin_resume` and `pin_remove` carry
only an existing owned pin ID. `save_layout` carries only `layout`, containing
exactly `positions` and `viewport`. At most 48 unique positions may name current
nodes/pins; each has id/x/y and may include pin width/height together. Unknown
identities, fields or bounds are refused without replacing the saved layout.
These are presentation/read operations and convey no Action authority.

Pin and Resume opt the connected workbench into local-history refresh. One
owner task at a time shares a 1.5-second budget across at most sixteen pin
definitions; a five-second tick rotates range priority. Signed-session and room
identity are checked before starting and before applying its result. Automatic
refresh does not extend the session TTL. Pause prevents later refreshes; an
already-running read may finish. Removing a pin cannot be undone by a late
result. No timer starts a model request, collector, database connection or
Action. Reopening/reloading restores cached pins paused. Room death discards
cached observations; expiry/revocation discards the session board.

Saved geometry and canonical pin definitions belong to the bounded signed
session. Save retains node/pin positions, pin sizes and viewport for later
mounts in that session; it is not a frozen dataset or an authorization grant.
The separate documentation LiveView remains public and inert. Opening Docs
from the board first retains one presentation snapshot in the existing signed
session, without extending its TTL or changing Save layout. The canvas event
`open_documentation` carries exactly `view`, containing `layout` and `selection`.
Layout obeys the same current-identity and geometry bounds as `save_layout`;
selection is empty or one current node/pin ID. Optional canvas `selection`
presentation names only a current graph subject. The server validates the
current session, room and island revision before retaining anything.

The server supplies the originating Workbench route, bounded experiment forms,
explicit readings, metric draft, question and completed answer/chart results.
The snapshot admits only its closed fields, at most three experiment forms,
31 readings and eight investigation charts, with a 256 KiB term/JSON budget
and depth 24. Opaque process, function, port and reference values are refused.
The snapshot contains no worker, command, approval or active refresh owner.
Running investigations are cancelled only after retention succeeds. A failed
capture keeps the workbench open; it never silently navigates away.

Public documentation verifies an existing token only to choose the local
Return destination; it allocates no session or room. The unavailable state
uses that target; the built reader host controls and visual composition still
need their source-alignment pass. A Workbench HTTP mount
reads the snapshot, and its connected mount consumes it once. It restores
unsaved geometry separately from the saved layout, including viewport, pin
sizes and selected subject. Explicit readings and invalid experiment values
retain their original meaning. Completed results remain cached and pins stay
paused. No restoration reads a Property, queries history, reruns an experiment,
asks a provider or sends an Action. Room death discards the retained snapshot;
expiry/revocation discards the entire session. Without the canvas enhancement,
the ordinary LiveView Docs action retains server presentation and its last
available geometry. Modified-click links retain ordinary browser behavior.

The Workbench uses one LiveView lifecycle with bounded Svelte islands, not a
LiveView page beside a Svelte single-page application. LiveView owns routes,
session and room identity, canonical assigns, server validation, evidence,
authorization and effectful commands. Svelte owns descendant DOM and local
presentation state inside one `WotexLabWorkbenchWeb.Islands` mount root.

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
root uses the `WotexLabSvelteIsland` hook and ignored DOM contract. LiveView may update the
fallback and the mount root's transport `data-*` attributes. Svelte may update
only descendants of that mount root. The hook owns only the Lab protocol's preserved
readiness handoff attribute on the outer boundary. Any other page patch, island
update or browser enhancer that crosses those ownership lines is a defect.

The first accepted props are a complete finite snapshot. They arrive inline
when they fit the Lab protocol's attribute limit or through its connected bootstrap while
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

## Lab frontend system and Storybook

Wotex Lab is the source for its design tokens, CSS, icons, component
descriptors, Svelte components, HEEx primitives and story fixtures. The base
library publishes the renderer-neutral token and island contracts; the
Workbench owns browser code and concrete presentation. Its semantic token
catalogue follows Design Tokens Community Group 2025.10.

The Wotex Lab Svelte Storybook is the public static component catalogue.
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

Task fixtures reuse one closed snapshot and local-state envelope across compact,
medium and expanded compositions. Boundary pairs at 599/600 pixels and 839/840
pixels verify the selected subject and revision, local draft and selection, focus
key, connected state, pending command identity, fallback state and recovery path.
The fixture set includes loading, empty, denied, stale, disconnected, reconnecting,
validation failure and unknown command outcome.

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
The canvas retains the originating node control, edge or tool while a
contextual inspector is open. Closing or escaping a tool returns focus there
after the navigation patch and canvas update complete.
If that object is removed or lies outside the visible canvas, focus returns to
Connections; when that tool is unavailable, the board menu is the fallback.
Deep links with no local origin also use the board menu. Recovery does not pan
the board. Context menus support Shift+F10, arrows, Home/End and Escape; Tab
closes the menu and continues from its originating control.
Connection Back, Cancel, Apply and Remove return to the matching connection
row. Reload draft returns to the source field. Back and Close retain an
uncommitted draft; Cancel discards it. These local focus targets carry no
configuration or operation authority. Complete screen-reader, reconnect and
cross-profile qualification remains separate from this bounded source journey.
The Remove button admits LiveView's empty transport `value` field only beside
the exact port/revision pair. Nonempty values and additional operation fields
remain invalid; room ownership and revision checks still apply.
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

The base library's design-system surface remains Wotex theme tokens, bounded
island envelopes and CSS only. The separate host selects Phoenix Assets, Vite,
Svelte and LiveView. Neither
token tests, Storybook stories nor source-only component tests claim the
complete real-browser acceptance suite.

Workbench end-to-end journeys are Elixir ExUnit tests under
`hosts/workbench/test/e2e/`, driven through a real browser by test-only
PhoenixTest.Playwright. `WOTEX_LAB_E2E=1` explicitly enables the disposable
loopback endpoint and browser supervisor. Ordinary host tests exclude this
lane; frontend asset tests remain unit tests. Connection coverage includes
origin and row focus, retained drafts, native Remove, concurrent revision
conflicts, edge replacement and the 599/600, 839/840 and 320-pixel profiles.
The suite also renders every static Storybook story in light and dark themes,
requires no accessibility-addon violations, exercises component/island keyboard
controls and verifies no-JavaScript server fallbacks without replay. Build both
the Workbench assets and Storybook before invoking it. The normal host gate
builds both; the current Lab CI lane explicitly enables the browser suite.
This bounded suite does not close the wider acceptance matrix above.

## Requirement catalogue

| ID | Requirement |
| --- | --- |
| WLB-S11-01 | Keep the base `wotex_lab` library independent from Phoenix, Vite, Svelte, Node and a browser while shipping immutable Wotex theme roles. |
| WLB-S11-02 | Use one LiveView application lifecycle and mount Svelte only through registered Lab islands with exclusive descendant DOM ownership. |
| WLB-S11-03 | Keep session, room, authorization, canonical state, evidence and effectful commands on the server; expose only closed bounded browser projections. |
| WLB-S11-04 | Apply revisioned snapshots and patches, request full state after any gap or reconnect, and never replay an unacknowledged effectful command. |
| WLB-S11-05 | Compose one Lab-owned token, CSS and component system across HEEx, Svelte, DocShell composition and Storybook without delegating product UI to the asset substrate. |
| WLB-S11-06 | Render useful HEEx fallbacks and preserve the Workbench's admitted operation when an island, asset or LiveSocket is unavailable. |
| WLB-S11-07 | Enhance bounded charts and data controls without admitting arbitrary client programs, remote data, unbounded values or browser-owned evidence. |
| WLB-S11-08 | Audit the complete frontend dependency lock, build the production Svelte components as a static Storybook and test their real LiveView integration in a separate Phoenix Storybook host. Hosted publication follows the WLB.08 qualification runbook. |
| WLB-S11-09 | Meet the specified keyboard, focus, landmark, reflow, contrast, motion, theme, failure and disconnected-state behavior. |
| WLB-S11-10 | Ship one local content-hashed Vite graph with code splitting, bundle budgets, no production Storybook manager and no Node runtime process. |
| WLB-S11-11 | Preserve session isolation, reconnect safety, explicit Action approval, escaped untrusted content and restrictive browser policy across every island event. |
| WLB-S11-12 | Keep Phoenix Assets UI-free and keep Wotex component behavior, domain policy and composition in Lab, with executable boundary checks in both repositories. |
| WLB-S11-13 | Select a task archetype and content-container profile without creating device-specific state, routes or command behavior. |
| WLB-S11-14 | Preserve the authoritative subject, revision, local input, focus, command identity and recovery across composition changes while retaining required evidence and Action scope in compact composition. |
| WLB-S11-15 | Deliver the separate editable WoTEx brand identity and approved asset handoff defined by WLB-C15, preserving the distinction between source values, proposals and accepted identity. |
| WLB-S11-16 | Deliver the editable Lab page/state/profile inventory and connected task flows defined by WLB-C16, with source-aligned components, adjacent briefs and explicit approval/recovery boundaries. |
| WLB-S11-17 | Author reference-room, component and island-story sample data in the backend Mix seed source; validate generated room input, reject stale generated outputs, and exclude Storybook sample payloads from production browser code. |
| WLB-S11-18 | Use typed Svelte 5 runes, arrow functions and closure controllers, expression-bodied inline handlers or named script handlers for block bodies, primitive composition, bounded components, transitive load ordering, consistent spacing and alias-based `.ts` imports. Colocate every primitive/composed component with its stories and keep island adapters thin. Enforce the source contract in the frontend gate. |
| WLB-S11-19 | Admit host-configured Modbus room profiles with explicit browser selection, exclusive endpoint custody, real Runtime exchanges and unchanged Action approval; no fabricated observations or frontend seed values. |

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
| WLB-V11-09 | The static Storybook imports the same component chunks, CSS and fixture digests as the Workbench; mocks are visibly distinct from real server operation. Every emitted story renders in light and dark themes without accessibility-addon violations; the full frontend lock audit passes without suppressed advisories. |
| WLB-V11-10 | Phoenix Storybook and Workbench browser cohorts cover keyboard/pointer interaction, focus recovery, 320-pixel reflow, 400% zoom, themes, high contrast, reduced motion, loading/error/disconnected states and assistive-content handoff. |
| WLB-V11-11 | Production asset inspection finds one manifest, declared chunks within budget and no Storybook manager, source map, remote runtime URL, runtime compiler, arbitrary import or Node production process. |
| WLB-V11-12 | The clone-free Workbench artifact runs the three experiments, metrics, evidence, documentation entry and no-LLM flow with islands enabled and with their client chunks deliberately unavailable. |
| WLB-V11-13 | HEEx, Svelte and Storybook render the same task fixture at 599/600-pixel and 839/840-pixel task-container boundary pairs without changing its closed snapshot or emitting a command. |
| WLB-V11-14 | Keyboard-only, screen-reader, reduced-motion and coarse-pointer journeys preserve selection, focus, drafts, evidence identity, pending-command state and reconnect recovery in every profile. |
| WLB-V11-15 | Inspect the native brand file, source-exact assets/tokens, default/inverse instances and destination exports; verify accepted rules and independently restore the archived native artwork and dependencies. |
| WLB-V11-16 | Inspect native Lab components and all required page/state/profile mappings, execute named Play journeys including back/cancel/expiry/reconnect, compare with the pinned source and independently restore the native prototype and component links. |
| WLB-V11-17 | Repeated Mix seeding produces identical bytes without allocating browser state; check-only detects missing or stale output without writes; room admission rejects malformed, duplicate and oversized seeds; a fresh browser renders no Things, readings, Runs, pins or evidence before explicit backend operations. |
| WLB-V11-18 | AST and installed-Biome vectors accept arrows, accessors, aliases, expression-bodied inline handlers and named Svelte handlers and reject classes outside the documented platform exemptions, function/method declarations, `.js`/relative imports, inline block handlers, raw domain controls, oversized components, eager forward calls and missing spacing. Every production component has colocated rendered stories; callback-context isolation, enabled-menu navigation and single native activation pass unit/browser regressions. |
| WLB-V11-19 | Configured room profiles pass malformed/duplicate/unknown/busy and owner-loss vectors; the independent container peer drives an Elixir browser journey through graph inspection, read, approved Run dispatch, target readback and failure/release without replay. |

## Completion boundary

WLB-S11-01 through WLB-S11-12 and WLB-V11-01 through WLB-V11-12 have local
source or candidate-artifact evidence against the Lab-owned frontend cohort. Static
Storybook publication is hosted adoption evidence, not proof of LiveView
transport. The Phoenix Storybook and local browser runs establish the source
contract but do not claim WCAG certification. Publication and broader hosted
adoption remain separate qualification work under the
[qualification runbook](../plans/qualification.md).

WLB-S11-13, WLB-S11-14, WLB-V11-13 and WLB-V11-14 are accepted obligations
without recorded executable evidence. They keep WLB.11 evidence partial until the
container-profile implementation and boundary-pair cohorts pass.

WLB-S11-15, WLB-S11-16, WLB-V11-15 and WLB-V11-16 add design acceptance.
The initial editable files and representative render inspection are recorded
in the design contract. Complete native coverage, Play, accepted identity and
archive/restore evidence remain open. These obligations keep implementation
and evidence partial; historical host evidence is not promoted to cover them.
